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
	# The nations stay still here; their armies are tested in test_m18f_b1_war.gd.
	state.realm.ai_enabled = false
	state.realm.armies.clear()
	return state


func _build_barracks(state: KingdomState) -> void:
	state.stockpile.add({&"food": 900, &"wood": 900, &"stone": 900})
	state.board.set_land(Vector2i(4, 4), &"grass", false)
	check_eq(state.build(&"barracks", Vector2i(4, 4)), BuildRules.Result.OK, "Barracks built")


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
	check_eq(state.realm.order(force, RealmMap.town_id(2, RealmMap.Slot.NORTH), 1), Realm.Result.NOT_NEIGHBOR, "Only along roads")
	check_eq(state.realm.order(force, east, 1), Realm.Result.OK, "Ordered east")
	check_eq([force.town, force.order, force.target], [Realm.HOME_CAPITAL, Realm.MOVE, east], "Waits for the end of the turn")
	check_eq(state.realm.cancel_order(force), Realm.Result.OK, "Cancelled")
	check(not force.has_order(), "No order left")
	check_eq(state.realm.cancel_order(force), Realm.Result.NO_ORDER, "Nothing to cancel")
	state.realm.order(force, east, 1)
	var report := state.realm.end_turn(state)
	check_eq(force.town, east, "Marched when the turn ended")
	check(not force.has_order(), "The order is spent")
	check_eq(report.marched.size(), 1, "Reported")
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
	var simulator := state.start_siege([force], target)
	check(simulator != null, "The siege starts")
	var walls := simulator.record.sides[BattleRecord.DEFENDER].units[0]
	check(walls.defense_mult > 1.0, "Defenders behind walls")
	var result := state.finish_siege([force], target, _run(simulator))
	check(result.won, "Thirty soldiers fall to twenty royal squads")
	check_eq(town.owner, Realm.PLAYER, "The town is ours")
	check_eq(force.town, target, "The army stands in it")
	check(not force.has_order(), "No order after the siege")
	check_eq(state.stockpile.get_amount(&"food"), food + Realm.CAPTURE_LOOT[&"food"], "Loot taken")
	check_eq(state.realm.captured_towns().size(), 1, "One town captured")
	check_eq(result.destroyed, &"", "The nation stands")
	check(state.realm.nations[nation].destroyed == false, "Not destroyed")
	check_eq(state.realm.squad_bonus(), Realm.TOWN_SQUADS * 6, "Five home towns and the new one")


func test_orders_home_and_due_sieges() -> void:
	var state := _realm_state()
	var general := _general(state, 5)
	state.realm.form(state, general, _squads(state, &"royal_swordguard", 5, 400.0))
	var force: Realm.Force = state.realm.forces[0]
	check_eq(state.realm.check_home(force), Realm.Result.ALREADY_HOME, "Already at the capital")
	var east := RealmMap.town_id(0, RealmMap.Slot.EAST)
	force.town = east
	check_eq(state.realm.route(east, Realm.HOME_CAPITAL), [Realm.HOME_CAPITAL] as Array[int], "One road home")
	check_eq(state.realm.order_home(force, 2), Realm.Result.OK, "Ordered home")
	check_eq(state.realm.next_town(force), Realm.HOME_CAPITAL, "Next stop the capital")
	state.realm.end_turn(state)
	check_eq(force.town, Realm.HOME_CAPITAL, "Home")
	check(not force.has_order(), "The way home ends there")
	force.town = east
	var target := -1
	for id in RealmMap.neighbors(east):
		if state.realm.towns[id].owner != Realm.PLAYER:
			target = id
	check_eq(state.realm.order(force, target, 5), Realm.Result.OK, "Siege ordered")
	check_eq(force.order, Realm.SIEGE, "A siege order")
	check(state.realm.due_sieges(5).is_empty(), "Not this turn")
	check_eq(state.realm.due_sieges(6).size(), 1, "At the start of the next one")
	state.realm.end_turn(state)
	check_eq(force.town, east, "A siege does not move the army at the end of the turn")
	var copy := _state(9)
	copy.load_save(JSON.parse_string(JSON.stringify(state.to_save())))
	var saved: Realm.Force = copy.realm.forces[0]
	check_eq([saved.order, saved.target, saved.order_turn], [Realm.SIEGE, target, 5], "The order is saved")
	check(not ForceCompare.odds(10, 30) == ForceCompare.Odds.EASY, "Few against many")
	check_eq(ForceCompare.odds(100, 30), ForceCompare.Odds.EASY, "Many against few")
	check_eq(ForceCompare.odds(100, 90, 0.5), ForceCompare.Odds.HARD, "Walls tip it")


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
	var result := state.finish_siege([force], target, _run(state.start_siege([force], target)))
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
	var result := state.finish_siege([force], capital, _run(state.start_siege([force], capital)))
	check(result.won, "Taken")
	check_eq(result.destroyed, nation.id, "The nation fell")
	check(nation.destroyed, "Marked destroyed")
	check_eq(state.realm.count_owned(nation.id), 0, "Its towns are ours")
	check_eq(result.gained.size(), 3, "Three more towns handed over")
	check(state.realm.armies_of(nation.id).is_empty() and not state.realm.treasury.has(nation.id),
			"No armies or treasury left")


