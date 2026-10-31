class_name BoardData
extends RefCounted
## Authoritative grid state. Knows nothing about rendering.
## Coordinates: Vector2i(x, y), x grows right, y grows down, (0, 0) is the top-left cell.

signal cell_changed(coord: Vector2i)
## The board grew (see expand). `shift` is how far existing coordinates moved.
signal resized(shift: Vector2i)

const CASTLE_ID: StringName = &"castle"
const NEIGHBOR_OFFSETS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var width: int
var height: int
var _cells: Array[CellData] = []


func _init(p_width: int, p_height: int) -> void:
	assert(p_width > 0 and p_height > 0, "Board size must be positive")
	width = p_width
	height = p_height
	for y in height:
		for x in width:
			_cells.append(CellData.new(Vector2i(x, y)))


## Creates a square board with a castle in the middle and a ring of owned grass around it.
static func create_starting_board(size: int, castle_size: int = 2, start_margin: int = 1) -> BoardData:
	var board := BoardData.new(size, size)
	var castle_origin := Vector2i((size - castle_size) / 2, (size - castle_size) / 2)
	var start_area := Rect2i(castle_origin, Vector2i(castle_size, castle_size)).grow(start_margin)
	for y in range(start_area.position.y, start_area.end.y):
		for x in range(start_area.position.x, start_area.end.x):
			var coord := Vector2i(x, y)
			if board.is_in_bounds(coord):
				board.set_terrain(coord, &"grass")
				board.set_owned(coord, true)
	var placed := board.place_building(CASTLE_ID, castle_origin, Vector2i(castle_size, castle_size))
	assert(placed, "Castle must fit on the starting board")
	return board


func is_in_bounds(coord: Vector2i) -> bool:
	return coord.x >= 0 and coord.y >= 0 and coord.x < width and coord.y < height


## Returns null for coordinates outside the board.
func get_cell(coord: Vector2i) -> CellData:
	if not is_in_bounds(coord):
		return null
	return _cells[coord.y * width + coord.x]


func get_all_cells() -> Array[CellData]:
	return _cells


## Edge-adjacent cells only (no diagonals), skipping cells outside the board.
func get_neighbors(coord: Vector2i) -> Array[CellData]:
	var result: Array[CellData] = []
	for offset in NEIGHBOR_OFFSETS:
		var cell := get_cell(coord + offset)
		if cell != null:
			result.append(cell)
	return result


func set_terrain(coord: Vector2i, terrain_id: StringName) -> void:
	var cell := get_cell(coord)
	if cell == null or cell.terrain_id == terrain_id:
		return
	cell.terrain_id = terrain_id
	cell_changed.emit(coord)


func set_owned(coord: Vector2i, owned: bool) -> void:
	var cell := get_cell(coord)
	if cell == null or cell.owned == owned:
		return
	cell.owned = owned
	cell_changed.emit(coord)


## Claims a cell with new land, replacing whatever terrain and key cell it had.
## Validation is the caller's job (see PlacementRules).
func set_land(coord: Vector2i, terrain_id: StringName, is_key: bool) -> void:
	var cell := get_cell(coord)
	if cell == null:
		return
	cell.terrain_id = terrain_id
	cell.is_key = is_key
	cell.owned = true
	cell_changed.emit(coord)


## A building fits when every cell is on the board, owned and free of other buildings.
func can_place_building(origin: Vector2i, size: Vector2i) -> bool:
	if size.x <= 0 or size.y <= 0:
		return false
	for coord in _rect_coords(Rect2i(origin, size)):
		var cell := get_cell(coord)
		if cell == null or not cell.owned or cell.has_building():
			return false
	return true


## Returns false and leaves the board untouched when the building does not fit.
func place_building(building_id: StringName, origin: Vector2i, size: Vector2i) -> bool:
	if not can_place_building(origin, size):
		return false
	for coord in _rect_coords(Rect2i(origin, size)):
		var cell := get_cell(coord)
		cell.building_id = building_id
		cell.building_origin = origin
		cell.building_level = 1
		cell.building_turns = 0
		cell.building_upgrading = false
		cell_changed.emit(coord)
	return true


func get_building_level(origin: Vector2i) -> int:
	var cell := get_cell(origin)
	return cell.building_level if cell != null and cell.has_building() else 0


func set_building_level(origin: Vector2i, level: int) -> void:
	for cell in get_building_cells(origin):
		cell.building_level = level
		cell_changed.emit(cell.coord)


## Starts (turns > 0) or ends (0) the construction of the building at `origin` (GDD §8, M12d).
func set_construction(origin: Vector2i, turns: int, upgrading: bool = false) -> void:
	for cell in get_building_cells(origin):
		cell.building_turns = turns
		cell.building_upgrading = upgrading and turns > 0
		cell_changed.emit(cell.coord)


## Top-left cells of every building under construction.
func get_construction_origins() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in _cells:
		if cell.is_constructing() and cell.coord == cell.building_origin:
			result.append(cell.coord)
	return result


## All cells covered by the building whose top-left cell is `origin`.
func get_building_cells(origin: Vector2i) -> Array[CellData]:
	var result: Array[CellData] = []
	for cell in _cells:
		if cell.has_building() and cell.building_origin == origin:
			result.append(cell)
	return result


func count_owned_cells() -> int:
	var count := 0
	for cell in _cells:
		if cell.owned:
			count += 1
	return count


## Owned cells that are not part of the castle (the land an invasion can still take).
func count_land_outside_castle() -> int:
	var count := 0
	for cell in _cells:
		if cell.owned and cell.building_id != CASTLE_ID:
			count += 1
	return count


