extends "res://tests/test_suite.gd"
## M16e: events with battles and lasting morale changes (MoraleEffects, EventBattles: duel,
## breakout, surprise attack, rescue; warned invasions).

const CLAN := &"north_wolves"

var terrains := TerrainLibrary.load_all()


func _state(squads: int = 6) -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.start()
	state.turn = 12
	state.stockpile.add({&"food": 500, &"wood": 500, &"stone": 500, &"ore": 500, &"hardwood": 500, &"horses": 500})
	for i in squads:
		state.army.add_squad(&"swordsman", state.units[&"swordsman"].squad_size)
	return state


## At war with CLAN, strong enough to field a general.
func _war(state: KingdomState) -> void:
	state.wars.declare_war(CLAN)
	state.wars.fronts[CLAN].strength = 600
	state.clan_officers.ensure(CLAN, state.wars, state.difficulty)


func _commander(state: KingdomState, stars: int = 3) -> General:
	var general := state.generals.generate(stars)
	state.generals.add(general)
	state.generals.set_commander(general)
	return general


func _rng(seed_value: int = 1) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## An RNG whose first randf() satisfies `predicate`.
func _rng_where(predicate: Callable) -> RandomNumberGenerator:
	for seed_value in 10000:
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_value
		if predicate.call(probe.randf()):
			return _rng(seed_value)
	return RandomNumberGenerator.new()


func _resolve(state: KingdomState, event_id: StringName, index: int, clan_id: StringName = &"",
		rng: RandomNumberGenerator = _rng()) -> Dictionary:
	state.events.pending = [{"event_id": event_id, "clan_id": clan_id}] as Array[Dictionary]
	return state.events.resolve(state, rng, index)


func _can(state: KingdomState, event_id: StringName) -> bool:
	return state.events.can_happen(state, state.events.events[event_id])


## Runs the pending event battle with `winner` forced, and returns EventBattles.finish's result.
func _fight(state: KingdomState, winner: int) -> Dictionary:
	var battle := state.events.pending_battle
	var simulator := EventBattles.start(state, battle, _rng())
	check(simulator != null, "%s can be fought" % battle.kind)
	while not simulator.finished:
		simulator.step()
	simulator.record.winner = winner
	return EventBattles.finish(state, battle, simulator.record)


## Starting morale of the defending clan's first own unit.
func _defender_morale(simulator: BattleSimulator) -> float:
	for unit in simulator.record.sides[BattleRecord.DEFENDER].units:
		if unit.ally == null and not unit.is_general_guard:
			return unit.morale
	return 0.0


func test_events_load() -> void:
	var events := EventData.load_all()
	for id: StringName in [&"enemy_duel", &"general_ambushed", &"enemy_leak", &"official_kidnapped",
			&"stolen_letter", &"agent_warning"]:
		check(events.has(id), "%s loaded" % id)


# --- MoraleEffects ----------------------------------------------------------------------------

func test_morale_effects_once_and_timed() -> void:
	var effects := MoraleEffects.new()
	effects.add(MoraleEffects.ENEMY, -2, CLAN)
	effects.add(MoraleEffects.KINGDOM, -1, &"", 2)
	check_eq(effects.total(MoraleEffects.ENEMY, CLAN), -2, "Against the clan")
	check_eq(effects.total(MoraleEffects.ENEMY, &"other"), 0, "Not against another clan")
	check_eq(effects.total(MoraleEffects.KINGDOM, &""), -1, "Any battle, bandits too")
	effects.after_battle(&"other")
	check_eq(effects.total(MoraleEffects.ENEMY, CLAN), -2, "Another battle does not use it")
	effects.after_battle(CLAN)
	check_eq(effects.total(MoraleEffects.ENEMY, CLAN), 0, "Used up by the battle with the clan")
	check_eq(effects.total(MoraleEffects.KINGDOM, CLAN), -1, "Timed ones stay")
	effects.end_turn()
	check_eq(effects.entries.size(), 1, "One turn left")
	effects.end_turn()
	check(effects.entries.is_empty(), "Expired")


