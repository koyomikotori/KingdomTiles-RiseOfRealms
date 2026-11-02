class_name OfficerFigure
extends Control
## An officer's (or a unit's) battle sprite standing (and breathing) in lists: the same picture as on the
## battlefield (GameArt.officer_sprite). Read-only.

## Idle animation speed (frames per second).
const FPS := 2.0

var art_scale := 2
var _sprite_id: StringName
var _tints: Dictionary = {}
var _frame := 0
## The officer's stars: their sprite's tier and the 5–6★ aura (GameArt.draw_aura); 0 for units.
var _stars := 0


func setup(officer: Officer, scale: int = 2, team: Color = KingdomState.shown_color) -> void:
	art_scale = scale
	var kind := BattleView.ADVISOR_KIND if officer is Advisor else BattleView.GENERAL_KIND
	_stars = officer.stars
	_sprite_id = GameArt.officer_sprite(kind, officer.look, (officer as General).weapon_type() if officer is General else &"",
			_stars)
	if officer is Ruler:
		_stars = 0
		_sprite_id = GameArt.ruler_sprite(officer)
	_tints = GameArt.unit_tints(team, officer.look)
	_fit()


## A soldier of this unit type instead (the recruit window, GDD §8 M12d).
func setup_unit(unit: UnitData, scale: int = 2, team: Color = KingdomState.shown_color) -> void:
	art_scale = scale
	_sprite_id = unit.get_sprite_id()
	_stars = 0
	_tints = GameArt.unit_tints(team)
	_fit()


func _fit() -> void:
	var sheet := GameArt.unit_sheet(_sprite_id)
	var frame_size := GameArt.unit_frame(sheet, &"stand", 0, GameArt.frames_of(_sprite_id)).size if sheet != null else Vector2(16, 16)
	custom_minimum_size = frame_size * art_scale
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _process(_delta: float) -> void:
	var frame := GameArt.anim_frame(_sprite_id, Time.get_ticks_msec() / 1000.0 * FPS)
	if _stars >= GameArt.AURA_MIN_STARS:
		queue_redraw()
	if frame != _frame:
		_frame = frame
		queue_redraw()


func _draw() -> void:
	if _sprite_id != &"":
		var foot := Vector2(size.x * 0.5, size.y)
		var time := Time.get_ticks_msec() / 1000.0
		GameArt.draw_aura(self, _sprite_id, foot, art_scale, _stars, time)
		GameArt.draw_unit(self, _sprite_id, foot, 0.0, Vector2.ONE * art_scale, &"stand", _frame, _tints)
		GameArt.draw_aura_sparks(self, _sprite_id, foot, art_scale, _stars, time)
