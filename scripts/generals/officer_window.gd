class_name OfficerWindow
extends ModalWindow
## One general's or advisor's details (GDD §13, M12c): their portrait, a "Chỉ số" tab (stats with
## bars and level points — item bonuses in brackets —, level and XP, trait or stratagems, post and
## what it gives, upkeep) and a "Trang bị" tab (M12e: the three slots, the chosen slot's item, the
## storage items that fit it, wear / take off / dismantle), with Làm tổng tướng / Sa thải below.
## The title is colored by stars; ← / → (keys or the buttons under the portrait) switch to the
## previous / next general or advisor in the Tướng sĩ tab's order (M13b, buttons M14g).

const STAT_BAR_WIDTH := 160
## The tab pages keep this height whatever they show (their content scrolls).
const TABS_HEIGHT := 480
## Screen height the rest of the window needs (ModalWindow.fit_height).
const TABS_RESERVED := 260

## "Đến xưởng rèn" in the Trang bị tab: the kingdom scene opens the forge's Rèn tab for this
## officer's kind and the slot shown (M14h).
signal forge_requested(kind: StringName, slot: StringName)

var _state: KingdomState
var _officer: Officer
var _resource_types: Array[ResourceTypeData] = ResourceTypeData.load_all()
var _tabs: TabContainer
var _stats: VBoxContainer
var _role: Label
var _commander_button: Button
var _dismiss_button: Button
var _equip_box: VBoxContainer
## The slot shown in the Trang bị tab.
var _slot: StringName = &"weapon"
## Item waiting for a second press on "Phân rã".
var _dismantling: Item
## "Đột phá" was pressed once and waits for the second press.
var _break_armed := false


func open(state: KingdomState, officer: Officer) -> void:
	_state = state
	_officer = officer
	var body := build_frame("%s %s" % [officer.name, officer.star_text()], Officer.star_color(officer.stars), 0.6)
	var row := _row([])
	row.add_theme_constant_override("separation", 16)
	body.add_child(row)
	var left := VBoxContainer.new()
	row.add_child(left)
	var portrait := PortraitView.new()
	portrait.setup(officer, 2)
	left.add_child(portrait)
	_role = _label("", 14)
	_role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_role.custom_minimum_size = Vector2(PortraitView.SIZE * 2, 0)
	left.add_child(_role)
	var officers := _all_officers()
	if officers.size() > 1:
		var previous := _button("←", _switch.bind(-1))
		var next := _button("→", _switch.bind(1))
		for button in [previous, next]:
			button.custom_minimum_size = Vector2(56, 40)
			button.tooltip_text = "Xem người khác (phím ← →)"
		var place := _label("%d/%d" % [officers.find(officer) + 1, officers.size()], 14, false)
		place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		place.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		place.add_theme_color_override("font_color", MUTED_COLOR)
		var switcher := _row([previous, place, next])
		switcher.custom_minimum_size = Vector2(PortraitView.SIZE * 2, 0)
		left.add_child(switcher)
	var tabs := TabContainer.new()
	_tabs = tabs
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(0, fit_height(TABS_HEIGHT, TABS_RESERVED))
	row.add_child(tabs)
	_stats = _tab(tabs, "Chỉ số")
	_equip_box = _tab(tabs, "Trang bị")
	if officer is General:
		_commander_button = add_action("Làm tổng tướng", _make_commander)
	_dismiss_button = add_action("Sa thải", _dismiss, true)
	state.generals.changed.connect(_refresh)
	state.advisors.changed.connect(_refresh)
	state.equipment.changed.connect(_refresh)
	# Cost chips turn green or red with the stockpile (RequirementView, M16c).
	state.stockpile.changed.connect(_refresh)
	_refresh()


## Generals, then advisors: the order of the Tướng sĩ tab.
func _all_officers() -> Array[Officer]:
	var result: Array[Officer] = []
	result.append_array(_state.generals.generals)
	result.append_array(_state.advisors.advisors)
	return result


## Replaces this window with the officer `step` places away (wrapping around), on the same tab.
func _switch(step: int) -> void:
	var officers := _all_officers()
	var index := officers.find(_officer)
	if officers.size() < 2 or index == -1:
		return
	var window := OfficerWindow.new()
	get_parent().add_child(window)
	window.open(_state, officers[posmod(index + step, officers.size())])
	window._tabs.current_tab = _tabs.current_tab
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and event.keycode in [KEY_LEFT, KEY_RIGHT]:
		_switch(-1 if event.keycode == KEY_LEFT else 1)
		get_viewport().set_input_as_handled()
		return
	super(event)


func _tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = title
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 10)
	tabs.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	return box


