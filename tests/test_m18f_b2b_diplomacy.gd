extends "res://tests/test_suite.gd"
## M18f-b2b: diplomacy between the kingdom and the nations (GDD §37): war at the start, the bloc
## by difficulty, relations, peace through an envoy, non-aggression, alliances and their armies.

var terrains := TerrainLibrary.load_all()


func _state(difficulty: int = Difficulty.Level.NORMAL, seed_value: int = 3) -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), seed_value)
	state.difficulty = difficulty
	state.start()
	var ids: Array = state.diplomacy.clans.keys()
	for clan_id in ids.slice(0, ids.size() - 1):
		state.wars.fronts[clan_id].annexed = true
		state.diplomacy.clans[clan_id].annexed = true
	state.diplomacy.clans[ids.back()].alliance_turns = 99
	state.victory.check(state)
	state.start_realm()
	state.realm.ai_enabled = false
	return state


func _advisor(state: KingdomState, diplomacy_points: int = 6) -> Advisor:
	var advisor := state.advisors.generate(3)
	advisor.diplomacy = diplomacy_points
	state.advisors.advisors.append(advisor)
	return advisor


## A nation outside the bloc.
func _free_nation(state: KingdomState) -> Realm.Nation:
	for nation in RealmWar.live_nations(state.realm):
		if not state.realm.diplomacy.in_bloc(nation.id):
			return nation
	return null


## Asks for peace until it is accepted (or 40 tries); returns the last result.
func _make_peace(state: KingdomState, nation_id: StringName) -> Dictionary:
	var dip := state.realm.diplomacy
	var advisor := _advisor(state, 10)
	var result := {}
	for i in 40:
		for member in dip.peace_party(state.realm, nation_id):
			dip.pair(Realm.PLAYER, member).asked_after = 0
		advisor.away = false
		result = dip.ask_peace(state.realm, state, nation_id, advisor, 0, false)
		if result.get("accepted", false):
			break
	return result


func test_war_with_every_nation_and_a_bloc_by_difficulty() -> void:
	var sizes := [0, 2, 3, 5]
	for difficulty in 4:
		var state := _state(difficulty)
		var dip := state.realm.diplomacy
		check_eq(dip.bloc.size(), sizes[difficulty], "Bloc size on %s" % Difficulty.NAMES[difficulty])
		for nation in RealmWar.live_nations(state.realm):
			check(dip.at_war(Realm.PLAYER, nation.id), "At war with %s" % nation.name)
		for a in dip.bloc:
			for b in dip.bloc:
				if a != b:
					check(dip.allied(a, b), "Bloc members are allied")
					check(not dip.at_war(a, b), "and never fight")
	var state := _state(Difficulty.Level.HARD)
	var dip := state.realm.diplomacy
	var leader := dip.bloc[0]
	for nation in RealmWar.live_nations(state.realm):
		check(RealmDiplomacy.power(state.realm, state, nation.id) <= RealmDiplomacy.power(state.realm, state, leader), "The strongest leads")
	check(not dip.at_war(Realm.REBELS, Realm.REBELS) and dip.at_war(Realm.REBELS, leader), "Rebels fight everyone")


func test_relations_drift_toward_their_factors_and_events_fade() -> void:
	var state := _state()
	var dip := state.realm.diplomacy
	var nation := _free_nation(state)
	var p := dip.pair(Realm.PLAYER, nation.id)
	var goal := dip.target(state.realm, state, Realm.PLAYER, nation.id)
	check_eq(float(p.base), goal, "Starts at its factors")
	check(goal < 0, "War weighs on it")
	p.base = goal + 10.0
	p.memory = 5.0
	dip.end_turn(state.realm, state)
	check_eq(p.base, goal + 10.0 - RealmDiplomacy.DRIFT, "Drifts 3 a turn")
	check_eq(p.memory, 5.0 - RealmDiplomacy.MEMORY_FADE, "Events fade 2 a turn")
	var texts := dip.factors(state.realm, state, Realm.PLAYER, nation.id).map(func(f: Dictionary) -> String: return f.text)
	check(texts.has("Chiến tranh"), "War is a factor")


func test_wariness_of_the_strong() -> void:
	var state := _state()
	var realm := state.realm
	var nation := _free_nation(state)
	var before := realm.diplomacy.target(realm, state, Realm.PLAYER, nation.id)
	for other in RealmWar.live_nations(realm):
		if other != nation:
			for town in realm.towns:
				if town.owner == other.id and not town.is_capital():
					town.owner = Realm.PLAYER
					break
	check(realm.diplomacy.target(realm, state, Realm.PLAYER, nation.id) < before, "Our growth makes them wary")


