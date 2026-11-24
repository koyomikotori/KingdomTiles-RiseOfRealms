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
## - Armies standing on a kingdom town regain a share of every squad's full size each turn
##   (end_turn, replenish_share): half the kingdom's own share (KingdomState.replenish_fraction)
##   up to TOWN_REPLENISH_CAP, the whole share up to CAPITAL_REPLENISH_CAP on a capital.
## - Several armies ordered against the same town fight its siege together (M18g).
## - Captured towns pay TOWN_YIELD, add squads to the kingdom's capacity and replenishment.
## - The nations' armies (NationArmy, RealmWar, M18f-b1): each nation raises armies from a
##   treasury, announces an attack a turn ahead and carries it out when the next turn ends; against
##   a town of ours it is fought at the start of the turn after (pending_attacks), between nations
##   it is simulated at once. Our armies can intercept an army that announced an attack.
## - Revolts (end_turn, M18g): a captured town may rise (revolt_chance: less with an army there,
##   much less once its nation is gone). Without an army it is lost at once; with one the rebels
##   attack at the start of the next turn (pending_revolt). A lost town goes back to its nation, or
##   to the rebels (REBELS) when the nation is gone.

enum Result { OK, NOT_ACTIVE, NO_GENERAL, GENERAL_BUSY, NO_SQUADS, TOO_MANY_SQUADS, SQUAD_BUSY, NOT_AT_CAPITAL,
		ALREADY_MOVED, NOT_NEIGHBOR, ENEMY_TOWN, OWN_TOWN, GENERAL_WOUNDED, ALREADY_HOME, NO_ROUTE, NO_ORDER, NO_ENEMY_ARMY, NOT_MARCHING,
		NOT_CONQUERED, ALREADY_VASSAL, IS_COMMANDER }

## Army orders (GDD §34, M18g): given during the turn, carried out when it ends (a march, a step of
## the way home) or at the start of the next one (a siege, after the turn's raid or expedition).
const MOVE: StringName = &"move"
const SIEGE: StringName = &"siege"
const HOME: StringName = &"home"
## Attacking an enemy army that announced an attack, in the open (M18f-b1): `target` is its town,
## `army` its id; fought at the start of the next turn like a siege.
const INTERCEPT: StringName = &"intercept"
## Save format of the realm: 2 = halved garrisons and nation armies (M18f-b1).
const SAVE_VERSION := 2

const PLAYER: StringName = &"player"
## The owner of a town that rose against us after its nation was destroyed.
const REBELS: StringName = &"rebels"
const REBEL_NAME := "Quân nổi loạn"
const REBEL_COLOR := Color(0.42, 0.36, 0.3)
const HOME_CAPITAL := RealmMap.HOME_REGION * RealmMap.TOWNS_PER_REGION + RealmMap.CAPITAL
## Generals the kingdom may keep in the realm phase (GDD §33: 3 → 9).
const MAX_GENERALS := 9
const MAX_ARMY_SQUADS := 20
## Garrison soldiers of a town by its region's distance from the kingdom (1 … 3).
const GARRISON_BY_DISTANCE: Array[int] = [0, 110, 160, 220]
const CAPITAL_GARRISON := 2.0
const GARRISON_REGEN := 0.1
## The walls: defenders' defense multiplier and morale (capitals more).
const WALL_DEFENSE := 0.15
const CAPITAL_WALL_DEFENSE := 0.3
const WALL_MORALE := 2.0
const CAPITAL_WALL_MORALE := 4.0
## The share of a squad's full size an army regains a turn on a town of ours: the kingdom's own
## replenishment × TOWN_REPLENISH_SHARE up to TOWN_REPLENISH_CAP, on a capital (ours or taken) the
## whole of it up to CAPITAL_REPLENISH_CAP. TOWN_REPLENISH per captured town is added to the
## kingdom's own replenishment.
const TOWN_REPLENISH_SHARE := 0.5
const TOWN_REPLENISH_CAP := 0.15
const CAPITAL_REPLENISH_CAP := 0.3
const TOWN_REPLENISH := 0.01
## Squads every town of ours (the five home towns too) adds to the kingdom's capacity.
const TOWN_SQUADS := 5
## What a captured town pays a turn (a capital CAPITAL_YIELD times that).
const TOWN_YIELD: Dictionary[StringName, int] = {&"food": 15, &"wood": 10, &"stone": 10, &"ore": 3,
		&"hardwood": 3, &"horses": 3}
const CAPITAL_YIELD := 2
## Taken once when a town falls (a capital CAPITAL_LOOT times that).
const CAPTURE_LOOT: Dictionary[StringName, int] = {&"food": 120, &"wood": 120, &"stone": 120, &"ore": 40,
		&"hardwood": 40, &"horses": 40}
const CAPITAL_LOOT := 3
## A captured town's own defenders: MILITIA_BASE peasants; a town of the united clans has
## HOME_MILITIA (M18f-b1: the nations' armies can attack it).
const MILITIA_BASE := 40
const HOME_MILITIA := 300
const MILITIA_UNITS: Dictionary[StringName, float] = {&"spearman": 1.0, &"archer": 1.0}
## The fewest rebels that rise in a town.
const REBEL_MIN := 40
## Revolts: chance a turn for a captured town left alone, with an army in it, and once its nation
## is destroyed; none in the first REVOLT_GRACE turns. The
## rebels number REBEL_SHARE of the town's usual garrison.
const REVOLT_CHANCE := 0.20
const REVOLT_GUARDED := 0.12
const REVOLT_PACIFIED := 0.02
const REVOLT_GRACE := 2
const REBEL_SHARE := 0.4
## Pacifying a destroyed nation's land (GDD §36, M18f-b2a): REVOLT_PACIFIED until a vassal king is
## crowned there, then PACIFY_STEP less a turn for PACIFY_TURNS turns (2% → 1%), minus
## VASSAL_COMMAND_CUT per point of the king's own Thống suất (never below 0).
const PACIFY_STEP := 0.002
const PACIFY_TURNS := 5
const VASSAL_COMMAND_CUT := 0.0005
## A vassal's soldiers guarding every town of its land: VASSAL_GUARD_BASE + VASSAL_GUARD_PER_MIGHT
## per point of the king's own Võ lực (items go back to us when crowned).
const VASSAL_GUARD_BASE := 40
const VASSAL_GUARD_PER_MIGHT := 5
## Tribute a turn: TRIBUTE_BASIC_PER_STAR × the king's stars of food, wood and stone; from
## TRIBUTE_RARE_FROM stars also TRIBUTE_RARE_PER_STAR × (stars − TRIBUTE_RARE_FROM + 1) of ore,
## hardwood and horses (4★ 2, 5★ 4, 6★ 6).
const TRIBUTE_BASIC_PER_STAR := 5
const TRIBUTE_BASIC: Array[StringName] = [&"food", &"wood", &"stone"]
const TRIBUTE_RARE_FROM := 4
const TRIBUTE_RARE_PER_STAR := 2
const TRIBUTE_RARE: Array[StringName] = [&"ore", &"hardwood", &"horses"]


