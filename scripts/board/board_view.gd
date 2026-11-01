class_name BoardView
extends Node2D
## Draws a BoardData with the generated pixel art (GameArt, GDD §13) and turns mouse input into
## cell coordinates: a click (press and release without moving), or a left-button drag that moves
## the map. Read-only: it never modifies the board, it only emits signals.

signal cell_hovered(coord: Vector2i)
## A press and release without moving (more than TAP_SLOP) on a cell.
signal cell_tapped(coord: Vector2i)
## A left-button drag: the map should follow (screen pixels).
signal pan_dragged(relative: Vector2)

## Cells are 48 px; buildings (16×16 art ×2) stand in their middle with room around them for the
## walkers (M13c).
const TILE_SIZE := 48
## Buildings sit this much below the center of their cells (their roofs need the room above).
const BUILDING_DROP := 4.0
## Building idle loops (GameArt.building_anim) advance this many frames per second.
const ANIM_FPS := 4.0
const OFF_BOARD := Vector2i(-1, -1)
## Screen pixels a press may move and still count as a click.
const TAP_SLOP := 12.0
const SELECTED_COLOR := Color(1.0, 0.9, 0.45)

const EMPTY_COLOR := Color(0.10, 0.11, 0.14)
const GRID_COLOR := Color(0, 0, 0, 0.12)
const TERRITORY_BORDER_COLOR := Color(1.0, 0.88, 0.4)
const TERRITORY_SHADOW_COLOR := Color(0.17, 0.11, 0.07, 0.8)
const HOVER_COLOR := Color(1, 1, 1, 0.9)
## Land outside the kingdom is darkened (wild land already has its own dull tile).
const UNOWNED_TINT := Color(0.55, 0.55, 0.6)
## Outline of the whole board, so wild land at the edges stands out from the background.
const BOARD_EDGE_COLOR := Color(0.93, 0.85, 0.64, 0.7)
const COORD_TEXT_COLOR := Color(1, 1, 1, 0.75)
const COORD_FONT_SIZE := 8
const KEY_MARKER_COLOR := Color(1.0, 0.85, 0.2)
const GHOST_ALPHA := 0.75
const GHOST_VALID_COLOR := Color(0.45, 1.0, 0.45)
const GHOST_INVALID_COLOR := Color(1.0, 0.3, 0.3)

## A building being upgraded shows through its scaffolding this much.
const UPGRADING_ALPHA := 0.6
## Buildings put out of work by a war event (M16b) are drawn grayed, with their turns left.
const DISABLED_TINT := Color(0.5, 0.5, 0.5)
## Turns left on the castle's upgrade (KingdomState.castle_turns), set by the kingdom scene.
var castle_turns := 0:
	set(value):
		if castle_turns != value:
			castle_turns = value
			queue_redraw()

## The cell whose information is shown (clicked with nothing selected), or OFF_BOARD.
var selected_cell := OFF_BOARD:
	set(value):
		selected_cell = value
		queue_redraw()
var _pressing := false
var _press_position := Vector2.ZERO
var _panning := false

## Shows "x,y" in every cell. Toggled with G in the kingdom scene (off now that cells have art).
var show_coords := false:
	set(value):
		show_coords = value
		queue_redraw()
## The kingdom's color on the castle's roofs and banners (GameArt.team_tinted, M14h). Set by the kingdom scene.
var team_color := Color(0, 0, 0, 0):
	set(value):
		team_color = value
		queue_redraw()
## Picks the castle picture (GameArt.castle). Set by the kingdom scene.
var castle_level := 1:
	set(value):
		castle_level = value
		queue_redraw()

var _board: BoardData
var _terrains: Dictionary[StringName, TerrainData] = {}
var _hovered := OFF_BOARD
var _ghost_piece: LandPiece
var _ghost_origin := Vector2i.ZERO
var _ghost_valid := false
var _ghost_building: BuildingData
var _buildings: Dictionary[StringName, BuildingData] = {}
## Buildings play their idle loops (the map effects setting, M13c).
var animate := true:
	set(value):
		animate = value
		_anim_frame = 0
		queue_redraw()
var _anim_frame := 0
var _anim_time := 0.0
## Level and turns badges are drawn on this child, above the walkers (MapLifeView, z_index 0).
var _badges := Node2D.new()


func _ready() -> void:
	_badges.z_index = 1
	_badges.draw.connect(_draw_level_badges)
	add_child(_badges)


func setup(board: BoardData, terrains: Dictionary[StringName, TerrainData],
		buildings: Dictionary[StringName, BuildingData] = {}) -> void:
	_board = board
	_terrains = terrains
	_buildings = buildings
	_board.cell_changed.connect(func(_coord: Vector2i) -> void: queue_redraw())
	queue_redraw()


