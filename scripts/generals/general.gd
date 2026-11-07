class_name General
extends Officer
## One general (GDD §8, M11d): Võ lực (might), Thống suất (command) and an optional trait, on top
## of what every officer has (name, stars, wounds, level).

const NO_TRAIT: StringName = &""

var might: int
var command: int
var trait_id: StringName = NO_TRAIT
## Turn of the last sparring match with the Chúa công (Spar, M16j); far back = never.
var last_spar_turn := -100


## Võ lực and Thống suất with the worn items (might / command are the general's own points).
func total_might() -> int:
	return might + item_bonus(&"might")


func total_command() -> int:
	return command + item_bonus(&"command")


## The worn weapon's type (Item.WEAPON_TYPES), or &"" without one.
func weapon_type() -> StringName:
	var weapon: Item = items.get(&"weapon")
	return weapon.weapon_type if weapon != null else &""


func to_save() -> Dictionary:
	var data := _officer_save()
	data.merge({"might": might, "command": command, "trait_id": String(trait_id), "last_spar_turn": last_spar_turn})
	return data


static func from_save(data: Dictionary) -> General:
	var general := General.new()
	general._officer_load(data)
	general.might = int(data.might)
	general.command = int(data.command)
	general.trait_id = StringName(data.trait_id)
	general.last_spar_turn = int(data.get("last_spar_turn", -100))
	return general
