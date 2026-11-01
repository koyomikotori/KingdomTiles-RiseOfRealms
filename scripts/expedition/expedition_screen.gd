class_name ExpeditionScreen
extends Control
## The full-screen replay of one expedition stage (ExpeditionView) with speed buttons and a skip,
## then the stage's statistics (GDD §15 M14i). Its own music. `closed` when the player is done.

signal closed

const SPEEDS: Array[float] = [1.0, 2.0, 4.0]
const STATS_COLUMNS: Array[String] = ["Đơn vị", "Còn", "Lính", "Mất", "Hạ"]
const STATS_KEYS: Array[String] = ["name", "left", "start", "lost", "kills"]
## The stats paper: what happened on the left (wrapped at this width), the team on the right.
const SUMMARY_WIDTH := 420

var _view: ExpeditionView
var _report: Dictionary
var _speed_buttons: Array[Button] = []
var _skip_button: Button
var _stats_shown := false


## `report`: the stage (Expedition.run_stage, plus "rewards" when it was the last one).
func open(report: Dictionary, stages: int) -> void:
	_report = report
	theme = BattleScreen._dark_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = BattleScreen.BACKGROUND_COLOR
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	var stage_text := "Ải %d/%d" % [report.stage + 1, stages]
	var title := Label.new()
	title.text = "Thảo phạt quân nổi loạn — %s" % stage_text
	title.add_theme_font_size_override("font_size", 20)
	layout.add_child(_margin(title, 8))
	_view = ExpeditionView.new()
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var battles: Array[BattleRecord] = []
	battles.assign(report.battles)
	_view.setup(battles, stage_text)
	_view.finished.connect(_show_stats)
	layout.add_child(_view)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for i in SPEEDS.size():
		var button := _button("x%d" % SPEEDS[i], _select_speed.bind(i))
		button.toggle_mode = true
		_speed_buttons.append(button)
		row.add_child(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_skip_button = _button("Bỏ qua tới kết quả", func() -> void: _view.skip())
	row.add_child(_skip_button)
	layout.add_child(_margin(row, 8))
	_select_speed(0)
	Sfx.music(&"expedition")


func _select_speed(index: int) -> void:
	_view.set_speed(SPEEDS[index])
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(i == index)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER]:
		if _stats_shown:
			_close()
		else:
			_view.skip()
	get_viewport().set_input_as_handled()


## The stage's statistics on paper over the replay: battles, the team's units, rewards.
func _show_stats() -> void:
	if _stats_shown:
		return
	_stats_shown = true
	_skip_button.disabled = true
	var dim := ColorRect.new()
	dim.color = UiPalette.DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.theme = null
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(_margin(column, 20))
	var won: bool = _report.won
	var title := _paper_label("Ải %d: %s" % [_report.stage + 1, "vượt ải!" if won else "thất bại"], 22)
	title.add_theme_color_override("font_color", UiPalette.GOOD if won else UiPalette.WARNING)
	column.add_child(title)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	column.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(SUMMARY_WIDTH, 0)
	left.add_theme_constant_override("separation", 6)
	columns.add_child(left)
	for line in summary_lines(_report, false):
		var label := _paper_label(line, 15)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		left.add_child(label)
	var rewards: Dictionary = _report.get("rewards", {})
	if not rewards.is_empty():
		left.add_child(_reward_view(rewards))
	columns.add_child(VSeparator.new())
	var grid := GridContainer.new()
	grid.columns = STATS_COLUMNS.size()
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	for heading in STATS_COLUMNS:
		grid.add_child(_paper_label(heading, 14, UiPalette.MUTED))
	for row in unit_rows(_report):
		for key in STATS_KEYS:
			var label := _paper_label(str(row[key]), 14)
			if key == "left" and row.left_count < row.squads:
				label.add_theme_color_override("font_color", UiPalette.WARNING)
			grid.add_child(label)
	columns.add_child(grid)
	var close := _button("Đóng (Enter)", _close)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	column.add_child(close)
	ScreenFit.shrink_to_fit(panel, get_viewport_rect().size)


func _close() -> void:
	Sfx.music(&"kingdom")
	closed.emit()
	queue_free()


## The rewards with icons: resources, items, scrolls, experience.
func _reward_view(rewards: Dictionary) -> RequirementView:
	var view := RequirementView.new()
	view.header("Phần thưởng")
	var amounts: Dictionary[StringName, int] = {}
	amounts.assign(rewards.resources)
	view.amounts("Thu được", amounts)
	for item: Item in rewards.items:
		view.gain("%s (%s)" % [item.display_name, Item.RARITY_NAMES[item.rarity]])
	if rewards.get("scrolls", 0) > 0:
		view.line(&"scroll", "Bí kíp đột phá +%d" % rewards.scrolls)
	if rewards.xp_officer > 0:
		view.gain("Kinh nghiệm: tướng sĩ +%d, lính +%d" % [rewards.xp_officer, rewards.xp_squad])
	return view


