class_name Realm
extends RefCounted
## The realm phase "Phân Chia Thiên Hạ" (GDD §33, M18f-a), after the 35 clans are united: the
## kingdom and five nations, five towns each, on RealmMap. Owned by KingdomState (`realm`); takes
## the state as an argument instead of holding it, like Victory.
##
## - Towns: every nation town has a garrison (GARRISON_BY_DISTANCE, ×CAPITAL_GARRISON for a
##   capital, × the difficulty) that regrows GARRISON_REGEN of its maximum a turn.
## - Armies (Force): one general and 1..MAX_ARMY_SQUADS squads, formed at the kingdom's capital;
##   general and squads are `away` (no home battles, posts or home replenishment). An army moves
##   one road a turn; entering an enemy town is a siege (create_siege / finish_siege) where the
##   defenders get the walls' bonus. A won siege takes the town (and its loot); taking a nation's
##   capital destroys the nation and hands over its other towns.
## - Armies standing on a kingdom town that did not move this turn regain soldiers (end_turn).
## - Captured towns pay TOWN_YIELD (half without a governor; the governor's stat adds more), add
##   squads to the kingdom's capacity and replenishment. A governor is a general or advisor who
##   stays there (`away`).
## - Counterattacks (end_turn): a nation not yet destroyed may send part of a neighboring town's
##   garrison against a town it lost; the town's army (if any) and its militia defend it.

enum Result { OK, NOT_ACTIVE, NO_GENERAL, GENERAL_BUSY, NO_SQUADS, TOO_MANY_SQUADS, SQUAD_BUSY, NOT_AT_CAPITAL,
		ALREADY_MOVED, NOT_NEIGHBOR, ENEMY_TOWN, OWN_TOWN, GENERAL_WOUNDED, NOT_CAPTURED, OFFICER_BUSY,
		HAS_GOVERNOR }

const PLAYER: StringName = &"player"
const HOME_CAPITAL := RealmMap.HOME_REGION * RealmMap.TOWNS_PER_REGION + RealmMap.CAPITAL
## Generals the kingdom may keep in the realm phase (GDD §33: 3 → 9).
const MAX_GENERALS := 9
const MAX_ARMY_SQUADS := 20
## Garrison soldiers of a town by its region's distance from the kingdom (1 … 3).
const GARRISON_BY_DISTANCE: Array[int] = [0, 220, 320, 440]
const CAPITAL_GARRISON := 2.0
const GARRISON_REGEN := 0.1
## The walls: defenders' defense multiplier and morale (capitals more).
const WALL_DEFENSE := 0.15
const CAPITAL_WALL_DEFENSE := 0.3
const WALL_MORALE := 2.0
const CAPITAL_WALL_MORALE := 4.0
## Share of a squad's full size an army regains a turn on a kingdom town (the capital more), plus
## TOWN_REPLENISH per captured town (also added to the kingdom's own replenishment).
const ARMY_REPLENISH := 0.1
const CAPITAL_REPLENISH := 0.2
const TOWN_REPLENISH := 0.01
## Squads every town of ours (the five home towns too) adds to the kingdom's capacity.
const TOWN_SQUADS := 5
## What a captured town pays a turn (a capital twice that); half without a governor, and
## GOVERNOR_YIELD more per point of the governor's Thống suất (general) or Nội chính (advisor).
const TOWN_YIELD: Dictionary[StringName, int] = {&"food": 15, &"wood": 10, &"stone": 10, &"ore": 3,
		&"hardwood": 3, &"horses": 3}
const CAPITAL_YIELD := 2
const UNGOVERNED_SHARE := 0.5
const GOVERNOR_YIELD := 0.05
## Taken once when a town falls (a capital CAPITAL_LOOT times that).
const CAPTURE_LOOT: Dictionary[StringName, int] = {&"food": 120, &"wood": 120, &"stone": 120, &"ore": 40,
		&"hardwood": 40, &"horses": 40}
