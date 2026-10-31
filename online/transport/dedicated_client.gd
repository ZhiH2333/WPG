extends OnlineChannel
class_name DedicatedClient

## Online 客户端入口的薄包装。实际 RPC / ENet create_client 在 OnlineChannel。
## 与 LobbyNet.client_connect 分离：本类只连 Dedicated Server，不连玩家 Host。
## 第三个参数是 game_ticket（dev 模式下可为 WPG_DEV_TOKEN）。


static func create(display_name: String = "player", game_ticket: String = "") -> DedicatedClient:
	var client := DedicatedClient.new()
	client.configure_client(display_name, game_ticket)
	return client


static func create_from_assignment(display_name: String, assignment: MatchAssignment) -> DedicatedClient:
	var ticket: String = assignment.game_ticket if assignment != null else ""
	return create(display_name, ticket)
