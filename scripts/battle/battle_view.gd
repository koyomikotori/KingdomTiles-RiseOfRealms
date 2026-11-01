class_name BattleView
extends Control
## Draws a battle as it happens (GDD §7.5): back-row units in the side zones, melee units in the
## middle field, the charge at contact, gun and arrow volleys, figures knocked away as soldiers
## fall and broken units fleeing, the winners cheering. Pixel art from GameArt (GDD §13, M12b):
## animated sprite sheets with the clothes tinted in each side's color, a sky / mountains / field
## backdrop with the kingdom's walls (defending) or the enemy camp (attacking), stratagem effects.
## Read-only: it looks at the BattleSide units the simulator updates and never changes them.

## One figure on the field stands for this many soldiers (was 4: big late-game armies lagged;
## a full 20-man squad is now 3 figures).
const SOLDIERS_PER_FIGURE := 7
## Width share of each side zone (18% of the screen out of the 80% this control covers).
const SIDE_ZONE_SHARE := 18.0 / 80.0
## Sprites (16×16, the bodyguard 24×20) are drawn ×3; spacing is in screen pixels.
const SPRITE_SCALE := 3.0
const FIGURE_SPACING := Vector2(30, 34)
const FIGURES_PER_ROW := 5
## Pixels per battle-second when units walk or charge.
const MOVE_SPEED := 200.0
## Melee units start running this many battle-seconds before contact.
const CHARGE_LEAD := 1.2
## Distance between the clash line and each unit's front figure.
const CLASH_GAP := 22.0
## Before the charge, the front row stands this much further forward than the row behind it.
const FRONT_ROW_LEAD := 130.0
## How far each further rank stands behind the one in front.
const RANK_GAP := 110.0
const GRAVITY := 900.0
## Pixels per battle-second when a figure steps forward to fill a gap in its unit.
const STEP_UP_SPEED := 60.0
## Pixels per battle-second when a unit shifts lanes to close a gap left by a fallen unit.
const LANE_SPEED := 70.0
## Screen-left side, screen-right side.
const SIDE_COLORS: Array[Color] = [Color(0.4, 0.6, 1.0), Color(0.95, 0.4, 0.35)]
## How far ahead of the front row the commander's guard stands.
const GENERAL_LEAD := 60.0
## The commander rides freely: lanes per battle-second while switching to an enemy's lane, and
## how close (in lanes' height) an enemy must be to count as straight ahead.
const GUARD_LANE_SPEED := 180.0
const GUARD_AHEAD_RANGE := 50.0
## The strategist stands behind their army and raises the fan this long after a stratagem.
const ADVISOR_CAST_TIME := 1.4
## How far units lent by another clan lean toward that clan's banner color.
const ALLY_COLOR_WEIGHT := 0.55
const SKY_TOP_COLOR := Color(0.45, 0.68, 0.9)
const SKY_HORIZON_COLOR := Color(0.82, 0.91, 0.97)
const GROUND_COLOR := Color(0.47, 0.76, 0.35)
const ZONE_LINE_COLOR := Color(1, 1, 1, 0.12)
const BULLET_COLOR := Color(1.0, 0.9, 0.5)
const ARROW_COLOR := Color(0.85, 0.75, 0.55)
const CANNONBALL_COLOR := Color(0.18, 0.17, 0.17)
## Artillery balls fly this long (battle-seconds), this high above the straight line.
const CANNONBALL_FLIGHT := 0.7
const CANNONBALL_ARC := 90.0
## Backdrop pieces are pixel art drawn ×3 (mountains, clouds, town, camp) and ×2 (field).
const BACKDROP_SCALE := 3.0
const GROUND_SCALE := 2.0
const CLOUD_SPEED := 6.0
## Animation speed per sprite state, in frames per second.
const STATE_FPS: Dictionary[StringName, float] = {&"stand": 2.0, &"walk": 7.0, &"attack": 4.0, &"fall": 1.0,
		&"cheer": 3.0}
