extends Control
## Carte de la ligne : une gare par niveau, le long d'une voie qui traverse les régions.
## La gare 1 est en bas ; on fait défiler la carte au doigt (ou à la molette).
## Les images viennent de assets/ui (générées par tools/gen_sprites.py).

signal level_picked(index: int)
signal closed

const SPACING := 150.0
const MARGIN_TOP := 260.0
const MARGIN_BOTTOM := 190.0
const RADIUS := 36.0
const INK := Color("1b1642")
const LIGHT := Color("efeaff")
const HEADER := Color("231d55")

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
## Images gardées en mémoire pour le dessin.
var _tex: Dictionary = {}
## Horloge de l'anneau qui bat autour de la gare en cours.
var _time: float = 0.0


func _ready() -> void:
	for name: String in ["station_done", "station_open", "station_locked", "star", "star_empty",
			"tree", "peak", "wave", "tie"]:
		_tex[name] = load("res://assets/ui/%s.svg" % name)
	_close = Button.new()
	_close.text = "Retour"
	_close.add_theme_font_size_override("font_size", 28)
	_close.pressed.connect(func() -> void: closed.emit())
	add_child(_close)
	resized.connect(_layout)
	_layout()


func _process(delta: float) -> void:
	if visible:
		_time += delta
		queue_redraw()


func _layout() -> void:
	_close.size = Vector2(170.0, 64.0)
	_close.position = Vector2(size.x - 200.0, 58.0 + top_inset)
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


## Texte clair cerné de sombre, lisible sur tous les fonds.
func _text(at: Vector2, text: String, align: HorizontalAlignment, width: float, font_size: int,
		color: Color = LIGHT) -> void:
	var font: Font = ThemeDB.fallback_font
	draw_string_outline(font, at, text, align, width, font_size, 8, INK)
	draw_string(font, at, text, align, width, font_size, color)


## Image dessinée à la moitié de sa taille (elles sont au double), centrée sur `center`.
func _sprite(name: String, center: Vector2, zoom: float = 1.0) -> void:
	var tex: Texture2D = _tex[name]
	var half: Vector2 = tex.get_size() * 0.25 * zoom
	draw_texture_rect(tex, Rect2(center - half, half * 2.0), false)


