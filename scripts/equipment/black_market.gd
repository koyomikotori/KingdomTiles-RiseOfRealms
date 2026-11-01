class_name BlackMarket
extends RefCounted
## The black market (chợ đen, GDD §20, M16d): every INTERVAL turns a cloaked merchant stops by for
## that turn only. They lay out SLOTS offers (items up to Sử thi priced by rarity, or a Bí kíp đột
## phá with SCROLL_CHANCE), which can be rerolled MAX_REFRESHES times for REFRESH_COST. Leaving
## (closing the window, or refusing) sends them away until the next visit. The merchant also buys
## the kingdom's items (stored or worn) for SELL_FACTOR × their dismantle value. Owned by
## KingdomState (own rng, seed + 8); items come from Equipment (a legendary on offer only counts as
## found once it is bought).

signal changed

enum Result { OK, SOLD, CANNOT_AFFORD, STORAGE_FULL, NO_REFRESHES, CLOSED, AWAY, NOT_OWNED }

const INTERVAL := 8
const SLOTS := 6
const MAX_REFRESHES := 3
const REFRESH_COST: Dictionary[StringName, int] = {&"ore": 10, &"hardwood": 10}
## Rarity weights of an item offer (Thường, Tốt, Hiếm, Sử thi, Huyền thoại ≈ 1.5%).
const RARITY_ODDS: Array[int] = [350, 320, 220, 95, 15]
## Base price by rarity, each amount × PRICE_JITTER either way.
const PRICES: Array = [
	{&"food": 15, &"wood": 15, &"stone": 10},
	{&"food": 30, &"wood": 30, &"stone": 20, &"ore": 5},
	{&"food": 50, &"wood": 50, &"stone": 50, &"ore": 15, &"hardwood": 15},
	{&"food": 100, &"wood": 100, &"stone": 100, &"ore": 40, &"hardwood": 40},
	{&"food": 250, &"wood": 250, &"stone": 250, &"ore": 100, &"hardwood": 100},
]
const PRICE_JITTER := 0.2
const SCROLL_CHANCE := 0.2
const SCROLL_PRICE: Dictionary[StringName, int] = {&"food": 150, &"ore": 30, &"hardwood": 30}
## Selling pays this many times Equipment.dismantle_value (rounded up, always more than dismantling).
const SELL_FACTOR := 1.5

## Offers while the merchant is here: {"item": Item or null (a scroll), "cost": amounts, "sold": bool}.
var offers: Array[Dictionary] = []
var refreshes_left := 0
## The merchant is waiting at the start of this turn (saved, so a reload shows them again).
var open := false
var rng := RandomNumberGenerator.new()


static func is_visit_turn(turn: int) -> bool:
	return turn > 0 and turn % INTERVAL == 0


## Turns until the next visit (0 on a visit turn).
static func turns_until_visit(turn: int) -> int:
	return posmod(-turn, INTERVAL)


## The merchant arrives: fresh offers and refreshes.
func arrive(equipment: Equipment) -> void:
	open = true
	refreshes_left = MAX_REFRESHES
	_stock(equipment)


## The merchant leaves (window closed or refused).
func leave() -> void:
	open = false
	offers.clear()
	changed.emit()


func check_refresh(stockpile: Stockpile) -> Result:
	if not open:
		return Result.CLOSED
	if refreshes_left <= 0:
		return Result.NO_REFRESHES
	if not stockpile.can_afford(REFRESH_COST):
		return Result.CANNOT_AFFORD
	return Result.OK


## Pays REFRESH_COST for new offers; nothing changes unless check_refresh() is OK.
func refresh(stockpile: Stockpile, equipment: Equipment) -> Result:
	var result := check_refresh(stockpile)
	if result == Result.OK:
		stockpile.spend(REFRESH_COST)
		refreshes_left -= 1
		_stock(equipment)
	return result


func check_buy(index: int, stockpile: Stockpile, equipment: Equipment) -> Result:
	if not open or index < 0 or index >= offers.size():
		return Result.CLOSED
	var offer := offers[index]
	if offer.sold:
		return Result.SOLD
	if offer.item != null and offer.item.legendary_id != &"" and equipment.found_legendaries.has(offer.item.legendary_id):
		return Result.SOLD
	if offer.item != null and not equipment.has_room():
		return Result.STORAGE_FULL
	if not stockpile.can_afford(offer.cost):
		return Result.CANNOT_AFFORD
	return Result.OK


## Pays for offer `index`: the item goes to storage or the scroll to KingdomState.scrolls.
## Nothing changes unless check_buy() is OK.
func buy(index: int, state: KingdomState) -> Result:
	var result := check_buy(index, state.stockpile, state.equipment)
	if result != Result.OK:
		return result
	var offer := offers[index]
	state.stockpile.spend(offer.cost)
	offer.sold = true
	if offer.item != null:
		if offer.item.legendary_id != &"":
			state.equipment.found_legendaries.append(offer.item.legendary_id)
		state.equipment.receive(offer.item, state.stockpile)
	else:
		state.scrolls += 1
		state.generals.changed.emit()
	changed.emit()
	return result


# --- Selling --------------------------------------------------------------------------------

## What the merchant pays for `item`.
static func sell_value(item: Item) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	var dismantle_share := Equipment.DISMANTLE_SHARE * (item.rarity + 1)
	for resource_id in Equipment.FORGE_COST:
		var dismantled := maxi(1, floori(Equipment.FORGE_COST[resource_id] * dismantle_share))
		result[resource_id] = maxi(dismantled + 1, ceili(dismantled * SELL_FACTOR))
	return result


