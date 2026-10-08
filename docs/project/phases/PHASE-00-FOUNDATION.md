# Phase 00 — Foundation: PostgreSQL/PostGIS + Docker + Security
Status: READY FOR CURSOR REPOSITORY AUDIT; implementation contingent on actual fork inspection.

## Goal
Deliver a reproducible, secure Rails baseline running entirely on PostgreSQL/PostGIS and compatible with AMD64 development and ARM64 OCI deployment. No feature expansion in this phase.

## Task sequence (separate reviewable changes)
### P0-01 Audit and baseline
Inspect targeted files: Gemfile/Gemfile.lock, `.ruby-version`, `config/database.yml`, Rails env configs, `db/migrate/**`, `db/schema.rb` or `structure.sql`, `config/queue.yml`, `config/cable.yml`, `config/cache.yml`, `config/routes.rb`, `app/controllers/sessions_controller.rb`, `app/models/user.rb`, `.github/workflows/ci.yml`, existing deployment config and tests. Identify SQLite-specific SQL and existing Docker/deployment assets. Record baseline test results. **Do not modify files yet.**
### P0-02 PostgreSQL migration
Use compatible PostgreSQL adapter and PostGIS stack, replace SQLite across app and Solid adapters, update database config, migrations/schema handling, seeds/fixtures/tests. Avoid unrelated model refactors. Verify clean install and full tests. If migrating existing user data is required, stop for approved transfer plan.
### P0-03 Container infrastructure
Docker Compose development/staging; web/worker/postgres-postgis services; persistent volumes, health checks, secrets placeholders, ARM64/AMD64 build support. Validate runtime architecture and libvips/native gems.
### P0-04 Authentication blocker
Inspect all login/verification flows, eliminate email-only sign-in bypass, add regression tests; do not assume password/OAuth implementation belongs in Phase 0 unless needed to secure existing login. Coordinate full identity redesign with Phase 1.
### P0-05 CI, backup, operational readiness
CI PostgreSQL/PostGIS service, tests/scanners/multiarch checks; encrypted off-host backup instructions, restore drill, rollback and runbook. Avoid claiming production readiness without actual test evidence.

## Acceptance checklist
- [ ] PostgreSQL/PostGIS used in dev/test/staging; no SQLite dependency in runtime.
- [ ] Clean database provisioning and migrations succeed.
- [ ] Existing tests and scanners pass or deviations documented/approved.
- [ ] Solid Queue/Cache/Cable verified on PostgreSQL.
- [ ] ARM64 image boots and health endpoint responds.
- [ ] Authentication bypass regression test passes.
- [ ] Backup restore successfully demonstrated.
- [ ] Changed files and rollback instructions documented.

## Hard constraints
No unapproved rewrite; no production secrets; no destructive operations on existing user data; no exposure of PostgreSQL to Internet; no changes to upstream AGENTS.md without review; do not merge until review.
