extends "res://tests/test_suite.gd"
## M18f-b2a: pacifying a destroyed nation's land and crowning a vassal king there (GDD §36).

var terrains := TerrainLibrary.load_all()


func _state(seed_value: int = 3) -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), seed_value)
	state.start()
	return state


## A realm with the nation of region 1 destroyed by us (all its towns ours), the other nations' armies
## cleared and the AI off, plus a 3★ commander and a home general to crown.
func _conquered(seed_value: int = 3) -> KingdomState:
	var state := _state(seed_value)
	var ids: Array = state.diplomacy.clans.keys()
	for clan_id in ids.slice(0, ids.size() - 1):
		state.wars.fronts[clan_id].annexed = true
		state.diplomacy.clans[clan_id].annexed = true
	state.diplomacy.clans[ids.back()].alliance_turns = 99
	state.victory.check(state)
	state.start_realm()
	state.realm.ai_enabled = false
	state.realm.armies.clear()
	var nation := state.realm.nation_in(1)
	state.realm.capture(state, state.realm.towns[nation.capital()])
	state.realm.destroy_nation(state, nation.id)
	var commander := state.generals.generate(3)
	state.generals.add(commander)
	state.generals.commander = commander
	return state


func _king(state: KingdomState, stars: int = 5, might: int = 8, command: int = 10) -> General:
	var general := state.generals.generate(stars)
	general.might = might
	general.command = command
	state.generals.add(general)
	return general


func _nation(state: KingdomState) -> Realm.Nation:
	return state.realm.nation_in(1)


func _region_town(state: KingdomState, slot: int) -> Realm.Town:
	return state.realm.towns[RealmMap.town_id(_nation(state).region, slot)]


func test_pacifying_waits_for_a_vassal_then_falls_to_one_percent() -> void:
	var state := _conquered()
	var nation := _nation(state)
	var town := _region_town(state, RealmMap.Slot.NORTH)
	var turn := state.turn + Realm.REVOLT_GRACE + 3
	check_eq(state.realm.revolt_chance(town, turn), Realm.REVOLT_PACIFIED, "2% without a vassal")
	check_eq(state.realm.revolt_chance(town, turn + 10), Realm.REVOLT_PACIFIED, "Still 2% later on")
	var king := _king(state, 5, 8, 0)
	check_eq(state.realm.crown(state, nation.id, king), Realm.Result.OK, "Crowned")
	var at := nation.vassal_turn
	var expected: Array[float] = [0.02, 0.02, 0.018, 0.016, 0.014, 0.012, 0.01, 0.01, 0.01]
	for i in expected.size():
		check(absf(state.realm.pacified_chance(nation, at + i) - expected[i]) < 0.00001,
				"Turn +%d: %.1f%%" % [i, expected[i] * 100.0])


func test_the_kings_command_lowers_it_further() -> void:
	var state := _conquered()
	var nation := _nation(state)
	var king := _king(state, 6, 10, 16)
	state.realm.crown(state, nation.id, king)
	var late := nation.vassal_turn + 20
	check(absf(state.realm.pacified_chance(nation, late) - (0.01 - 16 * Realm.VASSAL_COMMAND_CUT)) < 0.00001,
			"1% − 0.05% × 16 = 0.2%")
	king.command = 30
	check_eq(state.realm.pacified_chance(nation, late), 0.0, "Never below 0")


func test_crowning_rules() -> void:
	var state := _conquered()
	var realm := state.realm
	var live: Realm.Nation = RealmWar.live_nations(realm)[0]
	var king := _king(state)
	check_eq(realm.check_crown(state, live.id, king), Realm.Result.NOT_CONQUERED, "Only a destroyed nation")
	check_eq(realm.check_crown(state, _nation(state).id, state.generals.commander), Realm.Result.IS_COMMANDER,
			"Not the commander")
	king.wounded_turns = 2
	check_eq(realm.check_crown(state, _nation(state).id, king), Realm.Result.GENERAL_BUSY, "Not a wounded one")
	king.wounded_turns = 0
	check_eq(realm.check_crown(state, _nation(state).id, king), Realm.Result.OK, "A general at home")
	realm.towns[_nation(state).capital()].owner = Realm.REBELS
	check_eq(realm.check_crown(state, _nation(state).id, king), Realm.Result.NOT_CONQUERED, "The old capital must be ours")