const CAPITAL_LOOT := 3
## A captured town's own defenders: MILITIA_BASE peasants + MILITIA_PER_POINT per point of the
## governor's Võ lực (general) or Mưu lược (advisor).
const MILITIA_BASE := 40
const MILITIA_PER_POINT := 6
const MILITIA_UNITS: Dictionary[StringName, float] = {&"spearman": 1.0, &"archer": 1.0}
## Counterattacks: chance a turn when some lost town can be attacked, the share of the neighboring
## garrison sent, turns a newly taken town is left alone, and the fewest soldiers worth sending.
const COUNTER_CHANCE := 0.25
const COUNTER_SHARE := 0.5
const COUNTER_GRACE := 2
const COUNTER_MIN := 40


class Town:
	extends RefCounted
	var id: int
	var name: String
	## The nation the town belonged to at the start (PLAYER for the kingdom's region).
	var nation: StringName
	var owner: StringName
	var garrison := 0
	var max_garrison := 0
	## A General or an Advisor, or null.
	var governor: Officer
	var captured_turn := -100

	func is_capital() -> bool:
		return RealmMap.is_capital(id)

	## Taken from a nation (not one of the kingdom's own towns).
	func is_captured() -> bool:
		return owner == PLAYER and nation != PLAYER


class Nation:
	extends RefCounted
	var id: StringName
	var name: String
	var region: int
	var color: Color
	var destroyed := false

	func capital() -> int:
		return RealmMap.town_id(region, RealmMap.CAPITAL)

	func distance() -> int:
		return RealmMap.region_distance(region)


class Force:
	extends RefCounted
	var general: General
	var squads: Array[Army.Squad] = []
	var town := HOME_CAPITAL
	## Marched or fought this turn: no more orders, no replenishment.
	var moved := false

	func soldiers() -> int:
		var total := 0
		for squad in squads:
			total += squad.soldiers
		return total


var active := false
var towns: Array[Town] = []
var nations: Dictionary[StringName, Nation] = {}
var forces: Array[Force] = []
## The counterattack waiting to be played: {"town", "source", "sent"} (end_turn → finish_counter).
var pending_counter := {}
var rng := RandomNumberGenerator.new()


## Starts the phase: the nations take shuffled regions, every town gets its name and garrison.
func start(state: KingdomState) -> void:
	active = true
	towns.clear()
	nations.clear()
	forces.clear()
	var ids: Array = RealmMap.NATIONS.map(func(data: Dictionary) -> StringName: return data.id)
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: StringName = ids[i]
		ids[i] = ids[j]
		ids[j] = swap
	for i in ids.size():
		var data := RealmMap.nation_data(ids[i])
		var nation := Nation.new()
		nation.id = ids[i]
		nation.name = data.name
		nation.region = i + 1
		nation.color = RealmMap.nation_color(nation.id, state.player_color)
		nations[nation.id] = nation
	var home_names := _home_names(state)
	for id in RealmMap.TOWN_COUNT:
		var town := Town.new()
		town.id = id
		var region := RealmMap.region_of(id)
		if region == RealmMap.HOME_REGION:
			town.nation = PLAYER
			town.owner = PLAYER
			town.name = state.kingdom_name if town.is_capital() else home_names[_ring_index(id)]
		else:
			var nation := nation_in(region)
			town.nation = nation.id
			town.owner = nation.id
			town.name = town_name(nation.id, id)
			town.max_garrison = garrison_for(id, state.wars.enemy_scale)
			town.garrison = town.max_garrison
		towns.append(town)


## The four non-capital slots in order (N, W, E, S) → 0..3.
static func _ring_index(town: int) -> int:
	var slot := RealmMap.slot_of(town)
	return slot if slot < RealmMap.CAPITAL else slot - 1


## The kingdom's other four towns are named after the strongest clans it united.
static func _home_names(state: KingdomState) -> Array[String]:
	var clans: Array = state.diplomacy.clans.values()
	clans.sort_custom(func(a, b) -> bool: return a.data.military_strength > b.data.military_strength)
	var names: Array[String] = []
	for clan in clans.slice(0, 4):
		names.append(clan.data.display_name)
	while names.size() < 4:
		names.append("Trấn %d" % (names.size() + 1))
	return names


static func town_name(nation_id: StringName, town: int) -> String:
	var data := RealmMap.nation_data(nation_id)
	return data.capital if RealmMap.is_capital(town) else data.towns[_ring_index(town)]