func test_peace_chance_and_what_raises_it() -> void:
	var state := _state()
	var realm := state.realm
	var dip := realm.diplomacy
	var nation := _free_nation(state)
	var advisor := _advisor(state, 0)
	dip.pair(Realm.PLAYER, nation.id).base = 60.0  # keeps the chance off 0 with our small test army
	var base := dip.peace_chance(realm, state, nation.id, advisor)
	check(base > 0.0, "Some chance")
	advisor.diplomacy = 10
	check(absf(dip.peace_chance(realm, state, nation.id, advisor) - base - 0.2) < 0.001, "+2% a Ngoại giao point")
	var town: Realm.Town
	for t in realm.towns:
		if t.owner == nation.id and not t.is_capital():
			town = t
			break
	realm.capture(state, town)
	var held := dip.peace_chance(realm, state, nation.id, advisor)
	check(held >= base + 0.2 + 0.1, "Holding a town of theirs helps (+15%, minus their lost garrison's weight)")
	check(absf(dip.peace_chance(realm, state, nation.id, advisor, 200) - held - 0.1) < 0.001, "Goods: +5% a 100")
	check(absf(dip.peace_chance(realm, state, nation.id, advisor, 2000) - minf(RealmDiplomacy.PEACE_MAX, held + 0.3)) < 0.001,
			"Goods count up to +30%")
	check(dip.peace_chance(realm, state, nation.id, advisor, 0, true) >= minf(RealmDiplomacy.PEACE_MAX, held + 0.35) - 0.001,
			"Handing a town back: +35%")
	check(dip.peace_chance(realm, state, nation.id, advisor, 2000, true) <= RealmDiplomacy.PEACE_MAX, "Never above 90%")


func test_peace_calls_off_the_war() -> void:
	var state := _state(Difficulty.Level.EASY)
	var realm := state.realm
	var dip := realm.diplomacy
	var nation := RealmWar.live_nations(realm)[0]
	var army: NationArmy = realm.armies_of(nation.id)[0]
	army.target = Realm.HOME_CAPITAL + 1
	army.order_turn = state.turn
	var result := _make_peace(state, nation.id)
	check(result.accepted, "Peace in the end")
	check_eq(dip.pact(Realm.PLAYER, nation.id), RealmDiplomacy.Pact.PEACE, "A peace treaty")
	check_eq(dip.pair(Realm.PLAYER, nation.id).turns, RealmDiplomacy.PEACE_TURNS, "15 turns")
	check(not army.has_target(), "Their attack is called off")
	var advisor := _advisor(state)
	check_eq(dip.check_peace(realm, state, nation.id, advisor), RealmDiplomacy.Result.NOT_AT_WAR, "No second peace")
	var general := state.generals.generate(3)
	state.generals.add(general)
	var squads: Array[Army.Squad] = []
	state.army.add_squad(&"swordsman", 20)
	squads.append(state.army.squads.back())
	realm.form(state, general, squads)
	var force: Realm.Force = realm.forces.back()
	var target := -1
	for road in RealmMap.roads():
		for ends in [[road.x, road.y], [road.y, road.x]]:
			if target < 0 and realm.towns[ends[0]].owner == Realm.PLAYER and realm.towns[ends[1]].owner == nation.id:
				force.town = ends[0]
				target = ends[1]
	if target >= 0:
		check_eq(realm.check_siege(force, target), Realm.Result.NOT_AT_WAR, "No siege in peace")
	check_eq(realm.check_intercept(force, army), Realm.Result.NO_ENEMY_ARMY, "No interception in peace")


func test_a_refusal_waits_and_the_envoy_comes_home() -> void:
	var state := _state(Difficulty.Level.EASY)
	var realm := state.realm
	var dip := realm.diplomacy
	var nation := RealmWar.live_nations(realm)[0]
	var advisor := _advisor(state, 0)
	var refused := false
	for i in 60:
		dip.pair(Realm.PLAYER, nation.id).asked_after = 0
		advisor.away = false
		dip.pair(Realm.PLAYER, nation.id).base = -100.0
		var result := dip.ask_peace(realm, state, nation.id, advisor)
		if not result.accepted:
			refused = true
			break
		dip.set_pact(realm, state, Realm.PLAYER, nation.id, RealmDiplomacy.Pact.WAR)
	check(refused, "Refused once")
	check(not advisor.is_ready(), "The envoy is away")
	advisor.away = false
	check_eq(dip.check_peace(realm, state, nation.id, advisor), RealmDiplomacy.Result.REFUSED_RECENTLY, "Wait before asking again")
	advisor.away = true
	dip.end_turn(realm, state)
	check(advisor.is_ready(), "Home when the turn ends")


