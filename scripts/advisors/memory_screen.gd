class_name MemoryScreen
extends Control
## The memory card mini game (GDD §27, M16k): the Chúa công (the player, left) against one of the
## kingdom's advisors (the computer, right). MemoryMatch holds the rules; this screen reads the
## clicks, plays the advisor's turns at a readable pace and draws the table and the cards. When the
## match ends it pays the advisor's XP (KingdomState.finish_memory), shows the result with a
## counselor line and emits `finished` on "Xong".

signal finished(result: Dictionary)

## Seconds two cards that do not match stay up, between the advisor's flips, and before the start.
const REVEAL := 1.1
const AI_STEP := 1.0
const INTRO := 0.8
## Seconds a card takes to turn over.
const TURN_TIME := 0.16
const SIDE_WIDTH := 250.0
const TOP := 110.0
const BOTTOM := 70.0
const GAP := 8.0
const BACKGROUND := Color(0.3, 0.21, 0.15)
const TABLE := Color(0.42, 0.3, 0.2)
const TABLE_EDGE := Color(0.22, 0.15, 0.1)
const CARD_BACK := Color(0.55, 0.16, 0.12)
const CARD_BACK_DARK := Color(0.4, 0.1, 0.08)
const CARD_FACE := Color(0.96, 0.91, 0.79)
const CARD_EDGE := Color(0.2, 0.14, 0.1)
const GOLD := Color(0.95, 0.76, 0.24)
const RULER_COLOR := Color(0.95, 0.76, 0.24)
const ADVISOR_COLOR := Color(0.45, 0.7, 0.95)
const HOVER := Color(1, 1, 1, 0.25)

var _state: KingdomState
var _match: MemoryMatch
var _wait := INTRO
var _time := 0.0
## Card → seconds since it was turned up or down (for the turn-over animation).
var _turned: Dictionary[int, float] = {}
var _hover := MemoryMatch.NOBODY
## Floating texts: {"text", "color", "at": Vector2, "age"}.
var _popups: Array[Dictionary] = []
var _turn_label: Label
var _hint: Label
var _scores: Array[Label] = []
var _result: Dictionary = {}
## XP multiplier (EventSystem.REQUEST_BONUS when the officer asked for the match).
var _bonus := 1.0
var _forfeit_button: Button


func start(state: KingdomState, advisor: Advisor, seed_value: int = 0, bonus: float = 1.0) -> void:
	_state = state
	_bonus = bonus
	_match = MemoryMatch.new(advisor, seed_value)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 14
	top.add_theme_constant_override("separation", 2)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top)
	top.add_child(_label("Đấu trí: %s — %s %s" % [state.ruler.name, advisor.name, advisor.star_text()], 24))
	_turn_label = _label("", 18)
	top.add_child(_turn_label)
	_hint = _label("", 18)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -56
	_hint.offset_bottom = -22
	add_child(_hint)
	_add_side(state.ruler, state.ruler.name, true)
	_add_side(advisor, advisor.name, false)
	_forfeit_button = Button.new()
	_forfeit_button.text = "Bỏ cuộc"
	_forfeit_button.focus_mode = Control.FOCUS_NONE
	_forfeit_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_forfeit_button.offset_left = -150
	_forfeit_button.offset_top = 14
	_forfeit_button.offset_right = -16
	_forfeit_button.offset_bottom = 58
	_forfeit_button.tooltip_text = "Dừng ván: tính là Chúa công thua."
	_forfeit_button.pressed.connect(_forfeit)
	add_child(_forfeit_button)
	_update_texts()
	Sfx.play(&"open")


## A player's column: portrait, name and pairs taken.
func _add_side(officer: Officer, name: String, left: bool) -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT if left else Control.PRESET_CENTER_RIGHT)
	box.offset_left = 28.0 if left else -SIDE_WIDTH + 28.0
	box.offset_right = SIDE_WIDTH - 28.0 if left else -28.0
	box.offset_top = -170
	box.offset_bottom = 170
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var portrait := PortraitView.new()
	portrait.setup(officer, 2.0, _state.player_color)
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(portrait)
	var title := _label(name, 20)
	title.add_theme_color_override("font_color", RULER_COLOR if left else ADVISOR_COLOR)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var score := _label("", 22)
	box.add_child(score)
	_scores.append(score)


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UiPalette.ON_WOOD)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _process(delta: float) -> void:
	if _match == null:
		return
	_time += delta
	for card in _turned:
		_turned[card] += delta
	for popup in _popups:
		popup.age += delta
	_popups = _popups.filter(func(popup: Dictionary) -> bool: return popup.age < 1.2)
	if _result.is_empty() and not _match.is_over():
		_wait -= delta
		if _wait <= 0.0:
			if _match.waiting():
				_end_turn()
			elif _match.side == MemoryMatch.Side.ADVISOR:
				_flip(_match.ai_pick())
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _card_at(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if not _result.is_empty() or _match.side != MemoryMatch.Side.RULER:
			return
		if _match.waiting():
			_end_turn()  # a click turns the two cards down at once
		elif _time >= INTRO:
			_flip(_card_at(event.position))


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.is_echo() or _match == null:
		return
	if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] and not _result.is_empty():
		_close()
		get_viewport().set_input_as_handled()


