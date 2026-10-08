# Security Requirements and Launch Blockers
## Verified source-level concern
Upstream `app/controllers/sessions_controller.rb` conditionally calls `sign_in(user)` when `user.require_verification?` is false, after looking up or creating the account by email. The `check` action also permits sign-in without a valid code in that case. Treat as **potential authentication bypass** pending full-flow verification. **Do not expose the fork publicly until fixed and regression-tested.**

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
