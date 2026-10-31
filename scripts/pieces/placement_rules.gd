class_name PlacementRules
extends RefCounted
## Decides whether a land piece may be placed, and places it.
## Rules (GDD §4):
## - every cell must be on the board;
## - no cell may cover a building (the castle included);
## - the piece must overlap or edge-touch the player's territory.
## Overlapping existing land replaces its terrain and key cell.

enum Result { OK, OUT_OF_BOUNDS, ON_BUILDING, NOT_CONNECTED, REBELS }


static func check(board: BoardData, piece: LandPiece, origin: Vector2i) -> Result:
	var coords := piece.get_board_coords(origin)
	for coord in coords:
		if not board.is_in_bounds(coord):
			return Result.OUT_OF_BOUNDS
	for coord in coords:
		if board.get_cell(coord).has_building():
			return Result.ON_BUILDING
		if board.get_cell(coord).occupied:
			return Result.REBELS
	if not _touches_territory(board, coords):
		return Result.NOT_CONNECTED
	return Result.OK


## Places the piece only when check() is OK; otherwise the board is left untouched.
static func apply(board: BoardData, piece: LandPiece, origin: Vector2i) -> Result:
	var result := check(board, piece, origin)
	if result != Result.OK:
		return result
	var coords := piece.get_board_coords(origin)
	for i in coords.size():
		board.set_land(coords[i], piece.terrains[i], piece.is_key_cell(i))
	return Result.OK


static func describe(result: Result) -> String:
	match result:
		Result.OK:
			return "Có thể đặt ở đây."
		Result.OUT_OF_BOUNDS:
			return "Mảnh đất nằm ngoài bản đồ."
		Result.ON_BUILDING:
			return "Không thể đặt đè lên công trình."
		Result.NOT_CONNECTED:
			return "Mảnh đất phải chạm cạnh hoặc đè lên lãnh thổ."
		Result.REBELS:
			return "Vùng này đang bị quân nổi loạn chiếm: thảo phạt trước đã."
	return ""


static func _touches_territory(board: BoardData, coords: Array[Vector2i]) -> bool:
	for coord in coords:
		if board.get_cell(coord).owned:
			return true
		for neighbor in board.get_neighbors(coord):
			if neighbor.owned:
				return true
	return false
