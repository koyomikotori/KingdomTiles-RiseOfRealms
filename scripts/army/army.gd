class_name Army
extends RefCounted
## The kingdom's soldiers as a list of squads. Each recruitment adds one squad; a squad keeps
## its own soldier count after battles (GDD §7.6) and its own experience (GDD §8, M11e).

signal changed


class Squad:
	extends RefCounted
	var unit_id: StringName
	var soldiers: int
	## Average XP per soldier (Experience.squad_level).
	var xp := 0.0
	## On an expedition (M14i): no battles at home, no replenishment, cannot be disbanded.
	var away := false

	func _init(p_unit_id: StringName, p_soldiers: int, p_xp: float = 0.0) -> void:
		unit_id = p_unit_id
		soldiers = p_soldiers
		xp = p_xp

	func level() -> int:
		return Experience.squad_level(xp)


var squads: Array[Squad] = []


func add_squad(unit_id: StringName, soldiers: int) -> void:
	if soldiers > 0:
		squads.append(Squad.new(unit_id, soldiers))
		changed.emit()


## Sets a squad's soldier count; squads that reach 0 are removed.
func set_soldiers(squad: Squad, soldiers: int) -> void:
	squad.soldiers = maxi(0, soldiers)
	if squad.soldiers == 0:
		squads.erase(squad)
	changed.emit()


## Adds new soldiers (0 XP) to a squad: its average XP drops to xp × old / (old + added).
func add_soldiers(squad: Squad, added: int) -> void:
	if added <= 0:
		return
	var total := squad.soldiers + added
	squad.xp = squad.xp * squad.soldiers / total if total > 0 else 0.0
	squad.soldiers = total
	changed.emit()


func add_xp(squad: Squad, amount: float) -> void:
	if amount > 0.0:
		squad.xp += amount
		changed.emit()


## Barracks training: every squad gains Experience.TRAINING_XP, but never trains past
## Experience.TRAINING_MAX_LEVEL (squads already above it keep their XP).
func train() -> void:
	var cap: float = Experience.SQUAD_LEVEL_XP[Experience.TRAINING_MAX_LEVEL]
	for squad in squads:
		if squad.xp < cap:
			squad.xp = minf(cap, squad.xp + Experience.TRAINING_XP)
	changed.emit()


func remove_squad(squad: Squad) -> void:
	squads.erase(squad)
	changed.emit()


func count_squads(unit_id: StringName = &"") -> int:
	if unit_id == &"":
		return squads.size()
	return squads.filter(func(s: Squad) -> bool: return s.unit_id == unit_id).size()


func count_soldiers(unit_id: StringName = &"") -> int:
	var total := 0
	for squad in squads:
		if unit_id == &"" or squad.unit_id == unit_id:
			total += squad.soldiers
	return total


## Total upkeep per turn: each squad pays its unit's upkeep.
func get_upkeep(units: Dictionary[StringName, UnitData]) -> Dictionary[StringName, int]:
	var total: Dictionary[StringName, int] = {}
	for squad in squads:
		var unit: UnitData = units.get(squad.unit_id)
		if unit != null:
			Economy.add_into(total, unit.upkeep)
	return total


func to_save() -> Array:
	var result: Array = []
	for squad in squads:
		result.append({"unit": String(squad.unit_id), "soldiers": squad.soldiers, "xp": squad.xp, "away": squad.away})
	return result


## Squads of unit types that no longer exist in `units` are dropped.
func load_save(data: Array, units: Dictionary[StringName, UnitData]) -> void:
	squads.clear()
	for entry: Dictionary in data:
		if units.has(StringName(entry.unit)) and int(entry.soldiers) > 0:
			squads.append(Squad.new(StringName(entry.unit), int(entry.soldiers), float(entry.xp)))
			squads.back().away = bool(entry.get("away", false))
	changed.emit()
