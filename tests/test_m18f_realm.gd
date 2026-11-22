extends "res://tests/test_suite.gd"
## M18f-a: the realm phase (Phân Chia Thiên Hạ, GDD §33).

var terrains := TerrainLibrary.load_all()


func _state(seed_value: int = 3) -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), seed_value)
	state.start()
	return state


func _run(simulator: BattleSimulator) -> BattleRecord:
	while not simulator.finished:
		simulator.step()
	return simulator.record


## A united land: every clan annexed but one, allied; the victory won; the realm started.
func _realm_state(seed_value: int = 3) -> KingdomState:
	var state := _state(seed_value)
	var ids: Array = state.diplomacy.clans.keys()
	for clan_id in ids.slice(0, ids.size() - 1):
		state.wars.fronts[clan_id].annexed = true
		state.diplomacy.clans[clan_id].annexed = true
	state.diplomacy.clans[ids.back()].alliance_turns = 99
	state.victory.check(state)
	state.start_realm()
	return state


func _general(state: KingdomState, stars: int = 3) -> General:
	var general := state.generals.generate(stars)
	state.generals.add(general)
	return general


func _squads(state: KingdomState, unit_id: StringName, count: int, xp: float = 0.0) -> Array[Army.Squad]:
	var result: Array[Army.Squad] = []
	for i in count:
		state.army.add_squad(unit_id, state.units[unit_id].squad_size)
		state.army.squads.back().xp = xp
		result.append(state.army.squads.back())
	return result




func test_the_map_is_fixed_and_connected() -> void:
	check_eq(RealmMap.TOWN_COUNT, 30, "Us and five nations, five towns each")
	var seen := {Realm.HOME_CAPITAL: true}
	var queue: Array[int] = [Realm.HOME_CAPITAL]
	while not queue.is_empty():
		for other in RealmMap.neighbors(queue.pop_front()):
			if not seen.has(other):
				seen[other] = true
				queue.append(other)
	check_eq(seen.size(), 30, "Every town is reachable by road")
	for town in RealmMap.TOWN_COUNT:
		for other in RealmMap.neighbors(town):
			check(RealmMap.neighbors(other).has(town), "Roads go both ways")
		if RealmMap.is_capital(town):
			for other in RealmMap.neighbors(town):
				check_eq(RealmMap.region_of(other), RealmMap.region_of(town), "A capital is reached through its own towns")
	check_eq(RealmMap.region_distance(0), 0, "The kingdom")
	check_eq([RealmMap.region_distance(1), RealmMap.region_distance(3)], [1, 1], "Two near nations")
	check_eq(RealmMap.region_distance(5), 3, "The far corner")
	check_eq(RealmMap.NATIONS.size(), 5, "Five nations")


func test_starting_the_realm() -> void:
	var state := _state()
	check(not state.can_start_realm(), "Not before the land is united")
	var ids: Array = state.diplomacy.clans.keys()
	for clan_id in ids.slice(0, ids.size() - 2):
		state.wars.fronts[clan_id].annexed = true
		state.diplomacy.clans[clan_id].annexed = true
	for clan_id in ids.slice(ids.size() - 2):
		state.diplomacy.clans[clan_id].alliance_turns = 99
	check(state.victory.check(state) != Victory.NO_PATH, "United")
	check(state.can_start_realm(), "Now it can start")
	var joined := state.start_realm()
	check_eq(joined.size(), 2, "Both allies asked to join")
	check(state.diplomacy.clans.values().all(func(clan) -> bool: return clan.annexed), "Every clan annexed")
	check(state.realm.active and not state.can_start_realm(), "Started once")
	check_eq(state.generals.max_generals, 9, "Nine generals now")
	check_eq(state.realm.towns.size(), 30, "30 towns")
	check_eq(state.realm.count_owned(Realm.PLAYER), 5, "Our five towns")
	check_eq(state.realm.towns[Realm.HOME_CAPITAL].name, state.kingdom_name, "The capital is the kingdom")
	check_eq(state.realm.captured_towns().size(), 0, "Nothing captured yet")
	for nation in state.realm.nations.values():
		check_eq(state.realm.count_owned(nation.id), 5, "%s has five towns" % nation.name)
		var capital := state.realm.towns[nation.capital()]
		var ring := state.realm.towns[RealmMap.town_id(nation.region, RealmMap.Slot.NORTH)]
		check_eq(capital.garrison, ring.garrison * 2, "The capital holds twice the soldiers")
	var near := state.realm.nation_in(1)
	var far := state.realm.nation_in(5)
	check(state.realm.towns[far.capital()].garrison > state.realm.towns[near.capital()].garrison, "Far nations are stronger")
	var orders := {}
	for seed_value in range(1, 8):
		var other := _realm_state(seed_value)
		orders[str(other.realm.nation_in(1).id, other.realm.nation_in(5).id)] = true
	check(orders.size() > 2, "The nations change places between games")


