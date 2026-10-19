# P2-04 — Oracle A1 Read-Only Host Assessment

**Stop after assessment.** Capacity GO ≠ authorization to deploy.

| Item | Value |
|---|---|
| Hostname (P2-05) | `getcourt.zanity.net` |
| Compose project | `tennis` |
| Bind | `127.0.0.1:3010` |
| Release candidate | `edab5e2a6f54d90e47b0f2c5cfb98ce0ae748cf9` |
| Inventory | Sanitized paste `generated_utc=2026-10-16T16:08:19Z` |

Inventory script: [`scripts/ops/a1_host_inventory.sh`](../scripts/ops/a1_host_inventory.sh)  
TLS/DNS runbook: [p2-05-freedns-letsencrypt-runbook.md](p2-05-freedns-letsencrypt-runbook.md)

---

## Operator execution (recap)

```bash
bash scripts/ops/a1_host_inventory.sh | tee ~/a1-inventory.txt
```

Sanitize public IPs, domains, usernames before sharing.

---

## Sanitized inventory analysis

| Area | Status | Evidence |
|---|---|---|
| Architecture ARM64 | **PASS** | `uname_m=aarch64`, Docker `Arch=arm64` |
| Actual resources | **PASS** | `nproc=4`, MemTotal ~23 GiB, MemAvailable ~22 GiB (exceeds 1 OCPU / 6 GB plan) |
| Existing workload utilization | **PASS** | No running containers; loadavg ~0.08; idle host |
| Memory headroom | **PASS** | ~22 GiB available; no swap configured/used |
| Disk / inode headroom | **PASS** | `/` 45G, ~35G avail (23% used); inodes 6% |
| Port `3010` | **PASS** | `port_3010=NOT_SEEN_IN_LISTENERS` |
| Docker + Compose | **PASS** | Docker 29.9.1, Compose v5.6.0 |
| Reverse proxy | **PASS** | `nginx` active; listens 80/443; `sites-enabled/default` present — add tennis vhost carefully |
| Host firewall 80/443 | **PASS** | iptables/nft ACCEPT new tcp/80 and tcp/443 |
| OCI NSG / security list | **WARNING** | Not in inventory — verify in OCI console before Certbot |
| Conflicts with `tennis` | **PASS** | Empty `docker compose ls`; no containers |
| Backup destination | **WARNING** | `/var/backups` exists; `/var/backups/tennis` missing — create before first backup |
| FreeDNS / hostname | **UNKNOWN→ops** | Configure `getcourt.zanity.net` A/AAAA; verify with `dig` (P2-05) |

---

## Resource budget (measured)

Host is larger than the original Flex trial assumption. Still start conservative:

| Setting | Recommendation |
|---|---|
| `WEB_CONCURRENCY` | `1` |
| `RAILS_MAX_THREADS` | `3` |
| Solid Queue | Dedicated `worker`; `SOLID_QUEUE_IN_PUMA` empty |
| Postgres | Image defaults initially |
| Container mem limits | Optional; not required given ~22 GiB free |
| Monitor | MemAvailable &lt; 2 GiB sustained; disk &lt; 20% free; nginx 5xx; tennis health |

---

## Port and proxy

- **3010:** free — use `WEB_PORT=127.0.0.1:3010`
- **Nginx:** reuse (Option A); new `server_name getcourt.zanity.net`; do not blindly replace `default`
- **TLS:** Certbot + Let's Encrypt per P2-05 (not executed yet)

---

## Docker isolation

- Project `-p tennis` → volumes `tennis_*`, network `tennis_internal`
- No Compose projects currently running — low collision risk
- Distinct DB names in `.env.production.tennis`

---

## Deployment gate

### **CONDITIONAL GO** (capacity / host readiness)

Required axes for capacity GO:

| Requirement | Met? |
|---|---|
| ARM64 confirmed | Yes |
| Sufficient resources | Yes (4 CPU / ~23 GiB / ~35 GiB free) |
| No critical port conflicts | Yes (3010 free) |
| Docker + Compose compatible | Yes |
| Existing workloads protected | Yes (none running; Nginx present — protect `default` site) |
| Viable HTTPS approach | Yes (Nginx + Certbot plan) — **certs not issued yet** |
| Viable backup destination | Partial — create `/var/backups/tennis` |

**Conditions before deploy authorization:**

1. FreeDNS `getcourt.zanity.net` resolves to this VM (`dig`).  
2. OCI ingress 80/443 confirmed in console.  
3. Nginx backup + tennis vhost plan reviewed ([p2-05](p2-05-freedns-letsencrypt-runbook.md)).  
4. Explicit authorization to build/start Compose, change Nginx, run Certbot.

This **CONDITIONAL GO is not permission to deploy.**

---

## Recommended next steps

1. Review [p2-05-freedns-letsencrypt-runbook.md](p2-05-freedns-letsencrypt-runbook.md).  
2. Complete FreeDNS A record + OCI 80/443 check.  
3. Authorize deploy: Compose `tennis` + Nginx site + Certbot.  
4. OTP + backup drill + smoke; then authorize beta invites.
