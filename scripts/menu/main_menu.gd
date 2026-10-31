extends Control
## Main menu (GDD §10.1): continue the latest save, start a new game, load a slot, quit.
## Wood + paper look (GDD §13). Built in code.

const BACKGROUND_COLOR := UiPalette.BACKDROP
const TITLE_COLOR := UiPalette.ACCENT
const WARNING_COLOR := UiPalette.WARNING
## The castle picture above the title, ×4 (×2 in a short game window).
const CASTLE_SCALE := 4
const SHORT_CASTLE_SCALE := 2
## Below this height (design pixels) the menu uses the compact sizes.
const SHORT_SCREEN := 700.0
const NEW_GAME_TEXT := "Ván mới"

var _system := SaveSystem.new()
var _continue_button: Button
var _continue_info: Label
var _new_game_button: Button
var _status: Label


func _ready() -> void:
	Sfx.music(&"menu")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = BACKGROUND_COLOR
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	# Gameplay playing by itself, blurred (GDD §15 M14j).
	add_child(MenuBackdrop.new())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var paper := PanelContainer.new()
	center.add_child(paper)
	# A short game window shrinks the menu so every button (Thoát too) stays visible.
	paper.resized.connect(func() -> void: ScreenFit.shrink_to_fit(paper, get_viewport_rect().size))
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 24)
	paper.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.custom_minimum_size = Vector2(420, 0)
	margin.add_child(column)
	var castle := TextureRect.new()
	castle.texture = GameArt.castle(6)
	var short := get_viewport_rect().size.y < SHORT_SCREEN
	castle.custom_minimum_size = Vector2(32, 32) * (SHORT_CASTLE_SCALE if short else CASTLE_SCALE)
	castle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	castle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(castle)

	var title := _label("Kingdom Tiles", 36 if short else 48)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	column.add_child(title)
	var subtitle := _label("Rise Of Realms", 22)
	subtitle.add_theme_color_override("font_color", UiPalette.MUTED)
	column.add_child(subtitle)
	column.add_child(_spacer(8 if short else 24))

	_continue_button = _button("Tiếp tục", _on_continue_pressed)
	column.add_child(_continue_button)
	_continue_info = _label("", 13)
	_continue_info.add_theme_color_override("font_color", UiPalette.MUTED)
	column.add_child(_continue_info)
	_new_game_button = _button(NEW_GAME_TEXT, _on_new_game_pressed)
	column.add_child(_new_game_button)
	column.add_child(_button("Tải game", _on_load_pressed))
	column.add_child(_button("Cài đặt", func() -> void:
		var window := SettingsWindow.new()
		add_child(window)
		window.open()))
	column.add_child(_button("Thoát", func() -> void: get_tree().quit()))
	_status = _label("", 14)
	_status.add_theme_color_override("font_color", WARNING_COLOR)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_refresh()


func _refresh() -> void:
	var slot := _system.latest_slot()
	_continue_button.disabled = slot == ""
	_continue_info.text = "Chưa có bản lưu nào." if slot == "" else "%s: %s" % [SaveSystem.slot_name(slot),
			SaveSlotWindow.describe(_system.slot_info(slot))]


func _on_continue_pressed() -> void:
	_status.text = GameLaunch.load_game(get_tree(), _system, _system.latest_slot())


## A new game soon overwrites the autosave: the first click warns when there is one.
func _on_new_game_pressed() -> void:
	if _system.has_save(SaveSystem.AUTO_SLOT) and _new_game_button.text == NEW_GAME_TEXT:
		_new_game_button.text = "Bản tự động sẽ bị ghi đè. Bấm lần nữa để bắt đầu"
		_new_game_button.add_theme_color_override("font_color", UiPalette.WARNING_ON_WOOD)
		return
	# The choices first (GDD §15 M14h): name, color, difficulty.
	var window := NewGameWindow.new()
	add_child(window)
	window.open()
	window.start_requested.connect(func(settings: Dictionary) -> void: GameLaunch.new_game(get_tree(), settings))


func _on_load_pressed() -> void:
	var window := SaveSlotWindow.new()
	add_child(window)
	window.open(SaveSlotWindow.Mode.LOAD, _system)
	window.load_requested.connect(func(slot: String) -> void:
		var error := GameLaunch.load_game(get_tree(), _system, slot)
		if error != "":
			window.show_error(error))


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 56)
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(on_pressed)
	return button


func _spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer
