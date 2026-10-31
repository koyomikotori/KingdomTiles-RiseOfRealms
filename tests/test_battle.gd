extends "res://tests/test_suite.gd"

var terrains := TerrainLibrary.load_all()
var buildings := BuildingData.load_all()
var unit_list := UnitData.load_all()
var enemies := UnitData.load_enemies()


func _unit(id: StringName, row: UnitData.Row, kind: UnitData.AttackKind, melee_attack: int = 5,
		melee_defense: int = 5, armor: int = 0, charge: int = 0, morale: int = 50,
		range_attack: int = 0, reload_time: float = 5.0) -> UnitData:
	var unit := UnitData.new()
	unit.unit_id = id
	unit.display_name = String(id)
	unit.row = row
	unit.attack_kind = kind
	unit.melee_attack = melee_attack
	unit.melee_defense = melee_defense
	unit.armor = armor
	unit.charge_attack = charge
	unit.morale = morale
	unit.range_attack = range_attack
	unit.reload_time = reload_time
	return unit


func _side(units: Array) -> BattleSide:
	var side := BattleSide.new("test")
	for pair in units:
		side.add_unit(pair[0], pair[1])
	return side


func _run_until(simulator: BattleSimulator, seconds: float) -> void:
	while not simulator.finished and simulator.time < seconds - 0.0001:
		simulator.step()


func _events(record: BattleRecord, type: StringName, side: int = -1) -> Array:
	return record.events.filter(func(e: Dictionary) -> bool: return e.type == type and (side == -1 or e.side == side))


func _seeded_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _state() -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 5)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains, buildings, unit_list, 9)
	state.start()
	return state


## A target that cannot be hurt much and never breaks, to observe one side's attacks over time.
func _wall() -> UnitData:
	return _unit(&"wall", UnitData.Row.FRONT, UnitData.AttackKind.MELEE, 0, 1000, 1000, 0, 1000)


func test_unit_data_v2() -> void:
	var by_id := {}
	for unit in unit_list:
		by_id[unit.unit_id] = unit
	check_eq(by_id[&"swordsman"].squad_size, 20, "A swordsman squad has 20 soldiers")
	check_eq([by_id[&"archer"].row, by_id[&"archer"].attack_kind], [UnitData.Row.BACK, UnitData.AttackKind.BOW], "Archers shoot from the back")
	check(by_id[&"archer"].range_attack > 0 and by_id[&"swordsman"].range_attack == 0, "Only ranged units have range attack")
	check(by_id[&"swordsman"].morale > enemies[&"bandit_thug"].morale, "Trained soldiers have higher morale than bandits")


func test_same_seed_same_battle() -> void:
	var raid := RaidData.load_bandits()
	var make := func() -> BattleRecord:
		var kingdom := _side([[unit_list[0], 20], [unit_list[2], 15]])
		return BattleSimulator.simulate(RaidSystem.create_bandit_side(raid, enemies, 20, _seeded_rng(1)), kingdom, 77)
	var a: BattleRecord = make.call()
	var b: BattleRecord = make.call()
	check_eq(a.snapshots, b.snapshots, "Identical snapshots")
	check_eq(a.events, b.events, "Identical events")
	check_eq([a.winner, a.end_reason, a.duration], [b.winner, b.end_reason, b.duration], "Identical outcome")


func test_no_defenders_loses_immediately() -> void:
	var record := BattleSimulator.simulate(_side([[enemies[&"bandit_thug"], 10]]), _side([]), 1)
	check_eq([record.winner, record.end_reason], [BattleRecord.ATTACKER, BattleRecord.EndReason.NO_ARMY], "Nobody to fight")
	check_eq(record.duration, 0.0, "Ends at time 0")


