#!/usr/bin/env bash
# Backup all four GetCourt logical databases from a running Postgres container.
# Writes custom-format dumps under BACKUP_DIR/<utc-stamp>/.
#
# Usage:
#   BACKUP_DIR=./backups COMPOSE_FILE=docker-compose.prod.yml ENV_FILE=.env.production \
#     ./script/backup-postgres.sh
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
ENV_FILE="${ENV_FILE:-.env.production}"
DB_SERVICE="${DB_SERVICE:-db}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="${BACKUP_DIR}/${STAMP}"
REMOTE_DIR="/tmp/getcourt-backup-${STAMP}"

mkdir -p "${OUT_DIR}"

if [ -f "${ENV_FILE}" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${ENV_FILE}"
  set +a
fi

: "${DATABASE_USERNAME:?DATABASE_USERNAME required}"
: "${DATABASE_PASSWORD:?DATABASE_PASSWORD required}"
: "${DATABASE_NAME:?DATABASE_NAME required}"
: "${DATABASE_CACHE_NAME:?DATABASE_CACHE_NAME required}"
: "${DATABASE_QUEUE_NAME:?DATABASE_QUEUE_NAME required}"
: "${DATABASE_CABLE_NAME:?DATABASE_CABLE_NAME required}"

compose() {
  # COMPOSE_PROJECT_NAME is honored when set (e.g. disposable restore drills).
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" "$@"
}

echo "Creating dumps inside ${DB_SERVICE}:${REMOTE_DIR}"
compose exec -T -e PGPASSWORD="${DATABASE_PASSWORD}" "${DB_SERVICE}" bash -lc "
  set -euo pipefail
  mkdir -p '${REMOTE_DIR}'
  for db in '${DATABASE_NAME}' '${DATABASE_CACHE_NAME}' '${DATABASE_QUEUE_NAME}' '${DATABASE_CABLE_NAME}'; do
    echo \"Dumping \${db}...\"
    pg_dump -U '${DATABASE_USERNAME}' -d \"\${db}\" -Fc --no-owner --no-acl -f \"${REMOTE_DIR}/\${db}.dump\"
  done
  ls -la '${REMOTE_DIR}'
"

# Copy dumps out without piping binary through a shell redirect (Windows-safe).
container_id="$(compose ps -q "${DB_SERVICE}")"
docker cp "${container_id}:${REMOTE_DIR}/." "${OUT_DIR}/"
compose exec -T "${DB_SERVICE}" rm -rf "${REMOTE_DIR}"

cat > "${OUT_DIR}/MANIFEST.txt" <<EOF
created_utc=${STAMP}
primary=${DATABASE_NAME}
cache=${DATABASE_CACHE_NAME}
queue=${DATABASE_QUEUE_NAME}
cable=${DATABASE_CABLE_NAME}
format=pg_dump custom (-Fc)
EOF

# Fail if any expected dump is missing or empty.
for db in "${DATABASE_NAME}" "${DATABASE_CACHE_NAME}" "${DATABASE_QUEUE_NAME}" "${DATABASE_CABLE_NAME}"; do
  if [ ! -s "${OUT_DIR}/${db}.dump" ]; then
    echo "Backup incomplete: missing or empty ${OUT_DIR}/${db}.dump" >&2
    exit 1
  fi
done

# Tighten permissions on sensitive dump files (best-effort on hosts without chmod).
chmod 600 "${OUT_DIR}"/*.dump "${OUT_DIR}/MANIFEST.txt" 2>/dev/null || true

echo "Backup complete: ${OUT_DIR}"
ls -la "${OUT_DIR}"
