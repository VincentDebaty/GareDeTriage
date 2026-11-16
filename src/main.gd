extends Node2D
## Écran de jeu du prototype « Gare de triage » : rendu provisoire, saisie tactile et retours.
## Toute la règle du jeu vit dans triage_game.gd ; ce script ne fait qu'afficher et animer.
## La règle est appliquée dès la touche ; les animations sont programmées et ne bloquent
## jamais la saisie.

const Game := preload("res://src/triage_game.gd")
const Solver := preload("res://src/triage_solver.gd")
const Piece := preload("res://src/piece.gd")
const Sfx := preload("res://src/sfx.gd")
const MapView := preload("res://src/map_view.gd")

const PALETTE: Array[Color] = [
	Color("e4572e"), Color("3b8eea"), Color("f2c14e"),
	Color("4caf6d"), Color("9b5de5"), Color("ec6fa9"),
]
const STEP := 74.0
const TRACK_STEP := 68.0
const TRACK_ROWS := 8
const BG := Color("f3ead7")
const RAIL := Color("8a7968")
const INK := Color("2b2d42")
const GOLD := Color("f2b705")
## Durées d'essai des animations, en secondes.
const MOVE_TIME := 0.16
const ROLL_TIME := 0.26
const CASCADE_GAP := 0.14
const DEPART_TIME := 0.6
const LOCO_IN_TIME := 0.35
## Délai entre le début d'un départ et l'arrivée à quai de la locomotive suivante.
const NEXT_TRAIN_DELAY := 0.12 + DEPART_TIME * 0.7 + LOCO_IN_TIME
const SAVE_PATH := "user://progress.json"
## À incrémenter quand le jeu de niveaux change : la progression repart alors de zéro.
const SAVE_VERSION := 2

var _levels: Array = []
var _level_index: int = 0
var _game: Game
var _wagons: Dictionary = {}
var _locos: Array[Node2D] = []
## États précédents, pour le bouton « Annuler ».
var _history: Array[Game] = []
## Wagons mystère déjà dévoilés (identifiant -> true).
var _revealed: Dictionary = {}
## Ce que l'écran montre pour chaque quai ({color, size}) et pour les trains à venir
## ([couleur, longueur]). Ces vues suivent les animations, pas la règle : la règle est
## déjà à jour au moment de la touche, l'affichage change quand le train arrive vraiment.
var _slot_view: Array[Dictionary] = []
var _pending_view: Array = []
## Numéros d'ordre des mises à jour de ces vues : en jouant très vite, deux animations
## peuvent se terminer dans le désordre ; on n'applique jamais un état plus ancien que
## celui déjà affiché (par quai, et pour la liste des trains à venir).
var _view_seq: int = 0
var _view_applied: int = 0
var _slot_applied: Array[int] = []
var _gen: int = 0
var _stars_total: int = 0
var _stars_shown: int = 0
## Progression enregistrée : niveau courant et meilleure note par niveau.
var _progress: Dictionary = {"version": SAVE_VERSION, "level": 0, "stars": {}}
var _save_enabled: bool = true

var _pieces: Node2D
var _sfx: Sfx
var _title: Button
var _map: MapView
## Ligne : régions et noms de gares (data/line.json).
var _line: Dictionary = {}
var _hint: Label
var _stars_label: Label
var _pending_label: Label
var _restart: Button
var _undo_button: Button
var _overlay: ColorRect
var _overlay_label: Label
var _overlay_button: Button
var _overlay_alt: Button
var _star_row: Control


func _ready() -> void:
	RenderingServer.set_default_clear_color(BG)
	_levels = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json"))
	_line = JSON.parse_string(FileAccess.get_file_as_string("res://data/line.json"))
	_pieces = Node2D.new()
	add_child(_pieces)
	_sfx = Sfx.new()
	add_child(_sfx)
	_build_ui()
	get_viewport().size_changed.connect(_on_resize)
	# Les lancements de vérification (options après « -- ») ne touchent pas à la sauvegarde.
	_save_enabled = OS.get_cmdline_user_args().is_empty()
	_load_progress()
	_start_level(clampi(int(_progress["level"]), 0, _levels.size() - 1))
	# Le jeu s'ouvre sur la carte de la ligne (sauf lors des vérifications automatiques).
	if _save_enabled:
		_open_map()
	_debug_hook()


# --- Progression -------------------------------------------------------------

