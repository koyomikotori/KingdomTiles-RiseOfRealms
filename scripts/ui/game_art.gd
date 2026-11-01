class_name GameArt
extends RefCounted
## The generated pixel art (GDD §13, tools/art/generate.py): looks textures up by id, so drawing
## code never builds paths. Missing art returns null and callers fall back to flat colors.

const TILE_DIR := "res://assets/tiles/"
const BUILDING_DIR := "res://assets/buildings/"
const ICON_DIR := "res://assets/icons/"
const UNIT_DIR := "res://assets/units/"
const BATTLE_DIR := "res://assets/battle/"
const EFFECT_DIR := "res://assets/effects/"
const PORTRAIT_DIR := "res://assets/portraits/"
const WORLD_DIR := "res://assets/world/"
const ITEM_DIR := "res://assets/items/"
const MAP_DIR := "res://assets/map/"
## Hand-drawn portraits that replace the generated one: <officer name>.png.
const CUSTOM_PORTRAIT_DIR := "res://assets/portraits/custom/"
## Hand-drawn / AI portraits (96×96, transparent, no frame) shared out to officers by group:
## general_m_01.png, advisor_f_02.png… (docs/portrait_ai_guide.md).
const PORTRAIT_POOL_DIR := "res://assets/portraits/pool/"
## Sprite sheet layers (tools/art/battle_art.py LAYER_SUFFIXES): base in full color, then grays
## tinted with the side's color, the officer's hair color and accent color.
const LAYERS: Array[String] = ["", "_team", "_hair", "_accent"]
## Rows of every unit sprite sheet, top to bottom (tools/art/battle_art.py STATES); 2 frames each.
const UNIT_STATES: Array[StringName] = [&"stand", &"walk", &"attack", &"fall", &"cheer"]
const UNIT_FRAMES := 2
## Board art is shown ×2: 24×24 tiles fill a cell (BoardView.TILE_SIZE), 16×16 buildings stand in
## its middle (M13c).
const ART_SCALE := 2
## Frames in every building's idle loop ("<id>_anim.png", tools/art/generate.py ANIM_FRAMES).
const BUILDING_ANIM_FRAMES := 4

## Keeps every texture alive: canvas draw commands only hold the texture's RID, so a texture
## loaded inside _draw() and dropped right after would render white.
static var _cache: Dictionary[String, Texture2D] = {}
static var _pool_cache: Dictionary[String, PackedStringArray] = {}


