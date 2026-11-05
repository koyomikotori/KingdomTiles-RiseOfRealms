class_name CounselBox
extends VBoxContainer
## The counselor's words inside a window (GDD §25, M16i): one row per line with the speaker's
## portrait, name and words. Text is `width` wide so it never wraps a letter a line. The portrait
## has one size in every window (PORTRAIT_SCALE); a window makes room for it rather than shrink it.

const PORTRAIT_SCALE := 0.75


## `lines` from Counsel.lines; `on_wood` for dark backgrounds.
func setup(lines: Array[Dictionary], width: float, on_wood: bool = false) -> void:
	add_theme_constant_override("separation", 6)
	var portrait_width := PortraitView.SIZE * PORTRAIT_SCALE
	for line in lines:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		add_child(row)
		var portrait := CounselorPortrait.new()
		portrait.setup(line.speaker, line.expression, PORTRAIT_SCALE)
		portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		words.add_theme_constant_override("separation", 2)
		var name_label := Label.new()
		name_label.text = Counselor.NAMES[line.speaker]
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", UiPalette.ON_WOOD if on_wood
				else Counselor.NAME_COLORS[line.speaker])
		words.add_child(name_label)
		var text := Label.new()
		text.text = line.text
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(maxf(120.0, width - portrait_width - 10.0), 0)
		text.add_theme_font_size_override("font_size", 15)
		text.add_theme_color_override("font_color", UiPalette.ON_WOOD if on_wood else UiPalette.TEXT)
		words.add_child(text)
		row.add_child(portrait)
		row.add_child(words)