func test_what_towns_give() -> void:
	var state := _realm_state()
	var town := state.realm.towns[RealmMap.town_id(1, RealmMap.Slot.NORTH)]
	var before: int = state.get_turn_yield().get(&"food", 0)
	state.realm.capture(state, town)
	var given := state.realm.town_yield(town)
	check_eq(given[&"food"], Realm.TOWN_YIELD[&"food"], "The full yield, no governor needed")
	check_eq(state.get_turn_yield().get(&"food", 0), before + given[&"food"], "In the kingdom's yield")
	check(state.get_income_breakdown()[&"food"].any(func(entry: Dictionary) -> bool: return entry.source == &"towns"),
			"Its own income line")
	check_eq(state.realm.militia_soldiers(town), Realm.MILITIA_BASE, "Its militia")
	var capital := state.realm.towns[RealmMap.town_id(1, RealmMap.CAPITAL)]
	state.realm.capture(state, capital)
	check_eq(state.realm.town_yield(capital)[&"food"], Realm.TOWN_YIELD[&"food"] * Realm.CAPITAL_YIELD, "A capital gives more")


func test_revolt_chances() -> void:
	var state := _realm_state()
	var nation := state.realm.nation_in(1)
	var town := state.realm.towns[RealmMap.town_id(nation.region, RealmMap.Slot.WEST)]
	check_eq(state.realm.revolt_chance(town, state.turn), 0.0, "Not one of our captured towns")
	state.realm.capture(state, town)
	check_eq(state.realm.revolt_chance(town, state.turn), 0.0, "Not right after it fell")
	var later := state.turn + Realm.REVOLT_GRACE
	check_eq(state.realm.revolt_chance(town, later), Realm.REVOLT_CHANCE, "Unguarded")
	state.realm.form(state, _general(state), _squads(state, &"swordsman", 1))
	state.realm.forces[0].town = town.id
	check_eq(state.realm.revolt_chance(town, later), Realm.REVOLT_GUARDED, "An army holds it")
	nation.destroyed = true
	check_eq(state.realm.revolt_chance(town, later), Realm.REVOLT_PACIFIED, "Its nation is gone")
	check_eq(state.realm.revolt_chance(state.realm.towns[Realm.HOME_CAPITAL], later), 0.0, "Never at home")


