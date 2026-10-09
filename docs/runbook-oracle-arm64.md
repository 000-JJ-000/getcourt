# GetCourt deployment runbook — Oracle Cloud Ampere A1 (ARM64)

Concise ops guide for a small self-hosted community deployment. Companion to [deployment.md](deployment.md).

**Recommended starting shape:** 1 OCPU / 6 GB RAM VM. Treat this as a starting point only — measure under real traffic before committing capacity.

**Native ARM64 runtime** is only proven by running `script/arm64-smoke.sh` on the Ampere host. CI ARM64 image *builds* (often via QEMU) are **not** a substitute.

## 1. VM preparation

1. Create an Oracle Ampere A1 instance (Ubuntu 22.04/24.04 ARM64 recommended).
2. Open **only** ports needed for SSH and your reverse proxy (80/443). Do **not** expose Postgres or raw Puma publicly.
3. Create a non-root deploy user with Docker group membership.

## 2. Docker installation

```bash
# Ubuntu example
sudo apt-get update
sudo apt-get install -y ca-certificates curl git
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
# re-login, then:
docker version
docker compose version
```

## 3. Application checkout

```bash
git clone <your-fork-url> getcourt
cd getcourt
cp .env.production.example .env.production
# Edit .env.production — all required values (SECRET_KEY_BASE, DB password, APP_HOST, SMTP_*, etc.)
chmod 600 .env.production
```

Generate secrets:

```bash
openssl rand -hex 64   # SECRET_KEY_BASE
openssl rand -hex 24   # DATABASE_PASSWORD
```

## 4. Database initialization

```bash
docker compose -f docker-compose.prod.yml --env-file .env.production up -d db
docker compose -f docker-compose.prod.yml --env-file .env.production --profile migrate run --rm migrate
```

## 5. Application + worker startup

```bash
docker compose -f docker-compose.prod.yml --env-file .env.production up -d --build web worker
```

## 6. Health verification

```bash
curl -fsS http://127.0.0.1:3000/up
docker compose -f docker-compose.prod.yml --env-file .env.production ps
docker compose -f docker-compose.prod.yml --env-file .env.production logs --tail=100 web worker
```

Expect `web` healthy via `/up` and `worker` healthy (Solid Queue process + queue DB probe). Failures appear as unhealthy containers and stderr logs — no external monitoring stack is required for P0-05.

## 7. Native ARM64 smoke (required once per host/image)

```bash
chmod +x script/arm64-smoke.sh
./script/arm64-smoke.sh
```

Validates boot, pg/libvips (and tdlib if present), Puma `/up`, Solid Queue, migrate, and restart persistence on the **native** arch.

## 8. Reverse proxy (TLS)

Terminate HTTPS at Caddy/nginx/Cloudflare Tunnel in front of `WEB_PORT` (default 3000).

| Concern | Requirement |
|---|---|
| HTTPS | Proxy terminates TLS; Rails `force_ssl` + `assume_ssl` |
| Client IP | Proxy sets `X-Forwarded-For` / `X-Forwarded-Proto`; Rails trusts only `TRUSTED_PROXIES` CIDRs (private defaults + your CDN) |
| WebSockets | Forward `Upgrade` / `Connection` for Action Cable |
| Rate limits | Rack::Attack uses `request.ip` after trusted-proxy stripping — wrong trust → shared/wrong buckets |
| Cookies | Production session cookies are `Secure`, `HttpOnly`, `SameSite=Lax` |

Never expose Puma without a proxy that strips untrusted client forwarding headers.

## 9. Updating

```bash
git fetch && git checkout <tag-or-sha>
docker compose -f docker-compose.prod.yml --env-file .env.production build
docker compose -f docker-compose.prod.yml --env-file .env.production --profile migrate run --rm migrate
docker compose -f docker-compose.prod.yml --env-file .env.production up -d web worker
curl -fsS http://127.0.0.1:3000/up
```

## 10. Rollback

1. Check out the previous known-good git SHA/tag.
2. Rebuild and `up -d web worker` (re-run migrate only if that revision needs schema downgrade — prefer forward fixes).
3. If data regression: restore from the last off-host backup into a disposable stack first, then cut over.

## 11. Backup and restore

Schedule (small community): **daily** automated backup to off-host storage; retain ≥ 7 daily + 4 weekly.

```bash
# Backup (host directory outside containers)
BACKUP_DIR=/var/backups/getcourt \
COMPOSE_FILE=docker-compose.prod.yml ENV_FILE=.env.production \
  ./script/backup-postgres.sh
chmod 700 /var/backups/getcourt
```

```bash
# Disposable restore drill
docker compose -p getcourt-fresh -f docker-compose.fresh.yml --env-file .env.production up -d
BACKUP_PATH=/var/backups/getcourt/<stamp> \
COMPOSE_FILE=docker-compose.fresh.yml ENV_FILE=.env.production DB_SERVICE=db_fresh \
  ./script/restore-postgres.sh
```

All four logical databases (primary, cache, queue, cable) are included. Backup/restore scripts exit nonzero on missing dumps or hard `pg_restore` failures.

## 12. Logs and troubleshooting

```bash
docker compose -f docker-compose.prod.yml --env-file .env.production logs -f web worker db
```

| Symptom | Action |
|---|---|
| `web` unhealthy | Boot logs; `SECRET_KEY_BASE` / SMTP / DB env; `/up` |
| `worker` unhealthy | Queue DB migrated; `SOLID_QUEUE_IN_PUMA` empty; job process |
| Wrong client IPs / rate limits | Fix `TRUSTED_PROXIES` to match your proxy/CDN only |
| ARM gem/native crash | Re-run `script/arm64-smoke.sh`; check libvips/`tdlib-ruby` |

## Related

- [deployment.md](deployment.md) — Compose architecture, multi-arch builds, secrets
- `script/arm64-smoke.sh` — native runtime validation
- `script/backup-postgres.sh` / `script/restore-postgres.sh`
