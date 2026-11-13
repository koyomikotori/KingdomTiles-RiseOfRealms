class_name Tribute
extends RefCounted
## The kingdom demands tribute from a much weaker neighbor (M18c, GDD §9.8): one lump of goods
## from what the clan has in surplus, with a chance to accept that grows with how much stronger
## the kingdom is. Accepting or refusing both cost relation; the clan cannot be asked again for
## COOLDOWN_TURNS turns. Stateless: everything goes through the KingdomState passed in.

enum Result { OK, ANNEXED, NOT_NEIGHBOR, AT_WAR, ALLIED, NOT_WEAK, COOLDOWN }

## The kingdom's soldiers must be at least this many times the clan's.
const MIN_RATIO := 2.0
const BASE_CHANCE := 0.35
## Extra chance per step of ratio past MIN_RATIO.
const CHANCE_PER_RATIO := 0.15
const MAX_CHANCE := 0.9
## By ClanData.Personality: peaceful, aggressive, merchant, isolated.
const PERSONALITY_CHANCE: Array[float] = [0.1, -0.15, 0.05, -0.05]
## Trade value of the lump: BASE_VALUE + VALUE_PER_SOLDIER × the clan's soldiers.
const BASE_VALUE := 40
const VALUE_PER_SOLDIER := 0.25
## Paid in these when the clan has no surplus.
const FALLBACK_GOODS: Array[StringName] = [&"food", &"wood", &"stone"]
const ACCEPT_RELATION := -15
const REFUSE_RELATION := -10
## Every other clan grows a little warier when one pays.
const OTHERS_RELATION := -3
const COOLDOWN_TURNS := 10


## How many times stronger the kingdom is than the clan (soldiers).
static func ratio(state: KingdomState, clan_id: StringName) -> float:
	return state.army.count_soldiers() / maxf(1.0, state.wars.fronts[clan_id].strength)


static func check(state: KingdomState, clan_id: StringName) -> Result:
	var clan := state.diplomacy.clans[clan_id]
	if clan.annexed:
		return Result.ANNEXED
	if not state.wars.is_neighbor(clan_id):
		return Result.NOT_NEIGHBOR
	if state.wars.at_war_with(clan_id):
		return Result.AT_WAR
	if clan.is_allied():
		return Result.ALLIED
	if clan.tribute_cooldown > 0:
		return Result.COOLDOWN
	if ratio(state, clan_id) < MIN_RATIO:
		return Result.NOT_WEAK
	return Result.OK


static func chance(state: KingdomState, clan_id: StringName) -> float:
	var personality := state.diplomacy.clans[clan_id].data.personality
	var value := minf(MAX_CHANCE, BASE_CHANCE + CHANCE_PER_RATIO * maxf(0.0, ratio(state, clan_id) - MIN_RATIO))
	return clampf(value + PERSONALITY_CHANCE[personality], 0.05, 0.95)


## What the clan would pay: its surplus goods (or FALLBACK_GOODS), the value split evenly.
static func amounts(state: KingdomState, clan_id: StringName) -> Dictionary[StringName, int]:
	var goods: Array[StringName] = []
	for resource_id in state.diplomacy.clans[clan_id].data.surplus:
		if _trade_value(resource_id) > 0:
			goods.append(resource_id)
	if goods.is_empty():
		goods.assign(FALLBACK_GOODS)
	var value := BASE_VALUE + state.wars.fronts[clan_id].strength * VALUE_PER_SOLDIER
	var result: Dictionary[StringName, int] = {}
	for resource_id in goods:
		result[resource_id] = maxi(1, roundi(value / goods.size() / _trade_value(resource_id)))
	return result


static func _trade_value(resource_id: StringName) -> int:
	for type in ResourceTypeData.load_all():
		if type.resource_id == resource_id:
			return type.trade_value
	return 0


## Makes the demand. Returns {"result": Result, "accepted": bool, "amounts"}; nothing changes
## unless check() is OK.
static func demand(state: KingdomState, clan_id: StringName, rng: RandomNumberGenerator) -> Dictionary:
	var result := check(state, clan_id)
	if result != Result.OK:
		return {"result": result, "accepted": false, "amounts": {}}
	var diplomacy := state.diplomacy
	var goods := amounts(state, clan_id)
	var accepted := rng.randf() < chance(state, clan_id)
	diplomacy.clans[clan_id].tribute_cooldown = COOLDOWN_TURNS
	if accepted:
		state.stockpile.add(goods)
		diplomacy.change_relation(clan_id, ACCEPT_RELATION, Diplomacy.MEMORY_TRIBUTE)
		for other in diplomacy.clans:
			if other != clan_id and not diplomacy.clans[other].annexed:
				diplomacy.change_relation(other, OTHERS_RELATION, Diplomacy.MEMORY_AGGRESSION)
	else:
		diplomacy.change_relation(clan_id, REFUSE_RELATION, Diplomacy.MEMORY_TRIBUTE)
	return {"result": result, "accepted": accepted, "amounts": goods if accepted else {}}


static func describe(result: Result) -> String:
	match result:
		Result.ANNEXED:
			return "Gia tộc này đã thuộc về vương quốc."
		Result.NOT_NEIGHBOR:
			return "Chỉ đòi cống nạp được gia tộc giáp ranh."
		Result.AT_WAR:
			return "Đang có chiến tranh."
		Result.ALLIED:
			return "Không thể đòi cống nạp đồng minh."
		Result.COOLDOWN:
			return "Vừa đòi gần đây, phải đợi thêm ít lâu."
		Result.NOT_WEAK:
			return "Quân ta phải đông gấp %d lần quân họ thì họ mới sợ." % roundi(MIN_RATIO)
	return ""