static func garrison_for(town: int, scale: float) -> int:
	var base := GARRISON_BY_DISTANCE[RealmMap.region_distance(RealmMap.region_of(town))] * scale
	return roundi(base * (CAPITAL_GARRISON if RealmMap.is_capital(town) else 1.0))


func nation_in(region: int) -> Nation:
	for nation in nations.values():
		if nation.region == region:
			return nation
	return null


func owner_color(town: Town, player_color: Color) -> Color:
	return player_color if town.owner == PLAYER else nations[town.owner].color


func owner_name(town: Town, kingdom_name: String) -> String:
	return kingdom_name if town.owner == PLAYER else nations[town.owner].name


func captured_towns() -> Array[Town]:
	return towns.filter(func(town: Town) -> bool: return town.is_captured())


func count_owned(owner: StringName) -> int:
	return towns.filter(func(town: Town) -> bool: return town.owner == owner).size()


func forces_at(town: int) -> Array[Force]:
	return forces.filter(func(force: Force) -> bool: return force.town == town)


# --- Armies -------------------------------------------------------------------------------

func check_form(state: KingdomState, general: General, squads: Array[Army.Squad]) -> Result:
	if not active:
		return Result.NOT_ACTIVE
	if general == null:
		return Result.NO_GENERAL
	if not state.generals.generals.has(general) or not general.is_ready():
		return Result.GENERAL_BUSY
	return _check_squads(state, squads, null)


func _check_squads(state: KingdomState, squads: Array[Army.Squad], force: Force) -> Result:
	if squads.is_empty():
		return Result.NO_SQUADS
	if squads.size() > MAX_ARMY_SQUADS:
		return Result.TOO_MANY_SQUADS
	for squad in squads:
		if not state.army.squads.has(squad) or (squad.away and (force == null or not force.squads.has(squad))):
			return Result.SQUAD_BUSY
	return Result.OK


## A new army at the kingdom's capital. Nothing changes unless check_form is OK.
func form(state: KingdomState, general: General, squads: Array[Army.Squad]) -> Result:
	var result := check_form(state, general, squads)
	if result != Result.OK:
		return result
	var force := Force.new()
	force.general = general
	forces.append(force)
	_set_away(general, true, "dẫn đạo quân")
	_assign_squads(state, force, squads)
	state.generals.changed.emit()
	return Result.OK


## Changes the squads of an army standing at the kingdom's capital.
func check_regroup(state: KingdomState, force: Force, squads: Array[Army.Squad]) -> Result:
	if force.town != HOME_CAPITAL:
		return Result.NOT_AT_CAPITAL
	return _check_squads(state, squads, force)


func regroup(state: KingdomState, force: Force, squads: Array[Army.Squad]) -> Result:
	var result := check_regroup(state, force, squads)
	if result == Result.OK:
		_assign_squads(state, force, squads)
	return result


func _assign_squads(state: KingdomState, force: Force, squads: Array[Army.Squad]) -> void:
	for squad in force.squads:
		_set_away(squad, false)
	force.squads.assign(squads)
	for squad in squads:
		_set_away(squad, true, "theo đạo quân %s" % force.general.name)
	state.army.changed.emit()


## Sends the army's squads and general home (at the capital only, unless `anywhere`).
func disband(state: KingdomState, force: Force, anywhere: bool = false) -> Result:
	if not anywhere and force.town != HOME_CAPITAL:
		return Result.NOT_AT_CAPITAL
	for squad in force.squads:
		_set_away(squad, false)
	if force.general != null:
		_set_away(force.general, false)
	forces.erase(force)
	state.army.changed.emit()
	state.generals.changed.emit()
	return Result.OK


static func _set_away(who: Object, away: bool, duty: String = "") -> void:
	who.away = away
	who.duty = duty if away else ""


## Marching to a neighboring town of the kingdom (enemy towns are taken by check_siege).
func check_move(force: Force, town: int) -> Result:
	var basic := _check_step(force, town)
	if basic != Result.OK:
		return basic
	return Result.OK if towns[town].owner == PLAYER else Result.ENEMY_TOWN


func _check_step(force: Force, town: int) -> Result:
	if not active:
		return Result.NOT_ACTIVE
	if force.moved:
		return Result.ALREADY_MOVED
	if not RealmMap.are_neighbors(force.town, town):
		return Result.NOT_NEIGHBOR
	return Result.OK


