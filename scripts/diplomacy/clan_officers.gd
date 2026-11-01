class_name ClanOfficers
extends RefCounted
## The generals and advisors of the clans (GDD §15, M14h), owned by KingdomState. Weak clans field
## none; medium clans one general or one advisor of 1–2 stars; strong clans both, 3 stars; on
## Legendary medium clans get +1 star and strong clans +2 (Difficulty). The tier comes from the
## clan's current strength (Wars.tier), so a beaten clan stops fielding them until it grows back.
## They lead the clan's army like the kingdom's own (Generals.lead_officer, Advisors.assist_officer)
## but have no items or traits. A fallen general may die (Generals.DEATH_CHANCE) and is replaced
## after VACANCY_TURNS turns; otherwise they are wounded for a few turns and stay at home.
## Officers are made when a clan first needs them, with their own random numbers.

const MEDIUM_STARS := Vector2i(1, 2)
const STRONG_STARS := 3
const VACANCY_TURNS := 5


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


## Medium clans field a general or an advisor, always the same kind for a clan.
static func medium_kind(clan_id: StringName) -> StringName:
	return &"general" if String(clan_id).hash() % 2 == 0 else &"advisor"


## Lowest stars a clan of `tier` wants for `kind`; 0 = it fields none.
static func wanted_stars(clan_id: StringName, tier: int, kind: StringName, level: int) -> int:
	match tier:
		Wars.Tier.MEDIUM:
			return MEDIUM_STARS.x + Difficulty.extra_stars(level, tier) if kind == medium_kind(clan_id) else 0
		Wars.Tier.STRONG:
			return STRONG_STARS + Difficulty.extra_stars(level, tier)
	return 0


func staff(clan_id: StringName) -> Staff:
	if not staffs.has(clan_id):
		staffs[clan_id] = Staff.new()
	return staffs[clan_id]


## Makes or promotes the officers the clan wants now (its tier may have grown).
func ensure(clan_id: StringName, wars: Wars, level: int) -> void:
	var tier := wars.tier(clan_id)
	var s := staff(clan_id)
	var general_stars := wanted_stars(clan_id, tier, &"general", level)
	if general_stars > 0 and s.vacancy <= 0 and (s.general == null or s.general.stars < general_stars):
		s.general = _generals.generate(_roll_stars(tier, general_stars))
		s.general.trait_id = &""
	var advisor_stars := wanted_stars(clan_id, tier, &"advisor", level)
	if advisor_stars > 0 and s.advisor_vacancy <= 0 and (s.advisor == null or s.advisor.stars < advisor_stars):
		s.advisor = _advisors.generate(_roll_stars(tier, advisor_stars))


func _roll_stars(tier: int, lowest: int) -> int:
	if tier == Wars.Tier.MEDIUM:
		return lowest + rng.randi_range(0, MEDIUM_STARS.y - MEDIUM_STARS.x)
	return lowest


## The general and advisor the clan sends into battle now (null when none, wounded or not wanted).
func fielded_general(clan_id: StringName, wars: Wars, level: int) -> General:
	var general := staff(clan_id).general
	if general == null or general.wounded_turns > 0:
		return null
	return general if wanted_stars(clan_id, wars.tier(clan_id), &"general", level) > 0 else null


func fielded_advisor(clan_id: StringName, wars: Wars, level: int) -> Advisor:
	var advisor := staff(clan_id).advisor
	if advisor == null or advisor.wounded_turns > 0:
		return null
	return advisor if wanted_stars(clan_id, wars.tier(clan_id), &"advisor", level) > 0 else null


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
	for entry: Array in [[s.general, "Tướng", &"general"], [s.advisor, "Mưu sĩ", &"advisor"]]:
		var officer: Officer = entry[0]
		if officer == null or wanted_stars(clan_id, wars.tier(clan_id), entry[2], level) == 0:
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
