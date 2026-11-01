class_name BuildingWindow
extends ModalWindow
## Opens when a building on the board is tapped (Kairosoft style): its information and upgrade
## tabs (the castle also has "Chiêu hiền" to recruit generals and advisors, GDD §8 M11d/M11f;
## they are managed in the "Tướng sĩ" side tab, M12c), and the actions below (upgrade, move,
## demolish). While it is being built or upgraded (M12d) it only shows the turns left and
## "Phá hủy" / "Hủy nâng cấp". Every action first explains what it will do and waits for "Xác nhận".

## The player confirmed moving the building at `origin`; the kingdom scene lets them pick the spot.
signal move_requested(origin: Vector2i)
## The building was demolished, or its upgrade called off; `refund` is what came back.
signal demolished(building_name: String, refund: Dictionary)
## An upgrade was paid and started (the window closes); `text` says when it will be finished.
signal construction_started(text: String)
## "Giao nhiệm vụ" on an idle agent (Sở cảnh sát, GDD §8 M14e): the kingdom scene opens the map.
signal agent_mission_requested(agent: Agent)

const ACCENT := UiPalette.ACCENT
## Every tab page (and the confirm line under it) shares one fixed area: pages scroll instead of
## growing, so the window keeps its size and place whatever tab or confirm is showing and never
## gets taller than the screen (ScreenFit would shrink it). Preferred height on a tall screen.
const AREA_HEIGHT := 470
## Screen height the rest of the window needs (title, status, buttons; ModalWindow.fit_height).
const AREA_RESERVED := 250
## One width for every building window, wide enough for the cost and unit chips.
const WIDTH_SHARE_BUILDING := 0.52
const CANDIDATE_PORTRAIT_SCALE := 1

enum Action { NONE, UPGRADE, MOVE, DEMOLISH, CUSTOM, CANCEL_UPGRADE }

const AGENT_HIRE_TAB := "Chiêu mộ đặc vụ"
const FORGE_TAB := "Rèn"
const AGENTS_TAB := "Đặc vụ"

var _state: KingdomState
var _origin: Vector2i
var _resource_types: Array[ResourceTypeData] = ResourceTypeData.load_all()
var _is_castle := false
var _building: BuildingData
var _tabs: TabContainer
var _info: Label
var _upgrade: Label
## Icons for what a building gives and needs (RequirementView, M16c), under _info / _upgrade.
var _info_view: RequirementView
var _upgrade_view: RequirementView
var _upgrade_button: Button
var _confirm_box: VBoxContainer
var _confirm_text: Label
var _pending := Action.NONE
## What CUSTOM does once confirmed (recruit, refresh, appoint, dismiss).
var _custom: Callable
var _recruit_box: VBoxContainer
## The forge's "Rèn" tab (GDD §8 "Trang bị", M12e) and what it is set to make.
var _forge_box: VBoxContainer
var _forge_kind: StringName = &"general"
## The Sở cảnh sát's tabs (GDD §8 M14e).
var _agent_hire_box: VBoxContainer
var _agent_box: VBoxContainer
var _forge_slot: StringName = &"weapon"


