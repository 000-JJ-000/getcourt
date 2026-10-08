# Product Requirements Document (PRD)
Status: approved product direction; detailed workflows require UX validation.

## Personas
Recreational player: finds similarly skilled opponents and courts. Competitive player: records verified results and monitors separate singles/doubles ratings. Community moderator: reviews court corrections and user reports. Later: club/league organizer.

## MVP capabilities
**Identity**: email/password plus Google and Apple login; verified email, password recovery, explicit secure account linking; self-service account deletion/export.
**Profiles/discovery**: chosen display name, city/ZIP, configurable travel radius (5/10/25/50+ miles), favorite courts, self-reported NTRP, separate singles/doubles dynamic ratings, playing preferences, availability. Do not publicly reveal home address, email, phone or precise home coordinates.
**Matches**: search players, open match invitations, join/approve flows, recurring availability, singles and doubles, match status and notifications.
**Results**: opposing participant confirmation before competitive rating update; pending/disputed results do not count. Doubles verification policy unresolved; define before Phase 2.
**Courts**: community-managed directory with corrections and moderation; favorites and radius filtering.
**Messaging**: private one-to-one communication, blocking/reporting, user controls and push notifications.
**Discord**: optional linked account, interactive discovery/search/join requests; sensitive state changes completed via authorized Rails API; no private information exposed in public channels.
**Mobile**: Flutter Android/iOS with sign-in, profiles, discovery, invitations, results, messaging, push.

## Later
Advanced analytics, premium features, club/league administration, organizer subscriptions, regional expansion.

## User journeys / acceptance
1. New player signs in, verifies identity, selects city/ZIP and favorite courts, and appears in privacy-safe searches.
2. Player creates open invitation; eligible opponent requests to join; organizer approves; both receive notifications.
3. Players submit a result; authorized opponent confirms; only then does rating history update once (idempotently).
4. Player blocks another; blocked user cannot message or discover protected information about them.
5. Linked Discord user searches courts/matches without exposing private player data in a channel.

## Product questions not yet closed
Doubles confirmation quorum; exact rating algorithm and provisional rules; moderation response policy; retention/deletion of historical match records; launch geography and branding; monetization details after MVP.
