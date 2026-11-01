class_name Diplomacy
extends RefCounted
## Relations, gifts, one-off trades and long-term trade agreements with the clans (GDD §9).
## Pure logic, owned by KingdomState.

signal changed

enum Tier { HOSTILE, TENSE, NEUTRAL, FRIENDLY, CLOSE }
enum GiftResult { OK, EMPTY, CANNOT_AFFORD, LIMIT_REACHED, ANNEXED, TOO_SMALL, TOO_FAR }
enum TradeResult { OK, REFUSED, SAME_RESOURCE, EMPTY, CANNOT_AFFORD, OVER_CAPACITY, TOO_SMALL, TOO_FAR }
## OK = the clan signed. DECLINED = valid offer, but the clan said no.
enum ProposalResult { OK, DECLINED, REFUSED, SAME_RESOURCE, EMPTY, TOO_LARGE, BAD_DURATION, ALREADY_HAS, ASKED_THIS_TURN,
		TOO_FAR }

const TIER_NAMES: Array[String] = ["Thù địch", "Căng thẳng", "Trung lập", "Thân thiện", "Thân thiết"]
## Lowest relation of each tier above HOSTILE.
const TIER_THRESHOLDS: Array[int] = [-59, -19, 20, 60]
const MIN_RELATION := -100
const MAX_RELATION := 100

## Points per turn each recent event fades toward 0, and wariness moves toward its target,
## by personality.
const DRIFT_PER_TURN: Array[int] = [2, 3, 2, 1]  # PEACEFUL, AGGRESSIVE, MERCHANT, ISOLATED

## Sources of relation changes, remembered separately so the player can see why a clan feels the
## way it does (GDD §9.3). Each fades toward 0 every turn.
const MEMORY_FIRST_IMPRESSION: StringName = &"first_impression"
const MEMORY_GIFT: StringName = &"gift"
const MEMORY_TRADE: StringName = &"trade"
const MEMORY_AGREEMENT: StringName = &"agreement"
const MEMORY_WAR: StringName = &"war"
const MEMORY_AGGRESSION: StringName = &"aggression"
const MEMORY_BATTLE: StringName = &"battle"
const MEMORY_TREATY: StringName = &"treaty"
const MEMORY_EVENT: StringName = &"event"
const MEMORY_AGENT: StringName = &"agent"
const MEMORY_EXPEDITION: StringName = &"expedition"
const MEMORY_OTHER: StringName = &"other"
## Lasting factors in relation_factors(), in display order.
const LASTING_FACTORS: Array[StringName] = [&"base", &"wariness", &"agreement_bonus", &"alliance_bonus", &"pact_bonus"]
## Display names of the lasting factors, the memory sources and the clamp ("limit").
const FACTOR_NAMES: Dictionary[StringName, String] = {
	&"base": "Thiện cảm gốc",
	&"wariness": "E dè vương quốc lớn mạnh",
	&"agreement_bonus": "Đang có hợp đồng giao thương",
	&"alliance_bonus": "Đang liên minh",
	&"pact_bonus": "Đang có hiệp định bất tương xâm",
	&"limit": "Giới hạn −100 → 100",
	&"first_impression": "Ấn tượng ban đầu",
	&"gift": "Quà tặng",
	&"trade": "Giao thương",
	&"agreement": "Chuyện hợp đồng (ký, giao hàng, hủy)",
	&"war": "Chiến tranh với vương quốc",
	&"aggression": "Vương quốc gây chiến với gia tộc khác",
	&"battle": "Trận đánh chung",
	&"treaty": "Bị hủy liên minh / hiệp định",
	&"event": "Sự kiện",
	&"agent": "Đặc vụ",
	&"expedition": "Dẹp loạn đạo tặc",
	&"other": "Khác",
}
## Gift value per relation point before the personality multiplier.
const GIFT_VALUE_PER_POINT := 5
const GIFT_MULTIPLIER: Array[float] = [1.5, 0.6, 1.0, 0.5]
const MAX_GIFT_GAIN_PER_TURN := 15
const TRADE_RELATION_GAIN := 1
const MAX_TRADE_GAIN_PER_TURN := 3
## Total value of goods a clan accepts from the player per turn (stops buy-here-sell-there loops).
const TRADE_CAPACITY_PER_TURN := 40
## Markets make prices at most this much better (GDD §8 M14e).
const MAX_MARKET_PRICE := 0.15
## Clans below this tier refuse to trade.
const MIN_TRADE_TIER := Tier.NEUTRAL

