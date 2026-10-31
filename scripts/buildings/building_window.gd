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
## Height of the scrolling list in the castle's Chiêu hiền tab, on a tall enough screen.
const TAB_LIST_HEIGHT := 440
## Screen height the rest of the window needs (ModalWindow.fit_height).
const TAB_LIST_RESERVED := 330
## Room the confirm line and its two buttons take: the tab lists give it up while they show, so
## the window does not grow past the screen and get shrunk by ScreenFit (M14b fix).
const CONFIRM_HEIGHT := 100
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
var _upgrade_button: Button
var _confirm_box: VBoxContainer
var _confirm_text: Label
var _pending := Action.NONE
## What CUSTOM does once confirmed (recruit, refresh, appoint, dismiss).
var _custom: Callable
var _recruit_box: VBoxContainer
## The tab pages' scrolling lists (_tab_box), sized by _fit_tab_lists.
var _tab_scrolls: Array[ScrollContainer] = []
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
	var body := build_frame(_title(), ACCENT, 0.42)
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
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(0, 180)
	body.add_child(_tabs)
	_info = _tab_label("Thông tin")
	_upgrade = _tab_label("Nâng cấp")
	if cell.building_id == KingdomState.FORGE_ID:
		_forge_box = _tab_box(FORGE_TAB)
		_tabs.current_tab = 2
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
	body.add_child(_confirm_box)
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


func _tab_box(title: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = title
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 10)
	_tabs.add_child(margin)
	# Long lists (three advisors with their stratagems) scroll instead of growing off screen.
	var scroll := ScrollContainer.new()
	_tab_scrolls.append(scroll)
	_fit_tab_lists()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return box


func _tab_label(title: String) -> Label:
	var margin := MarginContainer.new()
	margin.name = title
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 10)
	_tabs.add_child(margin)
	var label := _label("", 14)
	margin.add_child(label)
	return label


func _refresh() -> void:
	var cell := _state.board.get_cell(_origin)
	var terrain: TerrainData = _state.terrains.get(cell.terrain_id)
	var lines: Array[String] = []
	if _is_castle:
		lines.append("Trung tâm của vương quốc. Không thể phá hủy hay di chuyển; mất hết đất xung quanh mà thua thêm một trận xâm lược thì thành thất thủ.")
		lines.append("Chỗ cho đơn vị lính: %d (gồm doanh trại và cấp thành)." % _state.get_squad_capacity())
		lines.append("Tướng và mưu sĩ tuyển được: tới %d sao (tab Chiêu hiền)." % _state.castle_level)
		var commander := _state.generals.commander
		lines.append("Tổng tướng: %s (quản lý ở tab Tướng sĩ)." % ("%s %s" % [commander.name, commander.star_text()]
				if commander != null else "chưa có"))
	elif _building != null:
		lines.append(_building.description)
		lines.append("Vị trí: ô (%d, %d), %s%s." % [_origin.x, _origin.y, terrain.display_name if terrain != null else "đất hoang",
				" ◆" if cell.is_key else ""])
		if _building.is_upgradable():
			lines.append("Cấp %d/%d." % [cell.building_level, _building.max_level()])
		var unlocked := _units_unlocked(1, cell.building_level)
		if not unlocked.is_empty():
			lines.append("Mở tuyển: %s." % ", ".join(unlocked))
		var produced := Economy.production(_state.board, _building, cell)
		if not produced.is_empty():
			lines.append("Mỗi lượt: %s%s." % [UiFormat.amounts(produced, _resource_types, true),
					"" if _state.buildings_supplied else " (đang ngừng vì thiếu phí duy trì)"])
		if _building.field_resource != &"":
			var fields := Economy.field_yield(_state.board, _building, _origin)
			lines.append("Trong đó từ ô đất xung quanh: %s." % (UiFormat.amounts(fields, _resource_types, true)
					if not fields.is_empty() else "chưa có"))
		if _building.replenish_per_level > 0.0:
			lines.append("Tăng tốc hồi quân: +%d%% (cấp %d)." % [roundi(_building.replenish_per_level * cell.building_level * 100),
					cell.building_level])
		var effects := _building.describe_effects(cell.building_level)
		if not effects.is_empty():
			lines.append("Tác dụng hiện tại: %s%s." % [effects,
					"" if _state.buildings_supplied else " (đang ngừng vì thiếu phí duy trì)"])
		var upkeep := _building.upkeep_at(cell.building_level)
		if not upkeep.is_empty():
			lines.append("Phí duy trì: %s mỗi lượt." % UiFormat.amounts(upkeep, _resource_types))
		var most := BuildRules.limit(_building, _state.castle_level)
		if most > 0:
			lines.append("Đang có %d/%d%s." % [_state.board.count_buildings(_building.building_id), most,
					"" if _building.fixed_count else " (thêm 1 chỗ mỗi cấp thành%s)" % (
						", tối đa %d" % _building.max_limit if _building.max_limit > 0 else "")])
	_info.text = "\n".join(lines)
	if not _is_castle:
		_refresh_building_upgrade(cell)
		if _forge_box != null:
			_refresh_forge()
		if _agent_box != null:
			_refresh_agents()
		return
	_refresh_generals()
	var next := _state.next_castle_level()
	if next == null:
		_upgrade.text = "Thành chính đã đạt cấp cao nhất (%d)." % _state.castle_level
		_upgrade_button.disabled = true
		return
	var result := _state.check_castle_upgrade()
	var text := "Lên cấp %d: %s. Mất %d lượt.\nCấp mới: thêm %d chỗ cho đơn vị lính, thêm 1 chỗ cho mỗi loại công trình, thêm 1 đội thợ, công trình nâng được tới cấp %d, tuyển được tướng và mưu sĩ tới %d sao." % [
			next.level, UiFormat.amounts(_state.castle_upgrade_cost(), _resource_types), _state.castle_upgrade_turns(),
			next.squad_capacity, next.level, next.level]
	if next.required_clans > 0:
		text += "
