class_name OfficerLook
extends RefCounted
## How a general or advisor looks (GDD §13, M12c): gender, skin, hair, eyes, brows, beard and an
## accent color. Picks the portrait parts and tints them, and picks the battle sprite variant.
## Saved with the officer; older saves get one made from the officer's name (always the same).

const GENDERS: Array[StringName] = [&"m", &"f"]
const SKIN_TONES: Array[Color] = [Color(1.0, 0.86, 0.74), Color(0.96, 0.78, 0.62), Color(0.88, 0.68, 0.52),
		Color(0.74, 0.55, 0.4)]
const HAIR_COLORS: Array[Color] = [Color(0.16, 0.12, 0.1), Color(0.3, 0.2, 0.13), Color(0.46, 0.3, 0.17),
		Color(0.58, 0.24, 0.16), Color(0.82, 0.82, 0.86)]
## Helmet plume and trims for generals, hairpins and hat bands for advisors.
const ACCENT_COLORS: Array[Color] = [Color(0.82, 0.2, 0.16), Color(0.95, 0.75, 0.2), Color(0.2, 0.62, 0.46),
		Color(0.55, 0.3, 0.75), Color(0.35, 0.6, 0.92), Color(0.92, 0.92, 0.9)]
## Portrait part counts (tools/art/portrait_art.py draws them).
const HAIR_STYLES := 3
const EYE_STYLES := 3
const BROW_STYLES := 2
## Beard 0 is none; only men grow one.
const BEARD_STYLES := 3

var gender: StringName = &"m"
var skin := 0
var hair_style := 0
var hair_color := 0
## A hair color outside HAIR_COLORS (alpha 0 = none): the rulers' blond hair (M16h). Not saved;
## a ruler's look comes from its preset.
var hair_override := Color(0, 0, 0, 0)
var eyes := 0
var brows := 0
var beard := 0
var accent := 0
## The pool portrait file this officer was given (GameArt.assign_portrait), or "".
var portrait := ""


static func random(rng: RandomNumberGenerator) -> OfficerLook:
	var look := OfficerLook.new()
	look.gender = GENDERS[rng.randi_range(0, GENDERS.size() - 1)]
	look.skin = rng.randi_range(0, SKIN_TONES.size() - 1)
	look.hair_style = rng.randi_range(0, HAIR_STYLES - 1)
	# Silver hair is rarer.
	look.hair_color = rng.randi_range(0, HAIR_COLORS.size() - 1) if rng.randf() < 0.15 else rng.randi_range(0, HAIR_COLORS.size() - 2)
	look.eyes = rng.randi_range(0, EYE_STYLES - 1)
	look.brows = rng.randi_range(0, BROW_STYLES - 1)
	look.beard = rng.randi_range(0, BEARD_STYLES - 1) if look.gender == &"m" else 0
	look.accent = rng.randi_range(0, ACCENT_COLORS.size() - 1)
	return look


## The same look every time for the same text (older saves: made from the officer's name).
static func from_seed(text: String) -> OfficerLook:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(text)
	return random(rng)


func is_female() -> bool:
	return gender == &"f"


func skin_color() -> Color:
	return SKIN_TONES[clampi(skin, 0, SKIN_TONES.size() - 1)]


func hair_tint() -> Color:
	if hair_override.a > 0.0:
		return hair_override
	return HAIR_COLORS[clampi(hair_color, 0, HAIR_COLORS.size() - 1)]


func accent_color() -> Color:
	return ACCENT_COLORS[clampi(accent, 0, ACCENT_COLORS.size() - 1)]


func to_save() -> Dictionary:
	return {"gender": String(gender), "skin": skin, "hair_style": hair_style, "hair_color": hair_color, "eyes": eyes,
			"brows": brows, "beard": beard, "accent": accent, "portrait": portrait}


static func from_save(data: Dictionary) -> OfficerLook:
	var look := OfficerLook.new()
	look.gender = StringName(data.gender)
	look.skin = int(data.skin)
	look.hair_style = int(data.hair_style)
	look.hair_color = int(data.hair_color)
	look.eyes = int(data.eyes)
	look.brows = int(data.brows)
	look.beard = int(data.beard)
	look.accent = int(data.accent)
	look.portrait = String(data.get("portrait", ""))
	return look
