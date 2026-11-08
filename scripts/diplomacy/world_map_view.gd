class_name WorldMapView
extends Control
## Draws the campaign map (GDD §15, M14b) as an old map on paper (GDD §13, M12c), bigger than the
## view: drag it with the mouse (or a finger) to look around. The 5×5 grid of the campaign sits on
## the land with every fort nudged off its square, dirt roads winding between neighbouring
## squares, two rivers and a lake, mountain chains, forests, hills and hamlets grouped in regions.
## Each clan is a fort flying its banner color on a patch tinted by the relation tier, with icons
## for war and alliance; annexed squares fly the kingdom's colors and clans beyond
## Diplomacy.REACH are faded. A click (without dragging) on a clan selects it. Read-only.

signal clan_selected(clan_id: StringName)

const KINGDOM_ID: StringName = &"kingdom"
const NODE_RADIUS := 22.0
const BACKGROUND_COLOR := Color(0.91, 0.84, 0.66)
const ROAD_COLOR := Color(0.47, 0.32, 0.18, 0.75)
const KINGDOM_COLOR := Color(1.0, 0.85, 0.35)
const SELECTED_COLOR := Color(0.85, 0.6, 0.12)
const LABEL_OUTLINE := Color(0.96, 0.92, 0.8, 0.9)
const RIVER_COLOR := Color(0.45, 0.66, 0.8)
const RIVER_EDGE_COLOR := Color(0.29, 0.2, 0.13, 0.6)
const LAKE_COLOR := Color(0.5, 0.7, 0.82)
## One grid square of the campaign on the map, and the land around the grid.
const CELL := Vector2(330, 250)
const MARGIN := Vector2(140, 110)
const WORLD_SIZE := CELL * ClanData.GRID_SIZE + MARGIN * 2.0
## Forts stand up to this share of a square away from its middle.
const JITTER := Vector2(0.22, 0.18)
## Map art is drawn ×2.
const ART_SCALE := 2.0
const EDGE_BANDS := 6
const EDGE_BAND_WIDTH := 10.0
const EDGE_COLOR := Color(0.45, 0.3, 0.15, 0.22)
const LAYOUT_SEED := 7
const DECORATION_TRIES := 700
## Decorations keep this far (pixels) from forts (and their labels), roads and water.
const NODE_CLEARANCE := 95.0
const ROAD_CLEARANCE := 24.0
const WATER_CLEARANCE := 28.0
## Points along each road / river (more = smoother).
const CURVE_STEPS := 18
## A press that moves more than this (pixels) drags the map instead of clicking.
const DRAG_SLOP := 6.0
## HOSTILE, TENSE, NEUTRAL, FRIENDLY, CLOSE
const TIER_COLORS: Array[Color] = [Color(0.9, 0.2, 0.2), Color(0.95, 0.55, 0.25), Color(0.75, 0.75, 0.75),
		Color(0.45, 0.85, 0.45), Color(0.3, 1.0, 0.6)]
const LABEL_FONT_SIZE := 13
const HINT_FONT_SIZE := 13
## Clans out of reach are drawn with this alpha.
const FAR_ALPHA := 0.45
const FAR_BANNER := Color(0.55, 0.52, 0.48)

var _diplomacy: Diplomacy
var _wars: Wars
var _selected: StringName = &""
## Top-left of the view in map coordinates (dragging moves it).
var _offset := Vector2.ZERO
var _pressing := false
var _dragging := false
var _press_position := Vector2.ZERO
## Built once (_build_layout): fort positions by square, roads, rivers, the lake, decorations.
var _squares: Dictionary[Vector2i, Vector2] = {}
var _roads: Array[PackedVector2Array] = []
var _rivers: Array[PackedVector2Array] = []
var _lake := Rect2()
## [piece, map position]
var _decorations: Array = []


## The player's kingdom on the map (KingdomState.kingdom_name / player_color, M14h).
var kingdom_name := KingdomState.DEFAULT_KINGDOM_NAME
var kingdom_color := KingdomState.PLAYER_COLOR


func setup(diplomacy: Diplomacy) -> void:
	_diplomacy = diplomacy
	_diplomacy.changed.connect(queue_redraw)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	# The parchment is a tiled texture.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_build_layout()
	resized.connect(func() -> void: _scroll_by(Vector2.ZERO))


