# P2-03 — Existing Oracle A1 Deployment Plan

**Planning only.** Do not SSH to the VM, provision, deploy, change DNS, push, or alter running services without separate authorization.

Companion docs: [deployment.md](deployment.md), [runbook-oracle-arm64.md](runbook-oracle-arm64.md), [arm64-smoke-checklist.md](arm64-smoke-checklist.md), [p2-00-deployment-preflight.md](p2-00-deployment-preflight.md), [p2-01-release-candidate.md](p2-01-release-candidate.md).

---

## 1. Release candidate verification

| Check | Result (local planning session) |
|---|---|
| Local `HEAD` | `edab5e2a6f54d90e47b0f2c5cfb98ce0ae748cf9` |
| Live remote `origin/main` (`git ls-remote`) | **Same SHA** `edab5e2…` |
| Tracking `origin/main` | Matches `HEAD` (clean working tree) |
| Prior Phase 1 + P2-00 bulk | Contained in ancestor `92b3868` |
| P2-01 RC doc | Present in `edab5e2` (`docs/p2-01-release-candidate.md`) |

**Deploy this revision (unless operator pins another):** `edab5e2a6f54d90e47b0f2c5cfb98ce0ae748cf9`.

Do not assume a stale local `origin/main` reflog equals the live remote without `git ls-remote`. Re-verify immediately before any authorized build.

---

## 2. Read-only host inventory (operator runs on VM)

Copy/paste on the A1 host. **Do not share raw output publicly** without redaction (see below).

```bash
# OS / arch
uname -a
cat /etc/os-release
uname -m   # expect aarch64

# CPU / RAM / pressure
nproc
lscpu | egrep 'Architecture|CPU\(s\)|Model name|Thread|Core'
free -h
# If installed:
# vmstat 1 5
# cat /proc/pressure/cpu /proc/pressure/memory 2>/dev/null || true

# Disk
df -hT
lsblk
docker system df 2>/dev/null || true

# Docker inventory (read-only)
docker version
docker compose version
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
docker compose ls
docker network ls
docker volume ls
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.Architecture}}' 2>/dev/null || docker images

# Listening ports (no secrets)
ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null || true

# Reverse proxy hints (paths only; redact vhost secrets)
command -v caddy nginx traefik 2>/dev/null
systemctl is-active caddy nginx traefik 2>/dev/null || true
ls /etc/caddy /etc/nginx /etc/traefik 2>/dev/null || true
# If Caddyfile/nginx sites exist, list names only:
# ls /etc/caddy/ /etc/nginx/sites-enabled/ 2>/dev/null

# Firewall
sudo iptables -L -n 2>/dev/null | head -80 || true
sudo nft list ruleset 2>/dev/null | head -80 || true
sudo firewall-cmd --list-all 2>/dev/null || true
# Oracle Cloud: also note VCN security-list / NSG rules in OCI console (not a CLI dump here)

# Backups already on host
ls -la /var/backups 2>/dev/null || true
crontab -l 2>/dev/null || true
sudo ls /etc/cron.* 2>/dev/null | head
```

### Redact before sharing

| Output | Risk |
|---|---|
| Env files, `.env*`, Compose `environment:` dumps | Passwords, SMTP, tokens |
| `docker inspect` full JSON | Env vars inside containers |
| TLS private keys, ACME account material | Compromise |
| Full firewall dumps with private IPs of peers | Topology |
| Backup paths containing customer dumps | PII / DB contents |
| Exact public IPs if not already public | Targeting |

Safe to share: arch, OCPU/RAM totals, free disk, container **names**/images/status (not env), port numbers in use, proxy **software** in use.

---

## 3. Workload isolation plan (`tennis` project)

Existing `docker-compose.prod.yml` has **no** `container_name:` overrides — Compose will name containers `{project}-{service}-{n}`. Named volumes without a hard-coded external name become `{project}_{volume}`.

### Recommended operator settings