func move(force: Force, town: int) -> Result:
	var result := check_move(force, town)
	if result == Result.OK:
		force.town = town
		force.moved = true
	return result


func check_siege(force: Force, town: int) -> Result:
	var basic := _check_step(force, town)
	if basic != Result.OK:
		return basic
	if towns[town].owner == PLAYER:
		return Result.OWN_TOWN
	if force.general == null or force.general.wounded_turns > 0:
		return Result.GENERAL_WOUNDED
	return Result.OK


## The siege battle: the army attacks the town's garrison behind its walls. Null unless check_siege is OK.
func create_siege(state: KingdomState, force: Force, town_id: int) -> BattleSimulator:
	if check_siege(force, town_id) != Result.OK:
		return null
	var town := towns[town_id]
	var attackers := force_side(state, force)
	var defenders := BattleSide.new("%s (%s)" % [town.name, nations[town.owner].name])
	defenders.color = nations[town.owner].color
	add_nation_units(defenders, nations[town.owner], town.garrison, state)
	_man_walls(defenders, town)
	return BattleSimulator.new(attackers, defenders, rng.randi())


## The army as a battle side, led by its general.
func force_side(state: KingdomState, force: Force) -> BattleSide:
	var side := BattleSide.new("Đạo quân %s" % force.general.name if force.general != null else state.kingdom_name)
	side.color = state.player_color
	for squad in force.squads:
		side.add_unit(state.units[squad.unit_id], squad.soldiers, squad)
	state.bless_army(side)
	if force.general != null and force.general.wounded_turns <= 0:
		state.generals.lead_officer(side, force.general, state.generals.active_trait(force.general, state.board, false))
	return side


## The nation's soldiers: half its own favored units, half the usual ones of its strength.
func add_nation_units(side: BattleSide, nation: Nation, soldiers: int, state: KingdomState) -> void:
	var tier := clampi(nation.distance(), 1, ClanLayout.ARMY_TIERS.size() - 1)
	var data := RealmMap.nation_data(nation.id)
	var weights := {}
	var usual: Dictionary = ClanLayout.ARMY_TIERS[tier]
	var special: Dictionary = data.special[clampi(nation.distance() - 1, 0, data.special.size() - 1)]
	for pair in [[usual, 0.5], [special, 0.5]]:
		var table: Dictionary = pair[0]
		var total := 0.0
		for unit_id in table:
			total += table[unit_id]
		for unit_id in table:
			weights[StringName(unit_id)] = weights.get(StringName(unit_id), 0.0) + table[unit_id] / total * pair[1]
	_add_weighted(side, weights, soldiers, state)


static func _add_weighted(side: BattleSide, weights: Dictionary, soldiers: int, state: KingdomState) -> void:
	var ids := weights.keys()
	var remaining := soldiers
	for i in ids.size():
		var unit: UnitData = state.units.get(ids[i])
		if unit == null:
			continue
		var share := remaining if i == ids.size() - 1 else mini(remaining, roundi(soldiers * weights[ids[i]]))
		remaining -= share
		while share > 0:
			var count := mini(share, state.wars.squad_size(unit))
			side.add_unit(unit, count)
			share -= count


## The walls: every defender (lent or not) fights better and holds longer.
static func _man_walls(side: BattleSide, town: Town) -> void:
	for unit in side.units:
		unit.defense_mult += CAPITAL_WALL_DEFENSE if town.is_capital() else WALL_DEFENSE
		unit.morale += CAPITAL_WALL_MORALE if town.is_capital() else WALL_MORALE