func test_crowning_takes_the_general_and_returns_their_items() -> void:
	var state := _conquered()
	var nation := _nation(state)
	var king := _king(state)
	var item := state.equipment.create(&"general", &"weapon", Item.Rarity.RARE)
	state.equipment.receive(item, state.stockpile)
	state.equipment.equip(king, item)
	check(king.items.has(item.slot), "Wearing it")
	var count := state.generals.generals.size()
	check_eq(state.realm.crown(state, nation.id, king), Realm.Result.OK, "Crowned")
	check_eq(state.generals.generals.size(), count - 1, "One general fewer")
	check(not state.generals.generals.has(king), "The king left our generals")
	check(state.equipment.items.has(item), "The item came back to the storage")
	check(king.items.is_empty(), "The king wears nothing of ours")
	check_eq(nation.vassal, king, "The land has its king")
	check_eq(state.realm.armies_of(nation.id).size(), 1, "The vassal raises its first army")
	var army: NationArmy = state.realm.armies_of(nation.id)[0]
	check(state.realm.is_ally(army), "An ally")
	check_eq(army.soldiers, RealmVassals.ARMY_SIZE, "280 soldiers")
	check_eq(army.general.stars, king.stars - 1, "Led by a general one star below the king")
	check_eq(state.realm.check_crown(state, nation.id, _king(state)), Realm.Result.ALREADY_VASSAL, "One king a land")


func test_the_guard_defends_every_town_of_the_land() -> void:
	var state := _conquered()
	var nation := _nation(state)
	var town := _region_town(state, RealmMap.Slot.NORTH)
	check_eq(state.realm.vassal_guard(town), 0, "No guard before")
	var king := _king(state, 5, 8, 4)
	state.realm.crown(state, nation.id, king)
	check_eq(state.realm.vassal_guard(town), 40 + 5 * 8, "40 + 5 × Võ lực")
	var defenders := state.realm.town_defenders(state, town)
	var soldiers := 0
	for unit in defenders.units:
		soldiers += unit.soldiers
	check(soldiers >= state.realm.militia_soldiers(town) + state.realm.vassal_guard(town), "Militia and guard both defend")
	var home := state.realm.towns[RealmMap.town_id(0, RealmMap.Slot.NORTH)]
	check_eq(state.realm.vassal_guard(home), 0, "Not outside the land")


func test_tribute_by_stars() -> void:
	var three := General.new()
	three.stars = 3
	var tribute := Realm.tribute_of(three)
	check_eq(tribute.get(&"food", 0), 15, "3★: 15 food")
	check(not tribute.has(&"ore"), "3★: no rare goods")
	var four := General.new()
	four.stars = 4
	check_eq(Realm.tribute_of(four).get(&"horses", 0), 2, "4★: 2 of each rare good")
	var six := General.new()
	six.stars = 6
	check_eq(Realm.tribute_of(six).get(&"stone", 0), 30, "6★: 30 of each basic good")
	check_eq(Realm.tribute_of(six).get(&"hardwood", 0), 6, "6★: 6 of each rare good")
	var state := _conquered()
	var before: int = state.get_turn_yield().get(&"food", 0)
	state.realm.crown(state, _nation(state).id, _king(state, 6))
	check_eq(state.get_turn_yield().get(&"food", 0), before + 30, "Paid every turn with the income")


func test_vassal_intercepts_an_enemy_about_to_strike_its_land() -> void:
	var state := _conquered()
	var nation := _nation(state)
	state.realm.crown(state, nation.id, _king(state))
	var realm := state.realm
	var mine: NationArmy = realm.armies_of(nation.id)[0]
	# Find a town of the land next to an enemy town.
	var pair: Array[int] = []
	for road in RealmMap.roads():
		for ends in [[road.x, road.y], [road.y, road.x]]:
			var a: Realm.Town = realm.towns[ends[0]]
			var b: Realm.Town = realm.towns[ends[1]]
			if pair.is_empty() and a.nation == nation.id and a.owner == Realm.PLAYER \
					and b.owner != Realm.PLAYER and b.owner != Realm.REBELS and realm.nations.has(b.owner) \
					and not realm.nations[b.owner].destroyed:
				pair = [a.id, b.id]
	check(not pair.is_empty(), "A town of the land borders an enemy")
	if pair.is_empty():
		return
	var enemy_nation: Realm.Nation = realm.nations[realm.towns[pair[1]].owner]
	var enemy := RealmWar.raise_army(realm, state, enemy_nation)
	enemy.town = pair[1]
	enemy.soldiers = 60
	enemy.max_soldiers = 60
	enemy.target = pair[0]
	enemy.order_turn = state.turn - 1
	# Our vassal stands in a town next to the enemy (the target itself borders it).
	mine.town = pair[0]
	var news := RealmVassals.run_turn(realm, state)
	check(not realm.armies.has(enemy), "The enemy army was broken before it struck")
	check(news.size() >= 1 and "chặn" in news[0], "Reported")


