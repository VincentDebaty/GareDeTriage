extends Node2D
## Wagon ou locomotive (graphisme provisoire).

const SIZE := 64.0
const MYSTERY := Color("3d4055")

var color: Color = Color.WHITE
var is_loco: bool = false
## Wagon joker : blanc avec une étoile.
var is_joker: bool = false
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


func _draw() -> void:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = MYSTERY if masked else color
	box.set_corner_radius_all(12)
	box.set_border_width_all(3)
	box.border_color = box.bg_color.darkened(0.35)
	if not is_loco:
		draw_style_box(box, Rect2(-SIZE / 2.0, -SIZE / 2.0, SIZE, SIZE))
		# Roues, pour que le wagon se lise comme un wagon.
		draw_circle(Vector2(-18.0, SIZE / 2.0 - 2.0), 7.0, Color("2b2d42"))
		draw_circle(Vector2(18.0, SIZE / 2.0 - 2.0), 7.0, Color("2b2d42"))
		if is_joker:
			var star: PackedVector2Array = PackedVector2Array()
			for k: int in 10:
				star.append(Vector2(0.0, -2.0) + Vector2.from_angle(-PI / 2.0 + k * PI / 5.0) * (20.0 if k % 2 == 0 else 9.0))
			draw_colored_polygon(star, Color("f2b705"))
		if coupled:
			# Attelage : une plaque sombre à cheval sur les deux wagons.
			var plate: StyleBoxFlat = StyleBoxFlat.new()
			plate.bg_color = Color("2b2d42")
			plate.set_corner_radius_all(6)
			draw_style_box(plate, Rect2(-13.0, SIZE / 2.0 - 12.0, 26.0, 28.0))
			draw_circle(Vector2(0.0, SIZE / 2.0 + 2.0), 5.0, Color("f3ead7"))
		if masked:
			draw_string(ThemeDB.fallback_font, Vector2(-SIZE / 2.0, 15.0), "?",
				HORIZONTAL_ALIGNMENT_CENTER, SIZE, 42, Color.WHITE)
		return
	# Locomotive : corps allongé vers la droite, cabine sombre, cheminée et phare.
	draw_style_box(box, Rect2(-SIZE / 2.0, -SIZE / 2.0, SIZE + 26.0, SIZE))
	draw_rect(Rect2(-SIZE / 2.0 + 6.0, -SIZE / 2.0 + 6.0, 24.0, SIZE - 12.0), Color("2b2d42"))
	draw_circle(Vector2(26.0, 0.0), 12.0, Color("2b2d42"))
	draw_circle(Vector2(50.0, 0.0), 6.0, Color("fff3b0"))
	draw_circle(Vector2(-14.0, SIZE / 2.0 - 2.0), 8.0, Color("2b2d42"))
	draw_circle(Vector2(14.0, SIZE / 2.0 - 2.0), 8.0, Color("2b2d42"))
	draw_circle(Vector2(42.0, SIZE / 2.0 - 2.0), 8.0, Color("2b2d42"))