func _refresh() -> void:
	if not _is_still_here():
		close()
		return
	for child in _stats.get_children():
		_stats.remove_child(child)
		child.queue_free()
	if _officer is General:
		_fill_general(_officer as General)
	else:
		_fill_advisor(_officer as Advisor)
	_stats.add_child(_muted(_officer.level_text()))
	_add_limit_break()
	if _officer.points > 0:
		var points := _label("Còn %d điểm cộng: bấm +1 cạnh một chỉ số." % _officer.points, 13)
		points.add_theme_color_override("font_color", UiPalette.ACCENT)
		_stats.add_child(points)
	var upkeep := RequirementView.new()
	upkeep.amounts("Phí nuôi mỗi lượt:", _state.generals.ranks[_officer.stars].upkeep)
	_stats.add_child(upkeep)
	_fill_equipment()


## "Đang thảo phạt" or the wound under the role ("" when ready).
func _status_text(officer: Officer) -> String:
	if officer.away:
		return "\nĐang đi thảo phạt"
	return "" if officer.wounded_turns <= 0 else "\nBị thương, còn %d lượt" % officer.wounded_turns


func _fill_general(general: General) -> void:
	var generals := _state.generals
	var role := "Tổng tướng" if general == generals.commander else "Dự bị"
	_role.text = role + _status_text(general)
	_commander_button.disabled = general == generals.commander or general.away
	_dismiss_button.disabled = general.away
	_stat_row("Võ lực", general.might, general.stat_cap(Generals.STAT_MAX), generals.can_spend_point(general, &"might"),
			generals.spend_point.bind(general, &"might"), general.item_bonus(&"might"))
	_stat_row("Thống suất", general.command, general.stat_cap(Generals.STAT_MAX), generals.can_spend_point(general, &"command"),
			generals.spend_point.bind(general, &"command"), general.item_bonus(&"command"))
	var armor := general.item_bonus(&"guard_armor")
	if armor > 0:
		_stats.add_child(_muted("Giáp cận vệ +%d: phòng thủ cận vệ +%d%%, khả năng tử trận %d%%." % [armor,
				roundi(armor * Generals.ARMOR_DEFENSE * 100), roundi(Generals.death_chance(general, _state.building_effect(&"commander_survival")) * 100)]))
	var trait_data: GeneralTraitData = generals.traits.get(general.trait_id)
	if trait_data != null:
		var active := trait_data.is_active(_state.board, trait_data.defending_only)
		_stats.add_child(_label("Đặc tính %s: %s (%s%s)" % [trait_data.display_name, trait_data.description,
				trait_data.describe_condition(_state.terrains, _state.buildings),
				" — đang có tác dụng" if active else " — chưa đạt"], 13))


func _fill_advisor(advisor: Advisor) -> void:
	var advisors := _state.advisors
	var post := Advisors.POST_NAMES[advisor.post] if advisor.post != Advisor.NO_POST else "Chưa giữ chức"
	_role.text = post + _status_text(advisor)
	_dismiss_button.disabled = advisor.away
	for stat in Advisors.STAT_IDS:
		_stat_row(Advisors.STAT_NAMES[stat], advisor.get_stat(stat), advisor.stat_cap(Advisors.STAT_MAX),
				advisors.can_spend_point(advisor, stat), advisors.spend_point.bind(advisor, stat), advisor.item_bonus(stat))
	if advisor.post != Advisor.NO_POST:
		_stats.add_child(_label(Advisors.describe_post(advisor.post, advisor.stat_for(advisor.post)), 13))
	var posts := _row([_label("Giao chức:", 13, false)])
	for post_id in Advisors.POSTS:
		var button := _button(Advisors.POST_NAMES[post_id], advisors.assign.bind(advisor, post_id))
		button.disabled = advisor.post == post_id
		posts.add_child(button)
	_stats.add_child(posts)
	_stats.add_child(_label("Mưu kế (dùng khi giữ chức Quân sự):", 13))
	for id in advisor.stratagems:
		var stratagem: StratagemData = advisors.stratagems.get(id)
		if stratagem != null:
			_stats.add_child(_muted("%s — %s" % [stratagem.display_name, stratagem.describe(advisor.stat_for(&"military"))]))


