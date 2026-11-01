class_name TextPagesWindow
extends ModalWindow
## A window of text pages, one tab each, every page scrolling on its own (M14c: Cách chơi,
## Giới thiệu). Subclasses fill it with `add_page`.

const ACCENT := UiPalette.ACCENT
const PAGE_HEIGHT := 420.0
const RESERVED := 220.0

var _tabs: TabContainer


func open_frame(title: String, width_share: float = 0.5) -> VBoxContainer:
	var body := build_frame(title, ACCENT, width_share)
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(0, fit_height(PAGE_HEIGHT, RESERVED))
	body.add_child(_tabs)
	return body


## A tab named `title` showing `paragraphs` (a line starting with "# " is a small heading);
## returns its box, for extra controls.
func add_page(title: String, paragraphs: Array, font_size: int = 15) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	for paragraph: String in paragraphs:
		if paragraph.begins_with("# "):
			var heading := _label(paragraph.substr(2), font_size + 2)
			heading.add_theme_color_override("font_color", ACCENT)
			box.add_child(heading)
		else:
			box.add_child(_label(paragraph, font_size))
	return box
