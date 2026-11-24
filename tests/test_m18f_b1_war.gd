extends "res://tests/test_suite.gd"
## M18f-b1: the nations' armies (GDD §35): treasury, raising, attacks announced a turn ahead,
## battles between nations, attacks on our towns, interceptions and sieges against armies.

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


func _strong_force(state: KingdomState, town: int) -> Realm.Force:
	var general := state.generals.generate(5)
	state.generals.add(general)
	var squads: Array[Army.Squad] = []
	for i in 20:
		state.army.add_squad(&"royal_swordguard", state.units[&"royal_swordguard"].squad_size)
		state.army.squads.back().xp = 400.0
		squads.append(state.army.squads.back())
	state.realm.form(state, general, squads)
	var force: Realm.Force = state.realm.forces.back()
	force.town = town
	return force


## An army of `nation` placed at `town` with `soldiers`.
func _army(state: KingdomState, nation: Realm.Nation, town: int, soldiers: int) -> NationArmy:
	var army := RealmWar.raise_army(state.realm, state, nation)
	army.town = town
	army.max_soldiers = soldiers
	army.soldiers = soldiers
	return army


## A road between towns of two different nations (neither ours, no capital): [from, to].
func _border(state: KingdomState) -> Array[int]:
	for road in RealmMap.roads():
		var a := state.realm.towns[road.x]
		var b := state.realm.towns[road.y]
		if a.owner != b.owner and a.owner != Realm.PLAYER and b.owner != Realm.PLAYER \
				and not a.is_capital() and not b.is_capital():
			return [a.id, b.id]
	return []


func test_nations_start_with_an_army_and_smaller_garrisons() -> void:
	var state := _realm_state()
	var realm := state.realm
	for nation in RealmWar.live_nations(realm):
		var own := realm.armies_of(nation.id)
		check_eq(own.size(), 1, "%s has one army" % nation.name)
		check_eq(own[0].town, nation.capital(), "In its capital")
		check_eq(own[0].soldiers, RealmWar.army_size(nation, state.wars.enemy_scale), "At full strength")
		check(own[0].general != null, "Led by a general with a portrait")
		check(not state.generals.generals.has(own[0].general), "Not one of ours")
	var near := realm.nation_in(1)
	var town := realm.towns[RealmMap.town_id(near.region, RealmMap.Slot.NORTH)]
	check_eq(town.max_garrison, roundi(110 * state.wars.enemy_scale), "Garrisons are half what they were")


func test_the_treasury_raises_armies() -> void:
	var state := _realm_state()
	var realm := state.realm
	var nation := realm.nation_in(1)
	var income := RealmWar.income(realm, nation.id, state.difficulty)
	check_eq(income, (4 * RealmWar.TOWN_INCOME + RealmWar.CAPITAL_INCOME) * RealmWar.INCOME_BY_DIFFICULTY[state.difficulty],
			"Four towns and a capital")
	check(RealmWar.income(realm, nation.id, Difficulty.Level.HARD) > RealmWar.income(realm, nation.id, Difficulty.Level.EASY),
			"Harder nations earn more")
	realm.treasury[nation.id] = RealmWar.ARMY_COST - 0.01
	var before := realm.armies_of(nation.id).size()
	RealmWar.run_turn(realm, state)
	check_eq(realm.armies_of(nation.id).size(), before + 1, "A second army")
	check(realm.treasury[nation.id] < RealmWar.ARMY_COST, "Paid for it")
	realm.treasury[nation.id] = 100.0
	for i in 10:
		RealmWar.run_turn(realm, state)
	check(realm.armies_of(nation.id).size() <= realm.count_owned(nation.id), "At most one army a town")
	check(realm.treasury[nation.id] <= RealmWar.MAX_TREASURY, "The treasury is capped")