func _flip(card: int) -> void:
	var side := _match.side
	var flipped := _match.flip(card)
	if flipped.is_empty():
		return
	_turned[card] = 0.0
	Sfx.play(&"click")
	if flipped.pair:
		Sfx.play(&"coins" if side == MemoryMatch.Side.RULER else &"stratagem")
		_popup("+1 cặp", RULER_COLOR if side == MemoryMatch.Side.RULER else ADVISOR_COLOR, _card_rect(card).get_center())
		_wait = AI_STEP
	elif flipped.second:
		_wait = REVEAL
	else:
		_wait = AI_STEP
	_update_texts()
	if _match.is_over():
		_finish(_match.ruler_won())


func _end_turn() -> void:
	for card in _match.picked:
		_turned[card] = 0.0
	_match.end_turn()
	_wait = AI_STEP
	_update_texts()


func _forfeit() -> void:
	if _result.is_empty():
		_finish(false, true)


func _finish(ruler_won: bool, forfeited: bool = false) -> void:
	_forfeit_button.visible = false
	var reward := _state.finish_memory(_match.advisor, ruler_won, _bonus)
	_result = {"won": ruler_won, "xp": reward.get("xp", 0), "levels": reward.get("levels", 0), "forfeited": forfeited}
	_update_texts()
	Sfx.play(&"level_up" if ruler_won else &"complete")
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
	var advisor := _match.advisor
	var title := Label.new()
	title.text = "Chúa công thắng!" if won else "Bỏ cuộc (tính là thua)" if _result.forfeited else "%s thắng" % advisor.name
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UiPalette.GOOD if won else UiPalette.WARNING)
	box.add_child(title)
	var lines: Array[String] = ["Số cặp: %s %d · %s %d" % [_state.ruler.name, _match.scores[MemoryMatch.Side.RULER],
			advisor.name, _match.scores[MemoryMatch.Side.ADVISOR]]]
	lines.append("%s nhận %d kinh nghiệm%s." % [advisor.name, _result.xp, _bonus_text()])
	if _result.levels > 0:
		lines.append("Lên %d cấp! (cấp %d)" % [_result.levels, advisor.level])
	lines.append("Lần đấu trí sau: %d lượt nữa." % MemoryMatch.COOLDOWN_TURNS)
	var text := Label.new()
	text.text = "\n".join(lines)
	text.add_theme_font_size_override("font_size", 16)
	box.add_child(text)
	var counsel := Counsel.lines(&"memory_won" if won else &"memory_lost", _state.counselor,
			Counsel.context(_state, {"advisor": advisor.name}))
	if not counsel.is_empty():
		var counsel_box := CounselBox.new()
		counsel_box.setup(counsel, 520.0)
		box.add_child(counsel_box)
	var done := Button.new()
	done.text = "Xong (Enter)"
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
	_scores[MemoryMatch.Side.RULER].text = "%d cặp" % _match.scores[MemoryMatch.Side.RULER]
	_scores[MemoryMatch.Side.ADVISOR].text = "%d cặp" % _match.scores[MemoryMatch.Side.ADVISOR]
	var left := _match.pair_count() - _match.scores[0] - _match.scores[1]
	if _match.is_over() or not _result.is_empty():
		_turn_label.text = ""
		_hint.text = ""
		return
	var ruler_turn := _match.side == MemoryMatch.Side.RULER
	_turn_label.text = "Lượt của %s · còn %d cặp" % [_state.ruler.name if ruler_turn else _match.advisor.name, left]
	if not ruler_turn:
		_hint.text = "%s đang lật thẻ…" % _match.advisor.name
	elif _match.waiting():
		_hint.text = "Không trùng. Bấm để úp lại."
	else:
		_hint.text = "Lật 2 thẻ giống nhau để lấy cặp, trúng thì được lật tiếp"


