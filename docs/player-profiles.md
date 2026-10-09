# Player profiles (P1-01)

Player profiles live on the existing `users` table. There is no separate `PlayerProfile` model.

## Fields

| Field | Purpose |
| --- | --- |
| `name`, `about_me`, `city_name`, `timezone`, `preferred_sports`, `skill_levels`, `coach` | Existing profile fields (unchanged semantics) |
| `city_id` | Optional FK to the GeoNames `cities` catalog when a city is picked |
| `ntrp_rating` | Nullable decimal, self-reported 1.0–7.0 in 0.5 steps |
| `play_formats` | JSON array: `singles`, `doubles` |
| `play_styles` | JSON array: `casual`, `competitive` |
| `availability` | JSON weekly structure (see below) |
| `profile_visibility` | `private` / `members` / `public` (default `members`) |
| `show_stats_on_profile` | Boolean (default `true`) |
| `show_telegram_on_profile` | Boolean (default `false`) |
| Active Storage `avatar` | Optional profile photo |

Legacy `skill_level` / `skill_levels` values are not rewritten. Existing ELO ratings on `player_statistics` are unchanged.

## NTRP

- Allowed values: `1.0`, `1.5`, … `7.0`, or unset.
- UI and public copy label ratings as **self-reported, not USTA-verified**.
- No verification boolean.

## Availability format

Small documented weekly structure only — no calendar sync:

```json
{
  "mon": ["morning", "evening"],
  "sat": ["afternoon"],
  "notes": "Usually free after 6pm"
}
```

- Days: `mon` … `sun`
- Periods: `morning`, `afternoon`, `evening`
- `notes`: optional string, max 200 characters
- Empty days may be omitted
- Invalid keys/periods are rejected

## Privacy defaults

- New and existing accounts default to `profile_visibility=members`, stats visible, Telegram hidden.
- `private`: owner only
- `members`: signed-in users
- `public`: anyone (still no email, auth IDs, coordinates, or Telegram unless opted in)
- Telegram-generated / email-less bot rows are not community-profile eligible and are not shown to others
- Non-public profiles set `noindex`

## Avatars

- Allowed types: JPEG, PNG, WebP; max 2 MB
- Optimized square variants generated via Active Storage / libvips
- Served through `GET /users/:id/avatar` after the same visibility checks as the profile page (no permanent public blob URLs for private photos)
- Default SVG avatar when none is attached

## Editing and viewing

- Edit: `/account/profile` (owner only)
- View: `GET /users/:id`
- Onboarding checklist encourages name, city, NTRP, preferences, and availability; dismissing remains available and incomplete profiles do not block the app
