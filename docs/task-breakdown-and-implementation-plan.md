# WPG Online 2.0 — Task Breakdown / Implementation Plan

## Execution policy

This is a dependency-ordered plan, not permission to implement everything in one pass. Work in small vertical slices. Verify repository state before every task group.

## Phase 0 — Repository reconnaissance and migration design
- [ ] Verify branch, clean/dirty state, Godot version, export templates.
- [ ] Re-read `roadmap.md`, `project.godot`, lobby architecture docs, networking scripts.
- [ ] Map current peer ownership and host/guest lifecycle.
- [ ] Identify current protocol constants and seat limits.
- [ ] Document legacy flows that must remain working.
- [ ] Produce a migration design and risk list.
**Exit:** current implementation map and approved change plan.

## Phase 1 — Headless Dedicated Server proof of concept
- [x] Add explicit server startup mode.
- [x] Add Linux headless export preset/build instructions.
- [x] Create a minimal Dedicated Server entry path without client UI dependencies.
- [x] Implement server-owned player admission and spawn.
- [x] Implement one authoritative state replication loop.
- [x] Connect two clients, then test four clients.
- [x] Validate malformed/unauthorized client messages.
- [x] Add Docker image for the exported server artifact.
- [x] Document actual UDP port and health behavior.
**Exit:** reproducible containerized headless server with four test clients in one match.
**Notes (Phase 2A landed in WPG):** see `docs/dedicated-server.md`. Dev identity only; WildBoat tickets are Phase 2.

## Phase 2 — WildBoat client integration foundation
- [ ] Add typed HTTPS API client wrapper.
- [ ] Add request IDs, timeouts, cancellation, and structured error parsing.
- [ ] Add token storage strategy appropriate to each platform.
- [ ] Add login/session UI and `GET /me` integration after WildBoat endpoint is available.
- [ ] Add assignment DTO and ticket handoff.
**Exit:** authenticated test identity obtains a match assignment and joins the server.

## Phase 3 — Online room flow
- [ ] Room create/join by code.
- [ ] Public room list.
- [ ] Room details and occupancy.
- [ ] Ready state.
- [ ] Room-to-match transition.
- [ ] Party-aware room entry.
- [ ] Quick Match UI and status states.
- [ ] Handle queue/full/expired/error outcomes.
**Exit:** complete lobby-to-game flow for up to four players.

## Phase 4 — Server-authoritative game modes
- [ ] Extract/implement server-owned Survival wave controller.
- [ ] Implement Endless escalation and termination.
- [ ] Implement FFA scoring and deterministic tie-break.
- [ ] Implement 2v2 Team Battle.
- [ ] Implement Kill Race target/timer logic.
- [ ] Implement authoritative result payload.
- [ ] Add per-mode automated or repeatable test scenarios.
**Exit:** each mode can complete and settle a match.

## Phase 5 — Social and Party client experience
- [ ] Friend list and requests.
- [ ] Presence display.
- [ ] Party panel and invitations.
- [ ] Leader/member state and transfer.
- [ ] Room invite and join flow.
- [ ] Recently Played With.
- [ ] Block/report UI.
**Exit:** social workflows work against WildBoat.

## Phase 6 — Progression and hybrid sync
- [ ] Define local cache schema and version.
- [ ] Fetch cloud profile/progression.
- [ ] Apply server-settled progression.
- [ ] Add idempotent sync/retry behavior.
- [ ] Implement settings sync policy.
- [ ] Handle offline mode and conflict UX.
**Exit:** cross-device cloud-backed progress is consistent and safe.

## Phase 7 — Hardening and release
- [ ] Reconnect/rejoin flow.
- [ ] Network loss/latency/packet-loss tests.
- [ ] Android and PC network tests.
- [ ] Server performance profiling.
- [ ] Protocol/API compatibility tests.
- [ ] Security review of ticket and client packet paths.
- [ ] Logging/metrics and operational error surfaces.
- [ ] Full regression of solo and legacy LAN/Host/Guest.
**Exit:** release candidate passes the acceptance criteria in PRD.

## Cross-repository coordination

For any contract change:
1. Update WildBoat `docs/data-models-and-apis.md`.
2. Update this WPG API contract document.
3. Add compatibility/version notes.
4. Implement backend and client changes in coordinated slices.
5. Test against a pinned backend API version.

## Definition of Done

A task is done only when:
- Code is implemented and reviewed.
- Relevant automated checks were run.
- Manual multiplayer steps are documented where automation is insufficient.
- Existing behavior is regression-tested where affected.
- Docs and roadmap reflect actual status.
- No secrets or generated build artifacts are committed accidentally.
