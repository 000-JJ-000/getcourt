# Match results & history (P1-05)

Community tennis results reuse the existing `Match` + `PlayerStatistic` / ELO pipeline. Peer invite-only games add confirmation before ratings update, plus invite-only access and soft cancellation.

## Reused infrastructure

- `Match` rows (one per registered player in a logical group via `stats["match_group_id"]`)
- `PlayerStatistics::UpsertMatchForGameService`, `SyncMatchGroupService`, `MatchUpserter`, `ScoreParser`
- `PlayerStatistic.recalculate_elo_for_mode!` (full deterministic replay)
- Web stats form on `games#show` and Telegram stats flows
- `NotificationDelivery` + Solid Queue (`MatchResultNotifyJob`)

## Result lifecycle

| Status | Meaning |
| --- | --- |
| *(missing / confirmed)* | Counts for ELO (legacy and open games auto-confirm on submit) |
| `pending` | Submitted on an `invite_only` game; awaiting opposing confirmation |
| `disputed` | Opponent disputed; resubmit a corrected score (returns to `pending`) |

### Submit

Any approved participant (or organizer/admin) may submit via the existing stats form after the game starts, unless the game is canceled or is a training.

For **invite_only** peer games the group is stored with `result_status=pending` and `submitted_by` / `result_updated_at`. Pending/disputed rows stay visible to participants but **do not change competitive wins/losses/games counts or ELO** until confirmed. Hours may still update on submit.

For **public** games submission remains auto-confirmed (pre–P1-05 behavior).

### Confirm / dispute

- **Singles:** the other registered player confirms or disputes.
- **Doubles:** any registered player on the **opposing team** may confirm or dispute (no invented partners).
- Submitter cannot finalize their own pending result.
- Confirmations require matching `result_updated_at` (stale tokens rejected).
- Concurrent confirms: row locks + status guard → single ELO recalculation path.

### Corrections

Editing a group (same `group_id`) on an invite_only game resets status to `pending` and requires reconfirmation. Confirmed open-game edits stay confirmed.

No walkover/retirement fields were added — use existing score/outcome conventions only.

## Statistics & ratings

- Self-reported NTRP on `User` stays separate from calculated ELO.
- ELO updates only through `recalculate_elo_for_mode!`, which ignores non-confirmed groups.
- No second ranking engine.

## Match history

Authenticated `GET /account/match_history` lists the current user’s `Match` rows (date, opponents, format, score, outcome, confirmation status, link to game when visible). Always available to the owner even if public profile stats are hidden.

## Invite-only access (P1-04 gap)

`Game#visible_to?(user)` gates HTML + nested resources (participations, media, scoreboard, weather, share card, prebookings, training proposals, stats submit, result confirm). Unauthorized viewers get `RecordNotFound` (no soft leak).

API `Game.publicly_visible` continues to exclude `invite_only` and canceled games.

**Doubles recruitment:** Telegram/game invitations to an invite_only game create a **pending participation** for the invitee so they can open the game and be approved — URLs alone are not authorization.

Strangers cannot self-join invite_only games.

## Peer-match cancellation

`games.canceled_at` soft-cancel. Either approved participant (or organizer/admin) may cancel an invite_only peer match via `cancel_peer`. Preserves Match history; blocks new results; notifies participants. Concurrent cancels are idempotent under row lock.

Individual withdrawal remains `Participation` destroy (does not cancel the whole peer match).

## Notifications

| Event | Recipients |
| --- | --- |
| result submitted | opposing registered players |
| confirmed / disputed | players in the match group |
| peer canceled | organizer + approved participants |

Delivery failures are logged and do not roll back state.

## Known limitations

- Confirmation gating applies to invite_only peer games; open community games auto-confirm.
- No structured set-by-set editor beyond existing free-text scores.
- No walkover/retirement outcomes.
- Counters may update on pending submit before ELO applies.
- Canceled games are soft-hidden from public lists; invitation rows still reference the game.
