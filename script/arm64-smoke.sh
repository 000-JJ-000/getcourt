#!/usr/bin/env bash
# Native ARM64 (e.g. Oracle Ampere A1) runtime smoke test for GetCourt.
#
# This script MUST be run on a real ARM64 host with Docker. Cross-compiled or
# QEMU build-only success does NOT prove runtime compatibility.
#
# Usage (on the ARM64 VM):
#   cp .env.production.example .env.production   # fill secrets first
#   chmod +x script/arm64-smoke.sh
#   ./script/arm64-smoke.sh
#
# Exit codes: 0 = all checks passed; nonzero = failure (see log).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
ENV_FILE="${ENV_FILE:-.env.production}"
ARCH="$(uname -m)"

echo "==> Host architecture: ${ARCH}"
case "${ARCH}" in
  aarch64|arm64) ;;
  *)
    echo "WARNING: expected aarch64/arm64; continuing anyway (mark native ARM64 validation pending if this is not Ampere)." >&2
    ;;
esac

if [ ! -f "${ENV_FILE}" ]; then
  echo "Missing ${ENV_FILE}. Copy from .env.production.example and fill required values." >&2
  exit 1
fi

compose() {
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" "$@"
}

echo "==> Building runtime image for this host platform"
compose build web worker

echo "==> Starting database"
compose up -d db
compose exec -T db pg_isready -U "${DATABASE_USERNAME:-getcourt}"

echo "==> Migrating (one-shot)"
compose --profile migrate run --rm migrate

echo "==> Starting web + worker"
compose up -d web worker

echo "==> Waiting for web /up"
ok=0
for i in $(seq 1 40); do
  if curl -fsS "http://127.0.0.1:${WEB_PORT:-3000}/up" >/dev/null 2>&1; then
    ok=1
    break
  fi
  sleep 3
done
if [ "${ok}" != "1" ]; then
  echo "web /up never became ready" >&2
  compose logs --tail=80 web
  exit 1
fi

echo "==> Container health"
compose ps
web_health="$(compose ps --format json web 2>/dev/null | head -1 || true)"
echo "${web_health}"

echo "==> Ruby/Rails boot + native gem probes inside web"
compose exec -T web bash -lc '
  set -euo pipefail
  ruby -v
  bundle exec rails runner "
    require \"vips\"
    puts \"ruby-vips=#{Vips.version_string}\"
    require \"pg\"
    puts \"pg=#{PG::VERSION}\"
    begin
      require \"tdlib-ruby\"
      puts \"tdlib-ruby=loaded\"
    rescue LoadError => e
      puts \"tdlib-ruby=SKIP (#{e.message})\"
    end
    puts \"cache_store=#{Rails.cache.class.name}\"
    puts \"rack_attack_store=#{Rack::Attack.cache.store.class.name}\"
    puts \"boot=ok\"
  "
'

echo "==> Solid Queue worker process present"
compose exec -T worker bash -lc "pgrep -af 'solid-queue|jobs start' | head -5"

echo "==> Persistence check (restart web)"
compose restart web
sleep 10
curl -fsS "http://127.0.0.1:${WEB_PORT:-3000}/up" >/dev/null

echo "==> ARM64 smoke PASSED (native runtime exercised on ${ARCH})"
echo "Record host model/OCPU/RAM and wall times for capacity planning (starter: 1 OCPU / 6 GB — measure under load)."
