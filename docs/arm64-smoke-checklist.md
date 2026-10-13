# Native Oracle Ampere A1 smoke-test checklist

Companion to [runbook-oracle-arm64.md](runbook-oracle-arm64.md), [deployment.md](deployment.md), [p2-00-deployment-preflight.md](p2-00-deployment-preflight.md).

**Do not provision, deploy, or run these on a remote host without authorization.**

Commands assume production Compose from the repo root with `.env.production` present (`chmod 600`).

```bash
export COMPOSE="docker compose -f docker-compose.prod.yml --env-file .env.production"
```

## QEMU / buildx vs native

| Validation | Proves | Does not prove |
|---|---|---|
| CI / `docker buildx --platform linux/arm64` | Image builds for arm64 | Runtime on Ampere |
| Commands below **on A1 host** | Native boot, PostGIS, jobs, libvips | Full load test |

## 1. Image architecture

```bash
uname -m   # expect aarch64
$COMPOSE build web
docker image inspect "$($COMPOSE images -q web | head -1)" --format '{{.Architecture}}'
# expect arm64
```

## 2. Container startup

```bash
$COMPOSE up -d db
$COMPOSE --profile migrate run --rm migrate
$COMPOSE up -d --build web worker
$COMPOSE ps
```

## 3. Database migrations

```bash
$COMPOSE --profile migrate run --rm migrate
# Idempotent on already-migrated DB; failures must not be ignored.
```

## 4. Web and worker health

```bash
curl -fsS http://127.0.0.1:${WEB_PORT:-3000}/up
$COMPOSE ps   # web + worker healthy
$COMPOSE logs --tail=80 web worker
```

## 5. Solid Queue recurring jobs

```bash
$COMPOSE exec worker bundle exec rails runner 'puts SolidQueue::Job.count'
# Confirm production recurring.yml tasks are loaded by the worker process
# (expire_match_invitations, expire_community_invitations, game reminders, etc.)
$COMPOSE logs worker 2>&1 | grep -i recurring || true
```

## 6. OTP email delivery

1. Request sign-in OTP for a test mailbox you control.  
2. Confirm message arrives (SMTP_* / Resend configured).  
3. Confirm application logs do **not** print the code.

## 7. Active Storage / avatars (libvips)

1. Sign in → edit profile → upload JPEG/PNG/WebP ≤ 2 MB.  
2. Confirm avatar renders on profile; check `web` logs for vips errors.

## 8. Player discovery

1. Two completed `members`/`public` profiles.  
2. `/players` lists eligible peers; private/incomplete hidden.

## 9. Invitations and coordination

1. Match invitation create → accept → schedule/propose as supported.  
2. Notifications delivered (email/Telegram per config).

## 10. Results and statistics

1. Invite-only game: submit result → peer confirms.  
2. Confirm W/L/hours update only after confirm; match history shows the match.

## 11. Community membership and invitations

1. Public approval community: request → approve → create community game.  
2. Private community: stranger URL 404; invite → accept; revoke/expire path.

## 12. Backup / restore

```bash
chmod +x script/backup-postgres.sh script/restore-postgres.sh
BACKUP_DIR=./backups COMPOSE_FILE=docker-compose.prod.yml ENV_FILE=.env.production \
  ./script/backup-postgres.sh
# Restore only into a disposable target (e.g. docker-compose.fresh.yml) — see deployment.md
```

## 13. Memory, CPU, disk, logs

```bash
docker stats --no-stream
df -h
$COMPOSE logs --tail=200 web worker db
# Note RSS for web/worker/db under idle and after smoke clicks. Watch disk for backups + storage volume.
```

## Pass criteria

- All healthchecks green  
- OTP works without logging codes  
- Avatar upload works  
- Core Phase 1 flows (discovery, invite, results, communities) succeed once  
- Backup artifact non-empty for all four DBs  
- No sustained OOM / restart loops on 1 OCPU / 6 GB during smoke
