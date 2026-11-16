extends Control
## Carte de la ligne : une gare par niveau, le long d'une voie qui traverse les régions.
## La gare 1 est en bas ; on fait défiler la carte au doigt (ou à la molette).

signal level_picked(index: int)
signal closed

const SPACING := 150.0
const MARGIN_TOP := 260.0
const MARGIN_BOTTOM := 190.0
const RADIUS := 36.0
const INK := Color("2b2d42")
const GOLD := Color("f2b705")
const RAIL := Color("8a7968")
const LOCKED := Color("c4c4c4")

## Noms des gares, une par niveau.
var stations: Array = []
## Régions : [{name, first, map, decor}], triées par `first`.
var regions: Array = []
## Meilleure note par niveau (clé = index en texte).
var stars: Dictionary = {}
var current: int = 0
## Dernière gare atteinte ; les suivantes sont grisées (mais restent accessibles pour les essais).
var reached: int = 0
## Hauteur réservée en haut de l'écran (encoche du téléphone).
var top_inset: float = 0.0

var _scroll: float = 0.0
var _pressed: bool = false
var _dragged: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _close: Button


func _ready() -> void:
	_close = Button.new()
	_close.text = "Retour"
	_close.add_theme_font_size_override("font_size", 28)
	_close.pressed.connect(func() -> void: closed.emit())
	add_child(_close)
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	_close.size = Vector2(170.0, 60.0)
	_close.position = Vector2(size.x - 200.0, 62.0 + top_inset)
	_scroll = clampf(_scroll, 0.0, _max_scroll())
	queue_redraw()


## Affiche la carte, centrée sur la gare en cours.
func open(current_level: int, reached_level: int, best_stars: Dictionary) -> void:
	current = current_level
	reached = reached_level
	stars = best_stars
	visible = true
	_pressed = false
	_layout()
	_scroll = clampf(MARGIN_BOTTOM + current * SPACING - size.y / 2.0, 0.0, _max_scroll())
	queue_redraw()


func _max_scroll() -> float:
	var total: float = MARGIN_BOTTOM + maxi(stations.size() - 1, 0) * SPACING + MARGIN_TOP + top_inset
	return maxf(0.0, total - size.y)


## Position à l'écran de la gare `i` (i peut être fractionnaire, pour tracer la voie).
func _pos(i: float) -> Vector2:
	return Vector2(size.x / 2.0 + sin(i * 0.85) * size.x * 0.24,
		size.y - MARGIN_BOTTOM - i * SPACING + _scroll)


func _region_index(i: int) -> int:
	var found: int = 0
	for r: int in regions.size():
		if int(regions[r]["first"]) <= i:
			found = r
	return found


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_scroll_by(80.0)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_scroll_by(-80.0)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_pressed = true
				_dragged = false
				_press_pos = button.position
			elif _pressed:
				_pressed = false
				if not _dragged:
					_tap(button.position)
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and _pressed:
		if motion.position.distance_to(_press_pos) > 12.0:
			_dragged = true
		_scroll_by(motion.relative.y)


func _scroll_by(delta: float) -> void:
	_scroll = clampf(_scroll + delta, 0.0, _max_scroll())
	queue_redraw()


func _tap(at: Vector2) -> void:
	for i: int in stations.size():
		if _pos(i).distance_to(at) <= RADIUS + 18.0:
			level_picked.emit(i)
			return


func _total_stars() -> int:
	var total: int = 0
	for v: Variant in stars.values():
		total += int(v)
	return total


