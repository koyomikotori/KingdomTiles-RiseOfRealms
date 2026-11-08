class_name CameraController
extends Camera2D
## Mouse wheel (or a trackpad pinch) zooms toward the cursor; right or middle mouse drag pans, and
## the board view asks for left-button pans through pan().

@export var min_zoom := 0.75
@export var max_zoom := 4.0
@export var zoom_step := 1.15

var _dragging := false
var _bounds := Rect2()


## Centers the camera on `rect` and picks a zoom that fits it.
## `reserved_right` / `reserved_top` / `reserved_left` are screen pixels covered by UI on those
## sides (side panel, resource bar, notice column), so the board is centered in the visible area.
func focus_on(rect: Rect2, reserved_right: float = 0.0, reserved_top: float = 0.0, reserved_left: float = 0.0) -> void:
	_bounds = rect
	var view_size := get_viewport_rect().size - Vector2(reserved_right + reserved_left, reserved_top)
	var fit := minf(view_size.x / rect.size.x, view_size.y / rect.size.y) * 0.9
	var z := clampf(fit, min_zoom, max_zoom)
	zoom = Vector2(z, z)
	position = rect.get_center() + Vector2((reserved_right - reserved_left) * 0.5, -reserved_top * 0.5) / z


func _ready() -> void:
	# Two-finger pinch on a phone (M15a).
	var touch := get_node_or_null("/root/TouchInput")
	if touch != null:
		touch.pinched.connect(func(center: Vector2, factor: float) -> void:
			if get_viewport().gui_get_hovered_control() == null:
				_zoom_at(center, factor))


## Moves the view by a drag of `screen_relative` pixels (the map follows the mouse).
func pan(screen_relative: Vector2) -> void:
	position -= screen_relative / zoom.x
	_clamp_to_bounds()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture:
		_zoom_at(event.position, event.factor)
		return
	if event is InputEventMouseButton:
		# Over a panel the wheel belongs to the panel (scrolling a tab), even when the panel let the
		# event through (nothing left to scroll, or the cursor is on a label).
		if _is_wheel(event) and get_viewport().gui_get_hovered_control() != null:
			return
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_at(event.position, zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_at(event.position, 1.0 / zoom_step)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		position -= event.relative / zoom.x
		_clamp_to_bounds()


## Keeps the world point under the cursor fixed while zooming.
func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var new_zoom := clampf(zoom.x * factor, min_zoom, max_zoom)
	var offset_from_center := screen_pos - get_viewport_rect().size * 0.5
	var world_under_cursor := position + offset_from_center / zoom.x
	zoom = Vector2(new_zoom, new_zoom)
	position = world_under_cursor - offset_from_center / new_zoom
	_clamp_to_bounds()


func _clamp_to_bounds() -> void:
	if _bounds.has_area():
		position = position.clamp(_bounds.position, _bounds.end)


static func _is_wheel(event: InputEventMouseButton) -> bool:
	return event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT,
			MOUSE_BUTTON_WHEEL_RIGHT]
