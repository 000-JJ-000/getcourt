# Architecture and Product Decision Log
| ID | Decision | Alternative | Rationale / status |
|---|---|---|---|
| D01 | Extend GetCourt fork | Rewrite | Reuse scheduling, courts, tournaments, player foundations; confirmed |
| D02 | Rails modular monolith | Microservices | Simplicity at 100–500 users; recommended |
| D03 | Hotwire web | React rewrite | Preserve existing investment; recommended |
| D04 | Flutter mobile | React Native/native separate | Shared Android/iOS client; recommended, pending final acceptance |
| D05 | TypeScript Discord bot | Bot embedded in Rails | Separate lifecycle and API-only access; recommended |
| D06 | PostgreSQL + PostGIS now | SQLite initially | Concurrency, spatial queries, avoid later migration; confirmed |
| D07 | Docker Compose on OCI ARM64 | Kubernetes | Fits existing 4 OCPU/24 GB instance; confirmed |
| D08 | Email/password, Google, Apple | Discord-only/passwordless | Accessible onboarding; confirmed |
| D09 | City/ZIP + radius + favorite courts | Precise GPS home | Discovery and privacy; confirmed |
| D10 | NTRP + dynamic singles/doubles ratings | Single rating | Flexible recreational/competitive use; confirmed |
| D11 | Opponent-confirmed results | Self-reported immediate update | Rating integrity; confirmed |
| D12 | Free accounts, premium later | Paid MVP | Adoption first; confirmed |
| D13 | Cursor implements; ChatGPT specifies/reviews | ChatGPT code changes | User-selected workflow; confirmed |

## Unresolved decisions
Exact rating algorithm and doubles confirmation quorum; Flutter final confirmation; Postgres DB topology based on Rails adapter constraints; upstream compatibility policy; data retention; off-host backup destination; project name/branding; mobile store accounts and push provider credentials.
