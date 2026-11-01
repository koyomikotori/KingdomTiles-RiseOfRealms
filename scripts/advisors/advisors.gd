class_name Advisors
extends RefCounted
## The kingdom's advisors (mưu sĩ, GDD §8 M11f): up to MAX_ADVISORS, each holding at most one of
## the three posts. Nội chính helps the economy, Ngoại giao the diplomacy, Quân sự goes to battle
## (army bonuses + stratagems). Owned by KingdomState; takes what it needs as arguments.
## Recruitment goes through the shared candidate list in Generals.

signal changed

const MAX_ADVISORS := 3
const POSTS: Array[StringName] = [&"admin", &"diplomacy", &"military"]
const POST_NAMES: Dictionary[StringName, String] = {&"admin": "Nội chính", &"diplomacy": "Ngoại giao",
		&"military": "Quân sự"}
const STAT_IDS: Array[StringName] = [&"admin", &"diplomacy", &"strategy"]
const STAT_NAMES: Dictionary[StringName, String] = {&"admin": "Nội chính", &"diplomacy": "Ngoại giao",
		&"strategy": "Mưu lược"}
const STAT_MIN := 1
const STAT_MAX := 10
## Advisors have three stats: their total is this many times a general's of the same stars.
const STAT_TOTAL_FACTOR := 1.5

## Nội chính, per point: production building yield, building and castle cost (less), army and
## generals upkeep (less).
const ADMIN_YIELD := 0.015
const ADMIN_COST := 0.015
const ADMIN_UPKEEP := 0.015
## Quân sự, per point of Mưu lược: morale and range attack for the kingdom's own units.
const MILITARY_MORALE := 0.25
const MILITARY_RANGE := 0.02
## Each stratagem works with this chance at the start of a battle (+ per point of Mưu lược).
const STRATAGEM_BASE_CHANCE := 0.25
const STRATAGEM_CHANCE_PER_POINT := 0.025
## The military advisor may be wounded only when the battle is lost; never killed.
const WOUND_CHANCE := 0.5
const WOUND_TURNS := 3
## XP per turn for the admin and diplomacy posts; the military post learns in battle.
const POST_TURN_XP := 10
const BATTLE_XP := 30
const WIN_XP := 30
## Male given names for advisors (family, middle and female names are in Officer).
const ADVISOR_NAMES: Array[String] = ["Trí", "Mưu", "Luận", "Thông", "Hiền", "Tuệ", "Đoán", "Liêm", "Tri", "Kế",
		"Lược", "Văn", "Học", "Sách", "Minh", "Đức"]

var advisors: Array[Advisor] = []
var ranks: Dictionary[int, GeneralRankData] = GeneralRankData.load_all()
var stratagems: Dictionary[StringName, StratagemData] = StratagemData.load_all()
## Own random numbers, so advisors never shift the kingdom's other rolls.
var rng := RandomNumberGenerator.new()


## A new random advisor: three stats summing to STAT_TOTAL_FACTOR × the rank's general total,
## and `stars` different stratagems.
func generate(stars: int) -> Advisor:
	var rank := ranks[clampi(stars, 1, ranks.size())]
	var advisor := Advisor.new()
	advisor.stars = rank.stars
	advisor.look = OfficerLook.random(rng)
	advisor.name = Officer.random_name(rng, advisor.look.is_female(), ADVISOR_NAMES)
	GameArt.assign_portrait(advisor)
	var total := clampi(roundi(rng.randi_range(rank.total_min, rank.total_max) * STAT_TOTAL_FACTOR),
			STAT_MIN * 3, STAT_MAX * 3)
	var stats := [STAT_MIN, STAT_MIN, STAT_MIN]
	for i in total - STAT_MIN * 3:
		var open: Array[int] = []
		for s in 3:
			if stats[s] < STAT_MAX:
				open.append(s)
		stats[open[rng.randi_range(0, open.size() - 1)]] += 1
	advisor.admin = stats[0]
	advisor.diplomacy = stats[1]
	advisor.strategy = stats[2]
	var pool: Array[StringName] = []
	pool.assign(stratagems.keys())
	pool.sort()
	for i in mini(advisor.stars, pool.size()):
		advisor.stratagems.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	advisor.stratagems.sort()
	return advisor


