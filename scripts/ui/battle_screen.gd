class_name BattleScreen
extends Control
## Full-screen battle (GDD §7.5): info | battlefield | info in a 10/80/10 split (the battlefield
## itself is 18/44/18), plus pause, speed, skip and retreat. Plays a BattleSimulator in real time
## and emits `finished` with the record once the result has been shown. Built in code.

signal finished(record: BattleRecord)

## Real seconds the result banner stays before `finished` is emitted.
const RESULT_DELAY := 1.6
## Battle seconds a stratagem message stays on screen.
const STRATAGEM_MESSAGE_TIME := 4.0
const STRATAGEM_COLOR := Color(1.0, 0.85, 0.35)
const BACKGROUND_COLOR := UiPalette.BACKDROP
const WIN_COLOR := Color(0.55, 0.95, 0.55)
const LOSS_COLOR := Color(1.0, 0.5, 0.45)

var _playback: BattlePlayback
## The battle side controlled by the player, drawn on the left.
var _player_side := BattleRecord.DEFENDER
var _view: BattleView
var _info_panels: Array[BattleInfoPanel] = []
var _time_label: Label
var _pause_button: Button
var _speed_buttons: Array[Button] = []
var _skip_button: Button
var _retreat_button: Button
var _result_label: Label
var _result_timer := -1.0
## Stratagems used at the start of the battle (GDD §8, M11f), shown over the battlefield.
var _stratagem_label: Label
var _stratagem_timer := 0.0
## Real seconds between steel sounds while the lines fight (randomized a little).
const CLASH_INTERVAL := 0.28
var _clash_timer := 0.0


## `player_side` is the BattleRecord side the player commands; it is drawn on the left.
func start(simulator: BattleSimulator, player_side: int, title: String) -> void:
	_playback = BattlePlayback.new(simulator)
	_player_side = player_side
	theme = _dark_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = BACKGROUND_COLOR
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	layout.add_child(_build_top_bar(title))
	layout.add_child(_build_middle(simulator))
	layout.add_child(_build_controls())
	_select_speed(0)
	Sfx.play(&"battle_start")


## A duel cannot be fled (M16e): the retreat button goes away.
func hide_retreat() -> void:
	_retreat_button.visible = false


func _process(delta: float) -> void:
	if _playback == null:
		return
	var events := _playback.advance(delta)
	var battle_delta := 0.0 if _playback.paused else delta * _playback.speed
	_view.update_view(battle_delta, events)
	_play_sounds(events, delta)
	_show_stratagems(events, battle_delta)
	for panel in _info_panels:
		panel.refresh()
	var seconds := roundi(_playback.simulator.time)
	_time_label.text = "%d:%02d" % [seconds / 60, seconds % 60]
	if _playback.is_finished():
		if _result_timer < 0.0:
			_show_result()
		_result_timer -= delta
		if _result_timer <= 0.0:
			set_process(false)
			finished.emit(_playback.simulator.record)
			queue_free()


## Sounds of the battle (M14a): one per simulator event, plus steel ringing now and then while the
## lines are in melee (CLASH_INTERVAL real seconds, faster at higher speeds).
func _play_sounds(events: Array[Dictionary], delta: float) -> void:
	for event in events:
		var side := _playback.simulator.record.sides[event.side]
		var unit: BattleSide.Unit = side.units[event.unit] if event.unit >= 0 and event.unit < side.units.size() else null
		match event.type:
			&"gun_volley":
				Sfx.play(&"cannon" if event.get("all_rows", false) else &"gun")
			&"arrow_volley":
				Sfx.play(&"crossbow" if unit != null and unit.data.armor_pierce > 0.0 else &"bow", -2.0)
			&"charge":
				Sfx.play(&"charge", -2.0)
			&"broken", &"retreat":
				Sfx.play(&"horn", -3.0)
			&"general_fallen":
				Sfx.play(&"general_fallen")
			&"stratagem":
				Sfx.play(&"stratagem")
	if _playback.paused or _playback.is_finished() or not _playback.simulator.is_melee_started():
		return
	_clash_timer -= delta * sqrt(_playback.speed)
	if _clash_timer <= 0.0:
		_clash_timer = CLASH_INTERVAL * randf_range(0.6, 1.4)
		Sfx.play(StringName("clash_%d" % randi_range(1, 3)), -6.0, 0.12)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_toggle_pause()
	# The kingdom underneath must not react to keys while a battle is on screen.
	get_viewport().set_input_as_handled()


# --- Layout -------------------------------------------------------------------------------

## The battle screen sits on dark wood (the info columns and bars around the battlefield): its
## labels are cream instead of the project theme's ink.
static func _dark_theme() -> Theme:
	var dark := Theme.new()
	dark.set_color("font_color", "Label", UiPalette.ON_WOOD)
	return dark


func _build_top_bar(title: String) -> Control:
	var bar := _margin(HBoxContainer.new(), 8)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.get_child(0).add_child(title_label)
	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 20)
	bar.get_child(0).add_child(_time_label)
	return bar


