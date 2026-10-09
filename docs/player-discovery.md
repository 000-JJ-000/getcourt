# Player discovery (P1-02)

Members-only directory at `GET /players`. Builds on [player profiles](player-profiles.md). No messaging, invitations, or matchmaking.

## Visibility rules

Included only when all are true:

- Viewer is authenticated
- Candidate is not the viewer
- `merged_at` is blank
- `telegram_generated_email` is false and `email` is present (community eligible)
- `profile_visibility` is `members` or `public` (`private` never listed)

Anonymous visitors are redirected to sign-in. Directory counts and empty states never distinguish “private exists” from “no match” — private rows are simply absent.

## Search filters

All optional and combinable:

| Param | Behavior |
| --- | --- |
| `selected_city_id` / `city_id` | Catalog city; matches `users.city_id` or case-insensitive `city_name` / aliases |
| `city_name` | Used when no catalog id; exact case-insensitive name match against the catalog, then users |
| `ntrp_min` / `ntrp_max` | Self-reported NTRP half-steps only; invalid values ignored; min/max swapped if reversed |
| `play_format` | `singles` or `doubles` (JSON contains) |
| `play_style` | `casual` or `competitive` (JSON contains) |

Invalid filter values are dropped (treated as unset). Queries are parameterized.

Availability day/period filtering is **not** implemented in MVP (JSON structure is not indexed for efficient containment at catalog scale).

## Location behavior

- Prefer results in the viewer’s city via sort (not a hard filter unless a city filter is set).
- City identity for a user:
  1. `city_id` when set (GeoNames catalog FK from the profile picker)
  2. else `city_name` string (legacy / free text) — directory matching uses case-insensitive equality and known catalog aliases when a city was picked
- No GPS, no invented distances, no PostGIS proximity.

## Sorting and pagination

Deterministic order:

1. Same city as viewer (`city_id` or case-insensitive `city_name`)
2. Profile completeness score (name, city, NTRP, preferences, availability)
3. Display name (lowercased)
4. `users.id`

Server-side pagination via Pagy (`20` per page). Relation-based — does not load all users into memory.

## Privacy guarantees

- No email, Telegram chat IDs, login codes, API tokens, or coordinates in HTML/JSON for the directory.
- Telegram handles are not shown on directory cards (profile page still respects `show_telegram_on_profile`).
- Avatars use `GET /users/:id/avatar` after the same visibility gate as profiles (members/public listed players are visible to signed-in members).
- Direct Active Storage blob URLs are not used for directory avatars.

## Known limitations

- No availability filter yet
- No radius / distance search
- Invitation picker (`GET /users/search`) is unchanged and separate from `/players`
- Coaches directory (`/coaches`) remains a separate, public coach listing
