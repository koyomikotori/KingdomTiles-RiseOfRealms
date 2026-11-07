extends "res://tests/test_suite.gd"
## M16h: the player's ruler (Chúa công) and generals on foot.


func _state(settings: Dictionary = {}) -> KingdomState:
	var terrains := TerrainLibrary.load_all()
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.setup_new_game(settings)
	state.start()
	return state


func test_presets_are_valid_and_drawn() -> void:
	check_eq(Ruler.PRESETS.size(), 6, "Six rulers to choose from")
	var genders := {}
	for i in Ruler.PRESETS.size():
		var ruler := Ruler.from_preset(i)
		var look := ruler.look
		genders[look.gender] = genders.get(look.gender, 0) + 1
		check(Ruler.OUTFIT_NAMES.has(ruler.outfit()), "Preset %d: a known outfit" % i)
		check(look.skin < OfficerLook.SKIN_TONES.size() and look.hair_style < OfficerLook.HAIR_STYLES
				and look.hair_color < OfficerLook.HAIR_COLORS.size() and look.eyes < OfficerLook.EYE_STYLES
				and look.brows < OfficerLook.BROW_STYLES and look.beard < OfficerLook.BEARD_STYLES
				and look.accent < OfficerLook.ACCENT_COLORS.size(), "Preset %d: face parts exist" % i)
		check(look.beard == 0 or not look.is_female(), "Preset %d: no beard on a woman" % i)
		check(GameArt.ruler_portrait(i) != null, "Preset %d: a drawn portrait" % i)
		check_eq(GameArt.ruler_portrait(i).get_size(), Vector2(PortraitView.SIZE, PortraitView.SIZE),
				"Preset %d: portrait is 96×96" % i)
		for entry: Array in PortraitView.layers(ruler, Color.WHITE):
			check(GameArt.portrait_part(entry[0]) != null, "Preset %d: portrait part %s" % [i, entry[0]])
	check_eq(genders, {&"m": 3, &"f": 3}, "Three men and three women")
	check_eq(Ruler.from_preset(2).look.hair_tint(), Ruler.BLOND, "Warriors are blond")
	check_eq(Ruler.from_preset(0).look.hair_tint(), OfficerLook.HAIR_COLORS[0], "Emperors have black hair")


func test_ruler_is_chosen_and_saved() -> void:
	var state := _state({"ruler_preset": 5, "ruler_name": "  Lý Chiêu Hoàng  "})
	check_eq(state.ruler.preset, 5, "Preset from the new game screen")
	check_eq(state.ruler.name, "Lý Chiêu Hoàng", "Name trimmed")
	check_eq(_state({"ruler_name": "   "}).ruler.name, Ruler.DEFAULT_NAME, "Empty name: Chúa công")
	var copy := _state()
	copy.load_save(JSON.parse_string(JSON.stringify(state.to_save())))
	check_eq(copy.ruler.preset, 5, "Preset saved")
	check_eq(copy.ruler.name, "Lý Chiêu Hoàng", "Name saved")
	var old := state.to_save()
	old.erase("ruler")
	copy.load_save(JSON.parse_string(JSON.stringify(old)))
	check(copy.ruler.preset == 0 and copy.ruler.name == Ruler.DEFAULT_NAME, "Older saves: the first ruler")


func test_generals_have_foot_sprites() -> void:
	for gender: StringName in OfficerLook.GENDERS:
		var look := OfficerLook.new()
		look.gender = gender
		for stars in [1, 3, 5]:
			for weapon_type: StringName in [&""] + Item.WEAPON_TYPES:
				var id := GameArt.foot_sprite(look, weapon_type, stars)
				check(String(id).begins_with("general_foot_"), "%s is a foot sprite" % id)
				for layer in GameArt.LAYERS:
					check(ResourceLoader.exists(GameArt.UNIT_DIR + String(id) + layer + ".png"), "%s%s" % [id, layer])
				check_eq(GameArt.frames_of(id), GameArt.OFFICER_FRAMES, "%s has 4 frames" % id)
