class_name RaidPressure
extends RefCounted
## Timed changes to the chance of a bandit raid (GDD §21, M16e), left by the bandit leader's
## challenge: beating them scares the bandits off, shutting the gate on them draws more raids.
## Owned by KingdomState (saved). Each entry is {"factor": float, "turns": int}; factors multiply.

## A raid chance raised by pressure never goes above this.
const MAX_CHANCE := 0.9

var entries: Array[Dictionary] = []


func add(factor: float, turns: int) -> void:
	entries.append({"factor": factor, "turns": turns})


## The product of every active factor (1.0 when none).
func factor() -> float:
	var result := 1.0
	for entry in entries:
		result *= entry.factor
	return result


## `chance` changed by the active factors.
func apply(chance: float) -> float:
	var changed := chance * factor()
	return minf(changed, maxf(chance, MAX_CHANCE))


## End of a turn: every entry runs down.
func end_turn() -> void:
	for entry in entries:
		entry.turns -= 1
	entries = entries.filter(func(entry: Dictionary) -> bool: return entry.turns > 0)


## "Trong 5 lượt: đạo tặc đến cướp nhiều hơn (×2)" and the like.
static func describe(entry_factor: float, turns: int) -> String:
	var more := entry_factor > 1.0
	return "Trong %d lượt: đạo tặc đến cướp %s (×%s)" % [turns, "nhiều hơn" if more else "ít hơn",
			("%.1f" % entry_factor).trim_suffix(".0")]


func to_save() -> Array:
	return entries.map(func(entry: Dictionary) -> Dictionary: return entry.duplicate())


func load_save(data: Array) -> void:
	entries.clear()
	for entry: Dictionary in data:
		entries.append({"factor": float(entry.factor), "turns": int(entry.turns)})
