class_name MoraleEffects
extends RefCounted
## Lasting changes to the starting morale ("nhuệ khí tối đa") of the kingdom's army or its enemies
## (GDD §21, M16e), left by events: a duel won or lost, a refused challenge, a stolen letter, an
## agent's warning. Owned by KingdomState (saved). Each entry is
## {"side": KINGDOM | ENEMY, "amount": int, "clan_id": StringName (&"" = every battle,
##  ClanOfficers.BANDITS = raids and other battles against bandits),
##  "turns": int (> 0: every matching battle for that many more turns; ONCE: the next matching
##  battle only)}.
## Expedition battles are not touched.

enum { KINGDOM, ENEMY }

const ONCE := -1
## Morale never drops below this at the start of a battle.
const MIN_MORALE := 1.0

var entries: Array[Dictionary] = []


## `turns` 0 = the next battle against `clan_id` (any battle when &"") only.
func add(side: int, amount: int, clan_id: StringName = &"", turns: int = 0) -> void:
	entries.append({"side": side, "amount": amount, "clan_id": clan_id, "turns": turns if turns > 0 else ONCE})


func _matches(entry: Dictionary, clan_id: StringName) -> bool:
	return entry.clan_id == &"" or entry.clan_id == clan_id


## The total change for `side` in a battle against `clan_id` (ClanOfficers.BANDITS for bandits).
func total(side: int, clan_id: StringName) -> int:
	var sum := 0
	for entry in entries:
		if entry.side == side and _matches(entry, clan_id):
			sum += entry.amount
	return sum


## Changes the starting morale of both sides' own units (not lent ones) for a battle against
## `clan_id`. Either side may be null.
func apply(kingdom_side: BattleSide, enemy_side: BattleSide, clan_id: StringName) -> void:
	for pair: Array in [[kingdom_side, KINGDOM], [enemy_side, ENEMY]]:
		var side: BattleSide = pair[0]
		var amount := total(pair[1], clan_id)
		if side == null or amount == 0:
			continue
		for unit in side.units:
			if unit.ally == null:
				unit.morale = maxf(MIN_MORALE, unit.morale + amount)


## After a battle against `clan_id`: the one-battle entries that applied are used up.
func after_battle(clan_id: StringName) -> void:
	entries = entries.filter(func(entry: Dictionary) -> bool: return entry.turns != ONCE or not _matches(entry, clan_id))


## End of a turn: timed entries run down.
func end_turn() -> void:
	for entry in entries:
		if entry.turns > 0:
			entry.turns -= 1
	entries = entries.filter(func(entry: Dictionary) -> bool: return entry.turns != 0)


func to_save() -> Array:
	var saved: Array = []
	for entry in entries:
		saved.append({"side": entry.side, "amount": entry.amount, "clan_id": String(entry.clan_id), "turns": entry.turns})
	return saved


func load_save(data: Array) -> void:
	entries.clear()
	for entry: Dictionary in data:
		entries.append({"side": int(entry.side), "amount": int(entry.amount), "clan_id": StringName(entry.clan_id),
				"turns": int(entry.turns)})
