class_name UprisingView
extends Node2D
## The uprising zone on the board (GDD §15 M14i): its cells pulse red, an outline marks its edge
## and a few bandits stand in it; while an expedition is on the way, one of the kingdom's soldiers
## faces them. A child of the BoardView, above the walkers. Tapping the zone is handled by the
## kingdom scene (ExpeditionWindow). Read-only.

const FILL := Color(0.85, 0.1, 0.06)
const MIN_ALPHA := 0.18
const MAX_ALPHA := 0.42
const PULSE_SPEED := 4.0
const EDGE := Color(0.95, 0.15, 0.1, 0.9)
const EDGE_WIDTH := 3.0
const SPRITE_SCALE := 2.0
const BANDIT_SPRITE: StringName = &"bandit_thug"
const SOLDIER_SPRITE: StringName = &"swordsman"
const ANIM_FPS := 3.0

var _state: KingdomState


func setup(state: KingdomState) -> void:
	_state = state


func _process(_delta: float) -> void:
	if _state != null and (_state.uprising.is_active() or visible):
		visible = _state.uprising.is_active()
		queue_redraw()


func _draw() -> void:
	if _state == null or not _state.uprising.is_active():
		return
	var cells := _state.uprising.cells
	var seconds := Time.get_ticks_msec() / 1000.0
	var alpha := lerpf(MIN_ALPHA, MAX_ALPHA, 0.5 + 0.5 * sin(seconds * PULSE_SPEED))
	var tile := Vector2.ONE * BoardView.TILE_SIZE
	for coord in cells:
		draw_rect(Rect2(BoardView.cell_to_local(coord), tile), Color(FILL, alpha))
	for coord in cells:
		var at := BoardView.cell_to_local(coord)
		for side: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			if cells.has(coord + side):
				continue
			var a := at + Vector2(maxi(side.x, 0), maxi(side.y, 0)) * tile
			var b := a + (Vector2(0, tile.y) if side.x != 0 else Vector2(tile.x, 0))
			draw_line(a, b, EDGE, EDGE_WIDTH)
	var frame := int(seconds * ANIM_FPS) % GameArt.UNIT_FRAMES
	var bandit_tints := GameArt.unit_tints(RaidSystem.BANDIT_COLOR)
	for index in [cells.size() / 2, 0, cells.size() - 1]:
		var foot := BoardView.cell_to_local(cells[index]) + Vector2(tile.x * 0.5, tile.y * 0.85)
		GameArt.draw_unit(self, BANDIT_SPRITE, foot, 0.0, Vector2(-SPRITE_SCALE, SPRITE_SCALE), &"stand", frame,
				bandit_tints)
	if _state.expedition != null:
		var foot := BoardView.cell_to_local(cells[0]) + Vector2(tile.x * 0.15, tile.y * 0.85)
		GameArt.draw_unit(self, SOLDIER_SPRITE, foot, 0.0, Vector2(SPRITE_SCALE, SPRITE_SCALE), &"attack", frame,
				GameArt.unit_tints(_state.player_color))