const BASE_PRICE := 0.6
const RELATION_PRICE := 0.2
const MERCHANT_BONUS := 0.15
const DEFICIT_BONUS := 1.4
const SURPLUS_BONUS := 1.3
const DISTANT_PENALTY := 0.85

# Long-term trade agreements (GDD §9.5).
const AGREEMENT_MIN_TURNS := 5
const AGREEMENT_MAX_TURNS := 30
## Most value the player may give per turn under one agreement.
const AGREEMENT_MAX_VALUE := 30
const AGREEMENT_SIGN_GAIN := 8
const AGREEMENT_TURN_GAIN := 1
const AGREEMENT_COMPLETE_GAIN := 3
const AGREEMENT_MISSED_PENALTY := 3
const AGREEMENT_CANCEL_PENALTY := 20
## Added to the relation while an agreement runs.
const AGREEMENT_BASE_BONUS := 15
## Added to the relation while allied with the kingdom (GDD §9.7).
const ALLIANCE_BASE_BONUS := 30
## Added to the relation while a non-aggression pact runs (M16a).
const PACT_BASE_BONUS := 10
## Clans farther than this many steps from the kingdom's territory (GDD §15) cannot trade, take
## gifts, sign agreements or ally with it; only those 1 step away can go to war with it.
const REACH := 2
## How strongly each personality reacts to the kingdom's threat (GDD §9.3):
## PEACEFUL, AGGRESSIVE, MERCHANT, ISOLATED.
const WARINESS: Array[float] = [0.5, 1.0, 0.4, 0.8]
## Most relation wariness can take away (M16a: late in the game the threat kept growing and pushed
## every clan to Hostile whatever the player did).
const MAX_WARINESS := 40
const AGREEMENT_MAX_CHANCE := 0.95
## Added to the acceptance chance, by personality: PEACEFUL, AGGRESSIVE, MERCHANT, ISOLATED.
const AGREEMENT_PERSONALITY: Array[float] = [0.05, -0.1, 0.15, -0.2]
## The Ngoại giao advisor (GDD §8, M11f), per point of `envoy`: better trade prices, likelier
## acceptance (agreements, alliances, peace), less wariness, bigger gift gains.
const ENVOY_PRICE := 0.02
const ENVOY_CHANCE := 0.03
const ENVOY_WARINESS := 0.04
const ENVOY_GIFT := 0.03


## The relation is never stored: it is the sum of lasting factors (base, wariness, treaties) and
## recent events that fade, so the panel can always show where every point comes from (GDD §9.3).
class ClanState:
	extends RefCounted
	var data: ClanData
	## Wariness of the kingdom felt right now (subtracted); moves toward Diplomacy.wariness_target()
	## by DRIFT_PER_TURN each turn.
	var wariness := 0
	## Recent events, source (MEMORY_*) -> relation points. Each fades toward 0 every turn.
	var memories: Dictionary[StringName, int] = {}
	## Running long-term trade agreement, or null.
	var agreement: Agreement
	var relation: int:
		get:
			return clampi(unclamped_relation(), MIN_RELATION, MAX_RELATION)
	var gift_gain_this_turn := 0
	var trade_gain_this_turn := 0
	var traded_value_this_turn := 0
	## A refused or accepted proposal blocks further proposals to this clan until next turn.
	var proposed_this_turn := false
	## Part of the kingdom now (Wars.annex): no more diplomacy.
	var annexed := false
	## Treaties (GDD §9.7, managed by Alliances): turns left, 0 = none.
	var alliance_turns := 0
	## Turns before the clan hears another alliance offer after refusing one.
	var alliance_cooldown := 0
	## Non-aggression pact (M16a): turns left, 0 = none; and turns before another offer.
	var pact_turns := 0
	var pact_cooldown := 0

	func is_allied() -> bool:
		return alliance_turns > 0

	func has_pact() -> bool:
		return pact_turns > 0

	func _init(p_data: ClanData) -> void:
		data = p_data
		if p_data.start_relation != p_data.base_relation:
			memories[MEMORY_FIRST_IMPRESSION] = p_data.start_relation - p_data.base_relation

	## Every lasting factor by id (LASTING_FACTORS), signed.
	func lasting_factors() -> Dictionary[StringName, int]:
		return {&"base": data.base_relation, &"wariness": -wariness,
				&"agreement_bonus": AGREEMENT_BASE_BONUS if agreement != null else 0,
				&"alliance_bonus": ALLIANCE_BASE_BONUS if is_allied() else 0,
				&"pact_bonus": PACT_BASE_BONUS if has_pact() else 0}

	func unclamped_relation() -> int:
		var total := 0
		for amount in lasting_factors().values():
			total += amount
		for amount in memories.values():
			total += amount
		return total


