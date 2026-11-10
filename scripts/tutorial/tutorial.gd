class_name Tutorial
extends RefCounted
## The first-game tutorial (GDD §29, M18a): the counselor leads the player through STEPS one at a
## time. Pure progress logic, owned and saved by KingdomState; TutorialOverlay shows it.
##
## A step ends in one of three ways (`need`):
## - NEXT: the player reads it and presses "Tiếp".
## - EVENT: the kingdom scene reports something the player did (`notify`), e.g. &"piece_selected".
## - STATE: the game state moved past the value it had when the step began (`update`), e.g. one
##   more farm or a later turn. Counting from the step's start means work done earlier never
##   skips a step by itself.
## Nothing is blocked: other buttons keep working; the step just waits. "Bỏ qua" ends it any time.

signal ended(skipped: bool)

enum Need { NEXT, EVENT, STATE }

const OFF := -1
## {id, need, event (EVENT) / check (STATE), target}: `target` names what the overlay points at
## (TutorialOverlay asks the kingdom scene for it); &"" points at nothing.
const STEPS: Array[Dictionary] = [
	{"id": &"welcome", "need": Need.NEXT, "target": &""},
	{"id": &"select_piece", "need": Need.EVENT, "event": &"piece_selected", "target": &"hand"},
	{"id": &"place_piece", "need": Need.EVENT, "event": &"piece_placed", "target": &""},
	{"id": &"open_build", "need": Need.EVENT, "event": &"build_window", "target": &"build_button"},
	{"id": &"build_farm", "need": Need.STATE, "check": &"farms", "target": &"farm_entry"},
	{"id": &"end_turn", "need": Need.STATE, "check": &"turn", "target": &"end_turn"},
	{"id": &"resources", "need": Need.NEXT, "target": &"resources"},
	{"id": &"recruit", "need": Need.STATE, "check": &"squads", "target": &"recruit_button"},
	{"id": &"castle", "need": Need.EVENT, "event": &"castle_opened", "target": &"castle"},
	{"id": &"hire", "need": Need.EVENT, "event": &"hire_tab", "target": &"hire_tab"},
	{"id": &"officers", "need": Need.NEXT, "target": &"officers_tab"},
	{"id": &"mini_games", "need": Need.NEXT, "target": &"officers_tab"},
	{"id": &"diplomacy", "need": Need.EVENT, "event": &"world_map", "target": &"diplomacy"},
	{"id": &"clan", "need": Need.EVENT, "event": &"clan_selected", "target": &""},
	{"id": &"war", "need": Need.NEXT, "target": &""},
	{"id": &"notices", "need": Need.NEXT, "target": &"notices"},
	{"id": &"rebels", "need": Need.NEXT, "target": &""},
	{"id": &"agents_market", "need": Need.NEXT, "target": &""},
	{"id": &"goal", "need": Need.NEXT, "target": &""},
]

## Index into STEPS, or OFF (never started, finished or skipped).
var step := OFF
## The STATE step's value when it began (measure).
var baseline := 0


func start(state: KingdomState) -> void:
	step = 0
	_enter(state)


func is_active() -> bool:
	return step >= 0 and step < STEPS.size()


func current() -> Dictionary:
	return STEPS[step] if is_active() else {}


func current_id() -> StringName:
	return current().get("id", &"")


## The player pressed "Tiếp" on a NEXT step.
func next(state: KingdomState) -> bool:
	if not is_active() or current().need != Need.NEXT:
		return false
	_advance(state)
	return true


## The kingdom scene reports what the player did; true when it ended the step.
func notify(event: StringName, state: KingdomState) -> bool:
	if not is_active() or current().need != Need.EVENT or current().event != event:
		return false
	_advance(state)
	return true


## Checks a STATE step (and the castle's hiring step, which cannot happen while the castle is
## being upgraded: Chiêu hiền is closed then); true when it ended the step.
func update(state: KingdomState) -> bool:
	if not is_active():
		return false
	var done := false
	if current().need == Need.STATE:
		done = measure(current().check, state) > baseline
	elif current_id() == &"hire":
		done = state.castle_turns > 0
	if done:
		_advance(state)
	return done


func skip() -> void:
	if not is_active():
		return
	step = OFF
	ended.emit(true)


## What a STATE step counts.
static func measure(check: StringName, state: KingdomState) -> int:
	match check:
		&"farms":
			return state.board.count_buildings(&"farm", true)
		&"turn":
			return state.turn
		&"squads":
			return state.army.count_squads()
	return 0


func _advance(state: KingdomState) -> void:
	step += 1
	if step >= STEPS.size():
		step = OFF
		ended.emit(false)
		return
	_enter(state)


func _enter(state: KingdomState) -> void:
	baseline = measure(current().get("check", &""), state) if current().need == Need.STATE else 0


func to_save() -> Dictionary:
	return {"step": step, "baseline": baseline}


## Older saves have no tutorial: it stays off.
func load_save(data: Dictionary) -> void:
	step = int(data.get("step", OFF))
	if step >= STEPS.size():
		step = OFF
	baseline = int(data.get("baseline", 0))
