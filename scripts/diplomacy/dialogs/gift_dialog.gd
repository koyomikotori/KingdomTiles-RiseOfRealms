class_name GiftDialog
extends DiplomacyDialog
## Gift resources to raise the relation (GDD §9.3), at most +15 per clan per turn.

var _amount: SpinBox
var _option: OptionButton
var _preview: Label
var _gift_button: Button


func _title() -> String:
	return "Tặng quà cho %s" % clan_data().display_name


func _shows_stockpile() -> bool:
	return true


func _build(content: VBoxContainer) -> void:
	var hint := _label(("Mỗi %d giá trị hàng = +1 quan hệ (nhân theo tính cách: %s). Tối đa +%d mỗi lượt. "
			+ "Tặng thứ họ thiếu hoặc đang cần gấp thì quý hơn; tặng liên tục thì họ quen dần, quà kém tác dụng.") % [
			Diplomacy.GIFT_VALUE_PER_POINT, ClanData.PERSONALITY_NAMES[clan_data().personality].to_lower(),
			Diplomacy.MAX_GIFT_GAIN_PER_TURN], 13)
	hint.add_theme_color_override("font_color", MUTED_COLOR)
	content.add_child(hint)
	_amount = _amount_box()
	_option = _resource_option(0)
	content.add_child(_row([_label("Tặng", 15, false), _amount, _option]))
	_preview = _label("", 15)
	content.add_child(_preview)


func _build_actions() -> void:
	_gift_button = add_action("Tặng", _on_gift_pressed)


func _gift() -> Dictionary[StringName, int]:
	var gift: Dictionary[StringName, int] = {_selected_resource(_option): int(_amount.value)}
	return gift


func _refresh() -> void:
	var result := state.diplomacy.check_gift(state.stockpile, clan_id, _gift())
	_gift_button.disabled = result != Diplomacy.GiftResult.OK
	if result == Diplomacy.GiftResult.OK:
		var tired := "\nHọ có vẻ đã quen nhận quà của ta." if state.diplomacy.gift_appeal(clan_id) < 0.75 else ""
		set_preview(_preview, "Quan hệ +%d (mờ dần theo thời gian).%s" % [state.diplomacy.gift_gain(clan_id, _gift()),
				tired], true)
	else:
		set_preview(_preview, Diplomacy.describe_gift(result), false)


func _on_gift_pressed() -> void:
	var gain := state.diplomacy.gift_gain(clan_id, _gift())
	var result := state.diplomacy.give_gift(state.stockpile, clan_id, _gift())
	var ok := result == Diplomacy.GiftResult.OK
	if ok:
		Sfx.play(&"coins")
	set_status(Diplomacy.describe_gift(result) + (" Quan hệ +%d." % gain if ok else ""), ok)
