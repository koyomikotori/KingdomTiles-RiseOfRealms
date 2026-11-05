class_name CounselWindow
extends ModalWindow
## A window of counselors' words only (GDD §25, M16i), e.g. the welcome of a new game. Closed with
## the button, Enter or Esc.

const COUNSEL_WIDTH := 0.42


func open(title: String, lines: Array[Dictionary]) -> void:
	var body := build_frame(title, UiPalette.HEADER, COUNSEL_WIDTH, false)
	var box := CounselBox.new()
	box.setup(lines, get_viewport_rect().size.x * COUNSEL_WIDTH - 60.0)
	body.add_child(box)
	add_action("Bắt đầu (Enter)", close)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		close()
		get_viewport().set_input_as_handled()
