# API Specification — Contract Plan
Status: planned; **not an implemented OpenAPI contract**. GetCourt currently documents read-only public `GET /api/v1/games` and `GET /api/v1/games/:id`; `/mcp` exposes read-only game tools. Preserve compatibility where feasible.

## Conventions
Prefix `/api/v1`; JSON over HTTPS; authenticated endpoints use revocable, scoped credentials; pagination, filtering, versioned errors, request IDs, explicit 401/403/404/409/422/429 behavior; rate limits and idempotency keys for mutations. Public endpoints expose only approved public data.

## Candidate endpoints (subject to repository audit)
| Method | Route | Purpose |
|---|---|---|
| POST | `/api/v1/auth/sessions` | Session/token creation via verified credentials |
| DELETE | `/api/v1/auth/sessions/current` | Revoke session |
| GET/PATCH | `/api/v1/me` | Read/update private profile |
| GET | `/api/v1/players` | Filtered privacy-safe discovery |
| GET | `/api/v1/courts` | Court discovery by distance/preferences |
| GET/POST | `/api/v1/availability` | Recurring availability |
| GET/POST | `/api/v1/match-invitations` | Browse/create invitations |
| POST | `/api/v1/match-invitations/{id}/requests` | Request participation |
| POST | `/api/v1/matches/{id}/results` | Submit score |
| POST | `/api/v1/matches/{id}/confirmations` | Confirm/dispute result |
| GET | `/api/v1/ratings/me` | Singles/doubles ratings/history |
| GET/POST | `/api/v1/conversations` | Private conversations |
| GET/POST | `/api/v1/conversations/{id}/messages` | Messages |
| POST | `/api/v1/device-registrations` | Register push token |
| POST | `/api/v1/integrations/discord/link` | Secure account linking |

## Required policy decisions
Define OAuth/OIDC flow, token lifecycle, refresh strategy, CSRF boundaries for web, CORS allowlist, and whether Discord uses service-to-service token exchange or delegated user tokens. Never use a shared MCP token for player write actions.

## Cursor deliverable
Create machine-readable OpenAPI contract after model audit and before implementing mobile endpoints; add request/response contract tests and example error payloads.
