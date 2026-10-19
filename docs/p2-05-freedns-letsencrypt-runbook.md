# P2-05 — FreeDNS, Nginx, Let's Encrypt Runbook

**Preparation only.** Do not install Certbot, issue certificates, modify live Nginx, change FreeDNS, or deploy containers until explicitly authorized.

| Item | Value |
|---|---|
| Hostname | `getcourt.zanity.net` |
| DNS | FreeDNS (afraid.org) |
| TLS | Let's Encrypt via Certbot |
| Proxy | Existing host Nginx (Ubuntu 24.04) |
| Upstream | `http://127.0.0.1:3010` (Compose project `tennis`) |
| Release candidate | `edab5e2a6f54d90e47b0f2c5cfb98ce0ae748cf9` |

Artifacts:

- Nginx template: [`deploy/nginx/getcourt.zanity.net.conf`](../deploy/nginx/getcourt.zanity.net.conf)
- Env template: [`deploy/env/tennis.production.example`](../deploy/env/tennis.production.example)
- Host inventory analysis: [p2-04-a1-host-assessment.md](p2-04-a1-host-assessment.md)

---

## 1. Rails / APP_HOST

In `.env.production.tennis` (on host when authorized):

```bash
APP_HOST=https://getcourt.zanity.net
RAILS_ALLOWED_HOSTS=getcourt.zanity.net
WEB_PORT=127.0.0.1:3010
```

**`APP_HOST` shape:** complete URL **with scheme** (`https://getcourt.zanity.net`). Not bare hostname alone.

| Consumer | Behavior |
|---|---|
| Action Mailer | Strips scheme → `default_url_options host` + `protocol: https` |
| `PublicAppHost` | Same normalization for invitation/result/community notification links |
| Telegram / some buttons | May use `APP_HOST` as a full URL string (scheme required) |
| `RAILS_ALLOWED_HOSTS` | Bare hostname only (`getcourt.zanity.net`) |

Also:

- `force_ssl` + `assume_ssl` → secure cookies; HTTPS URL generation behind Nginx when `X-Forwarded-Proto: https`
- Trusted proxies: Nginx → Rails on loopback; **default loopback trust is enough**
- Compose `WEB_PORT` is the **left side** of `ports:` (`host:port` or bare port). Use `127.0.0.1:3010`, never bare `3010` on a shared public host.

---

## 2. FreeDNS (afraid.org) — A/AAAA verification

Operator steps (manual console; not automated here):

1. Ensure FreeDNS record for `getcourt.zanity.net` points to this A1 public IP.
2. Prefer **A** record to the VM public IPv4. Add **AAAA** only if the VM has a stable public IPv6 you intend to serve.
3. Wait for FreeDNS approval / propagation if the zone requires it.
4. Verify from a separate network:

```bash
# Replace with public checks after DNS is live (do not leak IPs in tickets unnecessarily)
dig +short A getcourt.zanity.net
dig +short AAAA getcourt.zanity.net
# Expect the A1 public address(es) you configured — not an old/parked IP
```

5. Confirm FreeDNS TTL and that no conflicting CNAME remains.

**Stop:** Do not request Let's Encrypt until `dig` returns the correct A (and optional AAAA).

---

## 3. OCI ingress (TCP 80 / 443)

Host iptables already accepts NEW tcp/80 and tcp/443 (inventory). Still verify **OCI** path:

1. VCN → subnet → **Security List** and/or **NSG** on the VNIC.
2. Ingress: TCP **80** and **443** from `0.0.0.0/0` (and `::/0` if serving IPv6).
3. SSH (22) remains restricted as today.
4. Do **not** open Postgres or `3010` publicly.

Document the rule OCIDs / names in the operator notes (not in git).

---

## 4. Nginx virtual host

Templates:

- `deploy/nginx/getcourt.zanity.net.conf` — Phase A = ACME + 503 (no app proxy until TLS)
- `deploy/nginx/websocket_upgrade.conf` — `map` for `$connection_upgrade` (Phase B)

When authorized:

```bash
# Backup existing Nginx config first
sudo cp -a /etc/nginx /etc/nginx.bak.$(date -u +%Y%m%dT%H%M%SZ)

# WebSocket map (once)
sudo cp deploy/nginx/websocket_upgrade.conf /etc/nginx/conf.d/websocket_upgrade.conf

# ACME webroot
sudo mkdir -p /var/www/certbot
sudo chown www-data:www-data /var/www/certbot

# Install Phase A site — do not remove sites-enabled/default without review
sudo cp deploy/nginx/getcourt.zanity.net.conf /etc/nginx/sites-available/getcourt.zanity.net
sudo ln -sf /etc/nginx/sites-available/getcourt.zanity.net /etc/nginx/sites-enabled/getcourt.zanity.net

# Never reload on a failed test
sudo nginx -t && sudo systemctl reload nginx
```