func is_full() -> bool:
	return advisors.size() >= MAX_ADVISORS


## Adds an advisor (recruited) and gives them the first free post. False when there is no room.
func add(advisor: Advisor) -> bool:
	if is_full():
		return false
	advisors.append(advisor)
	advisor.post = Advisor.NO_POST
	for post_id in POSTS:
		if holder(post_id) == null:
			advisor.post = post_id
			break
	changed.emit()
	return true


func dismiss(advisor: Advisor) -> void:
	advisors.erase(advisor)
	changed.emit()


## Gives `post_id` to the advisor. Whoever held it takes the advisor's old post (a swap).
func assign(advisor: Advisor, post_id: StringName) -> void:
	if not advisors.has(advisor) or not POSTS.has(post_id) or advisor.post == post_id:
		return
	var current := holder(post_id)
	if current != null:
		current.post = advisor.post
	advisor.post = post_id
	changed.emit()


func holder(post_id: StringName) -> Advisor:
	for advisor in advisors:
		if advisor.post == post_id:
			return advisor
	return null


## The holder of the post when able to work (not wounded), or null.
func active(post_id: StringName) -> Advisor:
	var advisor := holder(post_id)
	return advisor if advisor != null and advisor.is_ready() else null


## The working holder's stat for that post (items included), or 0 without one.
func post_stat(post_id: StringName) -> int:
	var advisor := active(post_id)
	return advisor.stat_for(post_id) if advisor != null else 0


## An item effect (ItemEffectData) of the working holder of `post_id`, when the effect works in
## that post (M12e); 0.0 otherwise.
func post_effect(post_id: StringName, effect_id: StringName) -> float:
	var advisor := active(post_id)
	var data: ItemEffectData = Equipment.effect_data().get(effect_id)
	if advisor == null or data == null or (data.post != &"" and data.post != post_id):
		return 0.0
	return advisor.item_effect(effect_id)


## Adds one of the advisor's level points to a stat (STAT_IDS). False (nothing changes) without
## points or when that stat is already at its cap (STAT_MAX, raised by limit breaks: Officer.stat_cap).
func spend_point(advisor: Advisor, stat: StringName) -> bool:
	if not can_spend_point(advisor, stat):
		return false
	advisor.points -= 1
	match stat:
		&"admin":
			advisor.admin += 1
		&"diplomacy":
			advisor.diplomacy += 1
		&"strategy":
			advisor.strategy += 1
	changed.emit()
	return true


func can_spend_point(advisor: Advisor, stat: StringName) -> bool:
	if advisor == null or advisor.points <= 0 or not STAT_IDS.has(stat):
		return false
	return advisor.get_stat(stat) < advisor.stat_cap(STAT_MAX)


## What a post gives right now with `points` in its stat, for the UI.
static func describe_post(post_id: StringName, points: int) -> String:
	match post_id:
		&"admin":
			return "Đang cộng: +%d%% sản lượng công trình khai thác, −%d%% giá xây dựng và nâng cấp, −%d%% phí nuôi quân và tướng." % [
					roundi(points * ADMIN_YIELD * 100), roundi(points * ADMIN_COST * 100), roundi(points * ADMIN_UPKEEP * 100)]
		&"diplomacy":
			return "Đang cộng: giao thương lợi hơn %d%%, +%d%% khả năng được chấp nhận, −%d%% cảnh giác, +%d%% quà tặng." % [
					roundi(points * Diplomacy.ENVOY_PRICE * 100), roundi(points * Diplomacy.ENVOY_CHANCE * 100),
					roundi(points * Diplomacy.ENVOY_WARINESS * 100), roundi(points * Diplomacy.ENVOY_GIFT * 100)]
		&"military":
			return "Đang cộng: +%.1f sĩ khí, +%d%% tấn công tầm xa; mỗi mưu kế %d%% thành công đầu trận." % [
					points * MILITARY_MORALE, roundi(points * MILITARY_RANGE * 100), roundi(stratagem_chance(points) * 100)]
	return ""


func get_upkeep() -> Dictionary[StringName, int]:
	var total: Dictionary[StringName, int] = {}
	for advisor in advisors:
		Economy.add_into(total, ranks[advisor.stars].upkeep)
	return total


