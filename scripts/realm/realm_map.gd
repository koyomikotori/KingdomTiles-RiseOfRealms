class_name RealmMap
extends RefCounted
## The fixed map of the realm phase (Phân Chia Thiên Hạ, GDD §33, M18f-a): six regions of five
## towns on a 3×2 grid, the kingdom always in the top-left region. Each region is a diamond: the
## capital in the middle (slot CAPITAL), four towns around it joined to it and to each other in a
## ring; neighboring regions are joined by two roads. Which nation sits in which of the other five
## regions is shuffled each game (Realm.start). Also the five nations' fixed data (NATIONS).
##
## Towns are numbered region × TOWNS_PER_REGION + slot. Positions are in map units
## (MAP_SIZE), for RealmMapView.

const REGIONS := 6
const TOWNS_PER_REGION := 5
const TOWN_COUNT := REGIONS * TOWNS_PER_REGION
const GRID := Vector2i(3, 2)
const REGION_SIZE := 320.0
const MAP_SIZE := Vector2(960, 640)
## Slots: north, west, capital, east, south.
enum Slot { NORTH, WEST, CAPITAL, EAST, SOUTH }
const CAPITAL := Slot.CAPITAL
const SLOT_POSITIONS: Array[Vector2] = [Vector2(160, 52), Vector2(52, 160), Vector2(160, 160), Vector2(268, 160),
		Vector2(160, 268)]
## Roads inside a region (slot pairs): the capital to every town, then the ring.
const REGION_ROADS: Array[Vector2i] = [Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 3), Vector2i(2, 4),
		Vector2i(0, 1), Vector2i(0, 3), Vector2i(4, 1), Vector2i(4, 3)]
## Roads to the region on the right (left slot, right slot) and to the region below (top, bottom).
const EAST_ROADS: Array[Vector2i] = [Vector2i(3, 1), Vector2i(0, 0)]
const SOUTH_ROADS: Array[Vector2i] = [Vector2i(4, 0), Vector2i(3, 3)]
## The kingdom's region.
const HOME_REGION := 0

## The five nations (GDD §33a): name, banner color (and another when the player's color is too
## close), the four other towns' names (slots N, W, E, S) and the capital's, and the units they
## favor at each strength (index = distance from the kingdom − 1).
const NATIONS: Array[Dictionary] = [
	{"id": &"xich_viem", "name": "Xích Viêm Quốc", "color": Color(0.7, 0.16, 0.14), "alt": Color(0.55, 0.22, 0.1),
		"capital": "Xích Thành", "towns": ["Hỏa Lâm", "Đan Phong", "Viêm Giang", "Hồng Nham"],
		"trait": "Bộ binh nặng",
		"special": [{"elite_swordsman": 1.0, "shield_veteran": 1.0}, {"royal_swordguard": 1.0, "shield_guard": 1.0},
				{"royal_swordguard": 1.0, "shield_guard": 1.0}]},
	{"id": &"bac_mac", "name": "Bắc Mạc", "color": Color(0.55, 0.58, 0.62), "alt": Color(0.4, 0.42, 0.5),
		"capital": "Lang Cư", "towns": ["Phong Nguyên", "Mã Đề", "Sa Khẩu", "Tuyết Lĩnh"],
		"trait": "Kỵ binh",
		"special": [{"light_cavalry": 1.0, "horse_archer": 1.0}, {"lancer_cavalry": 1.0, "elite_horse_archer": 1.0},
				{"heavy_cavalry": 1.0, "royal_horse_archer": 1.0}]},
	{"id": &"thuong_lan", "name": "Thương Lan Quốc", "color": Color(0.16, 0.36, 0.72), "alt": Color(0.1, 0.5, 0.6),
		"capital": "Thương Lan Đô", "towns": ["Bích Ba", "Hải Môn", "Liễu Khê", "Vọng Hải"],
		"trait": "Cung thủ, nỏ binh",
		"special": [{"elite_archer": 1.0, "crossbow_pro": 1.0}, {"marksman_archer": 1.0, "crossbow_elite": 1.0},
				{"marksman_archer": 1.0, "crossbow_elite": 1.0}]},
	{"id": &"hoang_tho", "name": "Hoàng Thổ Quốc", "color": Color(0.78, 0.6, 0.18), "alt": Color(0.6, 0.45, 0.2),
		"capital": "Kim Đỉnh", "towns": ["Lôi Thạch", "Thiết Lô", "Hoàng Nguyên", "Cổ Đạo"],
		"trait": "Hỏa khí",
		"special": [{"elite_musketeer": 1.0, "light_artillery": 1.0}, {"elite_musketeer": 1.0, "light_artillery": 1.0},
				{"elite_musketeer": 1.0, "heavy_artillery": 1.0}]},
	{"id": &"tu_van", "name": "Tử Vân Quốc", "color": Color(0.5, 0.26, 0.66), "alt": Color(0.72, 0.3, 0.55),
		"capital": "Vân Đài", "towns": ["Thiền Lâm", "Tử Hà", "Linh Sơn", "Ngọc Tuyền"],
		"trait": "Võ tăng, trường thương",
		"special": [{"monk": 1.0, "elite_spearman": 1.0}, {"elite_monk": 1.0, "royal_pikeguard": 1.0},
				{"royal_monk": 1.0, "royal_pikeguard": 1.0}]},
]
## Banner colors closer than this to the player's switch to their "alt".
const COLOR_CLASH := 0.25


