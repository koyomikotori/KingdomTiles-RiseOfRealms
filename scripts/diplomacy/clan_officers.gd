class_name ClanOfficers
extends RefCounted
## The generals and advisors of the clans (GDD §15, M14h; M16g), owned by KingdomState. Every clan
## fields a general and an advisor, their stars by the clan's tier (STARS_BY_TIER: weak 1–2,
## medium 3–4, strong 5–6; on Legendary weak and medium clans get +1, Difficulty), but only one of
## the two may have the tier's top stars. The tier comes from the clan's current strength
## (Wars.tier): officers whose stars no longer fit it are replaced by new ones.
## They lead the clan's army like the kingdom's own (Generals.lead_officer, Advisors.assist_officer)
## but have no items or traits. A fallen general may die (Generals.DEATH_CHANCE) and is replaced
## after VACANCY_TURNS turns; otherwise they are wounded for a few turns and stay at home.
## Officers are made when a clan first needs them, with their own random numbers.

## Lowest and highest stars of a clan's officers by Wars.Tier (WEAK, MEDIUM, STRONG).
const STARS_BY_TIER: Array[Vector2i] = [Vector2i(1, 2), Vector2i(3, 4), Vector2i(5, 6)]
const MAX_STARS := 6
const VACANCY_TURNS := 5
## The bandits' leader (M16e) is kept under this key: [first turn, lowest stars, highest stars],
## a weak leader from turn 20, a medium one from 40, a strong one from 60.
const BANDITS := &"bandits"
const BANDIT_STARS: Array[Vector3i] = [Vector3i(20, 1, 2), Vector3i(40, 3, 4), Vector3i(60, 5, 6)]


class Staff:
	extends RefCounted
	var general: General
	var advisor: Advisor
	## Turns before a new general replaces one killed in battle (or assassinated, M16b).
	var vacancy := 0
	## Same for an assassinated advisor (M16b).
	var advisor_vacancy := 0


var staffs: Dictionary[StringName, Staff] = {}
var rng := RandomNumberGenerator.new()
## Their own generators (ranks, stratagems, the bodyguard unit); the kingdom's rolls stay as they were.
var _generals := Generals.new()
var _advisors := Advisors.new()


func _init() -> void:
	_generals.rng = rng
	_advisors.rng = rng


## The (lowest, highest) stars of the officers of a clan of `tier` on difficulty `level`.
static func star_range(tier: int, level: int) -> Vector2i:
	var stars := STARS_BY_TIER[clampi(tier, 0, STARS_BY_TIER.size() - 1)]
	var extra := Difficulty.extra_stars(level, tier)
	return Vector2i(mini(stars.x + extra, MAX_STARS), mini(stars.y + extra, MAX_STARS))


## Whether `officer` has stars that suit a clan of `tier` now.
static func fits(officer: Officer, tier: int, level: int) -> bool:
	var stars := star_range(tier, level)
	return officer != null and officer.stars >= stars.x and officer.stars <= stars.y


func staff(clan_id: StringName) -> Staff:
	if not staffs.has(clan_id):
		staffs[clan_id] = Staff.new()
	return staffs[clan_id]


## Makes the officers the clan is missing and replaces those whose stars no longer suit its tier.
## Only one of the two may have the tier's top stars.
func ensure(clan_id: StringName, wars: Wars, level: int) -> void:
	var tier := wars.tier(clan_id)
	var s := staff(clan_id)
	if s.vacancy <= 0 and not fits(s.general, tier, level):
		s.general = _generals.generate(_roll_stars(tier, level, s.advisor if fits(s.advisor, tier, level) else null))
		s.general.trait_id = &""
	if s.advisor_vacancy <= 0 and not fits(s.advisor, tier, level):
		s.advisor = _advisors.generate(_roll_stars(tier, level, s.general if fits(s.general, tier, level) else null))


## The stars the bandits' leader has on `turn`: (lowest, highest), ZERO before the first one.
static func bandit_stars(turn: int) -> Vector2i:
	var result := Vector2i.ZERO
	for entry in BANDIT_STARS:
		if turn >= entry.x:
			result = Vector2i(entry.y, entry.z)
	return result


## Makes the bandits' leader, or a stronger one when the bandits have grown (M16e).
func ensure_bandits(turn: int) -> void:
	var stars := bandit_stars(turn)
	var s := staff(BANDITS)
	if stars.x > 0 and s.vacancy <= 0 and (s.general == null or s.general.stars < stars.x):
		s.general = _generals.generate(rng.randi_range(stars.x, stars.y))
		s.general.trait_id = &""


## The bandits' leader able to fight on `turn`, or null (none yet, killed lately, or wounded).
func bandit_leader(turn: int) -> General:
	ensure_bandits(turn)
	var general := staff(BANDITS).general
	return general if general != null and general.wounded_turns <= 0 else null


## Puts the bandits' leader at the head of a raid.
func lead_bandits(side: BattleSide, turn: int) -> void:
	var general := bandit_leader(turn)
	if general != null:
		_generals.lead_officer(side, general)


## Stars for a new officer of a clan of `tier`: the lowest when `partner` (the other officer)
## already has the top stars.
func _roll_stars(tier: int, level: int, partner: Officer) -> int:
	var stars := star_range(tier, level)
	if partner != null and partner.stars >= stars.y:
		return stars.x
	return rng.randi_range(stars.x, stars.y)


