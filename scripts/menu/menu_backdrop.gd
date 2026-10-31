class_name MenuBackdrop
extends Control
## The blurred scene behind the main menu (GDD §15 M14j, like Kairosoft games): ordinary gameplay
## playing by itself, a battle against a clan and an expedition stage in turn. Both are fought by
## a throwaway kingdom that is never saved; the scene is drawn in a SubViewport wider than the
## screen and shown through a blur, dimmed, without sounds, while the camera pans slowly from side
## to side (so the fighting in the middle shows beside the menu). Read-only, no input.

const BLUR_SHADER := """
shader_type canvas_item;
uniform float radius = 3.0;
void fragment() {
	vec2 step_size = TEXTURE_PIXEL_SIZE * radius;
	vec4 sum = vec4(0.0);
	float total = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			float weight = 1.0 / (1.0 + float(x * x + y * y));
			sum += texture(TEXTURE, UV + vec2(float(x), float(y)) * step_size) * weight;
			total += weight;
		}
	}
	COLOR = sum / total;
}
"""
const BLUR_RADIUS := 2.5
## The scene's width as a share of the screen's, and the seconds the camera takes to pan from one
## side to the other (eased, back and forth; each scene starts on the left).
const PAN_WIDTH := 1.8
const PAN_TIME := 18.0
const DIM := Color(0.08, 0.06, 0.04, 0.35)
## Battle seconds per real second, so a battle does not drag on behind the menu.
const BATTLE_SPEED := 2.0
const EXPEDITION_SPEED := 1.0
## Real seconds the end of a scene stays before the next one, and the fade between them.
const HOLD_TIME := 2.0
const FADE_TIME := 0.6
## The kingdom's army in both scenes: unit ids, one squad each (some picked at random).
const ARMY_POOL: Array[StringName] = [&"elite_swordsman", &"elite_spearman", &"swordsman", &"spearman",
		&"elite_archer", &"archer", &"crossbow_pro", &"heavy_cavalry", &"light_cavalry", &"light_artillery"]
const ARMY_SIZE := Vector2i(5, 8)

var _viewport: SubViewport
var _screen: TextureRect
var _state: KingdomState
var _rng := RandomNumberGenerator.new()
var _scene: Control
var _playback: BattlePlayback
var _battle_view: BattleView
var _next_is_battle := true
var _hold := -1.0
var _pan_clock := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rng.randomize()
	_viewport = SubViewport.new()
	_viewport.disable_3d = true
	add_child(_viewport)
	clip_contents = true
	_screen = TextureRect.new()
	_screen.texture = _viewport.get_texture()
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen.stretch_mode = TextureRect.STRETCH_SCALE
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = BLUR_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"radius", BLUR_RADIUS)
	_screen.material = material
	add_child(_screen)
	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	resized.connect(_fit)
	_fit()
	_state = _new_state()
	_next_scene()


func _fit() -> void:
	var screen_size := size if size.x > 0.0 else get_viewport_rect().size
	_viewport.size = Vector2i(roundi(screen_size.x * PAN_WIDTH), roundi(screen_size.y))
	_screen.size = Vector2(_viewport.size)


func _process(delta: float) -> void:
	_pan_clock += delta
	var travel := _screen.size.x - size.x
	_screen.position.x = -travel * (0.5 - 0.5 * cos(_pan_clock * PI / PAN_TIME))
	if _playback != null:
		_battle_view.update_view(delta * BATTLE_SPEED, _playback.advance(delta))
		if _playback.is_finished() and _hold < 0.0:
			_hold = HOLD_TIME
	if _hold >= 0.0:
		_hold -= delta
		_screen.modulate.a = clampf(_hold / FADE_TIME, 0.0, 1.0)
		if _hold < 0.0:
			_next_scene()
	elif _screen.modulate.a < 1.0:
		_screen.modulate.a = minf(1.0, _screen.modulate.a + delta / FADE_TIME)


