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
	Color("f0412b"), Color("2f86f5"), Color("ffc61a"),
	Color("2fb344"), Color("a35cf2"), Color("f760b4"),
]
const STEP := 74.0
const TRACK_STEP := 68.0
const TRACK_ROWS := 8
const BG := Color("231d55")
const RAIL := Color("d6d0f7")
const TIE := Color("6d61c9")
const INK := Color("1b1642")
const GOLD := Color("ffc61a")
## Plateau en relief, creux des voies, texte clair, boutons.
const TRAY := Color("453a9e")
const SLOT := Color("2a2370")
const LIGHT := Color("efeaff")
## Réseau : abscisse de la voie en échelle (bord gauche) et rayon des courbes.
const LADDER_X := 62.0
const BEND := 36.0
## Durées d'essai des animations, en secondes.
const MOVE_TIME := 0.16
const ROLL_TIME := 0.38
const CASCADE_GAP := 0.14
const PAIR_GAP := 0.07
const DEPART_TIME := 0.6
const LOCO_IN_TIME := 0.35
## Délai entre le début d'un départ et l'arrivée à quai de la locomotive suivante.
const NEXT_TRAIN_DELAY := 0.12 + DEPART_TIME * 0.7 + LOCO_IN_TIME
## Plafond d'états explorés pour savoir s'il reste une solution (valeur d'essai). Au-delà,
## on ne sait pas : rien n'est annoncé.
const CHECK_LIMIT := 20000
const SAVE_PATH := "user://progress.json"
## À incrémenter quand le jeu de niveaux change : la progression repart alors de zéro.
const SAVE_VERSION := 4

var _levels: Array = []
var _level_index: int = 0
var _game: Game
var _wagons: Dictionary = {}
var _locos: Array[Node2D] = []
## Locomotives des trains à venir, garées sur la voie du bas (la première est la prochaine).
var _queue: Array[Node2D] = []
## États précédents, pour le bouton « Annuler ».
var _history: Array[Game] = []
## Nombre de coups joués au dernier moment où l'on sait que le niveau était encore faisable.
var _safe_depth: int = 0
## Numéro de la dernière vérification « reste-t-il une solution ? » ; les réponses plus
## anciennes sont ignorées.
var _check_seq: int = 0
## Vérifications en cours, chacune dans son fil d'exécution.
var _checks: Array[Thread] = []
## Wagons mystère déjà dévoilés (identifiant -> true).
var _revealed: Dictionary = {}
## Ce que l'écran montre pour chaque quai ({color, size}) et pour les trains à venir
## ([couleur, longueur]). Ces vues suivent les animations, pas la règle : la règle est
## déjà à jour au moment de la touche, l'affichage change quand le train arrive vraiment.
var _slot_view: Array[Dictionary] = []
var _pending_view: Array = []
## Nombre de places d'attente dessinées : une place ajoutée par un wagon « +1 »
## n'apparaît qu'à l'arrivée de ce wagon.
var _buffer_view: int = 0
## Dernière voie de destination empruntée (0 = attente, 1.. = quais) : oriente les aiguillages.
var _switch_lane: int = -1
## Numéros d'ordre des mises à jour de ces vues : en jouant très vite, deux animations
## peuvent se terminer dans le désordre ; on n'applique jamais un état plus ancien que
## celui déjà affiché (par quai, et pour la liste des trains à venir).
var _view_seq: int = 0
var _view_applied: int = 0
var _slot_applied: Array[int] = []
var _gen: int = 0
## Images du décor (assets/ui), gardées en mémoire pour le dessin.
var _tex: Dictionary = {}
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
	# Police ronde et grasse du système (aucun fichier à embarquer).
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Arial Rounded MT Bold", "Arial Rounded MT", "Helvetica Neue", "Arial"])
	font.font_weight = 700
	ThemeDB.fallback_font = font
	for name: String in ["tray", "slot", "socket", "tie", "knob", "bumper", "star", "star_empty"]:
		_tex[name] = load("res://assets/ui/%s.svg" % name)
	for i: int in PALETTE.size():
		_tex["chip_%d" % i] = load("res://assets/ui/chip_%d.svg" % i)
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
	l.add_theme_color_override("font_color", LIGHT)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 8)
	return l


