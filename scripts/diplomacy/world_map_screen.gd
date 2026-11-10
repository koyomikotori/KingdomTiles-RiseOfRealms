class_name WorldMapScreen
extends Control
## Full-screen world map (GDD §9.1): the map on the left (70%), the selected clan's summary and
## action buttons on the right (30%); actions open their dialog over this screen. Emits `closed`
## when the player goes back. Built in code.

signal closed
## Forwarded from the clan panel; the kingdom scene closes the map and runs the battle.
signal attack_requested(clan_id: StringName)
## A clan was picked on the map (the tutorial waits for it, M18a).
signal clan_shown(clan_id: StringName)

const BACKGROUND_COLOR := UiPalette.BACKDROP

var _map: WorldMapView
var _panel: ClanPanel


## With `agent`, the map opens to send that agent (GDD §8 M14e): picking a clan opens the agent dialog.
func open(state: KingdomState, resource_types: Array[ResourceTypeData], agent: Agent = null) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = BACKGROUND_COLOR
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layout)

	var top := HBoxContainer.new()
	var title := Label.new()
	title.text = "Bản đồ thế giới — Ngoại giao (lượt %d)" % state.turn
	if agent != null:
		title.text = "Chọn gia tộc để cử đặc vụ %s" % agent.name
	title.add_theme_font_size_override("font_size", 20)
	title.theme_type_variation = &"WoodLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var back := Button.new()
	back.text = Touch.keys("Quay lại (Esc)")
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(0, 40)
	back.pressed.connect(close)
	top.add_child(back)
	layout.add_child(_margin(top))

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(row)
	_map = WorldMapView.new()
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.size_flags_stretch_ratio = 7.0
	_map.kingdom_name = state.kingdom_name
	_map.kingdom_color = state.player_color
	_map.setup(state.diplomacy)
	row.add_child(_map)
	# The clan panel sits on paper (project theme, GDD §13).
	var paper := PanelContainer.new()
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paper.size_flags_stretch_ratio = 3.0
	row.add_child(paper)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	paper.add_child(scroll)
	_panel = ClanPanel.new()
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.dialog_host = self
	_panel.setup(state, resource_types)
	var panel_margin := _margin(_panel)
	panel_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel_margin)
	_map.clan_selected.connect(_panel.show_clan)
	_map.clan_selected.connect(func(clan_id: StringName) -> void: clan_shown.emit(clan_id))
	if agent != null:
		_panel.preferred_agent = agent
		_map.clan_selected.connect(func(clan_id: StringName) -> void:
			if not state.wars.fronts[clan_id].annexed and not agent.is_busy() and state.agents.agent_on(clan_id) == null:
				_panel.open_dialog(AgentDialog.new()))
	_panel.attack_requested.connect(func(clan_id: StringName) -> void: attack_requested.emit(clan_id))
	_map.setup_wars(state.wars)


## Opens with this clan already selected (used by tests and previews).
func select_clan(clan_id: StringName) -> void:
	_map.select(clan_id)
	_panel.show_clan(clan_id)


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
	# The kingdom underneath must not react to keys while the map is open.
	get_viewport().set_input_as_handled()


func _margin(child: Control) -> MarginContainer:
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 10)
	margin.add_child(child)
	return margin
