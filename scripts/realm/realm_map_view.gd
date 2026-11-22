class_name RealmMapView
extends Control
## Draws the realm map (Phân Chia Thiên Hạ, GDD §33, M18f-a) on paper, fitted to the view: the six
## regions tinted by the nation holding each town, the roads, a fort per town flying its owner's
## banner (capitals bigger, with a crown), enemy garrisons, and the kingdom's armies as flags.
## A click on a town emits `town_clicked`. Read-only: the screen decides what a click does.

signal town_clicked(town: int)

const ART_SCALE := 2.0
const CAPITAL_SCALE := 2.6
const ROAD_COLOR := Color(0.47, 0.32, 0.18, 0.8)
const REGION_ALPHA := 0.11
const REGION_RADIUS := 80.0
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

var realm: Realm
var player_color := KingdomState.PLAYER_COLOR
var kingdom_name := ""
var selected_town := -1
## The selected army's town, its reachable neighbors drawn as rings.
var selected_force: Realm.Force


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


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
	for town in realm.towns:
		draw_circle(RealmMap.position(town.id), REGION_RADIUS, Color(realm.owner_color(town, player_color), REGION_ALPHA))
	for road in RealmMap.roads():
		_draw_road(RealmMap.position(road.x), RealmMap.position(road.y))
	_draw_reach()
	for town in realm.towns:
		_draw_town(town)
	for town in realm.towns:
		_draw_forces(town.id)
	draw_set_transform(Vector2.ZERO)


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


## Rings around the towns the selected army can march to (green) or besiege (red).
func _draw_reach() -> void:
	if selected_force == null or selected_force.moved:
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
		var rect := Rect2(center - Vector2(draw_size.x * 0.5, draw_size.y * 0.7), draw_size)
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
		_text(font, center + Vector2(0, 44), "⚔ %d" % town.garrison, SMALL_FONT_SIZE, UiPalette.ink(banner))
	elif town.governor != null:
		_text(font, center + Vector2(0, 44), "Thái thú %s" % town.governor.name, SMALL_FONT_SIZE, UiPalette.MUTED)
	elif town.is_captured():
		_text(font, center + Vector2(0, 44), "Chưa có thái thú", SMALL_FONT_SIZE, UiPalette.WARNING)


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
		draw_colored_polygon(cloth, player_color.darkened(0.25) if force.moved else player_color)
		draw_polyline(PackedVector2Array([top, top + Vector2(16, 5), top + Vector2(0, 11)]), Color(0.2, 0.12, 0.08), 1.0)