func test_guns_fire_once_at_the_front_row() -> void:
	var gun := _unit(&"gun", UnitData.Row.BACK, UnitData.AttackKind.GUN, 1, 1, 0, 0, 50, 10)
	var front := _unit(&"front", UnitData.Row.FRONT, UnitData.AttackKind.MELEE, 0, 5, 0, 0, 1000)
	var back := _unit(&"back", UnitData.Row.BACK, UnitData.AttackKind.MELEE, 0, 5, 0, 0, 1000)
	var defender := _side([[front, 100], [back, 100]])
	var simulator := BattleSimulator.new(_side([[_wall(), 100], [gun, 10]]), defender, 2)
	_run_until(simulator, 2.9)
	check_eq(_events(simulator.record, &"gun_volley").size(), 1, "Exactly one gun volley")
	check_eq(_events(simulator.record, &"gun_volley")[0].time, BattleSimulator.GUN_TIME, "Fired at GUN_TIME")
	check(defender.units[0].soldiers < 100.0, "Front row took bullets")
	check_eq(defender.units[1].soldiers, 100.0, "Back row untouched")
	_run_until(simulator, 30.0)
	check_eq(_events(simulator.record, &"gun_volley").size(), 1, "Guns never fire again")


func test_archers_reload_and_better_bows_fire_faster() -> void:
	for pair in [[5.0, 4], [2.5, 8]]:
		var bow := _unit(&"bow", UnitData.Row.BACK, UnitData.AttackKind.BOW, 1, 1, 0, 0, 50, 6, pair[0])
		var simulator := BattleSimulator.new(_side([[_wall(), 100], [bow, 10]]), _side([[_wall(), 100]]), 3)
		_run_until(simulator, 20.0)
		check_eq(_events(simulator.record, &"arrow_volley").size(), pair[1], "Reload %ss: volleys in 20s" % pair[0])


func test_arrows_spread_over_all_rows() -> void:
	var bow := _unit(&"bow", UnitData.Row.BACK, UnitData.AttackKind.BOW, 1, 1, 0, 0, 50, 10)
	var target := func(row: UnitData.Row) -> UnitData:
		return _unit(&"t", row, UnitData.AttackKind.MELEE, 0, 5, 0, 0, 1000)
	var defender := _side([[target.call(UnitData.Row.FRONT), 50], [target.call(UnitData.Row.MIDDLE), 50],
			[target.call(UnitData.Row.BACK), 50]])
	var simulator := BattleSimulator.new(_side([[_wall(), 100], [bow, 30]]), defender, 4)
	_run_until(simulator, 2.0)
	for i in 3:
		check(defender.units[i].soldiers < 50.0, "Row %d was hit by the first volley" % i)


func test_melee_hits_front_row_and_charges_once() -> void:
	var sword := _unit(&"sword", UnitData.Row.FRONT, UnitData.AttackKind.MELEE, 10, 5, 0, 10, 50)
	var front := _unit(&"front", UnitData.Row.FRONT, UnitData.AttackKind.MELEE, 0, 5, 0, 0, 1000)
	var back := _unit(&"back", UnitData.Row.BACK, UnitData.AttackKind.MELEE, 0, 5, 0, 0, 1000)
	var defender := _side([[front, 200], [back, 50]])
	var simulator := BattleSimulator.new(_side([[sword, 20]]), defender, 4)
	_run_until(simulator, BattleSimulator.CONTACT_TIME - 0.05)
	check_eq(defender.units[0].soldiers, 200.0, "No melee before contact")
	_run_until(simulator, 10.0)
	check(defender.units[0].soldiers < 200.0, "Front row is hit in melee")
	check_eq(defender.units[1].soldiers, 50.0, "Back row is safe while the front row stands")
	check_eq(_events(simulator.record, &"charge", BattleRecord.ATTACKER).size(), 1, "The sword unit charges exactly once")