## `start_tab` names the tab to show first ("" = the first one).
func open(state: KingdomState, origin: Vector2i, start_tab: String = "") -> void:
	_state = state
	_origin = origin
	var cell := state.board.get_cell(origin)
	_is_castle = cell.building_id == BoardData.CASTLE_ID
	_building = state.buildings.get(cell.building_id)
	var body := build_frame(_title(), ACCENT, WIDTH_SHARE_BUILDING)
	_confirm_box = VBoxContainer.new()
	_confirm_box.visible = false
	_confirm_text = _label("", 15)
	_confirm_text.add_theme_color_override("font_color", ACCENT)
	_confirm_box.add_child(_confirm_text)
	var confirm := _button("Xác nhận", _on_confirm_pressed)
	confirm.custom_minimum_size = Vector2(140, 44)
	var cancel := _button("Hủy", _cancel_action)
	cancel.custom_minimum_size = Vector2(140, 44)
	_confirm_box.add_child(_row([confirm, cancel]))
	if _turns_left() > 0:
		_open_construction(body, cell)
		return
	var area := VBoxContainer.new()
	area.custom_minimum_size = Vector2(0, fit_height(AREA_HEIGHT, AREA_RESERVED))
	area.add_theme_constant_override("separation", 8)
	body.add_child(area)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.add_child(_tabs)
	_info = _tab_label("Thông tin")
	_info_view = _view_under(_info)
	# Buildings that never level up get no Upgrade tab (M16c).
	if _is_castle or (_building != null and _building.is_upgradable()):
		_upgrade = _tab_label("Nâng cấp")
		_upgrade_view = _view_under(_upgrade)
	if cell.building_id == KingdomState.FORGE_ID:
		_forge_box = _tab_box(FORGE_TAB)
		_tabs.current_tab = _tabs.get_tab_count() - 1
		state.equipment.changed.connect(_refresh)
	if _is_castle:
		_recruit_box = _tab_box("Chiêu hiền")
		state.generals.changed.connect(_refresh)
		state.advisors.changed.connect(_refresh)
	if cell.building_id == KingdomState.POLICE_ID:
		_agent_hire_box = _tab_box(AGENT_HIRE_TAB)
		_agent_box = _tab_box(AGENTS_TAB)
		state.agents.changed.connect(_refresh)
	for i in _tabs.get_tab_count():
		if _tabs.get_tab_title(i) == start_tab:
			_tabs.current_tab = i
	area.add_child(_confirm_box)
	if _is_castle or (_building != null and _building.is_upgradable()):
		_upgrade_button = add_action("Nâng cấp", _ask.bind(Action.UPGRADE))
	if not _is_castle:
		add_action("Di chuyển", _ask.bind(Action.MOVE))
		add_action("Phá hủy", _ask.bind(Action.DEMOLISH), true)
	state.stockpile.changed.connect(_refresh)
	_refresh()


## Turns left on this building's (or the castle's) construction; 0 when it is working.
func _turns_left() -> int:
	return _state.castle_turns if _is_castle else _state.board.get_cell(_origin).building_turns


## Under construction: what is being built, the turns left and the one action that remains.
func _open_construction(body: VBoxContainer, cell: CellData) -> void:
	var upgrading := _is_castle or cell.building_upgrading
	var target := _state.castle_level + 1 if _is_castle else cell.building_level + 1
	var text := "Đang nâng cấp lên cấp %d." % target if upgrading else "Đang xây nền móng."
	text += "\nHoàn thành sau %d lượt (lượt %d)." % [_turns_left(), _state.turn + _turns_left()]
	text += "\nTrong lúc thi công công trình không hoạt động." if not _is_castle \
			else "\nThành vẫn giữ các giới hạn của cấp %d; Chiêu hiền mở lại khi nâng cấp xong." % _state.castle_level
	text += "\nĐội thợ: %d/%d đang làm." % [_state.builders_busy(), _state.builder_limit()]
	body.add_child(_label(text, 15))
	body.add_child(_confirm_box)
	if upgrading:
		add_action("Hủy nâng cấp", _ask.bind(Action.CANCEL_UPGRADE), true)
	else:
		add_action("Phá hủy", _ask.bind(Action.DEMOLISH), true)


func _title() -> String:
	if _is_castle:
		return "Thành chính cấp %d" % _state.castle_level
	return _building.display_name if _building != null else "Công trình"


## A tab page that scrolls inside the fixed area (long lists: three advisors with their stratagems).
func _tab_box(title: String, separation: int = 8) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = title
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 10)
	_tabs.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", separation)
	scroll.add_child(box)
	return box


## A scrolling tab page starting with a text label (Thông tin, Nâng cấp).
func _tab_label(title: String) -> Label:
	var label := _label("", 14)
	_tab_box(title, 6).add_child(label)
	return label


## A RequirementView under a tab's label (_tab_label).
func _view_under(label: Label) -> RequirementView:
	var view := RequirementView.new()
	label.get_parent().add_child(view)
	return view