## The player gives `give_amount` of `give_id` and receives `get_amount` of `get_id` every turn.
class Agreement:
	extends RefCounted
	var clan_id: StringName
	var give_id: StringName
	var give_amount: int
	var get_id: StringName
	var get_amount: int
	var total_turns: int
	var turns_left: int


var clans: Dictionary[StringName, ClanState] = {}
## Every running agreement (each lives on its ClanState), in clan order.
var agreements: Array[Agreement]:
	get:
		var result: Array[Agreement] = []
		for clan_id in clans:
			if clans[clan_id].agreement != null:
				result.append(clans[clan_id].agreement)
		return result
## Ngoại giao of the kingdom's working diplomacy advisor, 0 without one (set by KingdomState).
var envoy := 0
## The kingdom's administrative effects (KingdomState.building_effect: effect id -> amount);
## unset in tests that build a Diplomacy alone. Markets: trade_capacity, trade_price.
var admin_effect: Callable
## Extra share of relation from gifts (the diplomacy advisor's items, M12e; set by KingdomState).
var gift_bonus := 0.0
## How threatening the kingdom looks (KingdomState.get_threat()); every clan's wariness grows toward
## it (wariness_target).
var threat := 0
var _trade_values: Dictionary[StringName, int] = {}


func _init(clan_list: Array[ClanData], resource_types: Array[ResourceTypeData]) -> void:
	for clan in clan_list:
		clans[clan.clan_id] = ClanState.new(clan)
	for type in resource_types:
		_trade_values[type.resource_id] = type.trade_value


static func tier_for(relation: int) -> Tier:
	var tier := 0
	for threshold in TIER_THRESHOLDS:
		if relation >= threshold:
			tier += 1
	return tier as Tier


# --- The campaign map (GDD §15) ---------------------------------------------------------

## The squares the kingdom holds: its home corner and every annexed clan.
func territory() -> Array[Vector2i]:
	var result: Array[Vector2i] = [ClanData.HOME]
	for clan_id in clans:
		if clans[clan_id].annexed:
			result.append(clans[clan_id].data.grid)
	return result


## Steps on the campaign map from the kingdom's territory to the clan (0 once annexed).
func distance(clan_id: StringName) -> int:
	var grid := clans[clan_id].data.grid
	var best := ClanData.GRID_SIZE * 2
	for square in territory():
		best = mini(best, ClanData.grid_distance(square, grid))
	return best


## Close enough to trade, give gifts, sign agreements and ally (not annexed).
func in_reach(clan_id: StringName) -> bool:
	return not clans[clan_id].annexed and distance(clan_id) <= REACH


## Next to the kingdom's territory: war can be declared either way, and it can invade.
func borders(clan_id: StringName) -> bool:
	return not clans[clan_id].annexed and distance(clan_id) == 1


## The kingdom board's side facing the clan: from the nearest held square toward it.
func direction_to(clan_id: StringName) -> ClanData.Direction:
	var grid := clans[clan_id].data.grid
	var nearest := ClanData.HOME
	for square in territory():
		if ClanData.grid_distance(square, grid) < ClanData.grid_distance(nearest, grid):
			nearest = square
	return ClanData.direction_of(grid - nearest)


