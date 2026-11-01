class_name BattleSide
extends RefCounted
## One army in a battle: a list of battle units, one per squad.


class Unit:
	extends RefCounted
	var data: UnitData
	## Formation row right now: data.row, until musketeers march to the front after their volley
	## (UnitData.melee_after_volley, M13).
	var row: UnitData.Row
	## The kingdom squad this unit came from, or null (bandits, test armies).
	var squad: Army.Squad
	## The clan that lent this unit to the side (an ally of the kingdom, or a friend helping the
	## defending clan), or null for the side's own army. Its losses come out of that clan's strength.
	var ally: ClanData
	## The commander's bodyguard (Generals.lead): when it breaks or dies, the general falls.
	var is_general_guard := false
	## Battle multipliers (1.0 = unit data as is), raised by the commander (Generals.lead).
	var attack_mult := 1.0
	var charge_mult := 1.0
	var defense_mult := 1.0
	var range_mult := 1.0
	## Share of the target's melee defense this unit's blows ignore (a mace, M12e).
	var defense_pierce := 0.0
	## The squad's experience level (Experience.squad_level) and its flat stat bonuses: melee
	## attack (range attack for ranged units), melee defense; morale is added directly.
	var level := 0
	var attack_bonus := 0
	var defense_bonus := 0
	var range_bonus := 0
	var start_soldiers: int
	## Fractional while casualties accumulate; alive() rounds up.
	var soldiers: float
	var morale: float
	var broken := false
	var has_charged := false
	var has_fired := false
	var next_volley_at := 0.0
	## Arrow volleys shot so far (UnitData.charge_after_volleys, M16f).
	var volleys := 0
	## Enemy soldiers this unit has taken down.
	var kills := 0.0
	## How many 25% casualty steps have already cost morale.
	var morale_steps := 0

	func _init(p_data: UnitData, count: int, p_squad: Army.Squad) -> void:
		data = p_data
		row = p_data.row
		squad = p_squad
		start_soldiers = count
		soldiers = count
		morale = p_data.morale
		if squad != null:
			level = squad.level()
			var bonus := level * Experience.SQUAD_LEVEL_BONUS
			if p_data.is_ranged():
				range_bonus = bonus
			if not p_data.is_ranged() or p_data.fights_in_melee_later():
				attack_bonus = bonus
			defense_bonus = bonus
			morale += bonus

	func melee_attack() -> float:
		return (data.melee_attack + attack_bonus) * attack_mult

	func melee_defense() -> float:
		return (data.melee_defense + defense_bonus) * defense_mult

	func range_attack() -> float:
		return (data.range_attack + range_bonus) * range_mult

	func alive() -> int:
		return ceili(soldiers - 0.0001) if soldiers > 0.0 else 0

	func lost() -> int:
		return start_soldiers - alive()

	## Still fighting: has soldiers and has not broken.
	func is_active() -> bool:
		return not broken and alive() > 0

	## A ranged unit that has left its row for melee: musketeers after their volley, horse
	## archers after their last volley.
	func has_closed_in() -> bool:
		if data.melee_after_volley:
			return has_fired
		return data.charge_after_volleys > 0 and volleys >= data.charge_after_volleys


var display_name: String
## Clothing color of the side's own soldiers in battle (the player's color, a clan's banner color,
## bandit brown). Lent units wear their clan's color instead (Unit.ally).
var color := Color(0.6, 0.6, 0.6)
var units: Array[Unit] = []
## The commander leading this side, or "" (Generals.lead), and how they look (their sprite).
var general_name := ""
var general_look: OfficerLook
## Set by the simulator when the commander's bodyguard broke or died.
var general_fallen := false
## The commander's weapon type (Item.WEAPON_TYPES; &"" = a plain sword), for their sprite.
var general_weapon: StringName = &""
## The military advisor behind this side, or "" (Advisors.assist): their Mưu lược and the
## stratagems the simulator rolls at the start of the battle.
var advisor_name := ""
var advisor_look: OfficerLook
var strategy := 0
## Extra stratagem chance from the advisor's items (M12e).
var stratagem_bonus := 0.0
var stratagems: Array[StratagemData] = []


func _init(p_display_name: String) -> void:
	display_name = p_display_name


## Adds a unit; counts of 0 or less are ignored.
func add_unit(data: UnitData, soldiers: int, squad: Army.Squad = null, ally: ClanData = null) -> void:
	if soldiers > 0:
		var unit := Unit.new(data, soldiers, squad)
		unit.ally = ally
		units.append(unit)


func active_units() -> Array[Unit]:
	return units.filter(func(u: Unit) -> bool: return u.is_active())


func alive_total() -> int:
	var total := 0
	for unit in units:
		total += unit.alive()
	return total


func start_total() -> int:
	var total := 0
	for unit in units:
		total += unit.start_soldiers
	return total


func fraction_alive() -> float:
	var start := start_total()
	return float(alive_total()) / start if start > 0 else 0.0


## The front-most row that still has active units, or -1 when none.
func front_row() -> int:
	var best := -1
	for unit in active_units():
		if best == -1 or unit.row < best:
			best = unit.row
	return best