## Applies a finished siege. Returns BattleOutcome.apply_to_army's report plus {"record", "won",
## "town", "enemy_lost", "general" (Generals.after_battle_of), "loot", "destroyed" (nation id or
## &""), "gained": town ids handed over with a destroyed nation, "disbanded" (the army is gone)}.
func finish_siege(state: KingdomState, force: Force, town_id: int, record: BattleRecord) -> Dictionary:
	var town := towns[town_id]
	var won := record.winner == BattleRecord.ATTACKER
	state.count_stat("battles_won" if won else "battles_lost")
	var result := BattleOutcome.apply_to_army(state.army, record, BattleRecord.ATTACKER, false,
			state.building_effect(&"retreat_keep"))
	var general := _general_after(state, force, record, BattleRecord.ATTACKER)
	var enemy_lost := BattleOutcome.soldiers_lost(record, BattleRecord.DEFENDER)
	town.garrison = maxi(0, town.garrison - enemy_lost)
	_drop_lost_squads(state, force)
	force.moved = true
	var loot: Dictionary[StringName, int] = {}
	var destroyed: StringName = &""
	var gained: Array[int] = []
	if won:
		var old_owner := town.owner
		loot = capture(state, town)
		force.town = town_id
		if town.is_capital() and old_owner != PLAYER:
			destroyed = old_owner
			gained = destroy_nation(state, old_owner)
	var disbanded := force.squads.is_empty() or force.general == null
	if disbanded:
		disband(state, force, true)
	result.merge({"record": record, "won": won, "town": town_id, "enemy_lost": enemy_lost, "general": general,
			"loot": loot, "destroyed": destroyed, "gained": gained, "disbanded": disbanded,
			"item": state.equipment.roll_loot(true, state.stockpile) if won else {}})
	return result


## The general of `force` after a battle: Generals.after_battle_of; a dead general leaves the army.
func _general_after(state: KingdomState, force: Force, record: BattleRecord, side: int) -> Dictionary:
	if force == null or force.general == null:
		return {"name": "", "fate": &"none", "xp": 0, "levels": 0}
	state.generals.survival = state.building_effect(&"commander_survival")
	var general := force.general
	var result := state.generals.after_battle_of(general, record, side)
	if result.fate == &"dead":
		state.count_stat("commanders_lost")
		general.away = false
		general.duty = ""
		force.general = null
	return result


static func _drop_lost_squads(state: KingdomState, force: Force) -> void:
	force.squads.assign(force.squads.filter(func(squad: Army.Squad) -> bool: return state.army.squads.has(squad)))


## The town becomes the kingdom's: its garrison is gone and its loot taken. Returns the loot.
func capture(state: KingdomState, town: Town) -> Dictionary[StringName, int]:
	town.owner = PLAYER
	town.garrison = 0
	town.max_garrison = 0
	town.captured_turn = state.turn
	var loot: Dictionary[StringName, int] = {}
	for resource_id in CAPTURE_LOOT:
		loot[resource_id] = CAPTURE_LOOT[resource_id] * (CAPITAL_LOOT if town.is_capital() else 1)
	state.stockpile.add(loot)
	return loot


## The nation falls with its capital: its other towns are handed over. Returns their ids.
func destroy_nation(state: KingdomState, nation_id: StringName) -> Array[int]:
	nations[nation_id].destroyed = true
	var gained: Array[int] = []
	for town in towns:
		if town.owner == nation_id:
			town.owner = PLAYER
			town.garrison = 0
			town.max_garrison = 0
			town.captured_turn = state.turn
			gained.append(town.id)
	return gained


# --- Governors and what towns give ----------------------------------------------------------

func check_governor(officer: Officer, town_id: int) -> Result:
	if not active:
		return Result.NOT_ACTIVE
	var town := towns[town_id]
	if not town.is_captured():
		return Result.NOT_CAPTURED
	if town.governor != null:
		return Result.HAS_GOVERNOR
	if officer == null or not officer.is_ready():
		return Result.OFFICER_BUSY
	return Result.OK


func assign_governor(state: KingdomState, officer: Officer, town_id: int) -> Result:
	var result := check_governor(officer, town_id)
	if result == Result.OK:
		towns[town_id].governor = officer
		_set_away(officer, true, "trấn thủ %s" % towns[town_id].name)
		_officers_changed(state)
	return result


func remove_governor(state: KingdomState, town_id: int) -> void:
	var officer := towns[town_id].governor
	if officer == null:
		return
	towns[town_id].governor = null
	_set_away(officer, false)
	_officers_changed(state)


static func _officers_changed(state: KingdomState) -> void:
	state.generals.changed.emit()
	state.advisors.changed.emit()


## The governor's stat for the town's economy: Thống suất (general) or Nội chính (advisor).
static func economy_score(officer: Officer) -> int:
	if officer is General:
		return (officer as General).total_command()
	if officer is Advisor:
		return (officer as Advisor).stat_for(&"admin")
	return 0


