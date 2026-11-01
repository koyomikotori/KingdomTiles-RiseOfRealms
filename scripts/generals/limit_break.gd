class_name LimitBreak
extends RefCounted
## Limit break (đột phá, GDD §19, M16c): a general or advisor at their max level may break through
## it. Each break raises every stat's cap by STAT_STEP and the max level by LEVEL_STEP, so new
## points come from XP again (points left over can be spent at once). How many breaks depends on
## the stars (MAX_BREAKS_BY_STARS); break N costs N × BASE_COST and N scrolls (Bí kíp đột phá,
## KingdomState.scrolls, only from cleared expeditions: Expedition.scrolls_for).

enum Result { OK, NOT_MAX_LEVEL, NO_BREAKS_LEFT, AWAY, NO_SCROLLS, NO_RESOURCES }

const STAT_STEP := 2
const LEVEL_STEP := 2
## Index = stars.
const MAX_BREAKS_BY_STARS: Array[int] = [0, 1, 1, 2, 2, 3, 3]
const BASE_COST: Dictionary[StringName, int] = {&"food": 100, &"wood": 100, &"stone": 100, &"ore": 20,
		&"hardwood": 20, &"horses": 20}


static func max_breaks(officer: Officer) -> int:
	return MAX_BREAKS_BY_STARS[clampi(officer.stars, 0, MAX_BREAKS_BY_STARS.size() - 1)]


## The cost of the next break (BASE_COST × its number).
static func cost(officer: Officer) -> Dictionary[StringName, int]:
	var total: Dictionary[StringName, int] = {}
	for resource_id in BASE_COST:
		total[resource_id] = BASE_COST[resource_id] * (officer.breaks + 1)
	return total


static func scrolls_needed(officer: Officer) -> int:
	return officer.breaks + 1


## Why the officer cannot break through right now ("" when they can).
static func describe(result: Result) -> String:
	match result:
		Result.NOT_MAX_LEVEL:
			return "Cần đạt cấp tối đa trước."
		Result.NO_BREAKS_LEFT:
			return "Đã đột phá hết số lần."
		Result.AWAY:
			return "Đang đi thảo phạt."
		Result.NO_SCROLLS:
			return "Không đủ Bí kíp đột phá (có được khi dẹp yên một vùng nổi loạn)."
		Result.NO_RESOURCES:
			return "Không đủ tài nguyên."
	return ""
