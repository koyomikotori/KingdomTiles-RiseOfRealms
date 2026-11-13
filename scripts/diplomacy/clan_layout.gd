class_name ClanLayout
extends RefCounted
## A new game's shuffled campaign map (GDD §31, M18d). `roll` deals the clans onto the squares
## of the fixed map: each square keeps its own strength (±STRENGTH_SPREAD) and army, so close
## squares stay weak; personalities are shuffled (same counts, a peaceful clan next to home),
## surplus / deficit goods are rolled and friends are paired again among bordering clans.
## The layout is JSON-safe data saved with the game (KingdomState.clan_layout); `apply` gives
## every ClanState its own copy of the ClanData with the layout's values.
##
## Layout: {clan_id (String): {"grid": [x, y], "personality": int, "strength": int,
## "army": {unit_id: weight}, "surplus": [id], "deficit": [id], "friends": [clan_id]}}.

const STRENGTH_SPREAD := 0.2
const STRENGTH_STEP := 5
## Start / base relation by ClanData.Personality.
const RELATIONS: Array[Vector2i] = [Vector2i(20, 25), Vector2i(-10, -15), Vector2i(10, 15), Vector2i(-5, 0)]
## Goods a clan may have in surplus or lack.
const GOODS: Array[StringName] = [&"food", &"wood", &"stone", &"ore", &"hardwood", &"horses"]
const MAX_FRIENDS := 2


static func roll(clans: Array[ClanData], rng: RandomNumberGenerator) -> Dictionary:
	var slots: Array[ClanData] = clans.duplicate()
	_shuffle(slots, rng)
	var personalities: Array[int] = []
	var pairs := 0
	for clan in clans:
		personalities.append(clan.personality)
		pairs += clan.friends.size()
	_shuffle(personalities, rng)
	_peaceful_near_home(slots, personalities, rng)
	var layout := {}
	for i in clans.size():
		var slot := slots[i]
		var spread := rng.randf_range(1.0 - STRENGTH_SPREAD, 1.0 + STRENGTH_SPREAD)
		var surplus := GOODS[rng.randi_range(0, GOODS.size() - 1)]
		var deficit := surplus
		while deficit == surplus:
			deficit = GOODS[rng.randi_range(0, GOODS.size() - 1)]
		var army := {}
		for unit_id in slot.army_units:
			army[String(unit_id)] = slot.army_units[unit_id]
		layout[String(clans[i].clan_id)] = {"grid": [slot.grid.x, slot.grid.y], "personality": personalities[i],
				"strength": maxi(STRENGTH_STEP, roundi(slot.military_strength * spread / STRENGTH_STEP) * STRENGTH_STEP),
				"army": army, "surplus": [String(surplus)], "deficit": [String(deficit)], "friends": []}
	_pair_friends(layout, pairs / 2, rng)
	return layout


## Gives every clan in `diplomacy` a copy of its data with the layout's values. An empty layout
## (older saves, tests) keeps the fixed map.
static func apply(diplomacy: Diplomacy, layout: Dictionary) -> void:
	for clan_id in diplomacy.clans:
		var entry: Dictionary = layout.get(String(clan_id), {})
		if entry.is_empty():
			continue
		var clan := diplomacy.clans[clan_id]
		var data: ClanData = clan.data.duplicate()
		data.grid = Vector2i(int(entry.grid[0]), int(entry.grid[1]))
		data.personality = clampi(int(entry.personality), 0, RELATIONS.size() - 1) as ClanData.Personality
		data.military_strength = int(entry.strength)
		var army: Dictionary[StringName, float] = {}
		for unit_id in entry.army:
			army[StringName(unit_id)] = float(entry.army[unit_id])
		data.army_units = army
		data.surplus = _names(entry.surplus)
		data.deficit = _names(entry.deficit)
		data.friends = _names(entry.friends)
		data.start_relation = RELATIONS[data.personality].x
		data.base_relation = RELATIONS[data.personality].y
		clan.data = data
		clan.memories.erase(Diplomacy.MEMORY_FIRST_IMPRESSION)
		if data.start_relation != data.base_relation:
			clan.memories[Diplomacy.MEMORY_FIRST_IMPRESSION] = data.start_relation - data.base_relation


## At least one of the clans bordering home is peaceful: swaps a peaceful personality in if not.
static func _peaceful_near_home(slots: Array[ClanData], personalities: Array[int], rng: RandomNumberGenerator) -> void:
	var near: Array[int] = []
	for i in slots.size():
		if slots[i].ring() == 1:
			if personalities[i] == ClanData.Personality.PEACEFUL:
				return
			near.append(i)
	var peaceful := personalities.find(ClanData.Personality.PEACEFUL)
	if near.is_empty() or peaceful < 0:
		return
	var target := near[rng.randi_range(0, near.size() - 1)]
	personalities[peaceful] = personalities[target]
	personalities[target] = ClanData.Personality.PEACEFUL


## Pairs up to `count` friends among bordering clans that are not isolated, at most MAX_FRIENDS each.
static func _pair_friends(layout: Dictionary, count: int, rng: RandomNumberGenerator) -> void:
	var ids: Array = layout.keys()
	ids.sort()
	var candidates: Array[Vector2i] = []
	for a in ids.size():
		for b in range(a + 1, ids.size()):
			var first: Dictionary = layout[ids[a]]
			var second: Dictionary = layout[ids[b]]
			if first.personality == ClanData.Personality.ISOLATED or second.personality == ClanData.Personality.ISOLATED:
				continue
			var offset := Vector2i(first.grid[0] - second.grid[0], first.grid[1] - second.grid[1])
			if absi(offset.x) + absi(offset.y) == 1:
				candidates.append(Vector2i(a, b))
	_shuffle(candidates, rng)
	var made := 0
	for pair in candidates:
		if made >= count:
			break
		var first: Array = layout[ids[pair.x]].friends
		var second: Array = layout[ids[pair.y]].friends
		if first.size() >= MAX_FRIENDS or second.size() >= MAX_FRIENDS:
			continue
		first.append(ids[pair.y])
		second.append(ids[pair.x])
		made += 1


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = items[i]
		items[i] = items[j]
		items[j] = swap


static func _names(values: Array) -> Array[StringName]:
	var result: Array[StringName] = []
	for value in values:
		result.append(StringName(value))
	return result
