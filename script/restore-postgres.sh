#!/usr/bin/env bash
# Restore a backup directory created by script/backup-postgres.sh into a target
# Postgres service. Destructive for the target databases.
#
# Usage:
#   BACKUP_PATH=./backups/20261008T120000Z \
#   COMPOSE_FILE=docker-compose.fresh.yml ENV_FILE=.env.production \
#   DB_SERVICE=db_fresh ./script/restore-postgres.sh
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:?COMPOSE_FILE required}"
ENV_FILE="${ENV_FILE:-.env.production}"
DB_SERVICE="${DB_SERVICE:-db}"
BACKUP_PATH="${BACKUP_PATH:?BACKUP_PATH required (directory with *.dump files)}"
REMOTE_DIR="/tmp/getcourt-restore-$$"

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
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" "$@"
}

container_id="$(compose ps -q "${DB_SERVICE}")"
compose exec -T "${DB_SERVICE}" mkdir -p "${REMOTE_DIR}"
docker cp "${BACKUP_PATH}/." "${container_id}:${REMOTE_DIR}/"

restore_one() {
  local db="$1"
  local dump="${REMOTE_DIR}/${db}.dump"
  echo "Restoring ${db}..."
  compose exec -T -e PGPASSWORD="${DATABASE_PASSWORD}" "${DB_SERVICE}" bash -lc "
    set -euo pipefail
    psql -U '${DATABASE_USERNAME}' -d postgres -v ON_ERROR_STOP=1 -c \"SELECT 1 FROM pg_database WHERE datname='${db}'\" | grep -q 1 \
      || psql -U '${DATABASE_USERNAME}' -d postgres -v ON_ERROR_STOP=1 -c \"CREATE DATABASE ${db} OWNER ${DATABASE_USERNAME}\"
    # Prefer clean restore; tolerate pg_restore notice exit codes.
    pg_restore -U '${DATABASE_USERNAME}' -d '${db}' --clean --if-exists --no-owner --no-acl '${dump}' || true
    psql -U '${DATABASE_USERNAME}' -d '${db}' -c 'SELECT current_database();' >/dev/null
  "
}

restore_one "${DATABASE_NAME}"
restore_one "${DATABASE_CACHE_NAME}"
restore_one "${DATABASE_QUEUE_NAME}"
restore_one "${DATABASE_CABLE_NAME}"

compose exec -T "${DB_SERVICE}" rm -rf "${REMOTE_DIR}"
echo "Restore complete from ${BACKUP_PATH}"