func _star(center: Vector2, radius: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for k: int in 10:
		points.append(center + Vector2.from_angle(-PI / 2.0 + k * PI / 5.0) * (radius if k % 2 == 0 else radius * 0.45))
	draw_colored_polygon(points, color)


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	var n: int = stations.size()
	# Fonds des régions : une bande par région, de la première à la dernière de ses gares.
	for r: int in regions.size():
		var first: int = regions[r]["first"]
		var last: int = (int(regions[r + 1]["first"]) if r + 1 < regions.size() else n) - 1
		var bottom: float = _pos(first).y + (MARGIN_BOTTOM + 10.0 if r == 0 else SPACING / 2.0)
		var top: float = _pos(last).y - (MARGIN_TOP + top_inset + 10.0 if r + 1 == regions.size() else SPACING / 2.0)
		draw_rect(Rect2(0.0, top, size.x, bottom - top), Color(str(regions[r]["map"])))
		draw_string(font, Vector2(0.0, bottom - 24.0), str(regions[r]["name"]),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 34, Color(INK, 0.45))
	# Décor : deux éléments par gare, placés du côté opposé à la voie.
	for i: int in n:
		var p: Vector2 = _pos(i)
		if p.y < -200.0 or p.y > size.y + 200.0:
			continue
		var side: float = -1.0 if p.x > size.x / 2.0 else 1.0
		var kind: String = regions[_region_index(i)]["decor"]
		for d: int in 2:
			var jitter: float = float((i * 37 + d * 71) % 60)
			var at: Vector2 = Vector2(size.x / 2.0 + side * (150.0 + d * 90.0 + jitter * 0.5),
				p.y - 40.0 + d * 70.0 + jitter * 0.4)
			_decor(kind, at)
	# La voie.
	var path: PackedVector2Array = PackedVector2Array()
	for k: int in (n - 1) * 8 + 1:
		path.append(_pos(k / 8.0))
	if path.size() >= 2:
		draw_polyline(path, RAIL, 18.0)
		draw_polyline(path, Color("e9dfd0"), 7.0)
	# Les gares.
	for i: int in n:
		var p: Vector2 = _pos(i)
		if p.y < -100.0 or p.y > size.y + 100.0:
			continue
		var best: int = int(stars.get(str(i), 0))
		var fill: Color = GOLD if best > 0 else (Color.WHITE if i <= reached else LOCKED)
		draw_circle(p, RADIUS + 5.0, INK)
		draw_circle(p, RADIUS, fill)
		if i == current:
			draw_arc(p, RADIUS + 13.0, 0.0, TAU, 48, Color("e4572e"), 6.0)
		draw_string(font, p + Vector2(-RADIUS, 12.0), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER,
			RADIUS * 2.0, 32, INK)
		var on_right: bool = p.x < size.x / 2.0
		var label_x: float = p.x + RADIUS + 22.0 if on_right else 0.0
		var label_w: float = size.x - label_x - 16.0 if on_right else p.x - RADIUS - 22.0
		draw_string(font, Vector2(label_x, p.y + 2.0), str(stations[i]),
			HORIZONTAL_ALIGNMENT_LEFT if on_right else HORIZONTAL_ALIGNMENT_RIGHT, label_w, 26,
			INK if i <= reached else Color(INK, 0.45))
		if best > 0:
			for s: int in 3:
				var sx: float = (label_x + 12.0 + s * 26.0) if on_right else (p.x - RADIUS - 34.0 - (2 - s) * 26.0)
				_star(Vector2(sx, p.y + 24.0), 11.0, GOLD if s < best else Color(INK, 0.2))
	# En-tête.
	draw_rect(Rect2(0.0, 0.0, size.x, 140.0 + top_inset), Color(1, 1, 1, 0.88))
	draw_string(font, Vector2(36.0, 96.0 + top_inset), "La ligne", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 40, INK)
	draw_string(font, Vector2(36.0, 128.0 + top_inset), "Étoiles : %d / %d" % [_total_stars(), n * 3],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, INK)


func _decor(kind: String, at: Vector2) -> void:
	match kind:
		"tree":
			draw_rect(Rect2(at + Vector2(-4.0, 6.0), Vector2(8.0, 20.0)), Color("8a6a4a"))
			draw_circle(at, 20.0, Color("7fb069"))
			draw_circle(at + Vector2(-10.0, 8.0), 13.0, Color("8fbf78"))
		"peak":
			draw_colored_polygon(PackedVector2Array([at + Vector2(-34.0, 26.0), at + Vector2(34.0, 26.0),
				at + Vector2(0.0, -30.0)]), Color("9aa5b8"))
			draw_colored_polygon(PackedVector2Array([at + Vector2(-11.0, -10.0), at + Vector2(11.0, -10.0),
				at + Vector2(0.0, -30.0)]), Color.WHITE)
		"wave":
			for k: int in 3:
				draw_arc(at + Vector2((k - 1) * 26.0, 0.0), 13.0, PI, TAU, 12, Color("5fa8c4"), 4.0)