## Archers keep drawing their bows this long after a volley.
const SHOT_POSE_TIME := 0.8
const EFFECT_TIME := 1.6
const EFFECT_SCALE := 3.0
## Officer sprite kinds (GameArt.officer_sprite picks the variant from the officer's look): the
## commander rides at the head of the bodyguard, the strategist stands behind the army.
## A duel (M16e, Generals.duel_side): the two generals alone, riding back and forth together
## (DUEL_SWAY px each way, up and down by DUEL_LANE_SWAY) while closing in and pulling apart
## (half the gap swings between (DUEL_GAP_MID ± DUEL_GAP_SWING) × CLASH_GAP); they strike when
## close (DUEL_STRIKE_GAP). Speeds in radians per battle second.
const DUEL_SWAY := 160.0
const DUEL_SWAY_SPEED := 0.5
const DUEL_LANE_SWAY := 60.0
const DUEL_LANE_SPEED := 0.7
const DUEL_GAP_MID := 4.2
const DUEL_GAP_SWING := 2.1
const DUEL_LUNGE_SPEED := 1.6
const DUEL_STRIKE_GAP := 2.8
const DUEL_MOVE_SPEED := 320.0
const GENERAL_KIND: StringName = &"general"
const ADVISOR_KIND: StringName = &"advisor"


class Figure:
	extends RefCounted
	enum State { STAND, FLY, FLEE, GONE }
	## Current place in the unit's block, moving toward `slot`.
	var offset: Vector2
	## Place the figure is walking to (figures step forward as the ones in front fall).
	var slot: Vector2
	var state := State.STAND
	## Absolute position while flying or fleeing.
	var pos: Vector2
	var velocity: Vector2
	var rotation := 0.0
	var spin := 0.0
	var phase: float


class UnitView:
	extends RefCounted
	var unit: BattleSide.Unit
	var battle_side: int
	## 0 = drawn on the left, 1 = on the right.
	var screen_side: int
	var lane_y := 0.0
	## Lane the unit is moving to; changes when units in the same group break or are wiped out.
	var lane_target := 0.0
	var pos := Vector2.ZERO
	var figures: Array[Figure] = []
	## Battle time of the unit's last gun or arrow volley (for the shooting pose).
	var last_volley := -100.0
	## The commander's bodyguard only: the enemy unit it rides at (null before the charge).
	var guard_target: UnitView


## A short-lived stratagem effect (fire, smoke, sparkle) over a unit.
class Effect:
	extends RefCounted
	var kind: StringName
	var pos: Vector2
	var age := 0.0
	var delay := 0.0


class Projectile:
	extends RefCounted
	var kind: StringName  # &"bullet", &"arrow", &"cannonball" (lobbed, M13)
	var from: Vector2
	var to: Vector2
	## Battle-seconds before it appears, then how long it flies.
	var delay := 0.0
	var duration := 0.3
	var age := 0.0


var _simulator: BattleSimulator
var _left_side := BattleRecord.DEFENDER
var _views: Array = [[], []]  # per battle side: Array[UnitView]
var _projectiles: Array[Projectile] = []
var _effects: Array[Effect] = []
var _clock := 0.0
var _rng := RandomNumberGenerator.new()
## Lanes depend on this control's size, which is only known once it is laid out.
var _laid_out := false
## Per battle side: battle time of the advisor's last stratagem (for the casting pose).
var _advisor_cast: Array[float] = [-100.0, -100.0]


## `left_side` is the battle side (BattleRecord.ATTACKER / DEFENDER) drawn on the left.
func setup(simulator: BattleSimulator, left_side: int) -> void:
	_simulator = simulator
	_left_side = left_side
	_rng.seed = 1
	# The field and mountains are tiled textures.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	for s in 2:
		var side := simulator.record.sides[s]
		for unit in side.units:
			var view := UnitView.new()
			view.unit = unit
			view.battle_side = s
			view.screen_side = 0 if s == left_side else 1
			for k in (1 if _is_duelist(unit) else ceili(float(unit.start_soldiers) / SOLDIERS_PER_FIGURE)):
				var figure := Figure.new()
				figure.offset = _figure_offset(k, view.screen_side)
				figure.slot = figure.offset
				figure.phase = _rng.randf() * TAU
				view.figures.append(figure)
			_views[s].append(view)
	resized.connect(_layout)


