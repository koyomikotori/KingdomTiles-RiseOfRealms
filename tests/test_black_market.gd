extends "res://tests/test_suite.gd"
## M16d: the black market (visit turns, offers, buying items and scrolls, refreshes, legendaries,
## selling stored and worn items, save).

var terrains := TerrainLibrary.load_all()


func _state(rich: bool = true) -> KingdomState:
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.start()
	if rich:
		state.stockpile.add({&"food": 2000, &"wood": 2000, &"stone": 2000, &"ore": 2000, &"hardwood": 2000})
	return state


## The first offer that is an item (or a scroll when `scroll`), or -1.
func _find(market: BlackMarket, scroll: bool) -> int:
	for i in market.offers.size():
		if (market.offers[i].item == null) == scroll:
			return i
	return -1


## Rerolls until an offer of the wanted kind shows up (refreshes do not count here).
func _ensure(state: KingdomState, scroll: bool) -> int:
	for attempt in 50:
		var index := _find(state.black_market, scroll)
		if index >= 0:
			return index
		state.black_market.arrive(state.equipment)
	return -1


func test_visit_turns() -> void:
	check(not BlackMarket.is_visit_turn(0), "Never on turn 0")
	check(not BlackMarket.is_visit_turn(7), "Not on turn 7")
	check(BlackMarket.is_visit_turn(8), "Turn 8")
	check(BlackMarket.is_visit_turn(16), "Turn 16")
	check_eq(BlackMarket.turns_until_visit(5), 3, "3 turns from turn 5")
	check_eq(BlackMarket.turns_until_visit(8), 0, "0 on a visit turn")


func test_arrive_stocks_six_offers() -> void:
	var state := _state()
	var market := state.black_market
	market.arrive(state.equipment)
	check(market.open, "Open after arriving")
	check_eq(market.offers.size(), BlackMarket.SLOTS, "Six offers")
	check_eq(market.refreshes_left, BlackMarket.MAX_REFRESHES, "Three refreshes")
	for offer in market.offers:
		check(not offer.cost.is_empty(), "Every offer has a price")
	market.leave()
	check(not market.open, "Closed after leaving")
	check(market.offers.is_empty(), "No offers once gone")
	check_eq(market.check_buy(0, state.stockpile, state.equipment), BlackMarket.Result.CLOSED, "Cannot buy once gone")


func test_prices_follow_rarity() -> void:
	var market := BlackMarket.new()
	market.rng.seed = 4
	for rarity in BlackMarket.PRICES.size():
		var cost := market._price(rarity)
		for resource_id: StringName in BlackMarket.PRICES[rarity]:
			var base: int = BlackMarket.PRICES[rarity][resource_id]
			check(cost[resource_id] >= floori(base * (1.0 - BlackMarket.PRICE_JITTER)) and
					cost[resource_id] <= ceili(base * (1.0 + BlackMarket.PRICE_JITTER)), "Price within the jitter")


func test_buy_item() -> void:
	var state := _state()
	state.black_market.arrive(state.equipment)
	var index := _ensure(state, false)
	check(index >= 0, "An item offer exists")
	var offer := state.black_market.offers[index]
	var food := state.stockpile.get_amount(&"food")
	check_eq(state.black_market.buy(index, state), BlackMarket.Result.OK, "Bought")
	check(offer.sold, "Marked sold")
	check(state.equipment.items.has(offer.item), "Item in storage")
	check_eq(state.stockpile.get_amount(&"food"), food - offer.cost.get(&"food", 0), "Paid the price")
	check_eq(state.black_market.buy(index, state), BlackMarket.Result.SOLD, "Cannot buy twice")


func test_buy_scroll() -> void:
	var state := _state()
	state.black_market.arrive(state.equipment)
	var index := _ensure(state, true)
	check(index >= 0, "A scroll offer exists")
	check_eq(state.black_market.buy(index, state), BlackMarket.Result.OK, "Bought")
	check_eq(state.scrolls, 1, "One scroll")
	check(state.equipment.items.is_empty(), "No item added")


