extends Node2D
## Écran de jeu du prototype « Gare de triage » : rendu provisoire, saisie tactile et retours.
## Toute la règle du jeu vit dans triage_game.gd ; ce script ne fait qu'afficher et animer.

const Game := preload("res://src/triage_game.gd")
const Solver := preload("res://src/triage_solver.gd")
const Piece := preload("res://src/piece.gd")
const Sfx := preload("res://src/sfx.gd")

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
const MOVE_TIME := 0.16
const DEPART_TIME := 0.45
const SAVE_PATH := "user://progress.json"

var _levels: Array = []
var _level_index: int = 0
var _game: Game
var _wagons: Dictionary = {}
var _locos: Array[Node2D] = []
var _gen: int = 0
var _stars: int = 0
## Progression enregistrée : niveau courant et meilleure note par niveau.
var _progress: Dictionary = {"level": 0, "stars": {}}
var _save_enabled: bool = true

var _pieces: Node2D
var _sfx: Sfx
var _title: Label
var _hint: Label
var _stars_label: Label
var _pending_label: Label
var _restart: Button
var _overlay: ColorRect
var _overlay_label: Label
var _overlay_button: Button
var _star_row: Control


func _ready() -> void:
	RenderingServer.set_default_clear_color(BG)
	_levels = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels.json"))
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
	_debug_hook()


# --- Progression -------------------------------------------------------------

func _load_progress() -> void:
	if not _save_enabled or not FileAccess.file_exists(SAVE_PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Dictionary and data.has("level") and data.get("stars") is Dictionary:
		_progress = data


func _save_progress() -> void:
	if not _save_enabled:
		return
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_progress))
		f.close()


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


func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_title = _label(40)
	_stars_label = _label(26)
	_hint = _label(23)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pending_label = _label(26)
	_pending_label.text = "Trains à venir :"
	_restart = Button.new()
	_restart.text = "Recommencer"
	_restart.add_theme_font_size_override("font_size", 26)
	_restart.pressed.connect(func() -> void: _start_level(_level_index))
	for c: Control in [_title, _stars_label, _hint, _pending_label, _restart]:
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
	_overlay_button = Button.new()
	_overlay_button.add_theme_font_size_override("font_size", 38)
	_overlay_button.pressed.connect(_on_overlay_button)
	_overlay.add_child(_overlay_button)
	_layout_ui()


func _layout_ui() -> void:
	var sz: Vector2 = _size()
	# Décale l'en-tête sous l'encoche ou la barre d'état du téléphone.
	var dy: float = maxf(0.0, _top_inset() - 50.0)
	_title.position = Vector2(40.0, 70.0 + dy)
	_restart.size = Vector2(220.0, 60.0)
	_restart.position = Vector2(sz.x - 260.0, 66.0 + dy)
	_stars_label.position = Vector2(40.0, 124.0 + dy)
	_hint.position = Vector2(40.0, 162.0 + dy)
	_hint.size = Vector2(sz.x - 80.0, 70.0)
	_pending_label.position = Vector2(40.0, sz.y * 0.945 - 18.0)
	_overlay.position = Vector2.ZERO
	_overlay.size = sz
	_overlay_label.position = Vector2(0.0, sz.y * 0.30)
	_overlay_label.size = Vector2(sz.x, 90.0)
	_star_row.position = Vector2(sz.x / 2.0, sz.y * 0.43)
	_overlay_button.size = Vector2(420.0, 100.0)
	_overlay_button.position = Vector2((sz.x - 420.0) / 2.0, sz.y * 0.52)


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


func _show_overlay(text: String, button: String, stars: int) -> void:
	_overlay_label.text = text
	_overlay_button.text = button
	_stars = stars
	_star_row.queue_redraw()
	_overlay.visible = true
	_overlay.modulate.a = 0.0
	_overlay.create_tween().tween_property(_overlay, "modulate:a", 1.0, 0.25)