func test_peace_with_a_bloc_nation_is_peace_with_the_bloc() -> void:
	var state := _state(Difficulty.Level.HARD)
	var dip := state.realm.diplomacy
	var member := dip.bloc[1]
	check_eq(dip.peace_party(state.realm, member).size(), 3, "The whole bloc")
	var result := _make_peace(state, member)
	check(result.accepted, "Peace in the end")
	for id in dip.bloc:
		check_eq(dip.pact(Realm.PLAYER, id), RealmDiplomacy.Pact.PEACE, "Peace with every member")
	dip.pair(Realm.PLAYER, member).pact = RealmDiplomacy.Pact.NEUTRAL
	dip.declare_war(state.realm, state, member, Realm.PLAYER)
	for id in dip.bloc:
		check(dip.at_war(Realm.PLAYER, id), "One member at war brings the bloc")


func test_a_peace_ends_in_war_or_neutrality() -> void:
	var state := _state(Difficulty.Level.EASY)
	var realm := state.realm
	var dip := realm.diplomacy
	var nations := RealmWar.live_nations(realm)
	var angry := nations[0].id
	var calm := nations[1].id
	dip.set_pact(realm, state, Realm.PLAYER, angry, RealmDiplomacy.Pact.PEACE, 1)
	dip.set_pact(realm, state, Realm.PLAYER, calm, RealmDiplomacy.Pact.PEACE, 1)
	dip.pair(Realm.PLAYER, angry).base = -50.0
	dip.pair(Realm.PLAYER, calm).base = 10.0
	var news := dip.end_turn(realm, state)
	check(dip.at_war(Realm.PLAYER, angry), "A hostile nation goes back to war")
	check_eq(dip.pact(Realm.PLAYER, calm), RealmDiplomacy.Pact.NEUTRAL, "Otherwise neutral")
	check(news.size() >= 2, "Reported")


func test_non_aggression_and_alliance_need_a_good_relation() -> void:
	var state := _state(Difficulty.Level.NORMAL)
	var realm := state.realm
	var dip := realm.diplomacy
	var nation := _free_nation(state)
	var advisor := _advisor(state, 10)
	check_eq(dip.check_nap(realm, state, nation.id), RealmDiplomacy.Result.AT_WAR, "Not at war")
	dip.set_pact(realm, state, Realm.PLAYER, nation.id, RealmDiplomacy.Pact.NEUTRAL)
	dip.pair(Realm.PLAYER, nation.id).base = 10.0
	check_eq(dip.check_nap(realm, state, nation.id), RealmDiplomacy.Result.TOO_LOW, "Needs Thân thiện")
	dip.pair(Realm.PLAYER, nation.id).base = 30.0
	check_eq(dip.sign_nap(realm, state, nation.id), RealmDiplomacy.Result.OK, "Always accepted")
	check_eq(dip.pact(Realm.PLAYER, nation.id), RealmDiplomacy.Pact.NAP, "Non-aggression")
	check_eq(dip.check_nap(realm, state, nation.id), RealmDiplomacy.Result.ALREADY, "Renewed only at the end")
	check_eq(dip.check_alliance(realm, state, nation.id, advisor), RealmDiplomacy.Result.TOO_LOW, "Alliance needs Thân thiết")
	check_eq(dip.check_alliance(realm, state, dip.bloc[0], advisor), RealmDiplomacy.Result.AT_WAR, "Not with an enemy")
	dip.pair(Realm.PLAYER, nation.id).base = 70.0
	check(absf(dip.alliance_chance(realm, nation.id, advisor) - (0.3 + 10.0 / 80.0 + 0.2)) < 0.001, "Alliance chance")
	var wars := dip.alliance_wars(realm, nation.id)
	var accepted := false
	for i in 40:
		dip.pair(Realm.PLAYER, nation.id).asked_after = 0
		advisor.away = false
		if dip.ask_alliance(realm, state, nation.id, advisor).accepted:
			accepted = true
			break
	check(accepted, "Allied in the end")
	check(dip.allied(Realm.PLAYER, nation.id), "Allied")
	check_eq(dip.allies_of_player(realm), [nation.id] as Array[StringName], "Our ally")
	for id: StringName in wars.theirs:
		check(dip.at_war(nation.id, id), "Our enemies are theirs")
	check_eq(dip.cancel_alliance(realm, state, nation.id), RealmDiplomacy.Result.OK, "Leaving it")
	check_eq(dip.pact(Realm.PLAYER, nation.id), RealmDiplomacy.Pact.NEUTRAL, "Neutral after")
	check(dip.pair(Realm.PLAYER, nation.id).memory <= RealmDiplomacy.BREAK_VICTIM, "They resent it")


