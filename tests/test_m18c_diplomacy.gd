extends "res://tests/test_suite.gd"
## M18c (GDD §9.8): hidden goods, supply and demand, urgent needs, tired of gifts, tribute.

var resource_types := ResourceTypeData.load_all()


func _diplomacy() -> Diplomacy:
	return Diplomacy.new(ClanData.load_all(), resource_types)


func _stock(amounts: Dictionary[StringName, int]) -> Stockpile:
	var stockpile := Stockpile.new()
	stockpile.add(amounts)
	return stockpile


func _state() -> KingdomState:
	var terrains := TerrainLibrary.load_all()
	var gen := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, 1)
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(gen), terrains,
			BuildingData.load_all(), UnitData.load_all(), 3)
	state.start()
	return state


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# --- Hidden goods -------------------------------------------------------------------------

func test_stock_depends_on_the_clan() -> void:
	var diplomacy := _diplomacy()
	# Wolves: aggressive, stone in surplus, food lacking; weak (no tier callable).
	check_eq(diplomacy.stock_max(&"north_wolves", &"wood"), 60, "60 value of wood")
	check_eq(diplomacy.stock_max(&"north_wolves", &"ore"), 20, "60 value of ore = 20")
	check_eq(diplomacy.stock_max(&"north_wolves", &"stone"), 60, "Surplus ×2: 30 → 60 stone")
	check_eq(diplomacy.stock_max(&"north_wolves", &"food"), 30, "Lacking ×0.5")
	diplomacy.clan_tier = func(_clan_id: StringName) -> int: return 2
	check_eq(diplomacy.stock_max(&"north_wolves", &"wood"), 90, "Strong clans ×1.5")
	check_eq(diplomacy.stock_left(&"north_wolves", &"wood"), 90, "Starts full")


func test_trades_take_from_the_hidden_stock_and_it_refills() -> void:
	var diplomacy := _diplomacy()
	var clan := diplomacy.clans[&"north_wolves"]
	var stockpile := _stock({&"wood": 100})
	var quote := diplomacy.trade_quote(&"north_wolves", &"wood", 30, &"stone")
	check(quote > 0, "They pay stone for wood")
	check_eq(diplomacy.trade(stockpile, &"north_wolves", &"wood", 30, &"stone"), Diplomacy.TradeResult.OK, "Traded")
	check_eq(diplomacy.stock_left(&"north_wolves", &"stone"), 60 - quote, "Their stone went down")
	check_eq(diplomacy.stock_left(&"north_wolves", &"wood"), 60, "Wood they got stays at most full")
	# The next quote is lower (they hold more wood now); leave one stone short of it.
	var next := diplomacy.trade_quote(&"north_wolves", &"wood", 30, &"stone")
	clan.stock[&"stone"] = next - 1
	clan.traded_value_this_turn = 0
	check_eq(diplomacy.check_trade(stockpile, &"north_wolves", &"wood", 30, &"stone"), Diplomacy.TradeResult.OUT_OF_STOCK,
			"Not enough stone left")
	check(diplomacy.stock_low(&"north_wolves", &"stone"), "The dialog hints their stone runs low")
	stockpile.add({&"wood": 100})
	check_eq(stockpile.get_amount(&"wood"), 170, "Nothing was taken by the refused trade")
	diplomacy.end_turn()
	check_eq(diplomacy.stock_left(&"north_wolves", &"stone"), next - 1 + 15, "A quarter of 60 comes back")
	for i in 4:
		diplomacy.end_turn()
	check(not clan.stock.has(&"stone"), "Full again: nothing left to remember")


func test_selling_one_thing_lowers_its_price() -> void:
	var diplomacy := _diplomacy()
	var clan := diplomacy.clans[&"north_wolves"]
	clan.urgent = &""
	var before := diplomacy.price_factor(&"north_wolves", &"wood", &"stone")
	diplomacy.trade(_stock({&"wood": 100}), &"north_wolves", &"wood", 40, &"stone")
	check_eq(clan.sold[&"wood"], 40, "Remembered 40 value of wood sold")
	var after := diplomacy.price_factor(&"north_wolves", &"wood", &"stone")
	check(after < before, "Wood is worth less to them now (%.3f → %.3f)" % [before, after])
	clan.sold.clear()
	check(is_equal_approx(diplomacy.price_factor(&"north_wolves", &"food", &"stone")
			/ diplomacy.price_factor(&"north_wolves", &"wood", &"stone"), 1.4), "Food (which they lack) pays ×1.4")
	clan.sold[&"wood"] = 1000
	check(is_equal_approx(diplomacy.demand_factor(&"north_wolves", &"wood"), 1.0 - Diplomacy.DEMAND_DROP), "Bottom of demand")
	clan.urgent_turns = 99
	diplomacy.end_turn()
	check_eq(clan.sold[&"wood"], 700, "Sales fade to 70% a turn")