## Boîte arrondie ; `depth` > 0 ajoute une tranche sombre en bas (relief).
func _box(fill: Color, radius: int, depth: int = 0) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	box.anti_aliasing_size = 1.5
	if depth > 0:
		box.border_width_bottom = depth
		box.border_color = fill.darkened(0.42)
	return box


## Bouton bombé : une image en 9 tranches (assets/ui/button_<look>.svg) glissée derrière
## le texte, remplacée par sa version enfoncée pendant l'appui.
func _style_button(b: Button, look: String) -> void:
	var normal: Texture2D = load("res://assets/ui/button_%s.svg" % look)
	var pressed: Texture2D = load("res://assets/ui/button_%s_pressed.svg" % look)
	var bg: NinePatchRect = b.get_node_or_null("Bg") as NinePatchRect
	if bg == null:
		bg = NinePatchRect.new()
		bg.name = "Bg"
		bg.show_behind_parent = true
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# L'image est dessinée au double de sa taille à l'écran.
		bg.scale = Vector2(0.5, 0.5)
		bg.patch_margin_left = 50
		bg.patch_margin_right = 50
		bg.patch_margin_top = 50
		bg.patch_margin_bottom = 70
		b.add_child(bg)
		b.resized.connect(func() -> void: bg.size = b.size * 2.0)
		b.button_down.connect(func() -> void: bg.texture = b.get_meta("pressed_tex"))
		b.button_up.connect(func() -> void: bg.texture = b.get_meta("normal_tex"))
	b.set_meta("normal_tex", normal)
	b.set_meta("pressed_tex", pressed)
	bg.texture = normal
	bg.size = b.size * 2.0
	var empty: StyleBoxEmpty = StyleBoxEmpty.new()
	empty.content_margin_left = 18.0
	empty.content_margin_right = 18.0
	# Le texte se centre sur le dessus du bouton, pas sur sa tranche.
	empty.content_margin_bottom = 13.0
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, empty)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, Color.WHITE)
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", 8)


