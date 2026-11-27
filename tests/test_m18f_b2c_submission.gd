extends "res://tests/test_suite.gd"
## M18f-b2c: weak neighbors asking to submit, the loyalty of submitted nations, breaking away, and
## sowing discord between two nations (GDD §38).

var terrains := TerrainLibrary.load_all()


func _state(seed_value: int = 3) -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), seed_value)
	state.start()
	var ids: Array = state.diplomacy.clans.keys()
	for clan_id in ids.slice(0, ids.size() - 1):
		state.wars.fronts[clan_id].annexed = true
		state.diplomacy.clans[clan_id].annexed = true
	state.diplomacy.clans[ids.back()].alliance_turns = 99
	state.victory.check(state)
	state.start_realm()
	state.realm.ai_enabled = false
	state.realm.armies.clear()
	for i in 4:
		state.army.add_squad(&"swordsman", 100)
	return state


## The nation of region 1 cut down to its capital and its SOUTH town (the rest ours), its armies
## gone and its garrisons small: weak enough to ask to submit.
func _weak(state: KingdomState) -> Realm.Nation:
	var realm := state.realm
	var nation := realm.nation_in(1)
	for slot in [RealmMap.Slot.NORTH, RealmMap.Slot.WEST, RealmMap.Slot.EAST]:
		var town := realm.towns[RealmMap.town_id(nation.region, slot)]
		town.owner = Realm.PLAYER
		town.garrison = 0
		town.max_garrison = 0
		town.captured_turn = state.turn
	for slot in [RealmMap.Slot.CAPITAL, RealmMap.Slot.SOUTH]:
		realm.towns[RealmMap.town_id(nation.region, slot)].garrison = 20
	return nation


## Rolls the end-of-turn offer until `nation` asks (or 100 tries).
func _offer(state: KingdomState, nation: Realm.Nation) -> void:
	for i in 100:
		state.realm._submission_turn(state)
		if state.realm.pending_submission == nation.id:
			return


func _submitted(state: KingdomState) -> Realm.Nation:
	var nation := _weak(state)
	_offer(state, nation)
	state.realm.accept_submission(state)
	return nation


func _diplomat(state: KingdomState, points: int) -> Advisor:
	var advisor := state.advisors.generate(3)
	advisor.diplomacy = points
	state.advisors.advisors.append(advisor)
	advisor.post = &"diplomacy"
	return advisor


func test_only_a_weak_neighbor_may_submit() -> void:
	var state := _state()
	var realm := state.realm
	var nation := realm.nation_in(1)
	check(not realm.can_submit(state, nation, state.turn + 1), "A whole nation does not ask")
	_weak(state)
	check(realm.can_submit(state, nation, state.turn + 1), "Two towns, weak, bordering us: may ask")
	realm.towns[nation.capital()].garrison = 5000
	check(not realm.can_submit(state, nation, state.turn + 1), "Not while stronger than half of us")
	realm.towns[nation.capital()].garrison = 20
	var north := realm.towns[RealmMap.town_id(nation.region, RealmMap.Slot.NORTH)]
	north.owner = nation.id
	check(not realm.can_submit(state, nation, state.turn + 1), "Not with three towns")
	north.owner = Realm.PLAYER
	for other in RealmWar.live_nations(realm):
		if other != nation and not RealmDiplomacy.borders(realm, other.id, Realm.PLAYER):
			check(not realm.can_submit(state, other, state.turn + 1), "A far nation never asks")


func test_the_diplomat_raises_the_chance() -> void:
	var state := _state()
	check_eq(Realm.submission_chance(state), Realm.SUBMIT_CHANCE, "20% with no diplomat")
	_diplomat(state, 10)
	check(is_equal_approx(Realm.submission_chance(state), 0.4), "+2% a point of Ngoại giao")


func test_an_offer_accepted_makes_a_vassal_that_follows_our_wars() -> void:
	var state := _state()
	var realm := state.realm
	var nation := _weak(state)
	_offer(state, nation)
	check_eq(realm.pending_submission, nation.id, "The weak neighbor asks")
	check_eq(realm.accept_submission(state), Realm.Result.OK, "Accepted")
	check(nation.submitted and nation.vassal != null, "A vassal with its own king")
	check_eq(nation.vassal.stars, Realm.king_stars(nation, state.difficulty), "King's stars by distance + 1")
	check_eq(nation.loyalty, Realm.LOYALTY_START, "Loyalty starts at 50")
	check_eq(realm.towns[nation.capital()].owner, nation.id, "It keeps its towns")
	check(not RealmWar.live_nations(realm).has(nation), "No longer on its own")
	check(not realm.diplomacy.in_bloc(nation.id), "Out of the bloc")
	var dip := realm.diplomacy
	check(not dip.at_war(Realm.PLAYER, nation.id), "Not at war with us")
	for other in RealmWar.live_nations(realm):
		check_eq(dip.at_war(nation.id, other.id), dip.at_war(Realm.PLAYER, other.id), "Shares our war with %s" % other.name)
	var tribute := realm.tribute()
	check_eq(tribute.get(&"food", 0), Realm.TRIBUTE_BASIC_PER_STAR * nation.vassal.stars, "Pays tribute")
	var ours := RealmDiplomacy.power(realm, state, Realm.PLAYER)
	RealmVassals.raise_army(realm, state, nation)
	check_eq(RealmDiplomacy.power(realm, state, Realm.PLAYER), ours, "Its armies are not counted as ours")
	check_eq(realm.armies_of(nation.id)[0].town, nation.capital(), "Raises armies in its own land")