## The governor's stat for the militia: Võ lực (general) or Mưu lược (advisor).
static func defense_score(officer: Officer) -> int:
	if officer is General:
		return (officer as General).total_might()
	if officer is Advisor:
		return (officer as Advisor).stat_for(&"military")
	return 0


func town_yield(town: Town) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	if not town.is_captured():
		return result
	var factor := float(CAPITAL_YIELD if town.is_capital() else 1)
	if town.governor == null:
		factor *= UNGOVERNED_SHARE
	else:
		factor *= 1.0 + economy_score(town.governor) * GOVERNOR_YIELD
	for resource_id in TOWN_YIELD:
		var amount := roundi(TOWN_YIELD[resource_id] * factor)
		if amount > 0:
			result[resource_id] = amount
	return result


func total_yield() -> Dictionary[StringName, int]:
	var total: Dictionary[StringName, int] = {}
	for town in captured_towns():
		Economy.add_into(total, town_yield(town))
	return total


func squad_bonus() -> int:
	return TOWN_SQUADS * count_owned(PLAYER) if active else 0


func replenish_bonus() -> float:
	return TOWN_REPLENISH * captured_towns().size()


func militia_soldiers(town: Town) -> int:
	return MILITIA_BASE + (defense_score(town.governor) * MILITIA_PER_POINT if town.governor != null else 0)


# --- Turns --------------------------------------------------------------------------------

## End of a turn: garrisons regrow, armies resting on kingdom towns regain soldiers, orders reset,
## and a nation may counterattack. Returns {"replenished": soldiers regained, "counter": the
## pending counterattack ({} without one)}.
func end_turn(state: KingdomState) -> Dictionary:
	pending_counter = {}
	if not active:
		return {"replenished": 0, "counter": {}}
	# Squads that deserted (unpaid upkeep) or were lost elsewhere leave their army; an empty army
	# breaks up.
	for force in forces.duplicate():
		_drop_lost_squads(state, force)
		if force.squads.is_empty() or force.general == null or not state.generals.generals.has(force.general):
			disband(state, force, true)
	for town in towns:
		if town.owner != PLAYER and town.garrison < town.max_garrison:
			town.garrison = mini(town.max_garrison, town.garrison + ceili(town.max_garrison * GARRISON_REGEN))
	var regained := 0
	for force in forces:
		if not force.moved and towns[force.town].owner == PLAYER:
			var fraction := (CAPITAL_REPLENISH if force.town == HOME_CAPITAL else ARMY_REPLENISH) + replenish_bonus()
			for squad in force.squads:
				var full := state.units[squad.unit_id].squad_size
				var gain := mini(ceili(full * fraction), full - squad.soldiers)
				if gain > 0:
					state.army.add_soldiers(squad, gain)
					regained += gain
		force.moved = false
	var targets := counter_targets(state.turn + 1)
	if not targets.is_empty() and rng.randf() < COUNTER_CHANCE:
		var town: Town = targets[rng.randi_range(0, targets.size() - 1)]
		var source := _strongest_neighbor(town)
		var sent := roundi(source.garrison * COUNTER_SHARE)
		source.garrison -= sent
		pending_counter = {"town": town.id, "source": source.id, "sent": sent}
	return {"replenished": regained, "counter": pending_counter}


## Towns their old nation can strike back at on `turn`.
func counter_targets(turn: int) -> Array[Town]:
	var result: Array[Town] = []
	for town in captured_towns():
		if nations[town.nation].destroyed or turn - town.captured_turn < COUNTER_GRACE:
			continue
		var source := _strongest_neighbor(town)
		if source != null and roundi(source.garrison * COUNTER_SHARE) >= COUNTER_MIN:
			result.append(town)
	return result


## The neighboring town of the town's old nation with the biggest garrison, or null.
func _strongest_neighbor(town: Town) -> Town:
	var best: Town = null
	for id in RealmMap.neighbors(town.id):
		var other := towns[id]
		if other.owner == town.nation and (best == null or other.garrison > best.garrison):
			best = other
	return best


