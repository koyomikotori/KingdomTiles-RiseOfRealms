class_name ForceCompare
extends VBoxContainer
## Before a battle the player starts (a siege, an attack on a clan; GDD §34, M18g): a bar with our
## soldiers against theirs, their side made longer by any defense bonus (walls), and a rough
## verdict. Only a guide: it counts soldiers, not unit types, generals or stratagems.

enum Odds { EASY, EVEN, HARD }

const ODDS_NAMES: Array[String] = ["Dễ thắng", "Cân sức", "Khó"]
const ODDS_COLORS: Array[Color] = [UiPalette.GOOD, Color(0.72, 0.5, 0.08), UiPalette.WARNING]
## Our soldiers ÷ their effective soldiers at or above which the battle looks easy / even.
const EASY_RATIO := 1.4
const EVEN_RATIO := 0.85
const BAR_HEIGHT := 14.0
const ENEMY_COLOR := Color(0.62, 0.2, 0.15)


static func odds(ours: int, theirs: int, bonus: float = 0.0) -> Odds:
	var effective := theirs * (1.0 + bonus)
	if effective <= 0.0:
		return Odds.EASY
	var ratio := ours / effective
	if ratio >= EASY_RATIO:
		return Odds.EASY
	if ratio >= EVEN_RATIO:
		return Odds.EVEN
	return Odds.HARD


## `bonus`: the defenders' extra share (e.g. Realm.WALL_DEFENSE), shown as a lighter end of their bar.
func setup(ours: int, our_color: Color, theirs: int, their_color: Color, bonus: float = 0.0,
		bonus_name: String = "") -> void:
	add_theme_constant_override("separation", 3)
	for child in get_children():
		child.queue_free()
	var verdict := odds(ours, theirs, bonus)
	var head := HBoxContainer.new()
	head.add_child(_label("Ta %d lính" % ours, UiPalette.ink(our_color)))
	var middle := _label(ODDS_NAMES[verdict], ODDS_COLORS[verdict], 15)
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(middle)
	head.add_child(_label("Địch %d lính" % theirs, UiPalette.ink(their_color)))
	add_child(head)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 0)
	bar.custom_minimum_size.y = BAR_HEIGHT
	add_child(bar)
	_segment(bar, our_color, maxf(1.0, ours))
	_segment(bar, their_color, maxf(1.0, theirs))
	if bonus > 0.0:
		_segment(bar, their_color.lightened(0.45), theirs * bonus)
	var note := "Ước lượng theo số lính"
	if bonus > 0.0:
		note += " · %s: địch mạnh thêm %d%%" % [bonus_name if bonus_name != "" else "phòng thủ", roundi(bonus * 100)]
	add_child(_label(note, UiPalette.MUTED, 12))


func _segment(bar: HBoxContainer, color: Color, weight: float) -> void:
	var rect := ColorRect.new()
	rect.color = color
	rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rect.size_flags_stretch_ratio = weight
	rect.custom_minimum_size.y = BAR_HEIGHT
	bar.add_child(rect)


func _label(text: String, color: Color, font_size: int = 13) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
