class_name RequirementView
extends VBoxContainer
## Costs and conditions drawn with icons instead of sentences (M16c): section headers, ✓ / ✗
## requirement lines, resource chips (an icon and the amount; green when the stockpile holds
## enough, red when it does not, the tooltip says how much is held), ▲ gains and info lines with an
## icon (turns to wait). Built in code and refilled by the window that owns it; read-only.

const ICON_SIZE := 22
const MET_COLOR := UiPalette.GOOD
const UNMET_COLOR := UiPalette.WARNING
const HEADER_SIZE := 13
const TEXT_SIZE := 14

var _resource_types: Array[ResourceTypeData] = ResourceTypeData.load_all()


func _init() -> void:
	add_theme_constant_override("separation", 4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


## A small colored title over a section ("YÊU CẦU", "CHI PHÍ", "NHẬN ĐƯỢC"), with a rule under it.
func header(text: String) -> void:
	var label := _text(text.to_upper(), HEADER_SIZE, UiPalette.ink(UiPalette.ACCENT))
	if get_child_count() > 0:
		label.add_theme_constant_override("line_spacing", 0)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 4)
		add_child(gap)
	add_child(label)
	var rule := HSeparator.new()
	rule.add_theme_constant_override("separation", 2)
	add_child(rule)


## "✓ text" in green when met, "✗ text" in red when not. Returns `met` so callers can count.
func requirement(text: String, met: bool) -> bool:
	add_child(_icon_line(&"check" if met else &"cross", text, MET_COLOR if met else UNMET_COLOR))
	return met


## Resource chips after an optional muted caption; with `stockpile` each one is green or red by
## what is held.
func costs(amounts: Dictionary[StringName, int], stockpile: Stockpile = null, caption: String = "") -> void:
	var row := _flow()
	if caption != "":
		row.add_child(_text(caption, TEXT_SIZE, UiPalette.MUTED))
	_add_chips(row, amounts, stockpile, false)
	add_child(row)


## Resource chips for incomes or upkeep (`signed` adds + / −), after an optional muted caption.
func amounts(caption: String, values: Dictionary[StringName, int], signed: bool = false) -> void:
	if values.is_empty():
		return
	var row := _flow()
	if caption != "":
		row.add_child(_text(caption, TEXT_SIZE, UiPalette.MUTED))
	_add_chips(row, values, null, signed)
	add_child(row)


## "▲ text": something the action gives.
func gain(text: String) -> void:
	# Effect texts are written to be joined mid-sentence (BuildingData.EFFECT_TEXTS): capitalize.
	add_child(_icon_line(&"gain", text.left(1).to_upper() + text.substr(1), UiPalette.TEXT))


## Unit chips: the unit's standing sprite and its name in its tier color, after a muted caption.
func units(caption: String, list: Array[UnitData]) -> void:
	if list.is_empty():
		return
	var row := _flow()
	if caption != "":
		row.add_child(_text(caption, TEXT_SIZE, UiPalette.MUTED))
	for unit in list:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 2)
		var icon := _icon(&"")
		icon.custom_minimum_size = Vector2(ICON_SIZE + 6, ICON_SIZE + 6)
		var sheet := GameArt.unit_sheet(unit.get_sprite_id())
		if sheet != null:
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = GameArt.unit_frame(sheet, &"stand", 0)
			icon.texture = atlas
		chip.add_child(icon)
		chip.add_child(_text(unit.display_name, TEXT_SIZE, unit.tier_color(false)))
		row.add_child(chip)
	add_child(row)


## An icon (GameArt.icon id, e.g. &"time", &"scroll") and a line of text.
func line(icon_id: StringName, text: String, color: Color = UiPalette.TEXT) -> void:
	add_child(_icon_line(icon_id, text, color))


## A muted line without an icon.
func note(text: String) -> void:
	add_child(_text(text, 13, UiPalette.MUTED))


func _flow() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	row.add_theme_constant_override("v_separation", 2)
	return row


func _add_chips(row: HFlowContainer, values: Dictionary[StringName, int], stockpile: Stockpile, signed: bool) -> void:
	for type in _resource_types:
		var amount: int = values.get(type.resource_id, 0)
		if amount == 0:
			continue
		var color := UiPalette.TEXT
		var tip := type.display_name
		if stockpile != null:
			var held := stockpile.get_amount(type.resource_id)
			color = MET_COLOR if held >= amount else UNMET_COLOR
			tip = "%s: cần %d, đang có %d" % [type.display_name, amount, held]
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 3)
		chip.tooltip_text = tip
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.add_child(_icon(type.resource_id))
		chip.add_child(_text("%+d" % amount if signed else str(amount), TEXT_SIZE + 1, color))
		row.add_child(chip)


func _icon_line(icon_id: StringName, text: String, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_icon(icon_id))
	var label := _text(text, TEXT_SIZE, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


func _icon(icon_id: StringName) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = GameArt.icon(icon_id) if icon_id != &"" else null
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
