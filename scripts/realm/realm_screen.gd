class_name RealmScreen
extends Control
## Full-screen realm map (Phân Chia Thiên Hạ, GDD §33, M18f-a), like the world map: the map on the
## left, a fixed-width panel on the right (M18g): the armies (portrait, soldiers, order), then one
## card — the selected army (units, order, "Xem chi tiết"), the town picked as its target (march
## or siege, alone or with the armies standing with it), or the selected town. Clicking a town
## selects it; with an army selected, clicking a neighboring town picks it as the target (GDD §34).
## Orders are carried out when the turn ends (sieges at the start of the next turn; every army
## ordered against a town fights it together) and can be cancelled until then. Tab picks the next
## army without an order. The nations' armies (M18f-b1) are listed on their town's card and on a
## target's card, where an army that announced an attack can be intercepted.

signal closed

## The side panel's fixed width: what it shows never changes the map's size.
const PANEL_WIDTH := 400.0
const ROSTER_PORTRAIT := 0.4
const CARD_PORTRAIT := 0.75
const CHIP_ICON := 30

var _state: KingdomState
var _map: RealmMapView
var _panel: VBoxContainer
var _title: Label
var _town := Realm.HOME_CAPITAL
var _force: Realm.Force
## A neighboring town the selected army may be ordered to, waiting for the order button.
var _siege_target := -1
var _status_text := ""
var _status_good := true


func open(state: KingdomState) -> void:
	_state = state
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = UiPalette.BACKDROP
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)
	var top := HBoxContainer.new()
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.theme_type_variation = &"WoodLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var back := Button.new()
	back.text = Touch.keys("Quay lại (Esc)")
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(0, 40)
	back.pressed.connect(close)
	top.add_child(back)
	layout.add_child(_margin(top))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(row)
	_map = RealmMapView.new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.realm = state.realm
	_map.player_color = state.player_color
	_map.kingdom_name = state.kingdom_name
	_map.town_clicked.connect(_on_town_clicked)
	row.add_child(_map)
	var paper := PanelContainer.new()
	paper.custom_minimum_size.x = PANEL_WIDTH
	row.add_child(paper)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	paper.add_child(scroll)
	_panel = VBoxContainer.new()
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.add_theme_constant_override("separation", 6)
	var panel_margin := _margin(_panel)
	panel_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel_margin)
	_refresh()


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close()
		elif event.keycode == KEY_TAB:
			select_next_force()
	get_viewport().set_input_as_handled()


## Selects the next army without an order (after the selected one), else the next army at all.
func select_next_force() -> void:
	var forces := _state.realm.forces
	if forces.is_empty():
		return
	var start := forces.find(_force)
	for pass_index in 2:
		for i in forces.size():
			var force: Realm.Force = forces[(start + 1 + i) % forces.size()]
			if pass_index == 1 or not force.has_order():
				_select_force(force)
				return


## Opens with this town (and its first army) selected; for tests and previews.
func select_town(town: int) -> void:
	_town = town
	var here := _state.realm.forces_at(town)
	_force = here[0] if not here.is_empty() else null
	_siege_target = -1
	_refresh()


func _on_town_clicked(town: int) -> void:
	_status_text = ""
	# A neighbor of the selected army: show it with a march / siege button (never moves on a click).
	if _force != null and _state.realm.forces.has(_force) and RealmMap.are_neighbors(_force.town, town):
		_town = town
		_siege_target = town
		_refresh()
		return
	_town = town
	_siege_target = -1
	var here := _state.realm.forces_at(town)
	_force = here[0] if not here.is_empty() else null
	_refresh()


func _set_status(text: String, good: bool) -> void:
	_status_text = text
	_status_good = good
	if not good:
		Sfx.play(&"error")


