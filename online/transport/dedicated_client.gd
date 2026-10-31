extends OnlineChannel
class_name DedicatedClient

## Online 客户端入口的薄包装。实际 RPC / ENet create_client 在 OnlineChannel。
## 与 LobbyNet.client_connect 分离：本类只连 Dedicated Server，不连玩家 Host。


static func create(display_name: String = "player", dev_token: String = "") -> DedicatedClient:
	var client := DedicatedClient.new()
	client.configure_client(display_name, dev_token)
	return client
