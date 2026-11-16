extends Node2D
## Wagon ou locomotive (graphisme provisoire).

const SIZE := 64.0
const MYSTERY := Color("3d4055")

var color: Color = Color.WHITE
var is_loco: bool = false
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
