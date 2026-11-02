class_name RulerWindow
extends ModalWindow
## Choosing the ruler (Chúa công, GDD §24, M16h) from the new game screen: one of Ruler.PRESETS
## (← / →) with its portrait in the kingdom's color, and a name. The foot sprite stays for the duel
## mini game (M16j).

## The ruler is chosen: Ruler.PRESETS index and name.
signal chosen(preset: int, ruler_name: String)

var _preset := 0
var _color := KingdomState.PLAYER_COLOR
var _portrait: PortraitView
var _title: Label
var _name_edit: LineEdit


func open(preset: int, ruler_name: String, color: Color) -> void:
	_preset = preset
	_color = color
	var body := build_frame("Chúa công", UiPalette.TEXT, 0.4)
	_portrait = PortraitView.new()
	_portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	body.add_child(_portrait)
	_title = _label("", 16, false)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var previous := _button("←", _step.bind(-1))
	var next := _button("→", _step.bind(1))
	for button in [previous, next]:
		button.custom_minimum_size = Vector2(56, 44)
	body.add_child(_row([previous, _title, next]))
	body.add_child(_label("Tên gọi (cố vấn vẫn gọi là \"Chúa công\"):", 15, false))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = Ruler.DEFAULT_NAME
	_name_edit.max_length = Ruler.MAX_NAME_LENGTH
	_name_edit.text = ruler_name if ruler_name != Ruler.DEFAULT_NAME else ""
	_name_edit.custom_minimum_size = Vector2(0, 40)
	body.add_child(_name_edit)
	add_action("Xong", _done)
	_refresh()


func _step(by: int) -> void:
	_preset = posmod(_preset + by, Ruler.PRESETS.size())
	_refresh()


func _refresh() -> void:
	var ruler := Ruler.from_preset(_preset)
	_portrait.setup(ruler, 2.0, _color)
	_title.text = "%s  (%d/%d)" % [ruler.describe(), _preset + 1, Ruler.PRESETS.size()]


func _done() -> void:
	chosen.emit(_preset, _name_edit.text)
	close()
