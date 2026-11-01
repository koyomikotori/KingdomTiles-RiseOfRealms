class_name CatalogWindow
extends ModalWindow
## A Kairosoft style shop in the middle of the screen (GDD §8, M12d): category tabs on top, the
## entries of the chosen category on the left, the chosen entry's picture and details on the right,
## and one action button below. BuildWindow and RecruitWindow fill it through the hooks below.

const ACCENT := UiPalette.ACCENT
const LIST_WIDTH := 310
const LIST_HEIGHT := 400
## Screen height the rest of the window needs (ModalWindow.fit_height).
const LIST_RESERVED := 350
const LIST_ICON := 32
## Opacity of entries that are not available yet.
const DIMMED_ALPHA := 0.55

var _category_buttons: Array[Button] = []
var _category := 0
var _list: VBoxContainer
var _entry_buttons: Dictionary = {}  # entry id -> Button
var _selected: StringName = &""
var _picture_box: CenterContainer
var _name_label: Label
var _details: Label
## Requirements, cost and effects as icons (RequirementView, M16c), filled by _fill_requirements.
var _requirements: RequirementView
var _reason: Label
var _action: Button


## `categories`: tab titles, the first one being "Tất cả".
func build_catalog(title: String, categories: Array[String], action_text: String) -> void:
	var body := build_frame(title, ACCENT, 0.62)
	# Many categories wrap onto a second row (the recruit window, M13b).
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 8)
	tabs.add_theme_constant_override("v_separation", 8)
	body.add_child(tabs)
	var group := ButtonGroup.new()
	for i in categories.size():
		var button := Button.new()
		button.text = categories[i]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(120, 38)
		button.button_pressed = i == 0
		button.pressed.connect(_show_category.bind(i))
		tabs.add_child(button)
		_category_buttons.append(button)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	body.add_child(columns)
	var list_frame := PanelContainer.new()
	list_frame.theme_type_variation = &"InsetPanel"
	columns.add_child(list_frame)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(LIST_WIDTH, fit_height(LIST_HEIGHT, LIST_RESERVED))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_frame.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	# Long details scroll beside the list instead of making the window taller than the screen
	# (ScreenFit would shrink the whole window) or change its size between entries.
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(detail_scroll)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 8)
	detail_scroll.add_child(detail)
	_picture_box = CenterContainer.new()
	_picture_box.custom_minimum_size = Vector2(0, 120)
	detail.add_child(_picture_box)
	_name_label = _label("", 20)
	_name_label.add_theme_color_override("font_color", UiPalette.ink(ACCENT))
	detail.add_child(_name_label)
	_details = _label("", 14)
	detail.add_child(_details)
	_requirements = RequirementView.new()
	detail.add_child(_requirements)
	_reason = _label("", 14)
	_reason.add_theme_color_override("font_color", WARNING_COLOR)
	detail.add_child(_reason)
	_action = add_action(action_text, func() -> void: _on_action(_selected))
	_show_category(0)


func _show_category(index: int) -> void:
	_category = index
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_entry_buttons.clear()
	var group := ButtonGroup.new()
	var ids := _entries(index)
	for id: StringName in ids:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = _entry_icon(id)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", LIST_ICON)
		button.custom_minimum_size = Vector2(0, LIST_ICON + 12)
		button.pressed.connect(_select.bind(id))
		_list.add_child(button)
		_entry_buttons[id] = button
	if ids.is_empty():
		_list.add_child(_label("Chưa có gì trong mục này.", 13))
	_select(_selected if ids.has(_selected) else (ids[0] if not ids.is_empty() else &""))


func _select(id: StringName) -> void:
	_selected = id
	for entry_id in _entry_buttons:
		_entry_buttons[entry_id].set_pressed_no_signal(entry_id == id)
	refresh()


## Entry labels, the details and the action button follow the current state.
func refresh() -> void:
	for id in _entry_buttons:
		var button: Button = _entry_buttons[id]
		button.text = _entry_text(id)
		var color := _entry_color(id)
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			if color.a > 0.0:
				button.add_theme_color_override(key, color)
			else:
				button.remove_theme_color_override(key)
		button.modulate.a = DIMMED_ALPHA if _entry_dimmed(id) else 1.0
	for child in _picture_box.get_children():
		_picture_box.remove_child(child)
		child.queue_free()
	if _selected == &"":
		_name_label.text = ""
		_details.text = ""
		_requirements.clear()
		_reason.text = ""
		_action.disabled = true
		return
	_picture_box.add_child(_picture(_selected))
	_name_label.text = _entry_name(_selected)
	_name_label.add_theme_color_override("font_color", _title_color(_selected))
	_details.text = _entry_details(_selected)
	_requirements.clear()
	_fill_requirements(_selected, _requirements)
	var reason := _block_reason(_selected)
	_reason.text = reason
	# The ✓ / ✗ lines already say why when the subclass fills them.
	_reason.visible = not reason.is_empty() and _requirements.get_child_count() == 0
	_action.disabled = not reason.is_empty()


# --- Hooks --------------------------------------------------------------------------------

## Name color on the wooden entry button; transparent = the theme's.
func _entry_color(_id: StringName) -> Color:
	return Color.TRANSPARENT


## Color of the chosen entry's name over the details (on paper).
func _title_color(_id: StringName) -> Color:
	return UiPalette.ink(ACCENT)


## Shown faded: not available yet (M13b).
func _entry_dimmed(_id: StringName) -> bool:
	return false


## Ids shown in category `index` (0 = all).
func _entries(_index: int) -> Array[StringName]:
	return []


func _entry_icon(_id: StringName) -> Texture2D:
	return null


func _entry_name(id: StringName) -> String:
	return String(id)


## The list button's text (name plus counts).
func _entry_text(id: StringName) -> String:
	return _entry_name(id)


func _picture(_id: StringName) -> Control:
	return Control.new()


func _entry_details(_id: StringName) -> String:
	return ""


## Requirements (✓ / ✗), cost chips and effects of the entry; empty by default.
func _fill_requirements(_id: StringName, _view: RequirementView) -> void:
	pass


## Why the action cannot be done right now; "" when it can.
func _block_reason(_id: StringName) -> String:
	return ""


func _on_action(_id: StringName) -> void:
	pass
