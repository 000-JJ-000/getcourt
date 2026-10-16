# P2-01 — Local Release Candidate

Checkpoint SHA: **`92b386871ee8c5b74dfb4e43d1b7409d0ec8f46d`**  
Message: `feat(infra): Up thorugh P2-00`  
Base: `548b34b` (P1-01–P1-04). **Do not push or deploy without authorization.**

## Included scope

Single coherent commit covering P1-05 (results/history), P1-06 (communities), P1-07 (beta readiness), and P2-00 (preflight). Milestone labels were not split: controllers, `Game`/`Match` stats, routes, schema, and locales interdepend.

## Required environment variables

See `.env.production.example`. Minimum for Compose production:

| Variable | Purpose |
|---|---|
| `SECRET_KEY_BASE` | Sessions / cookies |
| `APP_HOST` | Public HTTPS URL (scheme required) |
| `DATABASE_USERNAME` / `DATABASE_PASSWORD` | Postgres |
| `DATABASE_NAME` + `_CACHE` / `_QUEUE` / `_CABLE` | Four logical DBs |
| `SMTP_ADDRESS` / `SMTP_PORT` / `SMTP_USERNAME` / `SMTP_PASSWORD` (or Resend fallback) | OTP mail |
| `WEB_PORT` | Prefer `127.0.0.1:3000` |

Optional but production-important: `TRUSTED_PROXIES`, `RAILS_ALLOWED_HOSTS`, Telegram tokens, maps keys.

## Pending production configuration

- [ ] Reverse proxy + TLS terminator chosen  
- [ ] `TRUSTED_PROXIES` (or loopback-only bind) recorded  
- [ ] SMTP end-to-end OTP verified  
- [ ] Firewall: no public Postgres; web not raw-public without proxy  

## Database migrations (since 548b34b)

1. `20261013120000_add_canceled_at_to_games`  
2. `20261013140000_create_communities`  
3. `20261013160000_create_community_invitations`  

Apply once via:  
`docker compose -f docker-compose.prod.yml --env-file .env.production --profile migrate run --rm migrate`

## Image build (authorize separately)

```bash
docker buildx build --platform linux/arm64 -t getcourt:<tag> --target runtime --load .
# or Compose: docker compose -f docker-compose.prod.yml --env-file .env.production build
```

Do not publish registries without authorization. QEMU build ≠ native Ampere validation.

## ARM64 smoke / backup / rollback

- Smoke: [arm64-smoke-checklist.md](arm64-smoke-checklist.md)  
- Backup/restore: [deployment.md](deployment.md)  
- Rollback limits: forward-only migrations; incompatible schema needs DB restore — [p2-00-deployment-preflight.md](p2-00-deployment-preflight.md)

## Known cosmetic

`git diff --check 548b34b..HEAD` reports trailing whitespace in markdown checklists (`docs/arm64-smoke-checklist.md`, `docs/p2-00-deployment-preflight.md`). Non-blocking; clean up in a follow-up commit if desired.
