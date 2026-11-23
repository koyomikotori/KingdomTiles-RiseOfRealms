class_name ArmyDetailWindow
extends ModalWindow
## "Chi tiết đạo quân" (GDD §34, M18g): the general and every squad of a realm army with its
## soldiers out of a full squad, how many it regains a turn where the army stands
## (Realm.replenish_at) and how many turns until it is full. Read-only.

const WIDTH := 0.46
const ICON_SIZE := 34


func open(state: KingdomState, force: Realm.Force) -> void:
	var general := force.general
	var body := build_frame("Đạo quân %s" % general.name, UiPalette.ACCENT, WIDTH)
	var portrait := PortraitView.new()
	portrait.setup(general, 0.75, state.player_color)
	var info := VBoxContainer.new()
	info.add_child(_label("Tướng %s %s" % [general.name, general.star_text()], 17))
	info.add_child(_label("Võ lực %d · Thống suất %d" % [general.total_might(), general.total_command()], 14))
	var town := state.realm.towns[force.town]
	var per_turn := state.realm.replenish_at(force.town)
	info.add_child(_label("Đang ở %s · %d/%d đơn vị · %d lính" % [town.name, force.squads.size(),
			Realm.MAX_ARMY_SQUADS, force.soldiers()], 14))
	var gain := _label(("Hồi quân: +%d lính mỗi đơn vị mỗi lượt%s." % [per_turn,
			" (kinh đô)" if town.is_capital() else ""]) if per_turn > 0 else "Không hồi quân trên đất địch.", 14)
	gain.add_theme_color_override("font_color", UiPalette.GOOD if per_turn > 0 else UiPalette.WARNING)
	info.add_child(gain)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_row([portrait, info]))
	body.add_child(HSeparator.new())
	for squad in force.squads:
		body.add_child(_squad_row(state, squad, per_turn))
	if per_turn < Realm.CAPITAL_REPLENISH:
		var hint := _label("Đứng ở kinh đô (của ta hoặc kinh đô địch đã chiếm) hồi +%d mỗi lượt." % Realm.CAPITAL_REPLENISH, 13)
		hint.add_theme_color_override("font_color", UiPalette.MUTED)
		body.add_child(hint)


func _squad_row(state: KingdomState, squad: Army.Squad, per_turn: int) -> HBoxContainer:
	var unit: UnitData = state.units[squad.unit_id]
	var full := unit.squad_size
	var name_label := _label("%s · cấp %d" % [unit.display_name, squad.level()], 14, false)
	name_label.add_theme_color_override("font_color", unit.tier_color(false))
	name_label.custom_minimum_size.x = 170
	var bar := ProgressBar.new()
	bar.max_value = full
	bar.value = squad.soldiers
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(110, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var count := _label("%d/%d" % [squad.soldiers, full], 14, false)
	count.custom_minimum_size.x = 56
	var missing := full - squad.soldiers
	var text := "Đủ quân"
	var color := UiPalette.GOOD
	if missing > 0 and per_turn > 0:
		text = "+%d/lượt · đầy sau %d lượt" % [per_turn, ceili(float(missing) / per_turn)]
		color = UiPalette.TEXT
	elif missing > 0:
		text = "Chưa hồi được"
		color = UiPalette.WARNING
	var status := _label(text, 13, false)
	status.add_theme_color_override("font_color", color)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return _row([unit_icon(unit, ICON_SIZE), name_label, bar, count, status])


## The unit's standing sprite as an icon `size` pixels wide.
static func unit_icon(unit: UnitData, size: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(size, size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sheet := GameArt.unit_sheet(unit.get_sprite_id())
	if sheet != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = GameArt.unit_frame(sheet, &"stand", 0)
		icon.texture = atlas
	return icon