func _refresh() -> void:
	var cell := _state.board.get_cell(_origin)
	var terrain: TerrainData = _state.terrains.get(cell.terrain_id)
	var lines: Array[String] = []
	_info_view.clear()
	if _is_castle:
		lines.append("Trung tâm của vương quốc. Không thể phá hủy hay di chuyển; mất hết đất xung quanh mà thua thêm một trận xâm lược thì thành thất thủ.")
		_info_view.header("Hiện có")
		_info_view.gain("Chỗ cho đơn vị lính: %d (gồm doanh trại và cấp thành)" % _state.get_squad_capacity())
		_info_view.gain("Tướng và mưu sĩ tuyển được: tới %d sao" % _state.castle_level)
		var commander := _state.generals.commander
		_info_view.gain("Tổng tướng: %s" % ("%s %s" % [commander.name, commander.star_text()]
				if commander != null else "chưa có"))
	elif _building != null:
		lines.append(_building.description)
		var place := "Ô (%d, %d), %s%s" % [_origin.x, _origin.y, terrain.display_name if terrain != null else "đất hoang",
				" ◆" if cell.is_key else ""]
		if _building.is_upgradable():
			place += " · Cấp %d/%d" % [cell.building_level, _building.max_level()]
		var most := BuildRules.limit(_building, _state.castle_level)
		if most > 0:
			place += " · Đang có %d/%d" % [_state.board.count_buildings(_building.building_id), most]
		lines.append(place)
		_fill_building_effects(_info_view, cell, cell.building_level, false)
	_info.text = "\n".join(lines)
	if not _is_castle:
		_refresh_building_upgrade(cell)
		if _forge_box != null:
			_refresh_forge()
		if _agent_box != null:
			_refresh_agents()
		return
	_refresh_generals()
	_refresh_castle_upgrade()


## What a building does at `level`: output per turn (with the share from the fields around it),
## replenishment, effects, units it opens and its upkeep (GDD §8). `next`: the upgrade preview.
func _fill_building_effects(view: RequirementView, cell: CellData, level: int, next: bool) -> void:
	var stopped := not _state.buildings_supplied and not next
	var produced: Dictionary[StringName, int]
	if next:
		produced = Economy.building_yield(_building, cell.is_key, level)
		Economy.add_into(produced, Economy.field_yield(_state.board, _building, _origin))
	else:
		produced = Economy.production(_state.board, _building, cell)
	var effects := _building.effect_lines(level)
	# New units only in the upgrade preview; the army tab lists what can be recruited now.
	# Units that still need another building are only counted.
	var unlocked: Array[UnitData] = []
	var waiting := 0
	if next:
		for unit in _units_unlocked(level):
			if _other_buildings_ready(unit):
				unlocked.append(unit)
			else:
				waiting += 1
	var has_effects := not produced.is_empty() or _building.replenish_per_level > 0.0 or not effects.is_empty() \
			or not unlocked.is_empty() or waiting > 0
	if has_effects:
		view.header("Cấp %d nhận được" % level if next else "Tác dụng")
	if not produced.is_empty():
		view.amounts("Mỗi lượt:", produced, true)
		if not next and _building.field_resource != &"":
			var fields := Economy.field_yield(_state.board, _building, _origin)
			view.note("Trong đó từ ô đất xung quanh: %s." % (UiFormat.amounts(fields, _resource_types, true)
					if not fields.is_empty() else "chưa có"))
	if _building.replenish_per_level > 0.0:
		var share := _percent(_building.replenish_per_level * level)
		view.gain("Tăng tốc hồi quân %s → %s" % [_percent(_building.replenish_per_level * (level - 1)), share]
				if next else "Tăng tốc hồi quân %s" % share)
	for effect in effects:
		view.gain(effect)
	view.units("Mở tuyển:", unlocked)
	if waiting > 0:
		view.note("+%d loại lính khác khi có thêm công trình quân sự." % waiting)
	if has_effects and stopped:
		view.requirement("Đang ngừng vì thiếu phí duy trì", false)
	var upkeep := _building.upkeep_at(level)
	if not upkeep.is_empty():
		view.header("Phí duy trì")
		view.amounts("Mỗi lượt:", upkeep)


## The castle's Upgrade tab: requirements (✓ / ✗), cost, turns and what the new level gives.
func _refresh_castle_upgrade() -> void:
	_upgrade_view.clear()
	var next := _state.next_castle_level()
	if next == null:
		_upgrade.text = "Thành chính đã đạt cấp cao nhất (%d)." % _state.castle_level
		_upgrade_button.disabled = true
		return
	_upgrade.text = "Lên cấp %d" % next.level
	var view := _upgrade_view
	view.header("Yêu cầu")
	if next.required_clans > 0 and KingdomState.castle_needs_clans:
		var united := _state.diplomacy.count_united()
		view.requirement("Thôn tính hoặc liên minh %d gia tộc (đang có %d)" % [next.required_clans, united],
				united >= next.required_clans)
	_builders_requirement(view)
	view.header("Chi phí")
	view.costs(_state.castle_upgrade_cost(), _state.stockpile)
	view.line(&"time", "%d lượt" % _state.castle_upgrade_turns())
	view.header("Cấp %d nhận được" % next.level)
	view.gain("+%d chỗ cho đơn vị lính" % next.squad_capacity)
	view.gain("+1 chỗ cho mỗi loại công trình, +1 đội thợ")
	view.gain("Công trình nâng được tới cấp %d" % next.level)
	view.gain("Tuyển tướng và mưu sĩ tới %d sao" % next.level)
	_upgrade_button.disabled = _state.check_castle_upgrade() != KingdomState.CastleResult.OK