## Clans annexed or allied: they count toward the castle's levels and the victory (GDD §15).
func count_united() -> int:
	var total := 0
	for clan_id in clans:
		if clans[clan_id].annexed or clans[clan_id].is_allied():
			total += 1
	return total


func get_tier(clan_id: StringName) -> Tier:
	return tier_for(clans[clan_id].relation)


## Moves the shown relation by `amount` (within -100..100) and remembers it under `source`
## (MEMORY_*). Points past the limits are dropped so they never sit unseen in the memory; when
## lasting factors already pass a limit, the change starts from the shown value.
func change_relation(clan_id: StringName, amount: int, source: StringName = MEMORY_OTHER) -> void:
	var clan := clans[clan_id]
	var applied := clampi(clan.relation + amount, MIN_RELATION, MAX_RELATION) - clan.unclamped_relation()
	if applied * amount <= 0:  # still held at a limit by the lasting factors
		return
	var remembered: int = clan.memories.get(source, 0) + applied
	if remembered == 0:
		clan.memories.erase(source)
	else:
		clan.memories[source] = remembered
	changed.emit()


## Each turn recent events fade and wariness moves toward the kingdom's current threat, both by
## DRIFT_PER_TURN; per-turn gift, trade and proposal limits reset.
func end_turn() -> void:
	for clan_id in clans:
		var clan := clans[clan_id]
		if clan.annexed:
			continue
		var step: int = DRIFT_PER_TURN[clan.data.personality]
		clan.wariness = int(move_toward(mini(clan.wariness, MAX_WARINESS), wariness_target(clan_id), step))
		for source in clan.memories.keys():
			var left := int(move_toward(clan.memories[source], 0, step))
			if left == 0:
				clan.memories.erase(source)
			else:
				clan.memories[source] = left
		clan.gift_gain_this_turn = 0
		clan.trade_gain_this_turn = 0
		clan.traded_value_this_turn = 0
		clan.proposed_this_turn = false
	changed.emit()


## Relation once every recent event has faded and wariness has caught up with the threat:
## base, lowered by wariness of a strong kingdom, raised while a trade agreement or an alliance runs.
func target_relation(clan_id: StringName) -> int:
	var factors := clans[clan_id].lasting_factors()
	factors[&"wariness"] = -wariness_target(clan_id)
	var target := 0
	for amount in factors.values():
		target += amount
	return clampi(target, MIN_RELATION, MAX_RELATION)


## Wariness the clan's wariness grows (or shrinks) toward: threat x personality factor, at most
## MAX_WARINESS, lowered by the diplomacy advisor; allies feel none.
func wariness_target(clan_id: StringName) -> int:
	if clans[clan_id].is_allied():
		return 0
	var felt := minf(MAX_WARINESS, threat * WARINESS[clans[clan_id].data.personality])
	return roundi(felt * maxf(0.0, 1.0 - envoy * ENVOY_WARINESS))


## Where the relation comes from: [{"id": factor id or MEMORY_*, "amount": signed int,
## "fading": bool}], lasting factors first (zero ones left out), then recent events, largest first.
## The amounts add up to the relation ("limit" covers clamping).
func relation_factors(clan_id: StringName) -> Array[Dictionary]:
	var clan := clans[clan_id]
	var result: Array[Dictionary] = []
	var lasting := clan.lasting_factors()
	for id in LASTING_FACTORS:
		if lasting[id] != 0:
			result.append({"id": id, "amount": lasting[id], "fading": false})
	var recent: Array[Dictionary] = []
	for source in clan.memories:
		recent.append({"id": source, "amount": clan.memories[source], "fading": true})
	recent.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absi(a.amount) > absi(b.amount))
	result.append_array(recent)
	var overflow := clan.relation - clan.unclamped_relation()
	if overflow != 0:
		result.append({"id": &"limit", "amount": overflow, "fading": false})
	return result


func value_of(amounts: Dictionary[StringName, int]) -> int:
	var total := 0
	for resource_id in amounts:
		total += amounts[resource_id] * _trade_values.get(resource_id, 1)
	return total


# --- Gifts --------------------------------------------------------------------------------