func _draw_stars() -> void:
	if _stars <= 0:
		return
	for i: int in 3:
		var center: Vector2 = Vector2((i - 1) * 110.0, 0.0)
		var points: PackedVector2Array = PackedVector2Array()
		for k: int in 10:
			var radius: float = 48.0 if k % 2 == 0 else 21.0
			points.append(center + Vector2.from_angle(-PI / 2.0 + k * PI / 5.0) * radius)
		_star_row.draw_colored_polygon(points, GOLD if i < _stars else Color(1, 1, 1, 0.25))


func _on_overlay_button() -> void:
	if _game.status() == Game.WON:
		_start_level((_level_index + 1) % _levels.size())
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
	for child: Node in _pieces.get_children():
		child.queue_free()
	_wagons.clear()
	_locos.clear()
	_game = Game.new()
	_game.load_level(_levels[index])
	for id: int in _game.colors.size():
		_wagons[id] = _new_piece(PALETTE[_game.colors[id]], false)
	for s: int in _game.slots.size():
		_locos.append(null)
		_spawn_loco(s)
	_title.text = "Niveau %d / %d" % [index + 1, _levels.size()]
	_stars_label.text = "Étoiles : %d / %d" % [_total_stars(), _levels.size() * 3]
	_hint.text = ""
	if index == 0:
		_hint.text = "Touchez une voie pour envoyer son wagon du bas vers son train. S'il n'est pas attendu, il patiente sur la voie d'attente."
	_relayout(0.0)


func _new_piece(color: Color, is_loco: bool) -> Node2D:
	var p: Node2D = Piece.new()
	p.color = color
	p.is_loco = is_loco
	_pieces.add_child(p)
	return p


## Crée la locomotive du quai. Avec `delay` >= 0, elle entre par la gauche après ce délai.
func _spawn_loco(slot: int, delay: float = -1.0) -> void:
	var color: int = _game.slots[slot]["color"]
	if color == -1:
		_locos[slot] = null
		return
	var loco: Node2D = _new_piece(PALETTE[color], true)
	_locos[slot] = loco
	if delay < 0.0:
		loco.position = _loco_pos(slot)
		return
	loco.position = Vector2(-200.0, _loco_pos(slot).y)
	var tw: Tween = loco.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(loco, "position", _loco_pos(slot), 0.3).set_trans(Tween.TRANS_SINE)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _move(node: Node2D, target: Vector2, duration: float) -> void:
	if duration <= 0.0:
		node.position = target
	elif node.position != target:
		var tw: Tween = node.create_tween()
		tw.tween_property(node, "position", target, duration).set_trans(Tween.TRANS_SINE)