func _process(delta: float) -> void:
	if not animate or _board == null:
		return
	_anim_time += delta
	var frame := int(_anim_time * ANIM_FPS) % GameArt.BUILDING_ANIM_FRAMES
	if frame != _anim_frame:
		_anim_frame = frame
		queue_redraw()


## Where a building's picture goes: `art_size` (its texture) ×2, centered on its cells and a
## little lower (BUILDING_DROP), never past them.
static func art_rect(origin: Vector2i, cells: Vector2i, art_size: Vector2) -> Rect2:
	var bounds := Rect2(cell_to_local(origin), Vector2(cells * TILE_SIZE))
	var drawn := (art_size * GameArt.ART_SCALE).min(bounds.size)
	var pos := bounds.position + (bounds.size - drawn) * 0.5 + Vector2(0, BUILDING_DROP)
	pos.y = minf(pos.y, bounds.end.y - drawn.y)
	return Rect2(pos, drawn)


## Floor division so that positions left of / above the board map to negative cells.
static func local_to_cell(local_pos: Vector2) -> Vector2i:
	return Vector2i(floori(local_pos.x / TILE_SIZE), floori(local_pos.y / TILE_SIZE))


## Top-left corner of the cell in this node's local space.
static func cell_to_local(coord: Vector2i) -> Vector2:
	return Vector2(coord * TILE_SIZE)


## Returns null for unknown ids.
func get_terrain(terrain_id: StringName) -> TerrainData:
	return _terrains.get(terrain_id)


## Shows a translucent preview of `piece` placed at `origin`, outlined green or red.
func show_ghost(piece: LandPiece, origin: Vector2i, valid: bool) -> void:
	_ghost_piece = piece
	_ghost_building = null
	_ghost_origin = origin
	_ghost_valid = valid
	queue_redraw()


## Shows a translucent preview of `building` with its top-left cell at `origin`.
func show_building_ghost(building: BuildingData, origin: Vector2i, valid: bool) -> void:
	_ghost_building = building
	_ghost_piece = null
	_ghost_origin = origin
	_ghost_valid = valid
	queue_redraw()


func hide_ghost() -> void:
	if _ghost_piece == null and _ghost_building == null:
		return
	_ghost_piece = null
	_ghost_building = null
	queue_redraw()


func get_hovered_cell() -> Vector2i:
	return _hovered


func get_board_rect() -> Rect2:
	return Rect2(global_position, Vector2(_board.width, _board.height) * TILE_SIZE)


func _unhandled_input(event: InputEvent) -> void:
	if _board == null:
		return
	if event is InputEventMouseMotion:
		_update_hover(event.position)
		if not _pressing:
			return
		if _panning or event.position.distance_to(_press_position) > TAP_SLOP:
			_panning = true
			pan_dragged.emit(event.relative)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var coord := _cell_at(event.position)
		if event.pressed:
			_pressing = true
			_press_position = event.position
			_panning = false
		elif _pressing:
			_pressing = false
			if not _panning and _board.is_in_bounds(coord):
				cell_tapped.emit(coord)


## The cell under a viewport position (an input event's), possibly off the board.
func _cell_at(screen_position: Vector2) -> Vector2i:
	return local_to_cell(get_global_transform_with_canvas().affine_inverse() * screen_position)


func _update_hover(screen_position: Vector2) -> void:
	var coord := _cell_at(screen_position)
	if not _board.is_in_bounds(coord):
		coord = OFF_BOARD
	if coord == _hovered:
		return
	_hovered = coord
	cell_hovered.emit(coord)
	queue_redraw()


func _draw() -> void:
	if _board == null:
		return
	for cell in _board.get_all_cells():
		_draw_cell(cell)
	draw_rect(Rect2(Vector2.ZERO, Vector2(_board.width, _board.height) * TILE_SIZE).grow(1), BOARD_EDGE_COLOR, false, 2.0)
	_draw_territory_border()
	_draw_buildings()
	_draw_key_frames()
	_badges.queue_redraw()
	if show_coords:
		_draw_coords()
	if _ghost_piece != null:
		_draw_ghost()
	elif _ghost_building != null:
		_draw_building_ghost()
	elif _hovered != OFF_BOARD:
		draw_rect(_cell_rect(_hovered), HOVER_COLOR, false, 2.0)
	if selected_cell != OFF_BOARD and _ghost_piece == null and _ghost_building == null:
		draw_rect(_cell_rect(selected_cell).grow(-1), SELECTED_COLOR, false, 3.0)


func _draw_cell(cell: CellData) -> void:
	var rect := _cell_rect(cell.coord)
	var tint := Color.WHITE if cell.owned or not cell.has_terrain() else UNOWNED_TINT
	if not draw_terrain(self, rect, cell.terrain_id, tint):
		draw_rect(rect, EMPTY_COLOR if not cell.has_terrain() else _terrain_color(cell.terrain_id) * tint)
	draw_rect(rect, GRID_COLOR, false, 1.0)
	if cell.is_key:
		draw_key_marker(self, rect)


