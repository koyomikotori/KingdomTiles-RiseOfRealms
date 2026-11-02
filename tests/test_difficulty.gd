extends "res://tests/test_suite.gd"
## M14h: difficulty (enemy unit size, Legendary unlocked by a win), the kingdom's name and color,
## and the clans' generals and advisors.

const TEST_SETTINGS := "user://test_difficulty_settings.cfg"

var terrains := TerrainLibrary.load_all()


func _state(settings: Dictionary = {}) -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.setup_new_game(settings)
	state.start()
	return state


func test_difficulty_sizes_every_enemy_unit() -> void:
	var normal := _state()
	var hard := _state({"difficulty": Difficulty.Level.HARD})
	var easy := _state({"difficulty": Difficulty.Level.EASY})
	var clan: StringName = normal.wars.fronts.keys()[0]
	var base := normal.diplomacy.clans[clan].data.military_strength
	check_eq(normal.wars.fronts[clan].strength, base, "Normal: the clan's own strength")
	check_eq(hard.wars.fronts[clan].strength, roundi(base * 1.5), "Hard: 150%")
	check_eq(easy.wars.fronts[clan].max_strength, roundi(base * 0.75), "Easy: 75%")
	var unit: UnitData = normal.units[&"swordsman"]
	check_eq(hard.wars.squad_size(unit), roundi(unit.squad_size * 1.5), "Hard squads hold 150%")
	var side := hard.wars.create_clan_side(clan, hard.wars.fronts[clan].strength, hard.units)
	var normal_side := normal.wars.create_clan_side(clan, normal.wars.fronts[clan].strength, normal.units)
	check_eq(side.units.size(), normal_side.units.size(), "As many units as on Normal, each bigger")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var bandits := RaidSystem.create_bandit_side(hard.raid, hard.enemy_units, 10, rng, hard.wars.enemy_scale)
	var first := bandits.units[0]
	check_eq(first.soldiers, roundi(first.data.squad_size * 1.5), "Bandits too")
	check_eq(hard.wars.tier(clan), normal.wars.tier(clan), "The tier ignores the difficulty's scale")


func test_name_color_and_difficulty_are_saved() -> void:
	var color := KingdomState.PLAYER_COLORS[2]
	var state := _state({"difficulty": Difficulty.Level.LEGENDARY, "name": "  Đại Việt  ", "color": color})
	check_eq(state.kingdom_name, "Đại Việt", "Name trimmed")
	check_eq(_state({"name": "   "}).kingdom_name, KingdomState.DEFAULT_KINGDOM_NAME, "Empty name: the default")
	var side := state.create_kingdom_side(&"")
	check_eq(side.display_name, "Đại Việt", "The army fights under the kingdom's name")
	check_eq(side.color.to_html(false), color.to_html(false), "In the chosen color")
	var clan: StringName = state.wars.fronts.keys()[0]
	state.wars.fronts[clan].strength = 900
	state.clan_officers.ensure(clan, state.wars, state.difficulty)
	var copy := _state()
	copy.load_save(JSON.parse_string(JSON.stringify(state.to_save())))
	check_eq(copy.difficulty, Difficulty.Level.LEGENDARY, "Difficulty")
	check_eq(copy.kingdom_name, "Đại Việt", "Name")
	check_eq(copy.player_color, state.player_color, "Color")
	check_eq(copy.wars.enemy_scale, 2.0, "Enemy scale back before the clans' strength")
	check_eq(copy.wars.fronts[clan].max_strength, state.wars.fronts[clan].max_strength, "Same maximum strength")
	check_eq(copy.clan_officers.staff(clan).general.name, state.clan_officers.staff(clan).general.name, "Clan general")
	check_eq(copy.save_summary().difficulty, Difficulty.Level.LEGENDARY, "The save slot shows it")
	var old := state.to_save()
	for key in ["difficulty", "kingdom_name", "player_color", "clan_officers"]:
		old.erase(key)
	copy.load_save(JSON.parse_string(JSON.stringify(old)))
	check_eq(copy.difficulty, Difficulty.Level.NORMAL, "Older saves: Normal")
	check_eq(copy.kingdom_name, KingdomState.DEFAULT_KINGDOM_NAME, "and the default name")


