# WPG Online 2.0 — Coding Standards & Guidelines

## 1. General principles

- Prefer small, reviewable changes over broad rewrites.
- Preserve existing behavior unless a migration task explicitly changes it.
- Keep domain logic, transport, UI, and persistence/cache concerns separate.
- Make authority boundaries visible in names and APIs.
- Fail safely on malformed network data and unknown server values.

## 2. GDScript conventions

- Use `snake_case` for variables, functions, and file names.
- Use `PascalCase` for class names.
- Add explicit types to public methods, signals, and important state.
- Use enums/constants for protocol values; avoid scattered magic strings.
- Keep functions focused and avoid large scripts that own unrelated systems.
- Prefer dependency injection or explicit references over new global Autoloads.
- Use signals for decoupled UI updates; avoid hidden cyclic dependencies.
- Do not block the main thread with synchronous network or file operations.

## 3. Suggested module boundaries

Keep these as conceptual boundaries; inspect the current repository before choosing exact directories:
- `online/auth/` — client authentication/session handling.
- `online/social/` — friends, presence, Party UI/domain.
- `online/rooms/` — room browser, room code, ready state.
- `online/matchmaking/` — Quick Match and assignment handling.
- `online/transport/` — ENet client transport and protocol DTOs.
- `server/` — headless game-server entry and authoritative services.
- `game_modes/` — Survival, Endless, FFA, Team Battle, Kill Race rules.
- `tests/` — unit/integration/test harnesses.

Do not create all directories mechanically; align with the repository's existing structure.

## 4. Network security and validation

- Treat every client packet as untrusted.
- Validate type, range, ownership, state transition, and message rate.
- Reject impossible movement/state changes according to server rules.
- Never trust client-reported damage, kills, score, elapsed match time, or victory.
- Never log credentials, game tickets, refresh tokens, or personal secrets.
- Bind a validated ticket to one player and one match/instance; prevent replay.
- Keep server-only commands inaccessible from client RPC paths.

## 5. Multiplayer determinism and state

- Server owns authoritative simulation time.
- Use explicit match/player state machines.
- Separate reliable control events from high-frequency state updates where supported.
- Document snapshot cadence and interpolation expectations.
- Bound state history and packet sizes.
- Handle disconnect, timeout, rejoin, and match end as explicit transitions.
- Make settlement generation idempotent.

## 6. Testing

Minimum checks for relevant changes:
- Godot headless project parse/import.
- Unit tests for domain state transitions where test infrastructure exists.
- Serialization/deserialization tests for protocol DTOs.
- Negative tests for malformed and unauthorized messages.
- Two-client and four-client manual multiplayer test plans.
- Regression test of existing solo and LAN/Host/Guest flows.
- Dedicated Server startup/shutdown and invalid-ticket tests.

Record exact commands and outcomes. Do not claim a test passed if it was not run.

## 7. Documentation and change control

- Update protocol/API docs when wire contracts change.
- Update `roadmap.md` only when implementation status actually changes.
- Mark proposed features as planned, not complete.
- Do not create branches, commits, releases, or deployments unless requested.
- Include migration notes when touching legacy networking.
