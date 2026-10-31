class_name ExpeditionView
extends Control
## Replays one expedition stage side-on (GDD §15 M14i, after Dungeon Village): the team marches
## left to right, one figure per unit in columns of LANES abreast (the general alone up front, then
## cavalry, melee, ranged, the advisor behind); each ambush comes in from the right, the two lines clash, and a unit that breaks or dies
## (from the BattleRecord's events and snapshots) is thrown off the screen. Battles follow each other
## without a break. Presentation only: the battles were already fought (Expedition.run_stage).

signal finished

const SPRITE_SCALE := 3.0
## Room each figure takes in the line: foot soldiers, riders, the mounted general.
const SLOT_GAP := 58.0
const RIDER_GAP := 78.0
const GENERAL_GAP := 100.0
## Units abreast in a column, the depth between them, how far each nearer lane steps back (an
## echelon, so the back lanes show), and which lane each one of a column takes (the middle first).
const LANES := 3
const LANE_GAP := 46.0
const LANE_STAGGER := 14.0
const LANE_FILL: Array[int] = [1, 0, 2]
## Space between the two front figures while fighting, and before the clash.
const CLASH_GAP := 34.0
const MARCH_GAP := 140.0
const MARCH_TIME := 1.8
const APPROACH_TIME := 1.2
const MIN_FIGHT_TIME := 2.5
const MAX_FIGHT_TIME := 6.0
## Battle seconds per replay second while fighting.
const FIGHT_PACE := 6.0
const AFTER_TIME := 0.9
const END_TIME := 1.6
const FLY_TIME := 1.3
const FLY_SPEED := Vector2(320, -560)
const GRAVITY := 1100.0
const SPIN := 9.0
const MARCH_SPEED := 160.0
const ANIM_FPS := 6.0
const CLASH_INTERVAL := 0.3
const BAR_SIZE := Vector2(34, 4)
const BAR_BACK := Color(0, 0, 0, 0.45)
const BAR_TEAM := Color(0.45, 0.85, 0.45)
const BAR_ENEMY := Color(0.95, 0.45, 0.35)
const BANNER_COLOR := Color(1.0, 0.88, 0.45)

## One phase of the replay: {"kind": &"march" | &"approach" | &"fight" | &"after" | &"end",
## "battle": int, "start": float, "length": float}.
var _phases: Array[Dictionary] = []
var _battles: Array[BattleRecord] = []
var _clock := 0.0
var _speed := 1.0
var _scroll := 0.0
var _done := false
var _next_clash := 0.0
## When each unit of each battle leaves the fight, in battle seconds: _out[b][side][i] (INF = never).
var _out: Array = []
var _stage_text := ""
## No sounds and no banners (the main menu's backdrop, MenuBackdrop).
var quiet := false


func setup(battles: Array[BattleRecord], stage_text: String) -> void:
	_battles = battles
	_stage_text = stage_text
	var at := 0.0
	for b in battles.size():
		var record := battles[b]
		for kind: StringName in [&"march", &"approach", &"fight", &"after"]:
			var length := MARCH_TIME if kind == &"march" else APPROACH_TIME if kind == &"approach" else AFTER_TIME
			if kind == &"fight":
				length = clampf(record.duration / FIGHT_PACE, MIN_FIGHT_TIME, MAX_FIGHT_TIME)
			_phases.append({"kind": kind, "battle": b, "start": at, "length": length})
			at += length
		_out.append(_out_times(record))
	_phases.append({"kind": &"end", "battle": battles.size() - 1, "start": at, "length": END_TIME})
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_speed(speed: float) -> void:
	_speed = speed


func skip() -> void:
	_clock = total_time()


func total_time() -> float:
	return _phases.back().start + _phases.back().length if not _phases.is_empty() else 0.0