## The officer wearing `item`, or null (in storage, or not the kingdom's).
static func wearer(item: Item, state: KingdomState) -> Officer:
	for officer: Officer in state.generals.generals + state.advisors.advisors:
		if officer.items.values().has(item):
			return officer
	return null


## Items the merchant could buy: every stored item, then every worn one.
static func sellable(state: KingdomState) -> Array[Item]:
	var result: Array[Item] = []
	result.assign(state.equipment.items)
	for officer: Officer in state.generals.generals + state.advisors.advisors:
		for slot in Item.SLOTS:
			if officer.items.has(slot):
				result.append(officer.items[slot])
	return result


func check_sell(item: Item, state: KingdomState) -> Result:
	if not open:
		return Result.CLOSED
	if state.equipment.items.has(item):
		return Result.OK
	var officer := wearer(item, state)
	if officer == null:
		return Result.NOT_OWNED
	if officer.away:
		return Result.AWAY
	return Result.OK


## Sells a stored or worn item (taken off its wearer) for sell_value(). Nothing changes unless
## check_sell() is OK.
func sell(item: Item, state: KingdomState) -> Result:
	var result := check_sell(item, state)
	if result != Result.OK:
		return result
	if state.equipment.items.has(item):
		state.equipment.items.erase(item)
	else:
		var officer := wearer(item, state)
		officer.items.erase(officer.items.find_key(item))
		(state.advisors if officer is Advisor else state.generals).changed.emit()
	state.stockpile.add(sell_value(item))
	state.equipment.changed.emit()
	changed.emit()
	return result


static func describe(result: Result) -> String:
	match result:
		Result.SOLD:
			return "Món này đã bán."
		Result.CANNOT_AFFORD:
			return "Không đủ tài nguyên."
		Result.STORAGE_FULL:
			return "Kho đồ đã đầy."
		Result.NO_REFRESHES:
			return "Hết lượt làm mới."
		Result.CLOSED:
			return "Gã chợ đen đã đi."
		Result.AWAY:
			return "Người mang món này đang đi thảo phạt."
		Result.NOT_OWNED:
			return "Món này không còn của ta."
	return ""


func _stock(equipment: Equipment) -> void:
	offers.clear()
	for i in SLOTS:
		if rng.randf() < SCROLL_CHANCE:
			offers.append({"item": null, "cost": SCROLL_PRICE.duplicate(), "sold": false})
			continue
		var item := _create(equipment)
		offers.append({"item": item, "cost": _price(item.rarity), "sold": false})
	changed.emit()


## A random item for an offer. A legendary not found yet and not already on offer is shown but stays
## unfound (Equipment.create_legendary marks it; that mark is taken back until it is bought);
## an epic one when none is left.
func _create(equipment: Equipment) -> Item:
	var rarity := _roll_rarity()
	if rarity < Item.Rarity.LEGENDARY:
		return equipment.create(Item.KINDS[rng.randi_range(0, 1)], Item.SLOTS[rng.randi_range(0, 2)], rarity)
	var left: Array[StringName] = []
	for id in equipment.legendaries:
		if not equipment.found_legendaries.has(id) and not _offered(id):
			left.append(id)
	if left.is_empty():
		return equipment.create(Item.KINDS[rng.randi_range(0, 1)], Item.SLOTS[rng.randi_range(0, 2)], Item.Rarity.EPIC)
	var id := left[rng.randi_range(0, left.size() - 1)]
	var item := equipment.create_legendary(id)
	equipment.found_legendaries.erase(id)
	return item


func _offered(legendary_id: StringName) -> bool:
	for offer in offers:
		if offer.item != null and offer.item.legendary_id == legendary_id:
			return true
	return false


func _roll_rarity() -> int:
	var total := 0
	for weight in RARITY_ODDS:
		total += weight
	var pick := rng.randi_range(1, total)
	for i in RARITY_ODDS.size():
		pick -= RARITY_ODDS[i]
		if pick <= 0:
			return i
	return 0


func _price(rarity: int) -> Dictionary[StringName, int]:
	var base: Dictionary = PRICES[clampi(rarity, 0, PRICES.size() - 1)]
	var cost: Dictionary[StringName, int] = {}
	for resource_id: StringName in base:
		cost[resource_id] = maxi(1, roundi(base[resource_id] * rng.randf_range(1.0 - PRICE_JITTER, 1.0 + PRICE_JITTER)))
	return cost


# --- Save (GDD §10.1) ---------------------------------------------------------------------

func to_save() -> Dictionary:
	var saved: Array = []
	for offer in offers:
		saved.append({"item": offer.item.to_save() if offer.item != null else {}, "cost": offer.cost.duplicate(),
				"sold": offer.sold})
	return {"open": open, "refreshes_left": refreshes_left, "offers": saved}


func load_save(data: Dictionary) -> void:
	open = bool(data.get("open", false))
	refreshes_left = int(data.get("refreshes_left", 0))
	offers.clear()
	for entry: Dictionary in data.get("offers", []):
		var cost: Dictionary[StringName, int] = {}
		for resource_id: String in entry.get("cost", {}):
			cost[StringName(resource_id)] = int(entry.cost[resource_id])
		var item_data: Dictionary = entry.get("item", {})
		offers.append({"item": Item.from_save(item_data) if not item_data.is_empty() else null, "cost": cost,
				"sold": bool(entry.get("sold", false))})
	if offers.is_empty():
		open = false
