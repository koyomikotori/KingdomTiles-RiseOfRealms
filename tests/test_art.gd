extends "res://tests/test_suite.gd"
## M12a: every piece of content has its generated art (GDD §13, tools/art/generate.py).


func test_every_terrain_has_a_tile() -> void:
	for terrain_id in TerrainLibrary.load_all():
		var texture := GameArt.terrain(terrain_id)
		check(texture != null, "Tile for %s" % terrain_id)
		if texture != null:
			check_eq(texture.get_size(), Vector2(24, 24), "%s is 24×24 (M13c)" % terrain_id)
	check(GameArt.terrain(&"") != null, "Wild land outside the kingdom")
	check(GameArt.key_marker() != null, "Key cell marker")
	check(GameArt.key_frame() != null, "Key cell frame (drawn over buildings)")


func test_every_building_has_a_picture() -> void:
	for building_id in BuildingData.load_all():
		check(GameArt.building(building_id) != null, "Picture for %s" % building_id)
	for level in range(1, 7):
		var castle := GameArt.castle(level)
		check(castle != null and castle.get_size() == Vector2(32, 32), "Castle level %d is 32×32" % level)
		check(GameArt.level_badge(level) != null, "Level badge %d" % level)
	check(GameArt.castle(9) == GameArt.castle(6), "Levels past the art use the top castle")


func test_every_resource_has_an_icon() -> void:
	for type in ResourceTypeData.load_all():
		var icon := GameArt.icon(type.resource_id)
		check(icon != null, "Icon for %s" % type.resource_id)
		if icon != null:
			check_eq(icon.get_size(), Vector2(24, 24), "%s icon is 24×24" % type.resource_id)


func test_missing_art_is_null_not_an_error() -> void:
	check(GameArt.building(&"no_such_building") == null, "Unknown ids fall back to flat colors")


func test_project_theme_is_wood_and_paper() -> void:
	var path: String = ProjectSettings.get_setting("gui/theme/custom", "")
	check_eq(path, "res://assets/ui/theme.tres", "Project theme set")
	var theme: Theme = load(path)
	check(theme != null, "Theme loads")
	if theme == null:
		return
	check(theme.get_stylebox("panel", "PanelContainer") is StyleBoxTexture, "Paper panels")
	check(theme.get_stylebox("normal", "Button") is StyleBoxTexture, "Wooden buttons")
	check(theme.get_stylebox("panel", "WoodPanel") is StyleBoxTexture, "Wooden bars")
	check_eq(theme.get_color("font_color", "Label"), UiPalette.TEXT, "Ink on paper")
	check_eq(theme.get_color("font_color", "WoodLabel"), UiPalette.ON_WOOD, "Cream on wood")


func test_ink_keeps_dark_colors_and_darkens_light_ones() -> void:
	check_eq(UiPalette.ink(UiPalette.TEXT), UiPalette.TEXT, "Already dark")
	var light := Color(0.75, 0.8, 0.9)
	check(UiPalette.ink(light).get_luminance() < light.get_luminance() - 0.2, "Light clan colors get darker")


# --- Battle (M12b) ------------------------------------------------------------------------

func test_every_unit_has_a_battle_sprite_sheet() -> void:
	var all_units: Array[UnitData] = []
	all_units.append_array(UnitData.load_all())
	all_units.append_array(UnitData.load_enemies().values())
	all_units.append(Generals.new().guard_unit)
	for unit in all_units:
		var id := unit.get_sprite_id()
		var sheet := GameArt.unit_sheet(id)
		var team := GameArt.unit_sheet(id, "_team")
		check(ResourceLoader.exists(GameArt.UNIT_DIR + String(id) + ".png"), "Own sheet for %s" % id)
		check(sheet != null and team != null and sheet.get_size() == team.get_size(), "%s: sheet + team layer" % id)
		if sheet != null:
			var frame := GameArt.unit_frame(sheet, &"cheer", 1)
			check_eq(sheet.get_size(), frame.size * Vector2(GameArt.UNIT_FRAMES, GameArt.UNIT_STATES.size()),
					"%s: 2 frames × 5 states" % id)
	check(GameArt.unit_sheet(&"no_such_unit") == GameArt.unit_sheet(&"swordsman"), "Unknown sprites use the swordsman")


