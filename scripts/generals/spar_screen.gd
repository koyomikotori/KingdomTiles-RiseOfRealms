class_name SparScreen
extends Control
## The sparring mini game (GDD §26, M16j): a wandering fighter (left, Spar.rival) against one of the kingdom's
## generals (right, played by the player). Spar holds the rules; this screen runs the clock, reads
## the keys and draws the courtyard, both fighters on foot, the health bars, the strike bar and the
## dodge ring. When the match ends it pays the XP (KingdomState.finish_spar), shows the result with
## a counselor line and emits `finished` on "Xong".

signal finished(result: Dictionary)

const ART_SCALE := 5.0
## The rival's (unused) side color: their clothes are drawn in fixed colors.
const RIVAL_COLOR := Color(0.6, 0.6, 0.6)
## Seconds between the parts of a round (to read the hit), and before the first strike.
const PAUSE := 0.9
const INTRO := 1.2
## How long a fighter keeps the attack pose, and a dodge or knock-back lasts.
const POSE_TIME := 0.45
const DODGE_SHIFT := 70.0
const KNOCK_SHIFT := 26.0
const RING_START := 120.0
const RING_END := 26.0
const BAR_WIDTH_SHARE := 0.5
const BAR_HEIGHT := 34.0
const HP_BAR_SIZE := Vector2(360, 22)
const SKY := Color(0.62, 0.78, 0.86)
const WALL := Color(0.55, 0.47, 0.38)
const WALL_DARK := Color(0.42, 0.35, 0.28)
const ROOF := Color(0.55, 0.16, 0.12)
const GROUND := Color(0.76, 0.66, 0.48)
const GROUND_LINE := Color(0.68, 0.58, 0.41)
const MISS_COLOR := Color(0.45, 0.4, 0.35)
const GOOD_COLOR := Color(0.95, 0.75, 0.25)
const PERFECT_COLOR := Color(0.85, 0.2, 0.15)
const HP_COLOR := Color(0.35, 0.75, 0.35)
const HP_LOW_COLOR := Color(0.85, 0.3, 0.2)
const RING_COLOR := Color(1.0, 1.0, 1.0, 0.9)
const OPEN_COLOR := Color(0.4, 0.9, 0.45)
const ARROW_COLOR := Color(0.95, 0.25, 0.2)
const KEYS := {
	KEY_W: &"up", KEY_UP: &"up", KEY_A: &"left", KEY_LEFT: &"left",
	KEY_S: &"down", KEY_DOWN: &"down", KEY_D: &"right", KEY_RIGHT: &"right",
}
## Screen pixels a finger must travel to count as a swipe.
const SWIPE_MIN := 40.0
const NO_SWIPE := Vector2(-1, -1)
const ARROW_ANGLES := {&"up": -PI / 2, &"left": PI, &"down": PI / 2, &"right": 0.0}

var _state: KingdomState
var _spar: Spar
var _general_sprite: StringName
var _rival_sprite: StringName
var _general_tints: Dictionary
var _rival_tints: Dictionary
## Seconds into the current phase (the needle's or the ring's clock).
var _clock := 0.0
## Waiting before the next phase starts (after a hit, before the first strike).
var _wait := INTRO
var _time := 0.0
var _needle := 0.5
var _general_pose := 0.0
var _rival_pose := 0.0
var _general_shift := Vector2.ZERO
var _rival_shift := Vector2.ZERO
var _flash := 0.0
## Floating texts: {"text", "color", "at": Vector2, "age"}.
var _popups: Array[Dictionary] = []
var _round_label: Label
var _hint: Label
var _result: Dictionary = {}
## XP multiplier (EventSystem.REQUEST_BONUS when the officer asked for the match).
var _bonus := 1.0
var _forfeit_button: Button
var _swipe_from := NO_SWIPE
var _swiped := false


