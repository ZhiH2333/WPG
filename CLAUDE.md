# CLAUDE.md — WPG

## Project identity

WPG is the Godot game client and game-server codebase. Its backend is a separate planned repository named **WildBoat**. Do not place backend implementation here.

## Product baseline

- Co-op: Survival and Endless.
- Battle: FFA, Team Battle (initially 2v2), and Kill Race.
- Online discovery: room code, public room browser, and Quick Match.
- Social: WPass friends, parties, invitations, presence, player profiles, and recently-played-with.
- Progress: local cache plus cloud synchronization; cloud-authoritative records must come from trusted server settlement.
- Maximum 4 players in the initial online match.
- Server-authoritative gameplay.

## Architecture rules

- Godot Client: rendering, UI, input collection, local settings/cache, HTTPS calls to WildBoat, ENet connection to the assigned game server.
- Godot Headless Dedicated Server: authoritative simulation, AI, collision, damage, skills, scoring, match lifecycle, and final settlement payload.
- WildBoat: account/authentication, identity, friends, party, rooms, matchmaking, ticket issuance/validation coordination, persistence, progression APIs.
- HTTPS is used for business APIs. ENet/UDP is used for real-time game traffic.
- Cloudflare Workers or other HTTP gateways must not be treated as ENet/UDP proxies.
- The game server must validate a short-lived game ticket using the agreed WildBoat contract. Never accept a client-supplied account ID as proof of identity.

## Compatibility and migration

- Preserve existing solo and LAN/Host/Guest flows while the new Dedicated Server path is developed.
- Inspect the current lobby architecture before changing peer ownership. Existing documentation describes `LobbyNet` as the lobby ENet owner and `NetSession` as not creating its own connection; verify this still matches the checked-out code.
- Do not assume current networking protocol constants, seat limits, or file paths remain unchanged. Inspect them first.
- Avoid broad refactors. Add a separately testable online path and migrate deliberately.
- Do not add Autoloads without a documented need and explicit architecture review.

## Coding expectations

- Follow `docs/coding-standards-and-guidelines.md`.
- Keep gameplay authority on the server.
- Validate all network input and enforce rate/size bounds.
- Make network state transitions explicit and testable.
- Do not trust client clocks for match timing or authoritative progression.
- Do not log access tokens, refresh tokens, game tickets, passwords, or private user data.
- Use typed GDScript where practical; keep nodes and scripts narrowly scoped.

## Required workflow

1. Inspect repository state and relevant code before editing.
2. State the intended change and compatibility impact.
3. Implement one vertical slice at a time.
4. Run parse/import checks and available tests.
5. Include manual test steps for multiplayer behavior.
6. Summarize changed files, test evidence, and remaining risks.

Do not create commits, push, deploy, or modify GitHub settings unless directly requested.
