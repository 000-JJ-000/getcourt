# Implementation Roadmap
All durations are rough single-workstream estimates, not commitments.

| Phase | Objective | Approximate duration | Exit gate |
|---|---|---|---|
| 0 | Postgres/PostGIS migration, Docker, baseline security | 1–3 weeks | Fresh install, tests, security checks, ARM64 smoke test |
| 1 | Identity, player profiles, discovery, API | 3–5 weeks | API contract and privacy tests |
| 2 | Invitations, result confirmation, ratings, messaging | 3–5 weeks | State machine/rating invariants tested |
| 3 | Flutter Android/iOS | 4–6 weeks | Device beta flows and push tests |
| 4 | Discord integration | 2–3 weeks | Scoped auth and privacy tests |
| 5 | Production beta/local launch | 2–3 weeks | Load, restore, monitoring, onboarding |

## Work management
Each phase is divided into reviewable Cursor tasks, one bounded change set at a time. No feature work until Phase 0 DB migration is stable; no public launch until authentication remediation and backup restoration pass.

## Cursor report format
Scope; files changed; architecture deviations; commands/tests executed with results; security implications; migration/rollback notes; unresolved blockers; suggested next bounded task.