## "✓ Đội thợ rảnh (1/3 đang làm)".
func _builders_requirement(view: RequirementView) -> void:
	view.requirement("Có đội thợ rảnh (%d/%d đang làm)" % [_state.builders_busy(), _state.builder_limit()],
			_state.has_free_builder())


## The Upgrade tab of a building: requirements (✓ / ✗), cost, turns and the next level (GDD §8).
## "+1.5%" (one decimal only when needed).
static func _percent(share: float) -> String:
	var text := String.num(share * 100, 1)
	return "+%s%%" % text.trim_suffix(".0")


func _refresh_building_upgrade(cell: CellData) -> void:
	if _upgrade == null:
		return
	_upgrade_view.clear()
	var result := _state.check_building_upgrade(_origin)
	var level := cell.building_level
	if result == KingdomState.UpgradeResult.MAX_LEVEL:
		_upgrade.text = "Đã đạt cấp cao nhất (%d)." % level
		_upgrade_button.disabled = true
		return
	_upgrade.text = "Lên cấp %d" % (level + 1)
	var view := _upgrade_view
	view.header("Yêu cầu")
	var castle_needed := level + 1 + _building.castle_level_gap
	view.requirement("Thành chính cấp %d (đang cấp %d)" % [castle_needed, _state.castle_level],
			_state.castle_level >= castle_needed)
	_builders_requirement(view)
	if result == KingdomState.UpgradeResult.FORGING:
		view.requirement("Xưởng đang rèn: chờ rèn xong", false)
	if result == KingdomState.UpgradeResult.REBELS:
		view.requirement("Quân nổi loạn đang chiếm ô này: thảo phạt trước", false)
	view.header("Chi phí")
	view.costs(_state.building_upgrade_cost(_origin), _state.stockpile)
	view.line(&"time", "%d lượt (ngừng hoạt động trong lúc nâng cấp)" % _state.building_upgrade_turns(_origin))
	_fill_building_effects(view, cell, level + 1, true)
	_upgrade_button.disabled = result != KingdomState.UpgradeResult.OK


## Whether the kingdom already has every other building `unit` needs (so this upgrade alone opens it).
func _other_buildings_ready(unit: UnitData) -> bool:
	for building_id in unit.required_buildings:
		if building_id != _building.building_id \
				and _state.board.highest_building_level(building_id) < unit.required_buildings[building_id]:
			return false
	return true


## The unit types this building opens at exactly `level` (GDD §8, M13); other buildings they also
## need are left to the army tab.
func _units_unlocked(level: int) -> Array[UnitData]:
	var list: Array[UnitData] = []
	for unit: UnitData in _state.units.values():
		if unit.required_buildings.get(_building.building_id, 0) == level:
			list.append(unit)
	return list


## First step of an action: say what it will do and wait for confirmation.
func _ask(action: Action) -> void:
	_pending = action
	match action:
		Action.UPGRADE:
			_tabs.current_tab = 1
			if _is_castle:
				_confirm_text.text = "Nâng thành chính lên cấp %d? Trả %s, xong sau %d lượt." % [_state.castle_level + 1,
						UiFormat.amounts(_state.castle_upgrade_cost(), _resource_types), _state.castle_upgrade_turns()]
			else:
				_confirm_text.text = "Nâng %s lên cấp %d? Trả %s, xong sau %d lượt (ngừng hoạt động tới khi xong)." % [
						_building.display_name, _state.board.get_building_level(_origin) + 1,
						UiFormat.amounts(_state.building_upgrade_cost(_origin), _resource_types),
						_state.building_upgrade_turns(_origin)]
		Action.CANCEL_UPGRADE:
			var cell := _state.board.get_cell(_origin)
			var cost := _state.next_castle_level().cost if _is_castle else _building.upgrade_cost(cell.building_level + 1)
			var back := UiFormat.amounts(_state.half_refund(cost), _resource_types)
			_confirm_text.text = "Hủy nâng cấp? Hoàn lại %s; công trình giữ cấp hiện tại." % (back if not back.is_empty() else "không gì")
		Action.MOVE:
			_confirm_text.text = "Di chuyển %s? Bảng sẽ đóng; chọn ô mới trên bản đồ (miễn phí, đúng địa hình, trong lãnh thổ). Esc để hủy." % _building.display_name
		Action.DEMOLISH:
			var refund := UiFormat.amounts(_state.demolish_refund(_building.building_id), _resource_types)
			_confirm_text.text = "Phá hủy %s? Hoàn lại %s. Không thể hoàn tác." % [
					_building.display_name + (" đang xây" if _turns_left() > 0 else ""), refund if not refund.is_empty() else "không gì"]
	_show_confirm(true)


