class_name NationArmy
extends RefCounted
## An army of an AI nation on the realm map (GDD §35, M18f-b1): one general (generated, never
## ours), a number of soldiers of the nation's kind, the town it stands in and the town it has
## announced an attack on (target, a turn ahead: drawn on the map so the player can answer).

var id := 0
var nation: StringName
var general: General
var soldiers := 0
var max_soldiers := 0
var town := -1
## The town it means to attack (-1: none), announced on `order_turn`; carried out when a later
## turn ends.
var target := -1
var order_turn := 0


func has_target() -> bool:
	return target >= 0


func to_save() -> Dictionary:
	return {"id": id, "nation": String(nation), "general": general.to_save() if general != null else {},
			"soldiers": soldiers, "max": max_soldiers, "town": town, "target": target, "order_turn": order_turn}


static func from_save(data: Dictionary) -> NationArmy:
	var army := NationArmy.new()
	army.id = int(data.id)
	army.nation = StringName(data.nation)
	var general_data: Dictionary = data.get("general", {})
	army.general = General.from_save(general_data) if not general_data.is_empty() else null
	army.soldiers = int(data.soldiers)
	army.max_soldiers = int(data.max)
	army.town = int(data.town)
	army.target = int(data.get("target", -1))
	army.order_turn = int(data.get("order_turn", 0))
	return army
