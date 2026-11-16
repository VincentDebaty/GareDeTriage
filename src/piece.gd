extends Node2D
## Wagon ou locomotive (graphisme provisoire).

const SIZE := 64.0

var color: Color = Color.WHITE
var is_loco: bool = false


func _draw() -> void:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(12)
	box.set_border_width_all(3)
	box.border_color = color.darkened(0.35)
	if not is_loco:
		draw_style_box(box, Rect2(-SIZE / 2.0, -SIZE / 2.0, SIZE, SIZE))
		return
	# Locomotive : corps allongé vers la droite, cabine sombre, cheminée et phare.
	draw_style_box(box, Rect2(-SIZE / 2.0, -SIZE / 2.0, SIZE + 26.0, SIZE))
	draw_rect(Rect2(-SIZE / 2.0 + 6.0, -SIZE / 2.0 + 6.0, 24.0, SIZE - 12.0), Color("2b2d42"))
	draw_circle(Vector2(26.0, 0.0), 12.0, Color("2b2d42"))
	draw_circle(Vector2(50.0, 0.0), 6.0, Color("fff3b0"))