func _refresh() -> void:
	var realm := _state.realm
	if _force != null and not realm.forces.has(_force):
		_force = null
	if _force == null:
		_siege_target = -1
	_title.text = "Thiên hạ — Phân Chia Thiên Hạ (lượt %d)" % _state.turn
	_map.selected_town = _town
	_map.selected_force = _force
	_map.turn = _state.turn
	_map.queue_redraw()
	# Removed at once: children freed later would still take room for a frame and jolt the layout.
	for child in _panel.get_children():
		_panel.remove_child(child)
		child.queue_free()
	_fill_roster()
	_panel.add_child(HSeparator.new())
	if _force != null and _siege_target >= 0:
		_fill_target(realm.towns[_siege_target])
	elif _force != null:
		_fill_force(_force)
	else:
		_fill_town(realm.towns[_town])
	if _status_text != "":
		_panel.add_child(_line(_status_text, 14, UiPalette.GOOD if _status_good else UiPalette.WARNING))


## The kingdom's towns, then every army as a row: the general's portrait and a button with its
## soldiers and order (▶ the selected one); "Đạo kế tiếp (Tab)".
func _fill_roster() -> void:
	var realm := _state.realm
	var waiting := realm.forces.filter(func(force: Realm.Force) -> bool: return not force.has_order()).size()
	_panel.add_child(_line("Trấn của ta %d/%d · %d đạo quân%s" % [realm.count_owned(Realm.PLAYER), RealmMap.TOWN_COUNT,
			realm.forces.size(), " (%d chờ lệnh)" % waiting if waiting > 0 else ""], 14, UiPalette.MUTED))
	var threatened := {}
	for army in realm.armies:
		if army.has_target() and realm.towns[army.target].owner == Realm.PLAYER:
			threatened[army.target] = true
	if not threatened.is_empty():
		_panel.add_child(_line("⚠ Địch chuẩn bị đánh: %s" % ", ".join(threatened.keys().map(func(id: int) -> String:
				return realm.towns[id].name)), 14, UiPalette.WARNING))
	for force in realm.forces:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(ArmyFlag.of(force))
		var portrait := PortraitView.new()
		portrait.setup(force.general, ROSTER_PORTRAIT, _state.player_color)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(portrait)
		var button := _button("%s%s · %d lính · %s" % ["▶ " if force == _force else "", force.general.name,
				force.soldiers(), _order_text(force, true)], _select_force.bind(force))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 13)
		if force.has_order():
			button.add_theme_color_override("font_color", RealmMapView.order_color(force.order).lightened(0.55))
		row.add_child(button)
		_panel.add_child(row)
	var buttons: Array[Button] = []
	if not realm.forces.is_empty():
		buttons.append(_button(Touch.keys("Đạo kế tiếp (Tab)"), select_next_force))
	if _force != null:
		buttons.append(_button("Bỏ chọn", func() -> void:
			_force = null
			_siege_target = -1
			_refresh()))
	if not buttons.is_empty():
		_panel.add_child(_buttons_row(buttons))
	_fill_nations()


## Every nation standing: its pact with us and our relation; a click shows its capital.
func _fill_nations() -> void:
	var realm := _state.realm
	var dip := realm.diplomacy
	var nations := RealmWar.live_nations(realm)
	if nations.is_empty():
		return
	_panel.add_child(_line("Các nước", 14, UiPalette.HEADER))
	for nation in nations:
		var button := _button("%s · %s · %+d" % [nation.name, dip.status_text(nation.id), dip.relation(Realm.PLAYER, nation.id)],
				func() -> void:
					_force = null
					_siege_target = -1
					_town = nation.capital()
					_refresh())
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 13)
		button.custom_minimum_size.y = 32
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(_swatch(nation.color))
		row.add_child(button)
		_panel.add_child(row)


## A small square in a nation's color, for lists where colored text would be hard to read.
static func _swatch(color: Color) -> Panel:
	var swatch := Panel.new()
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = Color(0.15, 0.09, 0.05)
	box.set_border_width_all(2)
	box.set_corner_radius_all(3)
	swatch.add_theme_stylebox_override("panel", box)
	swatch.custom_minimum_size = Vector2(18, 18)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return swatch


