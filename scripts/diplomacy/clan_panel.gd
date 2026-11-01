class_name ClanPanel
extends VBoxContainer
## Right-hand column of the world map: a summary of the selected clan (relation with its
## breakdown, treaties, war) and one button per diplomatic action. Each button opens a
## DiplomacyDialog in the middle of the screen (Shogun 2 style) where the action is set up.
## Buttons that cannot be used are disabled with the reason underneath. No hover needed
## (touch-ready).

## The player confirmed an attack on this clan; the kingdom scene runs the battle.
signal attack_requested(clan_id: StringName)

const MUTED_COLOR := UiPalette.MUTED
const WARNING_COLOR := UiPalette.WARNING

## Where dialogs are added (the world map screen, so they cover it).
var dialog_host: Control
var _state: KingdomState
var _diplomacy: Diplomacy
var _wars: Wars
var _alliances: Alliances
var _resource_types: Array[ResourceTypeData] = []
var _clan_id: StringName = &""
var _dialog: DiplomacyDialog
## The agent "Cử đặc vụ" picks first (GDD §8 M14e; set when the map opens for one agent).
var preferred_agent: Agent

var _hint: Label
var _details: VBoxContainer
var _name_label: Label
var _description: Label
var _info: Label
var _relation_bar: ProgressBar
var _relation_label: Label
var _relation_toggle: Button
var _relation_details_label: Label
var _goods: Label
var _standing: Label
## One entry per action: {"button": Button, "reason": Label, "update": Callable(button, reason)}.
var _commands: Array[Dictionary] = []


func setup(state: KingdomState, resource_types: Array[ResourceTypeData]) -> void:
	_state = state
	_diplomacy = state.diplomacy
	_wars = state.wars
	_alliances = state.alliances
	_resource_types = resource_types
	add_theme_constant_override("separation", 8)
	_hint = _label("Chạm vào một gia tộc trên bản đồ để xem thông tin và ra lệnh ngoại giao.", 14)
	add_child(_hint)
	_details = VBoxContainer.new()
	_details.add_theme_constant_override("separation", 6)
	_details.visible = false
	add_child(_details)
	_build_details()
	_diplomacy.changed.connect(refresh)
	_wars.changed.connect(refresh)
	state.stockpile.changed.connect(refresh)


func show_clan(clan_id: StringName) -> void:
	_clan_id = clan_id
	refresh()


## Opens the dialog for one action (also used by previews).
func open_dialog(dialog: DiplomacyDialog) -> void:
	if _dialog != null:
		_dialog.close()
	_dialog = dialog
	dialog_host.add_child(dialog)
	if dialog is AgentDialog:
		dialog.preferred = preferred_agent
	dialog.open(_state, _resource_types, _clan_id)
	dialog.closed.connect(func() -> void: _dialog = null)
	if dialog is AttackDialog:
		dialog.attack_confirmed.connect(func(id: StringName) -> void: attack_requested.emit(id))


func refresh() -> void:
	_hint.visible = _clan_id == &""
	_details.visible = _clan_id != &""
	if _clan_id == &"":
		return
	var clan := _diplomacy.clans[_clan_id]
	var data := clan.data
	_name_label.text = data.display_name
	_name_label.add_theme_color_override("font_color", UiPalette.ink(data.color))
	_description.text = data.description
	var front := _wars.fronts[_clan_id]
	_info.text = "%s · %s · Quân: %d/%d lính" % [_distance_text(), ClanData.PERSONALITY_NAMES[data.personality],
			front.strength, front.max_strength]
	var officers := _state.clan_officers.describe(_clan_id, _wars, _state.difficulty)
	if not officers.is_empty():
		_info.text += "\n" + officers
	var tier := Diplomacy.tier_for(clan.relation)
	_relation_bar.value = clan.relation
	var fill := StyleBoxFlat.new()
	fill.bg_color = WorldMapView.TIER_COLORS[tier]
	_relation_bar.add_theme_stylebox_override("fill", fill)
	_relation_label.text = "Quan hệ: %d (%s)" % [clan.relation, Diplomacy.TIER_NAMES[tier]]
	var target := _diplomacy.target_relation(_clan_id)
	_relation_label.text += "\nVề lâu dài: %d" % target if target != clan.relation else "\nỔn định ở mức này"
	var details := _relation_details()
	_relation_details_label.text = details
	# Hovering shows the same breakdown on desktop; the toggle is for touch screens.
	for control: Control in [_relation_label, _relation_bar]:
		control.tooltip_text = details
	_goods.text = "Dư: %s · Thiếu: %s\nBạn bè: %s" % [_resource_names(data.surplus), _resource_names(data.deficit),
			_clan_names(data.friends)]
	_standing.text = _standing_text()
	_standing.add_theme_color_override("font_color", WARNING_COLOR if front.at_war else UiPalette.TEXT)
	for command in _commands:
		var button: Button = command.button
		var reason: Label = command.reason
		button.visible = not front.annexed
		reason.text = ""
		if button.visible:
			command.update.call(button, reason)
		reason.visible = button.visible and not reason.text.is_empty()


