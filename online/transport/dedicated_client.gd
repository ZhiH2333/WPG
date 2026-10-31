extends OnlineChannel
class_name DedicatedClient

## Online 客户端入口的薄包装。实际 RPC / ENet create_client 在 OnlineChannel。
## 与 LobbyNet.client_connect 分离：本类只连 Dedicated Server，不连玩家 Host。
## game_ticket 在 dev 模式下可为 WPG_DEV_TOKEN；生产为 WildBoat 短命票。


static func create(
	display_name: String = "player",
	game_ticket: String = "",
	claimed_player_id: String = "",
	claimed_match_id: String = ""
) -> DedicatedClient:
	var client := DedicatedClient.new()
	client.configure_client(display_name, game_ticket, claimed_player_id, claimed_match_id)
	return client


static func create_from_assignment(
	display_name: String,
	assignment: MatchAssignment,
	player_id: String = ""
) -> DedicatedClient:
	var ticket: String = assignment.game_ticket if assignment != null else ""
	var match_id: String = assignment.match_id if assignment != null else ""
	return create(display_name, ticket, player_id, match_id)
