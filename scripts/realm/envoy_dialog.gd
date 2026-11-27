class_name EnvoyDialog
extends ModalWindow
## Sending an envoy to a nation (GDD §37, M18f-b2b): pick a ready advisor, then, to ask for peace,
## goods to send along and whether to hand a town back; the chance shows before sending. Also an
## alliance request and a courtesy visit. The envoy is away until the turn ends.

signal done(text: String, good: bool)

enum Mode { PEACE, ALLIANCE, VISIT }

const WIDTH := 0.56
const PORTRAIT := 0.5
## Goods choices (value) for a peace offer.
const GOODS_STEPS: Array[int] = [0, 100, 200, 400, 600]

var _state: KingdomState
var _nation: Realm.Nation
var _mode := Mode.PEACE
var _advisor: Advisor
var _cards: Dictionary = {}  # Button -> Advisor
var _goods := 0
var _goods_buttons: Dictionary = {}  # Button -> int
var _return_town: CheckBox
var _preview: RequirementView


func open(state: KingdomState, nation: Realm.Nation, mode: Mode) -> void:
	_state = state
	_nation = nation
	_mode = mode
	var titles := ["Cầu hòa với %s", "Xin liên minh với %s", "Thăm hỏi %s"]
	var body := build_frame(titles[mode] % nation.name, UiPalette.ACCENT, WIDTH)
	body.add_child(_label("Chọn một mưu sĩ đi sứ (vắng mặt tới hết lượt). Ngoại giao càng cao càng dễ thành.", 14))
	var cards := HFlowContainer.new()
	cards.add_theme_constant_override("h_separation", 8)
	cards.add_theme_constant_override("v_separation", 6)
	body.add_child(cards)
	var best: Advisor = null
	for advisor in state.advisors.advisors:
		cards.add_child(_card(advisor))
		if advisor.is_ready() and (best == null or advisor.stat_for(&"diplomacy") > best.stat_for(&"diplomacy")):
			best = advisor
	if state.advisors.advisors.is_empty():
		body.add_child(_label("Chưa có mưu sĩ nào: chiêu hiền ở thành chính.", 14))
	if mode == Mode.PEACE:
		body.add_child(HSeparator.new())
		body.add_child(_label("Kèm cống phẩm (chỉ mất khi họ đồng ý):", 14))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 6)
		for value in GOODS_STEPS:
			var button := Button.new()
			button.toggle_mode = true
			button.focus_mode = Control.FOCUS_NONE
			button.text = "Không" if value == 0 else "%d giá trị" % value
			button.custom_minimum_size = Vector2(110, 36)
			button.button_pressed = value == 0
			button.disabled = value > 0 and not state.stockpile.can_afford(RealmDiplomacy.goods_for(value))
			button.pressed.connect(_pick_goods.bind(value, button))
			_goods_buttons[button] = value
			row.add_child(button)
		body.add_child(row)
		var town := RealmDiplomacy.town_to_return(state.realm, nation.id)
		if town >= 0:
			_return_town = CheckBox.new()
			_return_town.text = "Trả lại trấn %s cho họ" % state.realm.towns[town].name
			_return_town.focus_mode = Control.FOCUS_NONE
			_return_town.toggled.connect(func(_on: bool) -> void: _refresh())
			body.add_child(_return_town)
	body.add_child(HSeparator.new())
	_preview = RequirementView.new()
	body.add_child(_preview)
	add_action("Gửi sứ giả", _send)
	if best != null:
		for card: Button in _cards:
			if _cards[card] == best:
				_pick(best, card)
	_refresh()


func _card(advisor: Advisor) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(230, 48 * PORTRAIT * 2 + 12)
	card.disabled = not advisor.is_ready()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.offset_right = -6
	var portrait := PortraitView.new()
	portrait.setup(advisor, PORTRAIT, _state.player_color)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(portrait)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_on_wood("%s %s" % [advisor.name, advisor.star_text()], 14, UiPalette.ON_WOOD))
	info.add_child(_on_wood("Ngoại giao %d" % advisor.stat_for(&"diplomacy"), 12, UiPalette.ON_WOOD_MUTED))
	if card.disabled:
		info.add_child(_on_wood(advisor.away_text() if advisor.away else "Bị thương, còn %d lượt" % advisor.wounded_turns,
				12, UiPalette.WARNING_ON_WOOD))
	row.add_child(info)
	card.add_child(row)
	card.pressed.connect(_pick.bind(advisor, card))
	_cards[card] = advisor
	return card


func _pick(advisor: Advisor, pressed: Button) -> void:
	_advisor = advisor
	for card: Button in _cards:
		card.set_pressed_no_signal(card == pressed)
	_refresh()


func _pick_goods(value: int, pressed: Button) -> void:
	_goods = value
	for button: Button in _goods_buttons:
		button.set_pressed_no_signal(button == pressed)
	_refresh()


