# GetCourt deployment (Docker Compose)

Self-hosted deployment on AMD64 or ARM64 Linux. Application stack: Rails web, Solid Queue worker, PostgreSQL/PostGIS (four logical databases).

## Architecture

| Service | Role | Readiness signal |
|---|---|---|
| `db` | PostgreSQL 16 + PostGIS | `pg_isready` healthcheck |
| `migrate` | One-shot `db:prepare` (profile) | Exit code 0 |
| `web` | Puma / Rails | HTTP `GET /up` → 200 |
| `worker` | Solid Queue (`bin/jobs start`) | Process healthcheck |

- **Container running** ≠ **Rails ready**: check `web` health (`/up`).
- **Postgres accepting connections**: `db` health (`pg_isready`).
- **Worker operational**: `worker` health (Solid Queue process present).
- Do **not** set `SOLID_QUEUE_IN_PUMA` when the dedicated `worker` service is running (duplicate job processing).

PostgreSQL is **not** published to the host in production Compose. Only `web` exposes a port for a reverse proxy on a private network.

## Local development

```bash
cp .env-example .env
docker compose up -d db
docker compose up --build          # web runs db:prepare for convenience
# optional dedicated worker (then leave SOLID_QUEUE_IN_PUMA empty):
docker compose --profile worker up -d --build
```

Dev Compose still prepares the database on web start. Production does not.

## Production deployment workflow

1. Copy `.env.production.example` → `.env.production` and fill **all required** values (`SECRET_KEY_BASE`, DB password, `APP_HOST`, database names).
2. Build (see multi-arch below) or build on the host:
   ```bash
   docker compose -f docker-compose.prod.yml --env-file .env.production build
   ```
3. Start database:
   ```bash
   docker compose -f docker-compose.prod.yml --env-file .env.production up -d db
   ```
4. **Initialize / migrate once** (never from every web/worker replica startup):
   ```bash
   docker compose -f docker-compose.prod.yml --env-file .env.production --profile migrate run --rm migrate
   ```
5. Start app processes:
   ```bash
   docker compose -f docker-compose.prod.yml --env-file .env.production up -d web worker
   ```
6. Verify:
   ```bash
   docker compose -f docker-compose.prod.yml ps
   curl -fsS http://127.0.0.1:3000/up
   docker compose -f docker-compose.prod.yml logs -f web worker
   ```

### Schema migrations later

Repeat step 4 during a maintenance window **before** rolling new web/worker containers that require the new schema. Only one migrate task should run at a time.

## Environment variables

See `.env-example` (development) and `.env.production.example` (production).

| Variable | Production | Notes |
|---|---|---|
| `SECRET_KEY_BASE` | **Required** | `openssl rand -hex 64` |
| `DATABASE_PASSWORD` | **Required** | No default in production |
| `DATABASE_*_NAME` | **Required** | Four logical DBs |
| `APP_HOST` | **Required** | Public URL with scheme |
| `RAILS_ALLOWED_HOSTS` | Optional | Extra hosts, comma-separated |
| `SOLID_QUEUE_IN_PUMA` | Empty | Use dedicated worker |
| `WEB_PORT` | Optional | Host port mapped to Puma (default 3000) |

### Secrets

- Never commit `.env` / `.env.production`.
- Rotate `SECRET_KEY_BASE` only with a planned session invalidation window.
- Rotate DB passwords by updating Postgres roles, then `.env.production`, then recreate app containers.
- Recovery: restore from encrypted off-host backups (below); keep a copy of `.env.production` in a password manager.

## Reverse proxy / networking

| Item | Expectation |
|---|---|
| Ports | Host/proxy → `WEB_PORT` (default 3000) on `web`. Postgres: **internal only**. |
| HTTPS | Terminate TLS at Caddy/nginx/etc. Rails `assume_ssl` / `force_ssl` expect `X-Forwarded-Proto`. |
| Trusted hosts | Defaults include `getcourt.co` / `*.getcourt.co`; add others via `RAILS_ALLOWED_HOSTS`. |
| Health | Proxy may probe `/up` over HTTP to the container; HTTPS redirect is skipped for `/up`. |
| WebSockets | Forward `Upgrade` / `Connection` headers to Puma for Action Cable (Solid Cable). |
| Forwarded headers | Set `X-Forwarded-For`, `X-Forwarded-Proto`, `Host` (or `X-Forwarded-Host`) at the proxy. |

Do not expose Postgres or the raw app port to the public Internet without a proxy and firewall rules.

## Backup and restore

All four logical databases must be backed up together for a consistent restore.

```bash
# Backup (production Compose stack running; needs bash + docker on PATH — Linux, macOS, or Git Bash/WSL)
chmod +x script/backup-postgres.sh script/restore-postgres.sh
BACKUP_DIR=./backups COMPOSE_FILE=docker-compose.prod.yml ENV_FILE=.env.production \
  ./script/backup-postgres.sh
```

The scripts dump **inside** the Postgres container and `docker cp` the files out (avoids binary piping issues on Windows hosts).

```bash
# Restore into a disposable target (example: docker-compose.fresh.yml)
# WARNING: destructive to target DB names in ENV_FILE
BACKUP_PATH=./backups/<stamp> \
COMPOSE_FILE=docker-compose.fresh.yml ENV_FILE=.env.production DB_SERVICE=db_fresh \
  ./script/restore-postgres.sh
```

Store `./backups` off-host and encrypted. Practice restore on a disposable volume before relying on backups.

## AMD64 / ARM64 builds

Base image: `ruby:4.0.7-slim` (multi-arch). PostGIS: `postgis/postgis:16-3.5` (multi-arch).

```bash
# Create/use a buildx builder
docker buildx create --name getcourt-builder --use || docker buildx use getcourt-builder

# Build and load native arch for local run
docker buildx build --platform linux/amd64 -t getcourt:local --target runtime --load .

# Build both platforms (push to your registry; --load supports one platform)
docker buildx build --platform linux/amd64,linux/arm64 \
  -t registry.example.com/getcourt:latest --target runtime --push .
```

Native gems of note: `pg`, `ruby-vips`/`libvips`, `rgeo`, `tdlib-ruby` (heavy; validate on ARM64 hosts before production cutover).

Distinguish:

- **Native run**: build `--load` for the host arch and `docker compose ... up`
- **Emulated**: `buildx --platform` on a different arch (QEMU) — useful for build checks, not full performance validation
- **Build-only**: image builds successfully but was not executed

## Logs and troubleshooting

```bash
docker compose -f docker-compose.prod.yml --env-file .env.production logs -f web worker db
docker compose -f docker-compose.prod.yml ps
curl -v http://127.0.0.1:3000/up
```

| Symptom | Check |
|---|---|
| `web` unhealthy | Logs for boot errors; `/up` response; `SECRET_KEY_BASE` / DB env |
| `worker` unhealthy | `SOLID_QUEUE_IN_PUMA` empty; queue DB migrated; `bin/jobs` logs |
| Migrations missing | Run migrate profile once; do not rely on web startup |
| Duplicate jobs | Ensure only worker processes Solid Queue |
| SSL redirect loops | Proxy must send `X-Forwarded-Proto: https` |

## Related files

- `Dockerfile` — `runtime` (prod) and `development` targets
- `docker-compose.yml` — local development
- `docker-compose.prod.yml` — production-oriented stack
- `docker-compose.fresh.yml` — disposable PostGIS for drills
- `bin/docker-entrypoint` — `web` / `worker` / `migrate` roles