func _button(text: String, font_size: int, action: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(action)
	_style_button(b, "violet")
	return b


func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	# Le titre est un bouton : il ouvre la carte de la ligne.
	_title = _button("", 30, _open_map)
	_title.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_button(_title, "dark")
	_stars_label = _label(26)
	_hint = _label(23)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pending_label = _label(22)
	_pending_label.text = "Prochains trains"
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
	_overlay_label.add_theme_color_override("font_outline_color", INK)
	_overlay_label.add_theme_constant_override("outline_size", 14)
	_overlay_button = _button("", 38, _on_overlay_button)
	_style_button(_overlay_button, "green")
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
	_style_button(_map._close, "violet")
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
	_title.size = Vector2(sz.x - 310.0, 60.0)
	_map.position = Vector2.ZERO
	_map.top_inset = dy
	_map.size = sz
	_restart.size = Vector2(220.0, 60.0)
	_restart.position = Vector2(sz.x - 260.0, 62.0 + dy)
	_undo_button.size = Vector2(220.0, 60.0)
	_undo_button.position = Vector2(sz.x - 260.0, 134.0 + dy)
	_stars_label.position = Vector2(40.0, 140.0 + dy)
	_hint.position = Vector2(40.0, 196.0 + dy)
	_hint.size = Vector2(sz.x - 80.0, 70.0)
	# Légende de la voie des locomotives en attente, seulement s'il y a la place.
	_pending_label.position = Vector2(26.0, _queue_y() - 68.0)
	_pending_label.visible = _queue_y() - 68.0 > _lane_y(2) + 86.0
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
		var tex: Texture2D = _tex["star" if i < _stars_shown else "star_empty"]
		_star_row.draw_texture_rect(tex, Rect2((i - 1) * 110.0 - 52.0, -54.0, 104.0, 108.0), false)


func _on_overlay_button() -> void:
	if _game.status() == Game.WON:
		_start_level((_level_index + 1) % _levels.size())
	else:
		_rewind()


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


## Ordonnée de la voie collectrice, où se rejoignent les voies d'arrivée.
func _collector_y() -> float:
	return _head_y() + 82.0


## Ordonnée d'une voie de destination : 0 = attente, 1.. = quais.
func _lane_y(lane: int) -> float:
	return maxf(_size().y * 0.72, _collector_y() + 2.0 * BEND) + lane * _size().y * 0.072


func _buffer_pos(b: int) -> Vector2:
	return Vector2(LADDER_X + 78.0 + b * STEP, _lane_y(0))


func _loco_pos(slot: int) -> Vector2:
	return Vector2(_size().x - 120.0, _lane_y(slot + 1))


## Voie de garage, en bas de l'écran : les locomotives des trains à venir y attendent.
func _queue_y() -> float:
	return _size().y * 0.962


## Place de la i-ième locomotive en attente (0 = la prochaine, à gauche).
func _queue_pos(i: int) -> Vector2:
	return Vector2(74.0 + i * 88.0, _queue_y())


func _slot_pos(slot: int, k: int) -> Vector2:
	return _loco_pos(slot) - Vector2(STEP * (k + 1) + 4.0, 0.0)


## Angles du trajet d'une voie d'arrivée vers une voie de destination : la collectrice,
## puis l'échelle.
func _route_from_track(track: int, lane: int) -> Array[Vector2]:
	return [Vector2(_track_x(track), _collector_y()), Vector2(LADDER_X, _collector_y()),
		Vector2(LADDER_X, _lane_y(lane))]


## Angles du trajet de la voie d'attente vers un quai : retour à l'échelle, puis le quai.
func _route_from_buffer(lane: int) -> Array[Vector2]:
	return [Vector2(LADDER_X, _lane_y(0)), Vector2(LADDER_X, _lane_y(lane))]


## Ligne brisée dont les angles sont arrondis en courbes de rayon BEND (moins si les
## segments voisins sont trop courts).
func _rounded(points: Array[Vector2]) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var last: int = points.size() - 1
	out.append(points[0])
	for i: int in range(1, last):
		var len_in: float = points[i].distance_to(points[i - 1]) * (0.5 if i - 1 > 0 else 1.0)
		var len_out: float = points[i].distance_to(points[i + 1]) * (0.5 if i + 1 < last else 1.0)
		var r: float = minf(BEND, minf(len_in, len_out))
		if r < 1.0:
			continue
		var a: Vector2 = points[i] + (points[i - 1] - points[i]).normalized() * r
		var b: Vector2 = points[i] + (points[i + 1] - points[i]).normalized() * r
		for k: int in 9:
			out.append(a.bezier_interpolate(a.lerp(points[i], 0.55), b.lerp(points[i], 0.55), b, k / 8.0))
	out.append(points[last])
	return out


# --- Partie ------------------------------------------------------------------

func _start_level(index: int) -> void:
	_gen += 1
	_level_index = index
	_overlay.visible = false
	_history.clear()
	_safe_depth = 0
	_check_seq += 1
	_revealed.clear()
	_game = Game.new()
	_game.load_level(_levels[index])
	_switch_lane = -1
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
	_queue.clear()
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
	# Une locomotive par train à venir, tournée vers la gauche, sa longueur écrite dessus.
	for p: int in _game.pending.size():
		var waiting: Node2D = _new_piece(_game.pending[p], true)
		waiting.set("label", str(_game.pending_sizes[p]))
		waiting.set("heading", PI)
		waiting.scale = Vector2(0.86, 0.86)
		waiting.position = _queue_pos(p)
		_queue.append(waiting)
	_buffer_view = _game.buffer_size
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
	p.color = PALETTE[kind] if kind < PALETTE.size() else Color.WHITE
	p.is_bonus = kind == Game.BONUS
	p.kind = kind
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
	# La première locomotive de la voie de garage sort par la gauche pendant que le
	# train précédent s'en va, puis entre à quai ; les suivantes avancent d'une place.
	if not _queue.is_empty():
		var leaving: Node2D = _queue.pop_front()
		var out: Tween = leaving.create_tween()
		out.tween_interval(maxf(0.0, delay - 0.42))
		out.tween_property(leaving, "position:x", -160.0, 0.40).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		out.tween_callback(leaving.queue_free)
		for i: int in _queue.size():
			var shift: Tween = _queue[i].create_tween()
			shift.tween_interval(maxf(0.0, delay - 0.30) + 0.04 * i)
			shift.tween_property(_queue[i], "position", _queue_pos(i), 0.34).set_trans(Tween.TRANS_SINE)
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
		node.remove_meta("roll_target")
		node.z_index = 0


## Glissement simple en ligne droite (décalage d'une voie, resserrement de l'attente).
func _move(node: Node2D, target: Vector2, duration: float) -> void:
	_stop_move(node)
	if duration <= 0.0:
		node.position = target
	elif node.position != target:
		var tw: Tween = node.create_tween()
		tw.tween_property(node, "position", target, duration).set_trans(Tween.TRANS_SINE)
		node.set_meta("move", tw)


## Fait rouler un wagon jusqu'à `target` en suivant les rails : `corners` sont les angles
## du trajet (voir `_route_from_track` et `_route_from_buffer`).
## `on_start` et `on_arrive` sont appelés au départ et à l'arrivée (Callable() pour rien).
func _roll(node: Node2D, corners: Array[Vector2], target: Vector2, delay: float,
		on_start: Callable, on_arrive: Callable) -> void:
	_stop_move(node)
	var curve: Curve2D = Curve2D.new()
	var tw: Tween = node.create_tween()
	node.set_meta("move", tw)
	node.set_meta("roll_target", target)
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		node.z_index = 5
		# Le trajet part de là où le wagon se trouve vraiment à cet instant.
		var points: Array[Vector2] = [node.position]
		points.append_array(corners)
		points.append(target)
		for p: Vector2 in _rounded(points):
			curve.add_point(p)
		if on_start.is_valid():
			on_start.call())
	tw.tween_method(func(t: float) -> void:
		var length: float = curve.get_baked_length()
		var at: float = t * length
		node.position = curve.sample_baked(at)
		# Le wagon s'aligne sur les rails. Il est symétrique : on garde le sens le plus
		# proche de son orientation actuelle, donc il recule sans jamais se retourner.
		var along: Vector2 = curve.sample_baked(minf(at + 5.0, length)) - curve.sample_baked(maxf(at - 5.0, 0.0))
		if along.length() > 0.01:
			var angle: float = along.angle()
			if absf(angle_difference(float(node.get("heading")), angle)) > PI / 2.0:
				angle += PI
			node.set("heading", angle),
		0.0, 1.0, ROLL_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void:
		node.position = target
		# Toutes les destinations sont des voies horizontales.
		node.set("heading", 0.0)
		node.z_index = 0
		node.remove_meta("move")
		node.remove_meta("roll_target")
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
## `skip` : wagons dont le déplacement est déjà animé par ailleurs.
func _relayout(duration: float, skip: Array = []) -> void:
	for t: int in _game.tracks.size():
		for k: int in _game.tracks[t].size():
			var id: int = _game.tracks[t][k]
			var w: Node2D = _wagons[id]
			# Une voie peut porter plus de wagons que l'écran n'en montre : ceux du haut
			# attendent, cachés, au bout de la voie et apparaissent en descendant.
			if k >= TRACK_ROWS:
				_stop_move(w)
				w.visible = false
				w.position = _track_pos(t, TRACK_ROWS)
			else:
				if not w.visible:
					w.visible = true
					w.modulate.a = 0.0
					w.create_tween().tween_property(w, "modulate:a", 1.0, maxf(duration, 0.01))
				_move(w, _track_pos(t, k), duration)
			# Sur une voie d'arrivée, les wagons regardent vers le bas, dans le sens de la marche.
			w.set("heading", PI / 2.0)
			w.coupled = k > 0 and _game.linked[_game.tracks[t][k - 1]] == 1
			if k == 0 and w.masked:
				_reveal(id, duration > 0.0)
	for b: int in _game.buffer.size():
		var waiting: Node2D = _wagons[_game.buffer[b]]
		# Un wagon qui roule déjà vers cette place finit son trajet sur les rails.
		var rolling: bool = duration > 0.0 and waiting.has_meta("roll_target") \
				and waiting.get_meta("roll_target") == _buffer_pos(b)
		if not skip.has(_game.buffer[b]) and not rolling:
			_move(waiting, _buffer_pos(b), duration)
			waiting.set("heading", 0.0)
	# Les wagons à quai sont placés par leurs propres animations ; on ne les
	# repositionne ici que pour un placement immédiat (changement de taille d'écran).
	if duration <= 0.0:
		for s: int in _game.slots.size():
			var ids: Array = _game.slots[s]["ids"]
			for k: int in ids.size():
				_move(_wagons[ids[k]], _slot_pos(s, k), 0.0)
				_wagons[ids[k]].set("heading", 0.0)
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
	var head: Node2D = _wagons[_game.tracks[track][0]]
	var before: Game = _game.clone() as Game
	var ev: Dictionary = _game.take(track)
	if ev.is_empty():
		_shake(head)
		_sfx.play("nope")
		return
	_history.append(before)
	# La règle est appliquée tout de suite, jusqu'au bout des mouvements automatiques.
	# Les animations sont seulement programmées : elles ne bloquent jamais la saisie.
	Input.vibrate_handheld(15)
	var taken: Array = []
	var boarded: bool = false
	for i: int in ev["moves"].size():
		var id: int = ev["moves"][i]["id"]
		var slot: int = ev["moves"][i]["slot"]
		var w: Node2D = _wagons[id]
		taken.append(id)
		w.coupled = false
		_pop(w)
		# Deux wagons attelés partent l'un derrière l'autre.
		var delay: float = PAIR_GAP * i
		if slot == Game.TO_BONUS:
			# Le wagon « +1 » roule au bout de la voie d'attente et y devient une place.
			boarded = true
			_wagons.erase(id)
			_switch_lane = 0
			_roll(w, _route_from_track(track, 0), _buffer_pos(_game.buffer_size - 1), delay,
				Callable(), _become_place.bind(w, _game.buffer_size))
		elif slot >= 0:
			boarded = true
			_switch_lane = slot + 1
			_roll(w, _route_from_track(track, slot + 1),
				_slot_pos(slot, _game.slots[slot]["ids"].find(id)), delay, Callable(), _couple.bind(w))
		else:
			_switch_lane = 0
			_roll(w, _route_from_track(track, 0), _buffer_pos(_game.buffer.find(id)), delay,
				Callable(), Callable())
	_sfx.play("pop" if boarded else "wait")
	# Enchaînement : les wagons en attente montent en cascade, un train complet part
	# dès que son dernier wagon est attelé.
	var next_start: float = CASCADE_GAP
	var last_arrival: float = ROLL_TIME + PAIR_GAP * (taken.size() - 1)
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
	_relayout(MOVE_TIME, taken)
	if _game.status() != Game.PLAYING:
		var gen: int = _gen
		get_tree().create_timer(maxf(next_start, last_arrival) + 0.5).timeout.connect(func() -> void:
			if gen == _gen:
				_finish())
	else:
		_check_dead_end()


## Arrivée d'un wagon « +1 » : il disparaît et laisse une place d'attente de plus.
func _become_place(node: Node2D, places: int) -> void:
	_buffer_view = maxi(_buffer_view, places)
	_sfx.play("star")
	Input.vibrate_handheld(25)
	queue_redraw()
	var tw: Tween = node.create_tween()
	tw.tween_property(node, "scale", Vector2(1.4, 1.4), 0.12)
	tw.parallel().tween_property(node, "modulate:a", 0.0, 0.12)
	tw.tween_callback(node.queue_free)


## Un wagon en attente rejoint son train après `delay` secondes.
## Chaque wagon de l'enchaînement sonne un peu plus aigu que le précédent.
func _schedule_load(step: Dictionary, delay: float, chain: int) -> void:
	var w: Node2D = _wagons[step["id"]]
	var slot: int = step["slot"]
	var target: Vector2 = _slot_pos(slot, _game.slots[slot]["ids"].size() - 1)
	_roll(w, _route_from_buffer(slot + 1), target, delay, func() -> void:
		_switch_lane = slot + 1
		queue_redraw()
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
			_show_overlay("Gare bloquée !", "Reprendre avant l'erreur", 0, "Recommencer le niveau")


## Vérifie en arrière-plan s'il reste une solution depuis la position actuelle. Si l'on est
## sûr que non, le panneau « Voie sans issue » s'affiche sans attendre le dernier coup possible.
func _check_dead_end() -> void:
	_check_seq += 1
	var seq: int = _check_seq
	var depth: int = _history.size()
	var snapshot: Game = _game.clone() as Game
	var thread: Thread = Thread.new()
	_checks.append(thread)
	thread.start(func() -> void:
		var r: Dictionary = Solver.solve(snapshot, CHECK_LIMIT)
		_on_checked.call_deferred(thread, seq, depth, bool(r["solvable"]), bool(r["aborted"])))


func _exit_tree() -> void:
	for thread: Thread in _checks:
		thread.wait_to_finish()
	_checks.clear()


func _on_checked(thread: Thread, seq: int, depth: int, solvable: bool, aborted: bool) -> void:
	thread.wait_to_finish()
	_checks.erase(thread)
	if seq != _check_seq:
		return
	if solvable:
		_safe_depth = depth
		return
	if aborted:
		return
	# Laisse le dernier wagon arriver avant d'annoncer la mauvaise nouvelle.
	get_tree().create_timer(0.7).timeout.connect(func() -> void:
		if seq == _check_seq and _game.status() == Game.PLAYING and not _overlay.visible:
			_sfx.play("lose")
			_show_overlay("Voie sans issue !", "Reprendre avant l'erreur", 0, "Recommencer le niveau"))


## Revient au dernier moment où le niveau était encore faisable.
func _rewind() -> void:
	if _history.is_empty():
		_sfx.play("nope")
		return
	var found: int = mini(_safe_depth, _history.size() - 1)
	# Les positions dont la vérification n'avait pas abouti sont réexaminées, de la plus récente
	# à la plus ancienne.
	for d: int in range(_history.size() - 1, found, -1):
		if Solver.solve(_history[d], CHECK_LIMIT)["solvable"]:
			found = d
			break
	_gen += 1
	_check_seq += 1
	_game = _history[found]
	_history.resize(found)
	_safe_depth = found
	_overlay.visible = false
	_rebuild()
	_sfx.play("undo")


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
	if _history.size() > _safe_depth:
		# Position pas encore reconnue comme faisable : on revérifie.
		_check_dead_end()
	else:
		_check_seq += 1


func _smoke() -> CPUParticles2D:
	var p: CPUParticles2D = CPUParticles2D.new()
	p.position = Vector2(35.0, -6.0)
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

## Dessine une image en 9 tranches dans `rect`. `margin` : taille des bords à l'écran
## (l'image est au double de cette taille).
func _nine(tex: Texture2D, rect: Rect2, margin: float) -> void:
	var src: Vector2 = tex.get_size()
	var dx: Array[float] = [rect.position.x, rect.position.x + margin, rect.end.x - margin, rect.end.x]
	var dy: Array[float] = [rect.position.y, rect.position.y + margin, rect.end.y - margin, rect.end.y]
	var sx: Array[float] = [0.0, margin * 2.0, src.x - margin * 2.0, src.x]
	var sy: Array[float] = [0.0, margin * 2.0, src.y - margin * 2.0, src.y]
	for i: int in 3:
		for j: int in 3:
			draw_texture_rect_region(tex, Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j]),
				Rect2(sx[i], sy[j], sx[i + 1] - sx[i], sy[j + 1] - sy[j]))


