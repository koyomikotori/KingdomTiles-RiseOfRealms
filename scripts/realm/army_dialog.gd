class_name ArmyDialog
extends ModalWindow
## Forms an army at the kingdom's capital, or regroups one standing there (GDD §33, M18f-a): pick
## one ready general (fixed when regrouping) and up to Realm.MAX_ARMY_SQUADS squads from those at
## home (and the army's own).

signal done

var _state: KingdomState
var _force: Realm.Force
var _general: General
var _general_buttons: Array[Button] = []
var _checks: Dictionary = {}  # CheckBox -> Army.Squad
var _count: Label


## `force` null forms a new army.
func open(state: KingdomState, force: Realm.Force = null) -> void:
	_state = state
	_force = force
	var body := build_frame("Lập đạo quân" if force == null else "Điều chỉnh đạo quân %s" % force.general.name,
			UiPalette.ACCENT, 0.5)
	if force == null:
		body.add_child(_label("Chọn tướng dẫn quân (tổng tướng đi thì tướng ở nhà nhiều sao nhất tạm chỉ huy quân giữ nhà):", 15))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		body.add_child(flow)
		for general in state.generals.generals:
			var button := Button.new()
			button.toggle_mode = true
			button.focus_mode = Control.FOCUS_NONE
			button.custom_minimum_size = Vector2(0, 40)
			button.text = "%s %s · Võ %d · Thống %d" % [general.name, general.star_text(), general.total_might(),
					general.total_command()]
			button.disabled = not general.is_ready()
			if not general.is_ready():
				button.text += " — " + (general.away_text() if general.away else "bị thương")
			button.pressed.connect(_pick_general.bind(general, button))
			flow.add_child(button)
			_general_buttons.append(button)
		if state.generals.generals.is_empty():
			body.add_child(_label("Chưa có tướng nào. Chiêu hiền ở thành chính.", 14))
	_count = _label("", 15)
	body.add_child(_count)
	var list := VBoxContainer.new()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = fit_height(320.0, 330.0)
	scroll.add_child(list)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	for squad in state.army.squads:
		var mine := force != null and force.squads.has(squad)
		if squad.away and not mine:
			continue
		var unit: UnitData = state.units[squad.unit_id]
		var check := CheckBox.new()
		check.focus_mode = Control.FOCUS_NONE
		check.text = "%s · %s — %d/%d lính" % [unit.display_name, Experience.SQUAD_LEVEL_NAMES[squad.level()],
				squad.soldiers, unit.squad_size]
		check.button_pressed = mine
		check.toggled.connect(func(_on: bool) -> void: _refresh())
		list.add_child(check)
		_checks[check] = squad
	if _checks.is_empty():
		list.add_child(_label("Không còn đơn vị nào ở nhà.", 14))
	add_action("Lập đạo quân" if force == null else "Cập nhật", _confirm)
	_refresh()


func _pick_general(general: General, pressed: Button) -> void:
	_general = general
	for button in _general_buttons:
		button.set_pressed_no_signal(button == pressed)
	_refresh()


func _chosen() -> Array[Army.Squad]:
	var result: Array[Army.Squad] = []
	for check: CheckBox in _checks:
		if check.button_pressed:
			result.append(_checks[check])
	return result


func _refresh() -> void:
	var chosen := _chosen()
	var soldiers := 0
	for squad in chosen:
		soldiers += squad.soldiers
	set_preview(_count, "Đã chọn %d/%d đơn vị · %d lính" % [chosen.size(), Realm.MAX_ARMY_SQUADS, soldiers],
			chosen.size() <= Realm.MAX_ARMY_SQUADS)


func _confirm() -> void:
	var result: Realm.Result
	if _force == null:
		result = _state.realm.form(_state, _general, _chosen())
	else:
		result = _state.realm.regroup(_state, _force, _chosen())
	if result != Realm.Result.OK:
		set_status(Realm.describe(result), false)
		return
	Sfx.play(&"recruit")
	done.emit()
	close()
