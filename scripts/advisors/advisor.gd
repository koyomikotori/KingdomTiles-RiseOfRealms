class_name Advisor
extends Officer
## One advisor (mưu sĩ, GDD §8 M11f): Nội chính (admin), Ngoại giao (diplomacy) and Mưu lược
## (strategy), a set of stratagems (as many as stars), and the post they hold, on top of what
## every officer has (name, stars, wounds, level).

const NO_POST: StringName = &""

var admin: int
var diplomacy: int
var strategy: int
var stratagems: Array[StringName] = []
## Advisors.POSTS entry, or NO_POST.
var post: StringName = NO_POST
## Turn of the last memory match with the Chúa công (MemoryMatch, M16k); far back = never.
var last_memory_turn := -100


## The stat a post uses, worn items included: &"admin" → admin, &"diplomacy" → diplomacy,
## &"military" → strategy.
func stat_for(post_id: StringName) -> int:
	match post_id:
		&"admin":
			return admin + item_bonus(&"admin")
		&"diplomacy":
			return diplomacy + item_bonus(&"diplomacy")
		&"military":
			return strategy + item_bonus(&"strategy")
	return 0


## The advisor's own points in a stat (Advisors.STAT_IDS: &"admin", &"diplomacy", &"strategy"),
## without items.
func get_stat(stat: StringName) -> int:
	match stat:
		&"admin":
			return admin
		&"diplomacy":
			return diplomacy
		&"strategy":
			return strategy
	return 0


func to_save() -> Dictionary:
	var data := _officer_save()
	var ids: Array[String] = []
	for id in stratagems:
		ids.append(String(id))
	data.merge({"kind": "advisor", "admin": admin, "diplomacy": diplomacy, "strategy": strategy,
			"stratagems": ids, "post": String(post), "last_memory_turn": last_memory_turn})
	return data


static func from_save(data: Dictionary) -> Advisor:
	var advisor := Advisor.new()
	advisor._officer_load(data)
	advisor.admin = int(data.admin)
	advisor.diplomacy = int(data.diplomacy)
	advisor.strategy = int(data.strategy)
	for id: String in data.stratagems:
		advisor.stratagems.append(StringName(id))
	advisor.post = StringName(data.post)
	advisor.last_memory_turn = int(data.get("last_memory_turn", -100))
	return advisor