func test_charge_adds_a_burst_of_casualties() -> void:
	var make := func(charge: int) -> float:
		var unit := _unit(&"u", UnitData.Row.FRONT, UnitData.AttackKind.MELEE, 5, 5, 0, charge, 50)
		var defender := _side([[_unit(&"t", UnitData.Row.FRONT, UnitData.AttackKind.MELEE, 0, 5, 0, 0, 1000), 200]])
		var simulator := BattleSimulator.new(_side([[unit, 20]]), defender, 5)
		_run_until(simulator, BattleSimulator.CONTACT_TIME + 0.15)
		return 200.0 - defender.units[0].soldiers
	# Expected burst: 20 soldiers x 10/(10+5) x CHARGE_FACTOR.
	var burst := 20 * 10.0 / 15.0 * BattleSimulator.CHARGE_FACTOR
	check(make.call(10) > make.call(0) + burst * 0.8, "A charging unit kills more on contact")


func test_morale_breaks_unit_before_it_is_wiped_out() -> void:
	var strong := _unit(&"strong", UnitData.Row.FRONT, UnitData.AttackKind.MELEE, 20, 10, 0, 0, 50)
	var shaky := _unit(&"shaky", UnitData.Row.FRONT, UnitData.AttackKind.MELEE, 2, 2, 0, 0, 3)
	var defender := _side([[shaky, 40]])
	var record := BattleSimulator.simulate(_side([[strong, 40]]), defender, 6)
	check(defender.units[0].broken, "Morale 3 breaks after losing 25%")
	check(defender.units[0].alive() > 0, "Broken while soldiers were still alive")
	check(defender.units[0].lost() >= 10, "Broke only after at least a quarter was lost")
	check_eq([record.winner, record.end_reason], [BattleRecord.ATTACKER, BattleRecord.EndReason.ALL_BROKEN], "All broken = defeat")


func test_higher_morale_holds_longer() -> void:
	var broke_at := func(morale: int) -> int:
		var unit := _unit(&"u", UnitData.Row.FRONT, UnitData.AttackKind.MELEE, 1, 2, 0, 0, morale)
		var defender := _side([[unit, 40]])
		BattleSimulator.simulate(_side([[_unit(&"s", UnitData.Row.FRONT, UnitData.AttackKind.MELEE, 20, 10, 0, 0, 50), 40]]), defender, 7)
		return defender.units[0].lost()
	check(broke_at.call(9) > broke_at.call(4), "Morale 9 takes more losses than morale 4 before breaking")


func test_retreat_ends_battle_as_a_loss() -> void:
	var simulator := BattleSimulator.new(_side([[unit_list[0], 20]]), _side([[unit_list[1], 20]]), 8)
	_run_until(simulator, 6.0)
	simulator.retreat(BattleRecord.DEFENDER)
	check(simulator.finished, "Battle is over")
	check_eq([simulator.record.winner, simulator.record.end_reason, simulator.record.retreated_side],
			[BattleRecord.ATTACKER, BattleRecord.EndReason.RETREAT, BattleRecord.DEFENDER], "Retreating side loses")
	var soldiers_after := simulator.record.sides[BattleRecord.DEFENDER].alive_total()
	simulator.step()
	check_eq(simulator.record.sides[BattleRecord.DEFENDER].alive_total(), soldiers_after, "No fighting after the end")


func test_time_limit_goes_to_defender() -> void:
	var record := BattleSimulator.simulate(_side([[_wall(), 10]]), _side([[_wall(), 10]]), 9)
	check_eq([record.winner, record.end_reason], [BattleRecord.DEFENDER, BattleRecord.EndReason.TIME_LIMIT], "Defender holds")
	check(absf(record.duration - BattleSimulator.TIME_LIMIT) < 0.01, "Lasted the full time")
	# The attacker has more of its soldiers left, but has not won in time: it still loses.
	var defender := _side([[_wall(), 10]])
	defender.units[0].soldiers = 4.0
	record = BattleSimulator.simulate(_side([[_wall(), 10]]), defender, 9)
	check_eq([record.winner, record.end_reason], [BattleRecord.DEFENDER, BattleRecord.EndReason.TIME_LIMIT],
			"An attacker that runs out of time loses even when ahead")