## How far the clan is on the campaign map (GDD §15): bordering, within reach, or too far.
func _distance_text() -> String:
	if _diplomacy.clans[_clan_id].annexed:
		return "Lãnh thổ của bạn"
	var steps := _diplomacy.distance(_clan_id)
	if steps == 1:
		return "Giáp ranh"
	if steps <= Diplomacy.REACH:
		return "Cách %d vùng" % steps
	return "Cách %d vùng (quá xa)" % steps


## War or peace, then every treaty with its turns left.
func _standing_text() -> String:
	var clan := _diplomacy.clans[_clan_id]
	var front := _wars.fronts[_clan_id]
	if front.annexed:
		return "Đã sáp nhập vào vương quốc."
	var parts: Array[String] = []
	if front.at_war:
		parts.append("Đang chiến tranh!")
	elif front.truce_turns > 0:
		parts.append("Hòa bình (đình chiến còn %d lượt)" % front.truce_turns)
	else:
		parts.append("Hòa bình")
	if clan.is_allied():
		parts.append("Đồng minh (còn %d lượt)" % clan.alliance_turns)
	if clan.has_pact():
		parts.append("Bất tương xâm (còn %d lượt)" % clan.pact_turns)
	var agreement := clan.agreement
	if agreement != null:
		parts.append("Hợp đồng (còn %d lượt)" % agreement.turns_left)
	return " · ".join(parts)


## Every point of the relation, gains first then losses (Diplomacy.relation_factors), summing to it.
func _relation_details() -> String:
	var clan := _diplomacy.clans[_clan_id]
	var step: int = Diplomacy.DRIFT_PER_TURN[clan.data.personality]
	var gains: Array[String] = []
	var losses: Array[String] = []
	for factor in _diplomacy.relation_factors(_clan_id):
		var line := "  %+d  %s" % [factor.amount, Diplomacy.FACTOR_NAMES.get(factor.id, String(factor.id))]
		if factor.fading:
			line += " (mờ dần %d/lượt)" % step
		elif factor.id == &"wariness" and _diplomacy.wariness_target(_clan_id) != clan.wariness:
			line += " (sẽ thành %+d)" % -_diplomacy.wariness_target(_clan_id)
		(gains if factor.amount > 0 else losses).append(line)
	var lines: Array[String] = []
	if not gains.is_empty():
		lines.append("Cộng:")
		lines.append_array(gains)
	if not losses.is_empty():
		lines.append("Trừ:")
		lines.append_array(losses)
	lines.append("= %d (%s)" % [clan.relation, Diplomacy.TIER_NAMES[Diplomacy.tier_for(clan.relation)]])
	return "\n".join(lines)


func _on_relation_toggle_pressed() -> void:
	_relation_details_label.visible = not _relation_details_label.visible
	_relation_toggle.text = "Chi tiết quan hệ ▴" if _relation_details_label.visible else "Chi tiết quan hệ ▾"


# --- Commands -----------------------------------------------------------------------------
# Each update shows or enables its button and writes the reason when it cannot be used. The
# dialogs re-check everything; these only keep the column honest at a glance. During a war the
# peaceful actions that cannot work anyway (trade, agreement, treaties) are hidden.

