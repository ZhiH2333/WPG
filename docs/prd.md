# WPG Online 2.0 — Product Requirements Document

**Status:** Approved product direction / implementation specification  
**Product:** WPG  
**Client/game repository:** `ZhiH2333/WPG`  
**Backend:** `WildBoat` (separate planned repository)  
**Version:** 1.0

## 1. Product vision

Evolve WPG from its existing solo/LAN/Host-Guest experience into an online multiplayer game with persistent identity, social play, room discovery, quick matchmaking, server-authoritative game modes, and cross-device progression.

## 2. Confirmed product decisions

| Area | Decision |
|---|---|
| Account/social platform | WPass, Full social |
| Co-op | Survival, Endless |
| Battle | FFA, Team Battle, Kill Race |
| Match discovery | Room code, room browser, Quick Match |
| Progress | Hybrid local + cloud |
| Product ambition | Full online-platform direction, delivered incrementally |
| Initial match size | Up to 4 players |
| Game authority | Godot Headless Dedicated Server |
| Backend | WildBoat, Go, separate repository |
| Database | PostgreSQL |
| Lobby/business transport | HTTPS |
| Real-time game transport | ENet/UDP |

## 3. Target users and core journeys

### 3.1 Returning player
1. Launch WPG.
2. Sign in with WPass.
3. Load profile and cloud-backed progression.
4. Join a Party, room, or Quick Match.
5. Play and receive server-settled results.
6. Sync progression.

### 3.2 Playing with friends
1. Player A signs in and creates a Party.
2. A invites friends.
3. Invitees accept or decline.
4. Party leader selects a mode.
5. Party enters an existing room or creates a room.
6. Party members ready up and enter the assigned Dedicated Server.

### 3.3 Room-code join
1. Player enters a six-character room code.
2. WildBoat validates room visibility, state, capacity, and access rules.
3. Backend returns room metadata and a short-lived game ticket when appropriate.
4. Client connects to the assigned game server.
5. Dedicated Server validates the ticket before admitting the player.

### 3.4 Quick Match
1. Player or Party selects a mode.
2. Backend validates Party composition and eligibility.
3. Backend searches compatible rooms/queue.
4. If no compatible match exists, backend follows the configured room allocation policy.
5. Backend returns connection details and a short-lived ticket.
6. Client connects to Dedicated Server.

## 4. Game modes

### 4.1 Co-op Survival
- 2–4 players.
- Server-controlled waves, spawn schedule, enemy AI, damage, player state, and wave completion.
- Record wave reached, duration, team result, and relevant per-player contribution metrics.
- Difficulty and wave parameters are server-selected.
- A run ends according to server-defined failure/victory/abandon rules.

### 4.2 Co-op Endless
- Builds on Survival wave infrastructure.
- Continues until the team fails or the run is explicitly ended under defined rules.
- Difficulty escalates according to server-controlled progression.
- Track highest wave, survival duration, and run metadata.
- Optional mutators are a later extension, not a prerequisite for the first playable implementation.

### 4.3 Battle FFA
- 2–4 players.
- Each player competes individually.
- Server decides kills, score, respawn state, timer, and final ranking.
- Tie-breaking rules must be deterministic and documented before release.

### 4.4 Team Battle
- Initial configuration: 2v2.
- Team score and match outcome are server-authoritative.
- Team assignment is fixed for the match unless a future ruleset explicitly supports otherwise.

### 4.5 Kill Race
- 2–4 players.
- Match ends when a configured kill target is reached or the authoritative timer expires.
- Server decides final score and winner.

## 5. Social and account features

WPass Full scope:
- Registration, login, logout, session management, email verification, password reset/recovery.
- Stable `account_id` and WPG `player_id`.
- Display name, avatar, profile summary.
- Friend requests, accept/decline, remove, block.
- Online/offline/in-game presence.
- Party create, invite, join, leave, leader transfer, disband.
- Room and Party invitations.
- Recently Played With list.
- Basic report/block controls.

Public chat, guilds/clans, voice chat, and cross-game identity federation are not required for Online 2.0 release.

## 6. Room and matchmaking requirements

- Six-character human-readable room code. Character alphabet must avoid ambiguous glyphs.
- Room visibility: `public`, `private`, `friends_only`.
- Public room browser shows mode, occupancy, state, and selected public settings.
- Room lifecycle: waiting, ready/checking, allocating, in_game, completed, expired/cancelled.
- Party membership and room membership are separate concepts.
- Quick Match supports solo players and valid Parties.
- Initial deployment has one active game instance. Queue or reject additional match allocations rather than pretending multiple simultaneous matches are supported.
- Rejoin is supported only when the match and server policy permit it.

## 7. Progression and synchronization

Hybrid local + cloud:
- Local data may cache profile/progression and store client preferences.
- Cloud is authoritative for account identity, friend graph, server-settled match records, achievements, and cloud progression.
- Settings may use a documented last-write/version conflict policy.
- Additive statistics must use idempotent event/settlement identifiers to avoid double counting.
- Clients cannot upload arbitrary authoritative score, kill, achievement, or unlock values.
- Offline local-only progress must be clearly distinguished from verified online progression.

## 8. Non-functional requirements

- Server-authoritative game simulation.
- Validate and rate-limit all business API input.
- Short-lived, scoped game tickets; never store raw passwords in game-server memory or logs.
- Reliable match settlement with idempotency.
- Structured logs with correlation IDs and secret redaction.
- Health/readiness checks for server processes.
- Docker-based deployment for server-side components.
- Recoverable PostgreSQL backups and tested restore procedure before public release.
- Support PC and Android clients, subject to platform-specific network testing.
- Measure latency, packet loss, disconnects, server tick stability, and match completion.

## 9. Scope exclusions for initial release

- Guilds/clans and public chat channels.
- Voice chat.
- Spectator and replay systems.
- Seasons and complex ranked ladder.
- Multiple independent game instances until orchestration is implemented.
- Cross-game WPass federation.
- Monetization and paid competitive advantages.

## 10. Release acceptance

Online 2.0 is release-ready only when:
- WPass account lifecycle works.
- Friends, Party, invitations, presence, and recently-played-with work.
- Room code, room browser, and Quick Match work within the single-instance capacity policy.
- All five game modes complete full online matches for up to four players.
- Dedicated Server is authoritative for gameplay and settlement.
- Reconnect/rejoin behavior is defined and tested.
- Cloud progression is idempotent and hybrid sync conflict rules are tested.
- PC and Android builds pass supported-network testing.
- Server deployment, logs, monitoring, backups, and restore are documented and exercised.