## Relation the gift would add right now (after the per-turn limit).
func gift_gain(clan_id: StringName, amounts: Dictionary[StringName, int]) -> int:
	var clan := clans[clan_id]
	var raw := floori(float(value_of(amounts)) / GIFT_VALUE_PER_POINT * GIFT_MULTIPLIER[clan.data.personality]
			* (1.0 + envoy * ENVOY_GIFT + gift_bonus))
	return clampi(raw, 0, MAX_GIFT_GAIN_PER_TURN - clan.gift_gain_this_turn)


func check_gift(stockpile: Stockpile, clan_id: StringName, amounts: Dictionary[StringName, int]) -> GiftResult:
	if clans[clan_id].annexed:
		return GiftResult.ANNEXED
	if not in_reach(clan_id):
		return GiftResult.TOO_FAR
	if value_of(amounts) <= 0:
		return GiftResult.EMPTY
	if clans[clan_id].gift_gain_this_turn >= MAX_GIFT_GAIN_PER_TURN:
		return GiftResult.LIMIT_REACHED
	if not stockpile.can_afford(amounts):
		return GiftResult.CANNOT_AFFORD
	if gift_gain(clan_id, amounts) <= 0:
		return GiftResult.TOO_SMALL
	return GiftResult.OK


## Pays the gift and raises the relation. Nothing happens unless check_gift() is OK.
func give_gift(stockpile: Stockpile, clan_id: StringName, amounts: Dictionary[StringName, int]) -> GiftResult:
	var result := check_gift(stockpile, clan_id, amounts)
	if result != GiftResult.OK:
		return result
	var gain := gift_gain(clan_id, amounts)
	stockpile.spend(amounts)
	clans[clan_id].gift_gain_this_turn += gain
	change_relation(clan_id, gain, MEMORY_GIFT)
	return GiftResult.OK


static func describe_gift(result: GiftResult) -> String:
	match result:
		GiftResult.OK:
			return "Đã tặng quà."
		GiftResult.EMPTY:
			return "Chọn tài nguyên và số lượng để tặng."
		GiftResult.CANNOT_AFFORD:
			return "Không đủ tài nguyên."
		GiftResult.LIMIT_REACHED:
			return "Lượt này họ đã nhận đủ quà (tối đa +%d quan hệ mỗi lượt)." % MAX_GIFT_GAIN_PER_TURN
		GiftResult.ANNEXED:
			return "Gia tộc này đã thuộc về vương quốc."
		GiftResult.TOO_SMALL:
			return "Món quà quá nhỏ, họ sẽ không để ý (quan hệ +0)."
		GiftResult.TOO_FAR:
			return "Quá xa: chỉ qua lại được với gia tộc cách lãnh thổ tối đa %d vùng." % REACH
	return ""


# --- Trade --------------------------------------------------------------------------------

## How generous the clan is when the player gives `give_id` for `get_id`.
func price_factor(clan_id: StringName, give_id: StringName, get_id: StringName) -> float:
	var clan := clans[clan_id]
	var factor := BASE_PRICE + clan.relation / 100.0 * RELATION_PRICE
	if clan.data.personality == ClanData.Personality.MERCHANT:
		factor += MERCHANT_BONUS
	if clan.data.deficit.has(give_id):
		factor *= DEFICIT_BONUS
	if clan.data.surplus.has(get_id):
		factor *= SURPLUS_BONUS
	if distance(clan_id) > 1:
		factor *= DISTANT_PENALTY
	return factor * (1.0 + envoy * ENVOY_PRICE) * (1.0 + minf(MAX_MARKET_PRICE, _admin(&"trade_price")))


## Units of `get_id` the player would receive for `give_amount` of `give_id` (rounded down).
func trade_quote(clan_id: StringName, give_id: StringName, give_amount: int, get_id: StringName) -> int:
	var value: int = give_amount * _trade_values.get(give_id, 1)
	return floori(value * price_factor(clan_id, give_id, get_id) / _trade_values.get(get_id, 1))


func remaining_capacity(clan_id: StringName) -> int:
	return TRADE_CAPACITY_PER_TURN + roundi(_admin(&"trade_capacity")) - clans[clan_id].traded_value_this_turn


func _admin(effect_id: StringName) -> float:
	return admin_effect.call(effect_id) if admin_effect.is_valid() else 0.0