func _load_progress() -> void:
	if not _save_enabled or not FileAccess.file_exists(SAVE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Dictionary and int(data.get("version", 1)) == SAVE_VERSION \
			and data.has("level") and data.get("stars") is Dictionary:
		_progress = data


func _save_progress() -> void:
	if not _save_enabled:
		return
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_progress))
		f.close()


## Dernière gare atteinte sur la ligne.
func _reached() -> int:
	return int(_progress.get("reached", _progress["level"]))


func _region(index: int) -> Dictionary:
	var found: Dictionary = _line["regions"][0]
	for r: Dictionary in _line["regions"]:
		if int(r["first"]) <= index:
			found = r
	return found


func _total_stars() -> int:
	var total: int = 0
	for v: Variant in _progress["stars"].values():
		total += int(v)
	return total


# --- Interface ---------------------------------------------------------------

func _label(font_size: int) -> Label:
	var l: Label = Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", INK)
	return l


func _button(text: String, font_size: int, action: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(action)
	return b


func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	# Le titre est un bouton : il ouvre la carte de la ligne.
	_title = _button("", 30, _open_map)
	_title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_stars_label = _label(26)
	_hint = _label(23)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pending_label = _label(26)
	_pending_label.text = "Trains à venir :"
	_restart = _button("Recommencer", 26, func() -> void: _start_level(_level_index))
	_undo_button = _button("Annuler", 26, _undo)
	for c: Control in [_title, _stars_label, _hint, _pending_label, _restart, _undo_button]:
		layer.add_child(c)
	_overlay = ColorRect.new()
	_overlay.color = Color(0.1, 0.1, 0.15, 0.65)
	_overlay.visible = false
	layer.add_child(_overlay)
	_overlay_label = Label.new()
	_overlay_label.add_theme_font_size_override("font_size", 52)
	_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay.add_child(_overlay_label)
	_star_row = Control.new()
	_star_row.draw.connect(_draw_stars)
	_overlay.add_child(_star_row)
	_overlay_button = _button("", 38, _on_overlay_button)
	_overlay.add_child(_overlay_button)
	_overlay_alt = _button("", 30, _on_overlay_alt)
	_overlay.add_child(_overlay_alt)
	_map = MapView.new()
	_map.stations = _line["stations"]
	_map.regions = _line["regions"]
	_map.visible = false
	_map.level_picked.connect(_pick_level)
	_map.closed.connect(func() -> void: _map.visible = false)
	layer.add_child(_map)
	_layout_ui()


## Ouvre la carte de la ligne. Toutes les gares restent accessibles (utile pour les essais).
func _open_map() -> void:
	_map.open(_level_index, _reached(), _progress["stars"])


func _pick_level(index: int) -> void:
	_map.visible = false
	_progress["level"] = index
	_save_progress()
	_start_level(index)


func _layout_ui() -> void:
	var sz: Vector2 = _size()
	# Décale l'en-tête sous l'encoche ou la barre d'état du téléphone.
	var dy: float = maxf(0.0, _top_inset() - 50.0)
	_title.position = Vector2(30.0, 62.0 + dy)
	_title.size = Vector2(sz.x - 310.0, 56.0)
	_map.position = Vector2.ZERO
	_map.top_inset = dy
	_map.size = sz
	_restart.size = Vector2(220.0, 56.0)
	_restart.position = Vector2(sz.x - 260.0, 62.0 + dy)
	_undo_button.size = Vector2(220.0, 56.0)
	_undo_button.position = Vector2(sz.x - 260.0, 128.0 + dy)
	_stars_label.position = Vector2(40.0, 130.0 + dy)
	_hint.position = Vector2(40.0, 196.0 + dy)
	_hint.size = Vector2(sz.x - 80.0, 70.0)
	_pending_label.position = Vector2(40.0, sz.y * 0.945 - 18.0)
	_overlay.position = Vector2.ZERO
	_overlay.size = sz
	_overlay_label.position = Vector2(0.0, sz.y * 0.30)
	_overlay_label.size = Vector2(sz.x, 90.0)
	_star_row.position = Vector2(sz.x / 2.0, sz.y * 0.43)
	_overlay_button.size = Vector2(460.0, 100.0)
	_overlay_button.position = Vector2((sz.x - 460.0) / 2.0, sz.y * 0.52)
	_overlay_alt.size = Vector2(460.0, 80.0)
	_overlay_alt.position = Vector2((sz.x - 460.0) / 2.0, sz.y * 0.52 + 120.0)


## Hauteur de la zone non sûre en haut de l'écran, en unités du jeu (0 hors mobile).
func _top_inset() -> float:
	if not OS.has_feature("mobile"):
		return 0.0
	var screen_h: float = DisplayServer.screen_get_size().y
	if screen_h <= 0.0:
		return 0.0
	return DisplayServer.get_display_safe_area().position.y * _size().y / screen_h


func _on_resize() -> void:
	_layout_ui()
	if _game != null:
		_relayout(0.0)
		for s: int in _locos.size():
			if _locos[s] != null:
				_locos[s].position = _loco_pos(s)


## Affiche le panneau de fin. `stars` > 0 : les étoiles tombent une à une.
## `alt` : texte du bouton secondaire.
func _show_overlay(text: String, button: String, stars: int, alt: String) -> void:
	_overlay_label.text = text
	_overlay_button.text = button
	_overlay_alt.text = alt
	_stars_total = stars
	_stars_shown = 0
	_star_row.queue_redraw()
	_overlay.visible = true
	_overlay.modulate.a = 0.0
	_overlay.create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.25)
	if stars <= 0:
		return
	var tw: Tween = _star_row.create_tween()
	for i: int in stars:
		tw.tween_interval(0.32)
		tw.tween_callback(func() -> void:
			_stars_shown = i + 1
			_star_row.queue_redraw()
			_sfx.play("star", 1.0 + 0.18 * i)
			Input.vibrate_handheld(20))