func test_battlefield_and_effects_exist() -> void:
	for piece: StringName in [&"mountains", &"cloud", &"ground", &"town", &"camp", &"camp_team"]:
		check(GameArt.battle(piece) != null, "Battlefield piece %s" % piece)
	check(GameArt.effect(&"arrow") != null, "Arrow")
	for stratagem: StratagemData in StratagemData.load_all().values():
		if stratagem.effect != &"arrows":
			check(GameArt.effect(stratagem.effect) != null, "%s: effect %s" % [stratagem.stratagem_id, stratagem.effect])


func test_sides_wear_their_colors() -> void:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), TerrainLibrary.load_all(), 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), TerrainLibrary.load_all(),
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.start()
	check_eq(state.create_kingdom_side(&"").color, KingdomState.PLAYER_COLOR, "The kingdom wears the player's color")
	var bandits := RaidSystem.create_bandit_side(state.raid, state.enemy_units, 10, state.rng)
	check_eq(bandits.color, RaidSystem.BANDIT_COLOR, "Bandits wear brown")
	var clan := state.wars.create_clan_side(&"north_wolves", 30, state.units)
	check_eq(clan.color, state.diplomacy.clans[&"north_wolves"].data.color, "A clan wears its banner color")


func test_commander_and_strategist_have_their_own_sprites() -> void:
	for kind: StringName in [BattleView.GENERAL_KIND, BattleView.ADVISOR_KIND]:
		for gender: StringName in OfficerLook.GENDERS:
			var look := OfficerLook.new()
			look.gender = gender
			for stars in range(1, 7):
				var id := GameArt.officer_sprite(kind, look, &"", stars)
				check_eq(id, StringName("%s_%s_t%d" % [kind, gender, GameArt.officer_tier(stars)]),
						"Sprite id by gender and tier")
				for layer in GameArt.LAYERS:
					check(ResourceLoader.exists(GameArt.UNIT_DIR + String(id) + layer + ".png"), "%s%s" % [id, layer])
	var general_id := GameArt.officer_sprite(BattleView.GENERAL_KIND, null)
	var general := GameArt.unit_sheet(general_id)
	var soldier := GameArt.unit_sheet(&"swordsman")
	check(GameArt.unit_frame(general, &"stand", 0, GameArt.frames_of(general_id)).size.y
			> GameArt.unit_frame(soldier, &"stand", 0).size.y, "The commander is bigger than a soldier")


func test_officer_tiers_and_frames() -> void:
	check_eq([1, 2, 3, 4, 5, 6].map(GameArt.officer_tier), [1, 1, 2, 2, 3, 3], "Tiers by stars")
	var look := OfficerLook.new()
	for stars in [1, 3, 5]:
		for kind: StringName in [BattleView.GENERAL_KIND, BattleView.ADVISOR_KIND]:
			var id := GameArt.officer_sprite(kind, look, &"", stars)
			var sheet := GameArt.unit_sheet(id)
			check_eq(GameArt.frames_of(id), GameArt.OFFICER_FRAMES, "%s has 4 frames" % id)
			check(sheet != null, "%s sheet loads" % id)
			if sheet != null:
				var frame := GameArt.unit_frame(sheet, &"cheer", 3, GameArt.OFFICER_FRAMES)
				check_eq(sheet.get_size(), frame.size * Vector2(GameArt.OFFICER_FRAMES, GameArt.UNIT_STATES.size()),
						"%s: 4 frames × 5 states" % id)
	check_eq(GameArt.frames_of(&"general_guard"), GameArt.UNIT_FRAMES, "The bodyguard is a 2-frame unit sheet")
	check_eq(GameArt.frames_of(&"general_duelist"), GameArt.UNIT_FRAMES, "So is the duelist")
	var officer := GameArt.officer_sprite(BattleView.GENERAL_KIND, look)
	check_eq([0.0, 0.5, 1.0, 1.5, 2.0].map(func(beat: float) -> int: return GameArt.anim_frame(officer, beat)),
			[0, 1, 2, 3, 0], "Officers play 4 frames in a soldier's 2-frame loop")
	check_eq(GameArt.anim_frame(&"swordsman", 1.5), 1, "Soldiers keep 2 frames")


func test_duel_events_come_more_often() -> void:
	for id in ["bandit_challenge", "enemy_duel"]:
		var event: EventData = load("res://data/events/%s.tres" % id)
		check_eq(event.weight, 4.5, "%s weight raised" % id)