func test_vassal_takes_a_weak_enemy_town_for_us() -> void:
	var state := _conquered()
	var nation := _nation(state)
	state.realm.crown(state, nation.id, _king(state))
	var realm := state.realm
	var mine: NationArmy = realm.armies_of(nation.id)[0]
	var target := -1
	var from := -1
	for road in RealmMap.roads():
		for ends in [[road.x, road.y], [road.y, road.x]]:
			var a: Realm.Town = realm.towns[ends[0]]
			var b: Realm.Town = realm.towns[ends[1]]
			if target < 0 and a.nation == nation.id and b.owner != Realm.PLAYER and not b.is_capital():
				from = a.id
				target = b.id
	check(target >= 0, "An enemy town borders the land")
	if target < 0:
		return
	mine.town = from
	realm.towns[target].garrison = 5
	RealmVassals.run_turn(realm, state)
	check_eq(mine.target, target, "Announces the attack a turn ahead")
	check(realm.towns[target].owner != Realm.PLAYER, "Not yet taken")
	state.turn += 1
	realm.towns[target].garrison = 5
	var news := RealmVassals.run_turn(realm, state)
	check_eq(realm.towns[target].owner, Realm.PLAYER, "The town is ours")
	check_eq(mine.town, target, "The army moves in")
	check(news.any(func(line: String) -> bool: return "cho ta" in line), "Reported")


func test_nations_leave_vassal_armies_alone_and_we_cannot_intercept_them() -> void:
	var state := _conquered()
	var nation := _nation(state)
	state.realm.crown(state, nation.id, _king(state))
	var realm := state.realm
	var mine: NationArmy = realm.armies_of(nation.id)[0]
	mine.target = _region_town(state, RealmMap.Slot.NORTH).id
	mine.order_turn = state.turn - 1
	realm.ai_enabled = true
	RealmWar.run_turn(realm, state)
	check(realm.pending_attacks.is_empty(), "A vassal army never attacks us")
	var general := state.generals.generate(3)
	state.generals.add(general)
	var squads: Array[Army.Squad] = []
	state.army.add_squad(&"swordsman", 20)
	squads.append(state.army.squads.back())
	realm.form(state, general, squads)
	check_eq(realm.check_intercept(realm.forces.back(), mine), Realm.Result.NO_ENEMY_ARMY, "Not an enemy")


func test_vassal_falls_with_its_whole_land() -> void:
	var state := _conquered()
	var nation := _nation(state)
	state.realm.crown(state, nation.id, _king(state))
	var realm := state.realm
	for town in realm.region_towns(nation.region):
		if town.id != nation.capital():
			town.owner = Realm.REBELS
	check(realm.check_vassals().is_empty(), "Still holds its capital")
	realm.towns[nation.capital()].owner = Realm.REBELS
	var fallen := realm.check_vassals()
	check_eq(fallen.size(), 1, "Falls with its last town")
	check(nation.vassal == null, "No king any more")
	check(realm.armies_of(nation.id).is_empty(), "Its armies break up")
	check_eq(realm.pacified_chance(nation, state.turn + 9), Realm.REVOLT_PACIFIED, "Back to 2%")


func test_vassals_are_saved() -> void:
	var state := _conquered()
	var nation := _nation(state)
	var king := _king(state, 4, 7, 6)
	state.realm.crown(state, nation.id, king)
	var data := state.realm.to_save(state)
	var loaded := Realm.new()
	loaded.load_save(JSON.parse_string(JSON.stringify(data)), state)
	var again: Realm.Nation = loaded.nations[nation.id]
	check(again.vassal != null, "The king is back")
	check_eq(again.vassal.name, king.name, "Same king")
	check_eq(again.vassal.might, 7, "Same might")
	check_eq(again.vassal_turn, nation.vassal_turn, "Same crowning turn")
	check_eq(loaded.armies_of(nation.id).size(), 1, "Its army is back")
	check(loaded.is_ally(loaded.armies_of(nation.id)[0]), "Still an ally")


func test_armies_of_a_fallen_nation_hold_their_towns_as_rebels() -> void:
	var state := _state()
	var ids: Array = state.diplomacy.clans.keys()
	for clan_id in ids.slice(0, ids.size() - 1):
		state.wars.fronts[clan_id].annexed = true
		state.diplomacy.clans[clan_id].annexed = true
	state.diplomacy.clans[ids.back()].alliance_turns = 99
	state.victory.check(state)
	state.start_realm()
	var realm := state.realm
	realm.armies.clear()
	var nation := realm.nation_in(1)
	var held := realm.towns[RealmMap.town_id(nation.region, RealmMap.Slot.NORTH)]
	var empty := realm.towns[RealmMap.town_id(nation.region, RealmMap.Slot.SOUTH)]
	for soldiers in [150, 90]:
		var army := RealmWar.raise_army(realm, state, nation)
		army.town = held.id
		army.soldiers = soldiers
	realm.capture(state, realm.towns[nation.capital()])
	var holdouts: Array[int] = []
	var gained := realm.destroy_nation(state, nation.id, holdouts)
	check_eq(holdouts, [held.id] as Array[int], "The town its armies stand in holds out")
	check_eq(held.owner, Realm.REBELS, "As rebels")
	check_eq(held.garrison, 240, "Held by the armies' soldiers")
	check_eq(held.max_garrison, 240, "And never more")
	check(not gained.has(held.id), "Not handed over")
	check_eq(empty.owner, Realm.PLAYER, "An empty town is handed over")
	check(realm.armies_of(nation.id).is_empty(), "The armies break up")
