class_name ModalWindow
extends Control
## A window in the middle of the screen over a dimmed background: title, body, a status line and
## a row of action buttons ending with "Đóng (Esc)". Blocks everything underneath (keys too)
## until closed. Subclasses call build_frame() and fill the body. Built in code, touch-ready.

signal closed

const MUTED_COLOR := UiPalette.MUTED
const WARNING_COLOR := UiPalette.WARNING
const GOOD_COLOR := UiPalette.GOOD
## Default window width as a share of the screen; its height follows the content.
const WIDTH_SHARE := 0.5
## The status line always keeps this much room, so a result appearing never moves the window.
const STATUS_HEIGHT := 20.0
## Windows keep this far from the top and bottom of the screen.
const SCREEN_MARGIN := 12.0

var _status: Label
var _actions: HBoxContainer
var _close_button: Button
var _closable := true
## The top edge is fixed (_pin_top): the window only grows downward.
var _pinned := false
## The body sits in this: a window taller than the screen keeps its size and its body scrolls
## (drag with a finger, M15a) instead of the whole window shrinking.
var _frame_scroll: ScrollContainer
var _frame_body: VBoxContainer
var _frame_panel: PanelContainer
## Smallest body height kept when the screen is very short.
const MIN_BODY_HEIGHT := 120.0


## Builds the window and returns the body to fill (between the title and the status line).
## A window that is not `closable` has no close button and ignores Esc: one of its actions must
## lead on (the end-of-game screen).
func build_frame(title_text: String, accent: Color, width_share: float = WIDTH_SHARE, closable: bool = true) -> VBoxContainer:
	_closable = closable
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = UiPalette.DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.anchor_left = (1.0 - width_share) * 0.5
	panel.anchor_right = 1.0 - panel.anchor_left
	# Centered vertically and as tall as its content.
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	# The paper panel comes from the project theme (GDD §13).
	add_child(panel)
	# A small game window: a window taller or wider than it shrinks to fit (GDD §10.2).
	panel.resized.connect(func() -> void:
		_keep_on_screen(panel)
		ScreenFit.shrink_to_fit(panel, get_viewport_rect().size))
	_pin_top.call_deferred(panel)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	panel.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	var title := _label(title_text, 22)
	title.add_theme_color_override("font_color", UiPalette.ink(accent))
	layout.add_child(title)
	_frame_scroll = ScrollContainer.new()
	_frame_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(_frame_scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame_scroll.add_child(body)
	_frame_body = body
	_frame_panel = panel
	body.minimum_size_changed.connect(_fit_body)
	get_viewport().size_changed.connect(_fit_body)
	_status = _label("", 14)
	_status.custom_minimum_size.y = STATUS_HEIGHT
	layout.add_child(_status)
	layout.add_child(HSeparator.new())
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	_actions.alignment = BoxContainer.ALIGNMENT_END
	layout.add_child(_actions)
	_close_button = _button(Touch.keys("Đóng (Esc)"), close)
	_close_button.visible = closable
	_actions.add_child(_close_button)
	return body


## The body's room: all of its content, or what the screen leaves after the rest of the window.
func _fit_body() -> void:
	if not is_instance_valid(_frame_scroll) or not is_inside_tree():
		return
	var wanted := _frame_body.get_combined_minimum_size().y
	var others := _frame_panel.get_combined_minimum_size().y - _frame_scroll.custom_minimum_size.y
	var room := maxf(MIN_BODY_HEIGHT, get_viewport_rect().size.y - SCREEN_MARGIN * 2.0 - others)
	var height := minf(wanted, room)
	if not is_equal_approx(height, _frame_scroll.custom_minimum_size.y):
		_frame_scroll.custom_minimum_size.y = height


## Once the window has opened centered, its top edge stays put: content that grows or shrinks
## (hiring someone, spending a point, a result line) only moves the bottom edge instead of making
## the whole window jump as it re-centers (M14b fix). _keep_on_screen moves it up when it grows.
## Switching to another tab is a new page: the window centers itself again for it.
func _pin_top(panel: Control) -> void:
	await _center(panel)
	if not is_instance_valid(panel):
		return
	_pinned = true
	for tabs: TabContainer in panel.find_children("*", "TabContainer", true, false):
		tabs.tab_changed.connect(func(_tab: int) -> void: _center(panel))


## Centers the window on its current height, once the containers have sorted (a frame or two),
## and fixes its top edge there.
func _center(panel: Control) -> void:
	for i in 2:
		await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	var half_screen := get_viewport_rect().size.y * 0.5
	var top := maxf(-panel.get_combined_minimum_size().y * 0.5, SCREEN_MARGIN - half_screen)
	panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.offset_top = top
	panel.offset_bottom = top
	_keep_on_screen(panel)


## A pinned window that grew past the bottom of the screen (a taller tab) moves up just enough;
## one taller than the screen goes back to the middle, where ScreenFit shrinks it to fit.
func _keep_on_screen(panel: Control) -> void:
	if not _pinned:
		return
	var screen := get_viewport_rect().size.y
	var height := panel.size.y
	var top := panel.offset_top
	if height > screen - SCREEN_MARGIN * 2.0:
		top = -height * 0.5
	else:
		top = clampf(top, SCREEN_MARGIN - screen * 0.5, screen * 0.5 - SCREEN_MARGIN - height)
	if not is_equal_approx(top, panel.offset_top):
		panel.offset_top = top
		panel.offset_bottom = top


## `preferred` px, or less when the screen is short: what is left after `reserved` px of the rest
## of the window (title, tabs, buttons). For lists and tab pages that scroll.
func fit_height(preferred: float, reserved: float) -> float:
	return clampf(get_viewport_rect().size.y - reserved, 160.0, preferred)


func close() -> void:
	closed.emit()
	queue_free()


## Adds a button to the action row, left of "Đóng".
func add_action(text: String, on_pressed: Callable, danger: bool = false) -> Button:
	var button := _button(text, on_pressed)
	button.custom_minimum_size = Vector2(160, 44)
	if danger:
		button.add_theme_color_override("font_color", UiPalette.WARNING_ON_WOOD)
	_actions.add_child(button)
	_actions.move_child(button, _close_button.get_index())
	return button


## Result of the last action, green when it went well.
func set_status(text: String, good: bool = true) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", GOOD_COLOR if good else WARNING_COLOR)
	if not good and not text.is_empty():
		Sfx.play(&"error")


## A preview line: plain when the action is possible, in the warning color when it is not.
func set_preview(label: Label, text: String, ok: bool) -> void:
	label.text = text
	if ok:
		label.remove_theme_color_override("font_color")
	else:
		label.add_theme_color_override("font_color", WARNING_COLOR)


func _unhandled_key_input(event: InputEvent) -> void:
	if _closable and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
	# Whatever is underneath must not react to keys while the window is open.
	get_viewport().set_input_as_handled()


## Labels inside a row must not wrap: a wrapping label in an HBoxContainer collapses to zero width.
func _label(text: String, font_size: int, wrap: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 44)
	button.pressed.connect(on_pressed)
	return button


func _row(children: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for child: Control in children:
		row.add_child(child)
	return row