## The general and advisor the clan sends into battle now (null when none or wounded).
func fielded_general(clan_id: StringName, _wars: Wars, _level: int) -> General:
	var general := staff(clan_id).general
	return general if general != null and general.wounded_turns <= 0 else null


func fielded_advisor(clan_id: StringName, _wars: Wars, _level: int) -> Advisor:
	var advisor := staff(clan_id).advisor
	return advisor if advisor != null and advisor.wounded_turns <= 0 else null


## Puts the clan's officers at the head of its army on `side` (its own units, not lent ones).
func lead(side: BattleSide, clan_id: StringName, wars: Wars, level: int) -> void:
	if wars.fronts[clan_id].annexed:
		return
	ensure(clan_id, wars, level)
	var general := fielded_general(clan_id, wars, level)
	if general != null:
		_generals.lead_officer(side, general)
	var advisor := fielded_advisor(clan_id, wars, level)
	if advisor != null:
		_advisors.assist_officer(side, advisor, advisor.strategy, 0.0)


## After a battle the clan fought on `side`: a fallen general may die, else is wounded; a beaten
## advisor may be wounded. Returns {"general": {"name", "fate"}, "advisor": {"name", "fate"}}
## with fate &"none" | &"dead" | &"wounded" (name "" when they did not fight).
func after_battle(record: BattleRecord, side: int, clan_id: StringName) -> Dictionary:
	var battle_side := record.sides[side]
	var s := staff(clan_id)
	var result := {"general": {"name": "", "fate": &"none"}, "advisor": {"name": "", "fate": &"none"}}
	if s.general != null and battle_side.general_name == s.general.name:
		result.general.name = s.general.name
		if battle_side.general_fallen:
			if rng.randf() < Generals.DEATH_CHANCE:
				result.general.fate = &"dead"
				s.general = null
				s.vacancy = VACANCY_TURNS
			else:
				result.general.fate = &"wounded"
				s.general.wounded_turns = Generals.WOUND_TURNS
	if s.advisor != null and battle_side.advisor_name == s.advisor.name:
		result.advisor.name = s.advisor.name
		if record.winner != side and rng.randf() < Advisors.WOUND_CHANCE:
			result.advisor.fate = &"wounded"
			s.advisor.wounded_turns = Advisors.WOUND_TURNS
	return result


## Wounds heal and vacancies close; annexed clans lose their staff.
func end_turn(wars: Wars) -> void:
	for clan_id in staffs.keys():
		if wars.fronts.has(clan_id) and wars.fronts[clan_id].annexed:
			staffs.erase(clan_id)
			continue
		var s := staffs[clan_id]
		s.vacancy = maxi(0, s.vacancy - 1)
		s.advisor_vacancy = maxi(0, s.advisor_vacancy - 1)
		for officer: Officer in [s.general, s.advisor]:
			if officer != null:
				officer.wounded_turns = maxi(0, officer.wounded_turns - 1)


## An agent strikes at the clan's general or advisor (M16b): wounded or, with `killed`, gone
## for VACANCY_TURNS turns. Returns the officer's name ("" when the clan has none of that kind).
func assassinate(clan_id: StringName, kind: StringName, killed: bool) -> String:
	var s := staff(clan_id)
	var officer: Officer = s.general if kind == &"general" else s.advisor
	if officer == null:
		return ""
	if not killed:
		officer.wounded_turns = Generals.WOUND_TURNS if kind == &"general" else Advisors.WOUND_TURNS
	elif kind == &"general":
		s.general = null
		s.vacancy = VACANCY_TURNS
	else:
		s.advisor = null
		s.advisor_vacancy = VACANCY_TURNS
	return officer.name


## One line for the clan panel ("" when the clan fields nobody now).
func describe(clan_id: StringName, wars: Wars, level: int) -> String:
	if wars.fronts[clan_id].annexed:
		return ""
	ensure(clan_id, wars, level)
	var parts: Array[String] = []
	var s := staff(clan_id)
	for entry: Array in [[s.general, "Tướng"], [s.advisor, "Mưu sĩ"]]:
		var officer: Officer = entry[0]
		if officer == null:
			continue
		var text := "%s %s %s" % [entry[1], officer.name, officer.star_text()]
		if officer.wounded_turns > 0:
			text += " (bị thương, %d lượt)" % officer.wounded_turns
		parts.append(text)
	return " · ".join(parts)


# --- Save (GDD §10.1) ---------------------------------------------------------------------

func to_save() -> Dictionary:
	var data := {}
	for clan_id in staffs:
		var s := staffs[clan_id]
		data[String(clan_id)] = {"general": s.general.to_save() if s.general != null else {},
				"advisor": s.advisor.to_save() if s.advisor != null else {}, "vacancy": s.vacancy}
	return data


func load_save(data: Dictionary) -> void:
	staffs.clear()
	for clan_name: String in data:
		var entry: Dictionary = data[clan_name]
		var s := staff(StringName(clan_name))
		s.general = General.from_save(entry.general) if not entry.get("general", {}).is_empty() else null
		s.advisor = Advisor.from_save(entry.advisor) if not entry.get("advisor", {}).is_empty() else null
		s.vacancy = int(entry.get("vacancy", 0))