static func _load(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


## Lets the textures go (the headless test runner calls it before quitting).
static func clear_cache() -> void:
	_cache.clear()
	_pool_cache.clear()
	_tinted_cache.clear()


## Tile for a terrain id; &"" (no terrain) is the wild land outside the kingdom.
static func terrain(terrain_id: StringName) -> Texture2D:
	return _load(TILE_DIR + ("wild" if terrain_id == &"" else String(terrain_id)) + ".png")


static func key_marker() -> Texture2D:
	return _load(TILE_DIR + "key.png")


## Gold frame drawn over a key cell (above any building on it).
static func key_frame() -> Texture2D:
	return _load(TILE_DIR + "key_frame.png")


## The castle changes with the castle level (1–6).
## With `team` (alpha > 0), the roofs and banners are in that color (the kingdom's, M14h).
static func castle(level: int, team := Color(0, 0, 0, 0)) -> Texture2D:
	return team_tinted(_load(BUILDING_DIR + "castle_%d.png" % clampi(level, 1, 6)), team)


static func building(building_id: StringName) -> Texture2D:
	return _load(BUILDING_DIR + String(building_id) + ".png")


## The building's idle loop (BUILDING_ANIM_FRAMES frames side by side), or null (M13c).
static func building_anim(building_id: StringName) -> Texture2D:
	return _load(BUILDING_DIR + String(building_id) + "_anim.png")


static func castle_anim(level: int, team := Color(0, 0, 0, 0)) -> Texture2D:
	return team_tinted(_load(BUILDING_DIR + "castle_%d_anim.png" % clampi(level, 1, 6)), team)


## The castle's blue roof shades and red banner shades (tools/art/pixel.py "roof*" / "red*"),
## dark to light, swapped for shades of the kingdom's color by team_tinted.
const ROOF_SHADES: Array[Color] = [Color("2a4166"), Color("3e5c8a"), Color("5d7fb0")]
const BANNER_SHADES: Array[Color] = [Color("8e2a1e"), Color("c8412e"), Color("e8664c")]
static var _tinted_cache: Dictionary = {}


## `texture` with its roof and banner pixels in shades of `team`; unchanged without a team or
## for the default color.
static func team_tinted(texture: Texture2D, team: Color) -> Texture2D:
	if texture == null or team.a <= 0.0 or team.to_html(false) == KingdomState.PLAYER_COLOR.to_html(false):
		return texture
	var key := "%s|%s" % [texture.resource_path, team.to_html(false)]
	if not _tinted_cache.has(key):
		var swap := {}
		var shades: Array[Color] = [team.darkened(0.35), team, team.lightened(0.25)]
		for i in 3:
			swap[ROOF_SHADES[i].to_rgba32()] = shades[i]
			swap[BANNER_SHADES[i].to_rgba32()] = shades[i].lightened(0.15)
		var image := texture.get_image()
		image.decompress()
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				var opaque := Color(pixel.r, pixel.g, pixel.b, 1.0).to_rgba32()
				if pixel.a > 0.0 and swap.has(opaque):
					var shade: Color = swap[opaque]
					image.set_pixel(x, y, Color(shade.r, shade.g, shade.b, pixel.a))
		_tinted_cache[key] = ImageTexture.create_from_image(image)
	return _tinted_cache[key]


## A map walker strip (tools/art/map_art.py): &"villager_a", &"soldier" (+ "_team"), &"horse",
## &"cart", &"deer", &"bird", &"carry_food"…
static func map_sprite(sprite_id: StringName, layer: String = "") -> Texture2D:
	return _load(MAP_DIR + String(sprite_id) + layer + ".png")


static func level_badge(level: int) -> Texture2D:
	return _load(BUILDING_DIR + "level_%d.png" % level)


## Construction art (GDD §8, M12d): "foundation" (a new building's cells), "scaffold" (laid over
## every cell under construction).
static func construction(part: String) -> Texture2D:
	return _load(BUILDING_DIR + part + ".png")


## An item's 16×16 icon (Item.icon_id(): a type such as &"dao", or a legendary's id, M12e).
static func item_icon(icon_id: StringName) -> Texture2D:
	return _load(ITEM_DIR + String(icon_id) + ".png")


## The 24×24 frame of an item slot by rarity (Item.Rarity), -1 for an empty slot.
static func item_frame(rarity: int) -> Texture2D:
	return _load(ITEM_DIR + ("frame_empty" if rarity < 0 else "frame_%d" % rarity) + ".png")


## Plate with the turns a construction still needs (1–7).
static func turns_badge(turns: int) -> Texture2D:
	return _load(BUILDING_DIR + "turns_%d.png" % clampi(turns, 1, 7))


## Resource icon (24×24 on screen).
static func icon(resource_id: StringName) -> Texture2D:
	return _load(ICON_DIR + String(resource_id) + ".png")


# --- Battle (M12b) ------------------------------------------------------------------------

## One layer of a unit's sprite sheet (LAYERS): "" in full color, "_team" the clothes in grays.
## Unknown sprites fall back to the swordsman; missing officer layers are null.
static func unit_sheet(sprite_id: StringName, layer: String = "") -> Texture2D:
	var texture := _load(UNIT_DIR + String(sprite_id) + layer + ".png")
	if texture == null and not ResourceLoader.exists(UNIT_DIR + String(sprite_id) + ".png"):
		texture = _load(UNIT_DIR + "swordsman" + layer + ".png")
	return texture


## The battle sprite of a general (&"general") or an advisor (&"advisor") with this look.
## `weapon_type`: the general's worn weapon (Item.WEAPON_TYPES, M12e); &"" is a plain sword.
static func officer_sprite(kind: StringName, look: OfficerLook, weapon_type: StringName = &"") -> StringName:
	var id := "%s_%s" % [kind, "f" if look != null and look.is_female() else "m"]
	return StringName(id + ("_" + String(weapon_type) if weapon_type != &"" else ""))


## Tints for draw_unit: the side's color, plus the officer's hair and accent colors.
static func unit_tints(clothes: Color, look: OfficerLook = null) -> Dictionary:
	var tints := {"_team": clothes}
	if look != null:
		tints["_hair"] = look.hair_tint()
		tints["_accent"] = look.accent_color()
	return tints


## Draws one frame of a unit sprite with its foot (bottom middle) at `foot`; `scale.x` < 0 mirrors.
## `tints` maps a layer suffix to its color (unit_tints); untinted gray layers are skipped.
static func draw_unit(canvas: CanvasItem, sprite_id: StringName, foot: Vector2, rotation: float, scale: Vector2,
		state: StringName, frame: int, tints: Dictionary, darken: float = 0.0) -> void:
	var base := unit_sheet(sprite_id)
	if base == null:
		return
	var region := unit_frame(base, state, frame)
	var rect := Rect2(Vector2(-region.size.x * 0.5, -region.size.y), region.size)
	canvas.draw_set_transform(foot, rotation, scale)
	canvas.draw_texture_rect_region(base, rect, region, Color.WHITE.darkened(darken))
	for layer in LAYERS:
		if layer == "" or not tints.has(layer):
			continue
		var sheet := unit_sheet(sprite_id, layer)
		if sheet != null:
			canvas.draw_texture_rect_region(sheet, rect, region, (tints[layer] as Color).darkened(darken))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The region of `sheet` holding `frame` of `state`.
static func unit_frame(sheet: Texture2D, state: StringName, frame: int) -> Rect2:
	var size := sheet.get_size() / Vector2(UNIT_FRAMES, UNIT_STATES.size())
	return Rect2(Vector2(frame % UNIT_FRAMES, maxi(0, UNIT_STATES.find(state))) * size, size)


## Battlefield pieces: &"mountains", &"cloud", &"ground", &"town", &"camp" (+ &"camp_team").
static func battle(piece: StringName) -> Texture2D:
	return _load(BATTLE_DIR + String(piece) + ".png")


## Effect strips (2 frames side by side): &"fire", &"smoke", &"sparkle"; &"arrow" is one image.
static func effect(effect_id: StringName) -> Texture2D:
	return _load(EFFECT_DIR + String(effect_id) + ".png")


# --- Portraits (M12c) ---------------------------------------------------------------------

## A portrait part (tools/art/portrait_art.py), or null.
static func portrait_part(part: String) -> Texture2D:
	return _load(PORTRAIT_DIR + part + ".png")


## A hand-drawn portrait for this officer, if one was dropped into CUSTOM_PORTRAIT_DIR.
static func custom_portrait(officer_name: String) -> Texture2D:
	return _load(CUSTOM_PORTRAIT_DIR + officer_name + ".png")


## A non-officer character's portrait (96×96 with its background, e.g. the black market's
## merchant): a hand-drawn CUSTOM_PORTRAIT_DIR/<id>.png wins over the generated npc/<id>.png.
static func npc_portrait(npc_id: StringName) -> Texture2D:
	var custom := _load(CUSTOM_PORTRAIT_DIR + String(npc_id) + ".png")
	return custom if custom != null else _load(PORTRAIT_DIR + "npc/" + String(npc_id) + ".png")


## "general_m", "advisor_f"…: which pool portraits fit this officer.
static func portrait_group(officer: Officer) -> String:
	return "%s_%s" % ["advisor" if officer is Advisor else "general", "f" if officer.look.is_female() else "m"]


## The pool portraits of a group, sorted (ResourceLoader.list_directory also works in exports).
static func portrait_pool(group: String) -> PackedStringArray:
	if not _pool_cache.has(group):
		var names := PackedStringArray()
		if DirAccess.dir_exists_absolute(PORTRAIT_POOL_DIR):
			for file in ResourceLoader.list_directory(PORTRAIT_POOL_DIR):
				if file.begins_with(group + "_") and file.get_extension().to_lower() == "png":
					names.append(file)
		names.sort()
		_pool_cache[group] = names
	return _pool_cache[group]


## One of `names`, always the same for the same officer name; "" when the pool is empty.
static func pick_portrait(names: PackedStringArray, officer_name: String) -> String:
	return names[posmod(hash(officer_name), names.size())] if not names.is_empty() else ""


static func pool_portrait(file: String) -> Texture2D:
	return _load(PORTRAIT_POOL_DIR + file) if file != "" else null


## The officer's pool portrait: the one they were given (OfficerLook.portrait) while it is still
## in the pool, otherwise one picked from their name; null when the pool has none for them.
static func officer_pool_portrait(officer: Officer) -> Texture2D:
	var names := portrait_pool(portrait_group(officer))
	var file := officer.look.portrait if names.has(officer.look.portrait) else pick_portrait(names, officer.name)
	return pool_portrait(file)


## Gives a new officer their pool portrait for good (saved in their look).
static func assign_portrait(officer: Officer) -> void:
	officer.look.portrait = pick_portrait(portrait_pool(portrait_group(officer)), officer.name)


# --- World map (M12c) ---------------------------------------------------------------------

## World map pieces: &"parchment", &"mountain", &"trees", &"fort" (+ &"fort_team"),
## &"icon_war", &"icon_alliance", &"icon_pact".
static func world(piece: StringName) -> Texture2D:
	return _load(WORLD_DIR + String(piece) + ".png")