## Advances animations by `battle_delta` battle-seconds (0 while paused) and spawns effects for
## the simulator events that just happened.
func update_view(battle_delta: float, new_events: Array[Dictionary]) -> void:
	if not _laid_out:
		_layout()
	_clock += battle_delta
	for event in new_events:
		_spawn_effects(event)
	for s in 2:
		for view: UnitView in _views[s]:
			if view.unit.is_general_guard:
				_update_guard_target(view)
	for s in 2:
		_assign_lanes()
		for view: UnitView in _views[s]:
			_move_unit(view, battle_delta)
			_update_figures(view, battle_delta)
	for projectile in _projectiles:
		projectile.age += battle_delta
	_projectiles = _projectiles.filter(func(p: Projectile) -> bool: return p.age < p.delay + p.duration)
	for effect in _effects:
		effect.age += battle_delta
	_effects = _effects.filter(func(e: Effect) -> bool: return e.age < e.delay + EFFECT_TIME)
	queue_redraw()


## After a skip: jump every unit to its final place and drop pending effects.
func snap_to_end() -> void:
	_projectiles.clear()
	for s in 2:
		for view: UnitView in _views[s]:
			view.pos.x = _target_x(view)
			view.lane_y = view.lane_target
			view.pos.y = view.lane_y
			var standing := view.figures.filter(func(f: Figure) -> bool: return f.state == Figure.State.STAND)
			var fallen := maxi(0, standing.size() - _figures_wanted(view))
			for i in standing.size():
				var figure: Figure = standing[i]
				if i < fallen:
					figure.state = Figure.State.GONE
				else:
					figure.slot = _figure_offset(i - fallen, view.screen_side)
					figure.offset = figure.slot
			if view.unit.broken:
				for figure in view.figures:
					if figure.state == Figure.State.STAND:
						figure.state = Figure.State.GONE
	queue_redraw()


# --- Layout -------------------------------------------------------------------------------

func _zone_width() -> float:
	return size.x * SIDE_ZONE_SHARE


func _ground_top() -> float:
	return size.y * 0.32


func _is_in_side_zone(unit: BattleSide.Unit) -> bool:
	return unit.row == UnitData.Row.BACK


## Places every unit at its lane and current target. Runs again when the control is resized.
func _layout() -> void:
	if size.x <= 0.0:
		return
	_laid_out = true
	_assign_lanes()
	for s in 2:
		for view: UnitView in _views[s]:
			view.lane_y = view.lane_target
			view.pos = Vector2(_target_x(view), view.lane_y)


## Spreads each group (side zone / each field row) evenly over the ground band. Only units still
## fighting count, so the survivors close up when a unit breaks or is wiped out.
func _assign_lanes() -> void:
	var top := _ground_top() + 50.0
	var bottom := size.y - 30.0
	for s in 2:
		var groups := {}
		for view: UnitView in _views[s]:
			if not view.unit.is_active():
				continue
			if _is_duelist(view.unit):
				view.lane_target = (top + bottom) * 0.5 + (sin(_clock * DUEL_LANE_SPEED) * DUEL_LANE_SWAY if _duelling() else 0.0)
				continue
			# The commander's guard leads from the middle, then rides into its target's lane.
			if view.unit.is_general_guard:
				view.lane_target = view.guard_target.lane_y if view.guard_target != null else (top + bottom) * 0.5
				continue
			var key := -1 if _is_in_side_zone(view.unit) else int(view.unit.row)
			if not groups.has(key):
				groups[key] = []
			groups[key].append(view)
		for key in groups:
			var members: Array = groups[key]
			for i in members.size():
				members[i].lane_target = top + (i + 0.5) * (bottom - top) / members.size()


func _home_x(view: UnitView) -> float:
	var zone := _zone_width()
	var x: float
	if _is_in_side_zone(view.unit):
		x = zone * 0.5 + FIGURE_SPACING.x * (FIGURES_PER_ROW - 1) * 0.5
	else:
		x = zone + (FIGURES_PER_ROW * FIGURE_SPACING.x + (FRONT_ROW_LEAD if view.unit.row == UnitData.Row.FRONT else 0.0))
		if view.unit.is_general_guard:
			x += GENERAL_LEAD
	return x if view.screen_side == 0 else size.x - x


