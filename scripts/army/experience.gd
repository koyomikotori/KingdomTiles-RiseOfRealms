class_name Experience
extends RefCounted
## Experience rules for squads and generals (GDD §8, M11e).
## Squads: 3 levels by XP per soldier, from battles and barracks training (training stops at
## Veteran); new soldiers join with 0 XP and dilute the squad's average (Army.add_soldiers).
## Generals: only the commander who led a battle gains XP; each level gives 1 point the player
## adds to Võ lực or Thống suất (Generals.spend_point).

## XP a squad needs for each level: Recruit, Veteran, Elite.
const SQUAD_LEVEL_XP: Array[float] = [0.0, 100.0, 300.0]
const SQUAD_LEVEL_NAMES: Array[String] = ["Tân binh", "Cựu binh", "Tinh nhuệ"]
## Short marks for tight spaces (army list, battle screen).
const SQUAD_LEVEL_MARKS: Array[String] = ["", "▲", "▲▲"]
## Per level: melee attack (range attack for ranged units), melee defense and morale.
const SQUAD_LEVEL_BONUS := 2
## Every squad that is still with the kingdom after a battle.
const SQUAD_BATTLE_XP := 20.0
const SQUAD_KILL_XP := 2.0
const SQUAD_WIN_XP := 20.0
## Per turn with at least one barracks, up to TRAINING_MAX_LEVEL.
const TRAINING_XP := 10.0
const TRAINING_MAX_LEVEL := 1
## Every finished barracks adds this much training a turn for each level above 1 (M18f-a balance).
const TRAINING_XP_PER_LEVEL := 1.0
## A barracks at this level trains squads on to the top level, at ELITE_TRAINING_SHARE speed.
const ELITE_TRAINING_LEVEL := 6
const ELITE_TRAINING_SHARE := 0.5

## Generals start at level 1 and reach at most GENERAL_BASE_MAX_LEVEL + stars.
const GENERAL_BASE_MAX_LEVEL := 2
## XP to go from level N to N + 1 is GENERAL_XP_PER_LEVEL × N.
const GENERAL_XP_PER_LEVEL := 100
const GENERAL_BATTLE_XP := 30
const GENERAL_WIN_XP := 30
## Per enemy soldier the bodyguard took down.
const GENERAL_KILL_XP := 5


static func squad_level(xp: float) -> int:
	var level := 0
	for i in SQUAD_LEVEL_XP.size():
		if xp + 0.0001 >= SQUAD_LEVEL_XP[i]:
			level = i
	return level


static func squad_level_name(xp: float) -> String:
	return SQUAD_LEVEL_NAMES[squad_level(xp)]


## Progress toward the next level in [0, 1]; 1 at the top level.
static func squad_progress(xp: float) -> float:
	var level := squad_level(xp)
	if level >= SQUAD_LEVEL_XP.size() - 1:
		return 1.0
	var low := SQUAD_LEVEL_XP[level]
	return clampf((xp - low) / (SQUAD_LEVEL_XP[level + 1] - low), 0.0, 1.0)


## XP earned in one battle by a squad that is still with the kingdom afterwards.
static func squad_battle_xp(kills: float, won: bool) -> float:
	return SQUAD_BATTLE_XP + kills * SQUAD_KILL_XP + (SQUAD_WIN_XP if won else 0.0)


static func general_max_level(stars: int) -> int:
	return GENERAL_BASE_MAX_LEVEL + stars


static func general_xp_to_next(level: int) -> int:
	return GENERAL_XP_PER_LEVEL * level


static func general_battle_xp(guard_kills: float, won: bool) -> int:
	return GENERAL_BATTLE_XP + (GENERAL_WIN_XP if won else 0) + roundi(guard_kills * GENERAL_KILL_XP)