```bash
export COMPOSE_PROJECT_NAME=tennis
export COMPOSE="docker compose -p tennis -f docker-compose.prod.yml --env-file .env.production.tennis"
# Prefer a dedicated env file so passwords/DB names never collide with other apps.
```

| Concern | Plan |
|---|---|
| Project name | `tennis` (`-p tennis` / `COMPOSE_PROJECT_NAME`) |
| Containers | `tennis-db-1`, `tennis-web-1`, `tennis-worker-1` (auto) |
| Volumes | `tennis_postgres_prod_data`, `tennis_rails_storage` |
| Network | `tennis_internal` (bridge; Postgres not published) |
| Host Rails bind | `WEB_PORT=127.0.0.1:3010` (unique loopback port; adjust if busy) |
| Postgres ports | None on host (Compose file already omits them) |
| Four logical DBs | Keep via env: e.g. `tennis_production`, `tennis_production_cache`, `tennis_production_queue`, `tennis_production_cable` |
| Other Compose projects | Untouched; never run `docker system prune` / global volume rm |
| Start | `$COMPOSE up -d db` → migrate profile → `$COMPOSE up -d web worker` |
| Stop | `$COMPOSE stop` (project-scoped) |
| Backup | `COMPOSE_PROJECT_NAME=tennis COMPOSE_FILE=… ENV_FILE=.env.production.tennis BACKUP_DIR=/var/backups/tennis ./script/backup-postgres.sh` |

**Do not** reuse another app’s Postgres volume, network, or DB names.

Optional later (authorized code change): rename volumes in Compose to explicit `name: tennis_postgres_data` for clarity — **not required** for isolation if project name is always set.

---

## 4. ARM64 resource budget (planning estimates)

**Assumption if inventory confirms:** VM.Standard.A1.Flex with **1 OCPU / 6 GB** and **other workloads already running**. These are **planning budgets**, not measured A1 benchmarks.

| Slice | Conservative share of 6 GB | Concurrency guidance |
|---|---|---|
| OS + page cache | ~0.5–1.0 GB leave alone | — |
| Existing workloads | **Unknown — measure first** | Do not shrink without owner OK |
| Postgres/PostGIS (`tennis`) | ~0.5–1.0 GB RSS target | Single instance; default shared_buffers OK for beta |
| Rails `web` (Puma) | ~0.3–0.6 GB | `WEB_CONCURRENCY` unset (1 process); `RAILS_MAX_THREADS=3` (app default) |
| Solid Queue `worker` | ~0.2–0.4 GB | Single worker process; `SOLID_QUEUE_IN_PUMA` empty |
| libvips spikes | Transient CPU/RAM on avatar upload | Avoid bulk imports |
| Headroom | **≥1.0 GB free + no thrashing** | Required go condition |

### Go / no-go (after inventory)

**GO** only if all hold:

1. `uname -m` is `aarch64`.  
2. Free RAM after existing steady state leaves **≥ ~2 GB** before starting tennis (so tennis + headroom fit), **or** operator accepts documented risk and existing owners agree.  
3. Free disk **≥ 10 GB** on the volume that will hold Docker data + `/var/backups/tennis` (more if existing apps are large).  
4. No sustained swap thrashing / pressure on existing services.  
5. Chosen loopback port free; existing reverse proxy healthy.  
6. Operator authorization recorded.

**NO-GO** if: existing critical services already near OOM; disk &lt; 5 GB free; port/proxy conflict unresolved; arch not arm64; unauthorized change to other Compose projects would be required.

---

## 5. Reverse proxy and TLS

Prefer **Option A**. Hostname is an **operator decision** (not chosen here).

### Option A — Reuse existing proxy (preferred)