## The army defending `town` (the first one there), or null.
func defender_of(town_id: int) -> Force:
	var here := forces_at(town_id)
	return here[0] if not here.is_empty() else null


## The pending counterattack's battle: the nation attacks, the town's army and militia defend.
func create_counter(state: KingdomState) -> BattleSimulator:
	if pending_counter.is_empty():
		return null
	var town := towns[pending_counter.town]
	var nation := nations[town.nation]
	var attackers := BattleSide.new("Quân %s" % nation.name)
	attackers.color = nation.color
	add_nation_units(attackers, nation, pending_counter.sent, state)
	var force := defender_of(town.id)
	var defenders: BattleSide
	if force != null:
		defenders = force_side(state, force)
	else:
		defenders = BattleSide.new("Dân binh %s" % town.name)
		defenders.color = state.player_color
	var militia := {}
	for unit_id in MILITIA_UNITS:
		militia[unit_id] = MILITIA_UNITS[unit_id] / MILITIA_UNITS.size()
	_add_weighted(defenders, militia, militia_soldiers(town), state)
	_man_walls(defenders, town)
	return BattleSimulator.new(attackers, defenders, rng.randi())


## Applies the counterattack's battle. Lost: the town goes back to its nation with the attackers'
## survivors, its governor comes home and its armies fall back to a neighboring kingdom town (or
## the capital). Won: the survivors go back to where they came from.
## Returns apply_to_army's report plus {"record", "won", "town", "nation", "enemy_lost", "general",
## "lost_town": bool, "retreated_to": town id or -1, "governor": name of the governor sent home}.
func finish_counter(state: KingdomState, record: BattleRecord) -> Dictionary:
	var town := towns[pending_counter.town]
	var source := towns[pending_counter.source]
	var sent: int = pending_counter.sent
	pending_counter = {}
	var won := record.winner == BattleRecord.DEFENDER
	state.count_stat("battles_won" if won else "battles_lost")
	var force := defender_of(town.id)
	var result := BattleOutcome.apply_to_army(state.army, record, BattleRecord.DEFENDER, false,
			state.building_effect(&"retreat_keep"))
	var general := _general_after(state, force, record, BattleRecord.DEFENDER)
	var enemy_lost := BattleOutcome.soldiers_lost(record, BattleRecord.ATTACKER)
	var survivors := maxi(0, sent - enemy_lost)
	var governor := ""
	var retreated_to := -1
	if won:
		if source.owner == town.nation:
			source.garrison = mini(source.max_garrison, source.garrison + survivors)
	else:
		town.owner = town.nation
		town.max_garrison = garrison_for(town.id, state.wars.enemy_scale)
		town.garrison = mini(town.max_garrison, survivors)
		if town.governor != null:
			governor = town.governor.name
			remove_governor(state, town.id)
		retreated_to = _fallback(town.id)
		for other in forces_at(town.id):
			other.town = retreated_to
	if force != null:
		_drop_lost_squads(state, force)
		if force.squads.is_empty() or force.general == null:
			disband(state, force, true)
	result.merge({"record": record, "won": won, "town": town.id, "nation": town.nation, "enemy_lost": enemy_lost,
			"general": general, "lost_town": not won, "retreated_to": retreated_to, "governor": governor})
	return result


## A kingdom town next to `town_id`, else the capital.
func _fallback(town_id: int) -> int:
	for id in RealmMap.neighbors(town_id):
		if towns[id].owner == PLAYER:
			return id
	return HOME_CAPITAL


static func describe(result: Result) -> String:
	match result:
		Result.NOT_ACTIVE:
			return "Chưa bắt đầu Phân Chia Thiên Hạ."
		Result.NO_GENERAL:
			return "Đạo quân cần một tướng dẫn đầu."
		Result.GENERAL_BUSY:
			return "Tướng này đang bận hoặc bị thương."
		Result.NO_SQUADS:
			return "Chọn ít nhất một đơn vị lính."
		Result.TOO_MANY_SQUADS:
			return "Một đạo quân tối đa %d đơn vị." % MAX_ARMY_SQUADS
		Result.SQUAD_BUSY:
			return "Có đơn vị đang ở nơi khác."
		Result.NOT_AT_CAPITAL:
			return "Đạo quân phải ở kinh đô."
		Result.ALREADY_MOVED:
			return "Đạo quân đã hành quân lượt này."
		Result.NOT_NEIGHBOR:
			return "Chỉ đi được tới trấn kề bên theo đường."
		Result.ENEMY_TOWN:
			return "Trấn của địch: phải công thành."
		Result.OWN_TOWN:
			return "Trấn này đã là của ta."
		Result.GENERAL_WOUNDED:
			return "Tướng đang bị thương, chưa công thành được."
		Result.NOT_CAPTURED:
			return "Chỉ trấn chiếm được mới cần thái thú."
		Result.OFFICER_BUSY:
			return "Người này đang bận hoặc bị thương."
		Result.HAS_GOVERNOR:
			return "Trấn đã có thái thú."
	return ""