func _pop(node: Node2D) -> void:
	node.scale = Vector2(1.3, 1.3)
	node.create_tween().tween_property(node, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _shake(node: Node2D) -> void:
	var x: float = node.position.x
	var tw: Tween = node.create_tween()
	for dx: float in [10.0, -10.0, 6.0, 0.0]:
		tw.tween_property(node, "position:x", x + dx, 0.04)


## Place chaque wagon là où la logique dit qu'il se trouve.
func _relayout(duration: float) -> void:
	for t: int in _game.tracks.size():
		for k: int in _game.tracks[t].size():
			var w: Node2D = _wagons[_game.tracks[t][k]]
			_move(w, _track_pos(t, k), duration)
			w.modulate = Color(1, 1, 1, 1.0 if k == 0 else 0.5)
	for b: int in _game.buffer.size():
		var w: Node2D = _wagons[_game.buffer[b]]
		_move(w, _buffer_pos(b), duration)
		w.modulate = Color.WHITE
	# Les wagons à quai sont placés par leurs propres animations ; on ne les
	# repositionne ici que pour un placement immédiat (changement de taille d'écran).
	if duration <= 0.0:
		for s: int in _game.slots.size():
			var ids: Array = _game.slots[s]["ids"]
			for k: int in ids.size():
				_move(_wagons[ids[k]], _slot_pos(s, k), 0.0)
	queue_redraw()


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
	var head: Node2D = _wagons[_game.tracks[track][0]]
	var ev: Dictionary = _game.take(track)
	if ev.is_empty():
		_shake(head)
		_sfx.play("nope")
		return
	# La règle est appliquée tout de suite, jusqu'au bout des mouvements automatiques.
	# Les animations sont seulement programmées : elles ne bloquent jamais la saisie.
	head.modulate = Color.WHITE
	if ev["slot"] >= 0:
		_move(head, _slot_pos(ev["slot"], _game.slots[ev["slot"]]["ids"].size() - 1), MOVE_TIME)
	_pop(head)
	_sfx.play("pop" if ev["slot"] >= 0 else "wait")
	Input.vibrate_handheld(15)
	var t: float = 0.0
	var chain: int = 0
	while true:
		var step: Dictionary = _game.settle_step()
		if step.is_empty():
			break
		t += MOVE_TIME
		if step["type"] == "load":
			chain += 1
			_schedule_load(step, t, chain)
		else:
			_schedule_depart(step, t)
			t += DEPART_TIME
	_relayout(MOVE_TIME)
	if _game.status() != Game.PLAYING:
		var gen: int = _gen
		get_tree().create_timer(t + 0.5).timeout.connect(func() -> void:
			if gen == _gen:
				_finish())


## Un wagon en attente rejoint son train après `delay` secondes.
## Enchaînement : chaque wagon qui monte sonne un peu plus aigu.
func _schedule_load(step: Dictionary, delay: float, chain: int) -> void:
	var w: Node2D = _wagons[step["id"]]
	var slot: int = step["slot"]
	var target: Vector2 = _slot_pos(slot, _game.slots[slot]["ids"].size() - 1)
	var tw: Tween = w.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		_pop(w)
		_sfx.play("pop", 1.0 + 0.15 * chain))
	tw.tween_property(w, "position", target, MOVE_TIME).set_trans(Tween.TRANS_SINE)


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
		tw.tween_property(n, "position:x", _size().x + 300.0, DEPART_TIME).as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(n.queue_free)
	_spawn_loco(slot, delay + 0.12 + DEPART_TIME)
	queue_redraw()


func _finish() -> void:
	match _game.status():
		Game.WON:
			_celebrate()
		Game.LOST:
			_sfx.play("lose")
			_show_overlay("Gare bloquée !", "Recommencer", 0)


func _smoke() -> CPUParticles2D:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.position = Vector2(26.0, -20.0)
	p.amount = 14
	p.lifetime = 0.7
	p.direction = Vector2(-0.4, -1.0)
	p.spread = 25.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 120.0
	p.scale_amount_min = 10.0
	p.scale_amount_max = 20.0
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
		_show_overlay("Bravo, tout est réussi !", "Rejouer depuis le début", stars)
	else:
		_show_overlay("Niveau réussi !", "Niveau suivant", stars)


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
		if _game.slots[s]["color"] == -1:
			continue
		for k: int in _game.train_size:
			_place(_slot_pos(s, k), PALETTE[_game.slots[s]["color"]])
	# Trains à venir.
	for p: int in _game.pending.size():
		draw_circle(Vector2(264.0 + p * 36.0, sz.y * 0.945), 13.0, PALETTE[_game.pending[p]])


# --- Vérification automatique --------------------------------------------------

## Options après « -- » : --level=N, --autoplay=K (K coups du solveur), --pace=S (secondes
## entre deux touches, 0 = rafale), --wait=S (attente avant capture), --shot=chemin.png.
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
	if opts.has("shot"):
		await _wait(float(opts.get("wait", "2.5")))
		get_viewport().get_texture().get_image().save_png(opts["shot"])
		get_tree().quit()