## The stage's result in a few lines: battles, the duel and the rebel general, fates, and (with
## `with_rewards`) the rewards when the expedition is over.
static func summary_lines(report: Dictionary, with_rewards: bool = true) -> Array[String]:
	var lines: Array[String] = []
	var battles: Array = report.battles
	var duel: Dictionary = report.get("duel", {})
	var won := 0
	for b in battles.size():
		if b != duel.get("index", -1):
			won += 1 if battles[b].winner == BattleRecord.ATTACKER else 0
	var fought := battles.size() - (1 if duel.get("index", -1) >= 0 else 0)
	lines.append("Trận đã đánh: %d · thắng %d." % [fought, won])
	var changes: Array[String] = []
	if report.get("team_morale", 0) != 0:
		changes.append("quân ta %+d" % report.team_morale)
	if report.get("rebel_morale", 0) != 0:
		changes.append("quân nổi loạn %+d" % report.rebel_morale)
	if not changes.is_empty():
		lines.append("Nhuệ khí tối đa trong ải này: %s." % ", ".join(changes))
	if not duel.is_empty():
		if not duel.accepted:
			lines.append("Tướng nổi loạn %s ra thách đấu, ta không nhận lời." % duel.rebel)
		elif duel.won:
			lines.append("Tướng nổi loạn %s thách đấu và tử trận dưới tay tướng ta. Ải sau quân nổi loạn %+d nhuệ khí tối đa."
					% [duel.rebel, -Expedition.DUEL_MORALE])
		else:
			lines.append("Tướng nổi loạn %s thách đấu và chém chết tướng ta. Ải sau quân ta %+d nhuệ khí tối đa."
					% [duel.rebel, -Expedition.DUEL_MORALE])
	if report.get("boss", "") != "":
		lines.append("Tướng nổi loạn %s xuất hiện cuối ải%s." % [report.boss, " và đã bị đánh bại" if report.won else ""])
	match report.get("general_fate", &"none"):
		&"dead":
			lines.append("Tướng dẫn đội đã tử trận!")
		&"wounded":
			lines.append("Tướng dẫn đội bị thương, nghỉ %d lượt." % Generals.WOUND_TURNS)
	if report.get("advisor_fate", &"none") == &"wounded":
		lines.append("Mưu sĩ bị thương, nghỉ %d lượt." % Advisors.WOUND_TURNS)
	if report.won and not report.get("finished", false):
		lines.append("Cả đội đã hồi phục; lượt sau tiến vào ải tiếp theo.")
	var rewards: Dictionary = report.get("rewards", {})
	if not rewards.is_empty():
		lines.append("Đội thảo phạt trở về%s." % (": vùng nổi loạn đã được dẹp yên" if report.get("cleared", false) else ""))
		if report.has("relation"):
			lines.append("Các gia tộc cảm kích: quan hệ +%d với mọi gia tộc." % report.relation)
	if not rewards.is_empty() and with_rewards:
		var amounts: Dictionary[StringName, int] = {}
		amounts.assign(rewards.resources)
		var text := UiFormat.amounts(amounts, ResourceTypeData.load_all())
		if not text.is_empty():
			lines.append("Thu được: %s." % text)
		var items: Array = rewards.items
		if not items.is_empty():
			lines.append("Trang bị: %s." % ", ".join(items.map(func(item: Item) -> String:
				return "%s (%s)" % [item.display_name, Item.RARITY_NAMES[item.rarity]])))
		if rewards.get("scrolls", 0) > 0:
			lines.append("Bí kíp đột phá: +%d." % rewards.scrolls)
		if rewards.xp_officer > 0:
			lines.append("Kinh nghiệm: tướng sĩ +%d, lính +%d." % [rewards.xp_officer, rewards.xp_squad])
	return lines


## One row per kind of unit in the team over the stage's battles (the duel left out):
## {"name", "squads", "left_count", "left": "kept/squads", "start", "lost", "kills"}.
static func unit_rows(report: Dictionary) -> Array[Dictionary]:
	var squads := {}
	var order: Array = []
	var battles: Array = report.battles
	var duel_index: int = report.get("duel", {}).get("index", -1)
	for b in battles.size():
		if b == duel_index:
			continue
		var record: BattleRecord = battles[b]
		var side := record.sides[BattleRecord.ATTACKER]
		for unit in side.units:
			var key: Variant = unit.squad if unit.squad != null else "guard"
			if not squads.has(key):
				order.append(key)
				squads[key] = {"name": "Cận vệ của %s" % side.general_name if unit.is_general_guard else unit.data.display_name,
						"start": unit.start_soldiers, "lost": 0, "kills": 0, "kept": true}
			var entry: Dictionary = squads[key]
			entry.lost += unit.lost()
			entry.kills += roundi(unit.kills)
			if unit.alive() == 0 or unit.broken or record.winner != BattleRecord.ATTACKER:
				entry.kept = false
	var rows := {}
	var names: Array = []
	for key in order:
		var entry: Dictionary = squads[key]
		if not rows.has(entry.name):
			names.append(entry.name)
			rows[entry.name] = {"name": entry.name, "squads": 0, "left_count": 0, "start": 0, "lost": 0, "kills": 0}
		var row: Dictionary = rows[entry.name]
		row.squads += 1
		row.left_count += 1 if entry.kept else 0
		row.start += entry.start
		row.lost += entry.lost
		row.kills += entry.kills
	var result: Array[Dictionary] = []
	for name in names:
		var row: Dictionary = rows[name]
		row["left"] = "%d/%d" % [row.left_count, row.squads]
		result.append(row)
	return result


func _paper_label(text: String, font_size: int, color: Color = UiPalette.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _margin(child: Control, amount: int) -> MarginContainer:
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, amount)
	margin.add_child(child)
	return margin


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(120, 40)
	button.pressed.connect(on_pressed)
	return button