class Town:
	extends RefCounted
	var id: int
	var name: String
	## The nation the town belonged to at the start (PLAYER for the kingdom's region).
	var nation: StringName
	var owner: StringName
	var garrison := 0
	var max_garrison := 0
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
	## The vassal king ruling its land for us once it is destroyed (GDD §36), else null; crowned on
	## `vassal_turn`.
	var vassal: General = null
	var vassal_turn := 0

	func capital() -> int:
		return RealmMap.town_id(region, RealmMap.CAPITAL)

	func distance() -> int:
		return RealmMap.region_distance(region)


class Force:
	extends RefCounted
	var general: General
	var squads: Array[Army.Squad] = []
	var town := HOME_CAPITAL
	## The standing order: &"" (none), MOVE / SIEGE `target`, or HOME (to the capital).
	var order: StringName = &""
	var target := -1
	## The turn the order was given (a siege is fought on a later turn's start).
	var order_turn := 0
	## The enemy army an INTERCEPT order is against (NationArmy.id), else -1.
	var army := -1

	func has_order() -> bool:
		return order != &""

	func soldiers() -> int:
		var total := 0
		for squad in squads:
			total += squad.soldiers
		return total


var active := false
var towns: Array[Town] = []
var nations: Dictionary[StringName, Nation] = {}
var forces: Array[Force] = []
## The nations' armies, their treasuries (nation id -> points) and the next army id.
var armies: Array[NationArmy] = []
var treasury: Dictionary[StringName, float] = {}
var next_army_id := 1
## Attacks on towns of ours waiting for the start of the turn: [{"town", "armies": [army ids]}]
## (end_turn → create_enemy_attack / finish_enemy_attack, first one first); saved.
var pending_attacks: Array[Dictionary] = []
## The nations act at the end of a turn (tests turn it off to keep the map still).
var ai_enabled := true
## The revolt waiting to be fought at the start of the turn: {"town", "rebels"} (end_turn →
## create_revolt / finish_revolt); saved.
var pending_revolt := {}
var rng := RandomNumberGenerator.new()


## Starts the phase: the nations take shuffled regions, every town gets its name and garrison.
func start(state: KingdomState) -> void:
	active = true
	towns.clear()
	nations.clear()
	forces.clear()
	armies.clear()
	treasury.clear()
	pending_attacks.clear()
	next_army_id = 1
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
	for nation in RealmWar.live_nations(self):
		RealmWar.raise_army(self, state, nation)


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


## The rebels as a nation (made the first time a town falls to them).
func _rebels() -> Nation:
	if not nations.has(REBELS):
		var nation := Nation.new()
		nation.id = REBELS
		nation.name = REBEL_NAME
		nation.region = -1
		nation.color = REBEL_COLOR
		nations[REBELS] = nation
	return nations[REBELS]


func captured_towns() -> Array[Town]:
	return towns.filter(func(town: Town) -> bool: return town.is_captured())


func count_owned(owner: StringName) -> int:
	return towns.filter(func(town: Town) -> bool: return town.owner == owner).size()


func forces_at(town: int) -> Array[Force]:
	return forces.filter(func(force: Force) -> bool: return force.town == town)


func armies_at(town: int) -> Array[NationArmy]:
	return armies.filter(func(army: NationArmy) -> bool: return army.town == town)


func armies_of(nation_id: StringName) -> Array[NationArmy]:
	return armies.filter(func(army: NationArmy) -> bool: return army.nation == nation_id)


func army_by_id(id: int) -> NationArmy:
	for army in armies:
		if army.id == id:
			return army
	return null


## Enemy armies whose announced attack is on `town`.
func armies_targeting(town: int) -> Array[NationArmy]:
	return armies.filter(func(army: NationArmy) -> bool: return army.target == town)


## The army is gone (beaten): it leaves the map and any attack waiting for it.
func remove_army(army: NationArmy) -> void:
	armies.erase(army)
	for entry in pending_attacks:
		entry.armies.erase(army.id)
	pending_attacks.assign(pending_attacks.filter(func(entry: Dictionary) -> bool: return not entry.armies.is_empty()))


## Takes `lost` soldiers from an enemy town's garrison and its owner's armies there, in proportion.
func spread_town_losses(town: Town, lost: int) -> void:
	var here := armies_at(town.id)
	var total := town.garrison
	for army in here:
		total += army.soldiers
	if total <= 0:
		return
	town.garrison = maxi(0, town.garrison - roundi(float(lost) * town.garrison / total))
	for army in here:
		army.soldiers = maxi(0, army.soldiers - roundi(float(lost) * army.soldiers / total))
		if army.soldiers <= 0:
			remove_army(army)


