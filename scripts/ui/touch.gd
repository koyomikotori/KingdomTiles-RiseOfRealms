class_name Touch
extends Node
## Autoload "TouchInput" (GDD §10.2, M15a): everything a phone needs that a mouse does not.
## - Touch mode (`Touch.active`): on from the first finger, off again when a real mouse moves (a
##   touch laptop can use both). Phones start in it. The map then places by tap + Đặt / Hủy.
## - Two-finger pinch: `pinched(center, factor)` for the map camera; `fingers()` tells the board
##   to stop panning while two fingers are down.
## - Long press (LONG_PRESS s without moving) on a control with a tooltip shows it in a small box;
##   lifting the finger then closes it and does not press the control.
## - Android Back = Esc (closes windows, drops the selection).
## - The UI scale (GameSettings.ui_scale, "Tự động" = auto_ui_scale) on the root window.
## Godot turns the first finger into left mouse events as well, so taps, drags and DragScroll work
## through the usual mouse code.

signal pinched(center: Vector2, factor: float)
signal mode_changed(on: bool)

const LONG_PRESS := 0.5
## Screen pixels a finger may move and still count as holding still.
const HOLD_SLOP := 12.0
## A button about this tall (logical pixels) should be FINGER_MM on the glass.
const BUTTON_HEIGHT := 40.0
const FINGER_MM := 8.0
const MAX_AUTO_SCALE := 1.3
## The smallest logical screen the windows are laid out for: the UI scale never shrinks it below this.
const MIN_VIEW := Vector2(960, 500)
const AWAY := Vector2(-100000, -100000)
const TIP_WIDTH := 380.0
## Words that start a keyboard hint in brackets ("(Esc)", "(Enter)", "(Space)", "(phím ← →)").
const KEY_NAMES: Array[String] = ["Esc", "Enter", "Space", "phím"]

static var active := false
static var _fingers: Dictionary[int, Vector2] = {}

var _pinch_distance := 0.0
var _hold_time := -1.0
var _hold_start := Vector2.ZERO
var _tip: PanelContainer
var _tip_label: Label
var _tip_layer: CanvasLayer
## The finger that opened the tooltip is still down: its release must not press anything.
var _swallow_release := false


## Fingers on the screen now.
static func fingers() -> int:
	return _fingers.size()


## A label without its keyboard hint in touch mode: "Đóng (Esc)" -> "Đóng" (M15b). Only a
## trailing "(…)" that names a key is dropped.
static func keys(text: String) -> String:
	return strip_key_hint(text) if active else text


static func strip_key_hint(text: String) -> String:
	var open := text.rfind(" (")
	if open < 0 or not text.ends_with(")"):
		return text
	var inside := text.substr(open + 2, text.length() - open - 3)
	for key in KEY_NAMES:
		if inside.begins_with(key):
			return text.substr(0, open)
	return text


## The scale that makes a BUTTON_HEIGHT button about FINGER_MM tall on this screen: 1 on a computer
## (or when the screen does not say its density), at most MAX_AUTO_SCALE.
static func auto_ui_scale(screen_size: Vector2, dpi: float, base_size: Vector2, mobile: bool) -> float:
	if not mobile or dpi <= 0.0 or base_size.y <= 0.0:
		return 1.0
	var stretch := minf(screen_size.x / base_size.x, screen_size.y / base_size.y)
	var wanted := FINGER_MM / 25.4 * dpi
	return clampf(wanted / (BUTTON_HEIGHT * stretch), 1.0, MAX_AUTO_SCALE)


## The largest UI scale that still leaves MIN_VIEW logical pixels in a window this big (M15b): the
## windows are laid out for that much room, so a bigger chosen scale stops here. Never below 1.
static func fitting_scale(window_size: Vector2, base_size: Vector2) -> float:
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		return INF
	var stretch := minf(window_size.x / base_size.x, window_size.y / base_size.y)
	var logical := window_size / stretch
	return maxf(1.0, minf(logical.x / MIN_VIEW.x, logical.y / MIN_VIEW.y))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args():
		active = true
	get_tree().quit_on_go_back = false
	_build_tip()
	apply_ui_scale()
	GameSettings.notifier.changed.connect(apply_ui_scale)
	get_tree().root.size_changed.connect(apply_ui_scale)


