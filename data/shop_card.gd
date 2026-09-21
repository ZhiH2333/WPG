extends RefCounted
class_name ShopCard

## P8 商店一张卡。升级走 UpgradeDef，跟班走 CompanionDef。不是升级目录条目。
enum Kind { UPGRADE, COMPANION }

var kind: Kind = Kind.UPGRADE
var upgrade: UpgradeDef
var companion: CompanionDef

static func for_upgrade(def: UpgradeDef) -> ShopCard:
	var card: ShopCard = ShopCard.new()
	card.kind = Kind.UPGRADE
	card.upgrade = def
	return card

static func for_companion(def: CompanionDef) -> ShopCard:
	var card: ShopCard = ShopCard.new()
	card.kind = Kind.COMPANION
	card.companion = def
	return card

func get_title() -> String:
	if kind == Kind.COMPANION:
		if companion == null:
			return ""
		return companion.display_name
	if upgrade == null:
		return ""
	return upgrade.title

func get_description() -> String:
	if kind == Kind.COMPANION:
		if companion == null:
			return ""
		return companion.description
	if upgrade == null:
		return ""
	return upgrade.description

func get_cost(session: RunSession) -> int:
	if kind == Kind.COMPANION:
		if companion == null:
			return 0
		return companion.shop_cost
	if upgrade == null:
		return RunSession.SHOP_COST_FALLBACK
	if session == null:
		return RunSession.SHOP_COST_FALLBACK
	return session.get_shop_cost(upgrade.id)
