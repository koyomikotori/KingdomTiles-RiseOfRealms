class_name Officer
extends RefCounted
## What generals and advisors share (GDD §8): name, stars, wounds, the level they grow through
## (M11e: XP toward the next level and points not yet added to a stat), their look (M12c) and the
## items they wear (M12e).

## Names (GDD §13: half the officers are women). Male given names differ for generals and
## advisors (Generals.GIVEN_NAMES, Advisors.ADVISOR_NAMES).
const FAMILY_NAMES: Array[String] = ["Trần", "Lê", "Phạm", "Hoàng", "Vũ", "Đặng", "Bùi", "Đỗ", "Ngô", "Dương",
		"Đinh", "Mạc", "Phan", "Tôn", "Khúc", "Lạc", "Thạch", "Kiều"]
const MALE_MIDDLE_NAMES: Array[String] = ["Văn", "Đức", "Minh", "Quốc", "Hữu", "Công", "Thành", "Bá", "Trọng", "Khắc"]
const FEMALE_MIDDLE_NAMES: Array[String] = ["Thị", "Ngọc", "Diệu", "Thanh", "Bảo", "Quỳnh", "Mỹ", "Kim"]
const FEMALE_GIVEN_NAMES: Array[String] = ["Lan", "Mai", "Hoa", "Thảo", "Ngọc", "Linh", "Trang", "Yến", "Hằng",
		"Quyên", "Nguyệt", "Châu", "Uyên", "Diệp", "Hương", "Vân", "Anh", "Nhi", "Tuyết", "Phượng"]

var name: String
var stars: int
var wounded_turns := 0
## On an expedition (M14i): no command, post or battle at home, cannot be dismissed.
var away := false
var level := 1
## XP gathered toward the next level (reset on each level up).
var xp := 0
## Unspent level points.
var points := 0
## Limit breaks done (M16c, LimitBreak): each raises the stat caps and the max level.
var breaks := 0
## Portrait and battle sprite (OfficerLook).
var look := OfficerLook.new()
## Worn items by slot (Item.SLOTS), managed through Equipment.
var items: Dictionary[StringName, Item] = {}


## A full name for `look.gender`: family name, then a middle and a given name for that gender.
static func random_name(rng: RandomNumberGenerator, female: bool, given_names: Array[String]) -> String:
	var middle := FEMALE_MIDDLE_NAMES if female else MALE_MIDDLE_NAMES
	var given := FEMALE_GIVEN_NAMES if female else given_names
	return "%s %s %s" % [FAMILY_NAMES[rng.randi_range(0, FAMILY_NAMES.size() - 1)],
			middle[rng.randi_range(0, middle.size() - 1)], given[rng.randi_range(0, given.size() - 1)]]


## Not wounded and not away on an expedition (M14i): commands, holds a post, fights at home.
func is_ready() -> bool:
	return wounded_turns <= 0 and not away


## Name color by stars, the equipment rarity colors (Item.RARITY_COLORS): 1–2★ gray, 3★ green,
## 4★ blue, 5★ purple, 6★ gold (M13b).
static func star_color(p_stars: int) -> Color:
	return Item.RARITY_COLORS[clampi(p_stars - 2, 0, Item.RARITY_COLORS.size() - 1)]


## star_color made readable on paper.
func name_color() -> Color:
	return UiPalette.ink(star_color(stars))


func star_text() -> String:
	return "★".repeat(stars)


func max_level() -> int:
	return Experience.general_max_level(stars) + LimitBreak.LEVEL_STEP * breaks


## A stat's cap after the limit breaks (`base`: Generals.STAT_MAX or Advisors.STAT_MAX).
func stat_cap(base: int) -> int:
	return base + LimitBreak.STAT_STEP * breaks


func xp_to_next() -> int:
	return Experience.general_xp_to_next(level)


## "Cấp 2/5 · Kinh nghiệm 40/200", or "Cấp 5 (tối đa)" (GDD §8, M11e).
func level_text() -> String:
	if level >= max_level():
		return "Cấp %d (tối đa)" % level
	return "Cấp %d/%d · Kinh nghiệm %d/%d" % [level, max_level(), xp, xp_to_next()]


## Adds XP and levels up (1 point per level) until the max level, where extra XP is dropped.
## Returns how many levels were gained.
func gain_xp(amount: int) -> int:
	var gained := 0
	xp += maxi(0, amount)
	while level < max_level() and xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		points += 1
		gained += 1
	if level >= max_level():
		xp = 0
	return gained


## What the worn items add to a stat (Item.main_stat(): &"might", &"command", &"guard_armor",
## &"strategy", &"admin", &"diplomacy").
func item_bonus(stat: StringName) -> int:
	var total := 0
	for slot in items:
		if items[slot].main_stat() == stat:
			total += items[slot].main_bonus()
	return total


## The summed amount of an item effect (ItemEffectData) over the worn items; legendary ones ×2.
func item_effect(effect_id: StringName) -> float:
	var data: ItemEffectData = Equipment.effect_data().get(effect_id)
	if data == null:
		return 0.0
	var total := 0.0
	for slot in items:
		var item := items[slot]
		total += data.amount * item.effect_multiplier() * item.effects.count(effect_id)
	return total


func _officer_save() -> Dictionary:
	var worn := {}
	for slot in items:
		worn[String(slot)] = items[slot].to_save()
	return {"name": name, "stars": stars, "wounded_turns": wounded_turns, "level": level, "xp": xp, "points": points,
			"look": look.to_save(), "items": worn, "away": away, "breaks": breaks}


func _officer_load(data: Dictionary) -> void:
	name = data.name
	stars = int(data.stars)
	wounded_turns = int(data.wounded_turns)
	away = bool(data.get("away", false))
	level = int(data.level)
	xp = int(data.xp)
	points = int(data.points)
	# Saves from before M16c have no limit breaks.
	breaks = int(data.get("breaks", 0))
	# Saves from before M12c have no look: make one from the name.
	look = OfficerLook.from_save(data.look) if data.has("look") else OfficerLook.from_seed(name)
	# Saves from before M12e have no items.
	items.clear()
	var worn: Dictionary = data.get("items", {})
	for slot: String in worn:
		items[StringName(slot)] = Item.from_save(worn[slot])