func test_an_alliance_shares_its_enemies() -> void:
	var state := _state(Difficulty.Level.EASY)
	var realm := state.realm
	var dip := realm.diplomacy
	var nations := RealmWar.live_nations(realm)
	var friend := nations[0].id
	var foe := nations[1].id
	dip.set_pact(realm, state, Realm.PLAYER, friend, RealmDiplomacy.Pact.NEUTRAL)
	dip.set_pact(realm, state, Realm.PLAYER, foe, RealmDiplomacy.Pact.PEACE, 10)
	var wars := dip.alliance_wars(realm, friend)
	check(wars.ours.has(foe), "Their enemy becomes ours")
	var advisor := _advisor(state, 10)
	dip.pair(Realm.PLAYER, friend).base = 90.0
	for i in 40:
		dip.pair(Realm.PLAYER, friend).asked_after = 0
		advisor.away = false
		if dip.ask_alliance(realm, state, friend, advisor).accepted:
			break
	check(dip.at_war(Realm.PLAYER, foe), "We go to war with their enemy")
	check_eq(dip.check_alliance(realm, state, foe, advisor), RealmDiplomacy.Result.AT_WAR, "Cannot ally with their enemy")
	dip.set_pact(realm, state, Realm.PLAYER, foe, RealmDiplomacy.Pact.NEUTRAL)
	dip.pair(Realm.PLAYER, foe).base = 90.0
	advisor.away = false
	check_eq(dip.check_alliance(realm, state, foe, advisor), RealmDiplomacy.Result.ENEMY_OF_ALLY, "Still their ally's enemy")


func test_allies_favor_our_enemies_and_intercept_for_us() -> void:
	var state := _state(Difficulty.Level.EASY)
	var realm := state.realm
	var dip := realm.diplomacy
	var nations := RealmWar.live_nations(realm)
	realm.armies.clear()
	# An enemy army about to strike a town of ours next to an ally's town.
	var pair: Array[int] = []
	var ally_id: StringName
	var enemy_id: StringName
	for road in RealmMap.roads():
		for ends in [[road.x, road.y], [road.y, road.x]]:
			var mine: Realm.Town = realm.towns[ends[0]]
			var theirs: Realm.Town = realm.towns[ends[1]]
			if pair.is_empty() and mine.owner == Realm.PLAYER and theirs.owner != Realm.PLAYER:
				pair = [mine.id, theirs.id]
				enemy_id = theirs.owner
	check(not pair.is_empty(), "A border town")
	for nation in nations:
		if nation.id != enemy_id:
			ally_id = nation.id
			break
	dip.set_pact(realm, state, Realm.PLAYER, ally_id, RealmDiplomacy.Pact.ALLIANCE, 20)
	dip.set_pact(realm, state, ally_id, enemy_id, RealmDiplomacy.Pact.WAR)
	var enemy := RealmWar.raise_army(realm, state, realm.nations[enemy_id])
	enemy.town = pair[1]
	enemy.soldiers = 50
	enemy.target = pair[0]
	enemy.order_turn = state.turn - 1
	var helper := RealmWar.raise_army(realm, state, realm.nations[ally_id])
	helper.town = pair[0]  # next to the enemy's town
	helper.soldiers = 400
	helper.max_soldiers = 400
	var memory := dip.pair(Realm.PLAYER, ally_id).memory
	var news := RealmWar.ally_intercepts(realm, state)
	check(not realm.armies.has(enemy), "The ally broke the attack")
	check(news.size() == 1 and "Đồng minh" in news[0], "Reported")
	check_eq(dip.pair(Realm.PLAYER, ally_id).memory, memory + RealmDiplomacy.FIGHT_TOGETHER, "Fighting together helps")