func _draw_stars() -> void:
	if _stars_total <= 0:
		return
	for i: int in 3:
		var center: Vector2 = Vector2((i - 1) * 110.0, 0.0)
		var points: PackedVector2Array = PackedVector2Array()
		for k: int in 10:
			var radius: float = 48.0 if k % 2 == 0 else 21.0
			points.append(center + Vector2.from_angle(-PI / 2.0 + k * PI / 5.0) * radius)
		_star_row.draw_colored_polygon(points, GOLD if i < _stars_shown else Color(1, 1, 1, 0.25))


func _on_overlay_button() -> void:
	if _game.status() == Game.WON:
		_start_level((_level_index + 1) % _levels.size())
	else:
		_undo()


func _on_overlay_alt() -> void:
	if _game.status() == Game.WON:
		_open_map()
	else:
		_start_level(_level_index)


# --- Géométrie ---------------------------------------------------------------

func _size() -> Vector2:
	return get_viewport_rect().size


func _track_x(t: int) -> float:
	var n: int = _game.tracks.size()
	return _size().x / 2.0 + (t - (n - 1) / 2.0) * _track_gap()


func _track_gap() -> float:
	return minf(150.0, (_size().x - 40.0) / _game.tracks.size())


func _head_y() -> float:
	return _size().y * 0.60


## Position du k-ième wagon d'une voie d'arrivée (k = 0 : wagon de tête, en bas).
func _track_pos(t: int, k: int) -> Vector2:
	return Vector2(_track_x(t), _head_y() - k * TRACK_STEP)


func _track_rect(t: int) -> Rect2:
	var top: float = _head_y() - TRACK_ROWS * TRACK_STEP
	var width: float = _track_gap() - 6.0
	return Rect2(_track_x(t) - width / 2.0, top, width, _head_y() + 44.0 - top)


func _buffer_pos(b: int) -> Vector2:
	return Vector2(_size().x / 2.0 + (b - (_game.buffer_size - 1) / 2.0) * STEP, _size().y * 0.69)


func _loco_pos(slot: int) -> Vector2:
	return Vector2(_size().x - 120.0, _size().y * (0.785 + 0.085 * slot))


func _slot_pos(slot: int, k: int) -> Vector2:
	return _loco_pos(slot) - Vector2(STEP * (k + 1) + 4.0, 0.0)


# --- Partie ------------------------------------------------------------------

func _start_level(index: int) -> void:
	_gen += 1
	_level_index = index
	_overlay.visible = false
	_history.clear()
	_revealed.clear()
	_game = Game.new()
	_game.load_level(_levels[index])
	_rebuild()
	_title.text = "%d · %s" % [index + 1, _line["stations"][index]]
	RenderingServer.set_default_clear_color(Color(str(_region(index)["game"])))
	_stars_label.text = "Étoiles : %d / %d" % [_total_stars(), _levels.size() * 3]
	_hint.text = str(_levels[index].get("hint", ""))