## Shows war markers, annexed clans and clans that became neighbours.
func setup_wars(wars: Wars) -> void:
	_wars = wars
	_wars.changed.connect(queue_redraw)
	queue_redraw()


func select(clan_id: StringName) -> void:
	_selected = clan_id
	queue_redraw()


## Where a square's fort stands on the map.
func square_position(square: Vector2i) -> Vector2:
	return _squares.get(square, Vector2.ZERO)


func _position_of(id: StringName) -> Vector2:
	if id == KINGDOM_ID:
		return square_position(ClanData.HOME)
	return square_position(_diplomacy.clans[id].data.grid)


# --- Input ---------------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var press: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT) \
			or event is InputEventScreenTouch
	if press and event.pressed:
		_pressing = true
		_dragging = false
		_press_position = event.position
		accept_event()
	elif press and _pressing:
		_pressing = false
		if not _dragging:
			_click(event.position)
		_dragging = false
		accept_event()
	elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and _pressing:
		if _dragging or event.position.distance_to(_press_position) > DRAG_SLOP:
			_dragging = true
			_scroll_by(-event.relative)
		accept_event()


func _click(screen_position: Vector2) -> void:
	var at := screen_position + _offset
	for clan_id in _diplomacy.clans:
		if at.distance_to(_position_of(clan_id)) <= NODE_RADIUS + 14:
			select(clan_id)
			clan_selected.emit(clan_id)
			return


func _scroll_by(amount: Vector2) -> void:
	var most := (WORLD_SIZE - size).max(Vector2.ZERO)
	_offset = (_offset + amount).clamp(Vector2.ZERO, most)
	queue_redraw()


# --- Layout --------------------------------------------------------------------------------

func _build_layout() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = LAYOUT_SEED
	for y in ClanData.GRID_SIZE:
		for x in ClanData.GRID_SIZE:
			var middle := MARGIN + (Vector2(x, y) + Vector2(0.5, 0.45)) * CELL
			var nudge := Vector2(rng.randf_range(-JITTER.x, JITTER.x), rng.randf_range(-JITTER.y, JITTER.y)) * CELL
			_squares[Vector2i(x, y)] = middle + nudge
	for y in ClanData.GRID_SIZE:
		for x in ClanData.GRID_SIZE:
			for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var other := Vector2i(x, y) + step
				if _squares.has(other):
					_roads.append(_winding(_squares[Vector2i(x, y)], _squares[other], rng, 0.22))
	# A river down between the 3rd and 4th columns, and one from the west joining it between the
	# 3rd and 4th rows; both away from the forts.
	var east_x := MARGIN.x + 3.0 * CELL.x
	var join := Vector2(east_x, MARGIN.y + 3.0 * CELL.y)
	_rivers.append(_meander(Vector2(east_x, 0.0), Vector2(east_x, WORLD_SIZE.y), rng))
	_rivers.append(_meander(Vector2(0.0, join.y), join, rng))
	var lake_center := MARGIN + Vector2(1.0, 4.0) * CELL + Vector2(0, CELL.y * 0.55)
	_lake = Rect2(lake_center - Vector2(70, 34), Vector2(140, 68))
	_place_decorations(rng)


## A road from `from` to `to` that bends to one side (a curve through a shifted middle point).
func _winding(from: Vector2, to: Vector2, rng: RandomNumberGenerator, bend: float) -> PackedVector2Array:
	var normal := (to - from).orthogonal().normalized()
	var control := (from + to) * 0.5 + normal * (to - from).length() * rng.randf_range(-bend, bend)
	var points := PackedVector2Array()
	for i in CURVE_STEPS + 1:
		var t := float(i) / CURVE_STEPS
		points.append(from.lerp(control, t).lerp(control.lerp(to, t), t))
	return points


## A river wandering from `from` to `to` (sideways waves of a few dozen pixels).
func _meander(from: Vector2, to: Vector2, rng: RandomNumberGenerator) -> PackedVector2Array:
	var normal := (to - from).orthogonal().normalized()
	var phase := rng.randf() * TAU
	var points := PackedVector2Array()
	var steps := CURVE_STEPS * 3
	for i in steps + 1:
		var t := float(i) / steps
		var wave := sin(t * 9.0 + phase) * 26.0 + sin(t * 23.0 + phase * 2.0) * 9.0
		points.append(from.lerp(to, t) + normal * wave * (1.0 if 0.0 < t and t < 1.0 else 0.0))
	return points


