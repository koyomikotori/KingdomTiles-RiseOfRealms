class_name GovernorDialog
extends ModalWindow
## Appoints a governor (thái thú) to a captured town (GDD §33, M18f-a): any ready general or
## advisor; what their stats would give is shown on each row.

signal done

var _state: KingdomState
var _town: Realm.Town


func open(state: KingdomState, town: Realm.Town) -> void:
	_state = state
	_town = town
	var body := build_frame("Bổ nhiệm thái thú %s" % town.name, UiPalette.ACCENT, 0.5)
	body.add_child(_label("Thái thú ở lại trấn, không ra trận và không giữ chức ở nhà. Tướng dùng Thống suất (sản lượng) và Võ lực (dân binh); mưu sĩ dùng Nội chính và Mưu lược.", 14))
	var officers: Array[Officer] = []
	officers.append_array(state.generals.generals)
	officers.append_array(state.advisors.advisors)
	var any := false
	for officer in officers:
		if not officer.is_ready():
			continue
		any = true
		var economy := Realm.economy_score(officer)
		var defense := Realm.defense_score(officer)
		var role := "Tướng" if officer is General else "Mưu sĩ"
		var info := _label("%s %s %s\nSản lượng trấn +%d%% · Dân binh +%d lính" % [role, officer.name,
				officer.star_text(), roundi(economy * Realm.GOVERNOR_YIELD * 100.0), defense * Realm.MILITIA_PER_POINT], 14)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_color_override("font_color", officer.name_color())
		var button := _button("Bổ nhiệm", _appoint.bind(officer))
		button.custom_minimum_size.x = 120
		body.add_child(_row([info, button]))
	if not any:
		body.add_child(_label("Không có ai rảnh: mọi tướng sĩ đang bận hoặc bị thương.", 14))


func _appoint(officer: Officer) -> void:
	var result := _state.realm.assign_governor(_state, officer, _town.id)
	if result != Realm.Result.OK:
		set_status(Realm.describe(result), false)
		return
	done.emit()
	close()
