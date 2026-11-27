class_name ArmyFlag
extends Control
## A small flag in one of our armies' colors with its number (Realm.Force.flag, M18f QoL): the same
## flag the realm map draws over the army's town, so lists and the map match at a glance.

const POLE := 27.0
const CLOTH := Vector2(22, 15)
const POLE_COLOR := Color(0.25, 0.17, 0.1)
const OUTLINE := Color(0.15, 0.09, 0.05)

var color := Color.WHITE
var number := 0
var flag_scale := 1.0


static func of(force: Realm.Force, scale: float = 0.7) -> ArmyFlag:
	var flag := ArmyFlag.new()
	flag.color = Realm.flag_color(force)
	flag.number = force.flag + 1
	flag.flag_scale = scale
	flag.custom_minimum_size = Vector2(CLOTH.x + 6, POLE + 4) * scale
	flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return flag


func _draw() -> void:
	draw_flag(self, Vector2(3, size.y - 2), color, number, flag_scale)


## Draws a flag whose pole stands on `foot`: a swallowtail cloth in `cloth_color` with `number`,
## outlined in `border` (`border_width` thick).
static func draw_flag(canvas: CanvasItem, foot: Vector2, cloth_color: Color, flag_number: int, scale: float = 1.0,
		border: Color = OUTLINE, border_width: float = 1.5) -> void:
	var top := foot - Vector2(0, POLE * scale)
	canvas.draw_line(foot, top - Vector2(0, 2 * scale), POLE_COLOR, 2.5 * scale)
	var w := CLOTH.x * scale
	var h := CLOTH.y * scale
	var cloth := PackedVector2Array([top, top + Vector2(w, 0), top + Vector2(w * 0.75, h * 0.5), top + Vector2(w, h),
			top + Vector2(0, h)])
	canvas.draw_colored_polygon(cloth, cloth_color)
	var outline := cloth.duplicate()
	outline.append(top)
	canvas.draw_polyline(outline, border, border_width * maxf(scale, 0.7))
	if flag_number > 0:
		var font := ThemeDB.fallback_font
		var font_size := roundi(12 * scale)
		var text := str(flag_number)
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var ink := Color.BLACK if cloth_color.get_luminance() > 0.55 else Color.WHITE
		var at := top + Vector2(w * 0.4 - text_size.x * 0.5, h * 0.5 + font_size * 0.36)
		canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ink)
