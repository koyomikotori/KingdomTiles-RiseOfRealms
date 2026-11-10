class_name Counsel
extends RefCounted
## What the counselor says (GDD §25, M16i): picks a line of a topic from LINES_PATH. Pure; the
## windows show the result with CounselBox. Only the counselor chosen for the game speaks.
##
## LINES_PATH is JSON (dialogue reads better as text than as .tres): {topic: {"linh_nhi" /
## "tu_uyen": [[expression, text], …]}}. One line is picked at random. Texts may hold
## {placeholders} filled from the context (e.g. {clan}). Adding a topic needs no code.

const LINES_PATH := "res://data/counsel/lines.json"
## M16i-b: the counselor tells each event instead of its description: {event_id: {"linh_nhi" /
## "tu_uyen": [[expression, text], …]}}, same shape as a topic.
const EVENTS_PATH := "res://data/counsel/events.json"
## M18a: the tutorial's steps, {step_id: {"linh_nhi" / "tu_uyen": [[expression, text]]}}.
const TUTORIAL_PATH := "res://data/counsel/tutorial.json"

static var _topics: Dictionary = {}
static var _events: Dictionary = {}
static var _tutorial: Dictionary = {}
## Line picks only; never the game's own rolls (KingdomState.rng), so talking changes nothing.
static var _rng := RandomNumberGenerator.new()


static func topics() -> Dictionary:
	if _topics.is_empty():
		_topics = _load(LINES_PATH)
	return _topics


static func events() -> Dictionary:
	if _events.is_empty():
		_events = _load(EVENTS_PATH)
	return _events


static func tutorial() -> Dictionary:
	if _tutorial.is_empty():
		_tutorial = _load(TUTORIAL_PATH)
	return _tutorial


## The counselor explaining tutorial step `step_id` (Tutorial.STEPS).
static func tutorial_lines(step_id: StringName, speaker: StringName, context: Dictionary = {}) -> Array[Dictionary]:
	return _pick(tutorial().get(String(step_id), {}), speaker, context)


static func _load(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			return parsed
	return {}


## The context every line can use: {kingdom} as the counselor says it (the default name
## "Vương quốc của bạn" would have them call the ruler "bạn"), plus `extra`.
static func context(state: KingdomState, extra: Dictionary = {}) -> Dictionary:
	var result := {"kingdom": kingdom_label(state.kingdom_name)}
	result.merge(extra, true)
	return result


static func kingdom_label(kingdom_name: String) -> String:
	var name := kingdom_name.strip_edges()
	return "vương quốc ta" if name.is_empty() or name == KingdomState.DEFAULT_KINGDOM_NAME else name


static func has_topic(topic: StringName) -> bool:
	return topics().has(String(topic))


## [{"speaker", "expression", "text"}]: one line of `speaker`, or empty for an unknown topic. An
## array so CounselBox could show more than one line.
static func lines(topic: StringName, speaker: StringName, context: Dictionary = {}) -> Array[Dictionary]:
	return _pick(topics().get(String(topic), {}), speaker, context)


## The counselor telling event `event_id` (empty when it has no lines: show its own text).
static func event_lines(event_id: StringName, speaker: StringName, context: Dictionary = {}) -> Array[Dictionary]:
	return _pick(events().get(String(event_id), {}), speaker, context)


static func _pick(by_speaker: Dictionary, speaker: StringName, context: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	speaker = Counselor.valid(speaker)
	var options: Array = by_speaker.get(String(speaker), [])
	if options.is_empty():
		return result
	var line: Array = options[_rng.randi_range(0, options.size() - 1)]
	result.append({"speaker": speaker, "expression": StringName(line[0]),
			"text": String(line[1]).format(context)})
	return result