## Where the unit wants to stand right now: home before the charge, the clash line once melee
## starts (units behind the front line queue up behind it).
func _target_x(view: UnitView) -> float:
	if _simulator.time < BattleSimulator.CONTACT_TIME - CHARGE_LEAD:
		return _home_x(view)
	if _is_duelist(view.unit):
		var center := size.x * 0.5 + (sin(_clock * DUEL_SWAY_SPEED) * DUEL_SWAY if _duelling() else 0.0)
		return center - _facing(view.screen_side) * (_duel_gap() if _duelling() else CLASH_GAP)
	if view.unit.is_general_guard and view.guard_target != null:
		return view.guard_target.pos.x - _facing(view.screen_side) * CLASH_GAP * 2.0
	var side := _simulator.record.sides[view.battle_side]
	var rank := maxi(0, int(view.unit.row) - maxi(0, side.front_row()))
	if view.unit.data.is_ranged() and rank > 0 and not view.unit.data.melee_after_volley:
		return _home_x(view)
	var offset := CLASH_GAP + rank * RANK_GAP
	if view.unit.is_general_guard:
		offset = maxf(0.0, offset - GENERAL_LEAD * 0.5)
	return size.x * 0.5 - offset if view.screen_side == 0 else size.x * 0.5 + offset


static func _is_duelist(unit: BattleSide.Unit) -> bool:
	return unit.data.unit_id == Generals.DUELIST_ID


## The duel is on: past the charge and not over.
func _duelling() -> bool:
	return _simulator.time >= BattleSimulator.CONTACT_TIME - CHARGE_LEAD and not _simulator.finished


## Half the distance between the two duelists right now.
func _duel_gap() -> float:
	return CLASH_GAP * (DUEL_GAP_MID + DUEL_GAP_SWING * sin(_clock * DUEL_LUNGE_SPEED))


## Left side faces right (+1), right side faces left (-1).
func _facing(screen_side: int) -> float:
	return 1.0 if screen_side == 0 else -1.0


## The unit's position is its front figure; the rest of the block stands behind it.
func _figure_offset(index: int, screen_side: int) -> Vector2:
	var column := index % FIGURES_PER_ROW
	var row := index / FIGURES_PER_ROW
	var back := -(column * FIGURE_SPACING.x + (row % 2) * FIGURE_SPACING.x * 0.5)
	return Vector2(back * _facing(screen_side), (row - 0.5) * FIGURE_SPACING.y)


# --- Animation ----------------------------------------------------------------------------

func _move_unit(view: UnitView, delta: float) -> void:
	view.pos.x = move_toward(view.pos.x, _target_x(view), (DUEL_MOVE_SPEED if _is_duelist(view.unit) else MOVE_SPEED) * delta)
	var lane_speed := GUARD_LANE_SPEED if view.unit.is_general_guard else LANE_SPEED
	view.lane_y = move_toward(view.lane_y, view.lane_target, lane_speed * delta)
	view.pos.y = view.lane_y


## The commander rides at the enemy straight ahead in its lane; with nobody there, at the enemy in
## the nearest other lane (side zones included). The target is kept until it breaks or dies.
func _update_guard_target(view: UnitView) -> void:
	if not view.unit.is_active() or _simulator.time < BattleSimulator.CONTACT_TIME - CHARGE_LEAD:
		view.guard_target = null
		return
	if view.guard_target != null and view.guard_target.unit.is_active():
		return
	view.guard_target = null
	var best_score := INF
	for enemy: UnitView in _views[1 - view.battle_side]:
		if not enemy.unit.is_active():
			continue
		var lane_gap := absf(enemy.lane_y - view.lane_y)
		var distance := absf(enemy.pos.x - view.pos.x)
		# Straight ahead wins; otherwise the closest lane, then the closest unit.
		var score := distance if lane_gap < GUARD_AHEAD_RANGE else 100000.0 + lane_gap * 10.0 + distance
		if score < best_score:
			best_score = score
			view.guard_target = enemy


func _figures_wanted(view: UnitView) -> int:
	if _is_duelist(view.unit):
		return 1 if view.unit.alive() > 0 else 0
	return ceili(float(view.unit.alive()) / SOLDIERS_PER_FIGURE)