func _update_trade(button: Button, reason: Label) -> void:
	button.visible = not _wars.at_war_with(_clan_id)
	button.disabled = _diplomacy.get_tier(_clan_id) < Diplomacy.MIN_TRADE_TIER
	if button.disabled:
		reason.text = Diplomacy.describe_trade(Diplomacy.TradeResult.REFUSED)


func _update_gift(button: Button, reason: Label) -> void:
	button.disabled = _diplomacy.clans[_clan_id].gift_gain_this_turn >= Diplomacy.MAX_GIFT_GAIN_PER_TURN
	if button.disabled:
		reason.text = Diplomacy.describe_gift(Diplomacy.GiftResult.LIMIT_REACHED)


func _update_agreement(button: Button, reason: Label) -> void:
	var clan := _diplomacy.clans[_clan_id]
	button.visible = not _wars.at_war_with(_clan_id)
	button.disabled = false
	if clan.agreement != null:
		var renewable := clan.agreement.turns_left <= Diplomacy.AGREEMENT_RENEW_TURNS
		button.text = "Hợp đồng giao thương (%s)" % ("gia hạn được" if renewable else "đang chạy")
		return
	button.text = "Hợp đồng giao thương"
	if _diplomacy.get_tier(_clan_id) < Diplomacy.MIN_TRADE_TIER:
		button.disabled = true
		reason.text = Diplomacy.describe_proposal(Diplomacy.ProposalResult.REFUSED)
	elif clan.proposed_this_turn:
		button.disabled = true
		reason.text = Diplomacy.describe_proposal(Diplomacy.ProposalResult.ASKED_THIS_TURN)


func _update_pact(button: Button, reason: Label) -> void:
	var clan := _diplomacy.clans[_clan_id]
	button.visible = not _wars.at_war_with(_clan_id) and not clan.is_allied()
	button.text = "Bất tương xâm (đang có)" if clan.has_pact() else "Bất tương xâm"
	var result := _alliances.check_pact(_clan_id)
	button.disabled = not clan.has_pact() and result != Alliances.PactResult.OK
	if clan.has_pact():
		reason.text = "Còn %d lượt." % clan.pact_turns
	elif button.disabled:
		reason.text = Alliances.describe_pact(result)


func _update_alliance(button: Button, reason: Label) -> void:
	var clan := _diplomacy.clans[_clan_id]
	button.visible = not _wars.at_war_with(_clan_id)
	button.text = "Liên minh (đang liên minh)" if clan.is_allied() else "Liên minh"
	# While allied the dialog is where to renew or cancel it.
	var result := _alliances.check_alliance(_clan_id)
	button.disabled = not clan.is_allied() and result != Alliances.AllianceResult.OK
	if button.disabled:
		reason.text = Alliances.describe_alliance(result)


func _update_declare(button: Button, reason: Label) -> void:
	button.visible = not _wars.at_war_with(_clan_id)
	var result := _wars.check_declare(_clan_id)
	button.disabled = result != Wars.DeclareResult.OK
	if button.visible and button.disabled:
		reason.text = Wars.describe_declare(result)


func _update_attack(button: Button, reason: Label) -> void:
	button.visible = _wars.at_war_with(_clan_id)
	var result := _wars.check_attack(_clan_id, _state.army.count_squads() > 0)
	button.disabled = result != Wars.AttackResult.OK
	if button.visible and button.disabled:
		reason.text = Wars.describe_attack(result)


func _update_peace(button: Button, reason: Label) -> void:
	button.visible = _wars.at_war_with(_clan_id)
	button.disabled = _wars.fronts[_clan_id].peace_offered_this_turn
	if button.visible and button.disabled:
		reason.text = Wars.describe_peace(Wars.PeaceResult.ASKED_THIS_TURN)


