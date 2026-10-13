# GetCourt Beta Readiness (P1-07)

Status: implementation complete for controlled beta (~25–50 players). No public deployment or git push without explicit authorization.

## Supported features (Phase 1)

- Email OTP registration / sign-in
- Player profiles, avatars, directory (`/players`) with visibility controls
- Peer match invitations, scheduling, invite-only private games, cancel
- Match result submit → peer confirm/dispute; competitive stats + hours only when confirmed
- Public communities (open or approval join), private communities (invitation only)
- Community game create/link (non–invite-only), board listing
- Notifications via existing `NotificationDelivery` + Solid Queue
- Telegram bot (existing), public games API / MCP (existing)

## Explicitly out of scope

- Ladders, tournaments (UI may still exist from legacy GetCourt — not beta-supported workflows)
- General messaging / chat
- New frontend frameworks
- Paid infrastructure

## Statistics consistency rule

| Result state | Competitive W/L/games/ELO | Match-linked hours on `PlayerStatistic` |
|---|---|---|
| Pending (invite-only peer) | No | No (hours may sit on `Match#stats` only) |
| Disputed | No | No (unwind if previously confirmed) |
| Confirmed | Yes | Yes |
| Corrected (re-submit while pending) | Still no until confirm | Still no until confirm |
| Open / legacy auto-confirm | Yes (immediate) | Yes |
| Canceled game | No new results | Existing confirmed rows unchanged unless removed by sync |

Activity / playing hours are **verified competitive hours**, not unverified participation. Label in product copy should not imply “time on court” from pending scores.

Prefer re-credit from `Match` rows (`credit_confirmed_match!`) over irreversible incremental bumps.

## Private community invitations

- Owners/moderators invite a specific eligible player (`POST /communities/:id/invite`).
- Only the invitee may accept/decline; managers may revoke.
- Pending invitations expire (default 14 days); `ExpireCommunityInvitationsJob` hourly in production recurring schedule.
- Unique pending pair `(community_id, invitee_id)`.
- Private communities are **not** visible by URL alone; possession of the URL does not grant membership.
- Public open / approval membership flows unchanged.

## Community-first game creation

- Active members: **Create a game** → `games#new` with `community_id` preassociated when authorized.
- Existing link-existing-game flow retained.
- Invite-only peer matches never appear on the community board and cannot be linked.
- Members are not auto-enrolled into the new game.

## Security assumptions

- Authorization is enforced in controllers/services (not UI alone).
- Rack::Attack throttles (Solid Cache in production): login OTP, match invitations, community join requests, community invitations.
- Trusted proxies: **loopback only** by default; set `TRUSTED_PROXIES` (or opt-in `TRUST_PRIVATE_NETWORK_PROXIES=1` when justified). See [deployment.md](deployment.md).
- OTP codes must not appear in application logs.
- Avatars / profiles respect visibility; private profiles stay off the directory.

## Operational dependencies

Documented in [deployment.md](deployment.md) and [runbook-oracle-arm64.md](runbook-oracle-arm64.md):

- Secrets: `SECRET_KEY_BASE`, DB password, `APP_HOST`, SMTP (`SMTP_*` or Resend)
- Four logical DBs: primary, cache, queue, cable — backup/restore together
- Solid Queue worker + recurring tasks (`config/recurring.yml`)
- Image processing: libvips in the production image
- Health: web `/up`; worker healthcheck in Compose

### PostGIS schema-dump workaround

Still required: `lib/tasks/schema_postgis.rake` strips tiger/topology/`fuzzystrmatch` extension lines from `db/schema.rb` after dump so clean `db:schema:load` does not fail. Re-evaluate only if the PostGIS image stops enabling those extensions or the project switches to `structure.sql`.

## Manual test checklist

1. Register two users via OTP; complete profiles; appear in `/players`.
2. A invites B; B accepts; schedule / create invite-only game; submit + confirm result; stats + match history update.
3. Doubles: capacity 4; only approved participants; confirm result; stats consistent.
4. Public community: request → approve → member creates community game → others see board and can join game via normal participation.
5. Private community: stranger 404 on URL; invite → accept; revoke/expire paths; duplicate invite rejected.
6. Mobile (~360–412px): registration, profile, directory, invitations, score entry, communities — no clipped primary CTAs.

## ARM64 smoke (native vs QEMU)

| Check | QEMU/buildx (CI laptop) | Native Ampere A1 |
|---|---|---|
| Multi-arch image build | Yes | Optional |
| Runtime smoke (`script/arm64-smoke.sh`) | **Not sufficient** | **Required** |
| PostGIS init + migrate | Emulated OK for compile | Required on host |
| OTP email, avatars/libvips, jobs | Spot-check if possible | Checklist on host |
| Backup/restore | Optional | Required before beta data |

Do not provision Oracle infrastructure without authorization.

## Performance baseline (25–50 → 100–500)

- Directory and community membership queries: indexed FKs (`community_memberships`, invitations pending unique); watch N+1 on show pages (memberships include `:user`).
- Match history: scoped to participant; fine at beta scale.
- Notification jobs: Solid Queue; avoid fan-out storms (community game announce iterates active members — OK under 500).
- No new caches/infra required for beta.

## Quality gates (run before beta)

```bash
bin/rails db:test:prepare test test:system
bin/rubocop
bin/brakeman --no-pager
bin/importmap audit
bundle audit check --update   # if bundler-audit installed
docker compose -f docker-compose.prod.yml config
```

Record pass/fail in the P1-07 report; do not skip or weaken failures.

## Rollback / restore

1. Stop web/worker; keep DB volume.
2. Restore all four DBs from encrypted off-host backup (`script/restore-postgres.sh` into a drill target first).
3. Redeploy previous image tag; run migrations only forward — prefer restore over down-migrate for beta.
4. Invalidate sessions if `SECRET_KEY_BASE` rotated.

## Quality-gate results (2026-10-13, Docker `web` + local Compose)

| Gate | Result |
|---|---|
| `bin/rails db:test:prepare test` | Pass — 1558 runs, 0 failures |
| `bin/rails test:system` | Pass — 30 runs, 0 failures |
| `bin/rubocop` | Pass (after trailing-blank fix on `Match`) |
| `bin/brakeman --no-pager` | 1 medium SQL warning — pre-existing `Players::DirectoryQuery` `Arel.sql` order (viewer city id/`quote`d name; constants for completeness/name). Not introduced by P1-07. |
| `bin/importmap audit` | Pass — no vulnerable packages |
| `bundler-audit` | Not installed in image |
| `docker compose … config` | Dev quiet OK; prod + fresh OK with CI-style env |
| AMD64/ARM64 image build | Not re-run locally this session (CI workflow exists; QEMU ≠ native) |
| Native ARM64 smoke | **Blocked** — no deploy authorization |

## Outstanding blockers

- [x] Full test suite green on this branch
- [ ] Native ARM64 smoke on authorized host
- [ ] SMTP provider verified for OTP delivery in target environment
- [ ] Operator confirms `TRUSTED_PROXIES` / reverse-proxy chain for the chosen host
- [ ] Explicit authorization to push / deploy

## Phase 2 priorities (recommended)

1. Native ARM64 production smoke + monitored first cohort
2. Stronger abuse signals (report user, invitation opt-out analytics)
3. Community discoverability polish (city filters, soft caps)
4. Deterministic stats recalculation admin/rake for disputed corrections at scale
5. Only then: ladders / structured competition (explicit product decision)