func test_a_refusal_waits_five_turns() -> void:
	var state := _state()
	var realm := state.realm
	var nation := _weak(state)
	_offer(state, nation)
	realm.refuse_submission(state)
	check_eq(realm.pending_submission, &"", "No offer left")
	check(not realm.can_submit(state, nation, state.turn + Realm.SUBMIT_REFUSE_WAIT - 1), "Waits")
	check(realm.can_submit(state, nation, state.turn + Realm.SUBMIT_REFUSE_WAIT), "Asks again after 5 turns")


func test_a_submitted_nation_keeps_the_towns_it_takes() -> void:
	var state := _state()
	var realm := state.realm
	var nation := _submitted(state)
	var mine := RealmVassals.raise_army(realm, state, nation)
	var from := -1
	var target := -1
	for road in RealmMap.roads():
		for ends in [[road.x, road.y], [road.y, road.x]]:
			var a: Realm.Town = realm.towns[ends[0]]
			var b: Realm.Town = realm.towns[ends[1]]
			if target < 0 and a.owner == nation.id and not b.is_capital() and realm.diplomacy.at_war(Realm.PLAYER, b.owner):
				from = a.id
				target = b.id
	check(target >= 0, "An enemy town borders it")
	if target < 0:
		return
	mine.town = from
	realm.towns[target].garrison = 5
	RealmVassals.run_turn(realm, state)
	check_eq(mine.target, target, "Announces the attack")
	state.turn += 1
	realm.towns[target].garrison = 5
	RealmVassals.run_turn(realm, state)
	check_eq(realm.towns[target].owner, nation.id, "The town is the vassal's own")


func test_loyalty_rises_and_falls() -> void:
	var state := _state()
	var realm := state.realm
	var nation := _submitted(state)
	var town := realm.towns[RealmMap.town_id(nation.region, RealmMap.Slot.NORTH)]
	realm._lose_town(state, town, 10, false)
	check_eq(nation.loyalty, Realm.LOYALTY_START + Realm.LOYALTY_TOWN_LOST, "−10 for a town we lose")
	town.owner = Realm.PLAYER
	var capital := realm.towns[Realm.HOME_CAPITAL]
	realm._lose_town(state, capital, 10, false)
	capital.owner = Realm.PLAYER
	check_eq(nation.loyalty, Realm.LOYALTY_START - 30, "−20 for a capital")
	realm.change_loyalty(Realm.LOYALTY_WIN)
	check_eq(nation.loyalty, Realm.LOYALTY_START - 27, "+3 for a big win")
	var advisor := _diplomat(state, 4)
	check_eq(realm.diplomacy.check_visit(realm, state, nation.id, advisor), RealmDiplomacy.Result.OK, "May visit a vassal")
	realm.diplomacy.visit(realm, state, nation.id, advisor)
	check_eq(nation.loyalty, Realm.LOYALTY_START - 17, "+10 for a visit")
	check_eq(realm.diplomacy.check_visit(realm, state, nation.id, advisor), RealmDiplomacy.Result.TOO_SOON, "Once in 5 turns")
	# As strong as we are: −5 a turn.
	realm.towns[nation.capital()].garrison = 50000
	var before := nation.loyalty
	realm._submission_turn(state)
	check_eq(nation.loyalty, before + Realm.LOYALTY_STRONGER, "−5 while they are as strong as us")


func test_at_zero_it_breaks_away() -> void:
	var state := _state()
	var realm := state.realm
	var nation := _submitted(state)
	realm.towns[nation.capital()].garrison = 50000
	nation.loyalty = 5
	var report := realm._submission_turn(state)
	check(not nation.submitted and nation.vassal == null, "No longer our vassal")
	check_eq(report.broke_away, [nation.name], "Reported")
	check(RealmWar.live_nations(realm).has(nation), "On its own again")
	check(realm.diplomacy.at_war(Realm.PLAYER, nation.id), "At war with us")
	check(realm.diplomacy.relation(Realm.PLAYER, nation.id) <= roundi(Realm.BREAKAWAY_MEMORY), "Hates us")
	check(realm.tribute().is_empty(), "No more tribute")