## Lit de la voie : une rainure dans le plateau, de la couleur des creux des voies.
func _bed(points: PackedVector2Array) -> void:
	# Bord haut sombre (ombre de la paroi), bord bas clair : la rainure paraît creusée.
	var up: PackedVector2Array = PackedVector2Array()
	var down: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in points:
		up.append(p + Vector2(0.0, -3.0))
		down.append(p + Vector2(0.0, 3.0))
	draw_polyline(down, TRAY.lightened(0.16), 60.0, true)
	draw_polyline(up, SLOT.darkened(0.55), 60.0, true)
	draw_polyline(points, SLOT, 58.0, true)


## Traverses le long d'une ligne, sur `max_length` pixels au plus (0 = toute la ligne).
func _ties(points: PackedVector2Array, max_length: float = 0.0) -> void:
	var curve: Curve2D = Curve2D.new()
	for p: Vector2 in points:
		curve.add_point(p)
	var length: float = curve.get_baked_length()
	if max_length > 0.0:
		length = minf(length, max_length)
	var tex: Texture2D = _tex["tie"]
	var at: float = 10.0
	while at < length:
		var here: Vector2 = curve.sample_baked(at)
		var ahead: Vector2 = curve.sample_baked(at + 2.0)
		draw_set_transform(here, (ahead - here).orthogonal().angle())
		draw_texture_rect(tex, Rect2(-25.0, -4.5, 50.0, 12.0), false)
		at += 22.0
	draw_set_transform(Vector2.ZERO, 0.0)