Phase A does **not** proxy to Rails (avoids `force_ssl` redirect to HTTPS before certs exist). App smoke: `curl -fsS http://127.0.0.1:3010/up`.

---

## 5. Certbot (Let's Encrypt) — install & issue (authorized only)

Ubuntu 24.04 typical path:

```bash
sudo apt-get update
sudo apt-get install -y certbot python3-certbot-nginx
# Ensure DNS already points here, ports 80/443 open (OCI + host)
sudo certbot --nginx -d getcourt.zanity.net
# Or webroot:
# sudo certbot certonly --webroot -w /var/www/certbot -d getcourt.zanity.net
```

After success:

- Confirm HTTP → HTTPS redirect (Certbot usually inserts it; or enable Phase B in the template).
- `sudo nginx -t && sudo systemctl reload nginx`

### Renewal verification

```bash
sudo certbot renew --dry-run
# Confirm timer/service exists:
systemctl list-timers | grep -i certbot || true
ls /etc/cron.d/certbot 2>/dev/null || true
```

### Issuance failure recovery

1. Leave Phase A (HTTP ACME + 503) in place — do not enable HTTPS blocks without cert files.
2. Check `dig +short A getcourt.zanity.net` matches this VM.
3. Confirm OCI + host allow TCP 80.
4. `curl -sI http://getcourt.zanity.net/.well-known/acme-challenge/test` should not be answered by the wrong vhost (compare `server_name` / `default_server`).
5. Retry `certbot certonly --webroot -w /var/www/certbot -d getcourt.zanity.net` (isolates Nginx plugin edits).
6. Restore Nginx from `/etc/nginx.bak.*` if Certbot left a broken config; `nginx -t` before reload.
7. Rails on `127.0.0.1:3010` can stay up during cert recovery.

### Renewal troubleshooting

| Symptom | Checks |
|---|---|
| HTTP-01 fail | DNS A record, OCI 80 open, ACME location, not stolen by `default` |
| Renew dry-run fail | Disk space, `/etc/letsencrypt` perms, cert paths still referenced |
| Browser cert warning | Wrong `server_name`, incomplete chain, default site winning |
| Rails redirect loop | Missing `X-Forwarded-Proto https` on Phase B proxy |

Keep `/etc/nginx.bak.*` until a successful renew dry-run.

---

## 5b. Backups (staging — not production-ready until drilled)

| Item | Plan |
|---|---|
| Local staging | `/var/backups/tennis/` mode `700` |
| Command | `COMPOSE_PROJECT_NAME=tennis COMPOSE_FILE=docker-compose.prod.yml ENV_FILE=.env.production.tennis BACKUP_DIR=/var/backups/tennis ./script/backup-postgres.sh` |
| Retention | ≥ 7 daily + 4 weekly locally; **copy off-instance** (object storage / second host) |
| Restore drill | Separate project name (e.g. `tennis_restore`) + disposable volume / `docker-compose.fresh.yml` — never overwrite live `tennis` volumes on first try |
| Status | **Untested on this host** → do not treat as production-ready until one successful backup + disposable restore |

---

## 6. OTP / mailer hostname check (after app + SMTP up)

1. Request sign-in OTP to an operator mailbox.
2. Confirm links use `https://getcourt.zanity.net/...` (not localhost, getcourt.co, or gotcourt.sl8.net).
3. Confirm logs do not print OTP codes or SMTP passwords.

---

## 7. Ordered apply sequence (when authorized)

1. Confirm FreeDNS A/AAAA → this VM (`dig`).
2. Confirm OCI security list/NSG 80/443.
3. Backup `/etc/nginx`.
4. Add websocket map + `getcourt.zanity.net` HTTP site + ACME webroot; `nginx -t` / reload.
5. Bring up Compose `tennis` on `127.0.0.1:3010` (separate deploy auth).
6. Localhost: `curl -fsS http://127.0.0.1:3010/up`.
7. Install Certbot; issue cert for `getcourt.zanity.net`; enable HTTPS redirect.
8. `certbot renew --dry-run`.
9. External `https://getcourt.zanity.net/up` (or app root).
10. OTP mailer hostname check.
11. Create `/var/backups/tennis` (mode 700); run first tennis backup.

**Still not authorization** to invite beta users until product owner signs off.

---

## 8. Host capacity note (from sanitized inventory)

Inventory (`2026-10-16T16:08:19Z`): **4× aarch64**, **~23 GiB RAM** (~22 GiB available), **~35 GiB free** disk, **no running containers**, Nginx active on 80/443, **port 3010 free**, host firewall already allows 80/443.

Planning assumption of 1 OCPU / 6 GB is **below** observed capacity — favorable for tennis isolation. Gate details updated in P2-04 assessment.