func test_nation_colors_avoid_the_players() -> void:
	var red := Color(0.7, 0.16, 0.14)
	check(RealmMap.nation_color(&"xich_viem", red) != red, "Xích Viêm switches color")
	check_eq(RealmMap.nation_color(&"bac_mac", red), RealmMap.nation_data(&"bac_mac").color, "Others keep theirs")


func test_forming_an_army() -> void:
	var state := _realm_state()
	var general := _general(state)
	var squads := _squads(state, &"swordsman", 3)
	check_eq(state.realm.form(state, null, squads), Realm.Result.NO_GENERAL, "Needs a general")
	var empty: Array[Army.Squad] = []
	check_eq(state.realm.form(state, general, empty), Realm.Result.NO_SQUADS, "Needs squads")
	var many := _squads(state, &"spearman", 21)
	check_eq(state.realm.form(state, general, many), Realm.Result.TOO_MANY_SQUADS, "At most 20")
	check_eq(state.realm.forces.size(), 0, "Nothing formed")
	check_eq(state.realm.form(state, general, squads), Realm.Result.OK, "Formed")
	var force: Realm.Force = state.realm.forces[0]
	check_eq(force.town, Realm.HOME_CAPITAL, "At the capital")
	check(general.away and general.duty != "", "The general leads it")
	check(squads.all(func(squad: Army.Squad) -> bool: return squad.away), "Its squads left home")
	check_eq(RaidSystem.create_kingdom_side(state).units.size(), state.army.squads.size() - 3, "Home battles go without them")
	check_eq(state.realm.form(state, general, many.slice(0, 2)), Realm.Result.GENERAL_BUSY, "One army per general")
	check_eq(state.realm.form(state, _general(state), squads), Realm.Result.SQUAD_BUSY, "Squads in one army only")
	check_eq(state.realm.regroup(state, force, many.slice(0, 5)), Realm.Result.OK, "Regrouped at the capital")
	check(not squads[0].away and many[0].away, "Old squads came home, new ones left")
	check_eq(state.realm.disband(state, force), Realm.Result.OK, "Disbanded")
	check(not general.away and not many[0].away and state.realm.forces.is_empty(), "Everyone is home")


