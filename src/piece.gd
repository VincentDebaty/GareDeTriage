extends Node2D
## Wagon ou locomotive. L'image vient de assets/pieces (générées par tools/gen_sprites.py) ;
## seuls les marquages (« +1 », attelage, « ? ») sont dessinés par le code.

const SIZE := 64.0
const DARK := Color("1b1642")
## Les images sont dessinées au double de leur taille à l'écran ; le centre du wagon
## (origine du nœud) se trouve à (42, 36) dans l'image ramenée à l'échelle de l'écran.
const ORIGIN := Vector2(42.0, 36.0)

## Couleur du jeu (index de palette).
var kind: int = 0
var color: Color = Color.WHITE
var is_loco: bool = false
## Wagon « +1 » : blanc, il devient une place d'attente supplémentaire.
var is_bonus: bool = false
## Wagon attelé à celui qui le précède (dessiné juste en dessous sur la voie).
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
	draw_texture_rect(tex, Rect2(-ORIGIN, tex.get_size() / 2.0), false,
		Color(0.32, 0.32, 0.42) if masked else Color.WHITE)
	if is_loco:
		return
	if is_bonus:
		draw_string_outline(ThemeDB.fallback_font, Vector2(-SIZE / 2.0, 12.0), "+1",
			HORIZONTAL_ALIGNMENT_CENTER, SIZE, 34, 8, Color.WHITE)
		draw_string(ThemeDB.fallback_font, Vector2(-SIZE / 2.0, 12.0), "+1",
			HORIZONTAL_ALIGNMENT_CENTER, SIZE, 34, Color("5b3fd6"))
	if coupled:
		# Attelage : une plaque sombre à cheval sur les deux wagons.
		var plate: StyleBoxFlat = StyleBoxFlat.new()
		plate.bg_color = DARK
		plate.set_corner_radius_all(6)
		draw_style_box(plate, Rect2(-13.0, SIZE / 2.0 - 10.0, 26.0, 28.0))
		draw_circle(Vector2(0.0, SIZE / 2.0 + 4.0), 5.0, Color("f4f0ff"))
	if masked:
		draw_string(ThemeDB.fallback_font, Vector2(-SIZE / 2.0, 15.0), "?",
			HORIZONTAL_ALIGNMENT_CENTER, SIZE, 42, Color.WHITE)