1. Rails listens only on `127.0.0.1:3010` (`WEB_PORT=127.0.0.1:3010`).  
2. Add a new vhost / site for the tennis hostname → `http://127.0.0.1:3010`.  
3. Terminate HTTPS at the existing proxy (or CDN in front of it).  
4. Forward `Host`, `X-Forwarded-For`, `X-Forwarded-Proto`, `Upgrade`/`Connection` for Action Cable if used.  
5. Set Rails `APP_HOST=https://<tennis-host>`, `RAILS_ALLOWED_HOSTS=<tennis-host>`, `TRUSTED_PROXIES` to the proxy’s address as seen by the container/host (often `127.0.0.1` if proxy is on the host).  
6. Do not change unrelated vhosts beyond adding the new server block.

### Option B — Separate proxy (only if no suitable existing proxy)

Install/configure a dedicated Caddy/nginx instance **without** stealing ports 80/443 from an existing proxy. Prefer a second listener only if the operator’s topology requires it (unusual on one public IP). Default recommendation remains A.

### Security expectations

- `force_ssl` / secure cookies already in production Rails config.  
- No public publish of container port 3000 to `0.0.0.0`.  
- Spoofed `X-Forwarded-For` ignored unless peer is in `TRUSTED_PROXIES` (loopback-only default).

---

## 6. Database and storage

| Item | Plan |
|---|---|
| Postgres data | Volume `tennis_postgres_prod_data` |
| Active Storage | Volume `tennis_rails_storage` (shared by web + worker) |
| Backup dir | e.g. `/var/backups/tennis/` mode `700`; dumps mode `600` |
| Retention | Daily ≥ 7; weekly ≥ 4 (align with [deployment.md](deployment.md)); off-host copy |
| Migrate | `$COMPOSE --profile migrate run --rm migrate` once per schema change |
| Restore drill | Use `docker-compose.fresh.yml` **or** a separate project name (`tennis_restore`) and disposable volume — never overwrite live `tennis` volume blindly |
| Monitoring | `df -h`, `docker system df`, volume size growth weekly |

Backup script already respects `COMPOSE_PROJECT_NAME` and dumps all four logical DBs.

---

## 7. SMTP / OTP validation plan

**Do not paste secrets into tickets.** Operator configures `.env.production.tennis` from `.env.production.example`.

Checklist after web is up (authorized deploy only):

1. Confirm `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` (or intentional Resend fallback), `SMTP_AUTHENTICATION`, `SMTP_ENABLE_STARTTLS`.  
2. From the **web container**, verify outbound reachability to SMTP host:port (e.g. `nc -vz` / `openssl s_client` — no credentials in command history if avoidable).  
3. Request one OTP to an operator-controlled mailbox.  
4. Confirm delivery, login success, code expiry behavior.  
5. Confirm app logs show **no** plaintext OTP and no SMTP password.  
6. Confirm Rack::Attack login throttles still engage under repeated requests (use a test address; do not lock out real users).

---

## 8. Native ARM64 smoke (shared-host)

Use project-scoped Compose. **Stop** if existing workloads degrade (OOM, proxy 5xx, disk full).

```bash
export COMPOSE_PROJECT_NAME=tennis
export COMPOSE="docker compose -p tennis -f docker-compose.prod.yml --env-file .env.production.tennis"
# WEB_PORT must be set inside the env file, e.g. WEB_PORT=127.0.0.1:3010
```

| Step | Action | Stop if |
|---|---|---|
| Arch | `uname -m` → `aarch64` | Not arm64 |
| Build/load | `$COMPOSE build` (on host) | Build fails / wrong arch |
| DB up | `$COMPOSE up -d db` | Unhealthy &gt; few minutes |
| Migrate | `$COMPOSE --profile migrate run --rm migrate` | Nonzero exit |
| App up | `$COMPOSE up -d web worker` | Healthcheck fail; host memory thrash |
| Local health | `curl -fsS http://127.0.0.1:3010/up` | Fail |
| Jobs | Worker healthy; recurring tasks present in worker logs/config | Queue DB unreachable |
| Storage | Avatar upload (libvips) | Persistent vips errors |
| Product | Profile, `/players`, match invite, result confirm, community invite | Auth/data errors |
| Backup | Project-scoped `script/backup-postgres.sh` | Missing/empty dumps |
| Restore drill | Disposable project/volume only | Would touch live volume |
| Monitor | `docker stats`; `free -h`; existing app health | Existing services degrade |