# --- Save (GDD §10.1) ---------------------------------------------------------------------

func to_save(state: KingdomState) -> Dictionary:
	if not active:
		return {}
	var town_saves: Array = []
	for town in towns:
		town_saves.append({"name": town.name, "nation": String(town.nation), "owner": String(town.owner),
				"garrison": town.garrison, "max": town.max_garrison, "captured_turn": town.captured_turn,
				"governor": _officer_ref(state, town.governor)})
	var nation_saves := {}
	for nation in nations.values():
		nation_saves[String(nation.id)] = {"region": nation.region, "destroyed": nation.destroyed}
	var force_saves: Array = []
	for force in forces:
		force_saves.append({"general": state.generals.generals.find(force.general), "town": force.town,
				"moved": force.moved,
				"squads": force.squads.map(func(squad: Army.Squad) -> int: return state.army.squads.find(squad))})
	return {"towns": town_saves, "nations": nation_saves, "forces": force_saves}


static func _officer_ref(state: KingdomState, officer: Officer) -> Dictionary:
	if officer is General:
		return {"kind": "general", "index": state.generals.generals.find(officer)}
	if officer is Advisor:
		return {"kind": "advisor", "index": state.advisors.advisors.find(officer)}
	return {}


static func _officer_from(state: KingdomState, ref: Dictionary) -> Officer:
	var index := int(ref.get("index", -1))
	var list: Array = state.generals.generals if ref.get("kind", "") == "general" else state.advisors.advisors \
			if ref.get("kind", "") == "advisor" else []
	return list[index] if index >= 0 and index < list.size() else null


## Restores the phase; officers and squads by their index in the state (loaded before).
func load_save(data: Dictionary, state: KingdomState) -> void:
	active = not data.is_empty()
	towns.clear()
	nations.clear()
	forces.clear()
	pending_counter = {}
	if not active:
		return
	for nation_id: String in data.nations:
		var entry: Dictionary = data.nations[nation_id]
		var nation := Nation.new()
		nation.id = StringName(nation_id)
		nation.name = RealmMap.nation_data(nation.id).get("name", nation_id)
		nation.region = int(entry.region)
		nation.destroyed = bool(entry.destroyed)
		nation.color = RealmMap.nation_color(nation.id, state.player_color)
		nations[nation.id] = nation
	for i in data.towns.size():
		var entry: Dictionary = data.towns[i]
		var town := Town.new()
		town.id = i
		town.name = entry.name
		town.nation = StringName(entry.nation)
		town.owner = StringName(entry.owner)
		town.garrison = int(entry.garrison)
		town.max_garrison = int(entry.max)
		town.captured_turn = int(entry.captured_turn)
		town.governor = _officer_from(state, entry.get("governor", {}))
		if town.governor != null:
			_set_away(town.governor, true, "trấn thủ %s" % town.name)
		towns.append(town)
	for entry: Dictionary in data.forces:
		var index := int(entry.general)
		if index < 0 or index >= state.generals.generals.size():
			continue
		var force := Force.new()
		force.general = state.generals.generals[index]
		force.town = int(entry.town)
		force.moved = bool(entry.moved)
		for squad_index in entry.squads:
			if int(squad_index) >= 0 and int(squad_index) < state.army.squads.size():
				force.squads.append(state.army.squads[int(squad_index)])
		_set_away(force.general, true, "dẫn đạo quân")
		for squad in force.squads:
			_set_away(squad, true, "theo đạo quân %s" % force.general.name)
		forces.append(force)