func test_kills_never_exceed_enemy_soldiers() -> void:
	var defender := _side([[unit_list[0], 20], [unit_list[2], 15]])
	var attacker := RaidSystem.create_bandit_side(RaidData.load_bandits(), enemies, 6, _seeded_rng(3))
	BattleSimulator.simulate(attacker, defender, 10)
	var kills := 0.0
	for unit in defender.units:
		kills += unit.kills
	check(kills <= attacker.start_total() + 0.01, "Kills %.2f <= %d bandits" % [kills, attacker.start_total()])


func test_raid_chance_and_watchtowers() -> void:
	var raid := RaidData.load_bandits()
	var state := _state()
	check_eq(RaidSystem.get_raid_chance(state, raid), 0.0, "No raids on turn 1")
	state.turn = 6
	check(is_equal_approx(RaidSystem.get_raid_chance(state, raid), 0.15), "15% from turn 6")
	state.stockpile.add({&"wood": 50, &"stone": 50})
	state.build(&"watchtower", Vector2i(4, 4))
	check(is_equal_approx(RaidSystem.get_raid_chance(state, raid), 0.11), "One tower: 15% - 4%")
	check_eq(state.build(&"watchtower", Vector2i(7, 4)), BuildRules.Result.LIMIT_REACHED, "Only one at castle level 1")
	var limits: Array[int] = []
	for level in range(1, 7):
		limits.append(BuildRules.limit(state.buildings[&"watchtower"], level))
	check_eq(limits, [1, 2, 3, 4, 4, 4] as Array[int], "+1 per castle level, 4 at most (M14d)")
	state.castle_level = 3
	state.build(&"watchtower", Vector2i(7, 4))
	state.build(&"watchtower", Vector2i(4, 7))
	check(is_equal_approx(RaidSystem.get_raid_chance(state, raid), 0.03), "Three towers: 3%")
	state.buildings_supplied = false
	check(is_equal_approx(RaidSystem.get_raid_chance(state, raid), 0.15), "Unpaid towers do nothing")


func test_watchtower_upkeep_paid_or_paused() -> void:
	var state := _state()
	state.stockpile.add({&"wood": 4, &"stone": 3, &"food": 1})
	state.build(&"watchtower", Vector2i(4, 4))
	check_eq(state.get_building_upkeep(), {&"food": 1}, "Tower costs 1 food per turn")
	var report := state.end_turn()
	check(report.buildings_supplied, "Upkeep paid with 1 food")
	report = state.end_turn()
	check(not report.buildings_supplied, "No food left: tower paused")


func test_bandit_army_grows_with_turns() -> void:
	var raid := RaidData.load_bandits()
	var early := RaidSystem.create_bandit_side(raid, enemies, 6, _seeded_rng(1))
	var late := RaidSystem.create_bandit_side(raid, enemies, 30, _seeded_rng(1))
	check_eq(early.units.size(), 1 + floori(6 * 0.12), "Turn 6 bandit squads")
	check(late.units.size() > early.units.size(), "More bandit squads later")


func test_lost_raid_broken_squads_are_lost() -> void:
	var state := _state()
	state.stockpile.add({&"food": 10, &"wood": 7, &"stone": 3})
	state.army.add_squad(&"archer", 15)
	var bandits := _side([[enemies[&"bandit_thug"], 200]])
	var result := RaidSystem.resolve(state, RaidData.load_bandits(), bandits, 5)
	check(not result.won, "One archer squad cannot stop 200 bandits")
	check_eq(result.resources_lost, {&"food": 3, &"wood": 2}, "30% of each resource, rounded down")
	check_eq(state.army.count_squads(), 0, "The broken archer squad is gone")


