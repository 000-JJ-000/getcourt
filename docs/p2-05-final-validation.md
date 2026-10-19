# P2-05 Final Validation Report — getcourt.zanity.net

Local review only. Hostname updated from `gotcourt.sl8.net` → `getcourt.zanity.net`.

No deploy, commit, push, Certbot, or host changes executed in the hostname-change pass.

## Hostname change summary

| Item | Value |
|---|---|
| OLD | `gotcourt.sl8.net` |
| NEW | `getcourt.zanity.net` |
| `APP_HOST` | `https://getcourt.zanity.net` (URL with scheme) |
| `RAILS_ALLOWED_HOSTS` | `getcourt.zanity.net` (bare) |
| Nginx template | `deploy/nginx/getcourt.zanity.net.conf` |
| Certbot | `-d getcourt.zanity.net` |

## Issues found (prior validation; still relevant)

1. Phase A must not proxy HTTP to Rails under `force_ssl` before certs (fixed earlier).
2. WebSocket map file required for Phase B.
3. Notification URL builders need `PublicAppHost` normalization (fixed for Phase 1 notifiers).
4. Backups untested on A1.
5. Some Telegram/MCP helpers may still pass raw `APP_HOST` as `host:` (follow-up).
6. OCI NSG / FreeDNS for **new** hostname still operator-owned.

## Corrections in hostname-change pass

| File | Change |
|---|---|
| `deploy/nginx/gotcourt.sl8.net.conf` | **Removed** |
| `deploy/nginx/getcourt.zanity.net.conf` | **Added** with `server_name getcourt.zanity.net` |
| `deploy/env/tennis.production.example` | New hostname |
| `docs/p2-05-freedns-letsencrypt-runbook.md` | New hostname + certbot `-d` |
| `docs/p2-04-a1-host-assessment.md` | New hostname |
| `docs/p2-05-final-validation.md` | This report |
| `test/services/public_app_host_test.rb` | Example host updated |

## Local validation results

| Check | Result |
|---|---|
| Repo search for `gotcourt.sl8.net` | Must be zero after change |
| `APP_HOST` format | URL with scheme — matches Rails/mailer/`PublicAppHost` |
| Compose `WEB_PORT=127.0.0.1:3010` | Unchanged loopback binding |
| Nginx template | Phase A ACME + 503; HTTPS commented until certs |
| Secrets / live certs in git | None expected (templates only) |

## Remaining blockers

1. FreeDNS A/AAAA for `getcourt.zanity.net` → this VM (`dig`).
2. OCI ingress 80/443 confirmed.
3. Explicit auth to install Nginx site, run Certbot, start Compose.
4. SMTP configured; OTP links show `https://getcourt.zanity.net/...`.
5. Backup + disposable restore drill.

## Gate

**CONDITIONAL GO** (config/hostname artifacts). Not authorization to deploy.
