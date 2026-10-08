# Test Strategy
## Baseline
Run upstream CI equivalents: `bin/rails db:test:prepare test test:system`, `bin/rubocop`, `bin/brakeman --no-pager`, `bin/importmap audit`, and `bin/rails zeitwerk:check` where supported. Capture baseline failures separately from changes introduced by migration.

## Phase 0
- Clean PostgreSQL/PostGIS install from zero volumes; migrations succeed.
- Existing test and system suites pass against PostgreSQL.
- Verify unique indexes, transactions, foreign keys, JSON behavior, date/time handling, case sensitivity.
- Verify Rails/worker/Solid Cache/Solid Cable boot and use PostgreSQL.
- Multiarch Docker build and ARM64 runtime smoke test.
- Verify no SQLite connections or files required at runtime.
- Auth bypass regression tests and secure session tests.
- Backup, restore, and restart persistence drill.

## Later phases
- API contract tests, authZ/IDOR, pagination and rate limits.
- Property tests for rating updates, idempotency, result dispute/confirmation races.
- Location precision/privacy tests and distance edge cases.
- Messaging authorization, blocking, notification deduplication.
- Flutter real-device smoke tests; Discord channel privacy and scoped credentials.
- Representative 20–50 concurrent-client load testing; measure p95 latency, DB contention, error rate.

## Quality gate
No phase accepted on unverified assertions. Cursor must include actual command outputs or concise summaries, environment details, and explicit skipped tests.
