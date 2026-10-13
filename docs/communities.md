# Local tennis communities (P1-06)

Lightweight local groups for discovering players and organizing games. No chat, ladders, tournaments, or paid membership.

## Model

- `communities`: name, slug, description, city/city_name, creator, visibility (`public`|`private`), membership_policy (`open`|`approval`), optional NTRP range and play focus
- `community_memberships`: user, role (`owner`|`moderator`|`member`), status (`active`|`pending`|`removed`)
- `games.community_id` optional FK

## Visibility

- Directory `/communities` lists **public** communities only (members-only auth)
- Private communities: visible to active/pending members, creator, admin
- Member directory respects `User#profile_visible_to?` (no email/Telegram leaks)

## Membership

| Action | Who |
| --- | --- |
| Join open / request approval | Authenticated visitor of a visible community |
| Approve/decline requests | Owner or moderator |
| Remove member | Owner or moderator (owners protected) |
| Promote/demote/transfer | Owner (or admin) |
| Leave | Active member; sole owner must transfer first |

Uniqueness on `(community_id, user_id)`; transitions use locks.

## Community games

Members may link their own non–invite-only games. Linking does not enroll other members. Invite-only peer matches never appear on the community board. Game visibility rules still apply.

## Notifications

`CommunityNotifyJob` → `Communities::Notifier` for join requests, approvals, and game announcements via `NotificationDelivery`.

## Statistics confirmation (P1-05 closure)

Pending/disputed peer results do not change competitive W/L/games or ELO; confirmation credits counters then replays ELO. See `docs/match-results.md`.

## Known limitations

- No recurring community schedule, chat, or Discord
- Private communities are not discoverable (by design)
- Game linking is manual (no auto-create from community page yet)