func test_an_unguarded_town_revolts() -> void:
	var state := _realm_state()
	var nation := state.realm.nation_in(2)
	var town := state.realm.towns[RealmMap.town_id(nation.region, RealmMap.Slot.EAST)]
	state.realm.capture(state, town)
	nation.destroyed = true
	town.captured_turn = -50
	var lost := false
	for i in 400:
		var report := state.realm.end_turn(state)
		if not report.revolted.is_empty():
			check_eq(report.revolted[0].town, town.id, "That town")
			lost = true
			break
	check(lost, "It rose in time")
	check_eq(town.owner, Realm.REBELS, "Its nation is gone: the rebels hold it")
	check(town.garrison > 0, "With a garrison")
	check_eq(state.realm.owner_name(town, state.kingdom_name), Realm.REBEL_NAME, "Named")
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.to_save()))
	var copy := _state(9)
	copy.load_save(data)
	check_eq(copy.realm.towns[town.id].owner, Realm.REBELS, "Saved")
	check_eq(copy.realm.nations[Realm.REBELS].name, Realm.REBEL_NAME, "The rebels' name")
	# Taking it back.
	var general := _general(state, 5)
	state.realm.form(state, general, _squads(state, &"royal_swordguard", 10, 400.0))
	var force: Realm.Force = state.realm.forces[0]
	var next: int = RealmMap.neighbors(town.id)[0]
	state.realm.towns[next].owner = Realm.PLAYER
	force.town = next
	town.garrison = 10
	var result := state.finish_siege([force], town.id, _run(state.start_siege([force], town.id)))
	check(result.won, "Ten rebels fall")
	check_eq(town.owner, Realm.PLAYER, "Ours again")
	check_eq(result.destroyed, &"", "No nation destroyed by it")


func test_a_guarded_town_fights_its_rebels() -> void:
	var state := _realm_state()
	var nation := state.realm.nation_in(1)
	var town := state.realm.towns[RealmMap.town_id(nation.region, RealmMap.Slot.WEST)]
	state.realm.capture(state, town)
	town.captured_turn = -50
	state.realm.form(state, _general(state, 5), _squads(state, &"royal_swordguard", 10, 400.0))
	state.realm.forces[0].town = town.id
	var found := false
	for i in 300:
		state.realm.end_turn(state)
		if not state.realm.pending_revolt.is_empty():
			found = true
			break
	check(found, "A revolt came")
	check_eq(state.realm.pending_revolt.town, town.id, "In the guarded town")
	check_eq(town.owner, Realm.PLAYER, "Not lost before the battle")
	var copy := _state(9)
	copy.load_save(JSON.parse_string(JSON.stringify(state.to_save())))
	check_eq(copy.realm.pending_revolt.town, town.id, "The revolt is saved")
	var simulator := state.start_revolt()
	check(simulator != null, "The rebels attack")
	check(simulator.record.sides[BattleRecord.DEFENDER].general_name != "", "The army defends")
	var result := state.finish_revolt(_run(simulator))
	check(result.won, "Ten royal squads put it down")
	check_eq(town.owner, Realm.PLAYER, "Held")
	check(state.realm.pending_revolt.is_empty(), "Over")


func test_a_joint_siege() -> void:
	var state := _realm_state()
	var east := RealmMap.town_id(0, RealmMap.Slot.EAST)
	var weak := _general(state, 1)
	var strong := _general(state, 5)
	state.realm.form(state, weak, _squads(state, &"swordsman", 3))
	state.realm.form(state, strong, _squads(state, &"swordsman", 2))
	var first: Realm.Force = state.realm.forces[0]
	var second: Realm.Force = state.realm.forces[1]
	first.town = east
	second.town = east
	var target := -1
	for id in RealmMap.neighbors(east):
		if state.realm.towns[id].owner != Realm.PLAYER:
			target = id
	check_eq(state.realm.order(first, target, 5), Realm.Result.OK, "First ordered")
	check_eq(state.realm.order(second, target, 5), Realm.Result.OK, "Second ordered")
	check_eq(state.realm.besiegers(target).size(), 2, "Both against it")
	var groups := state.realm.due_siege_groups(6)
	check_eq(groups.size(), 1, "One battle")
	check_eq(groups[0].size(), 2, "Two armies in it")
	check_eq(Realm.leader_of(groups[0]), second, "The better general leads")
	state.realm.towns[target].garrison = 20
	var simulator := state.start_siege(groups[0], target)
	var side := simulator.record.sides[BattleRecord.ATTACKER]
	check(side.units.size() >= 5, "Every squad of both armies (%d)" % side.units.size())
	check_eq(side.general_name, strong.name, "Led by the better general")
	var result := state.finish_siege(groups[0], target, _run(simulator))
	check(result.won, "Five squads against twenty")
	check_eq(result.armies, 2, "Reported")
	for force in state.realm.forces:
		check_eq(force.town, target, "Both moved in")
		check(not force.has_order(), "Orders spent")


