class_name UnitData
extends Resource
## Static definition of a soldier type. Player units live in data/units/, enemy-only units
## (bandits, …) in data/enemy_units/. Combat rules: GDD §7.6.
## One recruitment gives one squad of `squad_size` soldiers.

## Formation row. Melee and gun fire hit the front-most row that still has soldiers.
enum Row { FRONT, MIDDLE, BACK }
## How the unit fights at range. MELEE units have no ranged attack.
enum AttackKind { MELEE, BOW, GUN }

const ROW_NAMES: Array[String] = ["Hàng trước", "Hàng giữa", "Hàng sau"]
## Kind of soldier, the recruit window's categories after "Tất cả" (M13b).
enum Type { SWORD, SPEAR, SHIELD, CAVALRY, BOW, CROSSBOW, FIREARM, HORSE_ARCHER, MONK }
const TYPE_NAMES: Array[String] = ["Kiếm", "Thương", "Đao thuẫn", "Kỵ binh", "Cung", "Nỏ", "Hỏa khí", "Kỵ cung",
		"Võ tăng"]
## Name colors per tier (tier() − 1): peasant brown, elite silver, royal gold. On wooden buttons,
## and darker on paper (M13b).
const TIER_COLORS_ON_WOOD: Array[Color] = [Color(0.9, 0.74, 0.54), Color(0.82, 0.9, 1.0), Color(1.0, 0.84, 0.3)]
const TIER_COLORS_ON_PAPER: Array[Color] = [Color(0.47, 0.31, 0.15), Color(0.3, 0.4, 0.55), Color(0.72, 0.5, 0.03)]
const ATTACK_KIND_NAMES: Array[String] = ["Cận chiến", "Cung", "Súng"]

@export var unit_id: StringName
@export var display_name: String
## Battle sprite sheet in assets/units/ (GameArt.unit_sheet); empty = the unit_id.
@export var sprite_id: StringName = &""
## Position in the army list, lowest first.
@export var sort_order: int = 0
## Soldiers per recruited squad (HP / Number at full strength).
@export var squad_size: int = 20

@export_group("Combat")
@export var row: Row = Row.FRONT
@export var attack_kind: AttackKind = AttackKind.MELEE
@export var melee_attack: int = 5
## Reduces casualties taken in melee.
@export var melee_defense: int = 5
## Reduces casualties taken from bullets and arrows.
@export var armor: int = 0
## Extra melee damage on the first clash only.
@export var charge_attack: int = 0
## Kind of soldier (recruit window categories).
@export var unit_type: Type = Type.SWORD
## Starting morale. Drops as the squad takes losses; at 0 the squad breaks.
@export var morale: int = 6
## Ranged damage. Only BOW and GUN units use it.
@export var range_attack: int = 0
## Seconds between arrow volleys. Guns fire a single volley and ignore this.
@export var reload_time: float = 5.0
## Casualties one soldier deals compared with an ordinary soldier (heroes and their guards hit like
## several men; GDD §8, M11d).
@export var damage_per_soldier: float = 1.0
## Casualties needed to bring one soldier down.
@export var hit_points: float = 1.0
## Mounted: charges hard, and anti-charge units (charge_resist) hit it harder (GDD §8, M13).
@export var is_cavalry: bool = false
## Share of incoming charge damage this unit shrugs off; its melee blows against cavalry are
## raised by the same share (spearmen, M13).
@export var charge_resist: float = 0.0
## Share of the target's armor this unit's arrows / bullets ignore (crossbows, M13).
@export var armor_pierce: float = 0.0
## The single gun volley hits every row instead of the front one (artillery, M13).
@export var volley_all_rows: bool = false
## After its gun volley the unit marches to the front row and fights in melee (musketeers, M13).
@export var melee_after_volley: bool = false
## After this many arrow volleys the unit stops shooting, rides to the front row and charges
## (horse archers, M16f); 0 = never.
@export var charge_after_volleys: int = 0
## "Tĩnh tâm" (monks, M16f): no morale lost when the commander falls, and enemy stratagems do not
## touch its morale.
@export var steadfast: bool = false

@export_group("Recruitment")
## Paid per squad.
@export var recruit_cost: Dictionary[StringName, int] = {}
## Paid every turn per squad.
@export var upkeep: Dictionary[StringName, int] = {}
## Finished buildings the kingdom needs, building_id -> lowest level (the highest-level one of
## that type counts), e.g. {&"barracks": 3}. Empty = no building needed (GDD §8, M13).
@export var required_buildings: Dictionary[StringName, int] = {}
## Minimum owned cells per terrain, e.g. {&"forest": 3} for archers.
@export var required_terrain: Dictionary[StringName, int] = {}
## 1–3 for units that need no barracks (monks, M16f); 0 = from the barracks level.
@export var tier_level: int = 0


## 1 peasant, 2 elite, 3 royal guard: tier_level, else from the barracks level it needs (1, 3, 6).
func tier() -> int:
	if tier_level > 0:
		return tier_level
	var barracks: int = required_buildings.get(&"barracks", 1)
	return 3 if barracks >= 6 else (2 if barracks >= 3 else 1)


func tier_color(on_wood: bool) -> Color:
	return (TIER_COLORS_ON_WOOD if on_wood else TIER_COLORS_ON_PAPER)[tier() - 1]


func is_ranged() -> bool:
	return attack_kind != AttackKind.MELEE


## Ranged units that end up fighting in melee anyway (musketeers, horse archers).
func fights_in_melee_later() -> bool:
	return melee_after_volley or charge_after_volleys > 0


## Player unit types, sorted by sort_order.
static func load_all() -> Array[UnitData]:
	return _load_sorted("res://data/units/")


## Enemy-only unit types (bandits, …), sorted by sort_order.
static func load_enemies() -> Dictionary[StringName, UnitData]:
	var result: Dictionary[StringName, UnitData] = {}
	for unit in _load_sorted("res://data/enemy_units/"):
		result[unit.unit_id] = unit
	return result


static func _load_sorted(folder: String) -> Array[UnitData]:
	var result: Array[UnitData] = []
	result.assign(DataLibrary.load_folder(folder, &"unit_id").values())
	result.sort_custom(func(a: UnitData, b: UnitData) -> bool: return a.sort_order < b.sort_order)
	return result


## Which battle sprite sheet draws this unit.
func get_sprite_id() -> StringName:
	return unit_id if sprite_id == &"" else sprite_id