func test_retreat_keeps_half_of_unbroken_squads() -> void:
	var state := _state()
	state.stockpile.add({&"food": 10})
	state.army.add_squad(&"swordsman", 20)
	state.army.add_squad(&"archer", 15)
	var kingdom := RaidSystem.create_kingdom_side(state)
	var simulator := BattleSimulator.new(_side([[enemies[&"bandit_thug"], 60]]), kingdom, 11)
	_run_until(simulator, 2.0)
	simulator.retreat(BattleRecord.DEFENDER)
	var expected := []
	for unit in kingdom.units:
		expected.append(roundi(unit.alive() * 0.5))
	var result := RaidSystem.apply_outcome(state, RaidData.load_bandits(), simulator.record)
	check(not result.won, "Retreat is a defeat")
	check_eq(state.army.squads.map(func(s: Army.Squad) -> int: return s.soldiers), expected, "Each squad keeps 50%")
	check_eq(state.stockpile.get_amount(&"food"), 7, "Resources are still lost on retreat")
	check(not result.retreat_losses.is_empty(), "Report lists the soldiers lost while retreating")


func test_won_raid_gives_reward_and_keeps_survivors() -> void:
	var state := _state()
	for i in 3:
		state.army.add_squad(&"swordsman", 20)
	state.army.add_squad(&"archer", 15)
	var bandits := _side([[enemies[&"bandit_thug"], 10], [enemies[&"bandit_archer"], 8]])
	var result := RaidSystem.resolve(state, RaidData.load_bandits(), bandits, 5)
	check(result.won, "Four squads beat two bandit squads")
	check_eq(result.reward, {&"food": 6, &"wood": 6}, "3 food + 3 wood per bandit squad")
	var record: BattleRecord = result.record
	var survivors := 0
	for unit in record.sides[BattleRecord.DEFENDER].units:
		survivors += unit.alive()
	check_eq(state.army.count_soldiers(), survivors, "Army keeps every survivor")
	check(result.scattered.is_empty() and result.retreat_losses.is_empty() and result.resources_lost.is_empty(),
			"Winners lose nothing else")


func test_end_turn_can_trigger_a_raid() -> void:
	var state := _state()
	state.turn = 10
	state.raid = RaidData.load_bandits().duplicate()
	state.raid.base_chance = 1.0
	state.stockpile.add({&"food": 10})
	var report := state.end_turn()
	check(report.has("pending_raid"), "Raid happens when the chance is 100%")
	var simulator: BattleSimulator = report.pending_raid
	check_eq(simulator.record.end_reason, BattleRecord.EndReason.NO_ARMY, "No army: decided before any fighting")
	check_eq(state.stockpile.get_amount(&"food"), 10, "Nothing is lost until finish_raid applies the battle")
	while not simulator.finished:
		simulator.step()
	var result := state.finish_raid(simulator.record)
	check(not result.won, "No army: the raid wins")
	check_eq(state.stockpile.get_amount(&"food"), 7, "Losses applied when the raid is finished")
	state.raid.base_chance = 0.0
	check(not state.end_turn().has("pending_raid"), "No raid at 0%")


func test_playback_speed_pause_skip() -> void:
	var make := func() -> BattlePlayback:
		return BattlePlayback.new(BattleSimulator.new(_side([[unit_list[0], 20]]), _side([[unit_list[1], 20]]), 12))
	var normal: BattlePlayback = make.call()
	var fast: BattlePlayback = make.call()
	fast.speed = 4.0
	normal.advance(1.0)
	fast.advance(1.0)
	check(is_equal_approx(normal.simulator.time, 1.0), "x1: one second of battle per second")
	check(is_equal_approx(fast.simulator.time, 4.0), "x4: four seconds of battle per second")
	normal.paused = true
	normal.advance(5.0)
	check(is_equal_approx(normal.simulator.time, 1.0), "Paused: time stands still")
	normal.paused = false
	var events := normal.advance(3.0)
	check(events.any(func(e: Dictionary) -> bool: return e.type == &"charge"), "Events since the last call are returned")
	check(normal.advance(0.0).is_empty(), "Each event is returned only once")
	normal.skip()
	check(normal.is_finished(), "Skip runs the battle to the end")
	check(normal.advance(1.0).is_empty(), "Skipped events are not replayed")