func test_morale_effects_apply_and_floor() -> void:
	var state := _state()
	var effects := MoraleEffects.new()
	effects.add(MoraleEffects.KINGDOM, -100, CLAN)
	effects.add(MoraleEffects.ENEMY, 3, CLAN)
	var ours := RaidSystem.create_kingdom_side(state)
	var theirs := RaidSystem.create_kingdom_side(state)
	var base: float = theirs.units[0].morale
	effects.apply(ours, theirs, CLAN)
	check_eq(ours.units[0].morale, MoraleEffects.MIN_MORALE, "Never below the floor")
	check_eq(theirs.units[0].morale, base + 3, "Raised")


func test_morale_effects_saved() -> void:
	var state := _state()
	state.morale_effects.add(MoraleEffects.ENEMY, 2, CLAN)
	state.morale_effects.add(MoraleEffects.KINGDOM, -1, &"", 5)
	state.events.invasion_forced = CLAN
	var copy := _state(0)
	copy.load_save(JSON.parse_string(JSON.stringify(state.to_save())))
	check_eq(copy.morale_effects.entries, state.morale_effects.entries, "Effects kept")
	check_eq(copy.events.invasion_forced, CLAN, "Warned invasion kept")
	var old := state.to_save()
	old.erase("morale_effects")
	var older := _state(0)
	older.load_save(JSON.parse_string(JSON.stringify(old)))
	check(older.morale_effects.entries.is_empty(), "Older saves: none")


func test_attack_uses_and_spends_morale_effects() -> void:
	var state := _state()
	_war(state)
	var plain := _defender_morale(state.create_attack(CLAN, 600))
	state.morale_effects.add(MoraleEffects.ENEMY, -2, CLAN)
	var simulator := state.start_attack(CLAN)
	check_eq(_defender_morale(simulator), maxf(1.0, plain - 2), "Enemy starts 2 lower")
	while not simulator.finished:
		simulator.step()
	state.finish_attack(CLAN, simulator.record)
	check(state.morale_effects.entries.is_empty(), "Used up")


# --- Duel -------------------------------------------------------------------------------------

func test_duel_conditions() -> void:
	var state := _state()
	check(not _can(state, &"enemy_duel"), "No war")
	_war(state)
	check(not _can(state, &"enemy_duel"), "No commander")
	_commander(state)
	check(_can(state, &"enemy_duel"), "At war, a commander, a rival general")


func test_duel_sides_are_two_generals() -> void:
	var state := _state()
	_war(state)
	_commander(state)
	var result := _resolve(state, &"enemy_duel", 0, CLAN)
	check_eq(result.get("battle"), EventBattles.DUEL, "A duel follows")
	var simulator := EventBattles.start(state, state.events.pending_battle, _rng())
	for side in simulator.record.sides:
		check_eq(side.units.size(), 1, "One fighter")
		check_eq(side.units[0].start_soldiers, Generals.DUEL_SOLDIERS, "The general and their guard as one pool")
		check(side.units[0].is_general_guard, "The general")
	BattleSimulator.simulate(simulator.record.sides[0], simulator.record.sides[1], 3)


func test_duel_won_kills_the_rival() -> void:
	var state := _state()
	_war(state)
	var commander := _commander(state)
	_resolve(state, &"enemy_duel", 0, CLAN)
	var result := _fight(state, BattleRecord.DEFENDER)
	check(result.won, "Won")
	check(state.clan_officers.staff(CLAN).general == null, "Rival dead")
	check_eq(state.morale_effects.total(MoraleEffects.ENEMY, CLAN), -EventBattles.DUEL_MORALE, "Enemy disheartened")
	check(state.generals.generals.has(commander), "Commander alive")


func test_duel_lost_kills_the_commander() -> void:
	var state := _state()
	_war(state)
	var commander := _commander(state)
	_resolve(state, &"enemy_duel", 0, CLAN)
	var result := _fight(state, BattleRecord.ATTACKER)
	check(not result.won, "Lost")
	check(not state.generals.generals.has(commander), "Commander dead")
	check_eq(result.general.fate, &"dead", "Reported dead")
	check_eq(state.morale_effects.total(MoraleEffects.KINGDOM, CLAN), -EventBattles.DUEL_MORALE, "Army disheartened")


func test_duel_refused() -> void:
	var state := _state()
	_war(state)
	_commander(state)
	var result := _resolve(state, &"enemy_duel", 1, CLAN)
	check(not result.has("battle"), "No battle")
	check_eq(state.morale_effects.total(MoraleEffects.KINGDOM, &""), -1, "Army −1 everywhere")
	check_eq(state.morale_effects.entries[0].turns, 5, "For 5 turns")