func test_clan_officers_follow_the_clans_strength() -> void:
	var state := _state()
	var wars := state.wars
	var officers := state.clan_officers
	var clan: StringName = wars.fronts.keys()[0]
	for entry: Array in [[100, Wars.Tier.WEAK, 1, 2], [200, Wars.Tier.MEDIUM, 3, 4], [500, Wars.Tier.STRONG, 5, 6]]:
		wars.fronts[clan].strength = entry[0]
		check_eq(wars.tier(clan), entry[1], "Strength %d: tier %d" % [entry[0], entry[1]])
		officers.ensure(clan, wars, state.difficulty)
		var s := officers.staff(clan)
		check(s.general != null and s.advisor != null, "Every clan has a general and an advisor")
		for officer: Officer in [s.general, s.advisor]:
			check(officer.stars >= entry[2] and officer.stars <= entry[3], "%d–%d stars" % [entry[2], entry[3]])
		check(not (s.general.stars == entry[3] and s.advisor.stars == entry[3]), "Only one at the top stars")
	check(officers.staff(clan).general.items.is_empty() and officers.staff(clan).general.trait_id == &"",
			"No items, no trait")
	check(officers.describe(clan, wars, state.difficulty).contains("Mưu sĩ"), "Shown in the clan panel")
	var strong_general := officers.staff(clan).general
	officers.ensure(clan, wars, state.difficulty)
	check(officers.staff(clan).general == strong_general, "Kept while the tier holds")
	wars.fronts[clan].strength = 100
	officers.ensure(clan, wars, state.difficulty)
	check(officers.staff(clan).general.stars <= 2, "A beaten clan's officers are replaced by weak ones")

	var tops := 0
	for i in 60:
		var s := officers.staff(clan)
		s.general = null
		s.advisor = null
		wars.fronts[clan].strength = 500
		officers.ensure(clan, wars, state.difficulty)
		check(s.general.stars + s.advisor.stars <= 11, "Never two 6-star officers")
		tops += 1 if maxi(s.general.stars, s.advisor.stars) == 6 else 0
	check(tops > 10, "Strong clans often have one 6-star officer (%d/60)" % tops)

	var legendary := _state({"difficulty": Difficulty.Level.LEGENDARY})
	var other: StringName = legendary.wars.fronts.keys()[0]
	legendary.wars.fronts[other].strength = roundi(200 * legendary.wars.enemy_scale)
	legendary.clan_officers.ensure(other, legendary.wars, legendary.difficulty)
	var stars := legendary.clan_officers.staff(other).general.stars
	check(stars >= 4 and stars <= 5, "Legendary medium: +1 star")
	legendary.wars.fronts[other].strength = roundi(500 * legendary.wars.enemy_scale)
	legendary.clan_officers.ensure(other, legendary.wars, legendary.difficulty)
	stars = legendary.clan_officers.staff(other).general.stars
	check(stars >= 5 and stars <= 6, "Legendary strong: still 5–6")


func test_clan_officers_lead_and_may_fall() -> void:
	var state := _state()
	var clan: StringName = state.wars.fronts.keys()[0]
	state.wars.fronts[clan].strength = 500
	var side := state.wars.create_clan_side(clan, 500, state.units)
	var squads := side.units.size()
	state.clan_officers.lead(side, clan, state.wars, state.difficulty)
	var general := state.clan_officers.staff(clan).general
	check_eq(side.units.size(), squads + 1, "The general's bodyguard joins")
	check(side.units.back().is_general_guard, "As the guard")
	check_eq(side.general_name, general.name, "Named on the side")
	check_eq(side.advisor_name, state.clan_officers.staff(clan).advisor.name, "The advisor follows")
	check(not side.stratagems.is_empty(), "With stratagems")
	var deaths := 0
	var wounds := 0
	for i in 200:
		var s := state.clan_officers.staff(clan)
		s.general = general
		s.general.wounded_turns = 0
		s.vacancy = 0
		var record := BattleSimulator.simulate(state.create_kingdom_side(clan, false), side, i)
		record.sides[BattleRecord.DEFENDER].general_fallen = true
		var fate: StringName = state.clan_officers.after_battle(record, BattleRecord.DEFENDER, clan).general.fate
		deaths += 1 if fate == &"dead" else 0
		wounds += 1 if fate == &"wounded" else 0
	check_eq(deaths + wounds, 200, "A fallen general dies or is wounded")
	check(deaths > 30 and deaths < 90, "About 30%% die (%d)" % deaths)
	var s := state.clan_officers.staff(clan)
	s.general = null
	s.vacancy = ClanOfficers.VACANCY_TURNS
	state.clan_officers.ensure(clan, state.wars, state.difficulty)
	check(s.general == null, "No new general right away")
	for i in ClanOfficers.VACANCY_TURNS:
		state.clan_officers.end_turn(state.wars)
	state.clan_officers.ensure(clan, state.wars, state.difficulty)
	check(s.general != null, "A new one after the vacancy")
	s.general.wounded_turns = 2
	check(state.clan_officers.fielded_general(clan, state.wars, state.difficulty) == null, "Wounded ones stay home")


func test_legendary_opens_after_a_win_on_normal_or_hard() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	GameSettings.use_file(TEST_SETTINGS)
	check(not GameSettings.legendary_unlocked(), "Locked at first")
	check(not Difficulty.unlocks_legendary(Difficulty.Level.EASY), "Not by an easy win")
	check(Difficulty.unlocks_legendary(Difficulty.Level.NORMAL) and Difficulty.unlocks_legendary(Difficulty.Level.HARD),
			"By a Normal or Hard win")
	GameSettings.unlock_legendary()
	GameSettings.use_file(TEST_SETTINGS)
	check(GameSettings.legendary_unlocked(), "Remembered")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS))
	GameSettings.use_file(GameSettings.PATH)
