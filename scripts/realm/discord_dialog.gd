class_name DiscordDialog
extends ModalWindow
## "Ly gián" (GDD §38, M18f-b2c): the Ngoại giao post holder goes to set `nation` against a second
## nation picked here. The chance shows before sending; success sours their relation (−50 at once,
## −5 a turn for 5 turns), exposure costs −30 with both. Once every 5 turns.

signal done(text: String, good: bool)

const WIDTH := 0.5

var _state: KingdomState
var _nation: Realm.Nation
var _other: StringName = &""
var _buttons: Dictionary = {}  # Button -> StringName
var _preview: RequirementView


func open(state: KingdomState, nation: Realm.Nation) -> void:
	_state = state
	_nation = nation
	var realm := state.realm
	var dip := realm.diplomacy
	var body := build_frame("Ly gián %s" % nation.name, UiPalette.ACCENT, WIDTH)
	var diplomat := state.advisors.active(&"diplomacy")
	body.add_child(_label("Mưu sĩ Ngoại giao %s đi gieo nghi kỵ giữa %s và một nước khác (vắng mặt tới hết lượt)." % [
			diplomat.name if diplomat != null else "(chưa có)", nation.name], 14))
	body.add_child(_label("Chọn nước thứ hai:", 14))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	body.add_child(row)
	for other in RealmWar.live_nations(realm):
		if other == nation:
			continue
		var button := Button.new()
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(150, 40)
		button.text = "%s (%+d)" % [other.name, dip.relation(nation.id, other.id)]
		button.tooltip_text = "Quan hệ giữa %s và %s: %s" % [nation.name, other.name,
				RealmDiplomacy.tier_name(dip.relation(nation.id, other.id))]
		button.pressed.connect(_pick.bind(other.id, button))
		_buttons[button] = other.id
		row.add_child(button)
	body.add_child(HSeparator.new())
	_preview = RequirementView.new()
	body.add_child(_preview)
	add_action("Gửi mưu sĩ", _send)
	for button: Button in _buttons:
		_pick(_buttons[button], button)
		break
	_refresh()


func _pick(other: StringName, pressed: Button) -> void:
	_other = other
	for button: Button in _buttons:
		button.set_pressed_no_signal(button == pressed)
	_refresh()


func _check() -> RealmDiplomacy.Result:
	return _state.realm.diplomacy.check_discord(_state.realm, _state, _nation.id, _other)


func _refresh() -> void:
	_preview.clear()
	_preview.line(&"time", "Khả năng thành: %d%%" % roundi(RealmDiplomacy.discord_chance(_state) * 100.0))
	_preview.line(&"check", "Thành: quan hệ giữa hai nước %d ngay, thêm %d mỗi lượt trong %d lượt (có thể làm khối rã, họ đánh nhau)." % [
			roundi(RealmDiplomacy.DISCORD_HIT), roundi(RealmDiplomacy.DISCORD_PER_TURN), RealmDiplomacy.DISCORD_TURNS])
	_preview.line(&"cross", "Lộ: cả hai nước %d quan hệ với ta." % roundi(RealmDiplomacy.DISCORD_EXPOSED), UiPalette.WARNING)
	_preview.note("Mưu sĩ Ngoại giao chỉ đi ly gián được 1 lần mỗi %d lượt." % RealmDiplomacy.DISCORD_COOLDOWN)
	var result := _check()
	set_status(RealmDiplomacy.describe(result) if result != RealmDiplomacy.Result.OK else "", result == RealmDiplomacy.Result.OK)


func _send() -> void:
	var realm := _state.realm
	var outcome := realm.diplomacy.sow_discord(realm, _state, _nation.id, _other)
	if outcome.result != RealmDiplomacy.Result.OK:
		set_status(RealmDiplomacy.describe(outcome.result), false)
		return
	var other_name := RealmDiplomacy.name_of(realm, _other)
	var text := "Ly gián thành công: %s và %s bắt đầu nghi kỵ nhau." % [_nation.name, other_name] if outcome.success \
			else "Ly gián bị lộ! %s và %s đều phật ý với ta." % [_nation.name, other_name]
	Sfx.play(&"click" if outcome.success else &"error")
	done.emit(text, outcome.success)
	close()
