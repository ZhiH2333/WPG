# WPG Online 2.0 — Data Models & APIs

This document defines the **client/server integration contract**. WildBoat owns the authoritative business API implementation. Endpoint names and JSON shapes below are proposed contracts; coordinate changes with the WildBoat repository before implementation.

## 1. Client-side domain types

Use typed GDScript classes/resources or narrowly scoped data objects. Keep transport DTOs separate from UI view models.

### PlayerIdentity
- `account_id: String`
- `player_id: String`
- `display_name: String`
- `avatar_id: String`
- `profile_version: int`

### PartySummary
- `party_id: String`
- `leader_player_id: String`
- `member_player_ids: Array[String]`
- `created_at: String`
- `version: int`

### RoomSummary
- `room_id: String`
- `room_code: String`
- `mode: String`
- `visibility: String`
- `state: String`
- `member_count: int`
- `max_players: int`
- `map_id: String`
- `version: int`

### MatchAssignment
- `match_id: String`
- `game_instance_id: String`
- `host: String`
- `port: int`
- `transport: String` (initially `enet_udp`)
- `game_ticket: String`
- `ticket_expires_at: String`
- `protocol_version: int`
- `server_build: String`

### MatchResultSummary
- `match_id: String`
- `mode: String`
- `result: String`
- `started_at: String`
- `ended_at: String`
- `duration_seconds: int`
- `settlement_id: String`

## 2. Enumerations

- Modes: `coop_survival`, `coop_endless`, `battle_ffa`, `battle_team`, `battle_kill_race`
- Room visibility: `public`, `private`, `friends_only`
- Room state: `waiting`, `ready_check`, `allocating`, `in_game`, `completed`, `cancelled`, `expired`
- Player presence: `offline`, `online`, `in_game`
- Party role: `leader`, `member`
- Match state: `allocated`, `running`, `completed`, `aborted`

Unknown enum values must be handled safely; do not crash on a newer backend enum.

## 3. Proposed HTTPS API surface

Base path: `/v1`. All requests use HTTPS and JSON unless specified.

### Authentication
- `POST /v1/auth/register`
- `POST /v1/auth/login`
- `POST /v1/auth/refresh`
- `POST /v1/auth/logout`
- `POST /v1/auth/verify-email`
- `POST /v1/auth/password/forgot`
- `POST /v1/auth/password/reset`
- `GET /v1/me`
- `PATCH /v1/me/profile`

### Friends and presence
- `GET /v1/friends`
- `POST /v1/friend-requests`
- `POST /v1/friend-requests/{request_id}/accept`
- `POST /v1/friend-requests/{request_id}/decline`
- `DELETE /v1/friends/{player_id}`
- `POST /v1/blocks/{player_id}`
- `DELETE /v1/blocks/{player_id}`
- `GET /v1/players/{player_id}`
- `GET /v1/presence/friends`
- `GET /v1/recent-players`

### Party
- `POST /v1/parties`
- `GET /v1/parties/{party_id}`
- `POST /v1/parties/{party_id}/invites`
- `POST /v1/party-invites/{invite_id}/accept`
- `POST /v1/party-invites/{invite_id}/decline`
- `POST /v1/parties/{party_id}/leave`
- `POST /v1/parties/{party_id}/disband`
- `POST /v1/parties/{party_id}/transfer-leader`

### Rooms and matchmaking
- `POST /v1/rooms`
- `GET /v1/rooms`
- `GET /v1/rooms/{room_id}`
- `POST /v1/rooms/join-by-code`
- `POST /v1/rooms/{room_id}/join`
- `POST /v1/rooms/{room_id}/leave`
- `POST /v1/rooms/{room_id}/ready`
- `PATCH /v1/rooms/{room_id}/settings`
- `POST /v1/matchmaking/quick`
- `GET /v1/matchmaking/requests/{request_id}`
- `POST /v1/matches/{match_id}/rejoin`

### Progression
- `GET /v1/progression`
- `GET /v1/progression/achievements`
- `GET /v1/matches/history`
- `GET /v1/stats`

### Server-to-server (not callable by clients)
- `POST /v1/server/tickets/validate` (if online validation is selected)
- `POST /v1/server/matches/{match_id}/settlement`
- `POST /v1/server/heartbeat`

Protect server routes with workload identity/mTLS or a rotated server credential stored outside source control. Do not expose server credentials to clients.

## 4. Example request/response contracts

### Quick Match request
```json
{
  "mode": "coop_survival",
  "region": "auto",
  "party_id": "pty_example",
  "preferences": {
    "map_id": "default"
  }
}
```

### Match assignment response
```json
{
  "match_id": "mat_example",
  "game_instance_id": "gsi_example",
  "endpoint": {
    "host": "game.example.net",
    "port": 24567,
    "transport": "enet_udp"
  },
  "game_ticket": "<short-lived-secret>",
  "ticket_expires_at": "2026-10-31T04:00:00Z",
  "protocol_version": 1,
  "server_build": "wpg-server-build"
}
```

The host/port and protocol version are deployment/configuration values, not hardcoded assumptions. The example ticket is a placeholder, not a real token.

### Ticket validation request (server-to-server)
```json
{
  "ticket": "<short-lived-secret>",
  "game_instance_id": "gsi_example",
  "server_build": "wpg-server-build"
}
```

### Settlement request (server-to-server)
```json
{
  "settlement_id": "set_unique_id",
  "match_id": "mat_example",
  "mode": "coop_survival",
  "started_at": "2026-10-31T03:40:00Z",
  "ended_at": "2026-10-31T03:55:00Z",
  "result": "completed",
  "players": [
    {
      "player_id": "plr_example",
      "team_id": "team_alpha",
      "kills": 12,
      "deaths": 2,
      "score": 1200
    }
  ],
  "mode_stats": {
    "highest_wave": 8
  }
}
```

Backend must deduplicate by `settlement_id` and validate the submitting game instance. Fields are illustrative and must be reconciled with actual WPG gameplay metrics.

## 5. Error envelope

Use a consistent envelope:
```json
{
  "error": {
    "code": "ROOM_FULL",
    "message": "Room is full.",
    "request_id": "req_example",
    "details": {}
  }
}
```

Clients should branch on stable `code`, not localized `message`.

## 6. Real-time game protocol

- Transport: ENet/UDP.
- Protocol version is explicit and checked during admission.
- Client messages express intent/input only.
- Server snapshots/events are authoritative.
- Define packet schemas, sequence numbers, rate limits, and maximum payload sizes in a separate protocol specification before production.
- Do not tunnel ENet through HTTP/Cloudflare Worker.
- Reconnect requires a new or refreshed admission authorization under server policy.

## 7. Compatibility policy

- Version API under `/v1`.
- Add optional response fields without breaking old clients.
- Do not silently change enum semantics.
- Version the game protocol independently from the HTTP API.
- Backend and client changes that alter contracts must be coordinated across the two repositories.