## "chờ lệnh", "→ X", "⚔ X", "⌂ về kinh đô"; the long form for the army card.
func _order_text(force: Realm.Force, short: bool) -> String:
	var realm := _state.realm
	match force.order:
		Realm.MOVE:
			return ("→ %s" if short else "Lệnh: hành quân tới %s khi hết lượt.") % realm.towns[force.target].name
		Realm.SIEGE:
			return ("⚔ %s" if short else "Lệnh: công thành %s ở đầu lượt sau.") % realm.towns[force.target].name
		Realm.INTERCEPT:
			var enemy := realm.army_by_id(force.army)
			var enemy_name := enemy.general.name if enemy != null else "?"
			return ("✕ chặn %s" if short else "Lệnh: đánh chặn đạo quân %s ở đầu lượt sau.") % enemy_name
		Realm.HOME:
			var steps := realm.route(force.town, Realm.HOME_CAPITAL).size()
			return "⌂ về kinh đô" if short else "Lệnh: về kinh đô, còn %d chặng (mỗi lượt một chặng)." % steps
	return "chờ lệnh" if short else "Chưa có lệnh."


## The selected town when no army is selected: who holds it and what it gives.
func _fill_town(town: Realm.Town) -> void:
	var realm := _state.realm
	var owner_color := realm.owner_color(town, _state.player_color)
	_panel.add_child(_line(("♛ " if town.is_capital() else "") + town.name, 20, UiPalette.ink(owner_color)))
	_panel.add_child(_line("%s của %s" % ["Kinh đô" if town.is_capital() else "Trấn",
			realm.owner_name(town, _state.kingdom_name)], 15))
	if town.owner != Realm.PLAYER:
		_panel.add_child(_line("Quân thủ %d/%d lính · tường thành +%d%% phòng thủ" % [town.garrison, town.max_garrison,
				roundi((Realm.CAPITAL_WALL_DEFENSE if town.is_capital() else Realm.WALL_DEFENSE) * 100)], 14))
		_fill_armies(town, null)
		if town.owner != Realm.REBELS:
			_panel.add_child(_line("Ngân khố %s: %d/%d (lập đạo quân mới tốn %d)" % [realm.nations[town.owner].name,
					floori(realm.treasury.get(town.owner, 0.0)), roundi(RealmWar.MAX_TREASURY), roundi(RealmWar.ARMY_COST)],
					13, UiPalette.MUTED))
		if town.owner != Realm.REBELS:
			_fill_diplomacy(realm.nations[town.owner])
		if town.is_capital() and town.owner != Realm.REBELS:
			_panel.add_child(_line("Chiếm kinh đô thì %s bị diệt, các trấn còn lại về tay ta (trấn có đạo quân của họ thành tàn quân nổi loạn)." % realm.nations[town.owner].name,
					13, UiPalette.MUTED))
	elif town.is_captured():
		var view := RequirementView.new()
		_panel.add_child(view)
		view.amounts("Mỗi lượt", realm.town_yield(town), false)
		_panel.add_child(_line("+%d đơn vị tối đa · dân binh %d lính" % [Realm.TOWN_SQUADS, realm.militia_soldiers(town)], 14))
		var chance := realm.revolt_chance(town, _state.turn)
		var old_nation: Realm.Nation = realm.nations[town.nation]
		var why := "mới chiếm"
		if chance > 0.0 and old_nation.destroyed:
			why = "nước cũ đã bị diệt, đang bình định" if old_nation.vassal != null else "nước cũ đã bị diệt, chưa có chư hầu"
		elif chance > 0.0:
			why = "có quân trấn giữ" if not realm.forces_at(town.id).is_empty() else "không quân trấn giữ"
		_panel.add_child(_line("Nguy cơ nổi loạn: %s%% mỗi lượt (%s)" % [CrownDialog._percent(chance), why], 14,
				UiPalette.WARNING if chance >= Realm.REVOLT_CHANCE else UiPalette.TEXT))
		_fill_vassal(town, old_nation)
	else:
		_panel.add_child(_line("Đất các gia tộc đã thống nhất · +%d đơn vị tối đa" % Realm.TOWN_SQUADS, 14))
	if town.owner == Realm.PLAYER:
		for army in realm.armies_targeting(town.id):
			_panel.add_child(_line("⚠ Đạo quân %s (%s, %d lính) ở %s chuẩn bị đánh trấn này." % [army.general.name,
					realm.nations[army.nation].name, army.soldiers, realm.towns[army.town].name], 14, UiPalette.WARNING))
	var share := realm.replenish_share(town.id, _state.replenish_fraction())
	if share > 0.0:
		_panel.add_child(_line("Đạo quân ở đây hồi %d%% quân số mỗi đơn vị mỗi lượt." % roundi(share * 100.0), 13,
				UiPalette.MUTED))
	if town.id == Realm.HOME_CAPITAL:
		_panel.add_child(_button("Lập đạo quân mới", _open_army.bind(null)))


