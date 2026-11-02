class_name NewGameWindow
extends ModalWindow
## Starting a new game (GDD §15, M14h): a picture of the kingdom at its greatest (the level-6
## castle and its soldiers) in the chosen color, the ruler ("Thay đổi" opens RulerWindow, M16h),
## the kingdom's name, its color and, near the bottom, the difficulty; "Bắt đầu chơi" or back to
## the main menu. Legendary stays locked until a
## game was won on Normal or Hard (GameSettings.legendary_unlocked).

## The choices are made: {"difficulty", "name", "color", "ruler_preset", "ruler_name"} for
## KingdomState.setup_new_game.
signal start_requested(settings: Dictionary)

const SWATCH_SIZE := Vector2(44, 44)
const CASTLE_SIZE := Vector2(160, 160)
const PREVIEW_HEIGHT := 190.0
const FIGURE_SCALE := 3
## The soldiers shown beside the castle: a new game's starting squads.
const PREVIEW_UNITS: Array[StringName] = [&"swordsman", &"spearman", &"archer"]
const PREVIEW_GRASS := Color(0.47, 0.66, 0.33)

var _name_edit: LineEdit
var _color := KingdomState.PLAYER_COLOR
var _difficulty: int = Difficulty.Level.NORMAL
var _castle: TextureRect
var _figures: Array[OfficerFigure] = []
var _commander: General
var _ruler := Ruler.from_preset(0)
var _ruler_label: Label
var _color_row: HBoxContainer
var _difficulty_row: HBoxContainer
var _description: Label


func open() -> void:
	var body := build_frame("Ván mới", UiPalette.TEXT, 0.5, false)
	body.add_child(_build_preview())
	_ruler_label = _label("", 15, false)
	_ruler_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_row([_ruler_label, _button("Thay đổi", _open_ruler)]))
	body.add_child(_label("Tên gia tộc của bạn:", 15, false))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = KingdomState.DEFAULT_KINGDOM_NAME
	_name_edit.max_length = KingdomState.MAX_NAME_LENGTH
	_name_edit.custom_minimum_size = Vector2(0, 40)
	body.add_child(_name_edit)
	body.add_child(_label("Màu chủ đạo (thành trì, áo quân, bản đồ):", 15, false))
	_color_row = HBoxContainer.new()
	_color_row.add_theme_constant_override("separation", 8)
	body.add_child(_color_row)
	body.add_child(HSeparator.new())
	body.add_child(_label("Độ khó:", 15, false))
	_difficulty_row = HBoxContainer.new()
	_difficulty_row.add_theme_constant_override("separation", 8)
	body.add_child(_difficulty_row)
	_description = _label("", 14)
	body.add_child(_description)
	add_action("Bắt đầu chơi", _start)
	add_action("Về màn hình chính", close)
	_refresh()


## The level-6 castle with the commander and the starting soldiers in front, on grass.
func _build_preview() -> Control:
	var frame := PanelContainer.new()
	frame.theme_type_variation = &"InsetPanel"
	var grass := ColorRect.new()
	grass.color = PREVIEW_GRASS
	grass.custom_minimum_size = Vector2(0, PREVIEW_HEIGHT)
	frame.add_child(grass)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grass.add_child(row)
	_castle = TextureRect.new()
	_castle.custom_minimum_size = CASTLE_SIZE
	_castle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_castle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_castle.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_castle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_castle)
	_commander = General.new()
	_commander.look = OfficerLook.from_seed("Kingdom Tiles")
	var units := {}
	for unit in UnitData.load_all():
		units[unit.unit_id] = unit
	var figures: Array[OfficerFigure] = []
	figures.append(OfficerFigure.new())
	for unit_id in PREVIEW_UNITS:
		if units.has(unit_id):
			var figure := OfficerFigure.new()
			figure.set_meta(&"unit", units[unit_id])
			figures.append(figure)
	for figure in figures:
		figure.size_flags_vertical = Control.SIZE_SHRINK_END
		row.add_child(figure)
	_figures = figures
	return frame


func _refresh() -> void:
	_castle.texture = GameArt.castle(6, _color)
	for figure in _figures:
		if figure.has_meta(&"unit"):
			figure.setup_unit(figure.get_meta(&"unit"), FIGURE_SCALE, _color)
		else:
			figure.setup(_commander, 2, _color)
	for row: Container in [_color_row, _difficulty_row]:
		for child in row.get_children():
			row.remove_child(child)
			child.queue_free()
	for color in KingdomState.PLAYER_COLORS:
		var swatch := Button.new()
		swatch.custom_minimum_size = SWATCH_SIZE
		swatch.focus_mode = Control.FOCUS_NONE
		var box := StyleBoxFlat.new()
		box.bg_color = color
		box.set_border_width_all(4 if color == _color else 1)
		box.border_color = UiPalette.TEXT if color == _color else color.darkened(0.4)
		box.set_corner_radius_all(4)
		for state_name in ["normal", "hover", "pressed"]:
			swatch.add_theme_stylebox_override(state_name, box)
		swatch.pressed.connect(func() -> void:
			_color = color
			_refresh())
		_color_row.add_child(swatch)
	var unlocked := GameSettings.legendary_unlocked()
	for level in Difficulty.NAMES.size():
		var button := _button(Difficulty.NAMES[level], func() -> void:
			_difficulty = level
			_refresh())
		button.toggle_mode = true
		button.button_pressed = level == _difficulty
		button.custom_minimum_size = Vector2(130, 44)
		button.disabled = level == Difficulty.Level.LEGENDARY and not unlocked
		_difficulty_row.add_child(button)
	_ruler_label.text = "Chúa công: %s (%s)" % [_ruler.name, _ruler.describe()]
	_description.text = Difficulty.DESCRIPTIONS[_difficulty]
	if not unlocked:
		_description.text += "\nHuyền thoại mở sau khi thắng một ván Bình thường hoặc Khó."


func _open_ruler() -> void:
	var window := RulerWindow.new()
	get_parent().add_child(window)
	window.open(_ruler.preset, _ruler.name, _color)
	window.chosen.connect(func(preset: int, ruler_name: String) -> void:
		_ruler = Ruler.from_preset(preset, ruler_name)
		_refresh())


func _start() -> void:
	start_requested.emit({"difficulty": _difficulty, "name": _name_edit.text, "color": _color,
			"ruler_preset": _ruler.preset, "ruler_name": _ruler.name})


## Esc goes back to the main menu.
func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
	get_viewport().set_input_as_handled()
