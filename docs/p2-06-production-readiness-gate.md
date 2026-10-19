# P2-06 — Production Readiness Gate

**No deployment or infrastructure modifications.** Local validation of artifacts for a controlled first deploy to the existing Oracle A1 host.

Hostname: **`getcourt.zanity.net`**  
Compose project: **`tennis`**  
Bind: **`127.0.0.1:3010`**

---

## 1. Release candidate

| Item | Result |
|---|---|
| Local `HEAD` | `edab5e2a6f54d90e47b0f2c5cfb98ce0ae748cf9` |
| Live `origin/main` (`git ls-remote`) | **Same SHA** |
| Tracking | `main` matches `origin/main` |
| Phase 1 + P2-00 bulk | Included via ancestor `92b3868` |

### Untracked / modified deployment-related work (not in `edab5e2`)

Must be committed (when authorized) before a reproducible host checkout matches local planning:

| Path | Notes |
|---|---|
| `deploy/nginx/getcourt.zanity.net.conf` | Nginx Phase A/B template |
| `deploy/nginx/websocket_upgrade.conf` | WebSocket map |
| `deploy/env/tennis.production.example` | Env template |
| `scripts/ops/a1_host_inventory.sh` | Host inventory |
| `docs/p2-03*.md` … `p2-06*.md` | Plans / assessments / this gate |
| `app/services/public_app_host.rb` | URL normalizer |
| `app/services/{communities,match_invitations,match_results}/notifier.rb` | Use `PublicAppHost` |
| `test/services/public_app_host_test.rb` | Unit test |

**Reproducibility:** Deploying only `edab5e2` **omits** Nginx/env/runbook/`PublicAppHost` fixes. Authorize a commit of the P2-03…P2-06 artifact set before remote deploy.

No commit/push performed in this gate.

---

## 2. Hostname validation

| Check | Result |
|---|---|
| Production hostname in deploy artifacts | **`getcourt.zanity.net` only** (old `gotcourt.sl8.net` only appears as historical rename notes) |
| `APP_HOST` format | **Full URL with scheme** — `https://getcourt.zanity.net` |
| Mailer | Strips scheme → `host` + `protocol: "https"` (`production.rb`) |
| `PublicAppHost` | Same normalization for Phase 1 notification links |
| `RAILS_ALLOWED_HOSTS` | Bare `getcourt.zanity.net` for `config.hosts` |
| Redirects | `force_ssl` + `assume_ssl`; health `/up` excluded from SSL redirect |
| `public_app_host_test.rb` | **Not executed** — Docker daemon unavailable this session (logic reviewed statically) |

---

## 3. Nginx and TLS

| Check | Result |
|---|---|
| HTTP-only Phase A installable without certs | **PASS** — ACME + 503; no `listen 443` active |
| Certbot sequence | Documented: DNS → OCI → Phase A → issue → Phase B/redirect → `renew --dry-run` |
| Preserve `sites-enabled/default` | **PASS** — templates instruct add-only; do not overwrite default |
| Reload only after `nginx -t` | Documented |
| Renewal / recovery | Documented in [p2-05-freedns-letsencrypt-runbook.md](p2-05-freedns-letsencrypt-runbook.md) |

---

## 4. Docker and ARM64

Local `docker compose -p tennis -f docker-compose.prod.yml … config` (with tennis env):

| Check | Result |
|---|---|
| Project name | `tennis` |
| Port 3010 loopback-only | **PASS** — `host_ip: 127.0.0.1`, `published: "3010"` |
| PostgreSQL published | **PASS** — no host port for `db` |
| Volumes | `tennis_postgres_prod_data`, `tennis_rails_storage` |
| Network | `tennis_internal` |
| Healthchecks / `depends_on` | Present for db → web/worker |
| Native ARM64 runtime smoke | **PENDING** — requires authorized deploy on A1 |
| Image build on Ampere | **PENDING** |
| libvips / PostGIS native behavior | **PENDING** until smoke |

Inventory (prior): host is aarch64, Docker arm64, idle — favorable, not a substitute for app smoke.

---

## 5. Security

| Check | Result |
|---|---|
| Trusted proxies | Loopback default; Nginx on host → OK without broad RFC1918 |
| `force_ssl` / `assume_ssl` | Enabled |
| Secure cookies | Via `force_ssl` |
| Allowed hosts | Defaults + `RAILS_ALLOWED_HOSTS=getcourt.zanity.net` |
| SMTP secrets | Env-only; `.env.production*` gitignored |
| Tracked secrets / private keys | None (`*.pem` / live `.env.production` not tracked) |
| Error pages | `consider_all_requests_local = false` |
| Parameter filtering | `filter_parameter_logging` present |

---

## 6. Backup readiness

| Check | Result |
|---|---|
| Scripts | `script/backup-postgres.sh`, `script/restore-postgres.sh` |
| Four logical DBs | Primary + cache + queue + cable dumped/restored |
| Local staging | `/var/backups/tennis/` (create on host when authorized) |
| Off-instance | **Required** — copy stamped dump dirs to operator-chosen object storage / second host (not configured in git) |
| Disposable restore drill | Use `COMPOSE_PROJECT_NAME=tennis_restore` or `docker-compose.fresh.yml`; never first-restore onto live `tennis` volumes |
| Actual restore execution | **PENDING until after deployment** |

Untested backup ≠ production-ready.

---

## 7. Deployment authorization matrix

### A. Local checks already passed

- [x] Live remote SHA matches `edab5e2` (app bulk through P2-01)
- [x] Hostname artifacts use `getcourt.zanity.net`
- [x] `APP_HOST` / mailer / `PublicAppHost` design reviewed
- [x] Nginx Phase A safe without certs
- [x] Compose tennis loopback 3010; Postgres internal
- [x] Secrets not in git; production error/filter settings OK
- [x] Backup scripts cover four DBs (procedure untested)

### B. Operator DNS / OCI checks still needed

- [ ] FreeDNS A/AAAA for `getcourt.zanity.net` → this VM (`dig`)
- [ ] OCI security list / NSG allows TCP 80 and 443
- [ ] Off-instance backup destination chosen

### C. Remote configuration changes requiring approval

- [ ] Authorize git commit of untracked P2-03…P2-06 artifacts (+ notifier/`PublicAppHost`)
- [ ] Authorize push / host checkout of that commit
- [ ] Authorize `.env.production.tennis` creation on host (secrets)
- [ ] Authorize Nginx Phase A install (`getcourt.zanity.net` + websocket map)
- [ ] Authorize Certbot issue for `getcourt.zanity.net`
- [ ] Authorize Compose `tennis` build/up + migrate

### D. Native ARM64 smoke tests requiring deployment

- [ ] `/up`, worker health, OTP email links, avatar/libvips, invite/result/community flows
- [ ] `certbot renew --dry-run`
- [ ] First backup + disposable restore drill

### E. Beta onboarding requiring separate approval

- [ ] Product owner authorizes inviting beta users after smoke passes

---

## Verdict: **CONDITIONAL GO**

**Meaning:** Local deployment *artifacts* and Compose/Nginx/hostname design are ready for a controlled first deploy **after**:

1. Committing the untracked artifact set (reproducible RC beyond `edab5e2`),  
2. FreeDNS + OCI checks,  
3. Explicit authorization for each remote change in matrix C,  
4. Completing matrix D smokes before beta (E).

This is **not** authorization to deploy, push, install Certbot, or change the Oracle host.
