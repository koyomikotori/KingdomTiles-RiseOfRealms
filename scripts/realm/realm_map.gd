class_name RealmMap
extends RefCounted
## The fixed map of the realm phase (Phân Chia Thiên Hạ, GDD §33, M18f-a; redrawn in M18g): six
## regions of five towns, the kingdom always in region 0 (top-left). Towns are placed by hand so
## each region has its own shape, and ROADS only join towns that are close (114–162 map units), so
## one road is one turn's march everywhere and a far town takes several. Which nation sits in which
## of the other five regions is shuffled each game (Realm.start). Also the five nations' fixed data
## (NATIONS).
##
## Towns are numbered region × TOWNS_PER_REGION + slot; the slot names are only rough directions
## inside the region. Positions are in map units (MAP_SIZE), for RealmMapView.

const REGIONS := 6
const TOWNS_PER_REGION := 5
const TOWN_COUNT := REGIONS * TOWNS_PER_REGION
## Regions laid out 3 × 2 for their distance from the kingdom (region_distance).
const GRID := Vector2i(3, 2)
const MAP_SIZE := Vector2(980, 650)
## Slots: north, west, capital, east, south.
enum Slot { NORTH, WEST, CAPITAL, EAST, SOUTH }
const CAPITAL := Slot.CAPITAL
## Every town's place on the map, by id.
const POSITIONS: Array[Vector2] = [
	Vector2(170, 60), Vector2(70, 170), Vector2(190, 175), Vector2(290, 120), Vector2(140, 280),
	Vector2(440, 70), Vector2(380, 190), Vector2(510, 165), Vector2(620, 85), Vector2(560, 270),
	Vector2(780, 60), Vector2(715, 175), Vector2(830, 180), Vector2(925, 110), Vector2(870, 290),
	Vector2(60, 400), Vector2(120, 520), Vector2(230, 440), Vector2(330, 360), Vector2(250, 580),
	Vector2(450, 380), Vector2(380, 500), Vector2(510, 490), Vector2(640, 400), Vector2(560, 600),
	Vector2(760, 390), Vector2(700, 520), Vector2(830, 480), Vector2(920, 400), Vector2(880, 590),
]
## Every road (lower id first): the shortest pairs that cross no other road, none longer than 165.
const ROADS: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 2), Vector2i(1, 4), Vector2i(2, 3), Vector2i(2, 4),
	Vector2i(3, 5), Vector2i(3, 6), Vector2i(4, 15), Vector2i(5, 6), Vector2i(5, 7), Vector2i(6, 7), Vector2i(7, 8),
	Vector2i(7, 9), Vector2i(8, 10), Vector2i(8, 11), Vector2i(9, 20), Vector2i(9, 23), Vector2i(10, 11),
	Vector2i(10, 12), Vector2i(10, 13), Vector2i(11, 12), Vector2i(12, 13), Vector2i(12, 14), Vector2i(14, 25),
	Vector2i(14, 28), Vector2i(15, 16), Vector2i(16, 17), Vector2i(16, 19), Vector2i(17, 18), Vector2i(17, 19),
	Vector2i(18, 20), Vector2i(18, 21), Vector2i(19, 21), Vector2i(20, 21), Vector2i(20, 22),
	Vector2i(21, 22), Vector2i(22, 23), Vector2i(22, 24), Vector2i(23, 25), Vector2i(23, 26), Vector2i(24, 26),
	Vector2i(25, 26), Vector2i(25, 27), Vector2i(25, 28), Vector2i(26, 27), Vector2i(27, 28), Vector2i(27, 29),
]
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


## Where the town is drawn (map units).
static func position(town: int) -> Vector2:
	return POSITIONS[town]


## Every road as a pair of towns (lower id first).
static func roads() -> Array[Vector2i]:
	return ROADS


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