## The vassal ruling the land of our town `town` (destroyed `nation`): its king, guard, armies and
## tribute; on the old capital of a destroyed nation without one, "Phong vương lập chư hầu".
func _fill_vassal(town: Realm.Town, nation: Realm.Nation) -> void:
	if not nation.destroyed:
		return
	var realm := _state.realm
	if nation.vassal == null:
		if town.id == nation.capital():
			_panel.add_child(_line("Phong một tướng làm vua chư hầu để bình định đất %s (nổi loạn giảm dần về 1%%)." %
					nation.name, 13, UiPalette.MUTED))
			_panel.add_child(_button("Phong vương lập chư hầu", _open_crown.bind(nation)))
		return
	var king := nation.vassal
	_panel.add_child(_line("Chư hầu %s — vua %s %s" % [nation.name, king.name, king.star_text()], 15, UiPalette.HEADER))
	_panel.add_child(_line("Võ %d · Thống %d · quân chư hầu giữ trấn %d lính" % [king.might, king.command,
			realm.vassal_guard(town)], 13))
	var view := RequirementView.new()
	_panel.add_child(view)
	view.amounts("Cống nạp mỗi lượt", Realm.tribute_of(king))
	var armies := realm.armies_of(nation.id)
	var soldiers := 0
	for army in armies:
		soldiers += army.soldiers
	_panel.add_child(_line("%d đạo quân chư hầu (%d lính) · ngân khố %d/%d" % [armies.size(), soldiers,
			floori(realm.treasury.get(nation.id, 0.0)), roundi(RealmWar.MAX_TREASURY)], 13, UiPalette.MUTED))


