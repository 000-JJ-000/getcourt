# Tennis Platform — Documentation Pack
Status: architecture baseline v0.1, 2026-10-08. This package contains **documentation and Cursor instructions only**, not code changes. Extract at the root of your GetCourt fork; files land under `docs/project/`. Do not overwrite the upstream `AGENTS.md` without reviewing its scope restrictions.

## Reading order
1. `00-PROJECT-VISION.md`, `01-PRD.md`, `02-SRS.md`
2. `03-SYSTEM-ARCHITECTURE.md`, `04-DATABASE-DESIGN.md`, `05-API-SPECIFICATION.md`
3. `06-SECURITY-REQUIREMENTS.md`, `07-DEPLOYMENT-ARCHITECTURE.md`, `09-TEST-STRATEGY.md`
4. `08-IMPLEMENTATION-ROADMAP.md`, `10-DECISION-LOG.md`
5. `phases/PHASE-00-FOUNDATION.md`, `cursor/PHASE-00-CURSOR-PROMPT.md`

## Source inspection boundary
Source-level findings were gathered from the upstream GitHub repository (routes, Gemfile, database.yml, models list, migrations list, CI, sessions controller, and API/MCP docs). This was **not** a full repository audit or a successful build. Cursor must verify everything against the actual fork and report deviations. Do not treat proposed schema/API names as existing implementations.

## Workflow
ChatGPT owns specifications and review; Cursor owns code changes and execution; user approves merges and deployment. Cursor returns changed-file list, test results, blockers, security notes, and follow-up recommendations after each bounded assignment.