## End of a turn: wounds heal; the admin and diplomacy holders gain POST_TURN_XP. Returns the
## advisors that recovered this turn.
## `extra_healing` more turns of a wound heal each turn (the Y quán, GDD §8 M14e).
func end_turn(extra_healing: int = 0) -> Array[Advisor]:
	var healed: Array[Advisor] = []
	for advisor in advisors:
		if advisor.wounded_turns > 0:
			advisor.wounded_turns = maxi(0, advisor.wounded_turns - 1 - extra_healing)
			if advisor.wounded_turns == 0:
				healed.append(advisor)
		if advisor.post == &"admin" or advisor.post == &"diplomacy":
			advisor.gain_xp(POST_TURN_XP)
	changed.emit()
	return healed


# --- Economy (Nội chính) -------------------------------------------------------------------

## Extra amounts: `share` of each amount, rounded to the nearest whole number.
static func share_of(amounts: Dictionary[StringName, int], share: float) -> Dictionary[StringName, int]:
	var result: Dictionary[StringName, int] = {}
	if share <= 0.0:
		return result
	for resource_id in amounts:
		var extra := roundi(amounts[resource_id] * share)
		if extra > 0:
			result[resource_id] = extra
	return result


## Cost after the Nội chính discount (each amount loses its share, rounded).
func discounted(cost: Dictionary[StringName, int]) -> Dictionary[StringName, int]:
	var result := cost.duplicate()
	var off := share_of(cost, post_stat(&"admin") * ADMIN_COST + post_effect(&"admin", &"build_discount"))
	for resource_id in off:
		result[resource_id] -= off[resource_id]
	return result


# --- Battle (Quân sự) ----------------------------------------------------------------------

## Puts the working military advisor behind `side`: their bonuses on the kingdom's own units and
## their stratagems, rolled by the simulator at the start of the battle.
func assist(side: BattleSide) -> void:
	var advisor := active(&"military")
	if advisor == null:
		return
	assist_officer(side, advisor, advisor.stat_for(&"military"), post_effect(&"military", &"stratagem"))


## `advisor` follows `side` with `strategy` points (the kingdom's military advisor, or a clan's, M14h).
func assist_officer(side: BattleSide, advisor: Advisor, strategy: int, stratagem_bonus: float) -> void:
	side.advisor_name = advisor.name
	side.advisor_look = advisor.look
	side.strategy = strategy
	side.stratagem_bonus = stratagem_bonus
	for id in advisor.stratagems:
		if stratagems.has(id):
			side.stratagems.append(stratagems[id])
	for unit in side.units:
		if unit.ally != null:
			continue
		unit.morale += strategy * MILITARY_MORALE
		unit.range_mult += strategy * MILITARY_RANGE


static func stratagem_chance(strategy: int) -> float:
	return clampf(STRATAGEM_BASE_CHANCE + strategy * STRATAGEM_CHANCE_PER_POINT, 0.0, 1.0)


## After a battle the military advisor followed on `side`: battle XP (more on a win); a lost
## battle may wound them. Returns {"name", "fate": &"none" | &"wounded", "xp", "levels"}.
func after_battle(record: BattleRecord, side: int) -> Dictionary:
	var advisor := holder(&"military")
	if record.sides[side].advisor_name.is_empty() or advisor == null:
		return {"name": "", "fate": &"none", "xp": 0, "levels": 0}
	var won := record.winner == side
	var fate := &"none"
	if not won and rng.randf() < WOUND_CHANCE:
		advisor.wounded_turns = WOUND_TURNS
		fate = &"wounded"
	var xp := roundi((BATTLE_XP + (WIN_XP if won else 0)) * (1.0 + advisor.item_effect(&"advisor_xp")))
	var levels := advisor.gain_xp(xp)
	changed.emit()
	return {"name": advisor.name, "fate": fate, "xp": xp, "levels": levels}


# --- Save (GDD §10.1) ---------------------------------------------------------------------

func to_save() -> Array:
	var result: Array = []
	for advisor in advisors:
		result.append(advisor.to_save())
	return result


func load_save(data: Array) -> void:
	advisors.clear()
	for entry: Dictionary in data:
		advisors.append(Advisor.from_save(entry))
	changed.emit()