func _update_figures(view: UnitView, delta: float) -> void:
	var standing := view.figures.filter(func(f: Figure) -> bool: return f.state == Figure.State.STAND)
	var back := -_facing(view.screen_side)
	# Fallen soldiers: the front figures are knocked backwards out of the formation...
	var fallen := maxi(0, standing.size() - _figures_wanted(view))
	for i in fallen:
		var figure: Figure = standing[i]
		figure.state = Figure.State.FLY
		figure.pos = view.pos + figure.offset
		figure.velocity = Vector2(back * _rng.randf_range(120, 220), -_rng.randf_range(220, 360))
		figure.spin = back * _rng.randf_range(6, 12)
	# ...and the ones behind step forward into their places.
	for i in range(fallen, standing.size()):
		standing[i].slot = _figure_offset(i - fallen, view.screen_side)
	# Broken unit: everyone left runs for their own edge.
	if view.unit.broken:
		for figure in view.figures:
			if figure.state == Figure.State.STAND:
				figure.state = Figure.State.FLEE
				figure.pos = view.pos + figure.offset
				figure.velocity = Vector2(back * _rng.randf_range(160, 220), 0)
	for figure in view.figures:
		match figure.state:
			Figure.State.STAND:
				figure.offset = figure.offset.move_toward(figure.slot, STEP_UP_SPEED * delta)
			Figure.State.FLY:
				figure.velocity.y += GRAVITY * delta
				figure.pos += figure.velocity * delta
				figure.rotation += figure.spin * delta
				if figure.pos.y > size.y + 40 or figure.pos.x < -40 or figure.pos.x > size.x + 40:
					figure.state = Figure.State.GONE
			Figure.State.FLEE:
				figure.pos += figure.velocity * delta
				if figure.pos.x < -40 or figure.pos.x > size.x + 40:
					figure.state = Figure.State.GONE


func _spawn_effects(event: Dictionary) -> void:
	if event.type == &"stratagem":
		_spawn_stratagem(event)
		return
	if event.type != &"gun_volley" and event.type != &"arrow_volley":
		return
	var shooter: UnitView = _views[event.side][event.unit]
	shooter.last_volley = _simulator.time
	var enemy_side := 1 - int(event.side)
	var targets: Array = []
	var front := _simulator.record.sides[enemy_side].front_row()
	for view: UnitView in _views[enemy_side]:
		if view.unit.is_active() and (event.type == &"arrow_volley" or event.get("all_rows", false) or int(view.unit.row) == front):
			targets.append(view)
	if targets.is_empty():
		return
	var count := clampi(_figures_wanted(shooter) * 2, 4, 16)
	for i in count:
		var target: UnitView = targets[_rng.randi() % targets.size()]
		var land := target.pos + Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-20, 20))
		var start := shooter.pos + Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-15, 5))
		if event.get("all_rows", false):
			# Artillery: a few heavy balls lobbed over the lines, smoke where they land.
			if i % 3 == 0:
				var delay := _rng.randf_range(0.0, 0.3)
				_add_projectile(&"cannonball", start, land, delay, CANNONBALL_FLIGHT)
				var smoke := Effect.new()
				smoke.kind = &"smoke"
				smoke.pos = land
				smoke.delay = delay + CANNONBALL_FLIGHT
				_effects.append(smoke)
		elif event.type == &"gun_volley":
			_add_projectile(&"bullet", start, land, _rng.randf_range(0.0, 0.15), 0.22)
		else:
			# Up and out of the frame, then down onto the target from above.
			var apex := Vector2(start.x + _facing(shooter.screen_side) * _rng.randf_range(60, 140), -30)
			var delay := _rng.randf_range(0.0, 0.25)
			_add_projectile(&"arrow", start, apex, delay, 0.45)
			_add_projectile(&"arrow", Vector2(land.x - _facing(shooter.screen_side) * 60, -30), land, delay + 0.75, 0.4)


