class_name NoticePanel
extends PanelContainer
## The notice column on the left of the kingdom screen (GDD §15, M14b): Notices.build() as
## sections of items, each a title with an arrow button on its right that folds its detail lines
## away (open by default; folded items are remembered by GameSettings). The « button folds the
## whole column into a thin strip. The cell info panel (`footer`) sits at the bottom of the column,
## and floats in the bottom-left corner on its own while the column is folded. Read-only.

const WIDTH := 300.0
const FOLDED_WIDTH := 52.0
const FOOTER_MARGIN := 12.0
const SECTION_FONT_SIZE := 16
const TITLE_FONT_SIZE := 14
const LINE_FONT_SIZE := 13
const EMPTY_TEXT := "Không có gì đáng chú ý."

var _list: VBoxContainer
var _scroll: ScrollContainer
var _title: Label
var _toggle: Button
var _footer_slot: VBoxContainer
var _footer: Control
## Where the footer floats while the column is folded.
var _footer_home: Node
var _sections: Array[Dictionary] = []
var _turn := 1


## `top`: the column starts this far down (under the top bar). `footer` (the cell info panel) moves
## into the column; `footer_home` is its parent while the column is folded.
func setup(top: float, footer: Control, footer_home: Node) -> void:
	_footer = footer
	_footer_home = footer_home
	set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	offset_top = top
	offset_bottom = 0.0
	# The cell info text wraps inside the column, and keeps the column's width when it floats.
	for label in footer.find_children("*", "Label", true, false):
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.custom_minimum_size.x = WIDTH - 20.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title = _label("", SECTION_FONT_SIZE, false)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_toggle = Button.new()
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.custom_minimum_size = Vector2(32, 30)
	_toggle.pressed.connect(func() -> void:
		GameSettings.set_notices_open(not GameSettings.notices_open())
		_apply_open())
	header.add_child(_toggle)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	_scroll.add_child(_list)
	_footer_slot = VBoxContainer.new()
	column.add_child(_footer_slot)
	_apply_open()


## Shows the notices for `turn` (Notices.build).
func show_notices(sections: Array[Dictionary], turn: int) -> void:
	_sections = sections
	_turn = turn
	_rebuild()


func _apply_open() -> void:
	var open := GameSettings.notices_open()
	custom_minimum_size.x = WIDTH if open else FOLDED_WIDTH
	offset_right = offset_left + custom_minimum_size.x
	_title.visible = open
	_scroll.visible = open
	_toggle.text = "«" if open else "»"
	_toggle.tooltip_text = "Thu gọn bảng thông báo" if open else "Mở bảng thông báo"
	if _footer == null:
		return
	if open and _footer.get_parent() != _footer_slot:
		_footer.reparent(_footer_slot, false)
		_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	elif not open and _footer.get_parent() != _footer_home:
		_footer.reparent(_footer_home, false)
		_footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, FOOTER_MARGIN)
		_footer.offset_left = FOLDED_WIDTH + FOOTER_MARGIN
		_footer.offset_right = _footer.offset_left
		_footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_title.text = "Thông báo · Lượt %d" % _turn


func _rebuild() -> void:
	_title.text = "Thông báo · Lượt %d" % _turn
	# Out of the list at once, so the old rows are never drawn under the new ones.
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if _sections.is_empty():
		var empty := _label(EMPTY_TEXT, LINE_FONT_SIZE)
		empty.add_theme_color_override("font_color", UiPalette.MUTED)
		_list.add_child(empty)
		return
	var folded := GameSettings.folded_notices()
	for section: Dictionary in _sections:
		var heading := _label(section.title, SECTION_FONT_SIZE)
		heading.add_theme_color_override("font_color", UiPalette.ACCENT)
		_list.add_child(heading)
		for item: Dictionary in section.items:
			_add_item(section.id, item, folded.has(Notices.key(section.id, item.id)))
		_list.add_child(HSeparator.new())


func _add_item(section_id: StringName, item: Dictionary, folded: bool) -> void:
	var row := HBoxContainer.new()
	var title := _label(item.title, TITLE_FONT_SIZE, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if item.warning:
		title.add_theme_color_override("font_color", UiPalette.WARNING)
	row.add_child(title)
	var arrow := Button.new()
	arrow.focus_mode = Control.FOCUS_NONE
	arrow.custom_minimum_size = Vector2(28, 26)
	arrow.text = "▸" if folded else "▾"
	arrow.tooltip_text = "Hiện chi tiết" if folded else "Ẩn chi tiết"
	row.add_child(arrow)
	_list.add_child(row)
	var details := _label("\n".join(item.lines.map(func(line: String) -> String: return "• " + line)), LINE_FONT_SIZE)
	details.visible = not folded
	_list.add_child(details)
	arrow.pressed.connect(func() -> void:
		details.visible = not details.visible
		arrow.text = "▾" if details.visible else "▸"
		arrow.tooltip_text = "Ẩn chi tiết" if details.visible else "Hiện chi tiết"
		GameSettings.set_notice_folded(Notices.key(section_id, item.id), not details.visible))


## Labels inside a row must not wrap (a wrapping label in an HBoxContainer collapses to zero
## width): they clip instead.
func _label(text: String, font_size: int, wrap: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Start at the list's width: a rebuild after this frame's layout would otherwise draw the
		# label 1 px wide (one letter per line), which crashed the engine on Vietnamese text.
		label.size.x = maxf(_list.size.x, WIDTH - 40.0)
	else:
		label.clip_text = true
	label.add_theme_font_size_override("font_size", font_size)
	return label
