class_name TributeDialog
extends DiplomacyDialog
## Demand tribute from a much weaker neighbor (M18c, GDD §9.8): what they would pay, the chance
## they give in, and what it costs in relation either way.

var _preview: Label
var _demand_button: Button


func _title() -> String:
	return "Đòi %s cống nạp" % clan_data().display_name


func _shows_stockpile() -> bool:
	return true


func _build(content: VBoxContainer) -> void:
	var rules := _label(("Chỉ đòi được gia tộc giáp ranh khi quân ta đông gấp %d lần quân họ. Họ nộp một lần "
			+ "bằng hàng họ dư. Nộp thì quan hệ %d và các gia tộc khác %d; từ chối thì quan hệ %d. "
			+ "Đòi xong phải đợi %d lượt mới đòi lại được.") % [roundi(Tribute.MIN_RATIO), Tribute.ACCEPT_RELATION,
			Tribute.OTHERS_RELATION, Tribute.REFUSE_RELATION, Tribute.COOLDOWN_TURNS], 13)
	rules.add_theme_color_override("font_color", MUTED_COLOR)
	content.add_child(rules)
	_preview = _label("", 15)
	content.add_child(_preview)


func _build_actions() -> void:
	_demand_button = add_action("Đòi cống nạp", _on_demand_pressed)


func _refresh() -> void:
	var result := Tribute.check(state, clan_id)
	_demand_button.disabled = result != Tribute.Result.OK
	if result != Tribute.Result.OK:
		set_preview(_preview, Tribute.describe(result), false)
		return
	var chance := Tribute.chance(state, clan_id)
	set_preview(_preview, "Họ sẽ nộp: %s.\nKhả năng chịu nộp: %s (%d%%)." % [
			UiFormat.amounts(Tribute.amounts(state, clan_id), ResourceTypeData.load_all()),
			Diplomacy.chance_name(chance), roundi(chance * 100)], true)


func _on_demand_pressed() -> void:
	var outcome := Tribute.demand(state, clan_id, state.rng)
	if outcome.result != Tribute.Result.OK:
		set_status(Tribute.describe(outcome.result), false)
		return
	if outcome.accepted:
		Sfx.play(&"coins")
		set_status("%s cúi đầu nộp cống: %s. Quan hệ %d." % [clan_data().display_name,
				UiFormat.amounts(outcome.amounts, ResourceTypeData.load_all()), Tribute.ACCEPT_RELATION], true)
	else:
		set_status("%s khước từ. Quan hệ %d." % [clan_data().display_name, Tribute.REFUSE_RELATION], false)