## Our pact and relation with `nation`, its wars and treaties, and what we can do (GDD §37).
func _fill_diplomacy(nation: Realm.Nation) -> void:
	var realm := _state.realm
	var dip := realm.diplomacy
	var p := dip.pair(Realm.PLAYER, nation.id)
	_panel.add_child(HSeparator.new())
	_panel.add_child(_line("Ngoại giao với %s" % nation.name, 15, UiPalette.HEADER))
	var status := RealmDiplomacy.PACT_NAMES[p.pact]
	if p.pact == RealmDiplomacy.Pact.WAR:
		status += " (%d lượt)" % (_state.turn - p.war_since)
	elif p.pact != RealmDiplomacy.Pact.NEUTRAL:
		status += ", còn %d lượt" % p.turns
	_panel.add_child(_line(status, 14, UiPalette.WARNING if p.pact == RealmDiplomacy.Pact.WAR else UiPalette.GOOD))
	if dip.in_bloc(nation.id):
		_panel.add_child(_line("Khối liên minh chống ta: %s" % ", ".join(dip.bloc.map(func(id: StringName) -> String:
				return RealmDiplomacy.name_of(realm, id))), 13, UiPalette.WARNING))
	var rel := p.relation()
	var goal := roundi(dip.target(realm, _state, Realm.PLAYER, nation.id))
	_panel.add_child(_line("Quan hệ %+d (%s) · về lâu dài %+d" % [rel, RealmDiplomacy.tier_name(rel), goal], 14))
	for factor in dip.factors(realm, _state, Realm.PLAYER, nation.id):
		_panel.add_child(_line("  • %s %+d" % [factor.text, factor.value], 12, UiPalette.MUTED))
	if absf(p.memory) >= 0.5:
		_panel.add_child(_line("  • Sự kiện gần đây %+d (phai dần)" % roundi(p.memory), 12, UiPalette.MUTED))
	var wars: Array[String] = []
	var friends: Array[String] = []
	for id in RealmDiplomacy.parties(realm):
		if id == nation.id or id == Realm.PLAYER:
			continue
		if dip.at_war(nation.id, id):
			wars.append(RealmDiplomacy.name_of(realm, id))
		elif dip.pact(nation.id, id) != RealmDiplomacy.Pact.NEUTRAL:
			friends.append("%s (%s)" % [RealmDiplomacy.name_of(realm, id), RealmDiplomacy.PACT_NAMES[dip.pact(nation.id, id)]])
	if not wars.is_empty():
		_panel.add_child(_line("Đang đánh: %s" % ", ".join(wars), 12, UiPalette.MUTED))
	if not friends.is_empty():
		_panel.add_child(_line("Hòa hảo: %s" % ", ".join(friends), 12, UiPalette.MUTED))
	var buttons: Array[Button] = []
	var reasons: Array[String] = []
	if p.pact == RealmDiplomacy.Pact.WAR:
		buttons.append(_diplomacy_button("Cầu hòa", _open_envoy.bind(nation, EnvoyDialog.Mode.PEACE),
				dip.check_peace(realm, _state, nation.id, null), reasons))
	else:
		buttons.append(_diplomacy_button("Bất tương xâm", func() -> void:
			dip.sign_nap(realm, _state, nation.id)
			_set_status("Ký bất tương xâm với %s." % nation.name, true)
			_refresh(), dip.check_nap(realm, _state, nation.id), reasons))
		buttons.append(_diplomacy_button("Liên minh", _open_envoy.bind(nation, EnvoyDialog.Mode.ALLIANCE),
				dip.check_alliance(realm, _state, nation.id, null), reasons))
	_panel.add_child(_buttons_row(buttons))
	var more: Array[Button] = [_diplomacy_button("Thăm hỏi", _open_envoy.bind(nation, EnvoyDialog.Mode.VISIT),
			dip.check_visit(realm, _state, nation.id, null), reasons)]
	if p.pact != RealmDiplomacy.Pact.WAR:
		more.append(_button("Tuyên chiến", _ask_declare.bind(nation)))
	if dip.allied(Realm.PLAYER, nation.id):
		more.append(_button("Hủy liên minh", func() -> void:
			ConfirmWindow.ask(self, "Hủy liên minh", "Hủy liên minh với %s?" % nation.name,
					func(view: RequirementView) -> void:
						view.note("Phá ước: %s %+d quan hệ, mọi nước khác %+d." % [nation.name,
								roundi(RealmDiplomacy.BREAK_VICTIM), roundi(RealmDiplomacy.BREAK_OTHERS)]),
					"Hủy liên minh", func() -> void:
						dip.cancel_alliance(realm, _state, nation.id)
						_refresh(), true)))
	_panel.add_child(_buttons_row(more))
	for reason in reasons:
		_panel.add_child(_line(reason, 12, UiPalette.MUTED))


## A diplomacy button, disabled with its reason listed when `result` is not OK (an advisor still to
## be picked counts as OK).
func _diplomacy_button(text: String, on_pressed: Callable, result: RealmDiplomacy.Result, reasons: Array[String]) -> Button:
	var button := _button(text, on_pressed)
	if result != RealmDiplomacy.Result.OK and result != RealmDiplomacy.Result.NO_ADVISOR:
		button.disabled = true
		reasons.append("%s: %s" % [text, RealmDiplomacy.describe(result)])
	return button


func _open_envoy(nation: Realm.Nation, mode: EnvoyDialog.Mode) -> void:
	var dialog := EnvoyDialog.new()
	add_child(dialog)
	dialog.open(_state, nation, mode)
	dialog.done.connect(func(text: String, good: bool) -> void:
		_set_status(text, good)
		_refresh())