func test_playback_retreat() -> void:
	var playback := BattlePlayback.new(BattleSimulator.new(_side([[unit_list[0], 20]]), _side([[unit_list[1], 20]]), 13))
	playback.advance(5.0)
	playback.retreat(BattleRecord.DEFENDER)
	check(playback.is_finished(), "Retreat ends the battle")
	check_eq(playback.simulator.record.end_reason, BattleRecord.EndReason.RETREAT, "Recorded as a retreat")


func test_battle_view_closes_lanes_and_steps_figures_forward() -> void:
	var sword := unit_list[0]
	var attacker := _side([[enemies[&"bandit_thug"], 16]])
	var defender := _side([[sword, 20], [sword, 20], [sword, 20]])
	var simulator := BattleSimulator.new(attacker, defender, 1)
	var view := BattleView.new()
	view.size = Vector2(1000, 600)
	view.setup(simulator, BattleRecord.DEFENDER)
	view.update_view(0.0, [])
	var views: Array = view._views[BattleRecord.DEFENDER]
	var lanes_before: Array = views.map(func(v: BattleView.UnitView) -> float: return v.lane_target)
	defender.units[1].broken = true
	view.update_view(0.1, [])
	var top: float = views[0].lane_target
	var bottom: float = views[2].lane_target
	check(top > lanes_before[0] and bottom < lanes_before[2], "Both survivors moved toward the gap")
	# Three lanes sit at 1/6, 3/6, 5/6 of the band; two lanes at 1/4 and 3/4 of it.
	var band: float = (lanes_before[2] - lanes_before[0]) * 1.5
	var band_top: float = lanes_before[0] - band / 6.0
	check(is_equal_approx(top, band_top + band / 4.0) and is_equal_approx(bottom, band_top + band * 0.75),
			"Survivors spread evenly over two lanes")
	for i in 200:
		view.update_view(0.1, [])
	check(is_equal_approx(views[0].lane_y, top), "Lane change finishes")

	# Figures: the front one falls, the rest step forward.
	var unit_view: BattleView.UnitView = views[0]
	var front_slot := unit_view.figures[0].slot
	defender.units[0].soldiers = 20.0 - BattleView.SOLDIERS_PER_FIGURE  # one figure lost
	view.update_view(0.1, [])
	check_eq(unit_view.figures[0].state, BattleView.Figure.State.FLY, "The front figure is knocked out")
	check(unit_view.figures[1].slot.is_equal_approx(front_slot), "The next figure takes the front place")
	for i in 50:
		view.update_view(0.1, [])
	check(unit_view.figures[1].offset.is_equal_approx(front_slot), "It walks there")
	view.free()


func test_battle_report_adds_up_squads_per_unit_type() -> void:
	var sword := _unit(&"sword", UnitData.Row.FRONT, UnitData.AttackKind.MELEE)
	var bow := _unit(&"bow", UnitData.Row.BACK, UnitData.AttackKind.BOW)
	var friend := ClanData.new()
	friend.clan_id = &"friend"
	friend.display_name = "Bạn"
	var side := _side([[sword, 20], [bow, 15], [sword, 10]])
	side.add_unit(sword, 8, null, friend)
	side.units[0].soldiers = 5.0
	side.units[0].kills = 3.0
	side.units[2].broken = true
	side.units[2].kills = 1.5
	var rows := BattleReport.unit_type_rows(side)
	check_eq(rows.size(), 3, "Swords, bows, the friend's lent swords")
	check_eq([rows[0].name, rows[0].squads, rows[0].start, rows[0].alive, rows[0].lost, roundi(rows[0].kills), rows[0].broken],
			["sword", 2, 30, 15, 15, 5, 1], "Two sword squads added up")
	check_eq([rows[1].name, rows[1].squads, rows[1].start], ["bow", 1, 15], "One bow squad")
	check_eq([rows[2].name, rows[2].squads, rows[2].start], ["sword · Bạn", 1, 8], "Lent units stay apart")