## "Name  [bar]  7/10 (+2)  [+1]" — the bracket is what the worn items add.
func _stat_row(stat_name: String, value: int, most: int, can_add: bool, add: Callable, bonus: int = 0) -> void:
	var name_label := _label(stat_name, 14, false)
	name_label.custom_minimum_size = Vector2(96, 0)
	var bar := ProgressBar.new()
	bar.max_value = most
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(STAT_BAR_WIDTH, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := _label("%d/%d%s" % [value, most, " (+%d)" % bonus if bonus > 0 else ""], 14, false)
	if bonus > 0:
		value_label.add_theme_color_override("font_color", UiPalette.GOOD)
	var row := _row([name_label, bar, value_label])
	if _officer.points > 0:
		var plus := _button("+1", add)
		plus.custom_minimum_size = Vector2(56, 36)
		plus.disabled = not can_add
		row.add_child(plus)
	_stats.add_child(row)


# --- Trang bị (M12e) ------------------------------------------------------------------------

## The three slots (pressing one shows it), the chosen slot's item and the storage items that fit.
func _fill_equipment() -> void:
	for child in _equip_box.get_children():
		_equip_box.remove_child(child)
		child.queue_free()
	var equipment := _state.equipment
	var slots := _row([])
	slots.add_theme_constant_override("separation", 12)
	_equip_box.add_child(slots)
	for slot in Item.SLOTS:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		var button := Button.new()
		button.toggle_mode = true
		button.button_pressed = slot == _slot
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2.ONE * (ItemIcon.SIZE * 2 + 12)
		button.pressed.connect(func() -> void:
			_slot = slot
			_dismantling = null
			_fill_equipment())
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(center)
		var icon := ItemIcon.new()
		icon.setup(_officer.items.get(slot), 2)
		center.add_child(icon)
		column.add_child(button)
		var caption := _label(Item.SLOT_NAMES[slot], 13, false)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(caption)
		slots.add_child(column)
	var worn: Item = _officer.items.get(_slot)
	if worn != null:
		_equip_box.add_child(_item_title(worn))
		for line in worn.describe_lines():
			_equip_box.add_child(_muted(line))
		var take_off := _button("Tháo ra", func() -> void:
			var result := equipment.unequip(_officer, _slot)
			if result != Equipment.Result.OK:
				set_status(Equipment.describe(result), false))
		take_off.custom_minimum_size = Vector2(120, 36)
		take_off.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_equip_box.add_child(take_off)
	else:
		_equip_box.add_child(_muted("%s: trống." % Item.SLOT_NAMES[_slot]))
	var has_forge := _state.forge_origin() != KingdomState.NO_FORGE
	var forge := _button("Đến xưởng rèn: rèn %s" % Item.SLOT_NAMES[_slot].to_lower(), func() -> void:
		forge_requested.emit(&"advisor" if _officer is Advisor else &"general", _slot))
	forge.custom_minimum_size = Vector2(0, 36)
	forge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	forge.disabled = not has_forge
	forge.tooltip_text = "" if has_forge else "Chưa có Xưởng rèn khí giới (thành cấp 3)."
	_equip_box.add_child(forge)
	if not has_forge:
		_equip_box.add_child(_muted("Chưa có Xưởng rèn khí giới (thành cấp 3)."))
	_equip_box.add_child(HSeparator.new())
	_equip_box.add_child(_label("Kho đồ %d/%d — hợp với ô %s:" % [equipment.items.size(), Equipment.MAX_STORAGE,
			Item.SLOT_NAMES[_slot].to_lower()], 13))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	_equip_box.add_child(list)
	var fitting := equipment.items.filter(func(item: Item) -> bool: return item.fits(_officer) and item.slot == _slot)
	fitting.sort_custom(func(a: Item, b: Item) -> bool: return a.rarity > b.rarity)
	if fitting.is_empty():
		list.add_child(_muted("Chưa có món nào. Rèn ở Xưởng rèn khí giới, hoặc thắng trận để có chiến lợi phẩm."))
	for item: Item in fitting:
		list.add_child(_storage_row(item))
	var others := _other_officers().filter(func(other: Officer) -> bool: return other.items.has(_slot))
	if not others.is_empty():
		_equip_box.add_child(HSeparator.new())
		_equip_box.add_child(_label("Đang ở trên người khác — đổi nhanh sang %s:" % _officer.name, 13))
		for other: Officer in others:
			_equip_box.add_child(_worn_row(other))


## The kingdom's other generals (or advisors, for an advisor).
func _other_officers() -> Array:
	var all: Array = _state.advisors.advisors if _officer is Advisor else _state.generals.generals
	return all.filter(func(other: Officer) -> bool: return other != _officer)


## An item another officer wears: their face and a short line about them, the item, and a button
## that moves it here (what this officer wore in that slot goes to them).
func _worn_row(other: Officer) -> Control:
	var item: Item = other.items[_slot]
	var face := PortraitView.new()
	face.setup(other, 0.5)
	var role := ""
	if other is General:
		role = "Tổng tướng" if other == _state.generals.commander else "Dự bị"
	else:
		role = Advisors.POST_NAMES[other.post] if other.post != Advisor.NO_POST else "Chưa giữ chức"
	var icon := ItemIcon.new()
	icon.setup(item, 2)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	column.add_child(_muted("%s %s · %s · Cấp %d" % [other.name, other.star_text(), role, other.level]))
	column.add_child(_item_title(item))
	column.add_child(_muted(" · ".join(item.describe_lines())))
	var swap := _button("Đổi", func() -> void:
		var result := _state.equipment.swap(other, _officer, _slot)
		if result == Equipment.Result.OK:
			set_status("Đã lấy %s từ %s." % [item.display_name, other.name])
		else:
			set_status(Equipment.describe(result), false))
	swap.custom_minimum_size = Vector2(100, 36)
	swap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := _row([face, icon, column, swap])
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	return row


func _storage_row(item: Item) -> Control:
	var icon := ItemIcon.new()
	icon.setup(item, 2)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	column.add_child(_item_title(item))
	column.add_child(_muted(" · ".join(item.describe_lines())))
	var wear := _button("Đeo", func() -> void:
		var result := _state.equipment.equip(_officer, item)
		if result != Equipment.Result.OK:
			set_status(Equipment.describe(result), false))
	wear.custom_minimum_size = Vector2(80, 36)
	var dismantle := _button("Chắc chắn?" if _dismantling == item else "Phân rã", func() -> void:
		if _dismantling != item:
			_dismantling = item
			_fill_equipment()
			return
		_dismantling = null
		var refund := _state.equipment.dismantle(item, _state.stockpile)
		set_status("Đã phân rã %s, lấy lại %s." % [item.display_name, UiFormat.amounts(refund, _resource_types)]))
	dismantle.custom_minimum_size = Vector2(100, 36)
	for button in [wear, dismantle]:
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := _row([icon, column, wear, dismantle])
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	return row


## The item's name in its rarity's color, with the rarity.
func _item_title(item: Item) -> Label:
	var title := _label("%s (%s)" % [item.display_name, Item.RARITY_NAMES[item.rarity]], 14)
	title.add_theme_color_override("font_color", UiPalette.ink(Item.RARITY_COLORS[item.rarity]))
	return title


func _muted(text: String) -> Label:
	var label := _label(text, 13)
	label.add_theme_color_override("font_color", UiPalette.MUTED)
	return label


## "Đột phá 1/3": the next break's requirements (✓ / ✗), cost chips and gains, then its button.
func _add_limit_break() -> void:
	var most := LimitBreak.max_breaks(_officer)
	if most == 0:
		return
	var view := RequirementView.new()
	_stats.add_child(view)
	view.header("Đột phá %d/%d" % [_officer.breaks, most])
	if _officer.breaks >= most:
		view.note("Đã đột phá hết số lần của bậc %d sao." % _officer.stars)
		return
	view.requirement("Đạt cấp tối đa (%d/%d)" % [_officer.level, _officer.max_level()],
			_officer.level >= _officer.max_level())
	var needed := LimitBreak.scrolls_needed(_officer)
	view.requirement("Bí kíp đột phá: %d/%d" % [_state.scrolls, needed], _state.scrolls >= needed)
	if _officer.away:
		view.requirement("Đang đi thảo phạt", false)
	view.header("Chi phí")
	view.costs(LimitBreak.cost(_officer), _state.stockpile)
	view.header("Nhận được")
	var cap := _officer.stat_cap(Generals.STAT_MAX)
	view.gain("Chỉ số tối đa %d → %d" % [cap, cap + LimitBreak.STAT_STEP])
	view.gain("Cấp tối đa %d → %d" % [_officer.max_level(), _officer.max_level() + LimitBreak.LEVEL_STEP])
	var button := _button("Chắc chắn?" if _break_armed else "Đột phá", _limit_break)
	button.custom_minimum_size = Vector2(160, 40)
	button.disabled = _state.check_limit_break(_officer) != LimitBreak.Result.OK
	_stats.add_child(_row([button]))


## A break spends a lot: the first press asks, the second breaks through.
func _limit_break() -> void:
	if not _break_armed:
		_break_armed = true
		set_status("Bấm lần nữa để đột phá cho %s." % _officer.name, false)
		_refresh()
		return
	_break_armed = false
	var result := _state.limit_break(_officer)
	if result == LimitBreak.Result.OK:
		Sfx.play(&"upgrade")
		set_status("%s đã đột phá: chỉ số tối đa %d, cấp tối đa %d." % [_officer.name,
				_officer.stat_cap(Generals.STAT_MAX), _officer.max_level()])
	else:
		set_status(LimitBreak.describe(result), false)
		_refresh()


func _is_still_here() -> bool:
	if _officer is General:
		return _state.generals.generals.has(_officer)
	return _state.advisors.advisors.has(_officer)


func _make_commander() -> void:
	_state.generals.set_commander(_officer as General)
	set_status("%s giờ là tổng tướng." % _officer.name)


## Dismissal cannot be undone: the first press asks, the second dismisses.
func _dismiss() -> void:
	if _dismiss_button.text == "Sa thải":
		_dismiss_button.text = "Chắc chắn?"
		set_status("Bấm lần nữa để sa thải %s. Không hoàn tác được." % _officer.name, false)
		return
	# Their items go back to storage.
	_state.dismiss_officer(_officer)
