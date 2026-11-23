class_name RulerWindow
extends ModalWindow
## Choosing the ruler (Chúa công, GDD §24, M16h) from the new game screen: one of Ruler.PRESETS
## (← / →) with its portrait in the kingdom's color, a name, and (M18b) a title (danh hiệu) and a
## portrait frame among those the achievements unlocked. The preset's background (Xuất thân,
## RulerOrigin, M18d) and its advantages show under the arrows.

## The ruler is chosen: Ruler.PRESETS index, name, honor ("" none) and frame id ("" the gold one).
signal chosen(preset: int, ruler_name: String, honor: String, frame: String)

var _preset := 0
var _color := KingdomState.PLAYER_COLOR
var _portrait: PortraitView
var _title: Label
var _origin: Label
var _name_edit: LineEdit
## "" first (none), then the unlocked ones.
var _honors: Array = [""]
var _frames: Array = [""]
var _honor := 0
var _frame := 0
var _honor_label: Label
var _frame_label: Label


func open(preset: int, ruler_name: String, color: Color, honor: String = "", frame: String = "") -> void:
	_preset = preset
	_color = color
	_honors.append_array(Achievements.unlocked_rewards("honor"))
	_frames.append_array(Achievements.unlocked_rewards("frame"))
	_honor = maxi(0, _honors.find(honor))
	_frame = maxi(0, _frames.find(frame))
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
	_origin = _label("", 14)
	_origin.add_theme_color_override("font_color", MUTED_COLOR)
	body.add_child(_origin)
	body.add_child(_label("Tên gọi (cố vấn vẫn gọi là \"Chúa công\"):", 15, false))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = Ruler.DEFAULT_NAME
	_name_edit.max_length = Ruler.MAX_NAME_LENGTH
	_name_edit.text = ruler_name if ruler_name != Ruler.DEFAULT_NAME else ""
	_name_edit.custom_minimum_size = Vector2(0, 40)
	body.add_child(_name_edit)
	_honor_label = _choice_row(body, "Danh hiệu:", _step_honor)
	_frame_label = _choice_row(body, "Khung chân dung:", _step_frame)
	if _honors.size() == 1 and _frames.size() == 1:
		var note := _label("Danh hiệu và khung chân dung mở bằng Thành tựu ở màn hình chính.", 13)
		note.add_theme_color_override("font_color", MUTED_COLOR)
		body.add_child(note)
	add_action("Xong", _done)
	_refresh()


## "Caption:  ←  value  →"; the arrows step through `step`.
func _choice_row(body: VBoxContainer, caption: String, step: Callable) -> Label:
	var name_label := _label(caption, 15, false)
	name_label.custom_minimum_size.x = 150
	var value := _label("", 15, false)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var previous := _button("←", step.bind(-1))
	var next := _button("→", step.bind(1))
	for button in [previous, next]:
		button.custom_minimum_size = Vector2(44, 36)
	body.add_child(_row([name_label, previous, value, next]))
	return value


func _step_honor(by: int) -> void:
	_honor = posmod(_honor + by, _honors.size())
	_refresh()


func _step_frame(by: int) -> void:
	_frame = posmod(_frame + by, _frames.size())
	_refresh()


func _step(by: int) -> void:
	_preset = posmod(_preset + by, Ruler.PRESETS.size())
	_refresh()


func _refresh() -> void:
	var ruler := Ruler.from_preset(_preset)
	ruler.frame = _frames[_frame]
	_portrait.setup(ruler, 2.0, _color)
	_honor_label.text = "%s  (%d/%d)" % [_honors[_honor] if _honor > 0 else "Không", _honor + 1, _honors.size()]
	_frame_label.text = "%s  (%d/%d)" % [Achievements.frame_name(_frames[_frame]) if _frame > 0 else "Vàng (mặc định)",
			_frame + 1, _frames.size()]
	_title.text = "%s  (%d/%d)" % [ruler.describe(), _preset + 1, Ruler.PRESETS.size()]
	_origin.text = RulerOrigin.summary(ruler.origin())


func _done() -> void:
	chosen.emit(_preset, _name_edit.text, _honors[_honor], _frames[_frame])
	close()