func test_marching_and_sieges() -> void:
	var state := _realm_state()
	var general := _general(state, 5)
	var force_squads := _squads(state, &"royal_swordguard", 20, 400.0)
	state.realm.form(state, general, force_squads)
	var force: Realm.Force = state.realm.forces[0]
	var east := RealmMap.town_id(0, RealmMap.Slot.EAST)
	check_eq(state.realm.move(force, RealmMap.town_id(2, RealmMap.Slot.NORTH)), Realm.Result.NOT_NEIGHBOR, "Only along roads")
	check_eq(state.realm.move(force, east), Realm.Result.OK, "Marched east")
	check_eq(state.realm.move(force, Realm.HOME_CAPITAL), Realm.Result.ALREADY_MOVED, "One road a turn")
	force.moved = false
	var target := -1
	for id in RealmMap.neighbors(east):
		if state.realm.towns[id].owner != Realm.PLAYER:
			target = id
	check(target >= 0, "An enemy town next door")
	check_eq(state.realm.check_move(force, target), Realm.Result.ENEMY_TOWN, "Enemy towns are besieged")
	general.wounded_turns = 2
	check_eq(state.realm.check_siege(force, target), Realm.Result.GENERAL_WOUNDED, "Not with a wounded general")
	general.wounded_turns = 0
	var town := state.realm.towns[target]
	var nation := town.owner
	town.garrison = 30
	var food := state.stockpile.get_amount(&"food")
	var simulator := state.start_siege(force, target)
	check(simulator != null, "The siege starts")
	var walls := simulator.record.sides[BattleRecord.DEFENDER].units[0]
	check(walls.defense_mult > 1.0, "Defenders behind walls")
	var result := state.finish_siege(force, target, _run(simulator))
	check(result.won, "Thirty soldiers fall to twenty royal squads")
	check_eq(town.owner, Realm.PLAYER, "The town is ours")
	check_eq(force.town, target, "The army stands in it")
	check(force.moved, "And waits for the next turn")
	check_eq(state.stockpile.get_amount(&"food"), food + Realm.CAPTURE_LOOT[&"food"], "Loot taken")
	check_eq(state.realm.captured_towns().size(), 1, "One town captured")
	check_eq(result.destroyed, &"", "The nation stands")
	check(state.realm.nations[nation].destroyed == false, "Not destroyed")
	check_eq(state.realm.squad_bonus(), Realm.TOWN_SQUADS * 6, "Five home towns and the new one")


func test_a_lost_siege() -> void:
	var state := _realm_state()
	var general := _general(state)
	state.realm.form(state, general, _squads(state, &"swordsman", 1))
	var force: Realm.Force = state.realm.forces[0]
	var east := RealmMap.town_id(0, RealmMap.Slot.EAST)
	force.town = east
	var target := RealmMap.town_id(1, RealmMap.Slot.WEST)
	var town := state.realm.towns[target]
	town.garrison = 2000
	var result := state.finish_siege(force, target, _run(state.start_siege(force, target)))
	check(not result.won, "One peasant squad cannot take the town")
	check(town.owner != Realm.PLAYER, "The town holds")
	check(town.garrison <= 2000, "Its losses count")
	if result.disbanded:
		check(state.realm.forces.is_empty(), "A broken army is gone")
		check(general.away == false, "Its general came home (or fell)")
	else:
		check_eq(force.town, east, "Still where it stood")


func test_taking_a_capital_destroys_the_nation() -> void:
	var state := _realm_state()
	var general := _general(state, 5)
	state.realm.form(state, general, _squads(state, &"royal_swordguard", 20, 400.0))
	var force: Realm.Force = state.realm.forces[0]
	var nation := state.realm.nation_in(1)
	var capital := nation.capital()
	force.town = RealmMap.town_id(nation.region, RealmMap.Slot.WEST)
	state.realm.towns[force.town].owner = Realm.PLAYER
	state.realm.towns[capital].garrison = 20
	var result := state.finish_siege(force, capital, _run(state.start_siege(force, capital)))
	check(result.won, "Taken")
	check_eq(result.destroyed, nation.id, "The nation fell")
	check(nation.destroyed, "Marked destroyed")
	check_eq(state.realm.count_owned(nation.id), 0, "Its towns are ours")
	check_eq(result.gained.size(), 3, "Three more towns handed over")
	check(state.realm.counter_targets(state.turn + 10).filter(func(town: Realm.Town) -> bool:
			return town.nation == nation.id).is_empty(), "A destroyed nation cannot strike back")