# --- Ambush -----------------------------------------------------------------------------------

func test_ambush_ignored_kills_the_commander() -> void:
	var state := _state()
	_war(state)
	var commander := _commander(state)
	_resolve(state, &"general_ambushed", 0, CLAN)
	check(not state.generals.generals.has(commander), "Commander dead")
	check_eq(state.army.count_squads(), 6, "No soldier lost")


func test_breakout_takes_a_detachment() -> void:
	var state := _state()
	_war(state)
	_commander(state)
	_resolve(state, &"general_ambushed", 1, CLAN)
	var simulator := EventBattles.start(state, state.events.pending_battle, _rng())
	var squads: Array = state.events.pending_battle.squads
	check(squads.size() >= EventBattles.DETACHMENT_MIN and squads.size() <= EventBattles.DETACHMENT_MAX, "3–5 squads")
	var kingdom: BattleSide = simulator.record.sides[BattleRecord.DEFENDER]
	check_eq(kingdom.units.size(), squads.size() + 1, "Detachment and the bodyguard")


func test_breakout_lost_loses_the_detachment() -> void:
	var state := _state()
	_war(state)
	var commander := _commander(state)
	_resolve(state, &"general_ambushed", 1, CLAN)
	var result := _fight(state, BattleRecord.ATTACKER)
	var squads: Array = state.events.pending_battle.squads
	check(not result.won, "Lost")
	check_eq(state.army.count_squads(), 6 - squads.size(), "The detachment is gone")
	check(result.general.fate in [&"dead", &"wounded"], "The commander fell")
	check(not state.generals.generals.has(commander) or commander.wounded_turns > 0, "Dead or wounded")


func test_breakout_won_keeps_the_commander() -> void:
	var state := _state()
	_war(state)
	_commander(state)
	_resolve(state, &"general_ambushed", 1, CLAN)
	var result := _fight(state, BattleRecord.DEFENDER)
	check(result.won, "Won")
	check(result.general.fate in [&"none", &"dead", &"wounded"], "Usual battle rules")


# --- Leaked news --------------------------------------------------------------------------------

func test_leak_success_attacks_half_the_clan() -> void:
	var state := _state()
	_war(state)
	_commander(state)
	var result := _resolve(state, &"enemy_leak", 0, CLAN, _rng_where(func(value: float) -> bool: return value < 0.1))
	check_eq(result.get("battle"), EventBattles.SURPRISE, "A surprise attack follows")
	var simulator := EventBattles.start(state, state.events.pending_battle, _rng())
	var defender: BattleSide = simulator.record.sides[BattleRecord.DEFENDER]
	var own := defender.units.filter(func(unit: BattleSide.Unit) -> bool: return unit.ally == null and not unit.is_general_guard)
	var soldiers := 0
	for unit: BattleSide.Unit in own:
		soldiers += unit.start_soldiers
	check(soldiers <= roundi(600 * EventBattles.SURPRISE_SHARE) + own.size(), "About half the clan")
	var plain := _defender_morale(state.create_attack(CLAN, 300))
	check_eq(_defender_morale(simulator), maxf(1.0, plain + EventBattles.SURPRISE_MORALE), "Caught out: lower morale")
	while not simulator.finished:
		simulator.step()
	var outcome := EventBattles.finish(state, state.events.pending_battle, simulator.record)
	check(outcome.has("loot") and outcome.has("annexed"), "Settled as an attack")


func test_leak_trap() -> void:
	var state := _state()
	_war(state)
	var commander := _commander(state)
	var before := state.army.count_soldiers()
	var result := _resolve(state, &"enemy_leak", 0, CLAN, _rng_where(func(value: float) -> bool: return value > 0.95))
	check(not result.has("battle"), "No battle")
	check(commander.wounded_turns > 0, "Commander wounded")
	check(state.army.count_soldiers() < before, "Soldiers lost")


# --- Kidnapped official -----------------------------------------------------------------------

func test_rescue() -> void:
	var state := _state()
	_commander(state)
	_resolve(state, &"official_kidnapped", 0)
	var simulator := EventBattles.start(state, state.events.pending_battle, _rng())
	check_eq(simulator.record.sides[BattleRecord.DEFENDER].display_name, "Quân cướp", "Against bandits")
	var food := state.stockpile.get_amount(&"food")
	var result := _fight(state, BattleRecord.ATTACKER)
	check(result.won, "Won")
	check_eq(state.stockpile.get_amount(&"food"), food + EventBattles.RESCUE_REWARD[&"food"], "Reward paid")
	_resolve(state, &"official_kidnapped", 0)
	var lost := _fight(state, BattleRecord.DEFENDER)
	check(not lost.won, "Lost")


