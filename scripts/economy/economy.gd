class_name Economy
extends RefCounted
## Per-turn production. Economy v2 (GDD §8): only production buildings produce, by level
## (BuildingData.yields_at); terrain `yields` are empty in the data now but still counted if set.
## Key cells double both. Fields (M14d): a production building also takes FIELD_YIELD of its
## BuildingData.field_resource from each owned, empty neighbor cell (the 8 around it) of its allowed
## terrain, doubled on a key cell; a cell next to two such buildings feeds both. Its own cell makes
## OWN_CELL_PENALTY less of that resource. Amount dictionaries map resource_id -> int.

const KEY_CELL_MULTIPLIER := 2
const FIELD_YIELD := 2
const OWN_CELL_PENALTY := 1


static func cell_yield(terrain: TerrainData, is_key: bool) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	if terrain == null:
		return result
	var multiplier := KEY_CELL_MULTIPLIER if is_key else 1
	for resource_id in terrain.yields:
		result[resource_id] = terrain.yields[resource_id] * multiplier
	return result


## Total produced by the player's territory in one turn.
static func board_yield(board: BoardData, terrains: Dictionary[StringName, TerrainData]) -> Dictionary[StringName, int]:
	var total: Dictionary[StringName, int] = {}
	for cell in board.get_all_cells():
		if cell.owned:
			add_into(total, cell_yield(terrains.get(cell.terrain_id), cell.is_key))
	return total


## What one building of `level` produces on its own cell per turn (less OWN_CELL_PENALTY of its
## field resource), doubled when its origin cell is a key cell. Fields come on top (field_yield).
static func building_yield(building: BuildingData, on_key_cell: bool, level: int = 1) -> Dictionary[StringName, int]:
	var result := building.yields_at(level)
	if result.has(building.field_resource):
		result[building.field_resource] = maxi(0, result[building.field_resource] - OWN_CELL_PENALTY)
	if on_key_cell:
		for resource_id in result:
			result[resource_id] *= KEY_CELL_MULTIPLIER
	return result


## What the building whose origin is `origin` takes from its fields: FIELD_YIELD per owned, empty
## neighbor cell of its allowed terrain, doubled on key cells.
static func field_yield(board: BoardData, building: BuildingData, origin: Vector2i) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	if building.field_resource == &"":
		return result
	var amount := 0
	for coord in neighbor_coords(board, building, origin):
		var cell := board.get_cell(coord)
		amount += field_amount(building, cell.owned and not cell.has_building(), cell.terrain_id, cell.is_key)
	if amount > 0:
		result[building.field_resource] = amount
	return result


## What one cell gives a neighboring building with fields: FIELD_YIELD (doubled on a key cell) when
## it is usable (owned, no building on it) and of the building's terrain.
static func field_amount(building: BuildingData, usable: bool, terrain_id: StringName, is_key: bool) -> int:
	if not usable or building.field_resource == &"" or not building.allowed_terrains.has(terrain_id):
		return 0
	return FIELD_YIELD * (KEY_CELL_MULTIPLIER if is_key else 1)


## The cells in bounds around a building's footprint (the 8 around a 1×1 building).
static func neighbor_coords(board: BoardData, building: BuildingData, origin: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var footprint := Rect2i(origin, building.size)
	for y in range(origin.y - 1, origin.y + building.size.y + 1):
		for x in range(origin.x - 1, origin.x + building.size.x + 1):
			var coord := Vector2i(x, y)
			if not footprint.has_point(coord) and board.is_in_bounds(coord):
				result.append(coord)
	return result


## Everything a working building makes per turn: its own cell plus its fields.
static func production(board: BoardData, building: BuildingData, cell: CellData) -> Dictionary[StringName, int]:
	var result := building_yield(building, cell.is_key, cell.building_level)
	add_into(result, field_yield(board, building, cell.building_origin))
	return result


## The finished production buildings with fields next to `coord`: origin -> BuildingData.
static func field_buildings_around(board: BoardData, buildings: Dictionary[StringName, BuildingData],
		coord: Vector2i) -> Dictionary:
	var result := {}
	for y in range(coord.y - 1, coord.y + 2):
		for x in range(coord.x - 1, coord.x + 2):
			var near := Vector2i(x, y)
			if near == coord or not board.is_in_bounds(near):
				continue
			var cell := board.get_cell(near)
			if cell.has_building() and not cell.is_idle() and buildings.has(cell.building_id) \
					and buildings[cell.building_id].field_resource != &"":
				result[cell.building_origin] = buildings[cell.building_id]
	return result


## What a land cell gives the working buildings around it (shown in the cell info panel).
static func cell_field_yield(board: BoardData, buildings: Dictionary[StringName, BuildingData],
		coord: Vector2i) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	var cell := board.get_cell(coord)
	var around := field_buildings_around(board, buildings, coord)
	for building: BuildingData in around.values():
		var amount := field_amount(building, cell.owned and not cell.has_building(), cell.terrain_id, cell.is_key)
		if amount > 0:
			result[building.field_resource] = result.get(building.field_resource, 0) + amount
	return result


## Total produced by every production building in one turn (each counted once, at its origin,
## with its fields). Buildings under construction produce nothing (GDD §8, M12d).
static func buildings_yield(board: BoardData, buildings: Dictionary[StringName, BuildingData]) -> Dictionary[StringName, int]:
	var total: Dictionary[StringName, int] = {}
	for cell in board.get_all_cells():
		if cell.has_building() and cell.coord == cell.building_origin and buildings.has(cell.building_id) \
				and not cell.is_idle():
			add_into(total, production(board, buildings[cell.building_id], cell))
	return total


## How the per-turn yield would change if `piece` were placed at `origin`, fields included when
## `buildings` is given. Assumes the placement is valid (pieces never cover a building); covered
## cells lose their old yield.
static func placement_delta(board: BoardData, piece: LandPiece, origin: Vector2i,
		terrains: Dictionary[StringName, TerrainData],
		buildings: Dictionary[StringName, BuildingData] = {}) -> Dictionary[StringName, int]:
	var delta: Dictionary[StringName, int] = {}
	var coords := piece.get_board_coords(origin)
	for i in coords.size():
		var cell := board.get_cell(coords[i])
		if cell.owned:
			add_into(delta, cell_yield(terrains.get(cell.terrain_id), cell.is_key), -1)
		add_into(delta, cell_yield(terrains.get(piece.terrains[i]), piece.is_key_cell(i)))
		for building: BuildingData in field_buildings_around(board, buildings, coords[i]).values():
			var change := field_amount(building, true, piece.terrains[i], piece.is_key_cell(i)) \
					- field_amount(building, cell.owned, cell.terrain_id, cell.is_key)
			delta[building.field_resource] = delta.get(building.field_resource, 0) + change
	for resource_id in delta.keys():
		if delta[resource_id] == 0:
			delta.erase(resource_id)
	return delta


## Adds `amounts` (times `sign`) into `target` in place.
static func add_into(target: Dictionary[StringName, int], amounts: Dictionary[StringName, int], sign: int = 1) -> void:
	for resource_id in amounts:
		target[resource_id] = target.get(resource_id, 0) + amounts[resource_id] * sign