func test_every_clan_has_an_urgent_need_that_changes() -> void:
	var diplomacy := _diplomacy()
	diplomacy.rng.seed = 4
	diplomacy.end_turn()
	for clan_id in diplomacy.clans:
		var clan := diplomacy.clans[clan_id]
		check(clan.urgent != &"", "%s needs something" % clan_id)
		check(not clan.data.surplus.has(clan.urgent), "%s never needs what it has in surplus" % clan_id)
		check_eq(clan.urgent_turns, Diplomacy.URGENT_TURNS, "For 6 turns")
	var clan := diplomacy.clans[&"north_wolves"]
	clan.sold.clear()
	var need := clan.urgent
	check(is_equal_approx(diplomacy.demand_factor(&"north_wolves", need), Diplomacy.URGENT_BONUS), "Pays more for it")
	var seen := {need: true}
	for i in 60:
		diplomacy.end_turn()
		seen[clan.urgent] = true
	check(seen.size() >= 3, "The need changes over time (%d kinds)" % seen.size())


# --- Gifts --------------------------------------------------------------------------------

func test_gifts_of_what_they_need_count_more() -> void:
	var diplomacy := _diplomacy()
	diplomacy.clans[&"north_wolves"].urgent = &""
	var wood: Dictionary[StringName, int] = {&"wood": 40}
	var food: Dictionary[StringName, int] = {&"food": 40}
	check(diplomacy.gift_gain(&"north_wolves", food) > diplomacy.gift_gain(&"north_wolves", wood), "Food (lacking) beats wood")
	diplomacy.clans[&"north_wolves"].urgent = &"wood"
	check_eq(diplomacy.gift_gain(&"north_wolves", wood), diplomacy.gift_gain(&"north_wolves", food), "Urgent wood as good as food")


func test_gifts_tire_and_have_a_ceiling() -> void:
	var diplomacy := _diplomacy()
	var clan := diplomacy.clans[&"south_farmers"]
	clan.urgent = &""
	var gift: Dictionary[StringName, int] = {&"wood": 40}
	var fresh := diplomacy.gift_gain(&"south_farmers", gift)
	check_eq(diplomacy.give_gift(_stock({&"wood": 400}), &"south_farmers", gift), Diplomacy.GiftResult.OK, "Given")
	check_eq(clan.gift_fatigue, fresh, "Fatigue grows by what it gave")
	diplomacy.end_turn()
	check(diplomacy.gift_appeal(&"south_farmers") < 1.0, "Less appealing after a gift")
	check(diplomacy.gift_gain(&"south_farmers", gift) < fresh, "The same gift does less (%d < %d)" % [
			diplomacy.gift_gain(&"south_farmers", gift), fresh])
	clan.gift_fatigue = 1000
	check(is_equal_approx(diplomacy.gift_appeal(&"south_farmers"), Diplomacy.GIFT_MIN_APPEAL), "Never below a quarter")
	clan.gift_fatigue = 0
	clan.memories[Diplomacy.MEMORY_GIFT] = Diplomacy.GIFT_MEMORY_CAP - 2
	check_eq(diplomacy.gift_gain(&"south_farmers", gift), 2, "Only up to the ceiling")
	clan.memories[Diplomacy.MEMORY_GIFT] = Diplomacy.GIFT_MEMORY_CAP
	check_eq(diplomacy.check_gift(_stock({&"wood": 400}), &"south_farmers", gift), Diplomacy.GiftResult.SATED, "Sated")
	clan.gift_fatigue = 12
	diplomacy.end_turn()
	check_eq(clan.gift_fatigue, 7, "Fatigue falls 5 a turn")


func test_market_state_is_saved() -> void:
	var diplomacy := _diplomacy()
	var clan := diplomacy.clans[&"north_wolves"]
	clan.stock[&"stone"] = 7
	clan.sold[&"wood"] = 33
	clan.urgent = &"horses"
	clan.urgent_turns = 4
	clan.gift_fatigue = 9
	clan.tribute_cooldown = 6
	clan.tribute_peace = 3
	var loaded := _diplomacy()
	loaded.load_save(JSON.parse_string(JSON.stringify(diplomacy.to_save())))
	var back := loaded.clans[&"north_wolves"]
	check_eq(back.stock, {&"stone": 7}, "Stock")
	check_eq(back.sold, {&"wood": 33}, "Sales")
	check_eq([back.urgent, back.urgent_turns], [&"horses", 4], "Urgent need")
	check_eq([back.gift_fatigue, back.tribute_cooldown, back.tribute_peace], [9, 6, 3], "Counters")
	var old := diplomacy.to_save()
	for entry: Dictionary in old.clans.values():
		entry.erase("stock")
		entry.erase("sold")
		entry.erase("urgent")
	var from_old := _diplomacy()
	from_old.load_save(JSON.parse_string(JSON.stringify(old)))
	check(from_old.clans[&"north_wolves"].stock.is_empty(), "Older saves start full")


