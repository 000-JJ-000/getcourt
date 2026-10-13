# P2-00 — Deployment Preflight

Preparation and verification only. **Do not deploy, push, or provision without explicit authorization.**

Companion docs: [deployment.md](deployment.md), [runbook-oracle-arm64.md](runbook-oracle-arm64.md), [arm64-smoke-checklist.md](arm64-smoke-checklist.md), [beta-readiness.md](beta-readiness.md).

---

## 1. Repository integrity (snapshot)

Recorded at P2-00 review time — re-check before any authorized commit.

| Item | Status |
|---|---|
| Branch | `main` tracking `origin/main` |
| HEAD | `548b34b` — feat(infra): P1-01 through 04… |
| Local identity | Configured (`user.name` / `user.email` present) — do not change via automation |
| Uncommitted Phase 1 work | Large dirty tree: communities, invitations, match results, docs, migrations, tests (P1-05–P1-07 + P2-00) |
| Secrets tracked | Only templates/encrypted: `.env.production.example`, `config/credentials.yml.enc`. No plaintext `.env.production` in git |
| Generated junk | `log/`, `coverage/`, `tmp/` gitignored — do not commit |

### Recommended commit plan (authorize before creating)

1. **P1-05** — invite-only games, cancel, match results confirm/dispute, stats gating, tests/docs  
2. **P1-06** — communities + membership  
3. **P1-07** — community invitations, community game create, hours consistency, beta docs, rate limits  
4. **P2-00** — Brakeman DirectoryQuery fix, trusted-proxy tightening, preflight docs  

Do not push until each slice is reviewed. Prefer one PR or sequential commits on a release branch if `main` must stay deployable.

---

## 2. Brakeman / DirectoryQuery

`Players::DirectoryQuery` ordering rebuilt with Arel `Case` / bound equality for same-city rank; completeness/name/id use **fixed** `Arel.sql` allowlist constants. No string interpolation of viewer input into `Arel.sql`.

Threat model if any residual warning: viewer city id coerced with `to_i`; city name compared as bound string via Arel `eq` (not concatenated). Filters still allowlist NTRP/formats/styles.

---

## 3. Production proxy & rate limits

See [deployment.md](deployment.md) § reverse proxy. Defaults now **loopback-only** trusted proxies; set `TRUSTED_PROXIES` (and optionally `TRUST_PRIVATE_NETWORK_PROXIES=1` only when justified). Rack::Attack uses `Rails.cache` (Solid Cache in production).

---

## 4. Oracle Ampere resource assessment (no native benchmarks)

**Target:** VM.Standard.A1.Flex, 1 OCPU / 6 GB RAM, Docker Compose (`db` + `web` + `worker`).

| Component | Expected role | Conservative guidance |
|---|---|---|
| PostgreSQL/PostGIS | Primary + cache/queue/cable DBs | Default shared_buffers fine for beta; watch connections |
| `web` (Puma) | HTTP | Prefer **low** concurrency: e.g. `WEB_CONCURRENCY=1`, `RAILS_MAX_THREADS=3–5` if set in image/entrypoint |
| `worker` (Solid Queue) | Jobs / recurring | Single worker process adequate for 25–50 users |
| Active Storage / libvips | Avatars | Spiky CPU on upload; avoid large batch imports |
| Reverse proxy | TLS | Host Caddy/nginx — light |

**Risks (estimate, not measured on A1):** OOM if Puma workers × threads + Postgres + worker exceed ~6 GB under peak; disk growth from backups/storage volume; queue backlog if SMTP stalls. Start at 1 OCPU / 6 GB; measure before scaling.

---

## 5. SMTP and secrets checklist

Never put real values in docs or git.

| Requirement | Notes |
|---|---|
| `SECRET_KEY_BASE` | Required; `openssl rand -hex 64` |
| DB user/password + four DB names | Required; Postgres not published |
| `APP_HOST` | Public HTTPS URL with scheme |
| `RAILS_ALLOWED_HOSTS` | Extra hosts if not getcourt.co |
| SMTP | `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` (or intentional `RESEND_API_KEY` fallback), `SMTP_AUTHENTICATION`, `SMTP_ENABLE_STARTTLS` |
| OTP | Uses SMTP; codes must not appear in logs |
| Session/cookies | `force_ssl` + secure cookies in production |
| Telegram | Optional `TELEGRAM_BOT_TOKEN` / chat id |
| `TRUSTED_PROXIES` | Required for correct client IP behind non-loopback proxy |
| Backups | Off-host encrypted retention; see rollback § |

Rails `credentials.yml.enc` / master key: only if the chosen deploy path uses encrypted credentials; Compose path primarily uses `.env.production`.

---

## 6. Beta rollback plan

1. **Pre-deploy:** encrypted backup of all four logical DBs (`script/backup-postgres.sh`); record image digest/tag.  
2. **Image versioning:** deploy immutable tags/digests; never rely on `:latest` alone.  
3. **Migrations:** prefer forward-only. Incompatible schema changes **cannot** be auto-rolled back by redeploying an old image without a DB restore.  
4. **Rollback options:** (a) redeploy previous image if schema compatible; (b) restore DB backup into drill/prod per [deployment.md](deployment.md); (c) stop onboarding if restore needed.  
5. **Recovery checks:** `/up`, worker health, OTP send, one login, one community/game read.  
6. **Roles:** operator (Compose/DB), product owner (stop onboarding), on-call for SMTP/DNS.  
7. **Stop-beta criteria:** auth/OTP failure, data corruption, unpatched critical CVE in running stack, sustained OOM, privacy breach.

---

## 7. Quality-gate results (P2-00 session)

| Gate | Command | Result |
|---|---|---|
| Directory regression | `bin/rails test test/services/players/directory_query_test.rb test/controllers/players_controller_test.rb test/system/player_discovery_test.rb` | Pass (13) |
| Unit/integration | `bin/rails db:test:prepare test` | Pass (1558) |
| System | `bin/rails test:system` | Pass (30) |
| RuboCop (changed) | `bin/rubocop app/services/players/directory_query.rb config/environments/production.rb` | Pass |
| Brakeman | `bin/brakeman --no-pager` | Pass — **0 warnings** |
| bundler-audit | ephemeral `gem install bundler-audit` → `bundle-audit update && bundle-audit check` (v0.9.3; DB updated 2026-10-10) | Pass — no vulns |
| importmap audit | `bin/importmap audit` | Pass |
| Compose | `docker compose -f docker-compose.yml config`; prod + fresh with CI env | Pass |
| Native ARM64 smoke | — | **Not executed** (no deploy auth) |
| AMD64/ARM64 image build | — | **Not re-run** this session (CI exists) |

## 8. Remaining deployment blockers

- [ ] Authorized git commits (Phase 1 + P2-00) and optional PR  
- [ ] Authorized push  
- [ ] Oracle A1 provision + native ARM64 smoke  
- [ ] SMTP verified end-to-end  
- [ ] `TRUSTED_PROXIES` / loopback bind decision recorded  
- [ ] Pre-deploy backup drill succeeded once  

## Recommended authorization steps

1. Review this preflight + quality-gate results.  
2. Authorize commits (commit plan above).  
3. Authorize push / PR merge.  
4. Authorize VM provision + Compose bring-up.  
5. Run [arm64-smoke-checklist.md](arm64-smoke-checklist.md) on the host.  
6. Authorize beta user invites only after smoke + OTP pass.