func _build_middle(simulator: BattleSimulator) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 0)
	var sides := [_player_side, 1 - _player_side]  # left, right
	for screen_side in 2:
		var panel := BattleInfoPanel.new()
		panel.setup(simulator.record.sides[sides[screen_side]], screen_side)
		_info_panels.append(panel)
	row.add_child(_info_column(_info_panels[0]))
	_view = BattleView.new()
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.size_flags_stretch_ratio = 8.0
	_view.clip_contents = true
	_view.setup(simulator, _player_side)
	row.add_child(_view)
	row.add_child(_info_column(_info_panels[1]))
	_result_label = Label.new()
	_result_label.add_theme_font_size_override("font_size", 48)
	_result_label.add_theme_constant_override("outline_size", 12)
	_result_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_result_label.visible = false
	_view.add_child(_result_label)
	_stratagem_label = Label.new()
	_stratagem_label.add_theme_font_size_override("font_size", 24)
	_stratagem_label.add_theme_constant_override("outline_size", 8)
	_stratagem_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_stratagem_label.add_theme_color_override("font_color", STRATAGEM_COLOR)
	_stratagem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stratagem_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_stratagem_label.offset_top = 12
	_view.add_child(_stratagem_label)
	return row


## Adds a line for each stratagem that worked; the lines fade after STRATAGEM_MESSAGE_TIME.
func _show_stratagems(events: Array[Dictionary], battle_delta: float) -> void:
	for event in events:
		if event.type != &"stratagem":
			continue
		var side := _playback.simulator.record.sides[event.side]
		var stratagem_name := String(event.stratagem)
		for stratagem in side.stratagems:
			if stratagem.stratagem_id == event.stratagem:
				stratagem_name = stratagem.display_name
		var line := "Mưu sĩ %s dùng %s!" % [side.advisor_name, stratagem_name]
		_stratagem_label.text = line if _stratagem_label.text.is_empty() else _stratagem_label.text + "\n" + line
		_stratagem_timer = STRATAGEM_MESSAGE_TIME
	if _stratagem_timer > 0.0:
		_stratagem_timer -= battle_delta
		_stratagem_label.modulate.a = clampf(_stratagem_timer, 0.0, 1.0)
		if _stratagem_timer <= 0.0:
			_stratagem_label.text = ""


## The info column scrolls, so a long army list never pushes the controls bar off screen.
func _info_column(panel: BattleInfoPanel) -> Control:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := _margin(panel, 8)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	return scroll


func _build_controls() -> Control:
	var bar := _margin(HBoxContainer.new(), 8)
	var row: HBoxContainer = bar.get_child(0)
	row.add_theme_constant_override("separation", 8)
	_pause_button = _button("Tạm dừng (Space)", _toggle_pause)
	row.add_child(_pause_button)
	for i in BattlePlayback.SPEEDS.size():
		var button := _button("x%d" % BattlePlayback.SPEEDS[i], _select_speed.bind(i))
		button.toggle_mode = true
		_speed_buttons.append(button)
		row.add_child(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_skip_button = _button("Bỏ qua tới kết quả", _on_skip)
	row.add_child(_skip_button)
	_retreat_button = _button("Rút lui", _on_retreat)
	_retreat_button.add_theme_color_override("font_color", LOSS_COLOR)
	row.add_child(_retreat_button)
	return bar


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
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(on_pressed)
	return button


# --- Controls -----------------------------------------------------------------------------

func _toggle_pause() -> void:
	if _playback.is_finished():
		return
	_playback.paused = not _playback.paused
	_pause_button.text = "Tiếp tục (Space)" if _playback.paused else "Tạm dừng (Space)"


func _select_speed(index: int) -> void:
	_playback.speed = BattlePlayback.SPEEDS[index]
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(i == index)


func _on_skip() -> void:
	_playback.skip()
	_view.snap_to_end()


## Retreat cannot be undone: the first click asks for confirmation.
func _on_retreat() -> void:
	if _playback.is_finished():
		return
	if _retreat_button.text == "Rút lui":
		_retreat_button.text = "Chắc chắn rút lui?"
		return
	_playback.retreat(_player_side)


func _show_result() -> void:
	_result_timer = RESULT_DELAY
	for button in [_pause_button, _skip_button, _retreat_button]:
		button.disabled = true
	for button in _speed_buttons:
		button.disabled = true
	var record := _playback.simulator.record
	var won := record.winner == _player_side
	if record.retreated_side == _player_side:
		_result_label.text = "RÚT LUI"
	else:
		_result_label.text = "CHIẾN THẮNG" if won else "THẤT BẠI"
	Sfx.sting(&"victory" if won and record.retreated_side != _player_side else &"defeat")
	_result_label.add_theme_color_override("font_color", WIN_COLOR if won else LOSS_COLOR)
	_result_label.visible = true