func test_governors_and_what_towns_give() -> void:
	var state := _realm_state()
	var town := state.realm.towns[RealmMap.town_id(1, RealmMap.Slot.NORTH)]
	var general := _general(state, 4)
	check_eq(state.realm.assign_governor(state, general, town.id), Realm.Result.NOT_CAPTURED, "Only captured towns")
	state.realm.capture(state, town)
	var plain := state.realm.town_yield(town)
	check_eq(plain[&"food"], roundi(Realm.TOWN_YIELD[&"food"] * Realm.UNGOVERNED_SHARE), "Half without a governor")
	var before: int = state.get_turn_yield().get(&"food", 0)
	var capacity := state.get_squad_capacity()
	check_eq(state.realm.assign_governor(state, general, town.id), Realm.Result.OK, "Governor appointed")
	check(general.away and general.away_text().begins_with("trấn thủ"), "The governor stays there")
	var governed := state.realm.town_yield(town)
	check(governed[&"food"] > Realm.TOWN_YIELD[&"food"], "A governor raises it (%d)" % governed[&"food"])
	check_eq(state.get_turn_yield().get(&"food", 0), before - plain[&"food"] + governed[&"food"], "In the kingdom's yield")
	check(state.get_income_breakdown()[&"food"].any(func(entry: Dictionary) -> bool: return entry.source == &"towns"),
			"Its own income line")
	check_eq(state.get_squad_capacity(), capacity, "Capacity does not depend on the governor")
	check(state.realm.militia_soldiers(town) > Realm.MILITIA_BASE, "Võ lực adds militia")
	var advisor := state.advisors.generate(3)
	state.advisors.add(advisor)
	check_eq(state.realm.assign_governor(state, advisor, town.id), Realm.Result.HAS_GOVERNOR, "One per town")
	state.realm.remove_governor(state, town.id)
	check(not general.away, "Back home")
	check_eq(state.realm.assign_governor(state, advisor, town.id), Realm.Result.OK, "Advisors govern too")


func test_armies_replenish_on_kingdom_towns() -> void:
	var state := _realm_state()
	var squads := _squads(state, &"swordsman", 2)
	state.realm.form(state, _general(state), squads)
	var force: Realm.Force = state.realm.forces[0]
	squads[0].soldiers = 5
	squads[1].soldiers = 5
	force.moved = true
	state.realm.end_turn(state)
	check_eq(squads[0].soldiers, 5, "Not after marching")
	check(not force.moved, "Orders reset")
	state.realm.end_turn(state)
	check_eq(squads[0].soldiers, 5 + ceili(20 * Realm.CAPITAL_REPLENISH), "Faster at the capital")
	force.town = RealmMap.town_id(0, RealmMap.Slot.EAST)
	state.realm.end_turn(state)
	check_eq(squads[1].soldiers, 9 + ceili(20 * Realm.ARMY_REPLENISH), "Slower in other towns")


func test_garrisons_regrow() -> void:
	var state := _realm_state()
	var town := state.realm.towns[RealmMap.town_id(1, RealmMap.Slot.NORTH)]
	town.garrison = 0
	state.realm.end_turn(state)
	check_eq(town.garrison, ceili(town.max_garrison * Realm.GARRISON_REGEN), "A tenth a turn")