static func region_of(town: int) -> int:
	return town / TOWNS_PER_REGION


static func slot_of(town: int) -> int:
	return town % TOWNS_PER_REGION


static func town_id(region: int, slot: int) -> int:
	return region * TOWNS_PER_REGION + slot


static func is_capital(town: int) -> bool:
	return slot_of(town) == CAPITAL


static func region_cell(region: int) -> Vector2i:
	return Vector2i(region % GRID.x, region / GRID.x)


## Steps between a region and the kingdom's (1 … 3): the nations' strength grows with it.
static func region_distance(region: int) -> int:
	var cell := region_cell(region)
	return cell.x + cell.y


## Where the town is drawn: its slot in its region, nudged a little so the map looks less like a grid.
static func position(town: int) -> Vector2:
	var cell := region_cell(region_of(town))
	var nudge := Vector2(float((town * 37) % 23 - 11), float((town * 53) % 23 - 11)) * 1.6
	if is_capital(town):
		nudge *= 0.4
	return Vector2(cell) * REGION_SIZE + SLOT_POSITIONS[slot_of(town)] + nudge


## Every road as a pair of towns (lower id first).
static func roads() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for region in REGIONS:
		for road in REGION_ROADS:
			result.append(_pair(town_id(region, road.x), town_id(region, road.y)))
		var cell := region_cell(region)
		if cell.x + 1 < GRID.x:
			for road in EAST_ROADS:
				result.append(_pair(town_id(region, road.x), town_id(region + 1, road.y)))
		if cell.y + 1 < GRID.y:
			for road in SOUTH_ROADS:
				result.append(_pair(town_id(region, road.x), town_id(region + GRID.x, road.y)))
	return result


static func _pair(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))


## Towns one road away.
static func neighbors(town: int) -> Array[int]:
	var result: Array[int] = []
	for road in roads():
		if road.x == town:
			result.append(road.y)
		elif road.y == town:
			result.append(road.x)
	return result


static func are_neighbors(a: int, b: int) -> bool:
	return roads().has(_pair(a, b))


static func nation_data(nation_id: StringName) -> Dictionary:
	for data in NATIONS:
		if data.id == nation_id:
			return data
	return {}


## The nation's banner color in a game where the player wears `player_color`.
static func nation_color(nation_id: StringName, player_color: Color) -> Color:
	var data := nation_data(nation_id)
	if data.is_empty():
		return Color.GRAY
	var color: Color = data.color
	if _color_distance(color, player_color) < COLOR_CLASH:
		return data.alt
	return color


static func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