func start(state: KingdomState, general: General, seed_value: int = 0, bonus: float = 1.0) -> void:
	_state = state
	_bonus = bonus
	_spar = Spar.new(general, seed_value)
	_general_sprite = GameArt.foot_sprite(general.look, general.weapon_type(), general.stars)
	_rival_sprite = _spar.rival.sprite
	_general_tints = GameArt.unit_tints(state.player_color, general.look)
	_rival_tints = GameArt.unit_tints(RIVAL_COLOR, OfficerLook.from_seed(_spar.rival.title))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 14
	# Clear of the "Bỏ cuộc" button on both sides so the centered title never runs under it.
	top.offset_left = 160
	top.offset_right = -160
	top.add_theme_constant_override("separation", 2)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	var title := _label("Tỉ thí võ công: %s — %s %s" % [_spar.rival_label(), general.name, general.star_text()], 24)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(title)
	_round_label = _label("", 18)
	top.add_child(_round_label)
	_hint = _label("", 18)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -64
	_hint.offset_bottom = -30
	add_child(_hint)
	_forfeit_button = Button.new()
	_forfeit_button.text = "Bỏ cuộc"
	_forfeit_button.focus_mode = Control.FOCUS_NONE
	_forfeit_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_forfeit_button.offset_left = -150
	_forfeit_button.offset_top = 14
	_forfeit_button.offset_right = -16
	_forfeit_button.offset_bottom = 58
	_forfeit_button.tooltip_text = "Dừng trận: tính là thua."
	_forfeit_button.pressed.connect(_forfeit)
	add_child(_forfeit_button)
	_update_texts()
	Sfx.play(&"battle_start")


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UiPalette.ON_WOOD)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("outline_size", 6)
	return label


func _process(delta: float) -> void:
	if _spar == null:
		return
	_time += delta
	_general_pose = maxf(0.0, _general_pose - delta)
	_rival_pose = maxf(0.0, _rival_pose - delta)
	_flash = maxf(0.0, _flash - delta)
	_general_shift = _general_shift.move_toward(Vector2.ZERO, delta * 260.0)
	_rival_shift = _rival_shift.move_toward(Vector2.ZERO, delta * 120.0)
	for popup in _popups:
		popup.age += delta
	_popups = _popups.filter(func(popup: Dictionary) -> bool: return popup.age < 1.2)
	if _result.is_empty() and not _spar.is_over():
		if _wait > 0.0:
			_wait -= delta
			if _wait <= 0.0:
				_clock = 0.0
				if _spar.phase == Spar.Phase.DEFEND:
					_rival_pose = _spar.dodge_time()
			_update_texts()
		else:
			_clock += delta
			if _spar.phase == Spar.Phase.ATTACK:
				_needle = _spar.needle_at(_clock)
			elif _clock > _spar.dodge_time():
				_defend(&"")
	queue_redraw()


## A tap anywhere strikes; a swipe (a finger or the held mouse moving SWIPE_MIN) dodges that way
## (M15b). The dodge counts the moment the swipe is long enough, not when the finger lifts.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_swipe_from = event.position
			_swiped = false
			_strike()
		else:
			_swipe_from = NO_SWIPE
		accept_event()
	elif event is InputEventMouseMotion and _swipe_from != NO_SWIPE and not _swiped:
		var key := swipe_direction(event.position - _swipe_from)
		if key != &"":
			_swiped = true
			_defend(key)
		accept_event()


## The dodge direction of a finger move, or &"" while it is still shorter than SWIPE_MIN.
static func swipe_direction(move: Vector2) -> StringName:
	if move.length() < SWIPE_MIN:
		return &""
	if absf(move.x) > absf(move.y):
		return &"right" if move.x > 0.0 else &"left"
	return &"down" if move.y > 0.0 else &"up"


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.is_echo() or _spar == null:
		return
	if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] and not _result.is_empty():
		_close()
	elif event.keycode == KEY_SPACE:
		_strike()
	elif KEYS.has(event.keycode):
		_defend(KEYS[event.keycode])
	get_viewport().set_input_as_handled()


func _ready_for(phase: Spar.Phase) -> bool:
	return _result.is_empty() and _wait <= 0.0 and _spar.phase == phase