## Mountains, forests, hills and hamlets in regions (a smooth wave field picks the kind), never on
## a fort, its label, a road or water; reeds around the lake.
func _place_decorations(rng: RandomNumberGenerator) -> void:
	for i in 10:
		var angle := TAU * i / 10.0
		_decorations.append([&"reeds", _lake.get_center() + Vector2(cos(angle) * 80, sin(angle) * 42)])
	for i in DECORATION_TRIES:
		var at := Vector2(rng.randf_range(20, WORLD_SIZE.x - 20), rng.randf_range(20, WORLD_SIZE.y - 20))
		if not _is_clear(at):
			continue
		var region := sin(at.x * 0.0042 + 1.3) * cos(at.y * 0.0051 + 0.7) + 0.35 * sin((at.x + at.y) * 0.003)
		var piece: StringName
		if region > 0.45:
			piece = &"mountain_range" if rng.randf() < 0.5 else &"mountain"
		elif region > 0.25:
			piece = &"mountain" if rng.randf() < 0.6 else &"hills"
		elif region < -0.45:
			piece = &"pines" if rng.randf() < 0.6 else &"trees"
		elif region < -0.25:
			piece = &"trees" if rng.randf() < 0.6 else &"hills"
		elif rng.randf() < 0.25:
			piece = [&"hills", &"village", &"trees"][rng.randi() % 3]
		else:
			continue
		_decorations.append([piece, at])
	# Drawn top to bottom, so lower pieces overlap the ones behind them.
	_decorations.sort_custom(func(a: Array, b: Array) -> bool: return a[1].y < b[1].y)


func _is_clear(at: Vector2) -> bool:
	for square: Vector2 in _squares.values():
		# The fort above, its label below.
		var zone := Rect2(square - Vector2(NODE_CLEARANCE, NODE_CLEARANCE * 0.7),
				Vector2(NODE_CLEARANCE * 2.0, NODE_CLEARANCE * 1.5))
		if zone.has_point(at):
			return false
	for line in _roads:
		if _distance_to_line(at, line) < ROAD_CLEARANCE:
			return false
	for line in _rivers:
		if _distance_to_line(at, line) < WATER_CLEARANCE:
			return false
	for decoration: Array in _decorations:
		if decoration[1].distance_to(at) < 46.0:
			return false
	return not _lake.grow(WATER_CLEARANCE).has_point(at)


static func _distance_to_line(at: Vector2, line: PackedVector2Array) -> float:
	var best := INF
	for i in line.size() - 1:
		best = minf(best, Geometry2D.get_closest_point_to_segment(at, line[i], line[i + 1]).distance_to(at))
	return best


# --- Drawing -------------------------------------------------------------------------------

func _draw() -> void:
	_draw_parchment()
	if _diplomacy == null:
		return
	draw_set_transform(-_offset)
	_draw_water()
	for line in _roads:
		_draw_road(line)
	for decoration: Array in _decorations:
		_draw_piece(decoration[0], decoration[1])
	_draw_node(_position_of(KINGDOM_ID), kingdom_color, KINGDOM_COLOR, kingdom_name, false)
	for clan_id in _diplomacy.clans:
		var clan := _diplomacy.clans[clan_id]
		var center := _position_of(clan_id)
		var front: Wars.Front = _wars.fronts[clan_id] if _wars != null else null
		if clan.annexed:
			_draw_node(center, kingdom_color, KINGDOM_COLOR, clan.data.display_name, clan_id == _selected)
			continue
		var tier_color := TIER_COLORS[Diplomacy.tier_for(clan.relation)]
		var far := not _diplomacy.in_reach(clan_id)
		var label := clan.data.display_name
		if clan.is_allied():
			label += " · đồng minh"
		_draw_node(center, FAR_BANNER if far else clan.data.color, tier_color, label, clan_id == _selected,
				FAR_ALPHA if far else 1.0)
		var corner := Vector2(NODE_RADIUS + 4, -NODE_RADIUS - 4)
		if front != null and front.at_war:
			_draw_piece(&"icon_war", center + corner)
		if clan.is_allied():
			_draw_piece(&"icon_alliance", center + Vector2(-corner.x, corner.y))
	draw_set_transform(Vector2.ZERO)
	_draw_edges()
	var font := ThemeDB.fallback_font
	var hint := "Kéo để di chuyển bản đồ" if Touch.active else "Kéo chuột để di chuyển bản đồ"
	var at := Vector2(14, size.y - 14)
	draw_string_outline(font, at, hint, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE, 5, LABEL_OUTLINE)
	draw_string(font, at, hint, HORIZONTAL_ALIGNMENT_LEFT, -1, HINT_FONT_SIZE, UiPalette.MUTED)