func _popup(text: String, color: Color, at: Vector2) -> void:
	_popups.append({"text": text, "color": color, "at": at, "age": 0.0})


# --- Layout -------------------------------------------------------------------------------------

## The square card size that fits the board between the two side columns.
func _card_size() -> float:
	var width := size.x - SIDE_WIDTH * 2.0
	var height := size.y - TOP - BOTTOM
	return floorf(minf((width - GAP) / _match.columns, (height - GAP) / _match.rows) - GAP)


func _board_rect() -> Rect2:
	var step := _card_size() + GAP
	var board := Vector2(step * _match.columns + GAP, step * _match.rows + GAP)
	var middle := Vector2(size.x * 0.5, TOP + (size.y - TOP - BOTTOM) * 0.5)
	return Rect2(middle - board * 0.5, board)


func _card_rect(card: int) -> Rect2:
	var side := _card_size()
	var at := _board_rect().position + Vector2(GAP, GAP)
	var cell := Vector2i(card % _match.columns, card / _match.columns)
	return Rect2(at + Vector2(cell) * (side + GAP), Vector2(side, side))


func _card_at(point: Vector2) -> int:
	for card in _match.cards.size():
		if _card_rect(card).has_point(point):
			return card
	return MemoryMatch.NOBODY


static func face_texture(face: int) -> Texture2D:
	var entry: Array = MemoryMatch.FACES[face]
	return GameArt.icon(entry[1]) if entry[0] == &"icon" else GameArt.item_icon(entry[1])


# --- Drawing ----------------------------------------------------------------------------------

func _draw() -> void:
	if _match == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	var board := _board_rect()
	draw_rect(board.grow(10), TABLE_EDGE)
	draw_rect(board, TABLE)
	for card in _match.cards.size():
		_draw_card(card)
	var font := get_theme_default_font()
	for popup in _popups:
		var color: Color = popup.color
		color.a = clampf(1.6 - popup.age * 1.4, 0.0, 1.0)
		var at: Vector2 = popup.at - Vector2(0, popup.age * 50.0)
		var text: String = popup.text
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_string_outline(font, at - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6,
				Color(0, 0, 0, color.a * 0.8))
		draw_string(font, at - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, color)


func _draw_card(card: int) -> void:
	var rect := _card_rect(card)
	var owner := _match.taken[card]
	var up := owner != MemoryMatch.NOBODY or _match.picked.has(card)
	# Turning over: the card narrows to a line and widens again showing its new side.
	var turn := clampf(_turned.get(card, TURN_TIME) / TURN_TIME, 0.0, 1.0)
	var squeeze := absf(1.0 - turn * 2.0) if turn < 1.0 else 1.0
	var showing_up := up if turn >= 0.5 else not up
	rect = Rect2(rect.position + Vector2(rect.size.x * (1.0 - squeeze) * 0.5, 0), Vector2(rect.size.x * squeeze, rect.size.y))
	if rect.size.x < 1.0:
		return
	draw_rect(rect, CARD_EDGE)
	var inner := rect.grow(-3)
	if not showing_up:
		draw_rect(inner, CARD_BACK)
		draw_rect(inner.grow(-5), CARD_BACK_DARK, false, 2.0)
		var middle := inner.get_center()
		var half := minf(inner.size.x, inner.size.y) * 0.18
		draw_colored_polygon(PackedVector2Array([middle + Vector2(0, -half), middle + Vector2(half, 0),
				middle + Vector2(0, half), middle + Vector2(-half, 0)]), GOLD)
		if card == _hover and _match.side == MemoryMatch.Side.RULER and _match.can_flip(card) and _result.is_empty():
			draw_rect(inner, HOVER)
		return
	draw_rect(inner, CARD_FACE)
	var texture := face_texture(_match.cards[card])
	if texture != null:
		var scale := maxf(1.0, floorf(minf(inner.size.x, inner.size.y) * 0.7 / texture.get_height()))
		var icon := Vector2(texture.get_width(), texture.get_height()) * scale
		icon.x *= squeeze if squeeze < 1.0 else 1.0
		draw_texture_rect(texture, Rect2(inner.get_center() - icon * 0.5, icon), false,
				Color(1, 1, 1, 0.55) if owner != MemoryMatch.NOBODY else Color.WHITE)
	if owner != MemoryMatch.NOBODY:
		draw_rect(inner, RULER_COLOR if owner == MemoryMatch.Side.RULER else ADVISOR_COLOR, false, 4.0)
