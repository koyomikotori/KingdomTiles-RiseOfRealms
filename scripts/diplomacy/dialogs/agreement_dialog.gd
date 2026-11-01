class_name AgreementDialog
extends DiplomacyDialog
## Long-term trade agreement (GDD §9.5): offer one (with the acceptance chance shown first), or
## look at the running one, renew it in its last Diplomacy.AGREEMENT_RENEW_TURNS turns (M16f) or
## cancel it.

const DEFAULT_TURNS := 10

var _offer_box: VBoxContainer
var _give_amount: SpinBox
var _give_option: OptionButton
var _get_amount: SpinBox
var _get_option: OptionButton
var _turns: SpinBox
var _preview: Label
var _contract_label: Label
var _renew_box: VBoxContainer
var _renew_turns: SpinBox
var _renew_preview: Label
var _renew_button: Button
var _fair_button: Button
var _offer_button: Button
var _cancel_button: Button


func _title() -> String:
	return "Hợp đồng giao thương với %s" % clan_data().display_name


func _shows_stockpile() -> bool:
	return true


func _build(content: VBoxContainer) -> void:
	_contract_label = _label("", 15)
	content.add_child(_contract_label)
	_offer_box = VBoxContainer.new()
	_offer_box.add_theme_constant_override("separation", 8)
	content.add_child(_offer_box)
	var hint := _label("Mỗi lượt bạn đưa một thứ, họ giao lại một thứ. Ký xong: quan hệ +%d, và +%d suốt thời gian hợp đồng chạy." % [
			Diplomacy.AGREEMENT_SIGN_GAIN, Diplomacy.AGREEMENT_BASE_BONUS], 13)
	hint.add_theme_color_override("font_color", MUTED_COLOR)
	_offer_box.add_child(hint)
	_give_amount = _amount_box()
	_give_option = _resource_option(1)
	_offer_box.add_child(_row([_label("Mỗi lượt đưa", 15, false), _give_amount, _give_option]))
	_get_amount = _amount_box()
	_get_option = _resource_option(0)
	_offer_box.add_child(_row([_label("Mỗi lượt nhận", 15, false), _get_amount, _get_option]))
	_turns = _amount_box(DEFAULT_TURNS, Diplomacy.AGREEMENT_MIN_TURNS, Diplomacy.AGREEMENT_MAX_TURNS)
	_offer_box.add_child(_row([_label("Trong", 15, false), _turns, _label("lượt", 15, false)]))
	_preview = _label("", 15)
	_offer_box.add_child(_preview)
	_renew_box = VBoxContainer.new()
	_renew_box.add_theme_constant_override("separation", 8)
	content.add_child(_renew_box)
	_renew_turns = _amount_box(DEFAULT_TURNS, Diplomacy.AGREEMENT_MIN_TURNS, Diplomacy.AGREEMENT_MAX_TURNS)
	_renew_box.add_child(_row([_label("Gia hạn thêm", 15, false), _renew_turns, _label("lượt, giữ nguyên điều khoản", 15, false)]))
	_renew_preview = _label("", 15)
	_renew_box.add_child(_renew_preview)


func _build_actions() -> void:
	_fair_button = add_action("Đòi đúng giá công bằng", _on_fair_pressed)
	_offer_button = add_action("Đề nghị ký", _on_offer_pressed)
	_renew_button = add_action("Gia hạn", _on_renew_pressed)
	_cancel_button = add_action("Hủy hợp đồng", _on_cancel_pressed, true)


func _refresh() -> void:
	var diplomacy := state.diplomacy
	var agreement := diplomacy.get_agreement(clan_id)
	_offer_box.visible = agreement == null
	_contract_label.visible = agreement != null
	_fair_button.visible = agreement == null
	_offer_button.visible = agreement == null
	_cancel_button.visible = agreement != null
	var renewable := agreement != null and agreement.turns_left <= Diplomacy.AGREEMENT_RENEW_TURNS
	_renew_box.visible = renewable
	_renew_button.visible = renewable
	if agreement != null:
		_contract_label.text = "Đang có hợp đồng: mỗi lượt đưa %d %s, nhận %d %s. Còn %d/%d lượt." % [
				agreement.give_amount, _resource_name(agreement.give_id), agreement.get_amount,
				_resource_name(agreement.get_id), agreement.turns_left, agreement.total_turns]
		if not renewable:
			_contract_label.text += "