## Fire, smoke or sparkles over the stratagem's targets; arrow rain falls on the enemy.
func _spawn_stratagem(event: Dictionary) -> void:
	var side := _simulator.record.sides[event.side]
	var stratagem: StratagemData = null
	for candidate in side.stratagems:
		if candidate.stratagem_id == event.stratagem:
			stratagem = candidate
	if stratagem == null:
		return
	_advisor_cast[int(event.side)] = _simulator.time
	var target_side := 1 - int(event.side) if stratagem.targets_enemy() else int(event.side)
	var targets: Array[UnitView] = []
	for view: UnitView in _views[target_side]:
		if view.unit.is_active():
			targets.append(view)
	if stratagem.target == StratagemData.Target.ENEMY_LARGEST and not targets.is_empty():
		targets.sort_custom(func(a: UnitView, b: UnitView) -> bool: return a.unit.alive() > b.unit.alive())
		targets = [targets[0]]
	elif stratagem.target == StratagemData.Target.ENEMY_RANGED:
		targets = targets.filter(func(v: UnitView) -> bool: return v.unit.data.is_ranged())
	for view in targets:
		for i in 4:
			var spot := view.pos + Vector2(-_facing(view.screen_side) * _rng.randf_range(0, 80), _rng.randf_range(-30, 10))
			if stratagem.effect == &"arrows":
				_add_projectile(&"arrow", Vector2(spot.x - 60, -30), spot, _rng.randf_range(0.0, 0.5), 0.45)
			else:
				var effect := Effect.new()
				effect.kind = stratagem.effect
				effect.pos = spot
				effect.delay = _rng.randf_range(0.0, 0.4)
				_effects.append(effect)


func _add_projectile(kind: StringName, from: Vector2, to: Vector2, delay: float, duration: float) -> void:
	var projectile := Projectile.new()
	projectile.kind = kind
	projectile.from = from
	projectile.to = to
	projectile.delay = delay
	projectile.duration = duration
	_projectiles.append(projectile)


# --- Drawing ------------------------------------------------------------------------------

func _draw() -> void:
	_draw_backdrop()
	var zone := _zone_width()
	for x in [zone, size.x - zone]:
		draw_line(Vector2(x, _ground_top()), Vector2(x, size.y), ZONE_LINE_COLOR, 2.0)
	if _simulator == null:
		return
	for s in 2:
		_draw_advisor(s)
	for s in 2:
		for view: UnitView in _views[s]:
			_draw_unit(view)
	for projectile in _projectiles:
		_draw_projectile(projectile)
	for effect in _effects:
		_draw_effect(effect)