func test_an_attack_on_our_town_is_announced_then_fought() -> void:
	var state := _realm_state()
	var realm := state.realm
	var nation := realm.nation_in(1)
	var ours := realm.towns[RealmMap.town_id(nation.region, RealmMap.Slot.WEST)]
	realm.capture(state, ours)
	var from := -1
	for id in RealmMap.neighbors(ours.id):
		if realm.towns[id].owner == nation.id:
			from = id
	check(from >= 0, "A town of theirs next to it")
	realm.armies.clear()
	var army := _army(state, nation, from, 2000)
	var report := realm.end_turn(state)
	check_eq(army.target, ours.id, "It picks our weak town")
	check_eq(report.threats.size(), 1, "Announced")
	check(realm.pending_attacks.is_empty(), "Not yet")
	state.turn += 1
	report = realm.end_turn(state)
	check_eq(report.attacks.size(), 1, "Now it attacks")
	check_eq(int(realm.pending_attacks[0].town), ours.id, "Our town")
	var simulator := state.start_enemy_attack()
	check(simulator != null, "A defend-town battle")
	check(simulator.record.sides[BattleRecord.DEFENDER].display_name.begins_with("Dân binh"), "The militia defends")
	var result := state.finish_enemy_attack(_run(simulator))
	check(not result.won, "2000 soldiers take it")
	check_eq(ours.owner, nation.id, "Theirs again")
	check_eq(army.town, ours.id, "The army moved in")
	check(not army.has_target(), "Its attack is done")
	check(realm.pending_attacks.is_empty(), "Nothing left to fight")


func test_no_clan_invasion_on_a_turn_with_an_enemy_attack() -> void:
	var state := _realm_state()
	var realm := state.realm
	var nation := realm.nation_in(1)
	var ours := realm.towns[RealmMap.town_id(nation.region, RealmMap.Slot.WEST)]
	realm.capture(state, ours)
	realm.armies.clear()
	for id in RealmMap.neighbors(ours.id):
		if realm.towns[id].owner == nation.id:
			var army := _army(state, nation, id, 2000)
			army.target = ours.id
			army.order_turn = state.turn - 1
			break
	var report := state.end_turn()
	check(not realm.pending_attacks.is_empty(), "An attack waits")
	check(not report.has("pending_invasion"), "It is the turn's battle")


func test_nations_fight_each_other() -> void:
	var state := _realm_state()
	var realm := state.realm
	var road := _border(state)
	check(not road.is_empty(), "Two nations meet somewhere")
	var attacker: Realm.Nation = realm.nations[realm.towns[road[0]].owner]
	var town := realm.towns[road[1]]
	var owner := town.owner
	var army := _army(state, attacker, road[0], 5000)
	army.target = town.id
	army.order_turn = state.turn - 1
	var war := RealmWar.run_turn(realm, state)
	check_eq(war.news.size(), 1, "Reported")
	check_eq(town.owner, attacker.id, "Taken")
	check_eq(army.town, town.id, "The army moved in")
	check(realm.armies_at(town.id).all(func(other: NationArmy) -> bool: return other.nation == attacker.id),
			"No defender left there")
	# Its capital next: the nation falls and its towns go to the winner.
	var victim: Realm.Nation = realm.nations[owner]
	var capital := realm.towns[victim.capital()]
	var gate := -1
	for id in RealmMap.neighbors(capital.id):
		gate = id
	realm.towns[gate].owner = attacker.id
	army.town = gate
	army.soldiers = 20000
	army.target = capital.id
	army.order_turn = state.turn - 1
	war = RealmWar.run_turn(realm, state)
	check(victim.destroyed, "%s is destroyed" % victim.name)
	check_eq(realm.count_owned(victim.id), 0, "Its towns change hands")
	check(realm.armies_of(victim.id).is_empty(), "Its armies are gone")


func test_intercepting_an_army() -> void:
	var state := _realm_state()
	var realm := state.realm
	var nation := realm.nation_in(1)
	var ours := realm.towns[RealmMap.town_id(nation.region, RealmMap.Slot.WEST)]
	realm.capture(state, ours)
	realm.armies.clear()
	var from := -1
	for id in RealmMap.neighbors(ours.id):
		if realm.towns[id].owner == nation.id:
			from = id
	var army := _army(state, nation, from, 300)
	var force := _strong_force(state, ours.id)
	check_eq(realm.check_intercept(force, army), Realm.Result.NOT_MARCHING, "Only an army about to attack")
	army.target = ours.id
	army.order_turn = state.turn
	realm.pending_attacks.append({"town": ours.id, "armies": [army.id]})
	check_eq(realm.order_intercept(force, army, state.turn), Realm.Result.OK, "Ordered")
	check(realm.due_intercept_groups(state.turn).is_empty(), "Next turn")
	var groups := realm.due_intercept_groups(state.turn + 1)
	check_eq(groups.size(), 1, "One interception")
	var simulator := state.start_intercept(groups[0], army.id)
	check(simulator != null, "In the open")
	check(simulator.record.sides[BattleRecord.DEFENDER].general_name == army.general.name, "Their general leads")
	var result := state.finish_intercept(groups[0], army.id, _run(simulator))
	check(result.won, "A strong army wins")
	check(realm.army_by_id(army.id) == null, "The enemy army is gone")
	check(realm.pending_attacks.is_empty(), "Its attack is off")
	check(not force.has_order() and force.town == ours.id, "Ours stays home")


