extends RefCounted
class_name Room

## 房间身份。座位 1 是 Host，2～5 取最小空位，空出后号不前挪。pending 不进 players。
enum Privacy { LAN_VISIBLE, INVITE_ONLY }
enum RoomState { OPEN, STARTING }

const HOST_SEAT: int = 1
const FIRST_GUEST_SEAT: int = 2

var room_id: String = ""
var host_profile_id: String = ""
var host_display_name: String = ""
var players: Array[LobbyPlayer] = []
var max_players: int = GameLaunch.NET_MAX_SEATS
var arena_id: String = "yard"
var net_play: GameLaunch.NetPlay = GameLaunch.NetPlay.COOP
var loop_goal: int = 20
var privacy: Privacy = Privacy.LAN_VISIBLE
var room_state: RoomState = RoomState.OPEN
var borrowed_record_id: String = ""
var invite: Variant = null

func is_open() -> bool:
	return room_state == RoomState.OPEN

func is_borrow_locked() -> bool:
	return not borrowed_record_id.is_empty()

func player_at(seat: int) -> LobbyPlayer:
	for player: LobbyPlayer in players:
		if player.seat == seat:
			return player
	return null

func player_for_peer(peer_id: int) -> LobbyPlayer:
	if peer_id <= 0:
		return null
	for player: LobbyPlayer in players:
		if player.peer_id == peer_id:
			return player
	return null

func lowest_empty_guest_seat() -> int:
	for seat: int in range(FIRST_GUEST_SEAT, max_players + 1):
		if player_at(seat) == null:
			return seat
	return 0

func insert_player(player: LobbyPlayer) -> bool:
	if player == null:
		return false
	if player.seat < HOST_SEAT or player.seat > max_players:
		return false
	if player_at(player.seat) != null:
		return false
	players.append(player)
	players.sort_custom(_is_earlier_seat)
	return true

func remove_seat(seat: int) -> bool:
	if seat < FIRST_GUEST_SEAT:
		return false
	for index: int in players.size():
		if players[index].seat != seat:
			continue
		players.remove_at(index)
		return true
	return false

func all_seated_ready() -> bool:
	if players.size() < 2:
		return false
	for player: LobbyPlayer in players:
		if not player.ready or not player.has_joined():
			return false
	return true

func roster_characters() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	ids.resize(max_players)
	ids.fill("")
	for player: LobbyPlayer in players:
		ids[player.seat - 1] = player.selected_character_id
	return ids

func roster_peers() -> PackedInt32Array:
	var peers: PackedInt32Array = PackedInt32Array()
	peers.resize(max_players)
	peers.fill(0)
	for player: LobbyPlayer in players:
		peers[player.seat - 1] = player.peer_id
	return peers

func _is_earlier_seat(left: LobbyPlayer, right: LobbyPlayer) -> bool:
	return left.seat < right.seat
