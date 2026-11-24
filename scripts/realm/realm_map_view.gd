class_name RealmMapView
extends Control
## Draws the realm map (Phân Chia Thiên Hạ, GDD §33, M18f-a) on paper, fitted to the view: the land
## around each town tinted by its owner (territory, M18g: blobs that follow the towns, borders
## darker), the roads, a fort per town flying its owner's
## banner (capitals bigger, with a crown), enemy garrisons, and the kingdom's armies as flags.
## Armies with an order (GDD §34, M18g) fly a ringed flag and a dashed line that crawls and blinks
## toward where they go (green march, red siege, gold the way home, purple an interception).
## The nations' armies (M18f-b1) fly their nation's flags on the left of a town, an attack they
## announced drawn as a red dashed line with an arrow; the number under a town counts its garrison
## and armies.
## A click on a town emits `town_clicked`. Read-only: the screen decides what a click does.

signal town_clicked(town: int)

const ART_SCALE := 2.0
const CAPITAL_SCALE := 2.6
const ROAD_COLOR := Color(0.47, 0.32, 0.18, 0.8)
## Territory: one cell per TERRITORY_CELL map units, tinted by the nearest town's owner up to
## TERRITORY_REACH away; border cells darker.
const TERRITORY_CELL := 5.0
const TERRITORY_REACH := 120.0
## The tint fades out over the last TERRITORY_FADE map units of its reach.
const TERRITORY_FADE := 35.0
const TERRITORY_SMOOTH := 4
const TERRITORY_ALPHA := 0.24
const BORDER_ALPHA := 0.55
## Room around the map for the outer towns' labels (map units).
const PAD := Vector2(70, 40)
const SELECTED_COLOR := Color(0.85, 0.6, 0.12)
const MOVE_COLOR := Color(0.2, 0.6, 0.25)
const ATTACK_COLOR := Color(0.8, 0.15, 0.1)
const LABEL_OUTLINE := Color(0.96, 0.92, 0.8, 0.9)
const LABEL_FONT_SIZE := 13
const SMALL_FONT_SIZE := 11
## A click this close (map units) to a town picks it.
const PICK_RADIUS := 34.0
const BACKGROUND_COLOR := Color(0.91, 0.84, 0.66)
const HOME_COLOR := Color(0.78, 0.55, 0.1)
const INTERCEPT_COLOR := Color(0.55, 0.2, 0.65)
const ENEMY_ATTACK_COLOR := Color(0.75, 0.05, 0.05)
## Order lines: dash length and gap (map units), crawl speed, blink period (seconds).
const ORDER_DASH := 10.0
const ORDER_GAP := 7.0
const ORDER_SPEED := 22.0
const ORDER_BLINK := 0.9

var _time := 0.0

var realm: Realm
var player_color := KingdomState.PLAYER_COLOR
var kingdom_name := ""
var selected_town := -1
## The selected army's town, its reachable neighbors drawn as rings.
var selected_force: Realm.Force
## The current turn, for the revolt chance under captured towns.
var turn := 0
var _territory: ImageTexture
var _territory_key := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


## Order lines move: redraw while any army has an order.
func _process(delta: float) -> void:
	if realm == null or (not realm.forces.any(func(force: Realm.Force) -> bool: return force.has_order())
			and not realm.armies.any(func(army: NationArmy) -> bool: return army.has_target())):
		return
	_time += delta
	queue_redraw()


static func order_color(order: StringName) -> Color:
	match order:
		Realm.SIEGE:
			return ATTACK_COLOR
		Realm.HOME:
			return HOME_COLOR
		Realm.INTERCEPT:
			return INTERCEPT_COLOR
	return MOVE_COLOR


## Map units → view: the whole map fitted and centered.
func _scale() -> float:
	var full := RealmMap.MAP_SIZE + PAD * 2.0
	return minf(size.x / full.x, size.y / full.y)


func _origin() -> Vector2:
	return (size - RealmMap.MAP_SIZE * _scale()) * 0.5


func town_at(view_position: Vector2) -> int:
	if realm == null or _scale() <= 0.0:
		return -1
	var point := (view_position - _origin()) / _scale()
	var best := -1
	var best_distance := PICK_RADIUS
	for town in RealmMap.TOWN_COUNT:
		var distance := point.distance_to(RealmMap.position(town))
		if distance < best_distance:
			best = town
			best_distance = distance
	return best


## Where a town is drawn in the view (for tests and the tutorial).
func town_screen_position(town: int) -> Vector2:
	return _origin() + RealmMap.position(town) * _scale()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var town := town_at(event.position)
		if town >= 0:
			town_clicked.emit(town)
			accept_event()


