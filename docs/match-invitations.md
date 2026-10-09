# Match invitations & coordination (P1-03 / P1-04)

Peer “Invite to play” proposals between community members, plus post-accept scheduling until a `Game` exists. Separate from `GameInvitationsController`, which notifies Telegram handles about an **existing** game.

This is not a messaging product — only invitation lifecycle, schedule proposals, and notifications.

## Reused infrastructure

- `Game` + `Participation` for confirmed bookings
- `NotificationDelivery` (email / Telegram per user preference)
- Solid Queue via `MatchInvitationNotifyJob`, `ExpireMatchInvitationsJob`, `MatchInvitationSchedulingReminderJob`
- Profile visibility / community eligibility from P1-01
- Player directory / profile entry points from P1-02
- Rack::Attack for create rate limits

## Data model

`match_invitations`:

| Field | Role |
| --- | --- |
| inviter / invitee | Participants |
| play_format | `singles` \| `doubles` |
| proposed_at / court | Optional schedule details |
| message | Invite note (≤500) |
| status | `pending` \| `accepted` \| `declined` \| `canceled` \| `expired` |
| scheduling_status | `none` \| `needed` \| `proposed` \| `scheduled` |
| proposed_by / proposal_note / proposal_updated_at | Active schedule proposal |
| scheduling_reminded_at | One-shot reminder marker |
| game | Associated peer game once scheduled |
| expires_at | Pending TTL (default +7 days) |

Unique partial index: one **pending** pair `(inviter_id, invitee_id)`.

User preference: `accepts_match_invitations` (default `true`).

Peer games set `games.invite_only = true` so they stay off public lists / API `publicly_visible`.

## Lifecycle

```
pending
  ├─ decline / cancel / expire → terminal
  └─ accept
       ├─ future proposed_at → scheduled + Game
       └─ else → scheduling needed
            └─ propose → proposed
                 ├─ change proposal → proposed (reconfirm)
                 └─ other confirms → scheduled + Game
```

### Accept rule (final)

Accepting an invitation that already includes a **future** `proposed_at` is treated as explicit agreement to that time (and optional court). The app creates the peer `Game` immediately.

If `proposed_at` is missing or in the past, the invitation becomes **accepted** with `scheduling_status=needed` — no invalid/unintended game.

Accepted invitations do **not** expire when the original pending TTL passes.

### Scheduling proposals

Either participant may propose or change date/time/court/optional note while accepted and unscheduled. Changing a proposal bumps `proposal_updated_at` and requires the other party to confirm again (stale confirm tokens rejected).

Confirmation:

- Only the non-proposer may confirm
- Must send matching `proposal_updated_at`
- Row lock + idempotent `create_peer_game!` → at most one game on concurrent confirms

### Game creation

- Organizer = inviter
- Both players get approved participations (`find_or_create_by`)
- Singles: `players_count=2` (full)
- Doubles: `players_count=4` with two approved players; UI shows open slots; remaining seats use existing join / game-invite flows
- `invite_only: true` — not publicly listed; not auto-joinable from browse
- Comment merges invitation message + proposal note (length-limited via Game)

Proposals cannot overwrite an already scheduled invitation (`already_scheduled`).

## Cancellation

- Pending: inviter cancel / invitee decline / expire job
- Scheduled games use normal Game edit/cancel flows (no separate peer-cancel that deletes the Game from the invitation UI yet)

## Notifications

| Event | Recipient |
| --- | --- |
| created | invitee |
| accepted / declined | inviter |
| canceled | invitee |
| proposal_submitted / proposal_changed | other participant |
| scheduled | both |
| scheduling_reminder | both (once, ~2 days after accept while still `needed`) |

Delivery failures are logged and do not roll back invitation/scheduling state. Jobs are async; retries re-deliver preferencing NotificationDelivery idempotency where available.

## Expiration & reminders

- `ExpireMatchInvitationsJob` (hourly in production recurring) marks overdue **pending** invites expired
- Lazy expire also runs on show/respond
- `MatchInvitationSchedulingReminderJob` (daily) sends one reminder for accepted+`needed` older than 2 days

## Privacy & authorization

- Only inviter/invitee see invitation detail / propose / confirm
- Invitee-only accept/decline; inviter-only cancel
- Court IDs must resolve via `Court.visible_to` for either participant
- Notes/messages escaped in views; length-limited
- Active Storage avatar gate from P1-03 unchanged
- `invite_only` games excluded from public games index and API visibility; show URL remains available so doubles slots can be filled via existing participation/invite mechanisms

## Known limitations

- No chat / calendar sync / court booking payments
- No push of invite-only privacy onto `games#show` beyond list/API hiding
- No dedicated “unschedule / cancel peer game from invitation” action
- Doubles partners are not auto-matched
- Time zone is application `Time.zone` (same as other Game scheduling)

## P1-02 follow-ups addressed (earlier)

- `play_formats` / `play_styles` migrated to **jsonb**; directory filters use native `@>`
- Active Storage blob/representation controllers deny `User` `avatar` attachments unless `profile_visible_to?(session viewer)`