Cần thôn tính hoặc liên minh %d gia tộc (đang có %d)." % [next.required_clans,
				_state.diplomacy.count_united()]
	if result == KingdomState.CastleResult.NEEDS_CLANS:
		text += "
Chưa đủ chiến công: hãy thôn tính hoặc liên minh thêm gia tộc."
	elif result == KingdomState.CastleResult.CANNOT_AFFORD:
		text += "\nChưa đủ tài nguyên."
	elif result == KingdomState.CastleResult.NO_BUILDERS:
		text += "\nKhông còn đội thợ rảnh: chờ một công trình xây xong."
	_upgrade.text = text
	_upgrade_button.disabled = result != KingdomState.CastleResult.OK


## The Upgrade tab of a production building: next level's cost, yield and upkeep (GDD §8, economy v2).
func _refresh_building_upgrade(cell: CellData) -> void:
	if _building == null or not _building.is_upgradable():
		_upgrade.text = "Công trình này chưa có nâng cấp."
		return
	var result := _state.check_building_upgrade(_origin)
	var level := cell.building_level
	if result == KingdomState.UpgradeResult.MAX_LEVEL:
		_upgrade.text = "Đã đạt cấp cao nhất (%d)." % level
		_upgrade_button.disabled = true
		return
	var text := "Lên cấp %d: %s. Mất %d lượt, công trình ngừng hoạt động trong lúc nâng cấp.\n" % [level + 1,
			UiFormat.amounts(_state.building_upgrade_cost(_origin), _resource_types), _state.building_upgrade_turns(_origin)]
	if not _building.level_yields.is_empty():
		var next_yield := Economy.building_yield(_building, cell.is_key, level + 1)
		Economy.add_into(next_yield, Economy.field_yield(_state.board, _building, _origin))
		text += "Mỗi lượt: %s. " % UiFormat.amounts(next_yield, _resource_types, true)
	if _building.replenish_per_level > 0.0:
		text += "Tăng tốc hồi quân: +%d%%. " % roundi(_building.replenish_per_level * (level + 1) * 100)
	var next_effects := _building.describe_effects(level + 1)
	if not next_effects.is_empty():
		text += "Tác dụng: %s. " % next_effects
	text += "Phí duy trì: %s mỗi lượt." % UiFormat.amounts(_building.upkeep_at(level + 1), _resource_types)
	var unlocked := _units_unlocked(level + 1, level + 1)
	if not unlocked.is_empty():
		text += "\nMở tuyển: %s." % ", ".join(unlocked)
	match result:
		KingdomState.UpgradeResult.CASTLE_TOO_LOW:
			text += "\nCần thành chính cấp %d (cấp công trình không vượt cấp thành%s)." % [
					level + 1 + _building.castle_level_gap,
					", %s thấp hơn thành %d cấp" % [_building.display_name, _building.castle_level_gap] \
							if _building.castle_level_gap > 0 else ""]
		KingdomState.UpgradeResult.CANNOT_AFFORD:
			text += "\nChưa đủ tài nguyên."
		KingdomState.UpgradeResult.NO_BUILDERS:
			text += "\nKhông còn đội thợ rảnh: chờ một công trình xây xong."
		KingdomState.UpgradeResult.FORGING:
			text += "\nXưởng đang rèn: chờ rèn xong rồi mới nâng cấp."
		KingdomState.UpgradeResult.REBELS:
			text += "\nQuân nổi loạn đang chiếm ô này: thảo phạt trước đã."
	_upgrade.text = text
	_upgrade_button.disabled = result != KingdomState.UpgradeResult.OK