func count_owned_terrain(terrain_id: StringName) -> int:
	var count := 0
	for cell in _cells:
		if cell.owned and cell.terrain_id == terrain_id:
			count += 1
	return count


## Number of separate buildings of this type (counted by their top-left cell). Buildings still
## being built do nothing, so they count only with `include_unfinished` (limits do).
func count_buildings(building_id: StringName, include_unfinished: bool = false) -> int:
	var count := 0
	for cell in _cells:
		if cell.building_id == building_id and cell.coord == cell.building_origin:
			if include_unfinished or not cell.is_idle():
				count += 1
	return count


## The level of the highest-level finished building of this type (one being upgraded keeps
## working at its level only once the upgrade is done), 0 without one.
func highest_building_level(building_id: StringName) -> int:
	var best := 0
	for cell in _cells:
		if cell.building_id == building_id and cell.coord == cell.building_origin and not cell.is_idle():
			best = maxi(best, cell.building_level)
	return best


func _rect_coords(rect: Rect2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			result.append(Vector2i(x, y))
	return result


## Removes a whole building (every cell it covers). The castle cannot be removed.
func remove_building(origin: Vector2i) -> void:
	for cell in get_building_cells(origin):
		if cell.building_id == CASTLE_ID:
			return
		cell.building_id = CellData.NO_BUILDING
		cell_changed.emit(cell.coord)


## Loses up to `max_cells` owned cells closest to the board edge in `direction`
## (Vector2i.UP = north edge, …): they turn back into wild land and any building on them is
## destroyed. Castle cells are never lost. Returns the lost coordinates.
func lose_edge_cells(direction: Vector2i, max_cells: int) -> Array[Vector2i]:
	var candidates: Array[CellData] = []
	for cell in _cells:
		if cell.owned and cell.building_id != CASTLE_ID:
			candidates.append(cell)
	var distance := func(cell: CellData) -> int:
		match direction:
			Vector2i.UP:
				return cell.coord.y
			Vector2i.DOWN:
				return height - 1 - cell.coord.y
			Vector2i.LEFT:
				return cell.coord.x
			_:
				return width - 1 - cell.coord.x
	# Closest to the edge first; ties broken by position so the result is always the same.
	candidates.sort_custom(func(a: CellData, b: CellData) -> bool:
		var da: int = distance.call(a)
		var db: int = distance.call(b)
		if da != db:
			return da < db
		return a.coord.x + a.coord.y * width < b.coord.x + b.coord.y * width)
	var lost: Array[Vector2i] = []
	for cell in candidates.slice(0, max_cells):
		if cell.has_building():
			remove_building(cell.building_origin)
		cell.owned = false
		cell.terrain_id = CellData.NO_TERRAIN
		cell.is_key = false
		lost.append(cell.coord)
		cell_changed.emit(cell.coord)
	return lost


## Grows the board by `amount` rows or columns of wild land on the `direction` side
## (Vector2i.UP adds rows at the top, …). Existing cells keep their contents; when growing up or
## left their coordinates shift, which `resized` reports.
func expand(direction: Vector2i, amount: int) -> void:
	var shift := Vector2i(amount if direction == Vector2i.LEFT else 0, amount if direction == Vector2i.UP else 0)
	var new_width := width + (amount if direction.x != 0 else 0)
	var new_height := height + (amount if direction.y != 0 else 0)
	var old_cells := _cells
	_cells = []
	for y in new_height:
		for x in new_width:
			_cells.append(CellData.new(Vector2i(x, y)))
	width = new_width
	height = new_height
	for old in old_cells:
		var cell := get_cell(old.coord + shift)
		cell.terrain_id = old.terrain_id
		cell.owned = old.owned
		cell.is_key = old.is_key
		cell.building_id = old.building_id
		cell.building_origin = old.building_origin + shift
		cell.building_level = old.building_level
		cell.building_turns = old.building_turns
		cell.building_upgrading = old.building_upgrading
		cell.occupied = old.occupied
	resized.emit(shift)


# --- Save (GDD §10.1) ---------------------------------------------------------------------

## Size plus every cell that is not plain wild land.
func to_save() -> Dictionary:
	var cells: Array = []
	for cell in _cells:
		if cell.has_terrain() or cell.owned or cell.is_key or cell.has_building():
			cells.append({"x": cell.coord.x, "y": cell.coord.y, "terrain": String(cell.terrain_id), "owned": cell.owned,
					"key": cell.is_key, "building": String(cell.building_id),
					"origin": [cell.building_origin.x, cell.building_origin.y], "level": cell.building_level,
					"turns": cell.building_turns, "upgrading": cell.building_upgrading})
	return {"width": width, "height": height, "cells": cells}


static func from_save(data: Dictionary) -> BoardData:
	var board := BoardData.new(int(data.width), int(data.height))
	for entry: Dictionary in data.cells:
		var cell := board.get_cell(Vector2i(int(entry.x), int(entry.y)))
		if cell == null:
			continue
		cell.terrain_id = StringName(entry.terrain)
		cell.owned = bool(entry.owned)
		cell.is_key = bool(entry.key)
		cell.building_id = StringName(entry.building)
		cell.building_origin = Vector2i(int(entry.origin[0]), int(entry.origin[1]))
		cell.building_level = int(entry.level)
		# Saves from before M12d have no construction: everything there is finished.
		cell.building_turns = int(entry.get("turns", 0))
		cell.building_upgrading = bool(entry.get("upgrading", false))
	return board