func _draw() -> void:
	var n: int = stations.size()
	# Fonds des régions : une bande par région, de la première à la dernière de ses gares.
	for r: int in regions.size():
		var first: int = regions[r]["first"]
		var last: int = (int(regions[r + 1]["first"]) if r + 1 < regions.size() else n) - 1
		var bottom: float = _pos(first).y + (MARGIN_BOTTOM + 10.0 if r == 0 else SPACING / 2.0)
		var top: float = _pos(last).y - (MARGIN_TOP + top_inset + 10.0 if r + 1 == regions.size() else SPACING / 2.0)
		var base: Color = Color(str(regions[r]["map"]))
		draw_rect(Rect2(0.0, top, size.x, bottom - top), base)
		# Liseré clair en haut de la bande : chaque région se lit comme une plaque.
		draw_rect(Rect2(0.0, top, size.x, 6.0), base.lightened(0.18))
		_text(Vector2(0.0, bottom - 24.0), str(regions[r]["name"]), HORIZONTAL_ALIGNMENT_CENTER,
			size.x, 34, Color(LIGHT, 0.75))
	# Décor : deux éléments par gare, placés du côté opposé à la voie.
	for i: int in n:
		var p: Vector2 = _pos(i)
		if p.y < -200.0 or p.y > size.y + 200.0:
			continue
		var side: float = -1.0 if p.x > size.x / 2.0 else 1.0
		var kind: String = regions[_region_index(i)]["decor"]
		for d: int in 2:
			var jitter: float = float((i * 37 + d * 71) % 60)
			_sprite(kind, Vector2(size.x / 2.0 + side * (150.0 + d * 90.0 + jitter * 0.5),
				p.y - 40.0 + d * 70.0 + jitter * 0.4), 1.0 - d * 0.2)
	# La voie : rainure, traverses, puis deux rails avec ombre et reflet.
	var path: PackedVector2Array = PackedVector2Array()
	for k: int in (n - 1) * 12 + 1:
		path.append(_pos(k / 12.0))
	if path.size() >= 2:
		draw_polyline(path, Color(0.03, 0.01, 0.12, 0.45), 62.0, true)
		var tie: Texture2D = _tex["tie"]
		var travelled: float = 0.0
		var next_tie: float = 10.0
		for k: int in path.size() - 1:
			var step: Vector2 = path[k + 1] - path[k]
			while next_tie <= travelled + step.length():
				var here: Vector2 = path[k] + step.normalized() * (next_tie - travelled)
				if here.y > -40.0 and here.y < size.y + 40.0:
					draw_set_transform(here, step.orthogonal().angle())
					draw_texture_rect(tie, Rect2(-25.0, -4.5, 50.0, 12.0), false)
				next_tie += 22.0
			travelled += step.length()
		draw_set_transform(Vector2.ZERO, 0.0)
		for rail_side: float in [1.0, -1.0]:
			var rail: PackedVector2Array = PackedVector2Array()
			var shadow: PackedVector2Array = PackedVector2Array()
			var shine: PackedVector2Array = PackedVector2Array()
			for k: int in path.size():
				var dir: Vector2 = (path[mini(k + 1, path.size() - 1)] - path[maxi(k - 1, 0)]).normalized()
				var q: Vector2 = path[k] + dir.orthogonal() * 18.0 * rail_side
				rail.append(q)
				shadow.append(q + Vector2(0.0, 5.5))
				shine.append(q + Vector2(-0.8, -1.4))
			draw_polyline(shadow, Color(0.03, 0.01, 0.12, 0.5), 6.5, true)
			draw_polyline(rail, Color("b9b1ec"), 6.5, true)
			draw_polyline(shine, Color.WHITE, 2.2, true)
	# Les gares.
	var font: Font = ThemeDB.fallback_font
	for i: int in n:
		var p: Vector2 = _pos(i)
		if p.y < -100.0 or p.y > size.y + 100.0:
			continue
		var best: int = int(stars.get(str(i), 0))
		if i == current:
			# Anneau qui bat autour de la gare en cours.
			var beat: float = 0.5 + 0.5 * sin(_time * 4.0)
			draw_arc(p, RADIUS + 14.0 + beat * 6.0, 0.0, TAU, 64, Color(1, 1, 1, 0.9 - beat * 0.5), 7.0, true)
		_sprite("station_done" if best > 0 else ("station_open" if i <= reached else "station_locked"),
			p + Vector2(0.0, 6.0))
		draw_string(font, p + Vector2(-RADIUS, 13.0), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER,
			RADIUS * 2.0, 34, INK if i <= reached or best > 0 else Color(LIGHT, 0.85))
		var on_right: bool = p.x < size.x / 2.0
		var label_x: float = p.x + RADIUS + 24.0 if on_right else 0.0
		var label_w: float = size.x - label_x - 16.0 if on_right else p.x - RADIUS - 24.0
		_text(Vector2(label_x, p.y + 2.0), str(stations[i]),
			HORIZONTAL_ALIGNMENT_LEFT if on_right else HORIZONTAL_ALIGNMENT_RIGHT, label_w, 27,
			LIGHT if i <= reached else Color(LIGHT, 0.6))
		if best > 0:
			for s: int in 3:
				var sx: float = (label_x + 14.0 + s * 30.0) if on_right else (p.x - RADIUS - 38.0 - (2 - s) * 30.0)
				_sprite("star" if s < best else "star_empty", Vector2(sx, p.y + 26.0), 0.6)
	# En-tête.
	draw_rect(Rect2(0.0, 0.0, size.x, 146.0 + top_inset), Color(HEADER, 0.94))
	draw_rect(Rect2(0.0, 146.0 + top_inset, size.x, 6.0), Color(0.03, 0.01, 0.12, 0.45))
	_text(Vector2(36.0, 98.0 + top_inset), "La ligne", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 42)
	_sprite("star", Vector2(52.0, 122.0 + top_inset), 0.6)
	_text(Vector2(76.0, 132.0 + top_inset), "%d / %d" % [_total_stars(), n * 3],
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26)
