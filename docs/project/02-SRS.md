# Software Requirements Specification (SRS)
## Functional requirements
- FR-001: Provide email/password registration, verified email, password reset, Google and Apple identity provider login.
- FR-002: Reject authentication lacking valid password/OTP/provider proof; require explicit secure account linking.
- FR-003: Provide authenticated profile CRUD and privacy preferences.
- FR-004: Search players by city/ZIP, adjustable radius, favorite courts, NTRP, singles/doubles preference, and availability.
- FR-005: Support player availability recurrence and time-zone-aware display.
- FR-006: Provide court directory, submission/correction, moderation, favorites.
- FR-007: Provide invitations, participation requests, approvals, cancellations, and match states.
- FR-008: Support canonical singles/doubles match results, confirmation, disputes, and immutable rating events.
- FR-009: Keep separate singles/doubles rating pools; never update on pending/disputed outcomes.
- FR-010: Provide authorized private messaging and blocking/reporting.
- FR-011: Deliver opted-in push/in-app notifications, deduplicated and retryable.
- FR-012: Expose versioned authenticated API for Flutter and Discord.
- FR-013: Support secure Discord account linking and scoped bot actions.
- FR-014: Provide account export/deletion and audit logs for sensitive operations.

## Nonfunctional requirements (initial targets; validate in testing)
- NFR-001: Deploy on ARM64 OCI 4 OCPU/24 GB and AMD64 development machines.
- NFR-002: PostgreSQL/PostGIS in all environments, no SQLite runtime fallback.
- NFR-003: Target p95 <=2 seconds for representative player/court searches at agreed 20–50 concurrent active clients; load-test before promising SLA.
- NFR-004: Target 99.5% monthly availability, with health checks and documented recovery.
- NFR-005: Encrypt HTTPS traffic; protect secrets; private DB network; role-based authorization and rate limits.
- NFR-006: Encrypted off-host backups, periodic restoration drill, RPO/RTO set before launch (proposal: RPO 24h, RTO 4h).
- NFR-007: Idempotent result confirmation, rating update, message/notification dispatch where applicable.
- NFR-008: Accessible mobile/web core workflows and consistent US timezone handling.
- NFR-009: Unit, request, system, migration, security, and multiarchitecture build checks in CI.
- NFR-010: Source of truth for code is user's fork; upstream changes are reviewed, not blindly merged.

## Release gates
Phase 0: Postgres migration + full tests + security remediation verified. Phase 1: secure identity and API contract tests. Phase 2: result/rating invariants. Phase 3: real-device tests. Phase 4: Discord authorization/privacy. Launch: backup restore and load test.