func check_trade(stockpile: Stockpile, clan_id: StringName, give_id: StringName, give_amount: int,
		get_id: StringName) -> TradeResult:
	if not clans[clan_id].annexed and not in_reach(clan_id):
		return TradeResult.TOO_FAR
	if clans[clan_id].annexed or get_tier(clan_id) < MIN_TRADE_TIER:
		return TradeResult.REFUSED
	if give_id == get_id:
		return TradeResult.SAME_RESOURCE
	if give_amount <= 0:
		return TradeResult.EMPTY
	if stockpile.get_amount(give_id) < give_amount:
		return TradeResult.CANNOT_AFFORD
	if give_amount * _trade_values.get(give_id, 1) > remaining_capacity(clan_id):
		return TradeResult.OVER_CAPACITY
	if trade_quote(clan_id, give_id, give_amount, get_id) <= 0:
		return TradeResult.TOO_SMALL
	return TradeResult.OK


## Swaps the goods and nudges the relation up. Nothing happens unless check_trade() is OK.
func trade(stockpile: Stockpile, clan_id: StringName, give_id: StringName, give_amount: int,
		get_id: StringName) -> TradeResult:
	var result := check_trade(stockpile, clan_id, give_id, give_amount, get_id)
	if result != TradeResult.OK:
		return result
	var received := trade_quote(clan_id, give_id, give_amount, get_id)
	stockpile.spend({give_id: give_amount})
	stockpile.add({get_id: received})
	var clan := clans[clan_id]
	clan.traded_value_this_turn += give_amount * _trade_values.get(give_id, 1)
	if clan.trade_gain_this_turn < MAX_TRADE_GAIN_PER_TURN:
		clan.trade_gain_this_turn += TRADE_RELATION_GAIN
		change_relation(clan_id, TRADE_RELATION_GAIN, MEMORY_TRADE)
	else:
		changed.emit()
	return TradeResult.OK


static func describe_trade(result: TradeResult) -> String:
	match result:
		TradeResult.OK:
			return "Giao dịch thành công."
		TradeResult.REFUSED:
			return "Họ từ chối giao thương khi quan hệ đang căng thẳng."
		TradeResult.SAME_RESOURCE:
			return "Chọn hai loại tài nguyên khác nhau."
		TradeResult.EMPTY:
			return "Chọn số lượng muốn đưa."
		TradeResult.CANNOT_AFFORD:
			return "Không đủ tài nguyên."
		TradeResult.OVER_CAPACITY:
			return "Lượt này họ không nhận thêm nhiều hàng như vậy."
		TradeResult.TOO_SMALL:
			return "Số lượng quá ít để đổi được gì."
		TradeResult.TOO_FAR:
			return "Quá xa: chỉ qua lại được với gia tộc cách lãnh thổ tối đa %d vùng." % REACH
	return ""


# --- Long-term agreements -----------------------------------------------------------------

func get_agreement(clan_id: StringName) -> Agreement:
	return clans[clan_id].agreement


## Ends the clan's agreement without any relation change (war, annexation).
func remove_agreement(clan_id: StringName) -> void:
	clans[clan_id].agreement = null
	changed.emit()


## Chance (0..AGREEMENT_MAX_CHANCE) that the clan signs. Asking for less than the fair amount
## (what they would pay in a one-off trade) makes it likelier; asking for more makes it harder.
func agreement_chance(clan_id: StringName, give_id: StringName, give_amount: int, get_id: StringName,
		get_amount: int) -> float:
	var fair := trade_quote(clan_id, give_id, give_amount, get_id)
	if fair <= 0 or get_amount <= 0:
		return 0.0
	var clan := clans[clan_id]
	var chance := 1.5 - float(get_amount) / fair + clan.relation / 200.0 + AGREEMENT_PERSONALITY[clan.data.personality] \
			+ envoy * ENVOY_CHANCE
	return clampf(chance, 0.0, AGREEMENT_MAX_CHANCE)


static func chance_name(chance: float) -> String:
	if chance >= 0.8:
		return "Rất có thể"
	if chance >= 0.55:
		return "Có thể"
	if chance >= 0.3:
		return "Khó"
	if chance > 0.0:
		return "Rất khó"
	return "Không thể"