func _ask_declare(nation: Realm.Nation) -> void:
	var dip := _state.realm.diplomacy
	var p := dip.pair(Realm.PLAYER, nation.id)
	var breaking := p.pact in [RealmDiplomacy.Pact.PEACE, RealmDiplomacy.Pact.NAP, RealmDiplomacy.Pact.ALLIANCE]
	ConfirmWindow.ask(self, "Tuyên chiến", "Tuyên chiến với %s?" % nation.name,
			func(view: RequirementView) -> void:
				if breaking:
					view.note("Phá %s: %s %+d quan hệ, mọi nước khác %+d." % [RealmDiplomacy.PACT_NAMES[p.pact].to_lower(),
							nation.name, roundi(RealmDiplomacy.BREAK_VICTIM), roundi(RealmDiplomacy.BREAK_OTHERS)])
				else:
					view.note("Đang trung lập: không phá ước nào."),
			"Tuyên chiến", func() -> void:
				var joined := dip.player_declares(_state.realm, _state, nation.id)
				_set_status("Chiến tranh với %s." % ", ".join(joined.map(func(id: StringName) -> String:
						return RealmDiplomacy.name_of(_state.realm, id))), true)
				_refresh(), true)


func _open_crown(nation: Realm.Nation) -> void:
	var dialog := CrownDialog.new()
	add_child(dialog)
	dialog.open(_state, nation)
	dialog.done.connect(func() -> void:
		_set_status("%s đã thành chư hầu của ta." % nation.name, true)
		_refresh())


## The selected army: its general, its soldiers by unit, its order and what can be done with it.
func _fill_force(force: Realm.Force) -> void:
	var general := force.general
	var realm := _state.realm
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var portrait := PortraitView.new()
	portrait.setup(general, CARD_PORTRAIT, _state.player_color)
	head.add_child(portrait)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_line("Đạo quân %s" % general.name, 17, UiPalette.ink(_state.player_color)))
	info.add_child(_line("%s · Võ %d · Thống %d" % [general.star_text(), general.total_might(), general.total_command()], 13))
	info.add_child(_line("Ở %s · %d/%d đơn vị · %d lính" % [realm.towns[force.town].name, force.squads.size(),
			Realm.MAX_ARMY_SQUADS, force.soldiers()], 13))
	if general.wounded_turns > 0:
		info.add_child(_line("Tướng bị thương, còn %d lượt" % general.wounded_turns, 13, UiPalette.WARNING))
	head.add_child(info)
	_panel.add_child(head)
	_panel.add_child(_unit_chips(force))
	_panel.add_child(_line(_order_text(force, false), 15,
			RealmMapView.order_color(force.order) if force.has_order() else UiPalette.TEXT))
	var buttons: Array[Button] = [_button("Xem chi tiết đạo quân", _open_detail.bind(force))]
	if force.has_order():
		buttons.append(_button("Hủy lệnh", func() -> void:
			realm.cancel_order(force)
			Sfx.play(&"click")
			_refresh()))
	_panel.add_child(_buttons_row(buttons))
	if not force.has_order():
		_panel.add_child(_line("Bấm trấn kề trên bản đồ: vòng xanh để hành quân, vòng đỏ để công thành.", 13, UiPalette.MUTED))
	if force.town != Realm.HOME_CAPITAL and force.order != Realm.HOME:
		var home := _button("Về kinh đô", func() -> void:
			var result := realm.order_home(force, _state.turn)
			if result == Realm.Result.OK:
				Sfx.play(&"place_land")
				_after_order(force.town)
			else:
				_set_status(Realm.describe(result), false)
			_refresh())
		home.disabled = realm.check_home(force) != Realm.Result.OK
		_panel.add_child(home)
	if force.town == Realm.HOME_CAPITAL:
		_panel.add_child(_buttons_row([_button("Điều chỉnh quân", _open_army.bind(force)),
				_button("Giải tán", func() -> void:
					ConfirmWindow.ask(self, "Giải tán đạo quân", "Giải tán đạo quân %s?" % force.general.name,
							func(view: RequirementView) -> void:
								view.note("Tướng và %d đơn vị về lại kinh đô, giữ nguyên lính." % force.squads.size()),
							"Giải tán", func() -> void:
								realm.disband(_state, force)
								_force = null
								_refresh(), true))]))
	# The town it stands in: its card stays one button away, and a destroyed nation's land shows
	# its vassal (or the crown button on the old capital) right here.
	var town := realm.towns[force.town]
	if town.owner == Realm.PLAYER and town.nation != Realm.PLAYER and realm.nations.has(town.nation) \
			and realm.nations[town.nation].destroyed:
		_panel.add_child(HSeparator.new())
		_fill_vassal(town, realm.nations[town.nation])
	_panel.add_child(_button("Xem trấn %s" % town.name, func() -> void:
		_force = null
		_refresh()))