func _cancel_action() -> void:
	_pending = Action.NONE
	_show_confirm(false)


## The confirm line takes its room from the tab page above it (same fixed area).
func _show_confirm(shown: bool) -> void:
	_confirm_box.visible = shown


func _on_confirm_pressed() -> void:
	var action := _pending
	_cancel_action()
	match action:
		Action.UPGRADE:
			if _is_castle and _state.upgrade_castle() == KingdomState.CastleResult.OK:
				Sfx.play(&"build")
				construction_started.emit("Bắt đầu nâng thành chính lên cấp %d, xong sau %d lượt." % [
						_state.castle_level + 1, _state.castle_turns])
				close()
			elif not _is_castle and _state.upgrade_building(_origin) == KingdomState.UpgradeResult.OK:
				Sfx.play(&"build")
				construction_started.emit("Bắt đầu nâng %s lên cấp %d, xong sau %d lượt." % [_building.display_name,
						_state.board.get_building_level(_origin) + 1, _turns_left()])
				close()
			else:
				_refresh()
		Action.CANCEL_UPGRADE:
			var refund := _state.cancel_castle_upgrade() if _is_castle else _state.cancel_upgrade(_origin)
			demolished.emit("Đã hủy nâng cấp %s" % ("thành chính" if _is_castle else _building.display_name), refund)
			close()
		Action.MOVE:
			move_requested.emit(_origin)
			close()
		Action.DEMOLISH:
			Sfx.play(&"demolish")
			demolished.emit("Đã phá hủy %s" % _building.display_name, _state.demolish(_origin))
			close()
		Action.CUSTOM:
			_custom.call()


## Like _ask, for the generals tabs: `text` says what will happen, `on_confirm` does it.
func _ask_custom(text: String, on_confirm: Callable) -> void:
	_pending = Action.CUSTOM
	_custom = on_confirm
	_confirm_text.text = text
	_show_confirm(true)


# --- Forge -------------------------------------------------------------------------------

## Who and which slot to forge for, the cost and odds at this forge level, the job in progress.
## Opens the Rèn tab set to make `kind`'s `slot` (from an officer's Trang bị tab, M14h).
func preset_forge(kind: StringName, slot: StringName) -> void:
	_forge_kind = kind
	_forge_slot = slot
	_refresh()


func _refresh_forge() -> void:
	for child in _forge_box.get_children():
		_forge_box.remove_child(child)
		child.queue_free()
	var equipment := _state.equipment
	var level := _state.forge_level()
	if not equipment.forge_job.is_empty():
		_show_forge_job(equipment.forge_job)
		return
	var kinds := _row([_label("Rèn cho:", 14, false)])
	for kind in Item.KINDS:
		kinds.add_child(_choice_button("Tướng" if kind == &"general" else "Mưu sĩ", _forge_kind == kind, func() -> void:
			_forge_kind = kind
			_refresh_forge()))
	_forge_box.add_child(kinds)
	var slots := _row([_label("Món:", 14, false)])
	for slot in Item.SLOTS:
		slots.add_child(_choice_button(_forge_slot_name(_forge_kind, slot), _forge_slot == slot, func() -> void:
			_forge_slot = slot
			_refresh_forge()))
	_forge_box.add_child(slots)
	var odds := Equipment.forge_odds(level)
	var total := 0
	for weight: int in odds:
		total += weight
	var parts: Array[String] = []
	for rarity in odds.size():
		parts.append("%s %d%%" % [Item.RARITY_NAMES[rarity], roundi(100.0 * odds[rarity] / total)])
	var view := RequirementView.new()
	_forge_box.add_child(view)
	var result := equipment.check_forge(_state.stockpile, level)
	view.header("Yêu cầu")
	view.requirement("Kho đồ còn chỗ (%d/%d món)" % [equipment.items.size(), Equipment.MAX_STORAGE],
			equipment.has_room())
	view.header("Chi phí")
	view.costs(Equipment.forge_cost(level), _state.stockpile)
	view.line(&"time", "%d lượt" % Equipment.FORGE_TURNS)
	view.header("Nhận được")
	view.gain("1 món ngẫu nhiên: %s" % ", ".join(parts))
	view.note("Nâng cấp xưởng để dễ ra đồ hiếm; Huyền thoại chỉ có từ chiến lợi phẩm và sự kiện.")
	var start := _button("Rèn", func() -> void:
		var started := _state.start_forge(_forge_kind, _forge_slot)
		if started == Equipment.Result.OK:
			set_status("Bắt đầu rèn, xong sau %d lượt." % Equipment.FORGE_TURNS)
			Sfx.play(&"forge")
		else:
			set_status(Equipment.describe(started), false))
	start.custom_minimum_size = Vector2(140, 40)
	start.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	start.disabled = result != Equipment.Result.OK
	_forge_box.add_child(start)
	if result != Equipment.Result.OK and result != Equipment.Result.CANNOT_AFFORD and result != Equipment.Result.FULL:
		var reason := _label(Equipment.describe(result), 13)
		reason.add_theme_color_override("font_color", WARNING_COLOR)
		_forge_box.add_child(reason)