## Les deux rails d'une ligne : ombre, métal, reflet.
func _rails(points: PackedVector2Array) -> void:
	for side: float in [1.0, -1.0]:
		var rail: PackedVector2Array = PackedVector2Array()
		var shadow: PackedVector2Array = PackedVector2Array()
		var shine: PackedVector2Array = PackedVector2Array()
		for i: int in points.size():
			var dir: Vector2 = (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
			var p: Vector2 = points[i] + dir.orthogonal() * 18.0 * side
			rail.append(p)
			shadow.append(p + Vector2(0.0, 5.5))
			shine.append(p + Vector2(-0.8, -1.4))
		draw_polyline(shadow, Color(0.03, 0.01, 0.12, 0.5), 6.5, true)
		draw_polyline(rail, Color("b9b1ec"), 6.5, true)
		draw_polyline(shine, Color.WHITE, 2.2, true)


## Heurtoir en bout de voie.
func _bumper(center: Vector2, vertical_track: bool) -> void:
	draw_set_transform(center, 0.0 if vertical_track else PI / 2.0)
	draw_texture_rect(_tex["bumper"], Rect2(-29.0, -8.0, 58.0, 22.0), false)
	draw_set_transform(Vector2.ZERO, 0.0)


func _knob(at: Vector2) -> void:
	draw_texture_rect(_tex["knob"], Rect2(at - Vector2(13.0, 13.0), Vector2(26.0, 28.0)), false)


## Aiguillage : un bouton, et une lame dorée orientée vers `toward`.
func _switch(at: Vector2, toward: Vector2) -> void:
	var tip: Vector2 = at + toward.normalized() * 30.0
	draw_line(at + Vector2(0.0, 3.0), tip + Vector2(0.0, 3.0), Color(0.03, 0.01, 0.12, 0.5), 8.0, true)
	draw_line(at, tip, Color("e7a400"), 8.0, true)
	draw_line(at + Vector2(-1.0, -1.5), tip + Vector2(-1.0, -1.5), Color("fff0a8"), 3.0, true)
	_knob(at)


## Emplacement à remplir : un creux teinté, cerclé de la couleur attendue.
func _place(center: Vector2, color: Color) -> void:
	draw_texture_rect(_tex["socket"], Rect2(center - Vector2(34.0, 28.0), Vector2(68.0, 62.0)), false, color)


func _draw() -> void:
	if _game == null:
		return
	var sz: Vector2 = _size()
	var font: Font = ThemeDB.fallback_font
	var n: int = _game.tracks.size()
	var cy: float = _collector_y()
	var last_lane: int = _game.slots.size()
	var top: float = _track_rect(0).position.y
	var places: int = mini(_buffer_view, _game.buffer_size)
	var buffer_end: Vector2 = _buffer_pos(maxi(places, 1) - 1) + Vector2(50.0, 0.0)
	# Lignes du réseau. Chaque voie d'arrivée descend, rejoint la collectrice, puis
	# l'échelle (bord gauche) qui distribue la voie d'attente et les quais.
	# Plateau en relief qui porte toute la gare, puis le creux de chaque voie d'arrivée.
	var tray: Rect2 = Rect2(6.0, top - 34.0, sz.x - 12.0, _lane_y(last_lane) + 62.0 - (top - 34.0))
	_nine(_tex["tray"], Rect2(tray.position - Vector2(4.0, 4.0), tray.size + Vector2(8.0, 24.0)), 50.0)
	var arrivals: Array[PackedVector2Array] = []
	for t: int in n:
		_nine(_tex["slot"], _track_rect(t), 30.0)
		var route: Array[Vector2] = [Vector2(_track_x(t), top)]
		route.append_array(_route_from_track(t, last_lane))
		route.append(Vector2(sz.x + 40.0, _lane_y(last_lane)))
		arrivals.append(_rounded(route))
	var lanes: Array[PackedVector2Array] = []
	for lane: int in last_lane:
		var end: Vector2 = buffer_end if lane == 0 else Vector2(sz.x + 40.0, _lane_y(lane))
		lanes.append(_rounded([Vector2(LADDER_X, _lane_y(lane) - BEND), Vector2(LADDER_X, _lane_y(lane)), end]))
	# Les quais se prolongent à gauche : c'est par là qu'arrivent les locomotives.
	for lane: int in range(1, last_lane + 1):
		lanes.append(PackedVector2Array([Vector2(-40.0, _lane_y(lane)), Vector2(LADDER_X + BEND, _lane_y(lane))]))
	# Traverses d'abord, rails ensuite. La voie d'arrivée la plus à droite porte les
	# traverses de toute la ligne principale ; les autres s'arrêtent à la collectrice.
	for line: PackedVector2Array in arrivals:
		_bed(line)
	for line: PackedVector2Array in lanes:
		_bed(line)
	for t: int in n:
		_ties(arrivals[t], 0.0 if t == n - 1 else cy - top - BEND * 0.4)
	for line: PackedVector2Array in lanes:
		_ties(line)
	for line: PackedVector2Array in arrivals:
		_rails(line)
	for line: PackedVector2Array in lanes:
		_rails(line)
	# Heurtoirs : en haut des voies d'arrivée et au bout de la voie d'attente.
	for t: int in n:
		var unseen: int = _game.tracks[t].size() - TRACK_ROWS
		if unseen <= 0:
			_bumper(Vector2(_track_x(t), top + 6.0), true)
			continue
		# Voie plus longue que l'écran : une étiquette compte les wagons encore cachés.
		var tag: Rect2 = Rect2(_track_x(t) - 36.0, top - 12.0, 72.0, 38.0)
		draw_style_box(_box(INK, 14), tag)
		draw_style_box(_box(Color("5b3fd6"), 12), tag.grow(-3.0))
		draw_string_outline(font, Vector2(tag.position.x, tag.position.y + 28.0), "+%d" % unseen,
			HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 24, 6, INK)
		draw_string(font, Vector2(tag.position.x, tag.position.y + 28.0), "+%d" % unseen,
			HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 24, Color.WHITE)
	_bumper(buffer_end, false)
	# Aiguillages : entrée de chaque voie sur la collectrice, puis départs de l'échelle.
	for t: int in n - 1:
		var joint: Vector2 = Vector2(_track_x(t) - minf(BEND, (_track_x(t) - LADDER_X) / 2.0), cy)
		_knob(joint)
	for lane: int in last_lane:
		_switch(Vector2(LADDER_X, _lane_y(lane) - BEND),
			Vector2(0.45, 1.0) if _switch_lane == lane else Vector2(0.0, 1.0))
	# Voie d'attente : vire au rouge quand il ne reste qu'une place.
	var tight: bool = _game.buffer.size() >= _game.buffer_size - 1
	for b: int in places:
		_place(_buffer_pos(b), PALETTE[0] if tight else Color("b7adff"))
	# Quais de départ : emplacements à remplir derrière chaque locomotive.
	for s: int in _game.slots.size():
		if s >= _slot_view.size() or _slot_view[s]["color"] == -1:
			continue
		for k: int in int(_slot_view[s]["size"]):
			_place(_slot_pos(s, k), PALETTE[_slot_view[s]["color"]])
	# Voie de garage des locomotives à venir.
	var garage: PackedVector2Array = PackedVector2Array([Vector2(-40.0, _queue_y()), Vector2(sz.x + 40.0, _queue_y())])
	_bed(garage)
	_ties(garage)
	_rails(garage)


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
	# --naive=N : N coups « première voie jouable », pour provoquer une voie sans issue.
	for k: int in int(opts.get("naive", "0")):
		if _overlay.visible or _game.status() != Game.PLAYING:
			break
		for t: int in _game.tracks.size():
			if _game.can_take(t):
				_take(t)
				break
		await _wait(1.6)
	print("coups joués : %d, panneau : %s (%s)" % [_history.size(), _overlay.visible, _overlay_label.text])
	if opts.has("rewind"):
		await _wait(0.5)
		_rewind()
		print("après reprise : %d coups, faisable : %s" % [_history.size(), Solver.solve(_game)["solvable"]])
	if opts.has("map"):
		_open_map()
	for n: int in int(opts.get("undo", "0")):
		await _wait(0.4)
		_undo()
	if opts.has("shot"):
		await _wait(float(opts.get("wait", "2.5")))
		get_viewport().get_texture().get_image().save_png(opts["shot"])
		get_tree().quit()
