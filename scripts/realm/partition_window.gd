class_name PartitionWindow
extends ModalWindow
## The big announcement that opens the realm phase: "Phân Chia Thiên Hạ" (GDD §33, M18f-a). Tells
## who joined, introduces the five nations (near ones weaker, far ones stronger) and the rules,
## then leads to the realm map (`proceed`). Not closable with Esc.

signal proceed

const TITLE_COLOR := Color(0.62, 0.42, 0.08)
const DISTANCE_NAMES: Array[String] = ["", "Láng giềng — yếu nhất", "Xa hơn — mạnh hơn", "Tận cùng — mạnh nhất"]


## `joined`: names of the allied clans that asked to join.
func open(state: KingdomState, joined: Array[String]) -> void:
	Sfx.sting(&"victory")
	var body := build_frame("Thông cáo thiên hạ", TITLE_COLOR, 0.64, false)
	var heading := _label("⚔  PHÂN CHIA THIÊN HẠ  ⚔", 34, false)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", UiPalette.WARNING)
	body.add_child(heading)
	var banner := _label("Ba mươi lăm gia tộc đã về một mối dưới cờ %s. Nhưng ngoài kia, năm quốc gia lớn đang chia nhau thiên hạ — và họ không coi ta ra gì." % state.kingdom_name, 16)
	body.add_child(banner)
	if not joined.is_empty():
		var line := _label("Các đồng minh xin quy phục: %s." % ", ".join(joined), 15)
		line.add_theme_color_override("font_color", GOOD_COLOR)
		body.add_child(line)
	body.add_child(HSeparator.new())
	var nations: Array = state.realm.nations.values()
	nations.sort_custom(func(a: Realm.Nation, b: Realm.Nation) -> bool: return a.distance() < b.distance())
	for nation: Realm.Nation in nations:
		var data := RealmMap.nation_data(nation.id)
		var swatch := ColorRect.new()
		swatch.color = nation.color
		swatch.custom_minimum_size = Vector2(22, 22)
		var name_label := _label(nation.name, 16, false)
		name_label.add_theme_color_override("font_color", UiPalette.ink(nation.color))
		var info := _label("%s · Kinh đô %s · %s" % [data.trait, data.capital, DISTANCE_NAMES[nation.distance()]], 14, false)
		info.add_theme_color_override("font_color", MUTED_COLOR)
		body.add_child(_row([swatch, name_label, info]))
	body.add_child(HSeparator.new())
	for line in [
			"Ta và năm nước, mỗi bên 5 trấn: 30 trấn nối nhau bằng đường.",
			"Lập đạo quân ở kinh đô: mỗi đạo một tướng, tối đa %d đơn vị. Lính không theo đạo nào ở lại giữ nhà." % Realm.MAX_ARMY_SQUADS,
			"Mỗi lượt một đạo quân đi một chặng đường; tiến vào trấn địch là công thành.",
			"Mỗi trấn của ta thêm %d chỗ cho quân. Trấn chiếm được còn nộp tài nguyên và tăng tốc bổ sung lính; cử thái thú để trấn nộp đủ." % Realm.TOWN_SQUADS,
			"Nước mất trấn sẽ tìm cách đánh chiếm lại. Chiếm kinh đô thì nước ấy bị diệt.",
			"Số tướng tối đa tăng lên %d. Đạo tặc thôi nổi loạn, nhưng cướp phá vẫn có." % Realm.MAX_GENERALS]:
		body.add_child(_label("• " + line, 14))
	add_action("Mở bản đồ thiên hạ", func() -> void:
		proceed.emit()
		close())
