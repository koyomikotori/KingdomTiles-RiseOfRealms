class_name BlackMarketWindow
extends ModalWindow
## The black market's visit (GDD §20, M16d): on the left the merchant's portrait and greeting,
## "Làm mới" with its cost, the storage count and the "Hành trang" button; on the right a
## fixed-size page, either the six offers in a 3 × 2 grid of same-sized cards (item icon or scroll,
## name in its rarity color, what it does, price chips, "Mua"), or the inventory (stored items, then
## items officers wear with their face) with "Bán" for BlackMarket.sell_value. Closing the window sends the merchant away
## (BlackMarket.leave).

const CARD_SIZE := Vector2(270, 250)
const GAP := 10
const PAGE_SIZE := Vector2(CARD_SIZE.x * 3 + GAP * 2, CARD_SIZE.y * 2 + GAP)
const PORTRAIT_SCALE := 2.0
const GREETINGS: Array[String] = [
	"Hề hề… Chúa công muốn xem hàng tốt chứ? Đồ của ta không hỏi nguồn gốc đâu nhé.",
	"Suỵt… hàng hiếm vừa về. Qua lượt này là ta biến mất đấy.",
	"Vàng bạc đổi bảo vật, công bằng sòng phẳng. Hề hề…",
]

var _state: KingdomState
var _selling := false
## The item whose "Bán" was pressed once (second press sells).
var _armed: Item
var _grid: GridContainer
var _sell_list: VBoxContainer
var _sell_page: ScrollContainer
## Under the portrait: refresh (buying) and the storage count; rebuilt with the page.
var _tools: VBoxContainer
var _mode_button: Button


