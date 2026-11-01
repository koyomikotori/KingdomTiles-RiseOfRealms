class_name EventWindow
extends ModalWindow
## Shows the oldest pending event (GDD §9c): its story, the stockpile, and its choices with their
## cost and a hint. After a choice the window shows what actually happened. It cannot be closed
## without answering.

const ACCENT := Color(0.42, 0.2, 0.55)
const CATEGORY_COLORS: Array[Color] = [Color(0.62, 0.42, 0.08), Color(0.18, 0.4, 0.65), Color(0.69, 0.2, 0.12),
		Color(0.2, 0.5, 0.22)]

var _state: KingdomState
var _rng: RandomNumberGenerator
var _resource_types: Array[ResourceTypeData] = ResourceTypeData.load_all()
var _body: VBoxContainer


func open(state: KingdomState, rng: RandomNumberGenerator) -> void:
	_state = state
	_rng = rng
	var event := state.events.current_event()
	var clan_id := state.events.current_clan()
	_body = build_frame(state.events.fill(state, event.title, clan_id), ACCENT, 0.45, false)
	var category := _label("Sự kiện · %s" % EventData.CATEGORY_NAMES[event.category], 13)
	category.add_theme_color_override("font_color", CATEGORY_COLORS[event.category])
	_body.add_child(category)
	_body.add_child(_label(state.events.fill(state, event.text, clan_id), 16))
	var stock := _label("Kho của bạn: " + _stock_text(), 13)
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
	var hint_text := choice.hint
	var chance := _state.events.choice_chance(_state, choice, clan_id)
	if chance >= 0.0:
		hint_text += " Khả năng thành công: %d%%." % roundi(chance * 100)
	var hint := _label(blocked if not blocked.is_empty() else hint_text.strip_edges(), 13)
	hint.add_theme_color_override("font_color", WARNING_COLOR if not blocked.is_empty() else MUTED_COLOR)
	column.add_child(hint)
	return column


func _on_choice_pressed(index: int) -> void:
	var result := _state.events.resolve(_state, _rng, index)
	if result.is_empty():
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_body.add_child(_label(result.text, 16))
	if not result.changes.is_empty():
		_body.add_child(_label("\n".join(result.changes.map(func(line: String) -> String: return "• " + line)), 14))
	add_action("Tiếp tục", close)


func _stock_text() -> String:
	var parts: Array[String] = []
	for type in _resource_types:
		parts.append("%s %d" % [type.display_name, _state.stockpile.get_amount(type.resource_id)])
	return " · ".join(parts)
