class_name MemoryMatch
extends RefCounted
## One memory card match between the Chúa công (the player) and an advisor (the computer)
## (GDD §27, M16k). Pure rules: the MemoryScreen feeds it the cards the player flips and asks
## `ai_pick` for the advisor's; this class keeps the board, the turn, the scores and the advisor's
## memory. Only XP comes out of it (KingdomState.finish_memory).
##
## A turn is two flips: a pair is kept and the same side flips again; otherwise the two cards
## stay up until `end_turn` turns them down and passes the turn. Over once every pair is taken.

enum Side { RULER, ADVISOR }
enum Result { OK, LOW_STARS, AWAY, WOUNDED, MAX_LEVEL, COOLDOWN }

const MIN_STARS := 3
const COOLDOWN_TURNS := 5
## Share of the XP to the advisor's next level: the Chúa công won (the advisor learned more), lost.
const WIN_SHARE := 0.4
const LOSS_SHARE := 0.15
## By the advisor's stars, from MIN_STARS (3★) to 6★: the board (columns × rows) and the chance
## the advisor remembers a card once it has been turned up.
const GRIDS: Array[Vector2i] = [Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 5), Vector2i(6, 6)]
const REMEMBER: Array[float] = [0.3, 0.4, 0.5, 0.6]
## The card faces: [&"icon", resource id] (GameArt.icon) or [&"item", icon id] (GameArt.item_icon).
const FACES: Array[Array] = [
	[&"icon", &"food"], [&"icon", &"wood"], [&"icon", &"stone"], [&"icon", &"ore"], [&"icon", &"hardwood"],
	[&"icon", &"horses"], [&"item", &"kiem"], [&"item", &"dao"], [&"item", &"chuy"],
	[&"item", &"general_armor"], [&"item", &"general_accessory"], [&"item", &"advisor_weapon"],
	[&"item", &"advisor_armor"], [&"item", &"advisor_accessory"], [&"item", &"ngoc_ty_truyen_quoc"],
	[&"item", &"ho_phu_tin_lang"], [&"item", &"bat_qua_chuy"], [&"item", &"bat_quai_dao_bao"],
]
const NOBODY := -1

var advisor: Advisor
var columns: int
var rows: int
## Face index (FACES) of each card, row by row.
var cards: Array[int] = []
## Who took each card (Side), NOBODY while it is still in play.
var taken: Array[int] = []
## The cards turned up this turn (0–2).
var picked: Array[int] = []
var side := Side.RULER
var scores: Array[int] = [0, 0]
## What the advisor remembers: card → face, only cards still in play.
var memory: Dictionary[int, int] = {}
var rng := RandomNumberGenerator.new()


func _init(playing: Advisor, seed_value: int = 0) -> void:
	advisor = playing
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var grid := GRIDS[_tier()]
	columns = grid.x
	rows = grid.y
	for face in pairs():
		cards.append(face)
		cards.append(face)
	for i in range(cards.size() - 1, 0, -1):  # Fisher–Yates with our own rng (repeatable)
		var j := rng.randi_range(0, i)
		var swap := cards[i]
		cards[i] = cards[j]
		cards[j] = swap
	taken.resize(cards.size())
	taken.fill(NOBODY)


## Whether `advisor` may play on `turn` (OK first: the button shows the first reason it may not).
static func check(playing: Advisor, turn: int) -> Result:
	if playing.stars < MIN_STARS:
		return Result.LOW_STARS
	if playing.away:
		return Result.AWAY
	if playing.wounded_turns > 0:
		return Result.WOUNDED
	if playing.level >= playing.max_level():
		return Result.MAX_LEVEL
	if turns_left(playing, turn) > 0:
		return Result.COOLDOWN
	return Result.OK


## Turns before `advisor` may play again (0 = now).
static func turns_left(playing: Advisor, turn: int) -> int:
	return maxi(0, playing.last_memory_turn + COOLDOWN_TURNS - turn)