## One chip per unit type in the army: its icon and how many squads.
func _unit_chips(force: Realm.Force) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	var counts := {}
	for squad in force.squads:
		counts[squad.unit_id] = counts.get(squad.unit_id, 0) + 1
	for unit_id in counts:
		var unit: UnitData = _state.units[unit_id]
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 2)
		chip.tooltip_text = unit.display_name
		chip.add_child(ArmyDetailWindow.unit_icon(unit, CHIP_ICON))
		var count := _line("×%d" % counts[unit_id], 14, unit.tier_color(false))
		count.autowrap_mode = TextServer.AUTOWRAP_OFF
		chip.add_child(count)
		flow.add_child(chip)
	return flow


## A neighboring town picked for the selected army: march there (a town of ours) or besiege it,
## alone or with the other armies standing with it; the odds count every army ordered there.
func _fill_target(town: Realm.Town) -> void:
	var realm := _state.realm
	var force := _force
	var ours := town.owner == Realm.PLAYER
	_panel.add_child(_line(("→ Hành quân tới %s" if ours else "⚔ Công thành %s") % town.name, 18,
			UiPalette.TEXT if ours else UiPalette.WARNING))
	_panel.add_child(_line("Đạo quân %s · %d lính" % [force.general.name, force.soldiers()], 14))
	# Armies standing with this one, free to go too.
	var mates: Array[Realm.Force] = []
	for other in realm.forces_at(force.town):
		if other != force and not other.has_order() and (realm.check_move(other, town.id) if ours
				else realm.check_siege(other, town.id)) == Realm.Result.OK:
			mates.append(other)
	var check := realm.check_move(force, town.id) if ours else realm.check_siege(force, town.id)
	if ours:
		if check == Realm.Result.OK:
			_panel.add_child(_button("Ra lệnh hành quân", _give_order.bind([force], town.id)))
			if not mates.is_empty():
				_panel.add_child(_button("Cả %d đạo ở đây cùng đi" % (mates.size() + 1),
						_give_order.bind([force] + mates, town.id)))
			_panel.add_child(_line("Đi khi bấm Kết thúc lượt; nhiều đạo có thể cùng tới một trấn.", 13, UiPalette.MUTED))
	else:
		var joined := realm.besiegers(town.id).filter(func(other: Realm.Force) -> bool: return other != force)
		var total := force.soldiers()
		for other: Realm.Force in joined:
			total += other.soldiers()
		if not joined.is_empty():
			_panel.add_child(_line("Cùng đánh: %s" % ", ".join(joined.map(func(other: Realm.Force) -> String:
					return "%s (%d)" % [other.general.name, other.soldiers()])), 13, UiPalette.GOOD))
		var compare := ForceCompare.new()
		_panel.add_child(compare)
		compare.setup(total, _state.player_color, realm.town_soldiers(town), realm.owner_color(town, _state.player_color),
				Realm.CAPITAL_WALL_DEFENSE if town.is_capital() else Realm.WALL_DEFENSE, "tường thành")
		if check == Realm.Result.OK:
			_panel.add_child(_button("Ra lệnh công thành", _give_order.bind([force], town.id)))
			if not mates.is_empty():
				var all := total
				for other in mates:
					all += other.soldiers()
				_panel.add_child(_button("Cả %d đạo ở đây cùng đánh (%d lính)" % [mates.size() + 1, all],
						_give_order.bind([force] + mates, town.id)))
			_panel.add_child(_line("Đánh ở đầu lượt sau. Mọi đạo được lệnh đánh trấn này sẽ hợp quân, tướng giỏi nhất chỉ huy.",
					13, UiPalette.MUTED))
		if not realm.armies_at(town.id).is_empty():
			_panel.add_child(_line("Công thành phải đánh cả quân thủ lẫn các đạo quân trong trấn:", 13, UiPalette.MUTED))
			_fill_armies(town, force)
	if check != Realm.Result.OK:
		_panel.add_child(_line(Realm.describe(check), 14, UiPalette.WARNING))
	_panel.add_child(_button("Quay lại đạo quân", func() -> void:
		_siege_target = -1
		_town = force.town
		_refresh()))