func _draw_ghost() -> void:
	var outline := GHOST_VALID_COLOR if _ghost_valid else GHOST_INVALID_COLOR
	var coords := _ghost_piece.get_board_coords(_ghost_origin)
	for i in coords.size():
		var rect := _cell_rect(coords[i])
		var tint := Color(1, 1, 1, GHOST_ALPHA)
		if not draw_terrain(self, rect, _ghost_piece.terrains[i], tint):
			var fill := _terrain_color(_ghost_piece.terrains[i])
			fill.a = GHOST_ALPHA
			draw_rect(rect, fill)
		if _ghost_piece.is_key_cell(i):
			draw_key_marker(self, rect)
			_draw_key_frame(rect)
		draw_rect(rect.grow(-1), outline, false, 2.0)


func _draw_building_ghost() -> void:
	var rect := Rect2(cell_to_local(_ghost_origin), Vector2(_ghost_building.size * TILE_SIZE))
	var texture := GameArt.building(_ghost_building.building_id)
	if texture != null:
		draw_texture_rect(texture, art_rect(_ghost_origin, _ghost_building.size, texture.get_size()), false,
				Color(1, 1, 1, GHOST_ALPHA))
	else:
		var fill := _ghost_building.color
		fill.a = GHOST_ALPHA
		draw_rect(rect.grow(-4), fill)
	draw_rect(rect.grow(-1), GHOST_VALID_COLOR if _ghost_valid else GHOST_INVALID_COLOR, false, 2.0)


## The terrain's tile stretched over `rect` (pixel art ×2). False when there is no art for it.
## Static so piece cards can share it.
static func draw_terrain(canvas: CanvasItem, rect: Rect2, terrain_id: StringName, tint: Color = Color.WHITE) -> bool:
	var texture := GameArt.terrain(terrain_id)
	if texture == null:
		return false
	canvas.draw_texture_rect(texture, rect, false, tint)
	return true


## Key cells (×2) keep a gold frame on top of their building, so they stay easy to spot.
func _draw_key_frames() -> void:
	for cell in _board.get_all_cells():
		if cell.is_key:
			_draw_key_frame(_cell_rect(cell.coord))


func _draw_key_frame(rect: Rect2) -> void:
	var frame := GameArt.key_frame()
	if frame != null:
		draw_texture_rect(frame, rect, false)
	else:
		draw_rect(rect.grow(-1), KEY_MARKER_COLOR, false, 2.0)


## Gold diamond over a key cell. Static so piece cards can share it.
static func draw_key_marker(canvas: CanvasItem, rect: Rect2) -> void:
	var texture := GameArt.key_marker()
	if texture != null:
		canvas.draw_texture_rect(texture, rect, false)
		return
	var c := rect.get_center()
	var r := rect.size.x * 0.22
	var points := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
	canvas.draw_colored_polygon(points, KEY_MARKER_COLOR)


func _terrain_color(terrain_id: StringName) -> Color:
	var terrain := get_terrain(terrain_id)
	return terrain.color if terrain != null else Color.MAGENTA


## Draws an edge wherever an owned cell touches a non-owned cell or the board edge.
func _draw_territory_border() -> void:
	for cell in _board.get_all_cells():
		if not cell.owned:
			continue
		var top_left := cell_to_local(cell.coord)
		var corners := [
			top_left,
			top_left + Vector2(TILE_SIZE, 0),
			top_left + Vector2(TILE_SIZE, TILE_SIZE),
			top_left + Vector2(0, TILE_SIZE),
		]
		# NEIGHBOR_OFFSETS order is up, right, down, left, matching corner pairs (i, i+1).
		for i in BoardData.NEIGHBOR_OFFSETS.size():
			var neighbor := _board.get_cell(cell.coord + BoardData.NEIGHBOR_OFFSETS[i])
			if neighbor == null or not neighbor.owned:
				draw_line(corners[i], corners[(i + 1) % 4], TERRITORY_SHADOW_COLOR, 4.0)
				draw_line(corners[i], corners[(i + 1) % 4], TERRITORY_BORDER_COLOR, 2.0)