func test_armies_march_together() -> void:
	var state := _realm_state()
	state.realm.form(state, _general(state), _squads(state, &"swordsman", 1))
	state.realm.form(state, _general(state), _squads(state, &"swordsman", 1))
	var to: int = RealmMap.neighbors(Realm.HOME_CAPITAL)[0]
	for force in state.realm.forces:
		check_eq(state.realm.order(force, to, state.turn), Realm.Result.OK, "Ordered")
	state.realm.end_turn(state)
	check_eq(state.realm.forces_at(to).size(), 2, "Both arrived the next turn")


func test_armies_replenish_on_kingdom_towns() -> void:
	var state := _realm_state()
	var squads := _squads(state, &"swordsman", 2)
	state.realm.form(state, _general(state), squads)
	var force: Realm.Force = state.realm.forces[0]
	squads[0].soldiers = 5
	squads[1].soldiers = 19
	state.realm.end_turn(state)
	check_eq(squads[0].soldiers, 5, "No barracks: no replenishment")
	_build_barracks(state)
	var home := state.replenish_fraction()
	check(home > 0.0, "The barracks gives a share")
	state.realm.end_turn(state)
	var capital_gain := Realm.replenish_gain(20, minf(home, Realm.CAPITAL_REPLENISH_CAP))
	check_eq(squads[0].soldiers, 5 + capital_gain, "The kingdom's share at the capital")
	check_eq(squads[1].soldiers, 20, "Never past full")
	force.town = RealmMap.town_id(0, RealmMap.Slot.EAST)
	force.order = Realm.SIEGE
	force.target = RealmMap.town_id(1, RealmMap.Slot.WEST)
	var before := squads[0].soldiers
	state.realm.end_turn(state)
	check_eq(squads[0].soldiers, before + Realm.replenish_gain(20, home * Realm.TOWN_REPLENISH_SHARE),
			"Half of it in other towns, orders or not")
	var nation := state.realm.nation_in(1)
	var capital := state.realm.towns[nation.capital()]
	state.realm.capture(state, capital)
	check_eq(state.realm.replenish_share(capital.id, home), minf(home, Realm.CAPITAL_REPLENISH_CAP),
			"The whole share in a capital we took")
	check_eq(state.realm.replenish_share(RealmMap.town_id(2, RealmMap.Slot.WEST), home), 0.0, "Nothing on enemy land")


func test_replenish_shares_are_capped() -> void:
	var state := _realm_state()
	var town := RealmMap.town_id(0, RealmMap.Slot.EAST)
	check_eq(state.realm.replenish_share(town, 0.2), 0.1, "Half the kingdom's share in a town")
	check_eq(state.realm.replenish_share(town, 0.5), Realm.TOWN_REPLENISH_CAP, "Capped in a town")
	check_eq(state.realm.replenish_share(Realm.HOME_CAPITAL, 0.2), 0.2, "The whole share at the capital")
	check_eq(state.realm.replenish_share(Realm.HOME_CAPITAL, 0.5), Realm.CAPITAL_REPLENISH_CAP, "Capped at the capital")
	check_eq(Realm.replenish_gain(20, 0.15), 3, "15% of 20")
	check_eq(Realm.replenish_gain(8, 0.13), 2, "Rounded up")
	check_eq(Realm.replenish_gain(20, 0.0), 0, "Nothing at no share")


func test_garrisons_regrow() -> void:
	var state := _realm_state()
	var town := state.realm.towns[RealmMap.town_id(1, RealmMap.Slot.NORTH)]
	town.garrison = 0
	state.realm.end_turn(state)
	check_eq(town.garrison, ceili(town.max_garrison * Realm.GARRISON_REGEN), "A tenth a turn")


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
	advisor.away = true
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
	# A governor saved before M18g comes home.
	data.realm.towns[town.id]["governor"] = {"kind": "advisor", "index": copy.advisors.advisors.size() - 1}
	var old := _state(9)
	old.load_save(data)
	check(not old.advisors.advisors.back().away, "An old governor is free again")
	var plain := _state(4)
	plain.load_save(JSON.parse_string(JSON.stringify(_state(4).to_save())))
	check(not plain.realm.active and plain.generals.max_generals == 3, "Older games are not in it")
