extends RefCounted
## Marchandises : une par couleur de wagon, avec une icône dessinée (graphisme provisoire).
## L'icône double la couleur, pour que deux wagons se distinguent aussi par leur forme.

const NAMES: Array[String] = ["Briques", "Eau", "Blé", "Bois", "Raisin", "Fleurs"]


## Dessine l'icône de la marchandise `kind` centrée en `c`, à l'échelle `s` (1 = wagon).
## `ink` est la couleur du dessin, `paper` celle du fond (pour les détails en creux).
static func draw_icon(ci: CanvasItem, kind: int, c: Vector2, s: float, ink: Color, paper: Color) -> void:
	match kind:
		0:  # Briques : deux en bas, une au-dessus.
			for r: Array in [[-15.0, 1.0], [1.0, 1.0], [-7.0, -11.0]]:
				ci.draw_rect(Rect2(c + Vector2(r[0], r[1]) * s, Vector2(14.0, 10.0) * s), ink)
		1:  # Eau : une goutte.
			ci.draw_circle(c + Vector2(0.0, 5.0) * s, 10.0 * s, ink)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-9.0, 1.0) * s, c + Vector2(9.0, 1.0) * s, c + Vector2(0.0, -15.0) * s]), ink)
		2:  # Blé : un épi.
			ci.draw_line(c + Vector2(0.0, 15.0) * s, c + Vector2(0.0, -10.0) * s, ink, 3.0 * s)
			for y: float in [-7.0, 1.0, 9.0]:
				ci.draw_circle(c + Vector2(-6.0, y) * s, 4.5 * s, ink)
				ci.draw_circle(c + Vector2(6.0, y) * s, 4.5 * s, ink)
			ci.draw_circle(c + Vector2(0.0, -13.0) * s, 4.5 * s, ink)
		3:  # Bois : trois rondins vus en bout.
			for p: Vector2 in [Vector2(-9.0, 6.0), Vector2(9.0, 6.0), Vector2(0.0, -8.0)]:
				ci.draw_circle(c + p * s, 8.5 * s, ink)
				ci.draw_circle(c + p * s, 3.5 * s, paper)
		4:  # Raisin : une grappe.
			for p: Vector2 in [Vector2(-9.0, -7.0), Vector2(0.0, -7.0), Vector2(9.0, -7.0),
					Vector2(-4.5, 2.0), Vector2(4.5, 2.0), Vector2(0.0, 11.0)]:
				ci.draw_circle(c + p * s, 5.5 * s, ink)
			ci.draw_line(c + Vector2(0.0, -11.0) * s, c + Vector2(4.0, -17.0) * s, ink, 3.0 * s)
		5:  # Fleurs : cinq pétales et un cœur.
			for k: int in 5:
				ci.draw_circle(c + Vector2.from_angle(-PI / 2.0 + k * TAU / 5.0) * 9.0 * s, 6.5 * s, ink)
			ci.draw_circle(c, 4.0 * s, paper)
