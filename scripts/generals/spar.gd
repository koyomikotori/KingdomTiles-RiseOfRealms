class_name Spar
extends RefCounted
## One sparring match between a general and a wandering fighter (GDD §26, M16j). Pure rules: the
## SparScreen feeds it the needle position on a strike and the key / time of a dodge; this class
## keeps the health, the round and the phase. Nobody is hurt for real: only XP comes out of it
## (KingdomState.finish_spar).
##
## A round is one strike by the general (ATTACK) then one blow by the rival (DEFEND). After
## ROUNDS rounds, or once one side has no health left, the match is DONE.

enum Phase { ATTACK, DEFEND, DONE }
enum Grade { MISS, GOOD, PERFECT }
enum Result { OK, LOW_STARS, AWAY, WOUNDED, MAX_LEVEL, COOLDOWN }

const MIN_STARS := 3
## Turns between two matches of the same general.
const COOLDOWN_TURNS := 5
const ROUNDS := 5
const MAX_HP := 100
const PERFECT_DAMAGE := 20
const GOOD_DAMAGE := 12
## Each point of Võ lực (items included) adds this share to the general's damage.
const MIGHT_FACTOR := 0.04
const RIVAL_DAMAGE := 20
## XP as a share of what the general's current level needs.
const WIN_SHARE := 0.4
const LOSS_SHARE := 0.15
## Difficulty by the general's stars, from MIN_STARS (3★) to 6★: seconds for the needle to cross
## the bar once, the half widths of the perfect and good zones (bar = 0..1, center 0.5), the
## seconds the dodge ring takes to close, and the share of that time before a dodge counts (the
## green target ring shrinks as it grows).
const SWEEP_TIME: Array[float] = [1.4, 1.15, 0.95, 0.8]
const PERFECT_HALF: Array[float] = [0.05, 0.04, 0.03, 0.025]
const GOOD_HALF: Array[float] = [0.15, 0.12, 0.1, 0.08]
const DODGE_TIME: Array[float] = [1.2, 1.05, 0.9, 0.8]
const DODGE_OPEN: Array[float] = [0.5, 0.6, 0.68, 0.75]
## Each point of Thống suất (items included) lengthens the ring, up to COMMAND_DODGE_MAX.
const COMMAND_DODGE := 0.02
const COMMAND_DODGE_MAX := 0.3
## The rival's blow comes from one of these (the keys W / A / S / D or the arrows).
const DIRECTIONS: Array[StringName] = [&"up", &"left", &"down", &"right"]
const DIRECTION_KEYS := {&"up": "W", &"left": "A", &"down": "S", &"right": "D"}
const GRADE_NAMES := {Grade.MISS: "Trượt", Grade.GOOD: "Trúng", Grade.PERFECT: "Chí mạng!"}
## The wandering fighters a general may meet (sprites npc_<kind>, tools/art/foot_art.py NPC_FIGHTERS).
const RIVALS: Array[Dictionary] = [
	{"kind": &"ronin", "title": "Kiếm sĩ nón tre"},
	{"kind": &"mace", "title": "Võ sư cầm chùy"},
	{"kind": &"fist", "title": "Lão võ sư"},
	{"kind": &"heroine", "title": "Nữ hiệp"},
	{"kind": &"spear", "title": "Thương Lãng Khách"},
]

var general: General
## The opponent: {"kind", "title", "sprite"}, picked at random (pick_rival).
var rival: Dictionary
var hp := MAX_HP
var rival_hp := MAX_HP
## 1 .. ROUNDS.
var round_number := 1
var phase := Phase.ATTACK
## The rival's blow during DEFEND.
var direction: StringName = &"up"
var rng := RandomNumberGenerator.new()


func _init(sparring: General, seed_value: int = 0) -> void:
	general = sparring
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	rival = pick_rival(rng)


## A random wandering fighter, known by a short title only.
static func pick_rival(random: RandomNumberGenerator) -> Dictionary:
	var entry: Dictionary = RIVALS[random.randi_range(0, RIVALS.size() - 1)]
	return {"kind": entry.kind, "title": entry.title, "sprite": StringName("npc_%s" % entry.kind)}


## "Kiếm sĩ nón tre".
func rival_label() -> String:
	return rival.title


