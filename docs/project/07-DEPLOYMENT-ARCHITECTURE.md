# Deployment Architecture
## Target
Local Docker Compose for development; Oracle Cloud Ampere A1 ARM64 (4 OCPUs, 24 GB RAM) for production. Build/test both `linux/amd64` and `linux/arm64` images. No Kubernetes required.

## Containers
- Caddy: TLS/reverse proxy, HTTP security headers, routing.
- Rails web: Puma, domain/API/web controllers.
- Rails worker: Solid Queue background processing.
- PostgreSQL/PostGIS: private internal Docker network, persistent durable volume.
- Discord bot: later phase, independent container and limited API credentials.

## Operational requirements
- Pin images by version/digest; reproducible builds, image health checks, startup readiness and graceful shutdown.
- DB not bound to public host interface. Separate app runtime DB role from migration/extension provisioning role.
- `.env.example` with placeholders only; use secret injection, never commit real secrets.
- Explicit PostgreSQL backups (e.g., `pg_dump` plus optional WAL/PITR plan), encrypted and stored off VPS; test restoration.
- Logs, resource monitoring, DB connection limits, disk usage and alerts; retain deployment rollback procedure.
- Keep production database and uploaded media persistent across releases.
- Verify libvips and Ruby native gems on ARM64; verify compatible PostGIS images.
- Proposed initial resource ceilings: PostgreSQL 2–4 GB, Rails web ~4 GB, worker ~2 GB, Discord ~1 GB; measure rather than hard-code before testing.

## Deployment stages
Developer workstation -> CI -> private staging on OCI -> security/performance validation -> invite-only beta -> public local launch.