## Tiled paper, scrolling with the map.
func _draw_parchment() -> void:
	var paper := GameArt.world(&"parchment")
	if paper == null:
		draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR)
		return
	var tile := paper.get_size() * ART_SCALE
	var shift := -Vector2(fmod(_offset.x, tile.x), fmod(_offset.y, tile.y))
	draw_set_transform(shift, 0.0, Vector2.ONE * ART_SCALE)
	draw_texture_rect(paper, Rect2(Vector2.ZERO, (size + tile) / ART_SCALE), true)
	draw_set_transform(Vector2.ZERO)


## Darker toward the view's edges like an old map.
func _draw_edges() -> void:
	for i in EDGE_BANDS:
		var inset := i * EDGE_BAND_WIDTH
		var shade := Color(EDGE_COLOR, EDGE_COLOR.a * (1.0 - float(i) / EDGE_BANDS))
		draw_rect(Rect2(Vector2.ONE * inset, size - Vector2.ONE * inset * 2.0), shade, false, EDGE_BAND_WIDTH)


func _draw_water() -> void:
	for line in _rivers:
		draw_polyline(line, RIVER_EDGE_COLOR, 11.0, true)
		draw_polyline(line, RIVER_COLOR, 7.0, true)
	draw_set_transform(_lake.get_center() - _offset, 0.0, Vector2(1.0, _lake.size.y / _lake.size.x))
	draw_circle(Vector2.ZERO, _lake.size.x * 0.5 + 3.0, RIVER_EDGE_COLOR)
	draw_circle(Vector2.ZERO, _lake.size.x * 0.5, LAKE_COLOR)
	draw_set_transform(-_offset)


## Dashes along the road's curve, from one fort's edge to the other's.
func _draw_road(line: PackedVector2Array) -> void:
	var trimmed := PackedVector2Array()
	for point in line:
		if point.distance_to(line[0]) > NODE_RADIUS and point.distance_to(line[line.size() - 1]) > NODE_RADIUS:
			trimmed.append(point)
	for i in trimmed.size() - 1:
		if i % 2 == 0:
			draw_line(trimmed[i], trimmed[i + 1], ROAD_COLOR, 4.0)


func _draw_piece(piece: StringName, center: Vector2) -> void:
	var texture := GameArt.world(piece)
	if texture != null:
		var draw_size := texture.get_size() * ART_SCALE
		draw_texture_rect(texture, Rect2(center - draw_size * 0.5, draw_size), false)


## A fort with its banner in `banner` color, standing on a patch tinted by the relation tier;
## `alpha` < 1 fades clans out of reach.
func _draw_node(center: Vector2, banner: Color, tier: Color, label: String, selected: bool, alpha: float = 1.0) -> void:
	var ground := Rect2(center + Vector2(-NODE_RADIUS - 6, NODE_RADIUS * 0.2), Vector2(NODE_RADIUS * 2 + 12, 18))
	draw_set_transform(ground.get_center() - _offset, 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, NODE_RADIUS + 8, Color(tier, 0.55 * alpha))
	if selected:
		draw_circle(Vector2.ZERO, NODE_RADIUS + 14, SELECTED_COLOR, false, 4.0)
	draw_set_transform(-_offset)
	var fort := GameArt.world(&"fort")
	if fort != null:
		var draw_size := fort.get_size() * ART_SCALE
		var rect := Rect2(center - Vector2(draw_size.x * 0.5, draw_size.y * 0.7), draw_size)
		draw_texture_rect(fort, rect, false, Color(1, 1, 1, alpha))
		var team := GameArt.world(&"fort_team")
		if team != null:
			draw_texture_rect(team, rect, false, Color(banner, alpha))
	else:
		draw_circle(center, NODE_RADIUS, banner)
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE).x
	var text_pos := center + Vector2(-width * 0.5, NODE_RADIUS + 22)
	draw_string_outline(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, 5,
			Color(LABEL_OUTLINE, LABEL_OUTLINE.a * alpha))
	draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, Color(UiPalette.TEXT, alpha))
