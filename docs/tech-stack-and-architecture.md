# WPG Online 2.0 — Tech Stack & Architecture

## 1. Technology baseline

| Layer | Technology | Notes |
|---|---|---|
| Game client | Godot 4.6, GDScript | Existing project baseline; verify exact installed version |
| Rendering/UI | Existing WPG Godot project | Preserve established visual/domain architecture |
| Client business API | HTTPS/JSON | Calls WildBoat |
| Real-time transport | ENet over UDP | Client to Dedicated Server |
| Game server | Godot Headless Dedicated Server | Same game ruleset with server role |
| Container runtime | Docker | Server-side game process image |
| Backend | WildBoat Go service | Separate repository |
| Database | PostgreSQL | Owned by WildBoat |
| HTTP edge | Optional Cloudflare Worker/reverse proxy | HTTP only; not UDP proxy |

Do not add a new networking library or dependency until the existing Godot transport and current code have been inspected.

## 2. Logical architecture

### Godot Client
Responsibilities:
- UI, input capture, rendering, audio, local preferences.
- WPass login/session UI.
- HTTPS requests to WildBoat.
- Display room, Party, friend, and match state.
- Connect to the assigned Dedicated Server using ENet/UDP.
- Render replicated server state.
- Maintain local cache without treating it as authoritative online progression.

Must not:
- Decide authoritative damage, AI, collision, score, kills, match end, or verified achievements.
- Generate or self-assert valid game tickets.
- Directly connect to another player as the new online architecture.

### Godot Headless Dedicated Server
Responsibilities:
- Validate game ticket according to the agreed WildBoat contract.
- Own match lifecycle and authoritative simulation.
- Own player spawn, movement validation, AI, collision, skills, damage, score, timers, and outcome.
- Broadcast snapshots/events to clients.
- Produce a signed/authenticated settlement request or server-authenticated settlement payload for WildBoat.
- Expose process health/readiness using a documented mechanism.

Must not:
- Store account passwords.
- Own friend graph, account lifecycle, or long-lived profile data.
- Trust client-submitted settlement results.

### WildBoat
Owns:
- WPass account and identity.
- Sessions and token lifecycle.
- Friends, blocks, presence, Parties, invitations.
- Rooms, room codes, room browser, matchmaking allocation.
- Game ticket issuance and revocation/validation coordination.
- Cloud progression, achievements, match records.
- Server registry/instance assignment metadata.

## 3. Connection lifecycle

1. Client authenticates to WildBoat over HTTPS.
2. Client requests room creation/join/Quick Match.
3. WildBoat validates identity, membership, room state, capacity, and mode.
4. WildBoat returns match assignment and a short-lived, scoped game ticket.
5. Client connects to the specified host/port over ENet/UDP.
6. Dedicated Server validates ticket with WildBoat using a server-to-server authenticated channel or a documented offline-verifiable token design.
7. Dedicated Server admits the player and binds the ticket subject to a server-side player slot.
8. Game simulation runs authoritatively.
9. Dedicated Server submits settlement once using a unique match/settlement ID.
10. WildBoat validates the server identity, stores the result idempotently, and updates progression.

Ticket format, signing, key rotation, revocation behavior, and server validation endpoint must be finalized in the WildBoat API contract. Never invent shared secrets in source control.

## 4. Single-instance constraint

Initial deployment runs one active Godot Dedicated Server game instance. This is a deliberate first-release capacity limit.

- Multiple waiting rooms/Parties may exist in WildBoat.
- Only one match can be actively allocated to the single game instance at a time unless the game process is explicitly designed and tested for isolated multiple worlds.
- Backend must serialize allocation and return a clear queue/full response.
- Do not multiplex unrelated matches into one shared game world.
- Multi-instance scheduling is a later milestone: multiple containers/processes, health registration, capacity leases, and allocation.

## 5. Godot project integration constraints

Previously inspected project facts (must be re-verified before changes):
- Godot 4.6, GDScript.
- Existing lobby/domain components include `LobbyManager`, `Room`, `LobbyPlayer`, and `LobbyNet`.
- Existing `NetSession` was documented as Host-authoritative.
- `LobbyNet` was documented as the lobby ENet owner; `NetSession` did not create its own connection.
- Existing project had no Autoload configured.
- Existing export presets included Web and Android; Linux Dedicated Server preset was not present at the time of inspection.
- Existing protocol/seat constants and roadmap may need updates, but inspect current source before editing.

Implementation guidance:
- Introduce a dedicated-server mode explicitly.
- Keep new online transport/session code isolated from legacy LAN code initially.
- Do not make `NetSession` and `LobbyNet` both own the same ENet peer.
- Add a Linux headless export/preset after verifying Godot 4.6 export support and project assets.
- Use separate configuration for client and server roles.
- Ensure headless server does not load client-only UI/audio/rendering paths unnecessarily.

## 6. Docker deployment boundary

The game server runs in a Docker image built from a reproducible Linux export artifact.

Expected deployment artifacts:
- `Dockerfile` for the Dedicated Server runtime.
- `.dockerignore`.
- Environment/configuration documentation.
- Health-check mechanism.
- UDP port mapping documented from the actual ENet configuration.
- Non-root runtime user where practical.
- Read-only filesystem and dropped capabilities where compatible.
- Resource limits and graceful shutdown behavior.

Do not put the Godot client in Docker as a production requirement. Docker applies to server-side components.

## 7. Reliability and security

- Validate all client messages and bound payload size/rate.
- Server owns authoritative clocks and match state.
- Ticket must be short-lived and scoped to a match/server/player.
- Prevent ticket replay and duplicate slot admission.
- Use TLS for HTTPS business traffic.
- Never log credentials, refresh tokens, or tickets.
- Settlement must be authenticated and idempotent.
- Treat disconnect/rejoin as explicit state transitions.
- Record server version, protocol version, match ID, and correlation ID in logs.