func test_nations_only_attack_whom_they_are_at_war_with() -> void:
	var state := _state(Difficulty.Level.EASY)
	var realm := state.realm
	var dip := realm.diplomacy
	var road := []
	for r in RealmMap.roads():
		var a := realm.towns[r.x]
		var b := realm.towns[r.y]
		if road.is_empty() and a.owner != b.owner and a.owner != Realm.PLAYER and b.owner != Realm.PLAYER:
			road = [a.id, b.id]
	var a_id := realm.towns[road[0]].owner
	var b_id := realm.towns[road[1]].owner
	realm.armies.clear()
	var army := RealmWar.raise_army(realm, state, realm.nations[a_id])
	army.town = road[0]
	army.soldiers = 5000
	realm.towns[road[1]].garrison = 1
	check_eq(RealmWar.pick_target(realm, state, army) >= 0, true, "At war: a target")
	dip.set_pact(realm, state, a_id, b_id, RealmDiplomacy.Pact.PEACE, 10)
	var picked := RealmWar.pick_target(realm, state, army)
	check(picked < 0 or realm.towns[picked].owner != b_id, "Never a town of a nation at peace")


func test_a_bloc_breaks_when_one_member_grows_too_strong() -> void:
	var state := _state(Difficulty.Level.LEGENDARY)
	var realm := state.realm
	var dip := realm.diplomacy
	var big := dip.bloc[0]
	var small := dip.bloc[1]
	dip.pair(big, small).base = 0.0
	dip.pair(big, small).memory = 0.0
	var news := dip.end_turn(realm, state)
	check(not dip.in_bloc(small) or not dip.in_bloc(big), "One left the bloc")
	check(dip.pact(big, small) != RealmDiplomacy.Pact.ALLIANCE, "No longer allied")
	check(news.any(func(line: String) -> bool: return "rời khối" in line), "Reported")
	# A bloc of one is no bloc.
	var state2 := _state(Difficulty.Level.NORMAL)
	var dip2 := state2.realm.diplomacy
	dip2.pair(dip2.bloc[0], dip2.bloc[1]).base = -10.0
	dip2.end_turn(state2.realm, state2)
	check(dip2.bloc.is_empty(), "The bloc broke up")


func test_quiet_wars_between_nations_end_in_peace() -> void:
	var state := _state(Difficulty.Level.EASY)
	var realm := state.realm
	var dip := realm.diplomacy
	var nations := RealmWar.live_nations(realm)
	var p := dip.pair(nations[0].id, nations[1].id)
	p.war_since = state.turn - 30
	p.last_capture = state.turn - 30
	state.turn += 1
	var made := false
	for i in 200:
		dip._ai_peace(realm, state)
		if p.pact == RealmDiplomacy.Pact.PEACE:
			made = true
			break
	check(made, "Peace sooner or later")
	var q := dip.pair(nations[2].id, nations[3].id)
	q.war_since = state.turn - 30
	q.last_capture = state.turn - 2
	for i in 100:
		dip._ai_peace(realm, state)
	check_eq(q.pact, RealmDiplomacy.Pact.WAR, "Not while towns change hands")


func test_visits_and_breaking_treaties() -> void:
	var state := _state(Difficulty.Level.EASY)
	var realm := state.realm
	var dip := realm.diplomacy
	var nations := RealmWar.live_nations(realm)
	var nation := nations[0].id
	var advisor := _advisor(state, 8)
	check_eq(dip.visit(realm, state, nation, advisor), RealmDiplomacy.Result.OK, "A visit")
	check_eq(dip.pair(Realm.PLAYER, nation).memory, 9.0, "+5 + Ngoại giao / 2")
	advisor.away = false
	check_eq(dip.check_visit(realm, state, nation, advisor), RealmDiplomacy.Result.TOO_SOON, "Once in 5 turns")
	dip.set_pact(realm, state, Realm.PLAYER, nation, RealmDiplomacy.Pact.NAP, 10)
	var other := nations[1].id
	var before := dip.pair(Realm.PLAYER, other).memory
	dip.player_declares(realm, state, nation)
	check(dip.at_war(Realm.PLAYER, nation), "At war")
	check_eq(dip.pair(Realm.PLAYER, nation).memory, 9.0 + RealmDiplomacy.BREAK_VICTIM, "The victim resents it")
	check_eq(dip.pair(Realm.PLAYER, other).memory, before + RealmDiplomacy.BREAK_OTHERS, "Everyone else too")