## A kingdom for the scenes only: the whole board owned, so an uprising zone has room.
func _new_state() -> KingdomState:
	var terrains := TerrainLibrary.load_all()
	var generator := PieceGenerator.new(PieceShapeLibrary.load_all(), terrains, _rng.randi())
	var state := KingdomState.new(BoardData.create_starting_board(12), PieceHand.new(generator), terrains,
			BuildingData.load_all(), UnitData.load_all(), _rng.randi())
	state.start()
	state.raid = null
	for cell in state.board.get_all_cells():
		cell.owned = true
		if cell.building_id != BoardData.CASTLE_ID:
			cell.terrain_id = &"grass"
	state.player_color = KingdomState.PLAYER_COLORS[_rng.randi() % KingdomState.PLAYER_COLORS.size()]
	return state


## Replaces the army, the commander and the advisor with new random ones.
func _muster() -> void:
	for squad in _state.army.squads.duplicate():
		_state.army.remove_squad(squad)
	var pool := ARMY_POOL.duplicate()
	pool.shuffle()
	for unit_id in pool.slice(0, _rng.randi_range(ARMY_SIZE.x, ARMY_SIZE.y)):
		_state.army.add_squad(unit_id, _state.units[unit_id].squad_size)
	for general in _state.generals.generals.duplicate():
		_state.generals.dismiss(general)
	for advisor in _state.advisors.advisors.duplicate():
		_state.advisors.dismiss(advisor)
	# The castle level sets the expedition's stages and ambushes.
	_state.castle_level = _rng.randi_range(3, 6)
	var general := _state.generals.generate(_rng.randi_range(1, 3))
	_state.generals.add(general)
	_state.generals.set_commander(general)
	_state.advisors.add(_state.advisors.generate(_rng.randi_range(1, 3)))


func _next_scene() -> void:
	if _scene != null:
		_scene.queue_free()
	_scene = null
	_playback = null
	_battle_view = null
	_hold = -1.0
	_pan_clock = 0.0
	_screen.modulate.a = 0.0
	_muster()
	if _next_is_battle:
		_start_battle()
	else:
		_start_expedition()
	_next_is_battle = not _next_is_battle


## The kingdom attacks a random clan with about as many soldiers as its own army.
func _start_battle() -> void:
	var clans := _state.wars.fronts.keys()
	var clan_id: StringName = clans[_rng.randi() % clans.size()]
	var kingdom := _state.create_kingdom_side(clan_id, false)
	var soldiers := roundi(kingdom.start_total() * _rng.randf_range(0.8, 1.3))
	var clan := _state.wars.create_clan_side(clan_id, soldiers, _state.units)
	var simulator := BattleSimulator.new(kingdom, clan, _rng.randi())
	_playback = BattlePlayback.new(simulator)
	_playback.speed = BATTLE_SPEED
	_battle_view = BattleView.new()
	_battle_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_battle_view.clip_contents = true
	_battle_view.setup(simulator, BattleRecord.ATTACKER)
	_scene = _battle_view
	_viewport.add_child(_scene)


## One expedition stage against a fresh uprising zone, replayed side-on.
func _start_expedition() -> void:
	if not _state.uprising.is_active():
		_state.uprising.start(_state.board)
	var squads: Array[Army.Squad] = []
	squads.assign(_state.army.squads)
	_state.expedition = null
	var result := _state.start_expedition(_state.generals.generals[0], _state.advisors.advisors[0], squads)
	if result != KingdomState.ExpeditionResult.OK:
		_start_battle()
		return
	_state.expedition.stage = _rng.randi_range(0, _state.expedition.stages - 1)
	var stage := _state.expedition.run_stage(_state, _rng)
	_state.expedition.finish(_state)
	_state.expedition = null
	var view := ExpeditionView.new()
	view.quiet = true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.setup(stage.battles, "")
	view.set_speed(EXPEDITION_SPEED)
	view.finished.connect(func() -> void: _hold = HOLD_TIME)
	_scene = view
	_viewport.add_child(_scene)
