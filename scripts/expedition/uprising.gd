class_name Uprising
extends RefCounted
## The bandit and rebel zone on the kingdom's own land (GDD §15, M14i), owned by KingdomState.
## From FIRST_TURN on, with no zone and the cooldown over, each turn has SPAWN_CHANCE to start one:
## a 3×3 block of owned land near the territory's edge (never the castle). Its buildings stop
## working and its cells are locked (CellData.occupied: no land placed, nothing built, upgraded or
## moved). Every GROW_TURNS turns without an expedition on the way it spreads one cell further in
## every direction it can (owned land, not the castle), until it touches the castle. Cleared by an
## Expedition; the next zone waits COOLDOWN_TURNS turns. Own random numbers (seed + 6).

const FIRST_TURN := 8
const SPAWN_CHANCE := 0.1
const GROW_TURNS := 2
const COOLDOWN_TURNS := 5
const START_RADIUS := 1
const ALL_AROUND: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
		Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]

var cells: Array[Vector2i] = []
## Turns since the zone last spread.
var grow_timer := 0
## No new zone before this turn.
var next_allowed_turn := FIRST_TURN
## Zones cleared so far: later expeditions meet more and stronger bandits.
var cleared := 0
var rng := RandomNumberGenerator.new()


func is_active() -> bool:
	return not cells.is_empty()


func covers(coord: Vector2i) -> bool:
	return cells.has(coord)


## The zone's size against its first 3×3 (1.0 … more): rewards and enemies grow with it.
func size_factor() -> float:
	return maxf(1.0, cells.size() / 9.0)


## End of a turn (after the board changed): drops cells lost meanwhile, maybe spreads (not while
## `paused`, an expedition on its way) or starts a zone. Returns &"started", &"spread" or &"".
func end_turn(board: BoardData, turn: int, paused: bool) -> StringName:
	_keep_owned(board)
	if is_active():
		if paused:
			return &""
		grow_timer += 1
		if grow_timer >= GROW_TURNS:
			grow_timer = 0
			if spread(board):
				return &"spread"
		return &""
	if turn >= next_allowed_turn and rng.randf() < SPAWN_CHANCE:
		return &"started" if start(board) else &""
	return &""


## Starts a zone whose 3×3 touches the territory's edge (picked at random among those that hold
## the most land). False when there is no room for one.
func start(board: BoardData) -> bool:
	var best := 0
	var picks: Array[Vector2i] = []
	for cell in board.get_all_cells():
		if not _takeable(board, cell.coord):
			continue
		var block := _around(board, cell.coord, START_RADIUS)
		if not block.any(func(coord: Vector2i) -> bool: return _on_edge(board, coord)):
			continue
		var count := block.size()
		if count > best:
			best = count
			picks.clear()
		if count == best:
			picks.append(cell.coord)
	if picks.is_empty():
		return false
	var center := picks[rng.randi_range(0, picks.size() - 1)]
	cells = _around(board, center, START_RADIUS)
	grow_timer = 0
	apply(board)
	return true


## One cell further in every direction it can go; stops once the zone touches the castle.
## Returns whether it grew.
func spread(board: BoardData) -> bool:
	if touches_castle(board):
		return false
	var added: Array[Vector2i] = []
	for coord in cells:
		for offset in ALL_AROUND:
			var next := coord + offset
			if not cells.has(next) and not added.has(next) and _takeable(board, next):
				added.append(next)
	if added.is_empty():
		return false
	cells.append_array(added)
	apply(board)
	return true


func touches_castle(board: BoardData) -> bool:
	for coord in cells:
		for offset in ALL_AROUND:
			var cell := board.get_cell(coord + offset)
			if cell != null and cell.building_id == BoardData.CASTLE_ID:
				return true
	return false


## The expedition won: the land is free again.
func clear(board: BoardData, turn: int) -> void:
	cells.clear()
	cleared += 1
	next_allowed_turn = turn + COOLDOWN_TURNS
	apply(board)


## Marks the zone's cells on the board (CellData.occupied), and only those.
func apply(board: BoardData) -> void:
	for cell in board.get_all_cells():
		cell.occupied = cells.has(cell.coord)


## The board grew on its top or left side: every coordinate moves by `shift`.
func shift(board: BoardData, offset: Vector2i) -> void:
	for i in cells.size():
		cells[i] += offset
	apply(board)


func _keep_owned(board: BoardData) -> void:
	cells = cells.filter(func(coord: Vector2i) -> bool: return _takeable(board, coord))
	apply(board)


func _takeable(board: BoardData, coord: Vector2i) -> bool:
	var cell := board.get_cell(coord)
	return cell != null and cell.owned and cell.building_id != BoardData.CASTLE_ID


func _on_edge(board: BoardData, coord: Vector2i) -> bool:
	for offset in ALL_AROUND:
		var cell := board.get_cell(coord + offset)
		if cell == null or not cell.owned:
			return true
	return false


func _around(board: BoardData, center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if _takeable(board, center + Vector2i(x, y)):
				result.append(center + Vector2i(x, y))
	return result


# --- Save (GDD §10.1) ---------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"cells": cells.map(func(c: Vector2i) -> Array: return [c.x, c.y]), "grow_timer": grow_timer,
			"next_allowed_turn": next_allowed_turn, "cleared": cleared}


func load_save(data: Dictionary, board: BoardData) -> void:
	cells.clear()
	for pair: Array in data.get("cells", []):
		cells.append(Vector2i(int(pair[0]), int(pair[1])))
	grow_timer = int(data.get("grow_timer", 0))
	next_allowed_turn = int(data.get("next_allowed_turn", FIRST_TURN))
	cleared = int(data.get("cleared", 0))
	apply(board)
