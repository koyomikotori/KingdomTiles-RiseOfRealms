class_name TutorialOverlay
extends Control
## Shows the tutorial (GDD §29, M18a) over the kingdom screen: the counselor's box with the step's
## words, "Tiếp" on steps the player only reads, "Bỏ qua hướng dẫn" (press twice), and a pulsing
## frame with an arrow around what the step is about. It never blocks the game: only the box takes
## clicks. The kingdom scene gives it `target_rect` (Rect2 on screen for a Tutorial target id, an
## empty Rect2 when hidden) and `is_busy` (a window or screen that has nothing to do with the step
## is open: the overlay hides meanwhile).

const BOX_WIDTH := 430.0
const MARGIN := 12.0
## Below the top bar when the box goes to the top.
const TOP_ROOM := 92.0
const FRAME_COLOR := Color(1.0, 0.85, 0.3)
const FRAME_WIDTH := 4.0
const FRAME_GROW := 6.0
const ARROW_SIZE := 22.0
const ARROW_GAP := 10.0
const BOUNCE := 8.0
const CHECK_INTERVAL := 0.2

var target_rect: Callable
var is_busy: Callable

var _state: KingdomState
var _box: PanelContainer
var _title: Label
var _words: VBoxContainer
var _next_button: Button
var _skip_button: Button
var _skip_armed := false
var _shown_step := Tutorial.OFF
var _time := 0.0
var _check := 0.0


func setup(state: KingdomState) -> void:
	_state = state
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_box()
	_refresh()


func _build_box() -> void:
	_box = PanelContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_box)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 14)
	_box.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 13)
	_title.add_theme_color_override("font_color", UiPalette.HEADER)
	column.add_child(_title)
	_words = VBoxContainer.new()
	column.add_child(_words)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)
	_skip_button = _button("Bỏ qua hướng dẫn", _on_skip)
	buttons.add_child(_skip_button)
	_next_button = _button("Tiếp", _on_next)
	_next_button.custom_minimum_size.x = 110
	buttons.add_child(_next_button)


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(action)
	return button


func _process(delta: float) -> void:
	if _state == null:
		return
	_time += delta
	_check += delta
	if _check >= CHECK_INTERVAL:
		_check = 0.0
		_state.tutorial.update(_state)
	if not _state.tutorial.is_active():
		_close()
		return
	if _state.tutorial.step != _shown_step:
		_refresh()
	visible = not (is_busy.is_valid() and is_busy.call())
	if visible:
		_place_box()
		queue_redraw()


## Frees the overlay with the CanvasLayer the kingdom scene made for it (one free, no signal from a
## node that is leaving the tree).
func _close() -> void:
	set_process(false)
	var layer := get_parent()
	if layer is CanvasLayer:
		layer.queue_free()
	else:
		queue_free()


func _refresh() -> void:
	_shown_step = _state.tutorial.step
	_skip_armed = false
	_skip_button.text = "Bỏ qua hướng dẫn"
	if not _state.tutorial.is_active():
		return
	var step := _state.tutorial.current()
	_title.text = "Hướng dẫn %d/%d" % [_state.tutorial.step + 1, Tutorial.STEPS.size()]
	for child in _words.get_children():
		_words.remove_child(child)
		child.queue_free()
	var counsel := CounselBox.new()
	counsel.setup(Counsel.tutorial_lines(step.id, _state.counselor, Counsel.context(_state)), BOX_WIDTH - 28.0)
	_words.add_child(counsel)
	var last := _state.tutorial.step == Tutorial.STEPS.size() - 1
	_next_button.visible = step.need == Tutorial.Need.NEXT
	_next_button.text = "Hoàn tất" if last else "Tiếp"
	_skip_button.visible = not last
	_box.reset_size()
	Sfx.play(&"click")


func _on_next() -> void:
	_state.tutorial.next(_state)


func _on_skip() -> void:
	if not _skip_armed:
		_skip_armed = true
		_skip_button.text = "Bấm lần nữa để bỏ qua"
		return
	_state.tutorial.skip()


## Bottom left (over the notice column) unless that covers what the step points at; then bottom
## middle, then under the top bar.
func _place_box() -> void:
	var view := get_viewport_rect().size
	var box_size := _box.get_combined_minimum_size()
	box_size.x = maxf(box_size.x, BOX_WIDTH)
	_box.size = box_size
	var target := _target()
	var spots: Array[Vector2] = [
		Vector2(MARGIN, view.y - box_size.y - MARGIN),
		Vector2((view.x - box_size.x) * 0.5, view.y - box_size.y - MARGIN),
		Vector2(MARGIN, TOP_ROOM),
	]
	var chosen := spots[0]
	for spot in spots:
		if not Rect2(spot, box_size).grow(FRAME_GROW + ARROW_SIZE).intersects(target):
			chosen = spot
			break
	_box.position = chosen


func _target() -> Rect2:
	var id: StringName = _state.tutorial.current().get("target", &"")
	if id == &"" or not target_rect.is_valid():
		return Rect2()
	return target_rect.call(id)


func _draw() -> void:
	var target := _target()
	if not target.has_area():
		return
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	var frame := target.grow(FRAME_GROW + pulse * 3.0)
	draw_rect(frame, Color(FRAME_COLOR, 0.35 + 0.5 * pulse), false, FRAME_WIDTH)
	# The arrow points down at the target from above, or up from below when there is no room.
	var bounce := sin(_time * 4.0) * BOUNCE
	var above := frame.position.y > ARROW_SIZE * 2.5
	var tip := Vector2(frame.get_center().x, frame.position.y - ARROW_GAP + bounce) if above \
			else Vector2(frame.get_center().x, frame.end.y + ARROW_GAP - bounce)
	var back := tip + Vector2(0, -ARROW_SIZE if above else ARROW_SIZE)
	var side := Vector2(ARROW_SIZE * 0.6, 0)
	var points := PackedVector2Array([tip, back + side, back - side])
	draw_colored_polygon(points, FRAME_COLOR)
	points.append(tip)
	draw_polyline(points, Color(0.3, 0.18, 0.05), 2.0)