Full narrative checklist remains in [arm64-smoke-checklist.md](arm64-smoke-checklist.md); **always** prefix with `-p tennis` and loopback `WEB_PORT` on a shared host.

---

## 9. Deployment and rollback runbook (ordered)

1. **Confirm operator authorization** (deploy on this VM; hostname; port).  
2. **Record existing host state** (inventory §2); save redacted notes.  
3. **Verify backups** of *existing* apps (their owners); confirm disk headroom (go/no-go §4).  
4. **Verify source revision** `edab5e2…` (or newer authorized pin) via `git rev-parse` / `git ls-remote`.  
5. **Prepare isolated config**: `.env.production.tennis` (`chmod 600`), `COMPOSE_PROJECT_NAME=tennis`, `WEB_PORT=127.0.0.1:3010`, unique DB names, `TRUSTED_PROXIES`, `APP_HOST`.  
6. **Build/load ARM64 images** on the host (`$COMPOSE build`) — no registry publish unless authorized.  
7. **Start isolated database** `$COMPOSE up -d db`; wait healthy.  
8. **Run migrations** migrate profile once.  
9. **Start web and worker** `$COMPOSE up -d web worker`.  
10. **Localhost smoke** `curl http://127.0.0.1:3010/up`; worker health.  
11. **Configure HTTPS** (Option A preferred) without breaking other vhosts.  
12. **OTP + workflows** (§7–8).  
13. **Backup + disposable restore drill** for tennis only.  
14. **Monitor** tennis and existing workloads 24–48h before broad invites.  
15. **Authorize beta invitations** separately.

### Stop conditions

- Existing production app on the VM becomes unhealthy.  
- Host OOM / heavy swap / disk full.  
- Migrate fails; do not open TLS until fixed.  
- OTP or auth broken.

### Rollback

| Layer | Action |
|---|---|
| TLS only | Remove/disable tennis vhost; leave containers stopped or running on loopback |
| App | `$COMPOSE stop` or `$COMPOSE down` (**without** `-v` unless destroying tennis data is intended) |
| Image | Redeploy previous image digest **only if** schema compatible |
| Data | Restore tennis dumps into tennis volumes; **never** restore into another project’s DB |
| Schema | Forward migrations are not auto-reversible; incompatible rollback ⇒ restore from backup |

---

## 10. Operator decisions needed

1. Confirm deploy onto **this** existing A1 VM (shared).  
2. Public hostname for tennis (DNS).  
3. Loopback port if `3010` is taken.  
4. Reuse existing reverse proxy (A) vs alternative (B).  
5. `TRUSTED_PROXIES` values for that proxy hop.  
6. SMTP provider credentials (kept out of git/chat).  
7. Go/no-go after inventory numbers.  
8. Authorization to build images / start containers / change proxy.  
9. Authorization for beta user invites.

---

## 11. Remaining risks and blockers

| Risk / blocker | Notes |
|---|---|
| Unknown co-tenants | Inventory not yet run; budget may fail go/no-go |
| Shared 1 OCPU / 6 GB | Contention with existing Compose apps |
| Port / proxy collision | Must pick free loopback port and safe vhost add |
| Secrets handling | `.env.production.tennis` must never be committed |
| Migration irreversibility | Backup before migrate; restore is the real rollback |
| No native smoke yet | QEMU/CI ≠ Ampere runtime |
| DNS / TLS certs | Operator-owned |
| This plan is not authorization | Explicit go required for each destructive/live step |

---

## Local quality checks (planning session)

| Check | Result |
|---|---|
| Working tree clean | Yes (`edab5e2`) |
| `git ls-remote origin main` | Matches `HEAD` |
| `docker compose -f docker-compose.yml config` | Pass |
| Remote SSH / deploy / image publish | **Not executed** |
