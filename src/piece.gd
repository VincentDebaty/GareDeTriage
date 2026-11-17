extends Node2D
## Wagon ou locomotive, vu du dessus. L'image (assets/pieces, générée par
## tools/gen_sprites.py) regarde vers la droite ; `heading` la fait pivoter le long des rails.
## L'épaisseur et l'ombre sont dessinées ici, toujours vers le bas de l'écran, quelle que
## soit l'orientation. Les marquages (« +1 », « ? ») restent droits.

const SIZE := 64.0
const DARK := Color("1b1642")
## Hauteur apparente de la pièce et décalage de son ombre, en pixels d'écran.
const DEPTH := 6.0
const SHADOW := 11.0

## Couleur du jeu (index de palette).
var kind: int = 0
var color: Color = Color.WHITE
var is_loco: bool = false
## Wagon « +1 » : blanc, il devient une place d'attente supplémentaire.
var is_bonus: bool = false
## Direction dans laquelle la pièce regarde, en radians (0 = vers la droite).
var heading: float = 0.0:
	set(value):
		heading = value
		rotation = value
		queue_redraw()
## Chiffre écrit sur la pièce (longueur du train, pour une locomotive en attente).
var label: String = "":
	set(value):
		label = value
		queue_redraw()
## Wagon attelé à celui qui le précède sur sa voie (donc devant lui).
var coupled: bool = false:
	set(value):
		coupled = value
		queue_redraw()
## Wagon mystère : couleur masquée par un « ? ».
var masked: bool = false:
	set(value):
		masked = value
		queue_redraw()

## Image de la pièce, gardée en mémoire : une texture chargée puis relâchée pendant
## `_draw` serait libérée avant le rendu.
var _tex: Texture2D


func _texture() -> Texture2D:
	if _tex == null:
		if is_bonus:
			_tex = load("res://assets/pieces/wagon_bonus.svg")
		else:
			_tex = load("res://assets/pieces/%s_%d.svg" % ["loco" if is_loco else "wagon", kind])
	return _tex


func _draw() -> void:
	var tex: Texture2D = _texture()
	# Les images sont au double de leur taille à l'écran ; le centre de la pièce est au
	# centre de l'image pour un wagon, vers l'arrière pour une locomotive.
	var rect: Rect2 = Rect2(Vector2(-37.0 if is_loco else -36.0, -32.0), tex.get_size() / 2.0)
	var tint: Color = Color(0.32, 0.32, 0.42) if masked else Color.WHITE
	# Ombre puis tranche : la même silhouette, décalée vers le bas de l'écran.
	draw_set_transform(Vector2(0.0, SHADOW).rotated(-rotation), 0.0)
	draw_texture_rect(tex, rect, false, Color(0.02, 0.0, 0.1, 0.30))
	draw_set_transform(Vector2(0.0, DEPTH).rotated(-rotation), 0.0)
	draw_texture_rect(tex, rect, false, Color(0.34, 0.31, 0.46))
	draw_set_transform(Vector2.ZERO, 0.0)
	draw_texture_rect(tex, rect, false, tint)
	if label != "":
		# Chiffre droit, au milieu de la pièce.
		draw_set_transform(Vector2(12.0 if is_loco else 0.0, 0.0), -rotation)
		draw_string_outline(ThemeDB.fallback_font, Vector2(-30.0, 14.0), label,
			HORIZONTAL_ALIGNMENT_CENTER, 60.0, 40, 12, DARK)
		draw_string(ThemeDB.fallback_font, Vector2(-30.0, 14.0), label,
			HORIZONTAL_ALIGNMENT_CENTER, 60.0, 40, Color.WHITE)
		draw_set_transform(Vector2.ZERO, 0.0)
	if is_loco:
		return
	if coupled:
		# Attelage : une plaque sombre à cheval sur ce wagon et celui qui le précède.
		var plate: StyleBoxFlat = StyleBoxFlat.new()
		plate.bg_color = DARK
		plate.set_corner_radius_all(6)
		draw_style_box(plate, Rect2(SIZE / 2.0 - 12.0, -13.0, 28.0, 26.0))
		draw_circle(Vector2(SIZE / 2.0 + 2.0, 0.0), 5.0, Color("f4f0ff"))
	# Les marquages restent droits, quelle que soit l'orientation du wagon.
	draw_set_transform(Vector2.ZERO, -rotation)
	if is_bonus:
		draw_string_outline(ThemeDB.fallback_font, Vector2(-SIZE / 2.0, 12.0), "+1",
			HORIZONTAL_ALIGNMENT_CENTER, SIZE, 32, 8, Color.WHITE)
		draw_string(ThemeDB.fallback_font, Vector2(-SIZE / 2.0, 12.0), "+1",
			HORIZONTAL_ALIGNMENT_CENTER, SIZE, 32, Color("5b3fd6"))
	if masked:
		draw_string(ThemeDB.fallback_font, Vector2(-SIZE / 2.0, 15.0), "?",
			HORIZONTAL_ALIGNMENT_CENTER, SIZE, 42, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0)
