class_name EventWindow
extends ModalWindow
## Shows the oldest pending event (GDD §9c): the counselor telling it (Counsel.event_lines, M16i-b;
## the event's own text when it has no lines), the stockpile, and its choices with their
## cost and a hint. The result gets one line of the counselor by its tone (EventSystem.tone). After a choice the window shows what actually happened. It cannot be closed
## without answering. An answer that leads to a battle (M16e) closes with "Vào trận"; the kingdom
## scene then plays EventSystem.pending_battle.

const ACCENT := Color(0.42, 0.2, 0.55)
const CATEGORY_COLORS: Array[Color] = [Color(0.62, 0.42, 0.08), Color(0.18, 0.4, 0.65), Color(0.69, 0.2, 0.12),
		Color(0.2, 0.5, 0.22)]

var _state: KingdomState
var _rng: RandomNumberGenerator
var _resource_types: Array[ResourceTypeData] = ResourceTypeData.load_all()
var _body: VBoxContainer
## The counselor's telling, picked once so going back from the general picker keeps it.
var _narration: Array[Dictionary] = []


func open(state: KingdomState, rng: RandomNumberGenerator) -> void:
	_state = state
	_rng = rng
	var event := state.events.current_event()
	var clan_id := state.events.current_clan()
	_body = build_frame(state.events.fill(state, event.title, clan_id), ACCENT, 0.45, false)
	_narration = Counsel.event_lines(event.event_id, state.counselor, _context(clan_id))
	open_body()


## The event's story and its choices.
func open_body() -> void:
	var state := _state
	var event := state.events.current_event()
	var clan_id := state.events.current_clan()
	var category := _label("Sự kiện · %s" % EventData.CATEGORY_NAMES[event.category], 13)
	category.add_theme_color_override("font_color", CATEGORY_COLORS[event.category])
	_body.add_child(category)
	if _narration.is_empty():
		_body.add_child(_label(state.events.fill(state, event.text, clan_id), 16))
	else:
		_body.add_child(_counsel_box(_narration))
	var stock := _label("Kho hiện có: " + _stock_text(), 13)
	stock.add_theme_color_override("font_color", MUTED_COLOR)
	_body.add_child(stock)
	_body.add_child(HSeparator.new())
	for i in event.choices.size():
		_body.add_child(_choice_row(event.choices[i], i))


func _choice_row(choice: EventChoiceData, index: int) -> Control:
	var clan_id := _state.events.current_clan()
	var blocked := _state.events.block_reason(_state, choice, clan_id)
	var text := choice.text
	if not choice.cost.is_empty():
		text += " (−%s)" % UiFormat.amounts(choice.cost, _resource_types)
	var button := _button(text, _on_choice_pressed.bind(index))
	button.disabled = not blocked.is_empty()
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var column := VBoxContainer.new()
	column.add_child(button)
	var hint_text := _state.events.fill(_state, choice.hint, clan_id)
	var chance := _state.events.choice_chance(_state, choice, clan_id)
	if chance >= 0.0:
		hint_text += " Khả năng thành công: %d%%." % roundi(chance * 100)
	var hint := _label(blocked if not blocked.is_empty() else hint_text.strip_edges(), 13)
	hint.add_theme_color_override("font_color", WARNING_COLOR if not blocked.is_empty() else MUTED_COLOR)
	column.add_child(hint)
	return column


func _on_choice_pressed(index: int) -> void:
	var choice: EventChoiceData = _state.events.current_event().choices[index]
	if choice.pick_general:
		_show_general_picker(index)
		return
	_answer(index, null)


## A pick_general choice (M16e): one row per general ready to fight, then "Quay lại".
func _show_general_picker(index: int) -> void:
	_clear_body()
	_body.add_child(_label("Cử tướng nào ra đấu? Người thua sẽ tử trận.", 16))
	var rival := _state.clan_officers.staff(ClanOfficers.BANDITS).general
	if _state.events.current_event().needs_bandit_leader and rival != null:
		var against := _label("Đối thủ: thủ lĩnh %s %s · Võ lực %d · Thống suất %d" % [rival.name, rival.star_text(),
				rival.total_might(), rival.total_command()], 14)
		against.add_theme_color_override("font_color", WARNING_COLOR)
		_body.add_child(against)
	for general in EventSystem.ready_generals(_state):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var portrait := PortraitView.new()
		portrait.setup(general, 0.5)
		row.add_child(portrait)
		var button := _button("%s %s · Võ lực %d · Thống suất %d" % [general.name, general.star_text(),
				general.total_might(), general.total_command()], _answer.bind(index, general))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(button)
		_body.add_child(row)
	_body.add_child(_button("Quay lại", func() -> void:
		_clear_body()
		open_body()))


func _answer(index: int, general: General) -> void:
	var clan_id := _state.events.current_clan()
	var officer_name := _state.events.current_officer_name()
	var result := _state.events.resolve(_state, _rng, index, general)
	if result.is_empty():
		return
	_clear_body()
	_body.add_child(_label(result.text, 16))
	if not result.changes.is_empty():
		_body.add_child(_label("\n".join(result.changes.map(func(line: String) -> String: return "• " + line)), 14))
	var tone: StringName = result.get("tone", &"")
	if tone != &"":
		var reaction := Counsel.lines(tone, _state.counselor, _context(clan_id, officer_name))
		if not reaction.is_empty():
			_body.add_child(_counsel_box(reaction))
	add_action("Vào trận" if result.has("battle") else "Bắt đầu" if result.has("request") else "Tiếp tục", close)


func _context(clan_id: StringName, officer_name: String = "") -> Dictionary:
	var clan_name := _state.diplomacy.clans[clan_id].data.display_name if clan_id != &"" else ""
	if officer_name == "":
		officer_name = _state.events.current_officer_name()
	return Counsel.context(_state, {"clan": clan_name, "officer": officer_name})


func _counsel_box(lines: Array[Dictionary]) -> CounselBox:
	var box := CounselBox.new()
	box.setup(lines, get_viewport_rect().size.x * 0.45 - 60.0)
	return box


func _clear_body() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()


func _stock_text() -> String:
	var parts: Array[String] = []
	for type in _resource_types:
		parts.append("%s %d" % [type.display_name, _state.stockpile.get_amount(type.resource_id)])
	return " · ".join(parts)