static func describe(result: Result, playing: Advisor = null, turn: int = 0) -> String:
	match result:
		Result.LOW_STARS:
			return "Chỉ mưu sĩ từ %d★ mới đấu trí được." % MIN_STARS
		Result.AWAY:
			return "Đang đi thảo phạt."
		Result.WOUNDED:
			return "Đang bị thương."
		Result.MAX_LEVEL:
			return "Đã đạt cấp tối đa."
		Result.COOLDOWN:
			return "Còn %d lượt nữa mới đấu trí lại được." % turns_left(playing, turn) if playing != null \
					else "Chưa hết thời gian nghỉ."
	return ""


## XP for the advisor: a share of their next level, more when the Chúa công won.
static func xp_reward(playing: Advisor, ruler_won: bool, bonus: float = 1.0) -> int:
	return ceili(playing.xp_to_next() * (WIN_SHARE if ruler_won else LOSS_SHARE) * bonus)


func _tier() -> int:
	return clampi(advisor.stars - MIN_STARS, 0, GRIDS.size() - 1)


## Pairs on this board.
func pair_count() -> int:
	return columns * rows / 2


## The faces in play: the first pair_count() of FACES.
func pairs() -> Array[int]:
	var faces: Array[int] = []
	for i in pair_count():
		faces.append(i)
	return faces


func remember_chance() -> float:
	return REMEMBER[_tier()]


## Whether `card` may be turned up now.
func can_flip(card: int) -> bool:
	return not is_over() and card >= 0 and card < cards.size() and taken[card] == NOBODY \
			and not picked.has(card) and picked.size() < 2


## Turns `card` up for the side to play. Returns {} if it may not; otherwise {"face", "second"
## (the turn's second card), "pair" (a pair taken: the same side flips again)}. After a second card
## that is no pair, the two stay up until end_turn.
func flip(card: int) -> Dictionary:
	if not can_flip(card):
		return {}
	picked.append(card)
	_see(card)
	if picked.size() < 2:
		return {"face": cards[card], "second": false, "pair": false}
	var first := picked[0]
	if cards[first] != cards[card]:
		return {"face": cards[card], "second": true, "pair": false}
	for taken_card in [first, card]:
		taken[taken_card] = side
		memory.erase(taken_card)
	scores[side] += 1
	picked.clear()
	return {"face": cards[card], "second": true, "pair": true}


## Whether two cards that do not match are up, waiting for end_turn.
func waiting() -> bool:
	return picked.size() == 2


## Turns the two cards down and passes the turn.
func end_turn() -> void:
	if not waiting():
		return
	picked.clear()
	side = Side.ADVISOR if side == Side.RULER else Side.RULER


## The advisor may remember a card once it is up (theirs or the Chúa công's).
func _see(card: int) -> void:
	if not memory.has(card) and rng.randf() < remember_chance():
		memory[card] = cards[card]


## The advisor's next card: a remembered pair, the twin of the card just turned up if remembered,
## otherwise a card they do not know.
func ai_pick() -> int:
	if picked.size() == 1:
		var face := cards[picked[0]]
		for card in memory:
			if card != picked[0] and memory[card] == face:
				return card
		return _unknown_card()
	var seen := {}
	for card in memory:
		var face: int = memory[card]
		if seen.has(face):
			return seen[face]
		seen[face] = card
	return _unknown_card()


## A random card in play the advisor does not remember (or any card in play if they know all).
func _unknown_card() -> int:
	var unknown: Array[int] = []
	var any: Array[int] = []
	for card in cards.size():
		if taken[card] == NOBODY and not picked.has(card):
			any.append(card)
			if not memory.has(card):
				unknown.append(card)
	var pool := unknown if not unknown.is_empty() else any
	return pool[rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else NOBODY


func is_over() -> bool:
	return scores[Side.RULER] + scores[Side.ADVISOR] >= pair_count()


## The Chúa công wins with more pairs; a tie goes to the advisor.
func ruler_won() -> bool:
	return is_over() and scores[Side.RULER] > scores[Side.ADVISOR]
