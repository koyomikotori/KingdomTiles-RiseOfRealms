class_name Counselor
extends RefCounted
## The two counselors who can narrate the game (GDD §25, M16i): Linh Nhi and Tử Uyên. The player
## picks one on the new game screen (KingdomState.counselor); only that one speaks (Counsel).
## Portraits are assets/portraits/counselor/<id>_<expression>.png (drawn by
## Gemini, docs/gemini_prompts.md); until they exist a generated portrait from FALLBACK_LOOKS.

const LINH_NHI := &"linh_nhi"
const TU_UYEN := &"tu_uyen"
const IDS: Array[StringName] = [LINH_NHI, TU_UYEN]
const NAMES: Dictionary[StringName, String] = {LINH_NHI: "Linh Nhi", TU_UYEN: "Tử Uyên"}
## One line for the new game screen.
const DESCRIPTIONS: Dictionary[StringName, String] = {
	LINH_NHI: "Vui tươi, hăng hái, khen nhiệt tình và luôn an ủi khi thất bại.",
	TU_UYEN: "Điềm tĩnh, nói thẳng và gọn, chỉ ra chỗ sai để lần sau làm tốt hơn.",
}
## Name colors on paper.
const NAME_COLORS: Dictionary[StringName, Color] = {LINH_NHI: Color(0.78, 0.25, 0.32),
		TU_UYEN: Color(0.2, 0.32, 0.5)}

const NEUTRAL := &"neutral"
const HAPPY := &"happy"
const CONCERNED := &"concerned"
const SURPRISED := &"surprised"
const EXPRESSIONS: Array[StringName] = [NEUTRAL, HAPPY, CONCERNED, SURPRISED]

const PORTRAIT_DIR := "res://assets/portraits/counselor/"
## Faces for the generated portrait (OfficerLook fields) while there is no drawn one.
const FALLBACK_LOOKS: Dictionary[StringName, Dictionary] = {
	LINH_NHI: {"gender": &"f", "skin": 0, "hair_style": 2, "hair_color": 1, "eyes": 1, "brows": 0,
			"beard": 0, "accent": 0},
	TU_UYEN: {"gender": &"m", "skin": 0, "hair_style": 1, "hair_color": 0, "eyes": 2, "brows": 1,
			"beard": 0, "accent": 4},
}


## A known id, or Linh Nhi (older saves, broken settings).
static func valid(id: StringName) -> StringName:
	return id if id in IDS else LINH_NHI


## The drawn portrait for this expression, the neutral one when it is missing, or null.
static func portrait(id: StringName, expression: StringName) -> Texture2D:
	for name in [expression, NEUTRAL]:
		var path := PORTRAIT_DIR + "%s_%s.png" % [id, name]
		if ResourceLoader.exists(path):
			return load(path)
	return null


## An Advisor wearing the counselor's fallback face, for PortraitView.layers.
static func fallback_officer(id: StringName) -> Advisor:
	var officer := Advisor.new()
	officer.name = NAMES[valid(id)]
	officer.stars = 4
	var look := OfficerLook.new()
	var fields: Dictionary = FALLBACK_LOOKS[valid(id)]
	for field: String in fields:
		look.set(field, fields[field])
	officer.look = look
	return officer