## The job in progress: what is being made, for whom, when it is ready and the odds it was rolled with.
func _show_forge_job(job: Dictionary) -> void:
	var icon := ItemIcon.new()
	# A general's weapon type is rolled when it is finished: show a sword meanwhile.
	icon.setup_type(&"kiem" if job.kind == &"general" and job.slot == &"weapon" else StringName("%s_%s" % [job.kind, job.slot]), 3)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_label("Đang rèn: %s cho %s" % [_forge_slot_name(job.kind, job.slot),
			"tướng" if job.kind == &"general" else "mưu sĩ"], 16))
	column.add_child(_label("Xong sau %d lượt (lượt %d). Độ hiếm biết khi rèn xong; món mới vào kho đồ." % [job.turns,
			_state.turn + job.turns], 14))
	_forge_box.add_child(_row([icon, column]))
	_forge_box.add_child(_label("Mỗi lúc chỉ rèn được 1 món; chọn món tiếp theo khi món này xong.", 13))


## "Vũ khí (đao, thương…)" for generals, "Quạt / Bút" … for advisors.
func _forge_slot_name(kind: StringName, slot: StringName) -> String:
	if kind == &"advisor":
		return {&"weapon": "Quạt / Bút", &"armor": "Áo bào", &"accessory": "Ấn / Ngọc bội"}[slot]
	return Item.SLOT_NAMES[slot]


func _choice_button(text: String, chosen: bool, on_pressed: Callable) -> Button:
	var button := _button(text, on_pressed)
	button.toggle_mode = true
	button.button_pressed = chosen
	button.custom_minimum_size = Vector2(110, 36)
	return button


# --- Agents (Sở cảnh sát, GDD §8 M14e) ---------------------------------------------------