func _process(delta: float) -> void:
	if _phases.is_empty():
		return
	var before := _clock
	_clock = minf(total_time(), _clock + delta * _speed)
	var phase := _phase_at(_clock)
	if phase.kind == &"march" or (phase.kind == &"approach"):
		_scroll += delta * _speed * MARCH_SPEED * (1.0 if phase.kind == &"march" else 0.4)
	if phase.kind == &"fight" and not quiet:
		if _phase_at(before).kind != &"fight":
			Sfx.play(&"charge")
		if _clock >= _next_clash:
			_next_clash = _clock + CLASH_INTERVAL
			Sfx.play([&"clash_1", &"clash_2", &"clash_3"].pick_random(), -8.0)
	if phase.kind == &"end" and _phase_at(before).kind != &"end" and not quiet:
		Sfx.play(&"complete")
	queue_redraw()
	if _clock >= total_time() and not _done:
		_done = true
		finished.emit()


func _phase_at(time: float) -> Dictionary:
	for phase in _phases:
		if time < phase.start + phase.length:
			return phase
	return _phases.back()


## Battle seconds shown at replay time `time` within battle `b` (0 before its fight, its whole
## length after).
func _battle_time(b: int, time: float) -> float:
	for phase in _phases:
		if phase.battle != b or phase.kind != &"fight":
			continue
		var t := clampf((time - phase.start) / phase.length, 0.0, 1.0)
		return t * _battles[b].duration
	return 0.0


func _out_times(record: BattleRecord) -> Array:
	var result := []
	for s in 2:
		var times := []
		times.resize(record.sides[s].units.size())
		times.fill(INF)
		result.append(times)
	for event in record.events:
		if event.type == &"broken" and event.unit >= 0 and event.unit < result[event.side].size():
			result[event.side][event.unit] = minf(result[event.side][event.unit], event.time)
	for snapshot in record.snapshots:
		for s in 2:
			var soldiers: Array = snapshot.soldiers[s]
			for i in soldiers.size():
				if soldiers[i] <= 0:
					result[s][i] = minf(result[s][i], snapshot.time)
	# The beaten side's last units run at the very end.
	var loser := record.loser()
	for i in result[loser].size():
		result[loser][i] = minf(result[loser][i], record.duration)
	return result


func _soldiers_at(record: BattleRecord, side: int, unit: int, time: float) -> float:
	var alive: float = record.sides[side].units[unit].start_soldiers
	for snapshot in record.snapshots:
		if snapshot.time > time:
			break
		var soldiers: Array = snapshot.soldiers[side]
		if unit < soldiers.size():
			alive = soldiers[unit]
	return alive


# --- Drawing ------------------------------------------------------------------------------

func _draw() -> void:
	if _phases.is_empty():
		return
	_draw_backdrop()
	var phase := _phase_at(_clock)
	var b: int = phase.battle
	var record := _battles[b]
	var battle_time := _battle_time(b, _clock)
	var ground := size.y * 0.78
	var front := size.x * 0.5
	# The team's slots, front first.
	var team := record.sides[BattleRecord.ATTACKER]
	var formation := _formation(team)
	var gap := CLASH_GAP if phase.kind == &"fight" or phase.kind == &"after" else MARCH_GAP
	if team.advisor_name != "":
		_draw_officer(&"advisor", team, Vector2(front - gap - formation.length - SLOT_GAP * 0.5, ground), 1.0, &"stand")
	for spot: Array in formation.spots:
		_draw_unit(record, BattleRecord.ATTACKER, spot[0], Vector2(front - gap - spot[1].x, ground + spot[1].y), 1.0,
				phase, battle_time)
	# The ambush: walking in from the right during the approach.
	if phase.kind != &"march":
		var enter := 1.0
		if phase.kind == &"approach":
			enter = clampf((_clock - phase.start) / phase.length, 0.0, 1.0)
		var enemy_front := front + gap + (1.0 - enter) * size.x * 0.6
		for spot: Array in _formation(record.sides[BattleRecord.DEFENDER]).spots:
			_draw_unit(record, BattleRecord.DEFENDER, spot[0], Vector2(enemy_front + spot[1].x, ground + spot[1].y), -1.0,
					phase, battle_time)
	if not quiet:
		_draw_banner(phase)


