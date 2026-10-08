# Cursor Assignment — P0-01 Repository Audit (Paste into Cursor)
You are working in my **fork** of GetCourt. Read `docs/project/README.md`, `phases/PHASE-00-FOUNDATION.md` (relative to `docs/project/`), and the repository's existing root `AGENTS.md` first. The root AGENTS.md requests smallest diff, targeted file inspection, and explicit confirmation before multi-file changes. Respect it.

**Task: P0-01 audit only. DO NOT MODIFY CODE YET.**

Objective: prepare the smallest safe implementation plan to migrate the existing Rails app and Solid Queue/Cache/Cable from SQLite to PostgreSQL/PostGIS, deploy with Docker Compose on ARM64 Oracle Ampere A1 and AMD64 dev, and remediate the suspected email-only sign-in bypass.

Inspect only the relevant files named in `docs/project/phases/PHASE-00-FOUNDATION.md` and directly required dependencies. Verify exact Rails/Ruby versions, existing Docker assets, PostgreSQL compatibility, SQL portability, schema format, CI/test setup, existing data transfer needs, and authentication code paths. If a wider scan is necessary, request permission first. Run non-destructive baseline tests if environment permits. Do not reset any existing databases.

Return:
1. Findings with exact file paths and line numbers.
2. Confirmed versus suspected risks, especially `SessionsController` verification bypass.
3. Proposed precise file change list for P0-02 and any prerequisites.
4. PostgreSQL/PostGIS image and adapter compatibility plan (including ARM64).
5. Tests and verification commands; note tests not run.
6. Rollback and data preservation strategy.
7. Questions requiring owner approval before editing.

Do not implement until I approve the file list and plan. Do not use shared MCP credentials for write operations. Do not add product features or reorganize Rails root in this assignment.
