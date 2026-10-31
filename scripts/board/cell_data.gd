class_name CellData
extends RefCounted
## Runtime state of one board cell.
## Terrain, ownership and building are separate on purpose: a forest cell can be
## owned by the player and also hold a lumber camp.

const NO_TERRAIN: StringName = &""
const NO_BUILDING: StringName = &""

var coord: Vector2i
var terrain_id: StringName = NO_TERRAIN
var owned: bool = false
## Special cell from a land piece (marked ◆). Lost when another piece covers it.
var is_key: bool = false
var building_id: StringName = NO_BUILDING
## Top-left cell of the building covering this cell. Only meaningful when has_building().
var building_origin: Vector2i = Vector2i.ZERO
## Level of the building covering this cell (same on all its cells; GDD §8, economy v2).
var building_level := 1
## Turns of construction left (GDD §8, M12d); 0 = finished. While above 0 the building does nothing.
var building_turns := 0
## The construction is an upgrade to building_level + 1 (the building stays at building_level).
var building_upgrading := false

## Held by the uprising (Uprising.apply, M14i): locked, its building does nothing. Not saved here;
## the uprising marks its cells again on load.
var occupied := false

func _init(p_coord: Vector2i) -> void:
	coord = p_coord


func has_terrain() -> bool:
	return terrain_id != NO_TERRAIN


func has_building() -> bool:
	return building_id != NO_BUILDING


## A building is being built or upgraded here (and does nothing until it is finished).
func is_constructing() -> bool:
	return has_building() and building_turns > 0


## A building that does nothing now: being built or upgraded, or held by the uprising (M14i).
func is_idle() -> bool:
	return is_constructing() or occupied