Còn %d lượt trở xuống thì có thể gia hạn." % Diplomacy.AGREEMENT_RENEW_TURNS
			return
		var renewal := diplomacy.check_renewal(clan_id, int(_renew_turns.value))
		var renew_chance := diplomacy.renewal_chance(clan_id)
		_renew_button.disabled = renewal != Diplomacy.ProposalResult.OK or renew_chance <= 0.0
		if renewal != Diplomacy.ProposalResult.OK:
			set_preview(_renew_preview, Diplomacy.describe_proposal(renewal), false)
		else:
			set_preview(_renew_preview, "Khả năng đồng ý gia hạn: %s (%d%%)." % [Diplomacy.chance_name(renew_chance),
					roundi(renew_chance * 100)], renew_chance > 0.0)
		return
	var give_id := _selected_resource(_give_option)
	var get_id := _selected_resource(_get_option)
	var give_amount := int(_give_amount.value)
	var get_amount := int(_get_amount.value)
	var result := diplomacy.check_proposal(clan_id, give_id, give_amount, get_id, get_amount, int(_turns.value))
	if result != Diplomacy.ProposalResult.OK:
		_offer_button.disabled = true
		set_preview(_preview, Diplomacy.describe_proposal(result), false)
		return
	var fair := diplomacy.trade_quote(clan_id, give_id, give_amount, get_id)
	var chance := diplomacy.agreement_chance(clan_id, give_id, give_amount, get_id, get_amount)
	# A 0% offer can only be refused and would waste this turn's proposal.
	_offer_button.disabled = chance <= 0.0
	set_preview(_preview, "Họ thấy công bằng: khoảng %d %s mỗi lượt.\nKhả năng đồng ý: %s (%d%%)." % [
			fair, _resource_name(get_id), Diplomacy.chance_name(chance), roundi(chance * 100)], chance > 0.0)


## Fills the "receive" amount with what the clan considers fair for the current offer.
func _on_fair_pressed() -> void:
	var fair := state.diplomacy.trade_quote(clan_id, _selected_resource(_give_option), int(_give_amount.value),
			_selected_resource(_get_option))
	_get_amount.value = maxi(fair, 1)


func _on_offer_pressed() -> void:
	var result := state.diplomacy.propose(state.rng, clan_id, _selected_resource(_give_option),
			int(_give_amount.value), _selected_resource(_get_option), int(_get_amount.value), int(_turns.value))
	var ok := result == Diplomacy.ProposalResult.OK
	set_status(Diplomacy.describe_proposal(result) + (" Quan hệ +%d." % Diplomacy.AGREEMENT_SIGN_GAIN if ok else ""), ok)


func _on_renew_pressed() -> void:
	var turns := int(_renew_turns.value)
	var result := state.diplomacy.renew_agreement(state.rng, clan_id, turns)
	var ok := result == Diplomacy.ProposalResult.OK
	set_status("Họ đồng ý gia hạn thêm %d lượt!" % turns if ok else Diplomacy.describe_proposal(result), ok)


## Breaking an agreement costs a lot of relation: the first click asks for confirmation.
func _on_cancel_pressed() -> void:
	if _cancel_button.text == "Hủy hợp đồng":
		_cancel_button.text = "Chắc chắn hủy? (quan hệ -%d)" % (Diplomacy.AGREEMENT_CANCEL_PENALTY + Diplomacy.AGREEMENT_BASE_BONUS)
		return
	_cancel_button.text = "Hủy hợp đồng"
	state.diplomacy.cancel_agreement(clan_id)
	set_status("Đã hủy hợp đồng. Quan hệ -%d, và mất +%d của hợp đồng." % [Diplomacy.AGREEMENT_CANCEL_PENALTY,
			Diplomacy.AGREEMENT_BASE_BONUS], false)