## Recrée tous les wagons et locomotives d'après l'état de la règle, sans animation.
func _rebuild() -> void:
	for child: Node in _pieces.get_children():
		child.queue_free()
	_wagons.clear()
	_locos.clear()
	var ids: Array[int] = []
	for track: Array in _game.tracks:
		ids.append_array(track)
	ids.append_array(_game.buffer)
	for slot: Dictionary in _game.slots:
		ids.append_array(slot["ids"])
	for id: int in ids:
		var w: Node2D = _new_piece(_game.colors[id], false)
		w.masked = _game.hidden[id] == 1 and not _revealed.has(id)
		_wagons[id] = w
	_slot_view.clear()
	_slot_applied.clear()
	for s: int in _game.slots.size():
		_locos.append(null)
		_spawn_loco(s)
		_slot_applied.append(_view_seq)
		_slot_view.append({"color": _game.slots[s]["color"], "size": _game.slots[s]["size"]})
	_pending_view = _pending_snapshot()
	_view_applied = _view_seq
	_relayout(0.0)


## Programme un changement d'affichage d'un quai (et, si `pending` est fourni, de la liste
## des trains à venir) dans `delay` secondes. Indépendant des locomotives : en jeu rapide,
## une locomotive peut repartir avant la fin de son animation d'arrivée.
func _schedule_view(slot: int, delay: float, view: Dictionary, pending: Variant) -> void:
	_view_seq += 1
	var seq: int = _view_seq
	var gen: int = _gen
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if gen != _gen:
			return
		if seq > _slot_applied[slot]:
			_slot_applied[slot] = seq
			_slot_view[slot] = view
		if pending != null and seq > _view_applied:
			_view_applied = seq
			_pending_view = pending
		queue_redraw())


func _pending_snapshot() -> Array:
	var list: Array = []
	for p: int in _game.pending.size():
		list.append([_game.pending[p], _game.pending_sizes[p]])
	return list


func _new_piece(kind: int, is_loco: bool) -> Node2D:
	var p: Node2D = Piece.new()
	p.color = PALETTE[kind]
	p.is_loco = is_loco
	_pieces.add_child(p)
	return p