func _returning() -> bool:
	return _return_town != null and _return_town.button_pressed


func _check() -> RealmDiplomacy.Result:
	var dip := _state.realm.diplomacy
	match _mode:
		Mode.PEACE:
			return dip.check_peace(_state.realm, _state, _nation.id, _advisor, _goods)
		Mode.ALLIANCE:
			return dip.check_alliance(_state.realm, _state, _nation.id, _advisor)
	return dip.check_visit(_state.realm, _state, _nation.id, _advisor)


func _refresh() -> void:
	var realm := _state.realm
	var dip := realm.diplomacy
	_preview.clear()
	match _mode:
		Mode.PEACE:
			var members := dip.peace_party(realm, _nation.id)
			if members.size() > 1:
				_preview.line(&"scroll", "Cả khối liên minh cùng hòa: %s" % ", ".join(members.map(func(id: StringName) -> String:
						return RealmDiplomacy.name_of(realm, id))))
			_preview.line(&"time", "Khả năng đồng ý: %d%%" % roundi(dip.peace_chance(realm, _state, _nation.id, _advisor,
					_goods, _returning()) * 100.0))
			if _goods > 0:
				_preview.costs(RealmDiplomacy.goods_for(_goods), _state.stockpile, "Cống phẩm")
			_preview.note("Đồng ý: hòa ước %d lượt, mọi lệnh đánh giữa hai bên bị hủy. Từ chối: %d lượt sau mới xin lại." % [
					RealmDiplomacy.PEACE_TURNS, RealmDiplomacy.REFUSE_WAIT])
		Mode.ALLIANCE:
			_preview.line(&"time", "Khả năng đồng ý: %d%%" % roundi(dip.alliance_chance(realm, _nation.id, _advisor) * 100.0))
			var wars := dip.alliance_wars(realm, _nation.id)
			if not wars.ours.is_empty():
				_preview.line(&"achievement_military", "Ta sẽ vào chiến tranh với: %s" % ", ".join(wars.ours.map(
						func(id: StringName) -> String: return RealmDiplomacy.name_of(realm, id))), UiPalette.WARNING)
			if not wars.theirs.is_empty():
				_preview.line(&"achievement_conquest", "%s sẽ đánh: %s" % [_nation.name, ", ".join(wars.theirs.map(
						func(id: StringName) -> String: return RealmDiplomacy.name_of(realm, id)))])
			_preview.note("Liên minh %d lượt: quân của họ ưu tiên đánh kẻ thù của ta và chặn quân địch sắp đánh trấn ta gần họ." %
					RealmDiplomacy.ALLIANCE_TURNS)
		Mode.VISIT:
			if _nation.submitted:
				_preview.line(&"scroll", "Trung thành +%d (hiện %d/%d)" % [Realm.LOYALTY_VISIT, _nation.loyalty, Realm.LOYALTY_MAX])
			else:
				_preview.line(&"scroll", "Quan hệ +%d ngay (phai dần như mọi sự kiện)" % roundi(RealmDiplomacy.visit_gain(_advisor)))
	var result := _check()
	set_status(RealmDiplomacy.describe(result) if result != RealmDiplomacy.Result.OK else "", result == RealmDiplomacy.Result.OK)


func _send() -> void:
	var result := _check()
	if result != RealmDiplomacy.Result.OK:
		set_status(RealmDiplomacy.describe(result), false)
		return
	var realm := _state.realm
	var dip := realm.diplomacy
	var text := ""
	var good := true
	match _mode:
		Mode.PEACE:
			var outcome := dip.ask_peace(realm, _state, _nation.id, _advisor, _goods, _returning())
			good = outcome.accepted
			if good:
				text = "%s chấp thuận hòa ước %d lượt." % [", ".join(outcome.nations.map(func(id: StringName) -> String:
						return RealmDiplomacy.name_of(realm, id))), RealmDiplomacy.PEACE_TURNS]
				if outcome.returned >= 0:
					text += " Trấn %s trả về cho họ." % realm.towns[outcome.returned].name
			else:
				text = "%s khước từ cầu hòa." % _nation.name
		Mode.ALLIANCE:
			var outcome := dip.ask_alliance(realm, _state, _nation.id, _advisor)
			good = outcome.accepted
			text = ("%s đồng ý liên minh!" if good else "%s khước từ liên minh.") % _nation.name
		Mode.VISIT:
			dip.visit(realm, _state, _nation.id, _advisor)
			text = ("Sứ giả thăm hỏi %s: lòng trung thành tăng." if _nation.submitted
					else "Sứ giả thăm hỏi %s: quan hệ được cải thiện.") % _nation.name
	Sfx.play(&"click" if good else &"error")
	done.emit(text, good)
	close()


func _on_wood(text: String, font_size: int, color: Color) -> Label:
	var label := _label(text, font_size, false)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
