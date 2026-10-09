# GetCourt

## Status

[![CI](https://github.com/denis1011101/getcourt/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/denis1011101/getcourt/actions/workflows/ci.yml)
![Coverage](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/denis1011101/72e5fc03477a6808b5feb024041ade22/raw/coverage.json)
![Ruby](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/denis1011101/72e5fc03477a6808b5feb024041ade22/raw/ruby.json)
![Rails](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/denis1011101/72e5fc03477a6808b5feb024041ade22/raw/rails.json)

Website: https://getcourt.co/

GetCourt is a simple app to bring together the community of people who play tennis.  
Create and join court games, manage courts, invite players, and receive Telegram reminders and notifications.

Main features
- Create and manage recurring or one-off games and trainings, with or without a coach
- Discover and open new local courts, suggest edits to the ones already listed
- Book slots ahead of an upcoming game and cancel them
- Run tournaments and collect match statistics that feed overall player ratings
- Search for coaches and launch player searches
- Find suitable opponents with AI-based matching, read scores off a photo of the scoreboard
- Share photos and clips from a game and follow the Tennis Life feed
- Telegram bot integration for notifications and registration tokens
- Mobile-friendly UI with map integration and simple search
- Public JSON API over upcoming games and an MCP server on top of it

Main technologies
- Ruby 4.0 / Ruby on Rails 8.1
- Hotwire (Turbo + Stimulus) for interactivity, Propshaft + importmap for assets
- Tailwind CSS for styling
- PostgreSQL with PostGIS (primary) plus separate logical DBs for Solid Cache / Queue / Cable
- Solid Queue / Solid Cache / Solid Cable for jobs, caching and websockets
- Active Storage with libvips for photos and clips
- RubyLLM (Gemini) for the AI features
- Google / Nominatim geocoding for addresses, Google Maps for the pickers
- Docker Compose for local PostgreSQL/PostGIS and optional app container

## Docker Compose (PostgreSQL/PostGIS)

**Local development** — copy `.env-example` to `.env`, then:

```bash
docker compose up -d db          # PostGIS only (use with local Ruby via bin/dev)
docker compose up --build        # web + database (db:prepare on start)
docker compose --profile worker up -d   # optional dedicated Solid Queue worker
docker compose down              # stop; data kept in the postgres_data volume
```

**Production-oriented stack** (web + worker + PostGIS, no public DB port):

```bash
cp .env.production.example .env.production   # fill required secrets
docker compose -f docker-compose.prod.yml --env-file .env.production up -d db
docker compose -f docker-compose.prod.yml --env-file .env.production --profile migrate run --rm migrate
docker compose -f docker-compose.prod.yml --env-file .env.production up -d web worker
curl -fsS http://127.0.0.1:3000/up
```

Four logical databases live on one Postgres server: primary (PostGIS), cache, queue, and cable.

Full ops guide (secrets, reverse proxy, backups, AMD64/ARM64 builds): [docs/deployment.md](docs/deployment.md).  
Oracle Ampere A1 runbook + native smoke: [docs/runbook-oracle-arm64.md](docs/runbook-oracle-arm64.md), `script/arm64-smoke.sh`.

## Public API and MCP

Upcoming games are readable from outside the app in two ways:

- `GET /api/v1/games` and `GET /api/v1/games/:id` — public JSON, no key needed
- `POST /mcp` — an MCP server (JSON-RPC 2.0 over Streamable HTTP) with `search_games` and
  `get_game` tools; the handshake and `tools/list` are open, tool calls need a bearer token
  (a personal one from *Account → Security*, or the shared `MCP_TOKEN`)

Both are read-only and expose only what a game page already shows in public. See
[docs/api-and-mcp.md](docs/api-and-mcp.md) for parameters, examples and limits, or the same
documentation for users at [getcourt.co/api-and-mcp](https://getcourt.co/api-and-mcp).

## Authentication

Sign-in is passwordless email OTP (no passwords, no OAuth in this flow):

1. Enter email on `/sign_in`
2. Receive a 6-digit code (10-minute TTL; digest-only storage)
3. Submit the code on `/sign_in/verify`
4. Session is established only after a successful verify (absolute 30-day lifetime from sign-in)

**Development:** Action Mailer writes messages under `tmp/mails` (see `config/environments/development.rb`). Open the latest file to copy the code. System tests need the `development` Docker image (includes Chromium).

**Production:** Configure SMTP with `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` (see `.env.production.example`). `RESEND_API_KEY` may substitute for `SMTP_PASSWORD` when using Resend SMTP. Delivery failures do not authenticate the user. Production never uses file-based delivery.

Telegram WebApp auth remains a separate path for the bot mini-app (signed `initData`, short TTL, replay cache).

## Tests and coverage

```bash
bin/rails test          # unit, model and controller tests
bin/rails test:system   # system tests, needs Chrome
bin/rubocop             # style, same as CI
```

Coverage is generated during Minitest runs and saved to `coverage/summary.txt`.

## License

This project is licensed under the **Apache License 2.0**.  
See the [LICENSE](LICENSE) file for details.

**Note on Trademarks:**  
The "GetCourt" name, logo, and associated branding are trademarks of the project author. 
While the code is open source, this license **does not** grant permission to use these trademarks 
to endorse or promote products derived from this software without prior written permission.