func _draw_buildings() -> void:
	for cell in _board.get_all_cells():
		if not cell.has_building() or cell.coord != cell.building_origin:
			continue
		var bounds := _cell_rect(cell.coord)
		for covered in _board.get_building_cells(cell.building_origin):
			bounds = bounds.merge(_cell_rect(covered.coord))
		var is_castle := cell.building_id == BoardData.CASTLE_ID
		var texture := GameArt.castle(castle_level, team_color) if is_castle else GameArt.building(cell.building_id)
		var building: BuildingData = _buildings.get(cell.building_id)
		var turns := castle_turns if is_castle else cell.building_turns
		var new_building := turns > 0 and not is_castle and not cell.building_upgrading
		var cells := Vector2i((bounds.size / TILE_SIZE).round())
		if new_building:
			_tile_over(cell.building_origin, GameArt.construction("foundation"))
		elif texture != null:
			var rect := art_rect(cell.building_origin, cells, texture.get_size())
			var tint := Color(1, 1, 1, UPGRADING_ALPHA) if turns > 0 else Color.WHITE
			if cell.disabled_turns > 0:
				tint = DISABLED_TINT
			var anim: Texture2D = null
			if animate and turns == 0 and cell.disabled_turns == 0:
				anim = GameArt.castle_anim(castle_level, team_color) if is_castle else GameArt.building_anim(cell.building_id)
			if anim != null:
				_draw_frame(anim, rect, _anim_frame, tint)
			else:
				draw_texture_rect(texture, rect, false, tint)
		else:
			draw_rect(bounds.grow(-8), building.color if building != null else Color.WHITE)
		if turns > 0:
			_draw_scaffold(cell.building_origin, cells)


## Frame `frame` of a strip of GameArt.BUILDING_ANIM_FRAMES frames, stretched over `rect`.
func _draw_frame(strip: Texture2D, rect: Rect2, frame: int, tint: Color = Color.WHITE) -> void:
	var size := Vector2(strip.get_width() / float(GameArt.BUILDING_ANIM_FRAMES), strip.get_height())
	draw_texture_rect_region(strip, rect, Rect2(Vector2(size.x * frame, 0), size), tint)


## Scaffolding (with a builder hammering away, M13c) over a construction's picture: one 32 px
## piece per cell it covers.
func _draw_scaffold(origin: Vector2i, cells: Vector2i) -> void:
	var still := GameArt.construction("scaffold")
	if still == null:
		return
	var anim := GameArt.construction("scaffold_anim") if animate else null
	var area := art_rect(origin, cells, Vector2(cells * 16))
	var piece := area.size / Vector2(cells)
	for y in cells.y:
		for x in cells.x:
			var rect := Rect2(area.position + piece * Vector2(x, y), piece)
			if anim != null:
				# Neighboring pieces hammer out of step.
				_draw_frame(anim, rect, (_anim_frame + x + y) % GameArt.BUILDING_ANIM_FRAMES)
			else:
				draw_texture_rect(still, rect, false)


## `texture` drawn on every cell of the building at `origin`.
func _tile_over(origin: Vector2i, texture: Texture2D) -> void:
	if texture == null:
		return
	for covered in _board.get_building_cells(origin):
		draw_texture_rect(texture, _cell_rect(covered.coord), false)


## Each production building's level on a small plate in its bottom-right corner, and the turns
## a construction still needs in its top-left corner, drawn on `_badges` so neither the key cell
## frames nor the walkers ever hide them.
func _draw_level_badges() -> void:
	if _board == null:
		return
	for cell in _board.get_all_cells():
		if not cell.has_building() or cell.coord != cell.building_origin:
			continue
		var turns := castle_turns if cell.building_id == BoardData.CASTLE_ID else cell.building_turns
		if turns == 0:
			turns = cell.disabled_turns  # idle after a war event: turns until it works again
		var plate := GameArt.turns_badge(turns) if turns > 0 else null
		if plate != null:
			_badges.draw_texture_rect(plate, Rect2(_cell_rect(cell.coord).position + Vector2(3, 3),
					plate.get_size() * GameArt.ART_SCALE), false)
		if cell.is_constructing() and not cell.building_upgrading:
			continue
		var building: BuildingData = _buildings.get(cell.building_id)
		var badge := GameArt.level_badge(cell.building_level)
		if building == null or not building.is_upgradable() or badge == null:
			continue
		var badge_size := badge.get_size() * GameArt.ART_SCALE
		var bounds := _cell_rect(cell.coord)
		_badges.draw_texture_rect(badge, Rect2(bounds.end - badge_size - Vector2(3, 3), badge_size), false)


func _draw_coords() -> void:
	var font := ThemeDB.fallback_font
	for cell in _board.get_all_cells():
		var pos := cell_to_local(cell.coord) + Vector2(2, COORD_FONT_SIZE + 1)
		draw_string(font, pos, "%d,%d" % [cell.coord.x, cell.coord.y],
				HORIZONTAL_ALIGNMENT_LEFT, -1, COORD_FONT_SIZE, COORD_TEXT_COLOR)


func _cell_rect(coord: Vector2i) -> Rect2:
	return Rect2(cell_to_local(coord), Vector2(TILE_SIZE, TILE_SIZE))