## The enemy armies in `town`: portrait, stars, soldiers and any attack they announced; with our
## army `force` next to them, a button to intercept each army that announced one.
func _fill_armies(town: Realm.Town, force: Realm.Force) -> void:
	var realm := _state.realm
	for army in realm.armies_at(town.id):
		var nation: Realm.Nation = realm.nations[army.nation]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var portrait := PortraitView.new()
		portrait.setup(army.general, ROSTER_PORTRAIT, nation.color)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(portrait)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(_line("Đạo quân %s (%s) %s" % [army.general.name, nation.name, army.general.star_text()], 13,
				UiPalette.ink(nation.color)))
		info.add_child(_line("%d/%d lính%s" % [army.soldiers, army.max_soldiers,
				" · ⚔ chuẩn bị đánh %s" % realm.towns[army.target].name if army.has_target() else ""], 13,
				UiPalette.WARNING if army.has_target() else UiPalette.TEXT))
		row.add_child(info)
		_panel.add_child(row)
		if force != null and army.has_target():
			var check := realm.check_intercept(force, army)
			var button := _button("Đánh chặn %s" % army.general.name,
					_give_intercept.bind([force], army))
			button.disabled = check != Realm.Result.OK
			_panel.add_child(button)
			if check == Realm.Result.OK:
				_panel.add_child(_line("Đánh ngoài thành (không tường, không quân thủ) ở đầu lượt sau, trước khi họ tấn công. Thắng thì đạo quân đó tan rã.",
						13, UiPalette.MUTED))
			else:
				_panel.add_child(_line(Realm.describe(check), 13, UiPalette.WARNING))


func _give_intercept(group: Array, army: NationArmy) -> void:
	_status_text = ""
	for force: Realm.Force in group:
		var result := _state.realm.order_intercept(force, army, _state.turn)
		if result != Realm.Result.OK:
			_set_status(Realm.describe(result), false)
			break
	if _status_text == "":
		Sfx.play(&"place_land")
		_after_order(group[0].town)
	_refresh()


func _give_order(group: Array, town: int) -> void:
	_status_text = ""
	for force: Realm.Force in group:
		var result := _state.realm.order(force, town, _state.turn)
		if result != Realm.Result.OK:
			_set_status(Realm.describe(result), false)
			break
	if _status_text == "" or _status_good:
		Sfx.play(&"place_land")
		_after_order(group[0].town)
	_refresh()


## An order given: the army is let go, so the next click on the map picks something else (another
## army standing next to it, say) instead of a target for this one.
func _after_order(town: int) -> void:
	_force = null
	_siege_target = -1
	_town = town


func _select_force(force: Realm.Force) -> void:
	_force = force
	_town = force.town
	_siege_target = -1
	_refresh()


func _open_army(force: Realm.Force) -> void:
	var dialog := ArmyDialog.new()
	add_child(dialog)
	dialog.open(_state, force)
	dialog.done.connect(func() -> void:
		if force == null and not _state.realm.forces.is_empty():
			_force = _state.realm.forces.back()
		_refresh())


func _open_detail(force: Realm.Force) -> void:
	var window := ArmyDetailWindow.new()
	add_child(window)
	window.open(_state, force)


func _line(text: String, font_size: int, color: Color = UiPalette.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## Long texts are cut, never widening the panel.
func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = text
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.custom_minimum_size = Vector2(0, 38)
	button.pressed.connect(on_pressed)
	return button


func _buttons_row(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for button: Button in buttons:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
	return row


func _margin(child: Control) -> MarginContainer:
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 10)
	margin.add_child(child)
	return margin