## Soldiers defending an enemy town: its garrison and its owner's armies in it; on a town of ours
## the vassal's guard and armies there.
func town_soldiers(town: Town) -> int:
	var total := town.garrison + vassal_guard(town)
	for army in armies_at(town.id):
		total += army.soldiers
	return total


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
	if not RealmMap.are_neighbors(force.town, town):
		return Result.NOT_NEIGHBOR
	return Result.OK


## Orders the army to `town`: a march to a town of ours, a siege of an enemy one. Replaces any
## order it had; nothing happens until the turn ends (GDD §34).
func order(force: Force, town: int, turn: int) -> Result:
	var result := check_move(force, town)
	if result == Result.ENEMY_TOWN:
		result = check_siege(force, town)
		if result == Result.OK:
			_set_order(force, SIEGE, town, turn)
		return result
	if result == Result.OK:
		_set_order(force, MOVE, town, turn)
	return result


## Orders the army home to the capital, one road a turn through towns of ours.
func check_home(force: Force) -> Result:
	if not active:
		return Result.NOT_ACTIVE
	if force.town == HOME_CAPITAL:
		return Result.ALREADY_HOME
	return Result.OK if not route(force.town, HOME_CAPITAL).is_empty() else Result.NO_ROUTE


func order_home(force: Force, turn: int) -> Result:
	var result := check_home(force)
	if result == Result.OK:
		_set_order(force, HOME, HOME_CAPITAL, turn)
	return result


func cancel_order(force: Force) -> Result:
	if not force.has_order():
		return Result.NO_ORDER
	_set_order(force, &"", -1, 0)
	return Result.OK


func _set_order(force: Force, kind: StringName, town: int, turn: int) -> void:
	force.order = kind
	force.target = town
	force.order_turn = turn
	force.army = -1


## The shortest way from `from` to `to` along roads through towns of ours (both ends excluded
## from the check of `from`): the towns to walk, `to` last; empty when there is none.
func route(from: int, to: int) -> Array[int]:
	var came_from := {from: -1}
	var queue: Array[int] = [from]
	while not queue.is_empty():
		var town: int = queue.pop_front()
		if town == to:
			var path: Array[int] = []
			while town != from:
				path.push_front(town)
				town = came_from[town]
			return path
		for next in RealmMap.neighbors(town):
			if not came_from.has(next) and towns[next].owner == PLAYER:
				came_from[next] = town
				queue.append(next)
	return []


## The town the army's order takes it to next (-1 without one): the target, or the next step home.
func next_town(force: Force) -> int:
	match force.order:
		MOVE, SIEGE:
			return force.target
		HOME:
			var path := route(force.town, HOME_CAPITAL)
			return path[0] if not path.is_empty() else -1
	return -1


## Armies whose siege is due at the start of `turn` (ordered on an earlier turn).
func due_sieges(turn: int) -> Array[Force]:
	var result: Array[Force] = []
	for force in forces:
		if force.order == SIEGE and force.order_turn < turn:
			result.append(force)
	return result


## The due sieges grouped by their town: armies ordered against the same town fight it together.
## [[Force, …], …] in the order of the first army of each group.
func due_siege_groups(turn: int) -> Array[Array]:
	var groups: Array[Array] = []
	var by_town := {}
	for force in due_sieges(turn):
		if not by_town.has(force.target):
			by_town[force.target] = groups.size()
			groups.append([])
		groups[by_town[force.target]].append(force)
	return groups


## Every army with a siege order against `town` (due or not).
func besiegers(town: int) -> Array[Force]:
	return forces.filter(func(force: Force) -> bool: return force.order == SIEGE and force.target == town)


## The army whose general leads a joint siege: the most stars, then the most soldiers.
static func leader_of(group: Array) -> Force:
	var best: Force = null
	for force: Force in group:
		if best == null or force.general.stars > best.general.stars \
				or (force.general.stars == best.general.stars and force.soldiers() > best.soldiers()):
			best = force
	return best


func check_siege(force: Force, town: int) -> Result:
	var basic := _check_step(force, town)
	if basic != Result.OK:
		return basic
	if towns[town].owner == PLAYER:
		return Result.OWN_TOWN
	if force.general == null or force.general.wounded_turns > 0:
		return Result.GENERAL_WOUNDED
	return Result.OK


## The siege battle: the armies of `group` attack the town's garrison behind its walls, led by
## leader_of(group). Null unless check_siege is OK for every one of them.
func create_siege(state: KingdomState, group: Array, town_id: int) -> BattleSimulator:
	if group.is_empty():
		return null
	for force: Force in group:
		if check_siege(force, town_id) != Result.OK:
			return null
	var town := towns[town_id]
	var attackers := group_side(state, group)
	var defenders := BattleSide.new("%s (%s)" % [town.name, nations[town.owner].name])
	defenders.color = nations[town.owner].color
	add_nation_units(defenders, nations[town.owner], town_soldiers(town), state)
	var guard := RealmWar.leader_of(armies_at(town.id))
	if guard != null:
		state.generals.lead_officer(defenders, guard.general)
	man_walls(defenders, town)
	return BattleSimulator.new(attackers, defenders, rng.randi())


## The army as a battle side, led by its general.
func force_side(state: KingdomState, force: Force) -> BattleSide:
	return group_side(state, [force])


## One battle side for several armies together: every squad, blessed once, led by the leader's general.
func group_side(state: KingdomState, group: Array) -> BattleSide:
	var leader := leader_of(group)
	var title := "Đạo quân %s" % leader.general.name if leader != null and leader.general != null else state.kingdom_name
	if group.size() > 1:
		title = "Liên quân %d đạo" % group.size()
	var side := BattleSide.new(title)
	side.color = state.player_color
	for force: Force in group:
		for squad in force.squads:
			side.add_unit(state.units[squad.unit_id], squad.soldiers, squad)
	state.bless_army(side)
	if leader != null and leader.general != null and leader.general.wounded_turns <= 0:
		state.generals.lead_officer(side, leader.general, state.generals.active_trait(leader.general, state.board, false))
	return side


