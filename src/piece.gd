extends Node2D
## Wagon ou locomotive (graphisme provisoire).

const SIZE := 64.0
const MYSTERY := Color("3d4055")
const Goods := preload("res://src/goods.gd")

var color: Color = Color.WHITE
var is_loco: bool = false
## Marchandise transportée (index de couleur), -1 pour aucune icône.
var kind: int = -1
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
		if not masked and kind >= 0:
			Goods.draw_icon(self, kind, Vector2(0.0, -3.0), 1.0, color.darkened(0.5), color)
		if masked:
			draw_string(ThemeDB.fallback_font, Vector2(-SIZE / 2.0, 15.0), "?",
				HORIZONTAL_ALIGNMENT_CENTER, SIZE, 42, Color.WHITE)
		return
	# Locomotive : corps allongé vers la droite, cabine sombre, cheminée et phare.
	draw_style_box(box, Rect2(-SIZE / 2.0, -SIZE / 2.0, SIZE + 26.0, SIZE))
	draw_rect(Rect2(-SIZE / 2.0 + 6.0, -SIZE / 2.0 + 6.0, 24.0, SIZE - 12.0), Color("2b2d42"))
	draw_circle(Vector2(26.0, 0.0), 12.0, Color("2b2d42"))
	if kind >= 0:
		# La cabine porte l'icône de la marchandise attendue.
		Goods.draw_icon(self, kind, Vector2(-14.0, 0.0), 0.6, Color.WHITE, Color("2b2d42"))
	draw_circle(Vector2(50.0, 0.0), 6.0, Color("fff3b0"))
	draw_circle(Vector2(-14.0, SIZE / 2.0 - 2.0), 8.0, Color("2b2d42"))
	draw_circle(Vector2(14.0, SIZE / 2.0 - 2.0), 8.0, Color("2b2d42"))
	draw_circle(Vector2(42.0, SIZE / 2.0 - 2.0), 8.0, Color("2b2d42"))