func _refresh_agents() -> void:
	var agents := _state.agents
	var slots := _state.agent_slots()
	for box: VBoxContainer in [_agent_hire_box, _agent_box]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	_agent_hire_box.add_child(_muted(("Đặc vụ trả một lần khi tuyển, không tốn phí nuôi. Đang có %d/%d đặc vụ (mỗi cấp sở giữ thêm 1). "
			+ "Ứng viên tới %d sao (cấp thành), danh sách mới sau %d lượt.") % [agents.agents.size(), slots, _state.castle_level,
			maxi(0, Agents.CANDIDATE_TURNS - (_state.turn - agents.candidates_turn))]))
	for i in agents.candidates.size():
		var candidate := agents.candidates[i]
		var cost := Agents.cost_of(candidate.stars)
		var result := agents.check_recruit(_state.stockpile, i, slots)
		var button := _button("Tuyển", _ask_custom.bind("Tuyển đặc vụ %s %s? Trả %s (một lần)." % [candidate.name,
				candidate.star_text(), UiFormat.amounts(cost, _resource_types)], _recruit_agent.bind(i)))
		button.disabled = result != Agents.Result.OK
		button.custom_minimum_size = Vector2(110, 44)
		var reason := "" if result == Agents.Result.OK or result == Agents.Result.CANNOT_AFFORD else Agents.describe(result)
		_agent_hire_box.add_child(_candidate_row(candidate, _agent_text(candidate), reason, [button], cost))
	var refresh := _button("Làm mới ngay (%s)" % UiFormat.amounts(Agents.REFRESH_COST, _resource_types),
			_ask_custom.bind("Đổi danh sách đặc vụ ngay? Trả %s." % UiFormat.amounts(Agents.REFRESH_COST, _resource_types),
			func() -> void: agents.buy_refresh(_state.stockpile, _state.castle_level, _state.turn)))
	refresh.disabled = not _state.stockpile.can_afford(Agents.REFRESH_COST)
	_agent_hire_box.add_child(refresh)

	_agent_box.add_child(_muted(("Mỗi nhiệm vụ %d lượt, sang bất kỳ gia tộc nào, mỗi gia tộc một đặc vụ. Lượt đầu có %s%% bị lộ, "
			+ "mỗi lượt sau +%d%%: bị lộ thì có thể bị giết (40%% − 5%% × sao), không thì trốn về; quan hệ với gia tộc đó −%d.") % [
			Agents.MISSION_TURNS, String.num(Agents.detect_chance(_state.police_level()) * 100, 1),
			roundi(Agents.DETECT_PER_TURN * 100), -Agents.CAUGHT_RELATION]))
	if agents.agents.is_empty():
		_agent_box.add_child(_muted("Chưa có đặc vụ nào: tuyển ở tab %s." % AGENT_HIRE_TAB))
	for agent in agents.agents:
		var status := "Đang rảnh."
		var buttons: Array = []
		if agent.is_busy():
			status = "%s ở %s, còn %d lượt · lượt này %s%% bị lộ." % [Agent.MISSION_NAMES[agent.mission],
					_state.diplomacy.clans[agent.target].data.display_name, agent.turns_left,
					String.num(Agents.current_detect_chance(agent, _state.police_level()) * 100, 1)]
		else:
			var send := _button("Giao nhiệm vụ", func() -> void:
				agent_mission_requested.emit(agent)
				close())
			send.custom_minimum_size = Vector2(150, 44)
			buttons.append(send)
		var dismiss := _button("Sa thải", _ask_custom.bind("Sa thải đặc vụ %s? Không hoàn lại tiền tuyển." % agent.name,
				func() -> void: agents.dismiss(agent)))
		dismiss.custom_minimum_size = Vector2(110, 44)
		buttons.append(dismiss)
		_agent_box.add_child(_candidate_row(agent, _agent_text(agent), status, buttons))


func _agent_text(agent: Agent) -> String:
	return "Đặc vụ %s %s · %s\nTăng quan hệ +%d/lượt · Phá hoại −%s%% hồi quân" % [agent.name, agent.star_text(),
			agent.level_text(), agent.relation_gain(), String.num(agent.sabotage_share() * 100, 1)]


func _recruit_agent(index: int) -> void:
	var name := _state.agents.candidates[index].name
	if _state.recruit_agent(index) == Agents.Result.OK:
		set_status("Đặc vụ %s đã nhận việc!" % name)
		Sfx.play(&"level_up")

# --- Generals (castle only) ---------------------------------------------------------------