func test_ransom_and_abandon() -> void:
	var state := _state()
	var food := state.stockpile.get_amount(&"food")
	_resolve(state, &"official_kidnapped", 1)
	check_eq(state.stockpile.get_amount(&"food"), food - 100, "Ransom paid")
	var relation := state.diplomacy.clans[CLAN].relation
	_resolve(state, &"official_kidnapped", 2)
	check_eq(state.diplomacy.clans[CLAN].relation, relation - 8, "Every clan thinks less of us")


func test_rescue_needs_squads_at_home() -> void:
	var state := _state(0)
	var choice: EventChoiceData = state.events.events[&"official_kidnapped"].choices[0]
	check(not state.events.can_choose(state, choice), "No squads: cannot rescue")


# --- Stolen letter and the agent's warning ----------------------------------------------------

func test_stolen_letter_ignored() -> void:
	var state := _state()
	_war(state)
	_resolve(state, &"stolen_letter", 1, CLAN, _rng(2))
	var total := state.morale_effects.total(MoraleEffects.ENEMY, CLAN)
	check(total == 2 or total == 0, "Enemy +2 next battle (or the letter is lost)")
	var raised := 0
	for seed_value in 40:
		var other := _state(0)
		_war(other)
		_resolve(other, &"stolen_letter", 1, CLAN, _rng(seed_value))
		raised += 1 if other.morale_effects.total(MoraleEffects.ENEMY, CLAN) == 2 else 0
	check(raised > 20, "Mostly the enemy knows (%d/40)" % raised)


func test_agent_warning_brings_the_invasion() -> void:
	var state := _state()
	_war(state)
	var agent := state.agents.generate(2)
	state.agents.agents.append(agent)
	check_eq(state.start_agent_mission(agent, Agent.RELATIONS, CLAN), Agents.Result.OK, "Agent sent")
	check(_can(state, &"agent_warning"), "May happen")
	for seed_value in 100:
		state.events.invasion_forced = &""
		state.morale_effects.entries.clear()
		_resolve(state, &"agent_warning", 0, CLAN, _rng(seed_value))
		if state.events.invasion_forced == CLAN:
			break
	check_eq(state.events.invasion_forced, CLAN, "The clan will come")
	check_eq(state.morale_effects.total(MoraleEffects.KINGDOM, CLAN), 3, "Army ready: +3")
	state.events.pending.clear()
	var report := state.end_turn()
	check(report.has("pending_invasion"), "Invasion at the next turn")
	check_eq(report.pending_invasion.clan_id, CLAN, "From the warned clan")
	check_eq(state.events.invasion_forced, &"", "Warning used")


func test_one_battle_event_a_turn() -> void:
	var state := _state()
	_war(state)
	_commander(state)
	state.events.raid_won_turn = state.turn
	var battle_ids := state.events.events.keys().filter(
			func(id: StringName) -> bool: return EventSystem.uses_battle(state.events.events[id]))
	check(battle_ids.size() >= 4, "Several commander / battle events")
	var possible := battle_ids.filter(func(id: StringName) -> bool: return _can(state, id))
	check(possible.size() >= 2, "At least two of them can happen now")
	for seed_value in 300:
		state.events.pending.clear()
		state.events.last_turn.clear()
		state.events.roll(state, _rng(seed_value))
		var count := state.events.pending.filter(func(entry: Dictionary) -> bool: return entry.event_id in battle_ids).size()
		if count > 1:
			check(false, "Two battle events rolled with seed %d" % seed_value)
			return
	check(true, "Never two battle events in one turn")


func test_stale_battle_event_dropped() -> void:
	var state := _state()
	_war(state)
	_commander(state)
	state.events.last_turn[&"enemy_duel"] = state.turn
	state.events.pending = [{"event_id": &"general_ambushed", "clan_id": CLAN},
			{"event_id": &"enemy_duel", "clan_id": CLAN},
			{"event_id": &"stolen_letter", "clan_id": CLAN}] as Array[Dictionary]
	state.events.drop_stale(state)
	check_eq(state.events.pending.size(), 3, "Nothing dropped while the conditions hold")
	state.events.resolve(state, _rng(), 0)  # Ignore the ambush: the commander dies.
	state.events.drop_stale(state)
	check_eq(state.events.pending.size(), 1, "The duel is dropped")
	check_eq(state.events.pending[0].event_id, &"stolen_letter", "Other events stay")
	check(not state.events.last_turn.has(&"enemy_duel"), "The dropped duel may come again")