func check_proposal(clan_id: StringName, give_id: StringName, give_amount: int, get_id: StringName,
		get_amount: int, turns: int) -> ProposalResult:
	if not clans[clan_id].annexed and not in_reach(clan_id):
		return ProposalResult.TOO_FAR
	if clans[clan_id].annexed or get_tier(clan_id) < MIN_TRADE_TIER:
		return ProposalResult.REFUSED
	if get_agreement(clan_id) != null:
		return ProposalResult.ALREADY_HAS
	if clans[clan_id].proposed_this_turn:
		return ProposalResult.ASKED_THIS_TURN
	if give_id == get_id:
		return ProposalResult.SAME_RESOURCE
	if give_amount <= 0 or get_amount <= 0:
		return ProposalResult.EMPTY
	if give_amount * _trade_values.get(give_id, 1) > AGREEMENT_MAX_VALUE:
		return ProposalResult.TOO_LARGE
	if turns < AGREEMENT_MIN_TURNS or turns > AGREEMENT_MAX_TURNS:
		return ProposalResult.BAD_DURATION
	return ProposalResult.OK


## Sends the offer. The clan accepts with agreement_chance(); either way it will not hear another
## offer until next turn. Signing raises the relation at once.
func propose(rng: RandomNumberGenerator, clan_id: StringName, give_id: StringName, give_amount: int,
		get_id: StringName, get_amount: int, turns: int) -> ProposalResult:
	var result := check_proposal(clan_id, give_id, give_amount, get_id, get_amount, turns)
	if result != ProposalResult.OK:
		return result
	clans[clan_id].proposed_this_turn = true
	if rng.randf() >= agreement_chance(clan_id, give_id, give_amount, get_id, get_amount):
		changed.emit()
		return ProposalResult.DECLINED
	var agreement := Agreement.new()
	agreement.clan_id = clan_id
	agreement.give_id = give_id
	agreement.give_amount = give_amount
	agreement.get_id = get_id
	agreement.get_amount = get_amount
	agreement.total_turns = turns
	agreement.turns_left = turns
	clans[clan_id].agreement = agreement
	change_relation(clan_id, AGREEMENT_SIGN_GAIN, MEMORY_AGREEMENT)
	return ProposalResult.OK


## The player breaks the agreement early: big relation penalty.
func cancel_agreement(clan_id: StringName) -> void:
	var agreement := get_agreement(clan_id)
	if agreement == null:
		return
	clans[clan_id].agreement = null
	change_relation(clan_id, -AGREEMENT_CANCEL_PENALTY, MEMORY_AGREEMENT)


## Runs every agreement for one turn. Returns one entry per agreement:
## {"clan_id", "agreement", "event": &"delivered" | &"missed" | &"cancelled_by_clan", "completed": bool}.
func run_agreements(stockpile: Stockpile) -> Array[Dictionary]:
	var report: Array[Dictionary] = []
	for agreement in agreements:
		var entry := {"clan_id": agreement.clan_id, "agreement": agreement, "completed": false}
		report.append(entry)
		if get_tier(agreement.clan_id) == Tier.HOSTILE:
			clans[agreement.clan_id].agreement = null
			entry["event"] = &"cancelled_by_clan"
			continue
		var payment: Dictionary[StringName, int] = {agreement.give_id: agreement.give_amount}
		if stockpile.spend(payment):
			var delivery: Dictionary[StringName, int] = {agreement.get_id: agreement.get_amount}
			stockpile.add(delivery)
			change_relation(agreement.clan_id, AGREEMENT_TURN_GAIN, MEMORY_AGREEMENT)
			entry["event"] = &"delivered"
		else:
			change_relation(agreement.clan_id, -AGREEMENT_MISSED_PENALTY, MEMORY_AGREEMENT)
			entry["event"] = &"missed"
		agreement.turns_left -= 1
		if agreement.turns_left <= 0:
			clans[agreement.clan_id].agreement = null
			change_relation(agreement.clan_id, AGREEMENT_COMPLETE_GAIN, MEMORY_AGREEMENT)
			entry["completed"] = true
	return report


