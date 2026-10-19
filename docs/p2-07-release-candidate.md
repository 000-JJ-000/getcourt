# P2-07 — Release Candidate Finalization

**Stop before creating the commit unless explicitly authorized.**  
No push, deploy, Certbot, or Oracle host changes.

Base (current `HEAD` / live `origin/main`): `edab5e2a6f54d90e47b0f2c5cfb98ce0ae748cf9`

---

## Staged-file manifest (proposed)

Exact paths to include in the release commit (in this order is fine; one commit):

### Application (URL generation)

1. `app/services/public_app_host.rb` *(new)*
2. `app/services/communities/notifier.rb` *(modified)*
3. `app/services/match_invitations/notifier.rb` *(modified)*
4. `app/services/match_results/notifier.rb` *(modified)*
5. `test/services/public_app_host_test.rb` *(new)*

### Deploy artifacts

6. `deploy/env/tennis.production.example` *(new)*
7. `deploy/nginx/getcourt.zanity.net.conf` *(new)*
8. `deploy/nginx/websocket_upgrade.conf` *(new)*

### Ops / docs (P2-03 … P2-07)

9. `scripts/ops/a1_host_inventory.sh` *(new)*
10. `docs/p2-03-existing-a1-deployment-plan.md` *(new)*
11. `docs/p2-04-a1-host-assessment.md` *(new)*
12. `docs/p2-05-freedns-letsencrypt-runbook.md` *(new)*
13. `docs/p2-05-final-validation.md` *(new)*
14. `docs/p2-06-production-readiness-gate.md` *(new)*
15. `docs/p2-07-release-candidate.md` *(new — this file)*

### Explicitly exclude

- `.env.production`, `.env.production.tennis`, any real SMTP/`SECRET_KEY_BASE` values  
- `*.pem`, `/etc/letsencrypt/**`, private keys  
- `log/`, `tmp/`, `coverage/`, Docker volumes  

---

## Diff review

| Change | Assessment |
|---|---|
| Three notifier `detail_url` methods | Intentional — use `PublicAppHost.url_options` instead of raw `APP_HOST` as `host:` |
| `PublicAppHost` | Intentional — strips scheme for Rails url_helpers |
| Deploy Nginx/env | Intentional — `getcourt.zanity.net`, Phase A without certs |
| Docs/scripts | Intentional — P2-03…P2-07 planning & ops |
| Credentials in diff | **None** — env example has empty `SECRET_KEY_BASE` / `DATABASE_PASSWORD` / `SMTP_PASSWORD` |
| Certificates / private keys | **None** in proposed tree |
| Accidental drive-by | **None** observed |

Hostname: production deploy artifacts use **`getcourt.zanity.net` only** (`gotcourt.sl8.net` only in historical rename notes).

---

## Validation results

| Check | Result |
|---|---|
| P2-03…P2-06 artifacts present | **PASS** (listed above; + this P2-07 doc) |
| Hostname `getcourt.zanity.net` | **PASS** |
| `APP_HOST=https://getcourt.zanity.net` | **PASS** (scheme required; mailer/`PublicAppHost` strip) |
| `PublicAppHost` implementation | **PASS** (static review) |
| `test/services/public_app_host_test.rb` | **UNTESTED** — Docker daemon unavailable this session |
| Compose `tennis` + `WEB_PORT=127.0.0.1:3010` | **PASS** (`host_ip: 127.0.0.1`, published `3010`, no Postgres host ports) |
| Nginx HTTP-only Phase A | **PASS** — ACME + 503; no active `listen 443` / cert paths required |
| Four-DB backup docs | **PASS** — `script/backup-postgres.sh` dumps primary/cache/queue/cable; runbook §5b documents staging, off-instance copy, disposable restore |
| Live remote SHA | Matches `edab5e2` |

---

## Proposed release commit message

```
feat(infra): finalize A1 tennis RC for getcourt.zanity.net

Add deploy templates (Nginx Phase A, env example), PublicAppHost URL
normalization for notifications, host inventory script, and P2-03–P2-07
ops docs so the Oracle A1 first deploy is reproducible from git.
```

---

## Remaining blockers (post-commit)

1. Operator FreeDNS `dig` for `getcourt.zanity.net`  
2. OCI ingress 80/443  
3. Authorize push + host checkout  
4. Authorize remote Nginx / Certbot / Compose  
5. Run `public_app_host_test` when Docker/Ruby available  
6. Native ARM64 smoke + backup/restore drill  
7. Separate beta invite approval  

---

## Recommendation: **SAFE TO COMMIT** (locally)

The proposed file set is coherent, contains no secrets/certs, and is required for a reproducible RC beyond `edab5e2`.

**Do not commit until the project owner explicitly authorizes.** After authorization, stage only the manifest paths above, then create the commit (still no push unless separately authorized).