func test_duel_dropped_when_the_rival_is_gone() -> void:
	var state := _state()
	_war(state)
	_commander(state)
	state.events.pending = [{"event_id": &"enemy_duel", "clan_id": CLAN}] as Array[Dictionary]
	state.clan_officers.assassinate(CLAN, &"general", true)
	state.events.drop_stale(state)
	check(state.events.pending.is_empty(), "No duel without a rival general")


# --- Bandit leader, raid pressure and the bandit challenge -----------------------------------

func test_bandit_leader_grows_with_the_turns() -> void:
	var state := _state()
	check_eq(ClanOfficers.bandit_stars(19), Vector2i.ZERO, "No leader before turn 20")
	check_eq(ClanOfficers.bandit_stars(20), Vector2i(1, 2), "Weak from turn 20")
	check_eq(ClanOfficers.bandit_stars(45), Vector2i(3, 4), "Medium from turn 40")
	check_eq(ClanOfficers.bandit_stars(80), Vector2i(5, 6), "Strong from turn 60")
	check(state.clan_officers.bandit_leader(19) == null, "Nobody yet")
	var weak := state.clan_officers.bandit_leader(25)
	check(weak != null and weak.stars <= 2, "A weak leader")
	check(state.clan_officers.bandit_leader(30) == weak, "The same leader")
	var strong := state.clan_officers.bandit_leader(60)
	check(strong != weak and strong.stars >= 5, "Replaced by a strong one")
	state.clan_officers.assassinate(ClanOfficers.BANDITS, &"general", true)
	check(state.clan_officers.bandit_leader(60) == null, "Killed: a vacancy")
	for i in ClanOfficers.VACANCY_TURNS:
		state.clan_officers.end_turn(state.wars)
	check(state.clan_officers.bandit_leader(60) != null, "A new leader after the vacancy")


func test_raids_are_led_by_the_bandit_leader() -> void:
	var state := _state()
	state.turn = 30
	state.events.raid_forced = true
	state.morale_effects.add(MoraleEffects.ENEMY, -2, ClanOfficers.BANDITS)
	var report := state.end_turn()
	check(report.has("pending_raid"), "A raid")
	var simulator: BattleSimulator = report.pending_raid
	var bandits := simulator.record.sides[BattleRecord.ATTACKER]
	var leader := state.clan_officers.staff(ClanOfficers.BANDITS).general
	check(leader != null and bandits.general_name == leader.name, "Led by the leader")
	while not simulator.finished:
		simulator.step()
	var result := state.finish_raid(simulator.record)
	check(result.has("enemy_officers"), "The leader's fate is reported")
	check_eq(state.morale_effects.total(MoraleEffects.ENEMY, ClanOfficers.BANDITS), 0, "Once: used by the raid")


func test_bandit_morale_only_against_bandits() -> void:
	var effects := MoraleEffects.new()
	effects.add(MoraleEffects.KINGDOM, -2, ClanOfficers.BANDITS)
	check_eq(effects.total(MoraleEffects.KINGDOM, ClanOfficers.BANDITS), -2, "Against bandits")
	check_eq(effects.total(MoraleEffects.KINGDOM, CLAN), 0, "Not against a clan")
	effects.after_battle(CLAN)
	check_eq(effects.entries.size(), 1, "A clan battle does not use it")


func test_raid_pressure() -> void:
	var state := _state()
	state.turn = 30
	var base := RaidSystem.get_raid_chance(state, state.raid)
	state.raid_pressure.add(2.0, 2)
	check(is_equal_approx(RaidSystem.get_raid_chance(state, state.raid), minf(base * 2.0, maxf(base, RaidPressure.MAX_CHANCE))),
			"Twice as likely")
	state.raid_pressure.add(0.5, 4)
	check(is_equal_approx(RaidSystem.get_raid_chance(state, state.raid), base), "x2 and x0.5")
	var saved := state.raid_pressure.to_save()
	state.raid_pressure.end_turn()
	state.raid_pressure.end_turn()
	check_eq(state.raid_pressure.entries.size(), 1, "The 2-turn entry ran out")
	check(is_equal_approx(state.raid_pressure.factor(), 0.5), "Only x0.5 left")
	var loaded := RaidPressure.new()
	loaded.load_save(saved)
	check(is_equal_approx(loaded.factor(), 1.0) and loaded.entries.size() == 2, "Saved")