## Crée la locomotive du quai. Avec `delay` >= 0, elle entre par la gauche après ce délai ;
## les cadres du quai et la liste des trains à venir ne changent qu'à son arrivée.
func _spawn_loco(slot: int, delay: float = -1.0) -> void:
	var color: int = _game.slots[slot]["color"]
	if delay >= 0.0:
		_schedule_view(slot, delay + LOCO_IN_TIME,
			{"color": color, "size": _game.slots[slot]["size"]}, _pending_snapshot())
	if color == -1:
		_locos[slot] = null
		return
	var loco: Node2D = _new_piece(color, true)
	_locos[slot] = loco
	if delay < 0.0:
		loco.position = _loco_pos(slot)
		return
	loco.position = Vector2(-200.0, _loco_pos(slot).y)
	var tw: Tween = loco.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(loco, "position", _loco_pos(slot), LOCO_IN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _stop_move(node: Node2D) -> void:
	if node.has_meta("move"):
		var old: Tween = node.get_meta("move")
		if old != null and old.is_valid():
			old.kill()
		node.remove_meta("move")


## Glissement simple en ligne droite (décalage d'une voie, resserrement de l'attente).
func _move(node: Node2D, target: Vector2, duration: float) -> void:
	_stop_move(node)
	if duration <= 0.0:
		node.position = target
	elif node.position != target:
		var tw: Tween = node.create_tween()
		tw.tween_property(node, "position", target, duration).set_trans(Tween.TRANS_SINE)
		node.set_meta("move", tw)


## Fait rouler un wagon jusqu'à `target` : il descend sa voie, puis longe le quai.
## `on_start` et `on_arrive` sont appelés au départ et à l'arrivée (Callable() pour rien).
func _roll(node: Node2D, target: Vector2, delay: float, on_start: Callable, on_arrive: Callable) -> void:
	_stop_move(node)
	var dy: float = absf(target.y - node.position.y)
	var dx: float = absf(target.x - node.position.x)
	var total: float = maxf(dx + dy, 1.0)
	var tw: Tween = node.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		node.z_index = 5
		if on_start.is_valid():
			on_start.call())
	tw.tween_property(node, "position:y", target.y, maxf(0.01, ROLL_TIME * dy / total)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(node, "position:x", target.x, maxf(0.01, ROLL_TIME * dx / total)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		node.z_index = 0
		if on_arrive.is_valid():
			on_arrive.call())


func _pop(node: Node2D) -> void:
	node.scale = Vector2(1.3, 1.3)
	node.create_tween().tween_property(node, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Attelage : claquement et petit écrasement du wagon contre le train.
func _couple(node: Node2D) -> void:
	_sfx.play("clack")
	node.scale = Vector2(0.82, 1.12)
	node.create_tween().tween_property(node, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _shake(node: Node2D) -> void:
	_stop_move(node)
	var x: float = node.position.x
	var tw: Tween = node.create_tween()
	for dx: float in [10.0, -10.0, 6.0, 0.0]:
		tw.tween_property(node, "position:x", x + dx, 0.04)
	node.set_meta("move", tw)


## Place les wagons des voies et de l'attente là où la règle dit qu'ils se trouvent.
## `skip_id` : wagon dont le déplacement est déjà animé par ailleurs.
func _relayout(duration: float, skip_id: int = -1) -> void:
	for t: int in _game.tracks.size():
		for k: int in _game.tracks[t].size():
			var id: int = _game.tracks[t][k]
			var w: Node2D = _wagons[id]
			_move(w, _track_pos(t, k), duration)
			if k == 0 and w.masked:
				_reveal(id, duration > 0.0)
	for b: int in _game.buffer.size():
		if _game.buffer[b] != skip_id:
			_move(_wagons[_game.buffer[b]], _buffer_pos(b), duration)
	# Les wagons à quai sont placés par leurs propres animations ; on ne les
	# repositionne ici que pour un placement immédiat (changement de taille d'écran).
	if duration <= 0.0:
		for s: int in _game.slots.size():
			var ids: Array = _game.slots[s]["ids"]
			for k: int in ids.size():
				_move(_wagons[ids[k]], _slot_pos(s, k), 0.0)
	queue_redraw()


## Dévoile un wagon mystère arrivé en tête de voie.
func _reveal(id: int, animated: bool) -> void:
	var w: Node2D = _wagons[id]
	_revealed[id] = true
	if not animated:
		w.masked = false
		return
	var tw: Tween = w.create_tween()
	tw.tween_property(w, "scale:x", 0.0, 0.09)
	tw.tween_callback(func() -> void:
		w.masked = false
		_sfx.play("reveal"))
	tw.tween_property(w, "scale:x", 1.0, 0.09)


func _unhandled_input(event: InputEvent) -> void:
	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	if _game == null:
		return
	for t: int in _game.tracks.size():
		if _track_rect(t).has_point(click.position):
			_take(t)
			return


func _take(track: int) -> void:
	if _game.status() != Game.PLAYING or _game.tracks[track].is_empty():
		return
	var id: int = _game.tracks[track][0]
	var head: Node2D = _wagons[id]
	var before: Game = _game.clone() as Game
	var ev: Dictionary = _game.take(track)
	if ev.is_empty():
		_shake(head)
		_sfx.play("nope")
		return
	_history.append(before)
	# La règle est appliquée tout de suite, jusqu'au bout des mouvements automatiques.
	# Les animations sont seulement programmées : elles ne bloquent jamais la saisie.
	head.modulate = Color.WHITE
	_pop(head)
	Input.vibrate_handheld(15)
	var slot: int = ev["slot"]
	if slot >= 0:
		_sfx.play("pop")
		_roll(head, _slot_pos(slot, _game.slots[slot]["ids"].size() - 1), 0.0, Callable(), _couple.bind(head))
	else:
		_sfx.play("wait")
		_roll(head, _buffer_pos(_game.buffer.size() - 1), 0.0, Callable(), Callable())
	# Enchaînement : les wagons en attente montent en cascade, un train complet part
	# dès que son dernier wagon est attelé.
	var next_start: float = CASCADE_GAP
	var last_arrival: float = ROLL_TIME
	var chain: int = 0
	while true:
		var step: Dictionary = _game.settle_step()
		if step.is_empty():
			break
		if step["type"] == "load":
			chain += 1
			_schedule_load(step, next_start, chain)
			last_arrival = next_start + ROLL_TIME
			next_start += CASCADE_GAP
		else:
			var start: float = maxf(next_start, last_arrival)
			_schedule_depart(step, start)
			# Les wagons en attente pour le train suivant arrivent en même temps que lui.
			next_start = start + NEXT_TRAIN_DELAY - ROLL_TIME
			last_arrival = start + NEXT_TRAIN_DELAY
	_relayout(MOVE_TIME, id)
	if _game.status() != Game.PLAYING:
		var gen: int = _gen
		get_tree().create_timer(maxf(next_start, last_arrival) + 0.5).timeout.connect(func() -> void:
			if gen == _gen:
				_finish())


## Un wagon en attente rejoint son train après `delay` secondes.
## Chaque wagon de l'enchaînement sonne un peu plus aigu que le précédent.
func _schedule_load(step: Dictionary, delay: float, chain: int) -> void:
	var w: Node2D = _wagons[step["id"]]
	var slot: int = step["slot"]
	var target: Vector2 = _slot_pos(slot, _game.slots[slot]["ids"].size() - 1)
	_roll(w, target, delay, func() -> void:
		_pop(w)
		_sfx.play("pop", 1.0 + 0.15 * chain), _couple.bind(w))


## Le train complet d'un quai part après `delay` secondes ; le suivant le remplace.
func _schedule_depart(step: Dictionary, delay: float) -> void:
	var slot: int = step["slot"]
	var loco: Node2D = _locos[slot]
	var leaving: Array[Node2D] = [loco]
	for id: int in step["ids"]:
		leaving.append(_wagons[id])
		_wagons.erase(id)
	for n: Node2D in leaving:
		var tw: Tween = n.create_tween()
		tw.tween_interval(delay)
		if n == loco:
			tw.tween_callback(func() -> void:
				_sfx.play("whistle")
				Input.vibrate_handheld(40)
				loco.add_child(_smoke()))
		tw.tween_interval(0.12)
		tw.tween_property(n, "position:x", _size().x + 300.0, DEPART_TIME).as_relative().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_callback(n.queue_free)
	# Le quai se vide de ses cadres au moment où le train s'ébranle.
	_schedule_view(slot, delay + 0.12, {"color": -1, "size": 0}, null)
	_spawn_loco(slot, delay + NEXT_TRAIN_DELAY - LOCO_IN_TIME)
	queue_redraw()


func _finish() -> void:
	match _game.status():
		Game.WON:
			_celebrate()
		Game.LOST:
			_sfx.play("lose")
			_show_overlay("Gare bloquée !", "Annuler le dernier coup", 0, "Recommencer le niveau")


## Revient à l'état d'avant le dernier coup.
func _undo() -> void:
	if _history.is_empty():
		_sfx.play("nope")
		return
	_gen += 1
	_game = _history.pop_back()
	_overlay.visible = false
	_rebuild()
	_sfx.play("undo")


func _smoke() -> CPUParticles2D:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.position = Vector2(26.0, -20.0)
	p.amount = 18
	p.lifetime = 0.8
	p.local_coords = false
	p.direction = Vector2(-0.3, -1.0)
	p.spread = 25.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 120.0
	p.scale_amount_min = 10.0
	p.scale_amount_max = 22.0
	p.color = Color(0.35, 0.35, 0.4, 0.55)
	return p


func _celebrate() -> void:
	# Note : 3 étoiles si l'attente n'a jamais dépassé le minimum possible (« par »).
	var par: int = int(_levels[_level_index].get("par", 0))
	var stars: int = clampi(3 - (_game.peak_buffer - par), 1, 3)
	_sfx.play("win")
	var key: String = str(_level_index)
	_progress["stars"][key] = maxi(stars, int(_progress["stars"].get(key, 0)))
	_progress["level"] = (_level_index + 1) % _levels.size()
	_progress["reached"] = maxi(_reached(), mini(_level_index + 1, _levels.size() - 1))
	_save_progress()
	var confetti: CPUParticles2D = CPUParticles2D.new()
	confetti.position = Vector2(_size().x / 2.0, _size().y * 0.25)
	confetti.one_shot = true
	confetti.explosiveness = 0.9
	confetti.amount = 90
	confetti.lifetime = 2.2
	confetti.spread = 180.0
	confetti.initial_velocity_min = 250.0
	confetti.initial_velocity_max = 650.0
	confetti.gravity = Vector2(0.0, 700.0)
	confetti.scale_amount_min = 8.0
	confetti.scale_amount_max = 16.0
	var ramp: Gradient = Gradient.new()
	ramp.colors = PackedColorArray([PALETTE[0], PALETTE[1], PALETTE[2], PALETTE[3], PALETTE[4]])
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	confetti.color_initial_ramp = ramp
	# Calque au-dessus du voile de fin pour que les confettis restent vifs.
	var fx: CanvasLayer = CanvasLayer.new()
	fx.layer = 2
	add_child(fx)
	fx.add_child(confetti)
	confetti.emitting = true
	get_tree().create_timer(3.0).timeout.connect(fx.queue_free)
	if _level_index == _levels.size() - 1:
		_show_overlay("Terminus !", "Rejouer depuis le début", stars, "Voir la carte")
	else:
		_show_overlay("Gare desservie !", "Gare suivante", stars, "Voir la carte")


# --- Décor -------------------------------------------------------------------

func _track(from: Vector2, to: Vector2) -> void:
	var normal: Vector2 = (to - from).normalized().orthogonal() * 18.0
	draw_line(from + normal, to + normal, RAIL, 5.0)
	draw_line(from - normal, to - normal, RAIL, 5.0)


func _place(center: Vector2, color: Color) -> void:
	draw_rect(Rect2(center - Vector2(32.0, 32.0), Vector2(64.0, 64.0)), Color(color, 0.22))
	draw_rect(Rect2(center - Vector2(32.0, 32.0), Vector2(64.0, 64.0)), color, false, 3.0)


func _draw() -> void:
	if _game == null:
		return
	var sz: Vector2 = _size()
	var font: Font = ThemeDB.fallback_font
	# Voies d'arrivée : le wagon du bas est celui qu'on peut prendre.
	for t: int in _game.tracks.size():
		var x: float = _track_x(t)
		draw_rect(_track_rect(t), Color(1, 1, 1, 0.35))
		_track(Vector2(x, _track_rect(t).position.y), Vector2(x, _head_y() + 44.0))
	# Voie d'attente : vire au rouge quand il ne reste qu'une place.
	var tight: bool = _game.buffer.size() >= _game.buffer_size - 1
	var first: Vector2 = _buffer_pos(0)
	var last: Vector2 = _buffer_pos(_game.buffer_size - 1)
	_track(first - Vector2(60.0, 0.0), last + Vector2(60.0, 0.0))
	for b: int in _game.buffer_size:
		_place(_buffer_pos(b), PALETTE[0] if tight else INK)
	# Quais de départ : emplacements à remplir derrière chaque locomotive.
	for s: int in _game.slots.size():
		var loco: Vector2 = _loco_pos(s)
		_track(Vector2(0.0, loco.y), Vector2(sz.x, loco.y))
		if s >= _slot_view.size() or _slot_view[s]["color"] == -1:
			continue
		for k: int in int(_slot_view[s]["size"]):
			_place(_slot_pos(s, k), PALETTE[_slot_view[s]["color"]])
	# Trains à venir : couleur et longueur.
	for p: int in _pending_view.size():
		var center: Vector2 = Vector2(266.0 + p * 38.0, sz.y * 0.945)
		draw_circle(center, 16.0, PALETTE[_pending_view[p][0]])
		draw_string(font, center + Vector2(-16.0, 7.0), str(_pending_view[p][1]),
			HORIZONTAL_ALIGNMENT_CENTER, 32.0, 20, Color.WHITE)


# --- Vérification automatique --------------------------------------------------

## Options après « -- » : --level=N, --autoplay=K (K coups du solveur), --pace=S (secondes
## entre deux touches, 0 = rafale), --undo=N (N annulations ensuite), --wait=S (attente
## avant capture), --map=1 (ouvre la carte de la ligne), --shot=chemin.png.
func _debug_hook() -> void:
	var opts: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=")
		if kv.size() == 2:
			opts[kv[0]] = kv[1]
	if opts.is_empty():
		return
	if opts.has("level"):
		_start_level(int(opts["level"]) - 1)
	var solution: Array = Solver.solve(_game)["moves"]
	var pace: float = float(opts.get("pace", "0.25"))
	for k: int in mini(int(opts.get("autoplay", "0")), solution.size()):
		_take(solution[k])
		if pace > 0.0:
			await _wait(pace)
	if opts.has("map"):
		_open_map()
	for n: int in int(opts.get("undo", "0")):
		await _wait(0.4)
		_undo()
	if opts.has("shot"):
		await _wait(float(opts.get("wait", "2.5")))
		get_viewport().get_texture().get_image().save_png(opts["shot"])
		get_tree().quit()
