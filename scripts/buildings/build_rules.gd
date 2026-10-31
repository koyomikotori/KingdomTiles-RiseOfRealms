class_name BuildRules
extends RefCounted
## Decides whether a building may be constructed, and constructs it (paying its cost).

enum Result { OK, OUT_OF_BOUNDS, NOT_OWNED, OCCUPIED, WRONG_TERRAIN, LIMIT_REACHED, CANNOT_AFFORD, CASTLE_TOO_LOW,
		NO_BUILDERS, UNDER_CONSTRUCTION, REBELS }

## Each castle level above the one a building needs allows this many more of it (GDD §8,
## economy v2; M14e counts from BuildingData.required_castle_level).
const EXTRA_PER_CASTLE_LEVEL := 1


## How many of this building the kingdom may have at this castle level; 0 = unlimited.
static func limit(building: BuildingData, castle_level: int) -> int:
	if building.max_count <= 0:
		return 0
	if building.fixed_count:
		return building.max_count
	var most := building.max_count + EXTRA_PER_CASTLE_LEVEL * maxi(0, castle_level - maxi(1, building.required_castle_level))
	return mini(most, building.max_limit) if building.max_limit > 0 else most


## Whether another one may be built at all (castle level, limit, builders), wherever it goes.
static func check_type(board: BoardData, building: BuildingData, castle_level: int = 1,
		builders_free: bool = true) -> Result:
	if castle_level < building.required_castle_level:
		return Result.CASTLE_TOO_LOW
	var most := limit(building, castle_level)
	if most > 0 and board.count_buildings(building.building_id, true) >= most:
		return Result.LIMIT_REACHED
	if not builders_free:
		return Result.NO_BUILDERS
	return Result.OK


## `cost`: what building it costs right now (KingdomState.building_cost); empty = building.cost.
## `builders_free`: a builder team is free to lay the foundation (KingdomState.has_free_builder).
static func check(board: BoardData, stockpile: Stockpile, building: BuildingData, origin: Vector2i,
		castle_level: int = 1, cost: Dictionary[StringName, int] = {}, builders_free: bool = true) -> Result:
	if castle_level < building.required_castle_level:
		return Result.CASTLE_TOO_LOW
	for y in building.size.y:
		for x in building.size.x:
			var cell := board.get_cell(origin + Vector2i(x, y))
			if cell == null:
				return Result.OUT_OF_BOUNDS
			if not cell.owned:
				return Result.NOT_OWNED
			if cell.has_building():
				return Result.OCCUPIED
			if cell.occupied:
				return Result.REBELS
			if not building.allowed_terrains.is_empty() and not building.allowed_terrains.has(cell.terrain_id):
				return Result.WRONG_TERRAIN
	var type_result := check_type(board, building, castle_level, builders_free)
	if type_result != Result.OK:
		return type_result
	if not stockpile.can_afford(building.cost if cost.is_empty() else cost):
		return Result.CANNOT_AFFORD
	return Result.OK


## Whether the building whose origin is `from_origin` may move to `to_origin`: the same rules as
## building it there (but no cost), with its own current cells counting as free.
static func check_move(board: BoardData, building: BuildingData, from_origin: Vector2i, to_origin: Vector2i) -> Result:
	if to_origin == from_origin:
		return Result.OCCUPIED
	for y in building.size.y:
		for x in building.size.x:
			var cell := board.get_cell(to_origin + Vector2i(x, y))
			if cell == null:
				return Result.OUT_OF_BOUNDS
			if not cell.owned:
				return Result.NOT_OWNED
			if cell.has_building() and cell.building_origin != from_origin:
				return Result.OCCUPIED
			if cell.occupied or board.get_cell(from_origin).occupied:
				return Result.REBELS
			if not building.allowed_terrains.is_empty() and not building.allowed_terrains.has(cell.terrain_id):
				return Result.WRONG_TERRAIN
	return Result.OK


## Lays the foundation only when check() is OK; otherwise nothing changes and nothing is paid.
## The building is finished after building.build_turns turns (GDD §8, M12d).
static func apply(board: BoardData, stockpile: Stockpile, building: BuildingData, origin: Vector2i,
		castle_level: int = 1, cost: Dictionary[StringName, int] = {}, builders_free: bool = true) -> Result:
	var result := check(board, stockpile, building, origin, castle_level, cost, builders_free)
	if result != Result.OK:
		return result
	board.place_building(building.building_id, origin, building.size)
	board.set_construction(origin, maxi(1, building.build_turns))
	stockpile.spend(building.cost if cost.is_empty() else cost)
	return Result.OK


static func describe(result: Result) -> String:
	match result:
		Result.OK:
			return "Có thể xây ở đây."
		Result.OUT_OF_BOUNDS:
			return "Công trình nằm ngoài bản đồ."
		Result.NOT_OWNED:
			return "Chỉ xây được trong lãnh thổ."
		Result.OCCUPIED:
			return "Ô này đã có công trình."
		Result.WRONG_TERRAIN:
			return "Không xây được trên địa hình này."
		Result.LIMIT_REACHED:
			return "Đã đạt số lượng tối đa của công trình này."
		Result.CANNOT_AFFORD:
			return "Không đủ tài nguyên."
		Result.CASTLE_TOO_LOW:
			return "Cần nâng cấp thành chính."
		Result.NO_BUILDERS:
			return "Không còn đội thợ rảnh: chờ một công trình xây xong."
		Result.REBELS:
			return "Vùng này đang bị quân nổi loạn chiếm: thảo phạt trước đã."
		Result.UNDER_CONSTRUCTION:
			return "Công trình đang thi công."
	return ""
