class_name AchievementToast
extends Control
## The "Đạt thành tựu!" note (M18b, GDD §30) that slides in at the top right of the kingdom screen
## when an achievement unlocks: medal, title and reward. Several wait their turn. Never takes clicks.

const WIDTH := 340.0
## Below the top bar, from the right edge.
const TOP := 96.0
const MARGIN := 16.0
const SLIDE := 0.35
const STAY := 4.0

var _queue: Array[Dictionary] = []
var _showing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_unlocked(entry: Dictionary) -> void:
	_queue.append(entry)
	if not _showing:
		_next()


func _next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var entry: Dictionary = _queue.pop_front()
	var panel := _build(entry)
	add_child(panel)
	Sfx.play(&"complete")
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	panel.reset_size()
	var shown_x := get_viewport_rect().size.x - WIDTH - MARGIN
	panel.position = Vector2(get_viewport_rect().size.x + MARGIN, TOP)
	var tween := create_tween()
	tween.tween_property(panel, "position:x", shown_x, SLIDE).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(STAY)
	tween.tween_property(panel, "position:x", get_viewport_rect().size.x + MARGIN, SLIDE).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		panel.queue_free()
		_next())


func _build(entry: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A fixed width so the wrapped lines know how tall they are.
	panel.custom_minimum_size.x = WIDTH
	panel.position = Vector2(get_viewport_rect().size.x + MARGIN, TOP)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 10)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var medal := TextureRect.new()
	medal.texture = AchievementWindow.medal_texture(entry, true)
	medal.custom_minimum_size = AchievementWindow.MEDAL_SIZE
	medal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	medal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	medal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(medal)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	column.add_child(_text("Đạt thành tựu!", 12, UiPalette.MUTED))
	column.add_child(_text(String(entry.title), 17, UiPalette.ACCENT))
	var reward := Achievements.reward_text(entry)
	column.add_child(_text("Mở khóa · " + reward if not reward.is_empty() else String(entry.description), 13,
			AchievementWindow.REWARD_COLOR if not reward.is_empty() else UiPalette.TEXT))
	return panel


func _text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH - AchievementWindow.MEDAL_SIZE.x - 40.0
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
