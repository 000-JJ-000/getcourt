# Security Requirements and Launch Blockers
## Verified source-level concern (remediated in P0-04)
Previously `SessionsController` signed users in when `require_verification` was false (email-only bypass). **P0-04** replaced this with passwordless email OTP: `EmailLoginChallenge` + `Sessions::EmailLogin`, digest-only codes, 10-minute TTL, session-bound challenges, rate limits, session rotation, and absolute 30-day session lifetime. `require_verification` no longer affects web login. Telegram WebApp auth validates HMAC `initData`, enforces freshness + replay cache, and rotates the session. Do not expose publicly until regression tests for this milestone pass in CI.

## Mandatory controls
- Every login requires proven ownership: password hash, valid expiring single-use code, or verified Google/Apple provider assertion.
- Never merge identities on matching email alone; require proof of both accounts and explicit linking.
- Session rotation on login, logout/revocation, rate limiting, credential recovery and account enumeration defenses.
- Authorization policies on every user-owned or private API resource; tests for IDOR and blocked-user rules.
- Store secrets outside repo, rotate credentials, use TLS and secure cookies/tokens, no public database port.
- Separate Discord bot credentials, minimum scopes, verified linking, no private data in public channel responses.
- No sensitive data in logs; audit security-sensitive changes.
- Moderation/reporting, privacy-safe geolocation, data export and deletion.
- Dependency vulnerability scanning, Rails Brakeman, CI secret scanning, image scanning.
- Backups encrypted, off-host, restore-tested; principle of least privilege for PostgreSQL runtime role.

## Phase 0 remediation tests
- Account with verification disabled cannot sign in by submitting only an email.
- New email cannot create authenticated session without proof.
- Invalid/expired/replayed codes fail.
- Existing valid authentication paths work after remediation.
- Session fixation, CSRF, login throttling, and reset flows are reviewed.
- Test suite and security scanners pass or all exceptions are explicitly documented.

## Match invitations & coordination (P1-03 / P1-04)
- Peer invitations require authentication; only inviter/invitee can view details; only invitee accept/decline; only inviter cancel.
- Schedule propose/confirm is limited to invitation participants; only the non-proposer may confirm; stale `proposal_updated_at` tokens are rejected.
- Targeting private, ineligible, opted-out, or self accounts is rejected; forged court IDs must resolve via `Court.visible_to`.
- Peer games set `invite_only` and are excluded from public games index / API `publicly_visible`.
- Create is rate-limited (Rack::Attack + pending-per-sender cap). See `docs/match-invitations.md`.
- Active Storage signed routes deny `User` avatar blobs unless the session viewer passes `profile_visible_to?`.

## Player discovery (P1-02)
- `GET /players` requires authentication. Private and community-ineligible accounts are excluded from the relation before pagination; counts do not reveal their existence.
- Filter parameters cannot broaden visibility beyond `members`/`public` eligible rows.
- Directory cards omit email, Telegram, tokens, and coordinates. See `docs/player-discovery.md`.

## Player profile privacy (P1-01)
- Only the account owner may update profile fields via `/account/profile`.
- Profile visibility: `private` (owner), `members` (authenticated), `public` (anonymous). Default is `members`.
- Public HTML never includes email, login codes, Telegram chat IDs, or exact coordinates. Telegram handles appear only when `show_telegram_on_profile` is enabled.
- Avatars stream through `UsersController#avatar` after the same visibility gate; do not rely on permanent public blob URLs for private photos.
- Telegram-generated email accounts are not community-profile eligible and must not be discoverable via `/users/:id`.
- See `docs/player-profiles.md`.

## Additional review
Check upstream Telegram auth, MCP tokens, account merge, media uploads, webhooks, SSRF/geocoding, moderation endpoints, public API PII, CORS and dependency CVEs. No assertion that these are vulnerable without evidence.