## The nation's soldiers: half its own favored units, half the usual ones of its strength.
func add_nation_units(side: BattleSide, nation: Nation, soldiers: int, state: KingdomState) -> void:
	if nation.id == REBELS:
		_add_rebels(side, soldiers, state)
		return
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


## Rebels: peasants and the weakest clan troops.
static func _add_rebels(side: BattleSide, soldiers: int, state: KingdomState) -> void:
	var weights := {}
	var table: Dictionary = ClanLayout.ARMY_TIERS[1]
	var total := 0.0
	for unit_id in table:
		total += table[unit_id]
	for unit_id in table:
		weights[StringName(unit_id)] = table[unit_id] / total * 0.5
	for unit_id in MILITIA_UNITS:
		weights[unit_id] = weights.get(unit_id, 0.0) + MILITIA_UNITS[unit_id] / MILITIA_UNITS.size() * 0.5
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
static func man_walls(side: BattleSide, town: Town) -> void:
	for unit in side.units:
		unit.defense_mult += CAPITAL_WALL_DEFENSE if town.is_capital() else WALL_DEFENSE
		unit.morale += CAPITAL_WALL_MORALE if town.is_capital() else WALL_MORALE


## Applies a finished siege by the armies of `group`. Returns BattleOutcome.apply_to_army's report
## plus {"record", "won", "town", "enemy_lost", "general" (the leader's Generals.after_battle_of),
## "loot", "destroyed" (nation id or &""), "gained": town ids handed over with a destroyed nation,
## "disbanded": armies that broke up, "armies": how many fought}. Won: every army moves in.
func finish_siege(state: KingdomState, group: Array, town_id: int, record: BattleRecord) -> Dictionary:
	var town := towns[town_id]
	var won := record.winner == BattleRecord.ATTACKER
	state.count_stat("battles_won" if won else "battles_lost")
	var result := BattleOutcome.apply_to_army(state.army, record, BattleRecord.ATTACKER, false,
			state.building_effect(&"retreat_keep"))
	var general := _general_after(state, leader_of(group), record, BattleRecord.ATTACKER)
	var enemy_lost := BattleOutcome.soldiers_lost(record, BattleRecord.DEFENDER)
	var loot: Dictionary[StringName, int] = {}
	var destroyed: StringName = &""
	var gained: Array[int] = []
	var holdouts: Array[int] = []
	if not won:
		spread_town_losses(town, enemy_lost)
	else:
		for army in armies_at(town_id):
			remove_army(army)
		var old_owner := town.owner
		loot = capture(state, town)
		if town.is_capital() and old_owner != PLAYER and old_owner != REBELS \
				and nations[old_owner].capital() == town_id:
			destroyed = old_owner
			gained = destroy_nation(state, old_owner, holdouts)
	var disbanded := 0
	for force: Force in group:
		_drop_lost_squads(state, force)
		_set_order(force, &"", -1, 0)
		if won:
			force.town = town_id
		if force.squads.is_empty() or force.general == null:
			disband(state, force, true)
			disbanded += 1
	result.merge({"record": record, "won": won, "town": town_id, "enemy_lost": enemy_lost, "general": general,
			"loot": loot, "destroyed": destroyed, "gained": gained, "holdouts": holdouts, "disbanded": disbanded, "armies": group.size(),
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


## The nation falls with its capital: its other towns are handed over, except the towns its
## armies stand in, which their soldiers hold as rebels (garrison = those soldiers); the armies
## break up. Returns the ids handed over; the rebel towns are appended to `holdouts`.
func destroy_nation(state: KingdomState, nation_id: StringName, holdouts: Array[int] = []) -> Array[int]:
	nations[nation_id].destroyed = true
	treasury.erase(nation_id)
	var left := {}
	for army in armies_of(nation_id):
		if towns[army.town].owner == nation_id:
			left[army.town] = left.get(army.town, 0) + army.soldiers
		remove_army(army)
	var gained: Array[int] = []
	for town in towns:
		if town.owner == nation_id and left.has(town.id):
			_rebels()
			town.owner = REBELS
			town.max_garrison = left[town.id]
			town.garrison = left[town.id]
			holdouts.append(town.id)
		elif town.owner == nation_id:
			town.owner = PLAYER
			town.garrison = 0
			town.max_garrison = 0
			town.captured_turn = state.turn
			gained.append(town.id)
	return gained


# --- What towns give ----------------------------------------------------------------------

func town_yield(town: Town) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	if not town.is_captured():
		return result
	var factor := float(CAPITAL_YIELD if town.is_capital() else 1)
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
	return MILITIA_BASE if town.is_captured() else HOME_MILITIA


## The share of a squad's full size an army standing in `town_id` regains a turn, from the
## kingdom's own share `home_share` (0 on an enemy town).
func replenish_share(town_id: int, home_share: float) -> float:
	var town := towns[town_id]
	if town.owner != PLAYER or home_share <= 0.0:
		return 0.0
	if town.is_capital():
		return minf(home_share, CAPITAL_REPLENISH_CAP)
	return minf(home_share * TOWN_REPLENISH_SHARE, TOWN_REPLENISH_CAP)


## Soldiers a squad of `full` soldiers regains a turn at `share` (rounded up, 0 at no share).
static func replenish_gain(full: int, share: float) -> int:
	return ceili(full * share) if share > 0.0 else 0


## The chance a turn that a captured town revolts (0 for our own towns and new conquests).
func revolt_chance(town: Town, turn: int) -> float:
	if not town.is_captured() or turn - town.captured_turn < REVOLT_GRACE:
		return 0.0
	if nations[town.nation].destroyed:
		return pacified_chance(nations[town.nation], turn)
	return REVOLT_GUARDED if not forces_at(town.id).is_empty() else REVOLT_CHANCE


func rebels_for(town: Town, scale: float) -> int:
	return maxi(REBEL_MIN, roundi(garrison_for(town.id, scale) * REBEL_SHARE))


# --- Vassals (GDD §36, M18f-b2a) ------------------------------------------------------------

## The chance a turn that a town of the destroyed `nation` revolts: REVOLT_PACIFIED without a
## vassal, falling PACIFY_STEP a turn after the crowning, minus the king's command.
func pacified_chance(nation: Nation, turn: int) -> float:
	if nation.vassal == null:
		return REVOLT_PACIFIED
	var steps := clampi(turn - nation.vassal_turn - 1, 0, PACIFY_TURNS)
	return maxf(0.0, REVOLT_PACIFIED - PACIFY_STEP * steps - VASSAL_COMMAND_CUT * nation.vassal.command)


## The vassal ruling the land `town` belongs to, while the town is ours; else null.
func vassal_of(town: Town) -> Nation:
	if town.owner != PLAYER or town.nation == PLAYER or not nations.has(town.nation):
		return null
	var nation := nations[town.nation]
	return nation if nation.vassal != null else null


func vassals() -> Array[Nation]:
	var result: Array[Nation] = []
	for nation: Nation in nations.values():
		if nation.vassal != null:
			result.append(nation)
	return result


## The vassal's soldiers guarding `town` (0 outside a vassal's land).
func vassal_guard(town: Town) -> int:
	var vassal := vassal_of(town)
	return 0 if vassal == null else guard_for(vassal.vassal)


static func guard_for(king: General) -> int:
	return VASSAL_GUARD_BASE + VASSAL_GUARD_PER_MIGHT * king.might


## An army of a vassal of ours (not an enemy).
func is_ally(army: NationArmy) -> bool:
	return nations.has(army.nation) and nations[army.nation].vassal != null


## The towns of `region` we hold.
func region_towns(region: int) -> Array[Town]:
	var result: Array[Town] = []
	for slot in RealmMap.TOWNS_PER_REGION:
		var town := towns[region * RealmMap.TOWNS_PER_REGION + slot]
		if town.owner == PLAYER:
			result.append(town)
	return result


## Tribute a vassal king pays a turn (by stars).
static func tribute_of(king: General) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	for resource_id in TRIBUTE_BASIC:
		result[resource_id] = TRIBUTE_BASIC_PER_STAR * king.stars
	if king.stars >= TRIBUTE_RARE_FROM:
		for resource_id in TRIBUTE_RARE:
			result[resource_id] = TRIBUTE_RARE_PER_STAR * (king.stars - TRIBUTE_RARE_FROM + 1)
	return result


## Every vassal's tribute together (part of the kingdom's income).
func tribute() -> Dictionary[StringName, int]:
	var total: Dictionary[StringName, int] = {}
	for nation in vassals():
		Economy.add_into(total, tribute_of(nation.vassal))
	return total


## Whether `general` may be crowned king of the destroyed `nation_id`'s land.
func check_crown(state: KingdomState, nation_id: StringName, general: General) -> Result:
	if not active:
		return Result.NOT_ACTIVE
	if not nations.has(nation_id) or nation_id == REBELS:
		return Result.NOT_CONQUERED
	var nation := nations[nation_id]
	if nation.vassal != null:
		return Result.ALREADY_VASSAL
	if not nation.destroyed or towns[nation.capital()].owner != PLAYER:
		return Result.NOT_CONQUERED
	if general == null or not state.generals.generals.has(general):
		return Result.NO_GENERAL
	if general == state.generals.commander:
		return Result.IS_COMMANDER
	if not general.is_ready():
		return Result.GENERAL_BUSY
	return Result.OK


## Crowns `general` king of the land: they leave our generals for good (their items come back to
## the storage), the pacifying starts and the vassal raises its first army.
func crown(state: KingdomState, nation_id: StringName, general: General) -> Result:
	var result := check_crown(state, nation_id, general)
	if result != Result.OK:
		return result
	var nation := nations[nation_id]
	state.equipment.take_back(general)
	state.generals.dismiss(general)
	nation.vassal = general
	nation.vassal_turn = state.turn
	treasury[nation_id] = 0.0
	RealmVassals.raise_army(self, state, nation)
	return Result.OK


## Vassals whose whole land is lost fall: the king is gone, their armies break up. Returns the
## fallen nations' names.
func check_vassals() -> Array[String]:
	var fallen: Array[String] = []
	for nation in vassals():
		if region_towns(nation.region).is_empty():
			nation.vassal = null
			treasury.erase(nation.id)
			for army in armies_of(nation.id):
				remove_army(army)
			fallen.append(nation.name)
	return fallen


## The vassal's share of a battle for `town`: its armies there lose their share of the defenders'
## losses (all of them when the town falls); the guard comes back every turn.
func _vassal_losses(town: Town, record: BattleRecord, won: bool) -> void:
	var here := armies_at(town.id).filter(func(army: NationArmy) -> bool: return is_ally(army))
	if here.is_empty():
		return
	if not won:
		for army: NationArmy in here:
			remove_army(army)
		return
	var lost := BattleOutcome.soldiers_lost(record, BattleRecord.DEFENDER)
	var ours := 0
	for army: NationArmy in here:
		ours += army.soldiers
	var total := ours + vassal_guard(town) + militia_soldiers(town)
	for force in forces_at(town.id):
		total += force.soldiers()
	RealmWar.spread_losses(self, here, roundi(float(lost) * ours / maxf(1.0, total)))


# --- Turns --------------------------------------------------------------------------------

## End of a turn: garrisons regrow, armies on kingdom towns regain soldiers, marches are carried
## out, the nations act (RealmWar.run_turn) and captured towns may revolt. Returns {"replenished":
## soldiers regained, "marched": [{general, from, to}], "news": [String] fights between nations,
## "threats": [{army, town}] attacks on our towns announced for next turn, "attacks": the pending
## attacks, "revolted": [{town, to}] towns lost to a revolt with no army there, "revolt": the
## pending revolt ({} without one)}.
func end_turn(state: KingdomState) -> Dictionary:
	pending_revolt = {}
	pending_attacks.clear()
	if not active:
		return {"replenished": 0, "marched": [], "news": [], "threats": [], "attacks": [], "revolted": [],
				"revolt": {}}
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
	var home_share := state.replenish_fraction()
	for force in forces:
		var share := replenish_share(force.town, home_share)
		for squad in force.squads:
			var full: int = state.units[squad.unit_id].squad_size
			var gain := mini(replenish_gain(full, share), full - squad.soldiers)
			if gain > 0:
				state.army.add_soldiers(squad, gain)
				regained += gain
	var marched: Array[Dictionary] = []
	for force in forces:
		var from := force.town
		match force.order:
			MOVE:
				if check_move(force, force.target) == Result.OK:
					force.town = force.target
				_set_order(force, &"", -1, 0)
			HOME:
				var step := next_town(force)
				if step < 0:
					_set_order(force, &"", -1, 0)
				else:
					force.town = step
					if step == HOME_CAPITAL:
						_set_order(force, &"", -1, 0)
		if force.town != from:
			marched.append({"general": force.general.name if force.general != null else "", "from": from,
					"to": force.town})
	var news: Array[String] = []
	news.append_array(RealmVassals.run_turn(self, state))
	var war := {"news": [], "threats": []}
	if ai_enabled:
		war = RealmWar.run_turn(self, state)
	news.append_array(war.news)
	var attacked := {}
	for entry in pending_attacks:
		attacked[entry.town] = true
	var revolted: Array[Dictionary] = []
	for town in captured_towns():
		if attacked.has(town.id):
			continue
		var chance := revolt_chance(town, state.turn + 1)
		if chance <= 0.0 or rng.randf() >= chance:
			continue
		var rebels := rebels_for(town, state.wars.enemy_scale)
		if forces_at(town.id).is_empty():
			_lose_town(state, town, rebels, true)
			revolted.append({"town": town.id, "to": town.owner})
		elif pending_revolt.is_empty():
			pending_revolt = {"town": town.id, "rebels": rebels}
	for name in check_vassals():
		news.append("Chư hầu %s sụp đổ: vùng đất đã mất hết." % name)
	return {"replenished": regained, "marched": marched, "news": news, "threats": war.threats,
			"attacks": pending_attacks.duplicate(true), "revolted": revolted, "revolt": pending_revolt}


# --- Enemy attacks on our towns and interceptions (M18f-b1) -----------------------------------

## The armies of the first pending attack still on the map.
func attack_armies(entry: Dictionary) -> Array[NationArmy]:
	var result: Array[NationArmy] = []
	for id in entry.armies:
		var army := army_by_id(int(id))
		if army != null:
			result.append(army)
	return result


## The first pending attack's battle: the nation's armies against the town's armies and militia
## behind its walls. Null (and the attack dropped) when none of its armies is left.
func create_enemy_attack(state: KingdomState) -> BattleSimulator:
	while not pending_attacks.is_empty():
		var entry: Dictionary = pending_attacks[0]
		var group := attack_armies(entry)
		var town := towns[entry.town]
		if group.is_empty() or town.owner != PLAYER:
			for army in group:
				army.target = -1
			pending_attacks.pop_front()
			continue
		var attackers := RealmWar.army_side(self, state, group, "Quân %s" % nations[group[0].nation].name)
		return BattleSimulator.new(attackers, town_defenders(state, town), rng.randi())
	return null


## Applies the first pending attack's battle. Lost: the town goes to the attacking nation, its
## armies move in and ours fall back. Returns apply_to_army's report plus {"record", "won",
## "town", "nation" (the attacker's id), "enemy_lost", "general", "lost_town", "retreated_to"}.
func finish_enemy_attack(state: KingdomState, record: BattleRecord) -> Dictionary:
	var entry: Dictionary = pending_attacks.pop_front()
	var group := attack_armies(entry)
	var town := towns[entry.town]
	var nation: StringName = group[0].nation if not group.is_empty() else town.nation
	var enemy_lost := BattleOutcome.soldiers_lost(record, BattleRecord.ATTACKER)
	var result := _finish_town_battle(state, town, record, enemy_lost, false, nation)
	for army in group:
		army.target = -1
	RealmWar.spread_losses(self, group, enemy_lost)
	if not result.won:
		town.garrison = 0
		for army in group:
			if armies.has(army):
				army.town = town.id
	result["nation"] = nation
	return result


## Intercepting `army` (an enemy army that announced an attack) from a neighboring town.
func check_intercept(force: Force, army: NationArmy) -> Result:
	if army != null and is_ally(army):
		return Result.NO_ENEMY_ARMY
	if army == null or not armies.has(army):
		return Result.NO_ENEMY_ARMY
	var basic := _check_step(force, army.town)
	if basic != Result.OK:
		return basic
	if not army.has_target():
		return Result.NOT_MARCHING
	if force.general == null or force.general.wounded_turns > 0:
		return Result.GENERAL_WOUNDED
	return Result.OK


func order_intercept(force: Force, army: NationArmy, turn: int) -> Result:
	var result := check_intercept(force, army)
	if result == Result.OK:
		_set_order(force, INTERCEPT, army.town, turn)
		force.army = army.id
	return result


## Interceptions due at the start of `turn`, grouped by the enemy army: [[Force, …], …].
func due_intercept_groups(turn: int) -> Array[Array]:
	var groups: Array[Array] = []
	var by_army := {}
	for force in forces:
		if force.order != INTERCEPT or force.order_turn >= turn:
			continue
		if not by_army.has(force.army):
			by_army[force.army] = groups.size()
			groups.append([])
		groups[by_army[force.army]].append(force)
	return groups


## The interception battle in the open: our armies of `group` against that one army (no walls,
## no garrison). Null when it can no longer happen (the army is gone or has moved).
func create_intercept(state: KingdomState, group: Array, army_id: int) -> BattleSimulator:
	var army := army_by_id(army_id)
	if army == null or group.is_empty():
		return null
	for force: Force in group:
		if check_intercept(force, army) != Result.OK:
			return null
	var defenders := RealmWar.army_side(self, state, [army], "Đạo quân %s (%s)" % [army.general.name,
			nations[army.nation].name])
	return BattleSimulator.new(group_side(state, group), defenders, rng.randi())


## Applies an interception. Won: the enemy army breaks up and its attack is off. Our armies stay
## where they were. Returns apply_to_army's report plus {"record", "won", "enemy_lost", "general",
## "disbanded", "armies", "nation"}.
func finish_intercept(state: KingdomState, group: Array, army_id: int, record: BattleRecord) -> Dictionary:
	var army := army_by_id(army_id)
	var won := record.winner == BattleRecord.ATTACKER
	state.count_stat("battles_won" if won else "battles_lost")
	var result := BattleOutcome.apply_to_army(state.army, record, BattleRecord.ATTACKER, false,
			state.building_effect(&"retreat_keep"))
	var general := _general_after(state, leader_of(group), record, BattleRecord.ATTACKER)
	var enemy_lost := BattleOutcome.soldiers_lost(record, BattleRecord.DEFENDER)
	var nation: StringName = army.nation if army != null else &""
	if army != null:
		if won:
			remove_army(army)
		else:
			RealmWar.spread_losses(self, [army], enemy_lost)
	var disbanded := 0
	for force: Force in group:
		_drop_lost_squads(state, force)
		_set_order(force, &"", -1, 0)
		if force.squads.is_empty() or force.general == null:
			disband(state, force, true)
			disbanded += 1
	result.merge({"record": record, "won": won, "enemy_lost": enemy_lost, "general": general,
			"disbanded": disbanded, "armies": group.size(), "nation": nation,
			"item": state.equipment.roll_loot(true, state.stockpile) if won else {}})
	return result


## A town of ours under attack: every army in it, its militia, behind its walls.
func town_defenders(state: KingdomState, town: Town) -> BattleSide:
	var here := forces_at(town.id)
	var defenders: BattleSide
	if not here.is_empty():
		defenders = group_side(state, here)
	else:
		defenders = BattleSide.new("Dân binh %s" % town.name)
		defenders.color = state.player_color
	var militia := {}
	for unit_id in MILITIA_UNITS:
		militia[unit_id] = MILITIA_UNITS[unit_id] / MILITIA_UNITS.size()
	_add_weighted(defenders, militia, militia_soldiers(town), state)
	var vassal := vassal_of(town)
	if vassal != null:
		var soldiers := vassal_guard(town)
		for army in armies_at(town.id):
			soldiers += army.soldiers
		add_nation_units(defenders, vassal, soldiers, state)
	man_walls(defenders, town)
	return defenders


## The pending revolt's battle: the rebels attack, the town's armies and militia defend.
func create_revolt(state: KingdomState) -> BattleSimulator:
	if pending_revolt.is_empty():
		return null
	var town := towns[pending_revolt.town]
	var attackers := BattleSide.new("%s ở %s" % [REBEL_NAME, town.name])
	attackers.color = REBEL_COLOR
	_add_rebels(attackers, pending_revolt.rebels, state)
	return BattleSimulator.new(attackers, town_defenders(state, town), rng.randi())


## Applies the revolt's battle: a lost town goes to its nation or the rebels (_finish_town_battle).
func finish_revolt(state: KingdomState, record: BattleRecord) -> Dictionary:
	var town := towns[pending_revolt.town]
	var rebels: int = pending_revolt.rebels
	pending_revolt = {}
	return _finish_town_battle(state, town, record, rebels, true)


## A battle for a town of ours: losses, the general, a lost town (to `to`, else its nation or the
## rebels) and our armies there. Returns apply_to_army's report plus {"record", "won", "town",
## "nation", "enemy_lost", "general", "lost_town", "retreated_to", "owner"}.
func _finish_town_battle(state: KingdomState, town: Town, record: BattleRecord, attackers: int,
		revolt: bool, to: StringName = &"") -> Dictionary:
	var won := record.winner == BattleRecord.DEFENDER
	state.count_stat("battles_won" if won else "battles_lost")
	var here := forces_at(town.id)
	var result := BattleOutcome.apply_to_army(state.army, record, BattleRecord.DEFENDER, false,
			state.building_effect(&"retreat_keep"))
	var general := _general_after(state, leader_of(here) if not here.is_empty() else null, record,
			BattleRecord.DEFENDER)
	var enemy_lost := BattleOutcome.soldiers_lost(record, BattleRecord.ATTACKER)
	var retreated_to := -1
	_vassal_losses(town, record, won)
	if not won:
		retreated_to = _lose_town(state, town, maxi(1, attackers - enemy_lost), revolt, to)
	for force in here:
		_drop_lost_squads(state, force)
		if force.squads.is_empty() or force.general == null:
			disband(state, force, true)
	result.merge({"record": record, "won": won, "town": town.id, "nation": town.nation, "enemy_lost": enemy_lost,
			"general": general, "lost_town": not won, "retreated_to": retreated_to, "owner": town.owner,
			"vassals_fallen": check_vassals()})
	return result


## The town is no longer ours: it goes back to its nation (or, after a revolt in a destroyed
## nation's land, to the rebels) holding `holders` soldiers; armies there fall back to a
## neighboring town of ours (or the capital) and drop their orders. Returns where they went.
func _lose_town(state: KingdomState, town: Town, holders: int, revolt: bool, to: StringName = &"") -> int:
	if to != &"":
		town.owner = to
		town.max_garrison = garrison_for(town.id, state.wars.enemy_scale)
	elif revolt and nations[town.nation].destroyed:
		_rebels()
		town.owner = REBELS
		town.max_garrison = rebels_for(town, state.wars.enemy_scale)
	else:
		town.owner = town.nation
		town.max_garrison = garrison_for(town.id, state.wars.enemy_scale)
	town.garrison = mini(town.max_garrison, holders)
	var retreated_to := _fallback(town.id)
	for force in forces_at(town.id):
		force.town = retreated_to
		_set_order(force, &"", -1, 0)
	return retreated_to


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
		Result.ALREADY_HOME:
			return "Đạo quân đang ở kinh đô."
		Result.NO_ROUTE:
			return "Không có đường về qua các trấn của ta."
		Result.NO_ORDER:
			return "Đạo quân chưa có lệnh nào."
		Result.NOT_NEIGHBOR:
			return "Chỉ đi được tới trấn kề bên theo đường."
		Result.ENEMY_TOWN:
			return "Trấn của địch: phải công thành."
		Result.OWN_TOWN:
			return "Trấn này đã là của ta."
		Result.GENERAL_WOUNDED:
			return "Tướng đang bị thương, chưa công thành được."
		Result.NO_ENEMY_ARMY:
			return "Đạo quân địch này không còn."
		Result.NOT_MARCHING:
			return "Chỉ đánh chặn được đạo quân địch đang chuẩn bị tấn công."
		Result.NOT_CONQUERED:
			return "Chỉ phong vương ở nước đã bị diệt khi kinh đô cũ đang trong tay ta."
		Result.ALREADY_VASSAL:
			return "Vùng này đã có chư hầu."
		Result.IS_COMMANDER:
			return "Không phong vương Tổng tướng được: đổi Tổng tướng trước."
	return ""


# --- Save (GDD §10.1) ---------------------------------------------------------------------

func to_save(state: KingdomState) -> Dictionary:
	if not active:
		return {}
	var town_saves: Array = []
	for town in towns:
		town_saves.append({"name": town.name, "nation": String(town.nation), "owner": String(town.owner),
				"garrison": town.garrison, "max": town.max_garrison, "captured_turn": town.captured_turn})
	var nation_saves := {}
	for nation in nations.values():
		var entry := {"region": nation.region, "destroyed": nation.destroyed}
		if nation.vassal != null:
			entry["vassal"] = nation.vassal.to_save()
			entry["vassal_turn"] = nation.vassal_turn
		nation_saves[String(nation.id)] = entry
	var force_saves: Array = []
	for force in forces:
		force_saves.append({"general": state.generals.generals.find(force.general), "town": force.town,
				"order": String(force.order), "target": force.target, "order_turn": force.order_turn, "army": force.army,
				"squads": force.squads.map(func(squad: Army.Squad) -> int: return state.army.squads.find(squad))})
	var treasury_saves := {}
	for nation_id in treasury:
		treasury_saves[String(nation_id)] = treasury[nation_id]
	return {"v": SAVE_VERSION, "towns": town_saves, "nations": nation_saves, "forces": force_saves,
			"revolt": pending_revolt, "armies": armies.map(func(army: NationArmy) -> Dictionary: return army.to_save()),
			"treasury": treasury_saves, "next_army": next_army_id, "attacks": pending_attacks}


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
	pending_revolt = {}
	armies.clear()
	treasury.clear()
	pending_attacks.clear()
	next_army_id = 1
	if not active:
		return
	var revolt: Dictionary = data.get("revolt", {})
	if not revolt.is_empty():
		pending_revolt = {"town": int(revolt.town), "rebels": int(revolt.rebels)}
	for nation_id: String in data.nations:
		var entry: Dictionary = data.nations[nation_id]
		var nation := Nation.new()
		nation.id = StringName(nation_id)
		nation.name = RealmMap.nation_data(nation.id).get("name", REBEL_NAME)
		nation.region = int(entry.region)
		nation.destroyed = bool(entry.destroyed)
		var vassal_data: Dictionary = entry.get("vassal", {})
		if not vassal_data.is_empty():
			nation.vassal = General.from_save(vassal_data)
			nation.vassal_turn = int(entry.get("vassal_turn", 0))
		nation.color = REBEL_COLOR if nation.id == REBELS else RealmMap.nation_color(nation.id, state.player_color)
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
		# Governors were removed in M18g: one saved before comes home.
		var governor := _officer_from(state, entry.get("governor", {}))
		if governor != null:
			_set_away(governor, false)
		towns.append(town)
	for entry: Dictionary in data.forces:
		var index := int(entry.general)
		if index < 0 or index >= state.generals.generals.size():
			continue
		var force := Force.new()
		force.general = state.generals.generals[index]
		force.town = int(entry.town)
		force.order = StringName(entry.get("order", ""))
		force.target = int(entry.get("target", -1))
		force.order_turn = int(entry.get("order_turn", 0))
		force.army = int(entry.get("army", -1))
		for squad_index in entry.squads:
			if int(squad_index) >= 0 and int(squad_index) < state.army.squads.size():
				force.squads.append(state.army.squads[int(squad_index)])
		_set_away(force.general, true, "dẫn đạo quân")
		for squad in force.squads:
			_set_away(squad, true, "theo đạo quân %s" % force.general.name)
		forces.append(force)
	for entry: Dictionary in data.get("armies", []):
		armies.append(NationArmy.from_save(entry))
	var saved_treasury: Dictionary = data.get("treasury", {})
	for nation_id: String in saved_treasury:
		treasury[StringName(nation_id)] = float(saved_treasury[nation_id])
	next_army_id = int(data.get("next_army", 1))
	for entry: Dictionary in data.get("attacks", []):
		pending_attacks.append({"town": int(entry.town), "armies": entry.armies.map(func(id) -> int: return int(id))})
	if int(data.get("v", 1)) < 2:
		# Before M18f-b1: garrisons were twice as big and the nations had no armies.
		for town in towns:
			if town.owner != PLAYER:
				town.max_garrison = roundi(town.max_garrison * 0.5)
				town.garrison = mini(town.garrison, town.max_garrison)
		for nation in RealmWar.live_nations(self):
			RealmWar.raise_army(self, state, nation)
