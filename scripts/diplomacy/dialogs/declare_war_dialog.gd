class_name DeclareWarDialog
extends DiplomacyDialog
## Declaring war (GDD §9.6, §9.7): every consequence listed before the player confirms.

var _consequences: Label
var _preview: Label
var _declare_button: Button


func _title() -> String:
	return "Tuyên chiến với %s" % clan_data().display_name


func _build(content: VBoxContainer) -> void:
	_consequences = _label("", 14)
	content.add_child(_consequences)
	_preview = _label("", 15)
	content.add_child(_preview)


func _build_actions() -> void:
	_declare_button = add_action("Tuyên chiến!", _on_declare_pressed, true)


func _refresh() -> void:
	var result := state.wars.check_declare(clan_id)
	_declare_button.disabled = result != Wars.DeclareResult.OK
	_consequences.visible = result == Wars.DeclareResult.OK
	if result != Wars.DeclareResult.OK:
		set_preview(_preview, Wars.describe_declare(result), false)
		return
	set_preview(_preview, "Không thể rút lại. Hòa lại phải qua nghị hòa.", false)
	var clan := state.diplomacy.clans[clan_id]
	var lines: Array[String] = ["Hậu quả:",
			"  • Quan hệ với %s xuống Thù địch (tối đa %d)." % [clan.data.display_name, Wars.DECLARE_RELATION]]
	if clan.agreement != null:
		lines.append("  • Hợp đồng giao thương với họ bị hủy (mất +%d)." % Diplomacy.AGREEMENT_BASE_BONUS)
	if clan.has_pact():
		lines.append("  • Phá hiệp định bất tương xâm (mất +%d; mọi gia tộc khác mất thêm %d)." % [Diplomacy.PACT_BASE_BONUS,
				absi(Wars.BREAK_PACT_PENALTY)])
	if clan.is_allied():
		lines.append("  • Phản bội liên minh (mất +%d)." % Diplomacy.ALLIANCE_BASE_BONUS)
	# 23 clans are too many to list: the friends by name, everyone else in one line.
	lines.append("  • Các gia tộc khác:")
	var others_penalty := 0
	for other in state.diplomacy.clans:
		if other == clan_id or state.diplomacy.clans[other].annexed:
			continue
		if clan.data.friends.has(other):
			lines.append("      %s (bạn của họ): quan hệ %d" % [_clan_name(other), state.wars.declare_penalty(clan_id, other)])
		else:
			others_penalty = state.wars.declare_penalty(clan_id, other)
	if others_penalty != 0:
		lines.append("      Mọi gia tộc còn lại: quan hệ %d" % others_penalty)
	lines.append("  • Họ có thể kéo quân xâm lược bạn; bạn có thể đem quân tấn công họ mỗi lượt một lần.")
	_consequences.text = "\n".join(lines)


func _on_declare_pressed() -> void:
	var result := state.wars.declare_war(clan_id)
	set_status(Wars.describe_declare(result), false)
