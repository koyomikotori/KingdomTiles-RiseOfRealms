class_name Ruler
extends Officer
## The player's ruler (Chúa công, GDD §24, M16h): one of PRESETS (a face and an outfit) and a
## name. No stats and no battles; shown (portrait only) on the new game screen and in the castle
## window. Their foot sprites wait for the duel mini game (M16j).
## Saved as {"preset", "name"}.

const DEFAULT_NAME := "Chúa công"
const MAX_NAME_LENGTH := 24
## Outfits (portrait parts body_ruler_<outfit> / ruler_hat_<outfit>_<m|f>,
## tools/art/portrait_art.py).
const OUTFIT_NAMES: Dictionary[StringName, String] = {&"dragon": "Long bào", &"armor": "Chiến bào",
		&"brocade": "Nho phục"}
## Blond hair (no officer color is this light).
const BLOND := Color(0.93, 0.74, 0.3)
## Each preset: a title, an outfit and the face (OfficerLook fields; "blond" overrides the hair
## color). The portrait is assets/portraits/ruler/ruler_<index>.png (GameArt.ruler_portrait).
const PRESETS: Array[Dictionary] = [
	{"title": "Thiên tử", "outfit": &"dragon", "gender": &"m", "skin": 0, "hair_style": 0, "hair_color": 0,
			"eyes": 0, "brows": 1, "beard": 0, "accent": 1},
	{"title": "Nữ hoàng", "outfit": &"dragon", "gender": &"f", "skin": 0, "hair_style": 1, "hair_color": 0,
			"eyes": 1, "brows": 0, "beard": 0, "accent": 1},
	{"title": "Bá vương", "outfit": &"armor", "gender": &"m", "skin": 1, "hair_style": 2, "hair_color": 0,
			"blond": true, "eyes": 2, "brows": 1, "beard": 1, "accent": 4},
	{"title": "Nữ tướng quân", "outfit": &"armor", "gender": &"f", "skin": 0, "hair_style": 2, "hair_color": 0,
			"blond": true, "eyes": 0, "brows": 1, "beard": 0, "accent": 0},
	{"title": "Mưu chủ", "outfit": &"brocade", "gender": &"m", "skin": 0, "hair_style": 1, "hair_color": 4,
			"eyes": 1, "brows": 0, "beard": 0, "accent": 5},
	{"title": "Nữ mưu chủ", "outfit": &"brocade", "gender": &"f", "skin": 0, "hair_style": 0, "hair_color": 4,
			"eyes": 2, "brows": 0, "beard": 0, "accent": 2},
]

var preset := 0


static func from_preset(index: int, ruler_name: String = "") -> Ruler:
	var ruler := Ruler.new()
	ruler.preset = posmod(index, PRESETS.size())
	var trimmed := ruler_name.strip_edges().left(MAX_NAME_LENGTH)
	ruler.name = trimmed if not trimmed.is_empty() else DEFAULT_NAME
	# The gold portrait frame.
	ruler.stars = 6
	var entry := PRESETS[ruler.preset]
	var look := OfficerLook.new()
	for field in ["gender", "skin", "hair_style", "hair_color", "eyes", "brows", "beard", "accent"]:
		look.set(field, entry[field])
	if entry.get("blond", false):
		look.hair_override = BLOND
	ruler.look = look
	return ruler


func outfit() -> StringName:
	return PRESETS[preset].outfit


func title() -> String:
	return PRESETS[preset].title


## "Thiên tử · Long bào"
func describe() -> String:
	return "%s · %s" % [title(), OUTFIT_NAMES[outfit()]]


func to_save() -> Dictionary:
	return {"preset": preset, "name": name}


## {} (older saves) gives the first preset.
static func from_save(data: Dictionary) -> Ruler:
	return from_preset(int(data.get("preset", 0)), String(data.get("name", "")))