func _strike() -> void:
	if not _ready_for(Spar.Phase.ATTACK):
		return
	var hit := _spar.strike(_needle)
	_general_pose = POSE_TIME
	var grade: Spar.Grade = hit.grade
	if grade == Spar.Grade.MISS:
		Sfx.play(&"click")
		_popup("Trượt", MISS_COLOR, _rival_foot() + Vector2(0, -ART_SCALE * 40))
	else:
		Sfx.play(&"clash_3" if grade == Spar.Grade.PERFECT else &"clash_1")
		_rival_shift = Vector2(-KNOCK_SHIFT * (2.0 if grade == Spar.Grade.PERFECT else 1.0), 0)
		_popup("%s −%d" % [Spar.GRADE_NAMES[grade], hit.damage], PERFECT_COLOR if grade == Spar.Grade.PERFECT else GOOD_COLOR,
				_rival_foot() + Vector2(0, -ART_SCALE * 40))
	_after_move()


func _defend(key: StringName) -> void:
	if not _ready_for(Spar.Phase.DEFEND):
		return
	var answer := _spar.defend(key, _clock)
	_rival_pose = POSE_TIME
	if answer.dodged:
		Sfx.play(&"charge", -6.0)
		var away: Vector2 = Vector2.from_angle(ARROW_ANGLES[key]) * DODGE_SHIFT
		_general_shift = Vector2(away.x, minf(away.y, 30.0) if away.y > 0 else away.y)
		_popup("Né được!", OPEN_COLOR, _general_foot() + Vector2(0, -ART_SCALE * 40))
	else:
		Sfx.play(&"clash_2")
		_flash = 0.3
		_general_shift = Vector2(KNOCK_SHIFT, 0)
		var why := ("Vuốt sai hướng" if Touch.active else "Bấm sai hướng") if key != &"" and key != _spar.direction else "Né sớm quá" if key != &"" else "Không kịp né"
		_popup("%s −%d" % [why, answer.damage], HP_LOW_COLOR, _general_foot() + Vector2(0, -ART_SCALE * 40))
	_after_move()


func _after_move() -> void:
	_wait = PAUSE
	_update_texts()
	if _spar.is_over():
		_finish(_spar.won())


func _forfeit() -> void:
	if _result.is_empty():
		_finish(false, true)


func _finish(won: bool, forfeited: bool = false) -> void:
	_forfeit_button.visible = false
	var reward := _state.finish_spar(_spar.general, won, _bonus)
	_result = {"won": won, "xp": reward.get("xp", 0), "levels": reward.get("levels", 0), "forfeited": forfeited}
	_hint.text = ""
	Sfx.play(&"level_up" if won else &"horn")
	_show_result()


func _show_result() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 22)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var won: bool = _result.won
	var title := Label.new()
	title.text = "Thắng!" if won else "Bỏ cuộc (tính là thua)" if _result.forfeited else "Thua"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiPalette.GOOD if won else UiPalette.WARNING)
	box.add_child(title)
	var lines: Array[String] = ["Máu còn lại: %s %d · %s %d" % [_spar.general.name, _spar.hp, _spar.rival_label(), _spar.rival_hp]]
	lines.append("%s nhận %d kinh nghiệm%s." % [_spar.general.name, _result.xp, _bonus_text()])
	if _result.levels > 0:
		lines.append("Lên %d cấp! (cấp %d)" % [_result.levels, _spar.general.level])
	lines.append("Lần tỉ thí sau: %d lượt nữa." % Spar.COOLDOWN_TURNS)
	var text := Label.new()
	text.text = "\n".join(lines)
	text.add_theme_font_size_override("font_size", 16)
	box.add_child(text)
	var counsel := Counsel.lines(&"spar_won" if won else &"spar_lost", _state.counselor,
			Counsel.context(_state, {"general": _spar.general.name, "rival": _spar.rival_label()}))
	if not counsel.is_empty():
		var counsel_box := CounselBox.new()
		counsel_box.setup(counsel, 520.0)
		box.add_child(counsel_box)
	var done := Button.new()
	done.text = Touch.keys("Xong (Enter)")
	done.custom_minimum_size = Vector2(200, 48)
	done.focus_mode = Control.FOCUS_NONE
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	done.pressed.connect(_close)
	box.add_child(done)


func _bonus_text() -> String:
	return " (tâm nguyện riêng: +%d%%)" % roundi((_bonus - 1.0) * 100) if _bonus > 1.0 else ""


