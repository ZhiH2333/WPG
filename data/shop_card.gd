extends RefCounted
class_name ShopCard

## P8 商店一张卡。升级走 UpgradeDef，跟班走 CompanionDef，消耗品走 ConsumableDef。
enum Kind { UPGRADE, COMPANION, CONSUMABLE }

var kind: Kind = Kind.UPGRADE
var upgrade: UpgradeDef
var companion: CompanionDef
var consumable: ConsumableDef

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

static func for_consumable(def: ConsumableDef) -> ShopCard:
	var card: ShopCard = ShopCard.new()
	card.kind = Kind.CONSUMABLE
	card.consumable = def
	return card

func get_title() -> String:
	if kind == Kind.CONSUMABLE:
		if consumable == null:
			return ""
		return consumable.display_name
	if kind == Kind.COMPANION:
		if companion == null:
			return ""
		return companion.display_name
	if upgrade == null:
		return ""
	return upgrade.title

func get_description() -> String:
	if kind == Kind.CONSUMABLE:
		if consumable == null:
			return ""
		return consumable.description
	if kind == Kind.COMPANION:
		if companion == null:
			return ""
		return companion.description
	if upgrade == null:
		return ""
	return upgrade.description

func get_kind_label() -> String:
	if kind == Kind.CONSUMABLE:
		return "Consumable"
	if kind == Kind.COMPANION:
		return "Companion"
	return "Upgrade"

func get_cost(session: RunSession) -> int:
	if kind == Kind.CONSUMABLE:
		if consumable == null:
			return 0
		return consumable.shop_cost
	if kind == Kind.COMPANION:
		if companion == null:
			return 0
		return companion.shop_cost
	if upgrade == null:
		return RunSession.SHOP_COST_FALLBACK
	if session == null:
		return RunSession.SHOP_COST_FALLBACK
	return session.get_shop_cost(upgrade.id)
