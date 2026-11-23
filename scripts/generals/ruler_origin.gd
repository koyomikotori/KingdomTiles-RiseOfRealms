class_name RulerOrigin
extends RefCounted
## The ruler's background (Xuất thân, GDD §31, M18d): it follows the portrait preset's outfit and
## gives one small set of advantages. KingdomState.origin() reads it (empty while
## KingdomState.origins_on is off, as in most tests); the numbers live here.

const EMPEROR: StringName = &"emperor"
const WARLORD: StringName = &"warlord"
const STRATEGIST: StringName = &"strategist"
const BY_OUTFIT: Dictionary[StringName, StringName] = {&"dragon": EMPEROR, &"armor": WARLORD,
		&"brocade": STRATEGIST}
const NAMES: Dictionary[StringName, String] = {EMPEROR: "Thiên tử", WARLORD: "Võ tướng",
		STRATEGIST: "Mưu sĩ"}

## Thiên tử: officers' XP, diplomacy chances (added), trade prices, starting resources.
const OFFICER_XP := 0.1
const DIPLOMACY_CHANCE := 0.1
const TRADE_PRICE := 0.1
const START_RESOURCES := 0.5
## Võ tướng: a starting general; squads' XP; recruiting squads costs less.
const SQUAD_XP := 0.1
const RECRUIT_DISCOUNT := 0.1
## Võ tướng's general and Mưu sĩ's advisor have these stars.
const START_STARS := 3
## Mưu sĩ: a starting advisor; production buildings' output; food the squads and generals eat.
const PRODUCTION := 0.1
const FOOD_UPKEEP_CUT := 0.1


static func of_preset(preset: int) -> StringName:
	return BY_OUTFIT[Ruler.PRESETS[posmod(preset, Ruler.PRESETS.size())].outfit]


static func display_name(origin: StringName) -> String:
	return NAMES.get(origin, "")


## One line per advantage, for the ruler window and the castle.
static func lines(origin: StringName) -> Array[String]:
	match origin:
		EMPEROR:
			return ["Tướng sĩ nhận kinh nghiệm +%d%%" % _pct(OFFICER_XP),
					"Cơ hội ngoại giao +%d%%, giá trao đổi tốt hơn %d%%" % [_pct(DIPLOMACY_CHANCE), _pct(TRADE_PRICE)],
					"Tài nguyên khởi đầu +%d%%" % _pct(START_RESOURCES)]
		WARLORD:
			return ["Có sẵn 1 tướng %d★" % START_STARS,
					"Đơn vị lính nhận kinh nghiệm +%d%%" % _pct(SQUAD_XP),
					"Tuyển lính rẻ hơn %d%%" % _pct(RECRUIT_DISCOUNT)]
		STRATEGIST:
			return ["Có sẵn 1 mưu sĩ %d★" % START_STARS,
					"Sản lượng công trình sản xuất +%d%%" % _pct(PRODUCTION),
					"Lương thực nuôi quân −%d%%" % _pct(FOOD_UPKEEP_CUT)]
	return []


## "Xuất thân: Thiên tử" and its lines, one per row (tooltips).
static func describe(origin: StringName) -> String:
	if not NAMES.has(origin):
		return ""
	var text := "Xuất thân: %s" % NAMES[origin]
	for line in lines(origin):
		text += "\n• " + line
	return text


## "Xuất thân Võ tướng: có sẵn 1 tướng 3★, …." in one sentence (ruler and castle windows).
static func summary(origin: StringName) -> String:
	if not NAMES.has(origin):
		return ""
	return "Xuất thân %s: %s." % [NAMES[origin], ", ".join(lines(origin)).to_lower()]


static func _pct(share: float) -> int:
	return roundi(share * 100)
