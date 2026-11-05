class_name Counsel
extends RefCounted
## What the counselor says (GDD §25, M16i): picks a line of a topic from LINES_PATH. Pure; the
## windows show the result with CounselBox. Only the counselor chosen for the game speaks.
##
## LINES_PATH is JSON (dialogue reads better as text than as .tres): {topic: {"linh_nhi" /
## "tu_uyen": [[expression, text], …]}}. One line is picked at random. Texts may hold
## {placeholders} filled from the context (e.g. {clan}). Adding a topic needs no code.

const LINES_PATH := "res://data/counsel/lines.json"

static var _topics: Dictionary = {}
## Line picks only; never the game's own rolls (KingdomState.rng), so talking changes nothing.
static var _rng := RandomNumberGenerator.new()


static func topics() -> Dictionary:
	if _topics.is_empty():
		var file := FileAccess.open(LINES_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_topics = parsed
	return _topics


static func has_topic(topic: StringName) -> bool:
	return topics().has(String(topic))


## [{"speaker", "expression", "text"}]: one line of `speaker`, or empty for an unknown topic. An
## array so CounselBox could show more than one line.
static func lines(topic: StringName, speaker: StringName, context: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	speaker = Counselor.valid(speaker)
	var options: Array = topics().get(String(topic), {}).get(String(speaker), [])
	if options.is_empty():
		return result
	var line: Array = options[_rng.randi_range(0, options.size() - 1)]
	result.append({"speaker": speaker, "expression": StringName(line[0]),
			"text": String(line[1]).format(context)})
	return result
