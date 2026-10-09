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

for db in "${DATABASE_NAME}" "${DATABASE_CACHE_NAME}" "${DATABASE_QUEUE_NAME}" "${DATABASE_CABLE_NAME}"; do
  if [ ! -f "${BACKUP_PATH}/${db}.dump" ]; then
    echo "Missing dump file: ${BACKUP_PATH}/${db}.dump" >&2
    exit 1
  fi
done

compose() {
  # COMPOSE_PROJECT_NAME is honored when set (e.g. disposable restore drills).
  docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" "$@"
}

container_id="$(compose ps -q "${DB_SERVICE}")"
if [ -z "${container_id}" ]; then
  echo "Database service '${DB_SERVICE}' is not running" >&2
  exit 1
fi

compose exec -T "${DB_SERVICE}" mkdir -p "${REMOTE_DIR}"
docker cp "${BACKUP_PATH}/." "${container_id}:${REMOTE_DIR}/"

restore_one() {
  local db="$1"
  local dump="${REMOTE_DIR}/${db}.dump"
  echo "Restoring ${db}..."
  compose exec -T -e PGPASSWORD="${DATABASE_PASSWORD}" "${DB_SERVICE}" bash -lc "
    set -euo pipefail
    test -f '${dump}'
    psql -U '${DATABASE_USERNAME}' -d postgres -v ON_ERROR_STOP=1 -tAc \"SELECT 1 FROM pg_database WHERE datname='${db}'\" | grep -q 1 \
      || psql -U '${DATABASE_USERNAME}' -d postgres -v ON_ERROR_STOP=1 -c \"CREATE DATABASE ${db} OWNER ${DATABASE_USERNAME}\"
    # pg_restore exit 1 = warnings only; >1 is a hard failure.
    set +e
    pg_restore -U '${DATABASE_USERNAME}' -d '${db}' --clean --if-exists --no-owner --no-acl '${dump}'
    status=\$?
    set -e
    if [ \"\${status}\" -gt 1 ]; then
      echo \"pg_restore failed for ${db} with status \${status}\" >&2
      exit \"\${status}\"
    fi
    psql -U '${DATABASE_USERNAME}' -d '${db}' -v ON_ERROR_STOP=1 -c 'SELECT current_database();' >/dev/null
  "
}

restore_one "${DATABASE_NAME}"
restore_one "${DATABASE_CACHE_NAME}"
restore_one "${DATABASE_QUEUE_NAME}"
restore_one "${DATABASE_CABLE_NAME}"

compose exec -T "${DB_SERVICE}" rm -rf "${REMOTE_DIR}"
echo "Restore complete from ${BACKUP_PATH}"