func _draw() -> void:
	_draw_parchment()
	if realm == null or not realm.active:
		return
	draw_set_transform(_origin(), 0.0, Vector2.ONE * _scale())
	draw_texture_rect(_territory_texture(), Rect2(Vector2.ZERO, RealmMap.MAP_SIZE), false)
	for road in RealmMap.roads():
		_draw_road(RealmMap.position(road.x), RealmMap.position(road.y))
	_draw_reach()
	for force in realm.forces:
		_draw_order(force)
	for army in realm.armies:
		_draw_threat(army)
	for town in realm.towns:
		_draw_town(town)
	for town in realm.towns:
		_draw_forces(town.id)
		_draw_armies(town.id)
	draw_set_transform(Vector2.ZERO)


## The territory picture, rebuilt only when a town changes hands.
func _territory_texture() -> ImageTexture:
	var key := str(player_color) + ":" + ",".join(realm.towns.map(func(town: Realm.Town) -> String: return String(town.owner)))
	if _territory != null and key == _territory_key:
		return _territory
	_territory_key = key
	var cells := Vector2i((RealmMap.MAP_SIZE / TERRITORY_CELL).ceil())
	var owner := PackedInt32Array()
	owner.resize(cells.x * cells.y)
	for y in cells.y:
		for x in cells.x:
			var point := (Vector2(x, y) + Vector2(0.5, 0.5)) * TERRITORY_CELL
			var best := -1
			var best_distance := TERRITORY_REACH
			for town in RealmMap.TOWN_COUNT:
				var distance := point.distance_to(RealmMap.position(town))
				if distance < best_distance:
					best = town
					best_distance = distance
			owner[y * cells.x + x] = best
	var image := Image.create(cells.x, cells.y, false, Image.FORMAT_RGBA8)
	for y in cells.y:
		for x in cells.x:
			var town := owner[y * cells.x + x]
			if town < 0:
				continue
			var color := realm.owner_color(realm.towns[town], player_color)
			var point := (Vector2(x, y) + Vector2(0.5, 0.5)) * TERRITORY_CELL
			var fade := clampf((TERRITORY_REACH - point.distance_to(RealmMap.position(town))) / TERRITORY_FADE, 0.0, 1.0)
			var border := false
			for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var other := Vector2i(x, y) + step
				if other.x < 0 or other.y < 0 or other.x >= cells.x or other.y >= cells.y:
					continue
				var next := owner[other.y * cells.x + other.x]
				if next >= 0 and realm.towns[next].owner != realm.towns[town].owner:
					border = true
					break
			image.set_pixel(x, y, Color(color.darkened(0.25), BORDER_ALPHA * fade) if border
					else Color(color, TERRITORY_ALPHA * fade))
	# Smoothed here: the view draws pixel art with nearest filtering.
	image.resize(cells.x * TERRITORY_SMOOTH, cells.y * TERRITORY_SMOOTH, Image.INTERPOLATE_BILINEAR)
	_territory = ImageTexture.create_from_image(image)
	return _territory


func _draw_parchment() -> void:
	var paper := GameArt.world(&"parchment")
	if paper == null:
		draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND_COLOR)
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * ART_SCALE)
	draw_texture_rect(paper, Rect2(Vector2.ZERO, size / ART_SCALE), true)
	draw_set_transform(Vector2.ZERO)


func _draw_road(from: Vector2, to: Vector2) -> void:
	var length := from.distance_to(to)
	var direction := (to - from) / length
	var step := 12.0
	var at := 26.0
	while at + step < length - 26.0:
		draw_line(from + direction * at, from + direction * (at + step * 0.6), ROAD_COLOR, 4.0)
		at += step


## The army's order as a dashed line that crawls toward its goal and blinks: one road for a march
## or a siege, the whole way for the road home.
func _draw_order(force: Realm.Force) -> void:
	if not force.has_order():
		return
	var path: Array[int] = [force.town]
	if force.order == Realm.HOME:
		path.append_array(realm.route(force.town, Realm.HOME_CAPITAL))
	else:
		path.append(force.target)
	var color := order_color(force.order)
	color.a = 0.55 + 0.45 * absf(sin(_time * PI / ORDER_BLINK))
	var width := 6.0 if force == selected_force else 4.0
	for i in path.size() - 1:
		_dash(RealmMap.position(path[i]), RealmMap.position(path[i + 1]), color, width)
	var goal := RealmMap.position(path.back())
	draw_arc(goal, 30.0, 0.0, TAU, 32, color, 3.0)


## An attack an enemy army announced: a red dashed line with an arrowhead at the town.
func _draw_threat(army: NationArmy) -> void:
	if not army.has_target():
		return
	var color := ENEMY_ATTACK_COLOR
	color.a = 0.6 + 0.4 * absf(sin(_time * PI / ORDER_BLINK))
	var from := RealmMap.position(army.town)
	var to := RealmMap.position(army.target)
	_dash(from, to, color, 4.0)
	var direction := (to - from).normalized()
	var tip := to - direction * 22.0
	var side := direction.orthogonal() * 8.0
	draw_colored_polygon(PackedVector2Array([tip, tip - direction * 14.0 + side, tip - direction * 14.0 - side]), color)