func _update_agent(button: Button, reason: Label) -> void:
	var idle := _state.agents.agents.any(func(a: Agent) -> bool: return not a.is_busy())
	var present := _state.agents.agent_on(_clan_id)
	button.disabled = not idle or _wars.fronts[_clan_id].annexed or present != null
	if _wars.fronts[_clan_id].annexed:
		reason.text = "Đã thuộc vương quốc."
	elif present != null:
		reason.text = "Đã có đặc vụ ở đây: %s (%s, còn %d lượt)." % [present.name,
				Agent.MISSION_NAMES[present.mission].to_lower(), present.turns_left]
	elif not idle:
		reason.text = "Không có đặc vụ rảnh (tuyển ở Sở cảnh sát)." if _state.agents.agents.is_empty() else "Mọi đặc vụ đều đang làm nhiệm vụ."


# --- Building -----------------------------------------------------------------------------

func _build_details() -> void:
	_name_label = _label("", 20)
	_details.add_child(_name_label)
	_description = _label("", 13)
	_description.add_theme_color_override("font_color", MUTED_COLOR)
	_details.add_child(_description)
	_info = _label("", 13)
	_details.add_child(_info)
	_relation_label = _label("", 14)
	_relation_label.mouse_filter = Control.MOUSE_FILTER_PASS  # for its tooltip
	_details.add_child(_relation_label)
	_relation_bar = ProgressBar.new()
	_relation_bar.min_value = Diplomacy.MIN_RELATION
	_relation_bar.max_value = Diplomacy.MAX_RELATION
	_relation_bar.show_percentage = false
	_relation_bar.custom_minimum_size = Vector2(0, 12)
	_details.add_child(_relation_bar)
	_relation_toggle = _button("Chi tiết quan hệ ▾", _on_relation_toggle_pressed)
	_relation_toggle.custom_minimum_size = Vector2(0, 32)
	_relation_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_details.add_child(_relation_toggle)
	_relation_details_label = _label("", 13)
	_relation_details_label.visible = false
	_details.add_child(_relation_details_label)
	_goods = _label("", 13)
	_details.add_child(_goods)
	_details.add_child(HSeparator.new())
	_standing = _label("", 15)
	_details.add_child(_standing)

	_add_command("Tấn công", AttackDialog, _update_attack, true)
	_add_command("Nghị hòa", PeaceDialog, _update_peace)
	_add_command("Trao đổi", TradeDialog, _update_trade)
	_add_command("Tặng quà", GiftDialog, _update_gift)
	_add_command("Hợp đồng giao thương", AgreementDialog, _update_agreement)
	_add_command("Liên minh", AllianceDialog, _update_alliance)
	_add_command("Bất tương xâm", PactDialog, _update_pact)
	_add_command("Tuyên chiến", DeclareWarDialog, _update_declare, true)
	_add_command("Cử đặc vụ", AgentDialog, _update_agent)


func _add_command(text: String, dialog_script: GDScript, update: Callable, danger: bool = false) -> void:
	var button := _button(text, func() -> void: open_dialog(dialog_script.new()))
	if danger:
		button.add_theme_color_override("font_color", UiPalette.WARNING_ON_WOOD)
	_details.add_child(button)
	var reason := _label("", 12)
	reason.add_theme_color_override("font_color", WARNING_COLOR)
	_details.add_child(reason)
	_commands.append({"button": button, "reason": reason, "update": update})


## Labels inside a row must not wrap: a wrapping label in an HBoxContainer collapses to zero width.
func _label(text: String, font_size: int, wrap: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 44)
	button.pressed.connect(on_pressed)
	return button


func _resource_name(resource_id: StringName) -> String:
	for type in _resource_types:
		if type.resource_id == resource_id:
			return type.display_name
	return String(resource_id)


func _resource_names(ids: Array[StringName]) -> String:
	var names: Array[String] = []
	for resource_id in ids:
		names.append(_resource_name(resource_id))
	return ", ".join(names) if not names.is_empty() else "—"


func _clan_names(ids: Array[StringName]) -> String:
	var names: Array[String] = []
	for clan_id in ids:
		if _diplomacy.clans.has(clan_id):
			names.append(_diplomacy.clans[clan_id].data.display_name)
	return ", ".join(names) if not names.is_empty() else "—"
