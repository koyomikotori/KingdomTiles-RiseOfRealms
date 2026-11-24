class_name CrownDialog
extends ModalWindow
## "Phong vương lập chư hầu" (GDD §36, M18f-b2a): pick a general at home (not the Tổng tướng) to
## crown king of a destroyed nation's land. Shows what that king brings (guard in every town,
## revolt cut, tribute, the stars of the vassal's generals), then asks again: the general leaves
## for good (their items come back to the storage).

signal done

const WIDTH := 0.56
const PORTRAIT := 0.5

var _state: KingdomState
var _nation: Realm.Nation
var _general: General
var _cards: Dictionary = {}  # Button -> General
var _preview: RequirementView


func open(state: KingdomState, nation: Realm.Nation) -> void:
	_state = state
	_nation = nation
	var body := build_frame("Phong vương đất %s" % nation.name, UiPalette.GOLD, WIDTH)
	body.add_child(_label(("Chọn một tướng ở nhà để phong làm vua chư hầu cai quản đất %s. Các trấn vẫn là của ta; "
			+ "chư hầu giữ thành, tự lập đạo quân, đánh các trấn địch giáp ranh và cống nạp mỗi lượt.") % nation.name, 14))
	var cards := HFlowContainer.new()
	cards.add_theme_constant_override("h_separation", 8)
	cards.add_theme_constant_override("v_separation", 6)
	body.add_child(cards)
	for general in state.generals.generals:
		cards.add_child(_card(general))
	if state.generals.generals.is_empty():
		body.add_child(_label("Chưa có tướng nào.", 14))
	body.add_child(_label("Võ lực, Thống suất tính không kèm trang bị (trang bị được thu về kho).", 13))
	body.add_child(HSeparator.new())
	_preview = RequirementView.new()
	body.add_child(_preview)
	add_action("Phong vương", _ask, true)
	_refresh()


func _reason(general: General) -> String:
	if general == _state.generals.commander:
		return "♛ Tổng tướng"
	if not general.is_ready():
		return general.away_text() if general.away else "Bị thương, còn %d lượt" % general.wounded_turns
	return ""


func _card(general: General) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(250, 48 * PORTRAIT * 2 + 12)
	var reason := _reason(general)
	card.disabled = reason != ""
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.offset_right = -6
	var portrait := PortraitView.new()
	portrait.setup(general, PORTRAIT, _state.player_color)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(portrait)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(_on_wood("%s %s" % [general.name, general.star_text()], 14, UiPalette.ON_WOOD))
	info.add_child(_on_wood("Võ %d · Thống %d" % [general.might, general.command], 12,
			UiPalette.ON_WOOD_MUTED))
	if reason != "":
		info.add_child(_on_wood(reason, 12, UiPalette.WARNING_ON_WOOD))
	row.add_child(info)
	card.add_child(row)
	card.pressed.connect(_pick.bind(general, card))
	_cards[card] = general
	return card


func _pick(general: General, pressed: Button) -> void:
	_general = general
	for card: Button in _cards:
		card.set_pressed_no_signal(card == pressed)
	_refresh()


func _refresh() -> void:
	_preview.clear()
	if _general == null:
		_preview.note("Chọn một tướng để xem chư hầu mạnh yếu ra sao (theo sao, Võ lực, Thống suất của tướng).")
		return
	_preview.header("Vua chư hầu %s %s" % [_general.name, _general.star_text()])
	_preview.line(&"achievement_military", "Quân chư hầu giữ mỗi trấn của vùng: %d lính (40 + 5 × Võ lực %d)" % [
			Realm.guard_for(_general), _general.might])
	var cut := Realm.VASSAL_COMMAND_CUT * _general.command
	var low := maxf(0.0, Realm.REVOLT_PACIFIED - Realm.PACIFY_STEP * Realm.PACIFY_TURNS - cut)
	_preview.line(&"scroll", "Nổi loạn: 2%% giảm 0,2%%/lượt trong %d lượt, rồi − %s%% (Thống suất %d) → %s%%/lượt" % [
			Realm.PACIFY_TURNS, _percent(cut), _general.command, _percent(low)])
	_preview.amounts("Cống nạp mỗi lượt", Realm.tribute_of(_general))
	_preview.line(&"achievement_conquest", "Đạo quân chư hầu: %d lính, tướng %d★; ngân khố cố định như AI Trung bình" % [
			RealmVassals.ARMY_SIZE, clampi(_general.stars - RealmVassals.STARS_BELOW_KING, 1, RealmWar.MAX_STARS)])
	_preview.note("⚠ Tướng sẽ rời khỏi ta vĩnh viễn; trang bị của tướng được thu về kho.")


static func _percent(value: float) -> String:
	return ("%.2f" % (value * 100.0)).trim_suffix("0").trim_suffix("0").trim_suffix(".").replace(".", ",")


func _ask() -> void:
	var result := _state.realm.check_crown(_state, _nation.id, _general)
	if result != Realm.Result.OK:
		set_status(Realm.describe(result), false)
		return
	var general := _general
	ConfirmWindow.ask(self, "Phong vương", "Phong %s làm vua chư hầu đất %s? Tướng sẽ rời khỏi ta vĩnh viễn." % [
			general.name, _nation.name], Callable(), "Phong vương", _crown.bind(general), true)


func _crown(general: General) -> void:
	var result := _state.realm.crown(_state, _nation.id, general)
	if result != Realm.Result.OK:
		set_status(Realm.describe(result), false)
		return
	Sfx.play(&"recruit")
	done.emit()
	close()


func _on_wood(text: String, font_size: int, color: Color) -> Label:
	var label := _label(text, font_size, false)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