## A dashed line crawling from `from` to `to`, kept clear of both towns.
func _dash(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var length := from.distance_to(to)
	if length <= 0.0:
		return
	var direction := (to - from) / length
	var period := ORDER_DASH + ORDER_GAP
	var at := fmod(_time * ORDER_SPEED, period) - period + 22.0
	while at < length - 22.0:
		var start := maxf(at, 22.0)
		var end := minf(at + ORDER_DASH, length - 22.0)
		if end > start:
			draw_line(from + direction * start, from + direction * end, color, width)
		at += period


## Rings around the towns the selected army can march to (green) or besiege (red).
func _draw_reach() -> void:
	if selected_force == null:
		return
	for id in RealmMap.neighbors(selected_force.town):
		var enemy := realm.towns[id].owner != Realm.PLAYER
		draw_circle(RealmMap.position(id), 40.0, Color(ATTACK_COLOR if enemy else MOVE_COLOR, 0.18))
		draw_arc(RealmMap.position(id), 40.0, 0.0, TAU, 40, ATTACK_COLOR if enemy else MOVE_COLOR, 3.0)


func _draw_town(town: Realm.Town) -> void:
	var center := RealmMap.position(town.id)
	var banner := realm.owner_color(town, player_color)
	if town.id == selected_town:
		draw_arc(center, 34.0, 0.0, TAU, 40, SELECTED_COLOR, 4.0)
	var art_scale := CAPITAL_SCALE if town.is_capital() else ART_SCALE
	var fort := GameArt.world(&"fort")
	if fort != null:
		var draw_size := fort.get_size() * art_scale
		# The wall's foot stays FORT_FOOT art pixels below the town (the art is taller than it was).
		var rect := Rect2(center - Vector2(draw_size.x * 0.5, draw_size.y - WorldMapView.FORT_FOOT * art_scale), draw_size)
		draw_texture_rect(fort, rect, false)
		var team := GameArt.world(&"fort_team")
		if team != null:
			draw_texture_rect(team, rect, false, banner)
	else:
		draw_circle(center, 18.0 if town.is_capital() else 13.0, banner)
	var font := ThemeDB.fallback_font
	var label := ("♛ " if town.is_capital() else "") + town.name
	_text(font, center + Vector2(0, 30), label, LABEL_FONT_SIZE, UiPalette.TEXT)
	if town.owner != Realm.PLAYER:
		_text(font, center + Vector2(0, 44), "⚔ %d" % realm.town_soldiers(town), SMALL_FONT_SIZE, UiPalette.ink(banner))
	else:
		var chance := realm.revolt_chance(town, turn)
		if chance > 0.0:
			_text(font, center + Vector2(0, 44), "Loạn %d%%" % roundi(chance * 100.0), SMALL_FONT_SIZE,
					UiPalette.WARNING if chance >= Realm.REVOLT_CHANCE else UiPalette.MUTED)


func _text(font: Font, at: Vector2, text: String, font_size: int, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var pos := at - Vector2(width * 0.5, 0.0)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, LABEL_OUTLINE)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## One small flag per army in the town, above it to the right; the selected army's flag is ringed.
func _draw_forces(town_id: int) -> void:
	var here := realm.forces_at(town_id)
	var base := RealmMap.position(town_id) + Vector2(18, -30)
	for i in here.size():
		var force: Realm.Force = here[i]
		var foot := base + Vector2(i * 14.0, 0.0)
		var top := foot - Vector2(0, 26)
		if force == selected_force:
			draw_circle(foot - Vector2(-6, 13), 17.0, Color(SELECTED_COLOR, 0.35))
		draw_line(foot, top, Color(0.25, 0.17, 0.1), 2.0)
		var cloth := PackedVector2Array([top, top + Vector2(16, 5), top + Vector2(0, 11)])
		draw_colored_polygon(cloth, player_color)
		# An army with an order: its flag gets the order's color as a thick border.
		var border := order_color(force.order) if force.has_order() else Color(0.2, 0.12, 0.08)
		draw_polyline(PackedVector2Array([top, top + Vector2(16, 5), top + Vector2(0, 11), top]), border,
				3.0 if force.has_order() else 1.0)


## One flag per enemy army in the town, above it to the left, in its nation's color, pointing left.
func _draw_armies(town_id: int) -> void:
	var here := realm.armies_at(town_id)
	var base := RealmMap.position(town_id) + Vector2(-18, -30)
	for i in here.size():
		var army: NationArmy = here[i]
		var foot := base - Vector2(i * 14.0, 0.0)
		var top := foot - Vector2(0, 26)
		draw_line(foot, top, Color(0.25, 0.17, 0.1), 2.0)
		var cloth := PackedVector2Array([top, top + Vector2(-16, 5), top + Vector2(0, 11)])
		draw_colored_polygon(cloth, realm.nations[army.nation].color)
		var border := ENEMY_ATTACK_COLOR if army.has_target() else Color(0.2, 0.12, 0.08)
		draw_polyline(PackedVector2Array([top, top + Vector2(-16, 5), top + Vector2(0, 11), top]), border,
				3.0 if army.has_target() else 1.0)
