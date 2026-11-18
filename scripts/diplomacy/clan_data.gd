class_name ClanData
extends Resource
## Static definition of a clan on the campaign map (GDD §15, M14b): a 6×6 grid (M18e) with the kingdom
## in the top-left corner (HOME) and one clan on each other square. One .tres per clan in data/clans/.

## A side of the kingdom board (where an invasion takes land).
enum Direction { NONE, NORTH, EAST, SOUTH, WEST }
enum Personality { PEACEFUL, AGGRESSIVE, MERCHANT, ISOLATED }

const DIRECTION_NAMES: Array[String] = ["Ở xa", "Phía Bắc", "Phía Đông", "Phía Nam", "Phía Tây"]
const PERSONALITY_NAMES: Array[String] = ["Ôn hòa", "Hiếu chiến", "Thương nhân", "Cô lập"]
## The campaign map is GRID_SIZE × GRID_SIZE squares (6×6 since M18e). The fixed map of
## data/clans/ (tests) has the kingdom on HOME; a new game puts it on a random edge square
## (ClanLayout, Diplomacy.home).
const GRID_SIZE := 6
const HOME := Vector2i.ZERO

@export var clan_id: StringName
@export var display_name: String
@export_multiline var description: String
## Banner color on the world map.
@export var color: Color = Color.WHITE
## Square on the campaign map (0..GRID_SIZE-1 in both axes; never HOME).
@export var grid: Vector2i = Vector2i(1, 0)
@export var personality: Personality = Personality.PEACEFUL
## Most soldiers the clan can field at the start of a game (its army regrows to this, and it
## grows over time, Wars.max_strength_at). GDD §15.
@export var military_strength: int = 50
## Player unit id -> relative weight of that unit type in the clan's army.
@export var army_units: Dictionary[StringName, float] = {}
## Resources this clan has plenty of (sells them cheaply).
@export var surplus: Array[StringName] = []
## Resources this clan lacks (pays more for them).
@export var deficit: Array[StringName] = []
## Relation at the start of a game, -100..100.
@export var start_relation: int = 0
## Relation drifts back toward this value every turn.
@export var base_relation: int = 0
## Clans that send soldiers to defend this one when the kingdom attacks it (GDD §9.7).
## Keep it mutual: list each pair in both files.
@export var friends: Array[StringName] = []


## Steps from HOME on the fixed map (1..10): farther clans are stronger.
func ring() -> int:
	return grid_distance(grid, HOME)


static func grid_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Board side a clan in `dir` borders: NORTH = Vector2i.UP (top edge), … NONE = ZERO.
static func direction_vector(dir: Direction) -> Vector2i:
	match dir:
		Direction.NORTH:
			return Vector2i.UP
		Direction.EAST:
			return Vector2i.RIGHT
		Direction.SOUTH:
			return Vector2i.DOWN
		Direction.WEST:
			return Vector2i.LEFT
	return Vector2i.ZERO


## The direction of `offset` on the map (the larger axis wins; east / south on a tie).
static func direction_of(offset: Vector2i) -> Direction:
	if offset == Vector2i.ZERO:
		return Direction.NONE
	if absi(offset.x) >= absi(offset.y):
		return Direction.EAST if offset.x > 0 else Direction.WEST
	return Direction.SOUTH if offset.y > 0 else Direction.NORTH


## All clans, sorted by clan_id.
static func load_all() -> Array[ClanData]:
	var result: Array[ClanData] = []
	result.assign(DataLibrary.load_folder("res://data/clans/", &"clan_id").values())
	return result