## Names of the unit types that need this building at a level from `from_level` to `to_level`
## (GDD §8, M13); other buildings they need are named in brackets.
func _units_unlocked(from_level: int, to_level: int) -> Array[String]:
	var names: Array[String] = []
	for unit: UnitData in _state.units.values():
		var needed: int = unit.required_buildings.get(_building.building_id, 0)
		if needed < from_level or needed > to_level:
			continue
		var others: Dictionary[StringName, int] = unit.required_buildings.duplicate()
		others.erase(_building.building_id)
		names.append(unit.display_name if others.is_empty() else "%s (cần thêm %s)" % [unit.display_name,
				RecruitmentRules.describe_buildings(others, _state.buildings)])
	return names


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


func _show_confirm(shown: bool) -> void:
	_confirm_box.visible = shown
	_fit_tab_lists()


## The tab lists' height: the screen's share, less the confirm box while it shows.
func _fit_tab_lists() -> void:
	var confirm := CONFIRM_HEIGHT if _confirm_box.visible else 0
	for scroll in _tab_scrolls:
		scroll.custom_minimum_size = Vector2(0, fit_height(TAB_LIST_HEIGHT - confirm, TAB_LIST_RESERVED + confirm))


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
	_forge_box.add_child(_label("Giá: %s. Xong sau %d lượt, ra 1 món ngẫu nhiên độ hiếm:\n%s.\nNâng cấp xưởng để dễ ra đồ hiếm; Huyền thoại chỉ có từ chiến lợi phẩm và sự kiện." % [
			UiFormat.amounts(Equipment.forge_cost(level), _resource_types), Equipment.FORGE_TURNS, ", ".join(parts)], 14))
	_forge_box.add_child(_label("Kho đồ: %d/%d món." % [equipment.items.size(), Equipment.MAX_STORAGE], 13))
	var result := equipment.check_forge(_state.stockpile, level)
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
	if result != Equipment.Result.OK:
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
		var reason := "" if result == Agents.Result.OK else " " + Agents.describe(result)
		_agent_hire_box.add_child(_candidate_row(candidate, _agent_text(candidate),
				"Giá: %s.%s" % [UiFormat.amounts(cost, _resource_types), reason], [button]))
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
			reason = " Đã đủ %d mưu sĩ." % Advisors.MAX_ADVISORS if is_advisor else " Đã đủ %d tướng." % Generals.MAX_GENERALS
		elif result != Generals.RecruitResult.OK:
			reason = " Chưa đủ tài nguyên."
		var extra := "Giá: %s.%s" % [UiFormat.amounts(cost, _resource_types), reason]
		if is_advisor:
			_recruit_box.add_child(_advisor_row(candidate as Advisor, extra, [button]))
		else:
			_recruit_box.add_child(_general_row(candidate as General, extra, [button]))
	var refresh := _button("Làm mới ngay (%s)" % UiFormat.amounts(Generals.REFRESH_COST, _resource_types),
			_ask_custom.bind("Đổi danh sách ứng viên ngay? Trả %s." % UiFormat.amounts(Generals.REFRESH_COST, _resource_types),
			_buy_refresh))
	refresh.disabled = not _state.stockpile.can_afford(Generals.REFRESH_COST)
	_recruit_box.add_child(refresh)


## Name, stars, the three stats and the stratagems, plus a line and buttons.
func _advisor_row(advisor: Advisor, extra: String, buttons: Array) -> Control:
	var names: Array[String] = []
	for id in advisor.stratagems:
		var stratagem: StratagemData = _state.advisors.stratagems.get(id)
		names.append(stratagem.display_name if stratagem != null else String(id))
	var text := "Mưu sĩ %s %s · Nội chính %d · Ngoại giao %d · Mưu lược %d\nMưu kế: %s" % [advisor.name,
			advisor.star_text(), advisor.admin, advisor.diplomacy, advisor.strategy, ", ".join(names)]
	return _candidate_row(advisor, text, extra, buttons)


## Name, stars, stats and trait (with whether its condition holds), plus a line and buttons.
func _general_row(general: General, extra: String, buttons: Array) -> Control:
	var text := "%s %s · Võ lực %d · Thống suất %d" % [general.name, general.star_text(), general.might, general.command]
	var trait_data: GeneralTraitData = _state.generals.traits.get(general.trait_id)
	if trait_data != null:
		var active := trait_data.is_active(_state.board, trait_data.defending_only)
		text += "\nĐặc tính %s: %s (%s%s)" % [trait_data.display_name, trait_data.description,
				trait_data.describe_condition(_state.terrains, _state.buildings), " — đang có tác dụng" if active else " — chưa đạt"]
	return _candidate_row(general, text, extra, buttons)


## Portrait, then the text and a muted line, then the buttons.
func _candidate_row(officer: Officer, text: String, extra: String, buttons: Array) -> Control:
	var portrait := PortraitView.new()
	portrait.setup(officer, CANDIDATE_PORTRAIT_SCALE)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := _label(text, 14)
	name_label.add_theme_color_override("font_color", officer.name_color())
	column.add_child(name_label)
	column.add_child(_muted(extra))
	var row := _row([portrait, column])
	for button: Button in buttons:
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
