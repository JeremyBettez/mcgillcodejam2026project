class_name RoundIconButton
extends Button
## Round, thumb-sized button with a vector icon drawn in code (no image or emoji
## assets, so it looks the same on every phone browser).

enum Icon { PAUSE, PLAY, FRIENDS, CAMERA, HOME, CLOSE }

var icon_kind := Icon.FRIENDS:
	set(value):
		icon_kind = value
		queue_redraw()
var fill_color := Color(0.12, 0.6, 0.58)
var glyph_color := Color.WHITE
var ring_color := Color.WHITE


func _init(kind := Icon.FRIENDS, diameter := 72.0, fill := Color(0.12, 0.6, 0.58), glyph := Color.WHITE) -> void:
	icon_kind = kind
	fill_color = fill
	glyph_color = glyph
	text = ""
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(diameter, diameter)
	for style in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(style, StyleBoxEmpty.new())
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 2.0
	var is_down := get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED
	r *= 0.94 if is_down else 1.0
	draw_circle(c + Vector2(0.0, 3.0), r, Color(0.0, 0.0, 0.0, 0.18)) # soft shadow
	draw_circle(c, r, ring_color)
	draw_circle(c, r - maxf(3.0, r * 0.08), fill_color.darkened(0.15) if is_down else fill_color)
	var s := r * 0.62 # icon scale
	match icon_kind:
		Icon.PAUSE:
			draw_rect(Rect2(c + Vector2(-0.42, -0.5) * s, Vector2(0.28, 1.0) * s), glyph_color)
			draw_rect(Rect2(c + Vector2(0.14, -0.5) * s, Vector2(0.28, 1.0) * s), glyph_color)
		Icon.PLAY:
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.32, -0.55) * s, c + Vector2(-0.32, 0.55) * s, c + Vector2(0.55, 0.0) * s]), glyph_color)
		Icon.FRIENDS:
			# Two people: one behind (lighter), one in front.
			var back := glyph_color.lerp(fill_color, 0.45)
			_person(c + Vector2(0.38, -0.12) * s, 0.78 * s, back)
			_person(c + Vector2(-0.22, 0.05) * s, 1.0 * s, glyph_color)
		Icon.CAMERA:
			draw_rect(Rect2(c + Vector2(-0.3, -0.62) * s, Vector2(0.6, 0.2) * s), glyph_color)
			_round_rect(Rect2(c + Vector2(-0.8, -0.45) * s, Vector2(1.6, 1.05) * s), 0.18 * s, glyph_color)
			draw_circle(c + Vector2(0.0, 0.08) * s, 0.36 * s, fill_color)
			draw_circle(c + Vector2(0.0, 0.08) * s, 0.22 * s, glyph_color)
			draw_circle(c + Vector2(0.55, -0.25) * s, 0.08 * s, fill_color)
		Icon.HOME:
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-0.75, -0.05) * s, c + Vector2(0.0, -0.72) * s, c + Vector2(0.75, -0.05) * s]), glyph_color)
			draw_rect(Rect2(c + Vector2(-0.52, -0.08) * s, Vector2(1.04, 0.72) * s), glyph_color)
			draw_rect(Rect2(c + Vector2(-0.14, 0.22) * s, Vector2(0.28, 0.42) * s), fill_color)
		Icon.CLOSE:
			draw_line(c + Vector2(-0.45, -0.45) * s, c + Vector2(0.45, 0.45) * s, glyph_color, 0.2 * s, true)
			draw_line(c + Vector2(0.45, -0.45) * s, c + Vector2(-0.45, 0.45) * s, glyph_color, 0.2 * s, true)


## A head and rounded shoulders; `at` is the head centre, `k` the person's size.
func _person(at: Vector2, k: float, color: Color) -> void:
	draw_circle(at, 0.3 * k, color)
	var shoulders := PackedVector2Array()
	var base := at + Vector2(0.0, 0.95 * k)
	for i in 17:
		var a := PI + PI * i / 16.0
		shoulders.append(base + Vector2(cos(a) * 0.55 * k, sin(a) * 0.5 * k))
	draw_colored_polygon(shoulders, color)


func _round_rect(rect: Rect2, radius: float, color: Color) -> void:
	draw_rect(rect.grow_individual(-radius, 0.0, -radius, 0.0), color)
	draw_rect(rect.grow_individual(0.0, -radius, 0.0, -radius), color)
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var inset: Vector2 = corner + Vector2(radius if corner.x == rect.position.x else -radius, radius if corner.y == rect.position.y else -radius)
		draw_circle(inset, radius, color)