func _close() -> void:
	finished.emit(_result)
	queue_free()


func _update_texts() -> void:
	_round_label.text = "Hiệp %d/%d" % [_spar.round_number, Spar.ROUNDS]
	if not _result.is_empty() or _spar.is_over():
		_hint.text = ""
	elif _wait > 0.0 and _spar.phase == Spar.Phase.ATTACK and _spar.round_number == 1 and _spar.rival_hp == Spar.MAX_HP:
		_hint.text = "Chuẩn bị…"
	elif _spar.phase == Spar.Phase.ATTACK:
		_hint.text = "Tấn công: chạm màn hình khi kim vào vùng giữa" if Touch.active 				else "Tấn công: bấm Space hoặc chuột trái khi kim vào vùng giữa"
	else:
		_hint.text = "Phòng thủ: vuốt theo hướng mũi tên khi vòng thu vào vòng xanh" if Touch.active 				else "Phòng thủ: bấm đúng hướng (W / A / S / D) hoặc vuốt khi vòng thu vào vòng xanh"


func _popup(text: String, color: Color, at: Vector2) -> void:
	_popups.append({"text": text, "color": color, "at": at, "age": 0.0})


func _ground_y() -> float:
	return size.y * 0.66


func _rival_foot() -> Vector2:
	return Vector2(size.x * 0.36, _ground_y()) + _rival_shift


func _general_foot() -> Vector2:
	return Vector2(size.x * 0.64, _ground_y()) + _general_shift


# --- Drawing ----------------------------------------------------------------------------------

func _draw() -> void:
	if _spar == null:
		return
	_draw_courtyard()
	var beat := _time * 4.0
	var rival_state := &"attack" if _rival_pose > 0.0 else &"stand"
	var rival_frame := GameArt.anim_frame(_rival_sprite, beat)
	GameArt.draw_unit(self, _rival_sprite, _rival_foot(), 0.0, Vector2.ONE * ART_SCALE, rival_state, rival_frame,
			_rival_tints)
	var general_foot := _general_foot()
	GameArt.draw_aura(self, _general_sprite, general_foot, ART_SCALE, _spar.general.stars, _time)
	var general_state := &"attack" if _general_pose > 0.0 else &"cheer" if _result.get("won", false) else &"stand"
	GameArt.draw_unit(self, _general_sprite, general_foot, 0.0, Vector2(-ART_SCALE, ART_SCALE), general_state,
			GameArt.anim_frame(_general_sprite, beat), _general_tints, 0.5 if _flash > 0.0 else 0.0)
	GameArt.draw_aura_sparks(self, _general_sprite, general_foot, ART_SCALE, _spar.general.stars, _time)
	_draw_hp(Vector2(size.x * 0.25 - HP_BAR_SIZE.x * 0.5, 96), _spar.rival_label(), _spar.rival_hp)
	_draw_hp(Vector2(size.x * 0.75 - HP_BAR_SIZE.x * 0.5, 96), _spar.general.name, _spar.hp)
	if _result.is_empty() and not _spar.is_over():
		if _spar.phase == Spar.Phase.ATTACK:
			_draw_bar()
		elif _wait <= 0.0:
			_draw_ring()
	var font := get_theme_default_font()
	for popup in _popups:
		var rise: float = popup.age * 50.0
		var color: Color = popup.color
		color.a = clampf(1.6 - popup.age * 1.4, 0.0, 1.0)
		var at: Vector2 = popup.at - Vector2(0, rise)
		var text: String = popup.text
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_string_outline(font, at - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6,
				Color(0, 0, 0, color.a * 0.8))
		draw_string(font, at - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, color)


