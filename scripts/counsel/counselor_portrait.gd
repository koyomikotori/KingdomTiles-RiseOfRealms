class_name CounselorPortrait
extends Control
## A counselor's 96×96 portrait for one expression (GDD §25), drawn `art_scale` times like
## PortraitView: the drawn picture on the background inside a gold frame, or the generated parts
## of Counselor.fallback_officer when there is no picture yet.

var art_scale := 1.0
var _speaker := Counselor.LINH_NHI
var _expression := Counselor.NEUTRAL
## Loaded in setup: a texture loaded for the first time inside _draw came out as a white square.
var _picture: Texture2D


func setup(speaker: StringName, expression: StringName, scale: float = 1.0) -> void:
	_speaker = Counselor.valid(speaker)
	_expression = expression
	art_scale = scale
	_picture = Counselor.portrait(_speaker, _expression)
	custom_minimum_size = Vector2.ONE * PortraitView.SIZE * scale
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2.ONE * PortraitView.SIZE * art_scale)
	var officer := Counselor.fallback_officer(_speaker)
	if _picture != null:
		for texture: Texture2D in [GameArt.portrait_part("bg"), _picture, GameArt.portrait_part(PortraitView.frame_part(officer))]:
			if texture != null:
				draw_texture_rect(texture, rect, false)
		return
	for entry: Array in PortraitView.layers(officer, KingdomState.shown_color):
		var texture := GameArt.portrait_part(entry[0])
		if texture != null:
			draw_texture_rect(texture, rect, false, entry[1])