static func describe_proposal(result: ProposalResult) -> String:
	match result:
		ProposalResult.OK:
			return "Họ đồng ý ký hợp đồng!"
		ProposalResult.DECLINED:
			return "Họ từ chối đề nghị. Hãy thử lại vào lượt sau."
		ProposalResult.REFUSED:
			return "Họ không muốn làm ăn khi quan hệ đang căng thẳng."
		ProposalResult.SAME_RESOURCE:
			return "Chọn hai loại tài nguyên khác nhau."
		ProposalResult.EMPTY:
			return "Chọn số lượng đưa và nhận mỗi lượt."
		ProposalResult.TOO_LARGE:
			return "Hợp đồng tối đa %d giá trị hàng mỗi lượt." % AGREEMENT_MAX_VALUE
		ProposalResult.BAD_DURATION:
			return "Thời hạn từ %d đến %d lượt." % [AGREEMENT_MIN_TURNS, AGREEMENT_MAX_TURNS]
		ProposalResult.ALREADY_HAS:
			return "Đã có hợp đồng với gia tộc này."
		ProposalResult.ASKED_THIS_TURN:
			return "Họ cần thời gian cân nhắc. Hãy đề nghị lại vào lượt sau."
		ProposalResult.TOO_FAR:
			return "Quá xa: chỉ qua lại được với gia tộc cách lãnh thổ tối đa %d vùng." % REACH
	return ""


# --- Save (GDD §10.1) ---------------------------------------------------------------------

## ClanState fields written as they are (ints and bools); add new plain fields here.
const SAVED_CLAN_FIELDS: Array[StringName] = [&"wariness", &"gift_gain_this_turn", &"trade_gain_this_turn",
		&"traded_value_this_turn", &"proposed_this_turn", &"annexed", &"alliance_turns",
		&"alliance_cooldown", &"pact_turns", &"pact_cooldown"]
const SAVED_AGREEMENT_FIELDS: Array[StringName] = [&"give_amount", &"get_amount", &"total_turns", &"turns_left"]


func to_save() -> Dictionary:
	var saved_clans := {}
	for clan_id in clans:
		var clan := clans[clan_id]
		var entry := {}
		for field in SAVED_CLAN_FIELDS:
			entry[String(field)] = clan.get(field)
		var memories := {}
		for source in clan.memories:
			memories[String(source)] = clan.memories[source]
		entry["memories"] = memories
		if clan.agreement != null:
			var agreement := {"give_id": String(clan.agreement.give_id), "get_id": String(clan.agreement.get_id)}
			for field in SAVED_AGREEMENT_FIELDS:
				agreement[String(field)] = clan.agreement.get(field)
			entry["agreement"] = agreement
		saved_clans[String(clan_id)] = entry
	return {"threat": threat, "clans": saved_clans}


## Clans missing from the save keep their starting state; saved clans no longer in the data are skipped.
func load_save(data: Dictionary) -> void:
	threat = int(data.threat)
	for clan_name: String in data.clans:
		var clan: ClanState = clans.get(StringName(clan_name))
		if clan == null:
			continue
		var entry: Dictionary = data.clans[clan_name]
		for field in SAVED_CLAN_FIELDS:
			if entry.has(String(field)):
				clan.set(field, _plain(entry[String(field)], clan.get(field)))
		clan.wariness = mini(clan.wariness, MAX_WARINESS)
		clan.memories.clear()
		for source: String in entry.memories:
			clan.memories[StringName(source)] = int(entry.memories[source])
		clan.agreement = null
		if entry.has("agreement"):
			var saved: Dictionary = entry.agreement
			var agreement := Agreement.new()
			agreement.clan_id = clan.data.clan_id
			agreement.give_id = StringName(saved.give_id)
			agreement.get_id = StringName(saved.get_id)
			for field in SAVED_AGREEMENT_FIELDS:
				agreement.set(field, int(saved[String(field)]))
			clan.agreement = agreement
	changed.emit()


## JSON numbers come back as floats: give a loaded value the type of the field it replaces.
static func _plain(value: Variant, current: Variant) -> Variant:
	if current is bool:
		return bool(value)
	if current is int:
		return int(value)
	return value