func _draw_courtyard() -> void:
	var ground := _ground_y()
	draw_rect(Rect2(0, 0, size.x, ground - 150), SKY)
	# The castle wall behind the courtyard, with a tiled roof and crenels.
	draw_rect(Rect2(0, ground - 170, size.x, 20), ROOF)
	draw_rect(Rect2(0, ground - 150, size.x, 150), WALL)
	for x in range(0, int(size.x), 64):
		draw_rect(Rect2(x, ground - 150, 2, 150), WALL_DARK)
	for y in [ground - 110, ground - 70, ground - 30]:
		draw_rect(Rect2(0, y, size.x, 2), WALL_DARK)
	draw_rect(Rect2(0, ground, size.x, size.y - ground), GROUND)
	for i in 6:
		var y := ground + 14 + i * i * 9.0
		draw_line(Vector2(0, y), Vector2(size.x, y), GROUND_LINE, 2.0)


func _draw_hp(at: Vector2, name: String, value: int) -> void:
	var font := get_theme_default_font()
	draw_string_outline(font, at + Vector2(0, -6), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.7))
	draw_string(font, at + Vector2(0, -6), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiPalette.ON_WOOD)
	draw_rect(Rect2(at - Vector2(3, 3), HP_BAR_SIZE + Vector2(6, 6)), Color(0.15, 0.1, 0.07))
	draw_rect(Rect2(at, HP_BAR_SIZE), Color(0.3, 0.25, 0.2))
	var share := float(value) / Spar.MAX_HP
	draw_rect(Rect2(at, Vector2(HP_BAR_SIZE.x * share, HP_BAR_SIZE.y)), HP_COLOR if share > 0.35 else HP_LOW_COLOR)
	var text := "%d/%d" % [value, Spar.MAX_HP]
	draw_string(font, at + Vector2(HP_BAR_SIZE.x - 64, HP_BAR_SIZE.y - 4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


## The strike bar: miss / good / perfect zones and the needle.
func _draw_bar() -> void:
	var width := size.x * BAR_WIDTH_SHARE
	var at := Vector2((size.x - width) * 0.5, size.y * 0.8)
	draw_rect(Rect2(at - Vector2(4, 4), Vector2(width + 8, BAR_HEIGHT + 8)), Color(0.15, 0.1, 0.07))
	draw_rect(Rect2(at, Vector2(width, BAR_HEIGHT)), MISS_COLOR)
	var good := _spar.good_half() * width
	var perfect := _spar.perfect_half() * width
	var middle := at.x + width * 0.5
	draw_rect(Rect2(middle - good, at.y, good * 2.0, BAR_HEIGHT), GOOD_COLOR)
	draw_rect(Rect2(middle - perfect, at.y, perfect * 2.0, BAR_HEIGHT), PERFECT_COLOR)
	var x := at.x + width * _needle
	draw_rect(Rect2(x - 3, at.y - 12, 6, BAR_HEIGHT + 24), Color.WHITE)
	draw_rect(Rect2(x - 1, at.y - 12, 2, BAR_HEIGHT + 24), Color(0.1, 0.1, 0.1))


## The rival's blow: an arrow for its direction and a ring closing on it; the green ring marks
## where a dodge starts to count.
func _draw_ring() -> void:
	var center := Vector2(size.x * 0.5, size.y * 0.42)
	var progress := clampf(_clock / _spar.dodge_time(), 0.0, 1.0)
	var radius := lerpf(RING_START, RING_END, progress)
	var open_radius := lerpf(RING_START, RING_END, _spar.dodge_open_share())
	draw_circle(center, open_radius, Color(OPEN_COLOR, 0.18))
	draw_arc(center, open_radius, 0.0, TAU, 48, OPEN_COLOR, 3.0)
	var open := progress >= _spar.dodge_open_share()
	draw_arc(center, radius, 0.0, TAU, 48, OPEN_COLOR if open else RING_COLOR, 6.0)
	var angle: float = ARROW_ANGLES[_spar.direction]
	var tip := center + Vector2.from_angle(angle) * 22.0
	var back := center - Vector2.from_angle(angle) * 16.0
	var side := Vector2.from_angle(angle + PI / 2) * 16.0
	draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), ARROW_COLOR)
	var font := get_theme_default_font()
	if Touch.active:
		return
	var key: String = Spar.DIRECTION_KEYS[_spar.direction]
	draw_string_outline(font, center + Vector2(-8, RING_START + 34), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 6, Color(0, 0, 0, 0.8))
	draw_string(font, center + Vector2(-8, RING_START + 34), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