## Sky, drifting clouds, far mountains and the field; the kingdom's walls behind the player when
## defending, the enemy's camp (in its colors) when attacking.
func _draw_backdrop() -> void:
	var horizon := _ground_top()
	var bands := 6
	for i in bands:
		var color := SKY_TOP_COLOR.lerp(SKY_HORIZON_COLOR, float(i) / (bands - 1))
		draw_rect(Rect2(0, horizon * i / bands, size.x, horizon / bands + 1), color)
	var cloud := GameArt.battle(&"cloud")
	if cloud != null:
		for i in 3:
			var x := fposmod(i * size.x / 3.0 + _clock * CLOUD_SPEED * (1 + i * 0.3), size.x + 120.0) - 100.0
			_draw_scaled(cloud, Vector2(x, horizon * (0.12 + i * 0.13)), BACKDROP_SCALE)
	var mountains := GameArt.battle(&"mountains")
	if mountains != null:
		var height := mountains.get_size().y * BACKDROP_SCALE
		draw_set_transform(Vector2(0, horizon - height), 0.0, Vector2.ONE * BACKDROP_SCALE)
		draw_texture_rect(mountains, Rect2(0, 0, size.x / BACKDROP_SCALE + 1, mountains.get_size().y), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var ground := GameArt.battle(&"ground")
	if ground != null:
		draw_set_transform(Vector2(0, horizon), 0.0, Vector2.ONE * GROUND_SCALE)
		draw_texture_rect(ground, Rect2(0, 0, size.x / GROUND_SCALE + 1, (size.y - horizon) / GROUND_SCALE + 1), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_rect(Rect2(0, horizon, size.x, size.y - horizon), GROUND_COLOR)
	var defending := _left_side == BattleRecord.DEFENDER
	var piece := GameArt.battle(&"town" if defending else &"camp")
	if piece == null:
		return
	var piece_size := piece.get_size() * BACKDROP_SCALE
	var x := 8.0 if defending else size.x - piece_size.x - 8.0
	var at := Vector2(x, horizon - piece_size.y + 10)
	_draw_scaled(piece, at, BACKDROP_SCALE)
	if not defending:
		var team := GameArt.battle(&"camp_team")
		if team != null:
			_draw_scaled(team, at, BACKDROP_SCALE, _simulator.record.sides[1 - _left_side].color)


func _draw_scaled(texture: Texture2D, at: Vector2, scale: float, tint: Color = Color.WHITE) -> void:
	draw_texture_rect(texture, Rect2(at, texture.get_size() * scale), false, tint)


func _draw_unit(view: UnitView) -> void:
	var facing := _facing(view.screen_side)
	var fighting := _simulator.is_melee_started() and absf(view.pos.x - _target_x(view)) < 1.0 \
			and not _is_in_side_zone(view.unit) and absf(view.lane_y - view.lane_target) < 2.0
	var running := absf(view.pos.x - _target_x(view)) >= 1.0
	if _is_duelist(view.unit) and _duelling():
		# Riding all the time; striking whenever the two are close.
		fighting = _duel_gap() < CLASH_GAP * DUEL_STRIKE_GAP
		running = not fighting
	var shooting := _simulator.time - view.last_volley < SHOT_POSE_TIME
	var cheering := _simulator.finished and _simulator.record.winner == view.battle_side and view.unit.is_active()
	# The commander rides at the head of the bodyguard on their own horse, until they fall.
	var leader: Figure = null
	if view.unit.is_general_guard and not _simulator.record.sides[view.battle_side].general_fallen:
		for figure in view.figures:
			if figure.state == Figure.State.STAND:
				leader = figure
				break
	var base_id := view.unit.data.get_sprite_id()
	var side := _simulator.record.sides[view.battle_side]
	var leader_id := GameArt.officer_sprite(GENERAL_KIND, side.general_look, side.general_weapon)
	var tints := GameArt.unit_tints(_clothes_color(view))
	var leader_tints := GameArt.unit_tints(_clothes_color(view), side.general_look)
	for figure in view.figures:
		var sprite_id := leader_id if figure == leader else base_id
		var figure_tints := leader_tints if figure == leader else tints
		match figure.state:
			Figure.State.STAND:
				var state := &"stand"
				if cheering:
					state = &"cheer"
				elif running:
					state = &"walk"
				elif fighting or shooting:
					state = &"attack"
				var frame := _frame(state, figure.phase)
				if shooting and not fighting and not running and not cheering:
					frame = 0 if _simulator.time - view.last_volley < SHOT_POSE_TIME * 0.5 else 1
				_draw_sprite(sprite_id, view.pos + figure.offset, 0.0, facing, state, frame, 0.0, figure_tints)
			Figure.State.FLY:
				_draw_sprite(sprite_id, figure.pos, figure.rotation, facing, &"fall", 0, 0.25, figure_tints)
			Figure.State.FLEE:
				_draw_sprite(sprite_id, figure.pos, 0.0, -facing, &"walk", _frame(&"walk", figure.phase), 0.35,
						figure_tints)
	if view.unit.ally != null:
		_draw_banner(view, facing, view.unit.ally.color, 18.0)
	if leader != null:
		_draw_banner(view, facing, Color(1.0, 0.82, 0.25), 44.0)


## The side's strategist (Advisors.assist) stands behind its army: fan raised while casting,
## cheering with the winners.
func _draw_advisor(battle_side: int) -> void:
	var side := _simulator.record.sides[battle_side]
	if side.advisor_name.is_empty():
		return
	var screen_side := 0 if battle_side == _left_side else 1
	var x := _zone_width() * 0.22
	var foot := Vector2(x if screen_side == 0 else size.x - x, _ground_top() + 46.0)
	var state := &"stand"
	if _simulator.finished and _simulator.record.winner == battle_side:
		state = &"cheer"
	elif _simulator.time - _advisor_cast[battle_side] < ADVISOR_CAST_TIME:
		state = &"attack"
	_draw_sprite(GameArt.officer_sprite(ADVISOR_KIND, side.advisor_look), foot, 0.0, _facing(screen_side), state,
			_frame(state, 0.0), 0.0, GameArt.unit_tints(side.color, side.advisor_look))


func _frame(state: StringName, phase: float) -> int:
	return int(_clock * STATE_FPS.get(state, 2.0) + phase) % GameArt.UNIT_FRAMES


## Clothes color: the side's color, or the lending clan's for allied units.
func _clothes_color(view: UnitView) -> Color:
	if view.unit.ally != null:
		return view.unit.ally.color
	return _simulator.record.sides[view.battle_side].color


## One figure standing on `foot` (the sprite's bottom middle), facing right when facing > 0, its
## layers tinted with `tints` (GameArt.unit_tints).
func _draw_sprite(sprite_id: StringName, foot: Vector2, rotation: float, facing: float, state: StringName,
		frame: int, darken: float, tints: Dictionary) -> void:
	GameArt.draw_unit(self, sprite_id, foot, rotation, Vector2(facing * SPRITE_SCALE, SPRITE_SCALE), state, frame,
			tints, darken)


## A pennant on a pole above the unit's first standing figure: the lending clan's color for allies,
## gold (and taller) for the commander's bodyguard.
func _draw_banner(view: UnitView, facing: float, color: Color, height: float) -> void:
	for figure in view.figures:
		if figure.state != Figure.State.STAND:
			continue
		var foot := view.pos + figure.offset
		var top := foot.y - 20.0 * SPRITE_SCALE - height
		var pole_x := foot.x - 3.0 * SPRITE_SCALE * facing
		draw_line(Vector2(pole_x, foot.y - 15.0 * SPRITE_SCALE), Vector2(pole_x, top), Color(0.25, 0.17, 0.1), 2.0)
		var flag := PackedVector2Array([Vector2(pole_x, top), Vector2(pole_x + 16.0 * facing, top + 5.0),
				Vector2(pole_x, top + 10.0)])
		draw_colored_polygon(flag, color)
		flag.append(flag[0])
		draw_polyline(flag, Color(0.17, 0.11, 0.07), 1.0)
		return


## Side color, tinted toward the lending clan's banner color for allied units (soldier bars on
## the battle screen's info columns).
static func unit_color(unit: BattleSide.Unit, screen_side: int) -> Color:
	var color := SIDE_COLORS[screen_side]
	return color.lerp(unit.ally.color, ALLY_COLOR_WEIGHT) if unit.ally != null else color


func _draw_projectile(projectile: Projectile) -> void:
	var t := (projectile.age - projectile.delay) / projectile.duration
	if t < 0.0 or t > 1.0:
		return
	var direction := (projectile.to - projectile.from).normalized()
	var pos := projectile.from.lerp(projectile.to, t)
	if projectile.kind == &"bullet":
		draw_line(pos, pos - direction * 14.0, BULLET_COLOR, 1.5)
		return
	if projectile.kind == &"cannonball":
		pos.y -= sin(t * PI) * CANNONBALL_ARC
		draw_circle(pos, 4.0, CANNONBALL_COLOR)
		draw_circle(pos - Vector2(1.2, 1.2), 1.5, CANNONBALL_COLOR.lightened(0.4))
		return
	var arrow := GameArt.effect(&"arrow")
	if arrow == null:
		draw_line(pos, pos - direction * 10.0, ARROW_COLOR, 1.2)
		return
	draw_set_transform(pos, direction.angle(), Vector2.ONE * SPRITE_SCALE)
	draw_texture(arrow, -arrow.get_size() * Vector2(1.0, 0.5))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Two-frame effect strip, fading out at the end.
func _draw_effect(effect: Effect) -> void:
	var time := effect.age - effect.delay
	if time < 0.0:
		return
	var strip := GameArt.effect(effect.kind)
	if strip == null:
		return
	var frame_size := Vector2(strip.get_size().x / 2.0, strip.get_size().y)
	var region := Rect2(Vector2(int(time * 6.0) % 2 * frame_size.x, 0), frame_size)
	var alpha := clampf((EFFECT_TIME - time) / 0.4, 0.0, 1.0)
	var rise := -time * 10.0 if effect.kind != &"fire" else 0.0
	var draw_size := frame_size * EFFECT_SCALE
	draw_texture_rect_region(strip, Rect2(effect.pos + Vector2(-draw_size.x * 0.5, -draw_size.y + rise), draw_size),
			region, Color(1, 1, 1, alpha))