func test_bandit_challenge_conditions() -> void:
	var state := _state()
	state.turn = 25
	_commander(state)
	state.events.last_turn.clear()
	check(_can(state, &"bandit_challenge"), "A leader and a general at home")
	state.turn = 15
	check(not _can(state, &"bandit_challenge"), "No leader before turn 20")
	check(EventSystem.uses_battle(state.events.events[&"bandit_challenge"]), "One battle event a turn")


func test_bandit_challenge_with_a_picked_general_won() -> void:
	var state := _state()
	state.turn = 25
	var commander := _commander(state)
	var picked := state.generals.generate(2)
	state.generals.add(picked)
	state.events.pending = [{"event_id": &"bandit_challenge", "clan_id": &""}] as Array[Dictionary]
	var result := state.events.resolve(state, _rng(), 0, picked)
	check_eq(result.get("battle"), EventBattles.BANDIT_DUEL, "A duel follows")
	check(state.events.pending_battle.general == picked, "The picked general, not the commander")
	var simulator := EventBattles.start(state, state.events.pending_battle, _rng())
	check_eq(simulator.record.sides[BattleRecord.DEFENDER].general_name, picked.name, "The picked general fights")
	var fight := _fight(state, BattleRecord.DEFENDER)
	check(fight.won, "Won")
	check(state.clan_officers.bandit_leader(state.turn) == null, "The leader is dead")
	check_eq(state.morale_effects.total(MoraleEffects.ENEMY, ClanOfficers.BANDITS), -EventBattles.DUEL_MORALE,
			"Bandits disheartened")
	check(is_equal_approx(state.raid_pressure.factor(), EventBattles.BANDIT_WIN_RAID_FACTOR), "Fewer raids")
	for i in EventBattles.BANDIT_WIN_TURNS:
		state.morale_effects.after_battle(ClanOfficers.BANDITS)
	check_eq(state.morale_effects.total(MoraleEffects.ENEMY, ClanOfficers.BANDITS), -EventBattles.DUEL_MORALE,
			"Every raid of the next turns")
	check(state.generals.generals.has(commander) and state.generals.generals.has(picked), "Both alive")


func test_bandit_challenge_lost() -> void:
	var state := _state()
	state.turn = 25
	var picked := _commander(state)
	state.events.pending = [{"event_id": &"bandit_challenge", "clan_id": &""}] as Array[Dictionary]
	state.events.resolve(state, _rng(), 0)
	var fight := _fight(state, BattleRecord.ATTACKER)
	check(not fight.won, "Lost")
	check(not state.generals.generals.has(picked), "The general is dead")
	check_eq(fight.general.title, "Tướng", "Reported as a general")
	check_eq(state.morale_effects.total(MoraleEffects.KINGDOM, ClanOfficers.BANDITS), -EventBattles.DUEL_MORALE,
			"Next bandit battle")
	check_eq(state.morale_effects.total(MoraleEffects.KINGDOM, CLAN), 0, "Not against clans")


func test_bandit_challenge_refused() -> void:
	var state := _state()
	state.turn = 25
	_commander(state)
	var result := _resolve(state, &"bandit_challenge", 1)
	check(not result.has("battle"), "No battle")
	check_eq(state.morale_effects.total(MoraleEffects.KINGDOM, CLAN), -1, "−1 in every battle")
	check(is_equal_approx(state.raid_pressure.factor(), 2.0), "Twice the raids")
	check_eq(state.raid_pressure.entries[0].turns, 5, "For 5 turns")


func test_pick_general_needs_one_ready() -> void:
	var state := _state()
	state.turn = 25
	var choice: EventChoiceData = state.events.events[&"bandit_challenge"].choices[0]
	check(not state.events.can_choose(state, choice), "Nobody to send")
	var general := _commander(state)
	check(state.events.can_choose(state, choice), "A general")
	general.wounded_turns = 2
	check(not state.events.can_choose(state, choice), "Wounded generals cannot fight")