func _slot_width(unit: BattleSide.Unit) -> float:
	if unit.is_general_guard:
		return GENERAL_GAP
	return RIDER_GAP if unit.data.is_cavalry else SLOT_GAP


## Where each unit of `side` stands: {"spots": [[unit index, Vector2(distance behind the front, depth)]]
## sorted back lane first (the drawing order), "length": the line's length}. The general stands
## alone up front; the rest, in marching order, in columns of LANES abreast.
func _formation(side: BattleSide) -> Dictionary:
	var order := _team_order(side)
	var spots: Array = []
	var x := 0.0
	var start := 0
	while start < order.size():
		var count := 1 if side.units[order[start]].is_general_guard else mini(LANES, order.size() - start)
		var width := 0.0
		for k in count:
			width = maxf(width, _slot_width(side.units[order[start + k]]))
		for k in count:
			var lane: int = LANE_FILL[k] - 1
			spots.append([order[start + k], Vector2(x + width * 0.5 + lane * LANE_STAGGER, lane * LANE_GAP)])
		x += width + (LANE_STAGGER if count > 1 else 0.0)
		start += count
	spots.sort_custom(func(a: Array, b: Array) -> bool: return a[1].y < b[1].y)
	return {"spots": spots, "length": x}


## Unit indexes in marching order: the general's guard and cavalry, then melee, then ranged.
func _team_order(side: BattleSide) -> Array[int]:
	var order: Array[int] = []
	for i in side.units.size():
		order.append(i)
	var rank := func(unit: BattleSide.Unit) -> int:
		if unit.is_general_guard:
			return 0
		if unit.data.is_cavalry:
			return 1
		return 3 if unit.data.is_ranged() else 2
	order.sort_custom(func(a: int, b: int) -> bool: return rank.call(side.units[a]) < rank.call(side.units[b]))
	return order


func _draw_unit(record: BattleRecord, side: int, i: int, foot: Vector2, facing: float, phase: Dictionary,
		battle_time: float) -> void:
	var unit := record.sides[side].units[i]
	var out: float = _out[phase.battle][side][i]
	var state: StringName = &"walk" if phase.kind in [&"march", &"approach"] else &"stand"
	if phase.kind == &"fight":
		state = &"attack"
	elif phase.kind in [&"after", &"end"]:
		state = &"cheer" if record.winner == side else &"stand"
	var rotation := 0.0
	if battle_time >= out and phase.kind in [&"fight", &"after", &"end"]:
		# Thrown off the screen: up and away, spinning, gone after FLY_TIME.
		var flown := (_clock - _replay_time(phase.battle, out))
		if flown > FLY_TIME:
			return
		var away := -facing
		foot += Vector2(away * FLY_SPEED.x * flown, FLY_SPEED.y * flown + 0.5 * GRAVITY * flown * flown)
		rotation = away * SPIN * flown
		state = &"fall"
	var frame := int(_clock * ANIM_FPS) % GameArt.UNIT_FRAMES
	var color := record.sides[side].color
	if unit.is_general_guard:
		_draw_officer(&"general", record.sides[side], foot, facing, state, rotation)
	else:
		GameArt.draw_unit(self, unit.data.get_sprite_id(), foot, rotation, Vector2(facing * SPRITE_SCALE, SPRITE_SCALE),
				state, frame, GameArt.unit_tints(color))
	if state != &"fall":
		var share := _soldiers_at(record, side, i, battle_time) / maxf(1.0, unit.start_soldiers)
		var bar := Rect2(foot + Vector2(-BAR_SIZE.x * 0.5, 6), BAR_SIZE)
		draw_rect(bar, BAR_BACK)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(share, 0.0, 1.0), bar.size.y)),
				BAR_TEAM if side == BattleRecord.ATTACKER else BAR_ENEMY)