func open(state: KingdomState) -> void:
	_state = state
	var body := build_frame("Chợ đen", UiPalette.ACCENT, 0.85)
	var row := _row([])
	row.add_theme_constant_override("separation", 16)
	body.add_child(row)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(PortraitView.SIZE * PORTRAIT_SCALE, 0)
	row.add_child(left)
	var portrait := TextureRect.new()
	portrait.texture = GameArt.npc_portrait(&"black_market")
	portrait.custom_minimum_size = Vector2.ONE * PortraitView.SIZE * PORTRAIT_SCALE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var frame := TextureRect.new()
	frame.texture = GameArt.portrait_part("frame_0")
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.add_child(frame)
	left.add_child(portrait)
	for text: String in [GREETINGS[state.turn / BlackMarket.INTERVAL % GREETINGS.size()],
			"Chỉ ở lại lượt này. Đóng cửa sổ là gã rời đi; %d lượt sau mới quay lại." % BlackMarket.INTERVAL]:
		var label := _label(text, 14 if left.get_child_count() == 1 else 13)
		label.custom_minimum_size = Vector2(PortraitView.SIZE * PORTRAIT_SCALE, 0)
		if left.get_child_count() > 1:
			label.add_theme_color_override("font_color", MUTED_COLOR)
		left.add_child(label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	_tools = VBoxContainer.new()
	_tools.add_theme_constant_override("separation", 4)
	left.add_child(_tools)
	_mode_button = _button("", _toggle_mode)
	_mode_button.custom_minimum_size = Vector2(0, 44)
	left.add_child(_mode_button)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", GAP)
	row.add_child(right)
	var page := Control.new()
	page.custom_minimum_size = PAGE_SIZE
	right.add_child(page)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	page.add_child(_grid)
	_sell_page = ScrollContainer.new()
	_sell_page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sell_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(_sell_page)
	_sell_list = VBoxContainer.new()
	_sell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sell_list.add_theme_constant_override("separation", 6)
	_sell_page.add_child(_sell_list)
	_close_button.text = "Rời đi (Esc)"
	closed.connect(state.black_market.leave)
	state.black_market.changed.connect(_refresh)
	state.stockpile.changed.connect(_refresh)
	state.equipment.changed.connect(_refresh)
	_refresh()


func _toggle_mode() -> void:
	_selling = not _selling
	_armed = null
	set_status("")
	_refresh()


func _refresh() -> void:
	for box: Container in [_grid, _sell_list, _tools]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	_grid.visible = not _selling
	_sell_page.visible = _selling
	_mode_button.text = "Quay lại quầy hàng" if _selling else "Hành trang (bán đồ)"
	if _selling:
		_fill_sell_page()
	else:
		_fill_buy_page()
	var storage := _label("Kho đồ: %d/%d" % [_state.equipment.items.size(), Equipment.MAX_STORAGE], 13, false)
	storage.add_theme_color_override("font_color", MUTED_COLOR)
	_tools.add_child(storage)


# --- Buying -------------------------------------------------------------------------------

func _fill_buy_page() -> void:
	var market := _state.black_market
	for i in market.offers.size():
		_grid.add_child(_card(i, market.offers[i]))
	var button := _button("Làm mới (còn %d lần)" % market.refreshes_left, _refresh_offers)
	button.custom_minimum_size = Vector2(0, 40)
	button.disabled = market.check_refresh(_state.stockpile) != BlackMarket.Result.OK
	_tools.add_child(button)
	var cost := RequirementView.new()
	cost.costs(BlackMarket.REFRESH_COST, _state.stockpile)
	_tools.add_child(cost)


## One offer, always CARD_SIZE: icon, name in its rarity color, what it does, price chips and
## "Mua" (or "Đã bán") pinned to the bottom.
func _card(index: int, offer: Dictionary) -> Control:
	# A plain Control holds the card so long text is cut off instead of growing the grid.
	var holder := Control.new()
	holder.custom_minimum_size = CARD_SIZE
	holder.clip_contents = true
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"InsetPanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)
	var item: Item = offer.item
	var name_label: Label
	var icon: Control
	if item != null:
		icon = ItemIcon.new()
		icon.setup(item, 2)
		name_label = _label("%s\n%s · %s" % [item.display_name, Item.RARITY_NAMES[item.rarity], _kind_name(item)], 14)
		name_label.add_theme_color_override("font_color", UiPalette.ink(Item.RARITY_COLORS[item.rarity]))
	else:
		icon = _scroll_icon()
		name_label = _label("Bí kíp đột phá\nĐang có %d cuốn" % _state.scrolls, 14)
		name_label.add_theme_color_override("font_color", UiPalette.ACCENT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_row([icon, name_label]))
	# Effects take the space left and scroll when long, so the price and "Mua" stay at the bottom.
	var effects := ScrollContainer.new()
	effects.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	effects.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(effects)
	var view := RequirementView.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effects.add_child(view)
	if item != null:
		for line in item.describe_lines():
			view.gain(line)
	else:
		view.gain("Dùng để đột phá giới hạn tướng / mưu sĩ")
	var price := RequirementView.new()
	price.costs(offer.cost, _state.stockpile)
	column.add_child(price)
	var result := _state.black_market.check_buy(index, _state.stockpile, _state.equipment)
	var text := "Đã bán" if offer.sold else ("Kho đầy" if result == BlackMarket.Result.STORAGE_FULL else "Mua")
	var buy := _button(text, _buy.bind(index))
	buy.custom_minimum_size = Vector2(0, 40)
	buy.disabled = result != BlackMarket.Result.OK
	column.add_child(buy)
	return holder


func _buy(index: int) -> void:
	var offer := _state.black_market.offers[index]
	var name: String = offer.item.display_name if offer.item != null else "Bí kíp đột phá"
	var result := _state.black_market.buy(index, _state)
	if result == BlackMarket.Result.OK:
		Sfx.play(&"coins")
		set_status("Đã mua %s." % name)
	else:
		set_status(BlackMarket.describe(result), false)


func _refresh_offers() -> void:
	var result := _state.black_market.refresh(_state.stockpile, _state.equipment)
	if result == BlackMarket.Result.OK:
		set_status("Gã chợ đen bày ra mớ hàng khác.")
	else:
		set_status(BlackMarket.describe(result), false)


# --- Selling ------------------------------------------------------------------------------

func _fill_sell_page() -> void:
	var items := BlackMarket.sellable(_state)
	var hint := _label("Gã trả cao hơn phân rã một chút. Bấm Bán hai lần để chắc chắn.", 13)
	hint.add_theme_color_override("font_color", MUTED_COLOR)
	_sell_list.add_child(hint)
	if items.is_empty():
		_sell_list.add_child(_label("Kho đồ trống, chưa ai mang trang bị.", 14))
	var worn_started := false
	for item in items:
		var officer := BlackMarket.wearer(item, _state)
		if officer != null and not worn_started:
			worn_started = true
			_sell_list.add_child(HSeparator.new())
			var caption := _label("Đang trên người tướng sĩ (bán sẽ tháo ra):", 13)
			caption.add_theme_color_override("font_color", MUTED_COLOR)
			_sell_list.add_child(caption)
		_sell_list.add_child(_sell_row(item, officer))


## A stored or worn item: the wearer's face (when worn), icon, name and effects, what the merchant
## pays, and a two-press "Bán".
func _sell_row(item: Item, officer: Officer) -> Control:
	var parts: Array = []
	if officer != null:
		var face := PortraitView.new()
		face.setup(officer, 0.5)
		parts.append(face)
	var icon := ItemIcon.new()
	icon.setup(item, 2)
	parts.append(icon)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)
	var title := _label("%s (%s · %s)" % [item.display_name, Item.RARITY_NAMES[item.rarity], _kind_name(item)], 14)
	title.add_theme_color_override("font_color", UiPalette.ink(Item.RARITY_COLORS[item.rarity]))
	column.add_child(title)
	var details := " · ".join(item.describe_lines())
	if officer != null:
		details = "%s %s mang · %s" % [officer.name, officer.star_text(), details]
	var detail_label := _label(details, 13)
	detail_label.add_theme_color_override("font_color", MUTED_COLOR)
	column.add_child(detail_label)
	parts.append(column)
	var price := RequirementView.new()
	price.amounts("", BlackMarket.sell_value(item), true)
	price.custom_minimum_size = Vector2(110, 0)
	price.size_flags_horizontal = Control.SIZE_SHRINK_END
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parts.append(price)
	var result := _state.black_market.check_sell(item, _state)
	var sell := _button("Chắc chắn?" if _armed == item else "Bán", _sell.bind(item))
	sell.custom_minimum_size = Vector2(110, 36)
	sell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sell.disabled = result != BlackMarket.Result.OK
	if result != BlackMarket.Result.OK:
		sell.tooltip_text = BlackMarket.describe(result)
	parts.append(sell)
	var row := _row(parts)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	return row


func _sell(item: Item) -> void:
	if _armed != item:
		_armed = item
		_refresh()
		return
	_armed = null
	var result := _state.black_market.sell(item, _state)
	if result == BlackMarket.Result.OK:
		Sfx.play(&"coins")
		set_status("Đã bán %s." % item.display_name)
	else:
		set_status(BlackMarket.describe(result), false)
		_refresh()


func _kind_name(item: Item) -> String:
	return "Tướng" if item.kind == &"general" else "Mưu sĩ"


func _scroll_icon() -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = GameArt.icon(&"scroll")
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return icon