func apply_ui_scale() -> void:
	var chosen := GameSettings.ui_scale()
	var base := Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height"))
	if chosen == GameSettings.AUTO_UI_SCALE:
		var screen := DisplayServer.screen_get_size()
		chosen = auto_ui_scale(Vector2(screen), DisplayServer.screen_get_dpi(), base, OS.has_feature("mobile"))
	chosen = minf(chosen, fitting_scale(Vector2(get_tree().root.size), base))
	if not is_equal_approx(get_tree().root.content_scale_factor, chosen):
		get_tree().root.content_scale_factor = chosen


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		for pressed in [true, false]:
			var key := InputEventKey.new()
			key.keycode = KEY_ESCAPE
			key.physical_keycode = KEY_ESCAPE
			key.pressed = pressed
			Input.parse_input_event(key)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_set_active(true)
		if event.pressed:
			_fingers[event.index] = event.position
		else:
			_fingers.erase(event.index)
		_pinch_distance = _finger_distance()
		if fingers() > 1:
			_hold_time = -1.0
	elif event is InputEventScreenDrag:
		_fingers[event.index] = event.position
		if fingers() == 2:
			var distance := _finger_distance()
			if _pinch_distance > 0.0 and distance > 0.0:
				pinched.emit(_finger_center(), distance / _pinch_distance)
			_pinch_distance = distance
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION \
			and not OS.has_feature("mobile") and event.relative.length() > 0.0:
		_set_active(false)
	if active:
		_long_press(event)


func _process(delta: float) -> void:
	if _hold_time < 0.0:
		return
	_hold_time += delta
	if _hold_time >= LONG_PRESS:
		_hold_time = -1.0
		_show_tip(_hold_start)


func _set_active(on: bool) -> void:
	if active == on:
		return
	active = on
	mode_changed.emit(on)


func _long_press(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_hide_tip()
			_hold_time = 0.0 if fingers() <= 1 else -1.0
			_hold_start = event.position
		else:
			_hold_time = -1.0
			if _swallow_release:
				_swallow_release = false
				_hide_tip()
				_release_away(event)
	elif event is InputEventMouseMotion and _hold_time >= 0.0:
		if event.position.distance_to(_hold_start) > HOLD_SLOP:
			_hold_time = -1.0


## The pressed control sees the pointer leave and the release far away: no click.
func _release_away(event: InputEventMouseButton) -> void:
	get_viewport().set_input_as_handled()
	var leave := InputEventMouseMotion.new()
	leave.position = AWAY
	leave.global_position = AWAY
	leave.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(leave, true)
	var away: InputEventMouseButton = event.duplicate()
	away.position = AWAY
	away.global_position = AWAY
	get_viewport().push_input(away, true)


## The tooltip of the control under the finger (or of the nearest parent that has one).
func _tooltip_at(position: Vector2) -> String:
	var control := get_viewport().gui_get_hovered_control()
	var start := control
	while control != null:
		var text := _own_tooltip(control, position)
		if not text.is_empty():
			return text
		control = control.get_parent() as Control
	# A finger is wide: a tip on a neighbour inside the same row (an icon's label) also counts.
	if start != null and start.get_parent() is Control:
		for sibling in (start.get_parent() as Control).get_children():
			if sibling is Control and (sibling as Control).is_visible_in_tree():
				var text := _own_tooltip(sibling, position)
				if not text.is_empty() and (sibling as Control).get_global_rect().grow(HOLD_SLOP * 2).has_point(position):
					return text
	return ""


func _own_tooltip(control: Control, position: Vector2) -> String:
	return control.get_tooltip(control.get_global_transform_with_canvas().affine_inverse() * position)


func _show_tip(position: Vector2) -> void:
	var text := _tooltip_at(position)
	if text.is_empty():
		return
	_tip_label.text = text
	# Short tips stay on one line; long ones wrap at TIP_WIDTH.
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_tip_label.custom_minimum_size.x = 0.0
	if _tip_label.get_minimum_size().x > TIP_WIDTH:
		_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_tip_label.custom_minimum_size.x = TIP_WIDTH
	_tip.reset_size()
	var view := get_viewport().get_visible_rect().size
	var size := _tip.get_combined_minimum_size()
	# Above the finger so it is not hidden under it, kept on screen.
	var at := position + Vector2(-size.x * 0.5, -size.y - 40.0)
	if at.y < 4.0:
		at.y = position.y + 40.0
	_tip.position = at.clamp(Vector2(4, 4), (view - size - Vector2(4, 4)).max(Vector2(4, 4)))
	_tip.visible = true
	_swallow_release = true


func _hide_tip() -> void:
	if _tip != null:
		_tip.visible = false


func _build_tip() -> void:
	_tip_layer = CanvasLayer.new()
	_tip_layer.layer = 120
	add_child(_tip_layer)
	_tip = PanelContainer.new()
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.1, 0.07, 0.95)
	style.border_color = UiPalette.ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	_tip.add_theme_stylebox_override("panel", style)
	_tip_layer.add_child(_tip)
	_tip_label = Label.new()
	_tip_label.add_theme_font_size_override("font_size", 15)
	_tip_label.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82))
	_tip.add_child(_tip_label)


func _finger_distance() -> float:
	if fingers() < 2:
		return 0.0
	var points := _fingers.values()
	return (points[0] as Vector2).distance_to(points[1])


func _finger_center() -> Vector2:
	var points := _fingers.values()
	return ((points[0] as Vector2) + (points[1] as Vector2)) * 0.5
