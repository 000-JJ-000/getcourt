# Database Design and Migration Strategy
## Phase 0 objective
Replace SQLite with PostgreSQL and enable PostGIS **before** building new product features. No production data migration is assumed; if fork has real user data, stop and design an explicit transfer/validation plan.

## Existing baseline observed upstream
`config/database.yml` defines SQLite databases for primary, cache, queue, cable; models include User, Court, Game, Participation, Match, PlayerStatistic, FavoriteCourt, CourtSuggestion, and others. `Match` records are user-perspective outcomes; don't assume they can serve as canonical confirmed results. Existing migrations must be reviewed for SQLite-specific SQL, indexing and defaults.

## Recommended DB topology
One PostgreSQL server with logically separate Rails databases for primary, cache, queue, cable if compatible with Solid adapters; alternatively separate schemas only after verifying framework support. Provision PostGIS on the primary DB; extensions must be installed via migration or provisioning in reproducible manner. Avoid granting extension-creation superuser privileges to the runtime app account.

## Migration checklist
1. Inventory migration SQL and `schema.rb`/`structure.sql`, seeds, fixtures, DB-dependent gems, test setup.
2. Select compatible `pg`, PostGIS and `activerecord-postgis-adapter` versions based on actual Rails/Ruby lockfile; verify ARM64 images.
3. Implement PostgreSQL config for development/test/production and Solid components.
4. Enable PostGIS in primary DB; verify extension permissions and migration reproducibility.
5. Run `db:prepare`, migration from empty DB, tests, system tests, and security scanners.
6. Verify index behavior, case sensitivity, JSON queries, foreign keys, timestamps, uniqueness, and transaction semantics.
7. Document clean reset, backups, restores, connection pool sizes and operational maintenance.

## Proposed future entities (not Phase 0 migrations)
UserIdentity; PlayerProfile; PlayerAvailability; MatchInvitation; canonical MatchResult; MatchResultConfirmation; PlayerRating; RatingEvent; Conversation; Message; DeviceRegistration; DiscordIdentity; NotificationPreference. Inspect existing tables first and prefer extensions over duplicates.

## Spatial privacy
Store approximate player search coordinates derived from city/ZIP, not precise residence. Court locations may use precise public facility coordinates. Use geography columns/GiST indexes and ST_DWithin for distance queries; test miles-to-meters conversion and edge cases.

## Consistency
Rating updates must occur transactionally and idempotently after confirmation; use constraints/unique keys to prevent double application. Backups require PITR strategy or clearly documented daily recovery limits.
