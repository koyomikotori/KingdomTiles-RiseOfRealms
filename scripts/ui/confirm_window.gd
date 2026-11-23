class_name ConfirmWindow
extends ModalWindow
## The confirmation for costly or lasting actions (GDD §34, M18g): a small window over a dimmed
## screen with the question, what the action costs and gives drawn with icons (a RequirementView
## filled by the caller), "Hủy" (Esc) and the action's own button (Enter). Opened on top of
## whatever asked (a building window, the officer window, the army tab); nothing happens until
## the player confirms.

signal confirmed

const WIDTH := 0.38

var _done := false


## `fill` gets the RequirementView to draw costs, gains, units and turns into (may be empty).
## Returns the window (already added under `host`).
static func ask(host: Node, title: String, question: String, fill: Callable, confirm_text: String,
		on_confirm: Callable, danger: bool = false) -> ConfirmWindow:
	var window := ConfirmWindow.new()
	host.add_child(window)
	window.open(title, question, fill, confirm_text, danger)
	window.confirmed.connect(on_confirm)
	return window


func open(title: String, question: String, fill: Callable = Callable(), confirm_text: String = "Xác nhận",
		danger: bool = false) -> void:
	var body := build_frame(title, UiPalette.WARNING if danger else UiPalette.ACCENT, WIDTH)
	_close_button.text = Touch.keys("Hủy (Esc)")
	if question != "":
		body.add_child(_label(question, 16))
	if fill.is_valid():
		var view := RequirementView.new()
		body.add_child(view)
		fill.call(view)
	var button := add_action(Touch.keys(confirm_text + " (Enter)"), _confirm, danger)
	button.custom_minimum_size.x = 190


func _confirm() -> void:
	if _done:
		return
	_done = true
	close()
	confirmed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_confirm()
		get_viewport().set_input_as_handled()
		return
	super(event)