func test_counterattacks() -> void:
	var state := _realm_state()
	var nation := state.realm.nation_in(1)
	var lost := state.realm.towns[RealmMap.town_id(nation.region, RealmMap.Slot.WEST)]
	state.realm.capture(state, lost)
	check(state.realm.counter_targets(state.turn).is_empty(), "Not right after it fell")
	check_eq(state.realm.counter_targets(state.turn + Realm.COUNTER_GRACE).size(), 1, "Later it can be struck")
	var governor := _general(state)
	state.realm.assign_governor(state, governor, lost.id)
	var found := false
	for i in 40:
		var report := state.end_turn()
		if report.has("pending_counter"):
			found = true
			check_eq(report.pending_counter.town, lost.id, "The lost town is attacked")
			var simulator: BattleSimulator = report.pending_counter.simulator
			var defenders := simulator.record.sides[BattleRecord.DEFENDER]
			check(defenders.display_name.begins_with("Dân binh"), "Its militia defends it")
			var result := state.finish_counter(_run(simulator))
			if result.won:
				check_eq(lost.owner, Realm.PLAYER, "Held")
			else:
				check_eq(lost.owner, nation.id, "Lost again")
				check(lost.governor == null and not governor.away, "The governor came home")
				check_eq(result.governor, governor.name, "Reported")
			break
	check(found, "A counterattack came within 40 turns")


func test_a_defending_army_and_its_retreat() -> void:
	var state := _realm_state()
	var nation := state.realm.nation_in(1)
	var lost := state.realm.towns[RealmMap.town_id(nation.region, RealmMap.Slot.WEST)]
	state.realm.capture(state, lost)
	state.realm.form(state, _general(state), _squads(state, &"swordsman", 1))
	var force: Realm.Force = state.realm.forces[0]
	force.town = lost.id
	var source := RealmMap.town_id(nation.region, RealmMap.CAPITAL)
	state.realm.pending_counter = {"town": lost.id, "source": source, "sent": 1500}
	var simulator := state.realm.create_counter(state)
	check(simulator.record.sides[BattleRecord.DEFENDER].general_name != "", "The army's general leads the defense")
	var result := state.finish_counter(_run(simulator))
	check(not result.won, "1500 soldiers take it back")
	check_eq(lost.owner, nation.id, "Lost")
	check(state.realm.towns[result.retreated_to].owner == Realm.PLAYER, "Fell back to one of our towns")
	if not state.realm.forces.is_empty():
		check_eq(force.town, result.retreated_to, "The army moved there")


func test_the_realm_is_saved() -> void:
	var state := _realm_state()
	var general := _general(state, 4)
	var squads := _squads(state, &"spearman", 3)
	state.realm.form(state, general, squads)
	state.realm.forces[0].town = RealmMap.town_id(0, RealmMap.Slot.SOUTH)
	var town := state.realm.towns[RealmMap.town_id(3, RealmMap.Slot.NORTH)]
	state.realm.capture(state, town)
	var advisor := state.advisors.generate(2)
	state.advisors.add(advisor)
	state.realm.assign_governor(state, advisor, town.id)
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.to_save()))
	var copy := _state(9)
	copy.load_save(data)
	check(copy.realm.active, "Still in the realm phase")
	check_eq(copy.generals.max_generals, 9, "Nine generals")
	for i in RealmMap.TOWN_COUNT:
		check_eq([copy.realm.towns[i].owner, copy.realm.towns[i].garrison, copy.realm.towns[i].name],
				[state.realm.towns[i].owner, state.realm.towns[i].garrison, state.realm.towns[i].name], "Town %d" % i)
	for nation in state.realm.nations.values():
		check_eq(copy.realm.nations[nation.id].region, nation.region, "%s in its place" % nation.name)
	check_eq(copy.realm.forces.size(), 1, "The army")
	var force: Realm.Force = copy.realm.forces[0]
	check_eq(force.general.name, general.name, "Its general")
	check_eq(force.squads.size(), 3, "Its squads")
	check_eq(force.town, RealmMap.town_id(0, RealmMap.Slot.SOUTH), "Where it stands")
	check(force.general.away and force.general.duty != "", "Away again with its duty")
	var governor := copy.realm.towns[town.id].governor
	check(governor != null and governor.name == advisor.name and governor.away, "The governor")
	var plain := _state(4)
	plain.load_save(JSON.parse_string(JSON.stringify(_state(4).to_save())))
	check(not plain.realm.active and plain.generals.max_generals == 3, "Older games are not in it")