func test_crowned_vassals_never_break_away() -> void:
	var state := _state()
	var realm := state.realm
	var nation := realm.nation_in(1)
	realm.capture(state, realm.towns[nation.capital()])
	realm.destroy_nation(state, nation.id)
	var commander := state.generals.generate(3)
	state.generals.add(commander)
	state.generals.commander = commander
	var king := state.generals.generate(4)
	state.generals.add(king)
	check_eq(realm.crown(state, nation.id, king), Realm.Result.OK, "Crowned")
	realm._lose_town(state, realm.towns[RealmMap.town_id(nation.region, RealmMap.Slot.NORTH)], 10, false)
	realm._submission_turn(state)
	check(nation.vassal != null and not nation.submitted, "Still crowned")
	check(not realm.diplomacy.at_war(Realm.PLAYER, nation.id), "Fights for us")


func test_sowing_discord() -> void:
	var state := _state()
	var realm := state.realm
	var dip := realm.diplomacy
	var nations := RealmWar.live_nations(realm)
	var a := nations[0].id
	var b := nations[1].id
	check_eq(dip.check_discord(realm, state, a, b), RealmDiplomacy.Result.NO_DIPLOMAT, "Needs the Ngoại giao post")
	var advisor := _diplomat(state, 20)
	check_eq(RealmDiplomacy.discord_chance(state), RealmDiplomacy.DISCORD_MAX, "At most 75%")
	advisor.diplomacy = 5
	check(is_equal_approx(RealmDiplomacy.discord_chance(state), 0.4), "20% + 4% a point")
	check_eq(dip.check_discord(realm, state, a, a), RealmDiplomacy.Result.SAME_NATION, "Two different nations")
	var outcome := {}
	var success := false
	var exposed := false
	for i in 60:
		dip.discord_turn = -100
		advisor.away = false
		dip.envoys.clear()
		var before_ab := dip.pair(a, b).memory
		var before_a := dip.pair(Realm.PLAYER, a).memory
		outcome = dip.sow_discord(realm, state, a, b)
		check_eq(outcome.result, RealmDiplomacy.Result.OK, "Sent")
		if outcome.success and not success:
			success = true
			check(is_equal_approx(dip.pair(a, b).memory, before_ab + RealmDiplomacy.DISCORD_HIT), "−50 at once")
			check_eq(dip.pair(a, b).discord, RealmDiplomacy.DISCORD_TURNS, "and more for 5 turns")
		elif not outcome.success and not exposed:
			exposed = true
			check(is_equal_approx(dip.pair(Realm.PLAYER, a).memory, before_a + RealmDiplomacy.DISCORD_EXPOSED), "Exposed: −30 with us")
		if success and exposed:
			break
	check(success and exposed, "Both outcomes seen")
	check(advisor.away, "The diplomat is away")
	check_eq(dip.check_discord(realm, state, a, b), RealmDiplomacy.Result.DISCORD_TOO_SOON, "Once every 5 turns")
	state.turn += RealmDiplomacy.DISCORD_COOLDOWN
	dip.end_turn(realm, state)
	check_eq(dip.check_discord(realm, state, a, b), RealmDiplomacy.Result.OK, "Free again")
	# The −5 a turn.
	var p := dip.pair(a, b)
	p.discord = 2
	var memory := p.memory
	dip.end_turn(realm, state)
	check(is_equal_approx(p.memory, move_toward(memory, 0.0, RealmDiplomacy.MEMORY_FADE) + RealmDiplomacy.DISCORD_PER_TURN),
			"−5 a turn on top of the fading")
	check_eq(p.discord, 1, "One turn less")


func test_submission_is_saved() -> void:
	var state := _state()
	var realm := state.realm
	var nation := _submitted(state)
	nation.loyalty = 33
	var other := RealmWar.live_nations(realm)[0]
	other.submit_after = state.turn + 4
	realm.pending_submission = other.id
	realm.diplomacy.discord_turn = state.turn
	var a := RealmWar.live_nations(realm)[1].id
	realm.diplomacy.pair(other.id, a).discord = 3
	var data := realm.to_save(state)
	var loaded := Realm.new()
	loaded.load_save(JSON.parse_string(JSON.stringify(data)), state)
	var again: Realm.Nation = loaded.nations[nation.id]
	check(again.submitted and again.vassal != null, "Still submitted")
	check_eq(again.loyalty, 33, "Same loyalty")
	check_eq(loaded.nations[other.id].submit_after, state.turn + 4, "Refusal wait kept")
	check_eq(loaded.pending_submission, other.id, "Pending offer kept")
	check_eq(loaded.diplomacy.discord_turn, state.turn, "Discord cooldown kept")
	check_eq(loaded.diplomacy.pair(other.id, a).discord, 3, "Discord turns kept")
	check(not loaded.diplomacy.at_war(Realm.PLAYER, nation.id), "Still on our side")
