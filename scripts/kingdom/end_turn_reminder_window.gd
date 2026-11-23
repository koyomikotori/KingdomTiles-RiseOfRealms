class_name EndTurnReminderWindow
extends ModalWindow
## "Chưa xong việc" (GDD §34, M18g): shown by "Kết thúc lượt" when EndTurnReminder finds something.
## Each row has "Xem" (`jump_requested`: the window closes and the kingdom scene opens that place),
## "Vẫn kết thúc" (Enter) ends the turn, "Quay lại" (Esc) does nothing; a hint says the reminder
## can be turned off in Cài đặt.

signal end_turn_confirmed
signal jump_requested(item: Dictionary)

const WIDTH := 0.42

var _done := false


func open(items: Array[Dictionary]) -> void:
	var body := build_frame("Chưa xong việc", UiPalette.ACCENT, WIDTH)
	_close_button.text = Touch.keys("Quay lại (Esc)")
	body.add_child(_label("Trước khi kết thúc lượt, bạn còn:", 16))
	for item in items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var text := _label("• " + str(item.text), 15)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var jump := _button("Xem", func() -> void:
			close()
			jump_requested.emit(item))
		jump.custom_minimum_size = Vector2(90, 36)
		row.add_child(jump)
		body.add_child(row)
	var hint := _label("Có thể tắt nhắc việc này trong Cài đặt.", 13)
	hint.add_theme_color_override("font_color", UiPalette.MUTED)
	body.add_child(hint)
	var button := add_action(Touch.keys("Vẫn kết thúc (Enter)"), _confirm)
	button.custom_minimum_size.x = 200


func _confirm() -> void:
	if _done:
		return
	_done = true
	close()
	end_turn_confirmed.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_confirm()
		get_viewport().set_input_as_handled()
		return
	super(event)