func test_cannot_afford_changes_nothing() -> void:
	var state := _state(false)
	state.black_market.arrive(state.equipment)
	check_eq(state.black_market.buy(0, state), BlackMarket.Result.CANNOT_AFFORD, "Too poor")
	check(not state.black_market.offers[0].sold, "Not sold")
	check_eq(state.black_market.refresh(state.stockpile, state.equipment), BlackMarket.Result.CANNOT_AFFORD,
			"Refresh too poor")
	check_eq(state.black_market.refreshes_left, BlackMarket.MAX_REFRESHES, "No refresh used")


func test_storage_full_blocks_items_only() -> void:
	var state := _state()
	while state.equipment.items.size() < Equipment.MAX_STORAGE:
		state.equipment.items.append(state.equipment.create_random(0))
	state.black_market.arrive(state.equipment)
	var index := _ensure(state, false)
	var before := state.stockpile.get_amount(&"food")
	check_eq(state.black_market.buy(index, state), BlackMarket.Result.STORAGE_FULL, "Storage full")
	check_eq(state.stockpile.get_amount(&"food"), before, "Nothing paid")
	var scroll := _ensure(state, true)
	check_eq(state.black_market.check_buy(scroll, state.stockpile, state.equipment), BlackMarket.Result.OK,
			"Scrolls still sell")


func test_refresh_limit_and_cost() -> void:
	var state := _state()
	state.black_market.arrive(state.equipment)
	var ore := state.stockpile.get_amount(&"ore")
	for i in BlackMarket.MAX_REFRESHES:
		check_eq(state.black_market.refresh(state.stockpile, state.equipment), BlackMarket.Result.OK, "Refresh %d" % i)
	check_eq(state.black_market.refreshes_left, 0, "None left")
	check_eq(state.stockpile.get_amount(&"ore"), ore - BlackMarket.MAX_REFRESHES * BlackMarket.REFRESH_COST[&"ore"],
			"Paid each refresh")
	check_eq(state.black_market.refresh(state.stockpile, state.equipment), BlackMarket.Result.NO_REFRESHES, "Limit")
	check_eq(state.black_market.offers.size(), BlackMarket.SLOTS, "Still six offers")


func test_save_and_load() -> void:
	var state := _state()
	state.black_market.arrive(state.equipment)
	state.black_market.refresh(state.stockpile, state.equipment)
	state.black_market.buy(0, state)
	var copy := _state(false)
	copy.load_save(JSON.parse_string(JSON.stringify(state.to_save())))
	var market := copy.black_market
	check(market.open, "Still open")
	check_eq(market.refreshes_left, BlackMarket.MAX_REFRESHES - 1, "Refreshes kept")
	check_eq(market.offers.size(), BlackMarket.SLOTS, "Offers kept")
	check(market.offers[0].sold, "Sold mark kept")
	for i in market.offers.size():
		var a: Dictionary = state.black_market.offers[i]
		var b: Dictionary = market.offers[i]
		check_eq(b.cost, a.cost, "Price kept")
		check_eq(b.item == null, a.item == null, "Kind kept")
		if a.item != null:
			check_eq(b.item.display_name, a.item.display_name, "Item kept")
	var old := state.to_save()
	old.erase("black_market")
	var older := _state(false)
	older.load_save(JSON.parse_string(JSON.stringify(old)))
	check(not older.black_market.open, "Older saves: no market")


func test_end_turn_brings_the_merchant_every_eight_turns() -> void:
	var state := _state()
	var visits: Array = []
	for i in 17:
		var report := state.end_turn()
		if report.get("black_market", false):
			check(state.black_market.open, "Open on turn %d" % state.turn)
			visits.append(state.turn)
		else:
			check(not state.black_market.open, "Gone on turn %d" % state.turn)
	check_eq(visits, [8, 16], "Turns 8 and 16")