func test_a_siege_fights_the_armies_inside() -> void:
	var state := _realm_state()
	var realm := state.realm
	var nation := realm.nation_in(1)
	var gate := realm.towns[RealmMap.town_id(nation.region, RealmMap.Slot.WEST)]
	realm.capture(state, gate)
	var target := -1
	for id in RealmMap.neighbors(gate.id):
		if realm.towns[id].owner == nation.id and not realm.towns[id].is_capital():
			target = id
	var town := realm.towns[target]
	realm.armies.clear()
	town.garrison = 20
	var army := _army(state, nation, town.id, 500)
	check_eq(realm.town_soldiers(town), 520, "Garrison and army together")
	check_eq(RealmWar.defense_of(realm, town), 520 * (1.0 + Realm.WALL_DEFENSE), "Behind the walls")
	var force := _strong_force(state, gate.id)
	var simulator := state.start_siege([force], town.id)
	check_eq(simulator.record.sides[BattleRecord.DEFENDER].general_name, army.general.name, "Their general leads")
	var result := state.finish_siege([force], town.id, _run(simulator))
	check(result.won, "Taken")
	check(realm.armies_at(town.id).is_empty() and realm.army_by_id(army.id) == null, "The army inside is gone")


func test_town_losses_are_shared() -> void:
	var state := _realm_state()
	var realm := state.realm
	var nation := realm.nation_in(1)
	var town := realm.towns[RealmMap.town_id(nation.region, RealmMap.Slot.NORTH)]
	realm.armies.clear()
	town.garrison = 100
	var army := _army(state, nation, town.id, 300)
	realm.spread_town_losses(town, 200)
	check_eq(town.garrison, 50, "A quarter from the garrison")
	check_eq(army.soldiers, 150, "Three quarters from the army")
	realm.spread_town_losses(town, 1000)
	check(realm.army_by_id(army.id) == null, "Wiped out")


func test_the_armies_are_saved() -> void:
	var state := _realm_state()
	var realm := state.realm
	var nation := realm.nation_in(1)
	var army: NationArmy = realm.armies_of(nation.id)[0]
	army.soldiers = 123
	army.target = RealmMap.town_id(nation.region, RealmMap.Slot.NORTH)
	army.order_turn = 7
	realm.treasury[nation.id] = 4.5
	realm.pending_attacks.append({"town": 3, "armies": [army.id]})
	var force := _strong_force(state, Realm.HOME_CAPITAL)
	force.order = Realm.INTERCEPT
	force.army = army.id
	var data: Dictionary = JSON.parse_string(JSON.stringify(state.to_save()))
	var copy := _state(9)
	copy.load_save(data)
	check_eq(copy.realm.armies.size(), realm.armies.size(), "Every army")
	var loaded := copy.realm.army_by_id(army.id)
	check_eq([loaded.nation, loaded.soldiers, loaded.target, loaded.order_turn, loaded.general.name],
			[army.nation, 123, army.target, 7, army.general.name], "The army")
	check_eq(copy.realm.treasury[nation.id], 4.5, "The treasury")
	check_eq(copy.realm.next_army_id, realm.next_army_id, "Next id")
	check_eq(copy.realm.pending_attacks, [{"town": 3, "armies": [army.id]}], "The waiting attack")
	check_eq(copy.realm.forces[0].army, army.id, "The interception")
	# A game saved before M18f-b1: garrisons halved, one army each.
	var town_id := RealmMap.town_id(nation.region, RealmMap.Slot.NORTH)
	data.realm.erase("v")
	data.realm.erase("armies")
	data.realm.erase("treasury")
	data.realm.erase("attacks")
	data.realm.towns[town_id].max = 400
	data.realm.towns[town_id].garrison = 400
	var old := _state(9)
	old.load_save(data)
	check_eq(old.realm.towns[town_id].max_garrison, 200, "Halved")
	check_eq(old.realm.towns[town_id].garrison, 200, "Never above it")
	check_eq(old.realm.armies.size(), RealmWar.live_nations(old.realm).size(), "One army a nation")
