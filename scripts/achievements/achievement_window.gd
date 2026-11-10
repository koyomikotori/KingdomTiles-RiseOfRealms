class_name AchievementWindow
extends ModalWindow
## The achievements board (M18b, GDD §30), from the main menu: how many are unlocked, then one
## list in the file's order (easy to hard, hidden ones last; the window's own scroll, no inner one)
## with one row per achievement: its medal (gray while locked; a "?" medal for a hidden one still
## locked), title, what to do (hidden ones say nothing until unlocked), the best progress so far,
## the reward and the day it was reached.

const MEDAL_SIZE := Vector2(48, 48)
const LOCKED_MODULATE := Color(0.35, 0.35, 0.35, 0.8)
const UNLOCKED_COLOR := UiPalette.ACCENT
const REWARD_COLOR := Color(0.55, 0.32, 0.05)


func open() -> void:
	var body := build_frame("Thành tựu", UiPalette.ACCENT, 0.6)
	var total := Achievements.all().size()
	var done := 0
	for entry in Achievements.all():
		done += 1 if AchievementStore.is_unlocked(entry.id) else 0
	var summary := _label("Đã đạt %d/%d thành tựu (%d%%). Thành tựu giữ qua mọi ván; phần thưởng là màu quân, danh hiệu và khung chân dung chọn ở màn Ván mới." % [
			done, total, roundi(100.0 * done / maxf(1.0, total))], 15)
	body.add_child(summary)
	var bar := ProgressBar.new()
	bar.max_value = total
	bar.value = done
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	body.add_child(bar)
	for entry in Achievements.all():
		body.add_child(_entry_row(entry))


static func medal_texture(entry: Dictionary, unlocked: bool) -> Texture2D:
	if entry.hidden and not unlocked:
		return GameArt.icon(Achievements.SECRET_ICON)
	return GameArt.icon(StringName("achievement_" + String(entry.category)))


func _entry_row(entry: Dictionary) -> Control:
	var unlocked := AchievementStore.is_unlocked(entry.id)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InsetPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var medal := TextureRect.new()
	medal.texture = medal_texture(entry, unlocked)
	medal.custom_minimum_size = MEDAL_SIZE
	medal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	medal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	medal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not unlocked:
		medal.modulate = LOCKED_MODULATE
	row.add_child(medal)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	var secret: bool = entry.hidden and not unlocked
	var title := _label("Thành tựu ẩn" if secret else String(entry.title), 16)
	title.add_theme_color_override("font_color", UNLOCKED_COLOR if unlocked else MUTED_COLOR)
	column.add_child(title)
	column.add_child(_label("Đạt được rồi mới biết." if secret else String(entry.description), 14))
	if not unlocked and not secret and entry.target > 1:
		var have := mini(AchievementStore.progress(entry.id), entry.target)
		var progress := HBoxContainer.new()
		progress.add_theme_constant_override("separation", 8)
		var bar := ProgressBar.new()
		bar.max_value = entry.target
		bar.value = have
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(160, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		progress.add_child(bar)
		progress.add_child(_label("%d/%d (cao nhất từng đạt)" % [have, entry.target], 12, false))
		column.add_child(progress)
	var reward := Achievements.reward_text(entry)
	if not reward.is_empty() and not secret:
		var reward_label := _label("Phần thưởng · " + reward, 13)
		reward_label.add_theme_color_override("font_color", REWARD_COLOR if unlocked else MUTED_COLOR)
		column.add_child(reward_label)
	if unlocked:
		var date := Time.get_datetime_dict_from_unix_time(AchievementStore.unlocked_at(entry.id))
		var when := _label("Đạt ngày %02d/%02d/%d" % [date.day, date.month, date.year], 12, false)
		when.add_theme_color_override("font_color", MUTED_COLOR)
		column.add_child(when)
	return panel
