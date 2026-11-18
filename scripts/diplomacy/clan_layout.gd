class_name ClanLayout
extends RefCounted
## A new game's shuffled campaign map (GDD §31 M18d, §32 M18e). `roll` puts the kingdom's home on
## a random edge square of the ClanData.GRID_SIZE grid and deals the clans onto the other squares;
## a square's strength (STRENGTH_BY_DISTANCE ±STRENGTH_SPREAD) and army (ARMY_TIERS) come from its
## distance to home, so close squares stay weak. Personalities are shuffled (same counts, a
## peaceful clan next to home), surplus / deficit goods are rolled and friends are paired again
## among bordering clans. The layout is JSON-safe data saved with the game
## (KingdomState.clan_layout); `apply` sets Diplomacy.home and gives every ClanState its own copy
## of the ClanData with the layout's values.
##
## Layout: {"home": [x, y], "clans": {clan_id (String): {"grid": [x, y], "personality": int,
## "strength": int, "army": {unit_id: weight}, "surplus": [id], "deficit": [id], "friends": [clan_id]}}}.

const STRENGTH_SPREAD := 0.2
const STRENGTH_STEP := 5
## Soldiers by steps from home (index = distance; 6×6 from an edge square: 1..10).
const STRENGTH_BY_DISTANCE: Array[int] = [0, 45, 65, 95, 140, 180, 240, 300, 380, 430, 480]
## Clan armies by distance: 1–2 peasants, 3–4 elite, 5–6 royal, 7+ royal with heavy cavalry and artillery.
const ARMY_TIER_FROM: Array[int] = [1, 3, 5, 7]
const ARMY_TIERS: Array[Dictionary] = [
	{"swordsman": 3.0, "spearman": 2.0, "archer": 2.0},
	{"swordsman": 1.0, "spearman": 1.0, "archer": 1.0, "elite_swordsman": 2.0, "elite_spearman": 2.0,
			"elite_archer": 2.0, "shield_veteran": 1.0, "crossbow_pro": 1.0, "light_cavalry": 1.0},
	{"elite_swordsman": 1.0, "elite_spearman": 1.0, "royal_swordguard": 2.0, "royal_pikeguard": 2.0,
			"marksman_archer": 2.0, "crossbow_elite": 1.0, "lancer_cavalry": 1.0, "elite_musketeer": 1.0,
			"light_artillery": 1.0, "shield_guard": 1.0},
	{"royal_swordguard": 2.0, "royal_pikeguard": 2.0, "marksman_archer": 2.0, "crossbow_elite": 1.0,
			"heavy_cavalry": 2.0, "elite_musketeer": 2.0, "heavy_artillery": 1.0, "shield_guard": 1.0},
]
## Start / base relation by ClanData.Personality.
const RELATIONS: Array[Vector2i] = [Vector2i(20, 25), Vector2i(-10, -15), Vector2i(10, 15), Vector2i(-5, 0)]
## Goods a clan may have in surplus or lack.
const GOODS: Array[StringName] = [&"food", &"wood", &"stone", &"ore", &"hardwood", &"horses"]
const MAX_FRIENDS := 2


## The squares on the map's edge (where home may be).
static func edge_squares() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var last := ClanData.GRID_SIZE - 1
	for y in ClanData.GRID_SIZE:
		for x in ClanData.GRID_SIZE:
			if x == 0 or y == 0 or x == last or y == last:
				result.append(Vector2i(x, y))
	return result


static func strength_at(distance: int) -> int:
	return STRENGTH_BY_DISTANCE[clampi(distance, 1, STRENGTH_BY_DISTANCE.size() - 1)]


static func army_at(distance: int) -> Dictionary:
	var tier := 0
	for i in ARMY_TIER_FROM.size():
		if distance >= ARMY_TIER_FROM[i]:
			tier = i
	return ARMY_TIERS[tier].duplicate()


## Needs one clan for every square but home (GRID_SIZE² − 1).
static func roll(clans: Array[ClanData], rng: RandomNumberGenerator) -> Dictionary:
	var edges := edge_squares()
	var home := edges[rng.randi_range(0, edges.size() - 1)]
	var squares: Array[Vector2i] = []
	for y in ClanData.GRID_SIZE:
		for x in ClanData.GRID_SIZE:
			if Vector2i(x, y) != home:
				squares.append(Vector2i(x, y))
	assert(squares.size() == clans.size(), "One clan per square")
	_shuffle(squares, rng)
	var personalities: Array[int] = []
	var pairs := 0
	for clan in clans:
		personalities.append(clan.personality)
		pairs += clan.friends.size()
	_shuffle(personalities, rng)
	_peaceful_near_home(squares, home, personalities, rng)
	var entries := {}
	for i in clans.size():
		var square := squares[i]
		var distance := ClanData.grid_distance(square, home)
		var spread := rng.randf_range(1.0 - STRENGTH_SPREAD, 1.0 + STRENGTH_SPREAD)
		var surplus := GOODS[rng.randi_range(0, GOODS.size() - 1)]
		var deficit := surplus
		while deficit == surplus:
			deficit = GOODS[rng.randi_range(0, GOODS.size() - 1)]
		entries[String(clans[i].clan_id)] = {"grid": [square.x, square.y], "personality": personalities[i],
				"strength": maxi(STRENGTH_STEP, roundi(strength_at(distance) * spread / STRENGTH_STEP) * STRENGTH_STEP),
				"army": army_at(distance), "surplus": [String(surplus)], "deficit": [String(deficit)], "friends": []}
	_pair_friends(entries, pairs / 2, rng)
	return {"home": [home.x, home.y], "clans": entries}


## Gives every clan in `diplomacy` a copy of its data with the layout's values. An empty layout
## (older saves, tests) keeps the fixed map.
static func apply(diplomacy: Diplomacy, layout: Dictionary) -> void:
	if layout.is_empty():
		return
	diplomacy.home = Vector2i(int(layout.home[0]), int(layout.home[1]))
	var entries: Dictionary = layout.get("clans", {})
	for clan_id in diplomacy.clans:
		var entry: Dictionary = entries.get(String(clan_id), {})
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
static func _peaceful_near_home(squares: Array[Vector2i], home: Vector2i, personalities: Array[int],
		rng: RandomNumberGenerator) -> void:
	var near: Array[int] = []
	for i in squares.size():
		if ClanData.grid_distance(squares[i], home) == 1:
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