## Replay time at which battle `b` reaches `battle_time` seconds.
func _replay_time(b: int, battle_time: float) -> float:
	for phase in _phases:
		if phase.battle == b and phase.kind == &"fight":
			return phase.start + phase.length * clampf(battle_time / maxf(0.01, _battles[b].duration), 0.0, 1.0)
	return 0.0


func _draw_officer(kind: StringName, side: BattleSide, foot: Vector2, facing: float, state: StringName,
		rotation: float = 0.0) -> void:
	var look := side.general_look if kind == &"general" else side.advisor_look
	var sprite := GameArt.officer_sprite(kind, look, side.general_weapon if kind == &"general" else &"")
	var frame := int(_clock * ANIM_FPS) % GameArt.UNIT_FRAMES
	GameArt.draw_unit(self, sprite, foot, rotation, Vector2(facing * SPRITE_SCALE, SPRITE_SCALE), state, frame,
			GameArt.unit_tints(side.color, look))


func _draw_backdrop() -> void:
	var horizon := size.y * 0.55
	var bands := 6
	for i in bands:
		var color := BattleView.SKY_TOP_COLOR.lerp(BattleView.SKY_HORIZON_COLOR, float(i) / (bands - 1))
		draw_rect(Rect2(0, horizon * i / bands, size.x, horizon / bands + 1), color)
	var cloud := GameArt.battle(&"cloud")
	if cloud != null:
		for i in 3:
			var x := fposmod(i * size.x / 3.0 - _scroll * 0.1 + _clock * 4.0, size.x + 160.0) - 120.0
			_draw_scaled(cloud, Vector2(x, horizon * (0.12 + i * 0.13)), BattleView.BACKDROP_SCALE)
	var mountains := GameArt.battle(&"mountains")
	if mountains != null:
		var scale := BattleView.BACKDROP_SCALE
		var width := mountains.get_size().x * scale
		var shift := fposmod(_scroll * 0.25, width)
		draw_set_transform(Vector2(-shift, horizon - mountains.get_size().y * scale), 0.0, Vector2.ONE * scale)
		draw_texture_rect(mountains, Rect2(0, 0, (size.x + width) / scale + 1, mountains.get_size().y), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var ground := GameArt.battle(&"ground")
	if ground != null:
		var scale := BattleView.GROUND_SCALE
		var width := ground.get_size().x * scale
		var shift := fposmod(_scroll, width)
		draw_set_transform(Vector2(-shift, horizon), 0.0, Vector2.ONE * scale)
		draw_texture_rect(ground, Rect2(0, 0, (size.x + width) / scale + 1, (size.y - horizon) / scale + 1), true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_rect(Rect2(0, horizon, size.x, size.y - horizon), BattleView.GROUND_COLOR)


func _draw_scaled(texture: Texture2D, at: Vector2, scale: float) -> void:
	draw_set_transform(at, 0.0, Vector2.ONE * scale)
	draw_texture(texture, Vector2.ZERO)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## "Trận 2/3" while fighting; the stage's name at the start and its result at the end.
func _draw_banner(phase: Dictionary) -> void:
	var font := get_theme_default_font()
	var text := ""
	if phase.kind == &"end":
		text = "%s: %s" % [_stage_text, "VƯỢT ẢI!" if _battles.back().winner == BattleRecord.ATTACKER else "THẤT BẠI"]
	elif phase.battle == 0 and phase.kind == &"march":
		text = _stage_text
	elif phase.kind == &"approach":
		var boss := _battles[phase.battle].sides[BattleRecord.DEFENDER].general_name
		text = "Tướng nổi loạn %s!" % boss if boss != "" else "Phục kích! (%d/%d)" % [phase.battle + 1, _battles.size()]
	if text.is_empty():
		return
	var font_size := 40
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
	var at := Vector2((size.x - width) * 0.5, size.y * 0.22)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 8, Color(0.2, 0.1, 0.05))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, BANNER_COLOR)