func test_legendary_offer_found_only_when_bought() -> void:
	var state := _state()
	var market := state.black_market
	market.open = true
	var item: Item = null
	for attempt in 400:
		item = market._create(state.equipment)
		if item.rarity == Item.Rarity.LEGENDARY:
			break
	check_eq(item.rarity, Item.Rarity.LEGENDARY, "Legendaries do show up")
	check(state.equipment.found_legendaries.is_empty(), "Not found just by being offered")
	market.offers = [{"item": item, "cost": market._price(item.rarity), "sold": false}]
	check_eq(market.buy(0, state), BlackMarket.Result.OK, "Bought")
	check(state.equipment.found_legendaries.has(item.legendary_id), "Found once bought")


func test_legendary_odds_are_low() -> void:
	var total := 0
	for weight in BlackMarket.RARITY_ODDS:
		total += weight
	var share := float(BlackMarket.RARITY_ODDS[Item.Rarity.LEGENDARY]) / total
	check(share >= 0.01 and share <= 0.02, "1–2% legendary")


func test_legendary_found_elsewhere_cannot_be_bought() -> void:
	var state := _state()
	var market := state.black_market
	market.open = true
	var id: StringName = state.equipment.legendaries.keys()[0]
	var item := state.equipment.create_legendary(id)
	state.equipment.found_legendaries.erase(id)
	market.offers = [{"item": item, "cost": market._price(item.rarity), "sold": false}]
	state.equipment.found_legendaries.append(id)
	check_eq(market.buy(0, state), BlackMarket.Result.SOLD, "Already found: gone")


func test_no_legendary_left_gives_epic() -> void:
	var state := _state()
	for id in state.equipment.legendaries:
		state.equipment.found_legendaries.append(id)
	var market := state.black_market
	for attempt in 300:
		check(market._create(state.equipment).rarity <= Item.Rarity.EPIC, "Epic at most")


func test_sell_value_beats_dismantling() -> void:
	var state := _state()
	for rarity in Item.Rarity.size():
		var item := state.equipment.create_random(rarity)
		var sold := BlackMarket.sell_value(item)
		var dismantled := state.equipment.dismantle_value(item)
		for resource_id in dismantled:
			check(sold[resource_id] > dismantled[resource_id], "More than dismantling (rarity %d)" % rarity)


func test_sell_stored_item() -> void:
	var state := _state(false)
	var item := state.equipment.create(&"general", &"weapon", 2)
	state.equipment.items.append(item)
	check_eq(state.black_market.sell(item, state), BlackMarket.Result.CLOSED, "Not while closed")
	state.black_market.arrive(state.equipment)
	check(BlackMarket.sellable(state).has(item), "Listed")
	check_eq(state.black_market.sell(item, state), BlackMarket.Result.OK, "Sold")
	check(not state.equipment.items.has(item), "Out of storage")
	check_eq(state.stockpile.get_amount(&"ore"), BlackMarket.sell_value(item)[&"ore"], "Paid")
	check_eq(state.black_market.sell(item, state), BlackMarket.Result.NOT_OWNED, "Cannot sell twice")


func test_sell_worn_item() -> void:
	var state := _state(false)
	var general := state.generals.generate(2)
	state.generals.add(general)
	var item := state.equipment.create(&"general", &"armor", 1)
	general.items[&"armor"] = item
	state.black_market.arrive(state.equipment)
	check(BlackMarket.sellable(state).has(item), "Worn items listed")
	check_eq(BlackMarket.wearer(item, state), general, "Wearer found")
	general.away = true
	check_eq(state.black_market.sell(item, state), BlackMarket.Result.AWAY, "Not while on an expedition")
	check(general.items.has(&"armor"), "Still worn")
	general.away = false
	check_eq(state.black_market.sell(item, state), BlackMarket.Result.OK, "Sold")
	check(not general.items.has(&"armor"), "Taken off")
	check(not state.equipment.items.has(item), "Not put in storage")