func _refresh_generals() -> void:
	var generals := _state.generals
	var advisors := _state.advisors
	for child in _recruit_box.get_children():
		_recruit_box.remove_child(child)
		child.queue_free()
	_recruit_box.add_child(_muted("Ứng viên tướng và mưu sĩ tới %d sao (cấp thành). Đang có %d/%d tướng, %d/%d mưu sĩ. Danh sách mới sau %d lượt." % [
			_state.castle_level, generals.generals.size(), Generals.MAX_GENERALS, advisors.advisors.size(),
			Advisors.MAX_ADVISORS, maxi(0, Generals.CANDIDATE_TURNS - (_state.turn - generals.candidates_turn))]))
	for i in generals.candidates.size():
		var candidate := generals.candidates[i]
		var is_advisor := candidate is Advisor
		var role := "mưu sĩ" if is_advisor else "tướng"
		var cost := generals.cost_of(candidate)
		var result := generals.check_recruit(_state.stockpile, i)
		var button := _button("Tuyển", _ask_custom.bind("Tuyển %s %s %s? Trả %s; phí nuôi %s mỗi lượt." % [role, candidate.name,
				candidate.star_text(), UiFormat.amounts(cost, _resource_types),
				UiFormat.amounts(generals.ranks[candidate.stars].upkeep, _resource_types)], _recruit.bind(i)))
		button.disabled = result != Generals.RecruitResult.OK
		button.custom_minimum_size = Vector2(110, 44)
		var reason := ""
		if result == Generals.RecruitResult.NO_ROOM:
			reason = "Đã đủ %d mưu sĩ." % Advisors.MAX_ADVISORS if is_advisor else "Đã đủ %d tướng." % Generals.MAX_GENERALS
		var upkeep := generals.ranks[candidate.stars].upkeep
		if is_advisor:
			_recruit_box.add_child(_advisor_row(candidate as Advisor, reason, [button], cost, upkeep))
		else:
			_recruit_box.add_child(_general_row(candidate as General, reason, [button], cost, upkeep))
	var refresh := _button("Làm mới ngay (%s)" % UiFormat.amounts(Generals.REFRESH_COST, _resource_types),
			_ask_custom.bind("Đổi danh sách ứng viên ngay? Trả %s." % UiFormat.amounts(Generals.REFRESH_COST, _resource_types),
			_buy_refresh))
	refresh.disabled = not _state.stockpile.can_afford(Generals.REFRESH_COST)
	_recruit_box.add_child(refresh)


## Name, stars, the three stats and the stratagems, plus a line and buttons.
func _advisor_row(advisor: Advisor, extra: String, buttons: Array, cost: Dictionary[StringName, int] = {},
		upkeep: Dictionary[StringName, int] = {}) -> Control:
	var names: Array[String] = []
	for id in advisor.stratagems:
		var stratagem: StratagemData = _state.advisors.stratagems.get(id)
		names.append(stratagem.display_name if stratagem != null else String(id))
	var text := "Mưu sĩ %s %s · Nội chính %d · Ngoại giao %d · Mưu lược %d\nMưu kế: %s" % [advisor.name,
			advisor.star_text(), advisor.admin, advisor.diplomacy, advisor.strategy, ", ".join(names)]
	return _candidate_row(advisor, text, extra, buttons, cost, upkeep)


## Name, stars, stats and trait (with whether its condition holds), plus a line and buttons.
func _general_row(general: General, extra: String, buttons: Array, cost: Dictionary[StringName, int] = {},
		upkeep: Dictionary[StringName, int] = {}) -> Control:
	var text := "%s %s · Võ lực %d · Thống suất %d" % [general.name, general.star_text(), general.might, general.command]
	var trait_data: GeneralTraitData = _state.generals.traits.get(general.trait_id)
	if trait_data != null:
		var active := trait_data.is_active(_state.board, trait_data.defending_only)
		text += "\nĐặc tính %s: %s (%s%s)" % [trait_data.display_name, trait_data.description,
				trait_data.describe_condition(_state.terrains, _state.buildings), " — đang có tác dụng" if active else " — chưa đạt"]
	return _candidate_row(general, text, extra, buttons, cost, upkeep)


## Portrait, then the text and a muted line, then the buttons.
## `cost` / `upkeep` show as resource chips (green or red by the stockpile) under the text.
func _candidate_row(officer: Officer, text: String, extra: String, buttons: Array,
		cost: Dictionary[StringName, int] = {}, upkeep: Dictionary[StringName, int] = {}) -> Control:
	var portrait := PortraitView.new()
	portrait.setup(officer, CANDIDATE_PORTRAIT_SCALE)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := _label(text, 14)
	name_label.add_theme_color_override("font_color", officer.name_color())
	column.add_child(name_label)
	if not cost.is_empty():
		var view := RequirementView.new()
		view.costs(cost, _state.stockpile, "Giá:")
		view.amounts("Nuôi mỗi lượt:", upkeep)
		column.add_child(view)
	if extra != "":
		column.add_child(_muted(extra))
	var row := _row([portrait, column])
	for button: Button in buttons:
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(button)
	return row


func _muted(text: String) -> Label:
	var label := _label(text, 13)
	label.add_theme_color_override("font_color", MUTED_COLOR)
	return label


func _recruit(index: int) -> void:
	var name := _state.generals.candidates[index].name
	if _state.generals.recruit(_state.stockpile, index) == Generals.RecruitResult.OK:
		set_status("%s đã gia nhập!" % name)
		Sfx.play(&"level_up")


func _buy_refresh() -> void:
	_state.generals.buy_refresh(_state.stockpile, _state.castle_level, _state.turn)
