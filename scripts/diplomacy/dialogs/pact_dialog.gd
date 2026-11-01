class_name PactDialog
extends DiplomacyDialog
## Non-aggression pact (GDD §9.7, back in M16a): what it does and the acceptance chance, then offer it.

var _preview: Label
var _propose_button: Button


func _title() -> String:
	return "Bất tương xâm với %s" % clan_data().display_name


func _build(content: VBoxContainer) -> void:
	var rules := _label(("Trong %d lượt, %s không tuyên chiến với bạn dù quan hệ có xấu đi, quan hệ +%d, và họ không "
			+ "gửi quân giúp bạn của họ khi bạn đánh bạn họ. Nếu bạn tuyên chiến với họ, hiệp định bị phá và mọi gia tộc "
			+ "khác mất thêm %d quan hệ.") % [Alliances.PACT_TURNS, clan_data().display_name, Diplomacy.PACT_BASE_BONUS,
			absi(Wars.BREAK_PACT_PENALTY)], 13)
	rules.add_theme_color_override("font_color", MUTED_COLOR)
	content.add_child(rules)
	_preview = _label("", 15)
	content.add_child(_preview)


func _build_actions() -> void:
	_propose_button = add_action("Đề nghị ký", _on_propose_pressed)


func _refresh() -> void:
	var clan := state.diplomacy.clans[clan_id]
	var result := state.alliances.check_pact(clan_id)
	if clan.has_pact():
		_propose_button.disabled = true
		set_preview(_preview, "Đang có hiệp định, còn %d lượt." % clan.pact_turns, true)
	elif result == Alliances.PactResult.OK:
		var chance := state.alliances.pact_chance(clan_id)
		_propose_button.disabled = chance <= 0.0
		set_preview(_preview, "Bất tương xâm %d lượt. Khả năng đồng ý: %s (%d%%)." % [Alliances.PACT_TURNS,
				Diplomacy.chance_name(chance), roundi(chance * 100)], chance > 0.0)
	else:
		_propose_button.disabled = true
		set_preview(_preview, Alliances.describe_pact(result), false)


func _on_propose_pressed() -> void:
	var result := state.alliances.propose_pact(state.rng, clan_id)
	var signed := result == Alliances.PactResult.OK
	set_status(Alliances.describe_pact(result) + (" Quan hệ +%d." % Diplomacy.PACT_BASE_BONUS if signed else ""), signed)