func test_neutral_nations_declare_on_us_when_hostile() -> void:
	var state := _state(Difficulty.Level.EASY)
	var realm := state.realm
	var dip := realm.diplomacy
	var nation := RealmWar.live_nations(realm)[0].id
	dip.set_pact(realm, state, Realm.PLAYER, nation, RealmDiplomacy.Pact.NEUTRAL)
	dip.pair(Realm.PLAYER, nation).base = -90.0
	var news := dip.end_turn(realm, state)
	check(dip.at_war(Realm.PLAYER, nation), "Hatred means war")
	check(news.any(func(line: String) -> bool: return "tuyên chiến với ta" in line), "Reported")


func test_diplomacy_is_saved() -> void:
	var state := _state(Difficulty.Level.HARD)
	var realm := state.realm
	var dip := realm.diplomacy
	var nation := _free_nation(state).id
	dip.set_pact(realm, state, Realm.PLAYER, nation, RealmDiplomacy.Pact.NAP, 7)
	dip.pair(Realm.PLAYER, nation).memory = 12.0
	var advisor := _advisor(state)
	dip.pair(Realm.PLAYER, nation).visit_turn = -100
	dip.visit(realm, state, nation, advisor)
	var data := realm.to_save(state)
	var loaded := Realm.new()
	loaded.load_save(JSON.parse_string(JSON.stringify(data)), state)
	var again := loaded.diplomacy
	check_eq(again.pact(Realm.PLAYER, nation), RealmDiplomacy.Pact.NAP, "Same pact")
	check_eq(again.pair(Realm.PLAYER, nation).turns, 7, "Same turns")
	check_eq(again.relation(Realm.PLAYER, nation), dip.relation(Realm.PLAYER, nation), "Same relation")
	check_eq(again.bloc, dip.bloc, "Same bloc")
	check_eq(again.envoys.size(), 1, "The envoy is still away")
	data.erase("diplomacy")
	var old := Realm.new()
	old.load_save(JSON.parse_string(JSON.stringify(data)), state)
	check(old.diplomacy.at_war(Realm.PLAYER, nation), "An old save starts at war")
	check_eq(old.diplomacy.bloc.size(), 3, "With the bloc of its difficulty")


## Army flags (M18f QoL): each new army takes the first free color, kept in the save.
func _flag_force(state: KingdomState) -> Realm.Force:
	var general := state.generals.generate(3)
	state.generals.generals.append(general)
	var squads: Array[Army.Squad] = []
	state.army.add_squad(&"swordsman", state.units[&"swordsman"].squad_size)
	squads.append(state.army.squads.back())
	check_eq(state.realm.form(state, general, squads), Realm.Result.OK, "Army formed")
	return state.realm.forces.back()


func test_armies_get_their_own_flags() -> void:
	var state := _state()
	var realm := state.realm
	var a := _flag_force(state)
	var b := _flag_force(state)
	var c := _flag_force(state)
	check_eq([a.flag, b.flag, c.flag], [0, 1, 2], "First free colors in order")
	check_eq(realm.disband(state, b, true), Realm.Result.OK, "Army 2 disbanded")
	var d := _flag_force(state)
	check_eq(d.flag, 1, "A new army takes the freed color")
	check_eq(Realm.flag_color(d), Realm.FLAG_COLORS[1], "Its color")
	var data := realm.to_save(state)
	var loaded := Realm.new()
	loaded.load_save(JSON.parse_string(JSON.stringify(data)), state)
	var flags: Array = []
	for force in loaded.forces:
		flags.append(force.flag)
	check_eq(flags, [0, 2, 1], "Flags kept in the save")
	for entry in data.forces:
		entry.erase("flag")
	var old := Realm.new()
	old.load_save(JSON.parse_string(JSON.stringify(data)), state)
	var old_flags := {}
	for force in old.forces:
		old_flags[force.flag] = true
	check_eq(old_flags.size(), 3, "An old save gives each army its own color")


## The realm's turn news go to the notice column (section "realm"), not the line under the pieces.
func test_realm_news_are_notices() -> void:
	var state := _state()
	var report := {"realm": {"marched": [{"general": "Lê Văn A", "to": Realm.HOME_CAPITAL}],
			"news": ["Hai nước đánh nhau."]}}
	var sections := Notices.build(state, report)
	check_eq(sections[0].id, &"realm", "The realm section comes first")
	var ids: Array = sections[0].items.map(func(item: Dictionary) -> StringName: return item.id)
	check(ids.has(&"realm_marched") and ids.has(&"realm_news"), "Marches and the nations' news are listed")
	check(Notices.build(state, {}).all(func(section: Dictionary) -> bool: return section.id != &"realm"),
			"Nothing to say, no realm section")