## Whether `general` may spar on `turn` (OK first: the button shows the first reason it may not).
static func check(general: General, turn: int) -> Result:
	if general.stars < MIN_STARS:
		return Result.LOW_STARS
	if general.away:
		return Result.AWAY
	if general.wounded_turns > 0:
		return Result.WOUNDED
	if general.level >= general.max_level():
		return Result.MAX_LEVEL
	if turns_left(general, turn) > 0:
		return Result.COOLDOWN
	return Result.OK


## Turns before `general` may spar again (0 = now).
static func turns_left(general: General, turn: int) -> int:
	return maxi(0, general.last_spar_turn + COOLDOWN_TURNS - turn)


static func describe(result: Result, general: General = null, turn: int = 0) -> String:
	match result:
		Result.LOW_STARS:
			return "Chỉ tướng từ %d★ mới được tỉ thí." % MIN_STARS
		Result.AWAY:
			return "Đang đi thảo phạt."
		Result.WOUNDED:
			return "Đang bị thương."
		Result.MAX_LEVEL:
			return "Đã đạt cấp tối đa."
		Result.COOLDOWN:
			return "Còn %d lượt nữa mới tỉ thí lại được." % turns_left(general, turn) if general != null \
					else "Chưa hết thời gian nghỉ."
	return ""


func _tier() -> int:
	return clampi(general.stars - MIN_STARS, 0, SWEEP_TIME.size() - 1)


func sweep_time() -> float:
	return SWEEP_TIME[_tier()]


func perfect_half() -> float:
	return PERFECT_HALF[_tier()]


func good_half() -> float:
	return GOOD_HALF[_tier()]


## The share of the ring's time before a dodge counts (too early = hit).
func dodge_open_share() -> float:
	return DODGE_OPEN[_tier()]


func dodge_time() -> float:
	return DODGE_TIME[_tier()] + minf(COMMAND_DODGE_MAX, COMMAND_DODGE * general.total_command())


## The needle's place on the bar (0..1) `time` seconds into the attack: back and forth.
func needle_at(time: float) -> float:
	var t := fmod(time / sweep_time(), 2.0)
	return t if t <= 1.0 else 2.0 - t


func grade(position: float) -> Grade:
	var off := absf(position - 0.5)
	if off <= perfect_half():
		return Grade.PERFECT
	if off <= good_half():
		return Grade.GOOD
	return Grade.MISS


func damage_of(hit: Grade) -> int:
	var base := PERFECT_DAMAGE if hit == Grade.PERFECT else GOOD_DAMAGE if hit == Grade.GOOD else 0
	return roundi(base * (1.0 + MIGHT_FACTOR * general.total_might()))


## The general strikes with the needle at `position`. Returns {"grade", "damage"}; the rival's
## blow comes next (a new `direction`) unless the match is over.
func strike(position: float) -> Dictionary:
	if phase != Phase.ATTACK:
		return {}
	var hit := grade(position)
	var damage := damage_of(hit)
	rival_hp = maxi(0, rival_hp - damage)
	if rival_hp <= 0:
		phase = Phase.DONE
	else:
		phase = Phase.DEFEND
		direction = DIRECTIONS[rng.randi_range(0, DIRECTIONS.size() - 1)]
	return {"grade": hit, "damage": damage}


## Whether pressing `key` (one of DIRECTIONS, or &"" when the ring closed) `elapsed` seconds into
## the rival's blow dodges it.
func dodges(key: StringName, elapsed: float) -> bool:
	return key == direction and elapsed >= dodge_time() * dodge_open_share() and elapsed <= dodge_time()


## The general answers the rival's blow. Returns {"dodged", "damage"} and moves to the next round.
func defend(key: StringName, elapsed: float) -> Dictionary:
	if phase != Phase.DEFEND:
		return {}
	var dodged := dodges(key, elapsed)
	var damage := 0 if dodged else RIVAL_DAMAGE
	hp = maxi(0, hp - damage)
	if hp <= 0 or round_number >= ROUNDS:
		phase = Phase.DONE
	else:
		round_number += 1
		phase = Phase.ATTACK
	return {"dodged": dodged, "damage": damage}


func is_over() -> bool:
	return phase == Phase.DONE


## The general wins by knocking the rival down, or with more health left after the last round.
func won() -> bool:
	if rival_hp <= 0:
		return true
	if hp <= 0:
		return false
	return hp > rival_hp


static func xp_reward(general: General, won_match: bool) -> int:
	return ceili(general.xp_to_next() * (WIN_SHARE if won_match else LOSS_SHARE))
