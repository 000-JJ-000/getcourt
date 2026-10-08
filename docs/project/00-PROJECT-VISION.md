# Project Vision
Build a local-first tennis community product by extending an Apache-2.0-licensed GetCourt fork. Serve recreational and competitive players, initially 100–500 registered users with a smaller invite-only beta. Responsive web first, followed by shared Flutter Android/iOS clients and an optional interactive Discord bot.

## Core proposition
Make it easy to find compatible tennis players, locate courts, schedule matches, communicate privately, and track trustworthy singles/doubles performance. Free player accounts; optional premium features later, **not** part of MVP.

## Constraints
Production: existing Oracle Cloud Ampere A1 ARM64 VPS, 4 OCPUs, 24 GB RAM; Docker Compose. Development on local Docker; images must support ARM64 and AMD64. PostgreSQL/PostGIS from Phase 0. Rails remains authoritative backend; web remains Hotwire; Flutter and Discord use authenticated APIs.

## Non-goals (MVP)
No subscriptions/payments, club billing, AI-required workflows, elaborate microservices, or independent rating logic in clients. Existing optional GetCourt AI/Telegram features may be retained, disabled, or isolated after audit; avoid breaking functionality without a decision.

## Success criteria (proposed, validate)
25–50 beta testers, 100–500 registered at local launch, p95 common searches under 2s at agreed test load, 99.5% monthly service availability target, successful encrypted backup restoration, zero known critical auth bypasses at launch.