func test_the_kingdom_wires_the_clan_tier() -> void:
	var state := _state()
	check(state.diplomacy.clan_tier.is_valid(), "Tier comes from Wars")
	state.wars.fronts[&"north_wolves"].strength = 1000
	check_eq(state.diplomacy.stock_max(&"north_wolves", &"wood"), 90, "A strong clan keeps more")


# --- Tribute ------------------------------------------------------------------------------

func test_tribute_needs_a_much_weaker_neighbor() -> void:
	var state := _state()
	state.wars.fronts[&"north_wolves"].strength = 50
	check_eq(Tribute.check(state, &"north_wolves"), Tribute.Result.NOT_WEAK, "No army")
	for i in 5:
		state.army.add_squad(&"swordsman", 20)
	check_eq(Tribute.check(state, &"north_wolves"), Tribute.Result.OK, "100 soldiers vs 50")
	state.wars.fronts[&"north_wolves"].strength = 51
	check_eq(Tribute.check(state, &"north_wolves"), Tribute.Result.NOT_WEAK, "Just short of twice")
	state.wars.fronts[&"north_wolves"].strength = 50
	var far := &""
	for clan_id in state.diplomacy.clans:
		if not state.wars.is_neighbor(clan_id):
			far = clan_id
			break
	check_eq(Tribute.check(state, far), Tribute.Result.NOT_NEIGHBOR, "Only neighbors")
	state.diplomacy.clans[&"north_wolves"].alliance_turns = 5
	check_eq(Tribute.check(state, &"north_wolves"), Tribute.Result.ALLIED, "Never an ally")
	state.diplomacy.clans[&"north_wolves"].alliance_turns = 0
	state.wars.declare_war(&"north_wolves")
	check_eq(Tribute.check(state, &"north_wolves"), Tribute.Result.AT_WAR, "Not during a war")


func test_tribute_chance_and_goods() -> void:
	var state := _state()
	state.wars.fronts[&"north_wolves"].strength = 40
	for i in 4:
		state.army.add_squad(&"swordsman", 20)
	# Ratio 2: base 35%, aggressive −15%.
	check(is_equal_approx(Tribute.chance(state, &"north_wolves"), 0.2), "35% − 15% for the aggressive wolves")
	state.wars.fronts[&"north_wolves"].strength = 20
	check(is_equal_approx(Tribute.chance(state, &"north_wolves"), 0.5), "Ratio 4: +30%")
	# Value 40 + 20 × 0.25 = 45 in stone (their surplus, worth 2): 22.5 rounds to 23.
	check_eq(Tribute.amounts(state, &"north_wolves"), {&"stone": 23}, "Paid in what they have in surplus")


func test_demanding_tribute() -> void:
	var accepted := 0
	var refused := 0
	for seed_value in 40:
		var state := _state()
		state.wars.fronts[&"north_wolves"].strength = 20
		for i in 4:
			state.army.add_squad(&"swordsman", 20)
		var wolves := state.diplomacy.clans[&"north_wolves"].relation
		var farmers := state.diplomacy.clans[&"south_farmers"].relation
		var outcome := Tribute.demand(state, &"north_wolves", _rng(seed_value))
		check_eq(state.diplomacy.clans[&"north_wolves"].tribute_cooldown, Tribute.COOLDOWN_TURNS, "Cooldown either way")
		check_eq(Tribute.check(state, &"north_wolves"), Tribute.Result.COOLDOWN, "Cannot ask again at once")
		if outcome.accepted:
			accepted += 1
			check_eq(state.stockpile.get_amount(&"stone"), 23, "Goods received")
			check_eq(state.diplomacy.clans[&"north_wolves"].relation, wolves + Tribute.ACCEPT_RELATION, "−15")
			check_eq(state.diplomacy.clans[&"south_farmers"].relation, farmers + Tribute.OTHERS_RELATION, "Others −3")
		else:
			refused += 1
			check_eq(state.stockpile.get_amount(&"stone"), 0, "Nothing received")
			check_eq(state.diplomacy.clans[&"north_wolves"].relation, wolves + Tribute.REFUSE_RELATION, "−10")
			check_eq(state.diplomacy.clans[&"south_farmers"].relation, farmers, "Others do not care")
	check(accepted > 5 and refused > 5, "Both happen (%d / %d)" % [accepted, refused])
