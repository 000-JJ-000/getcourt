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

## Additional review
Check upstream Telegram auth, MCP tokens, account merge, media uploads, webhooks, SSRF/geocoding, moderation endpoints, public API PII, CORS and dependency CVEs. No assertion that these are vulnerable without evidence.
