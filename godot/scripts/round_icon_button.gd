class_name RoundIconButton
extends Button
## Round, thumb-sized button with a vector icon drawn in code (no image or emoji
## assets, so it looks the same on every phone browser).

enum Icon { PAUSE, PLAY, FRIENDS, CAMERA, HOME, CLOSE }

const PULSE_PERIOD := 2.2 # seconds between invite pulses

var icon_kind := Icon.FRIENDS:
	set(value):
		if value != icon_kind and is_inside_tree():
			_spin_icon() # little twist when the icon changes (e.g. Pause <-> Play)
		icon_kind = value
		queue_redraw()
var fill_color := Color(0.12, 0.6, 0.58)
var glyph_color := Color.WHITE
var ring_color := Color.WHITE
## Draw a soft expanding ring every couple of seconds to invite a tap.
var pulse := false:
	set(value):
		pulse = value
		set_process(value)
		queue_redraw()

var _pulse_time := 0.0
var _icon_turn := 0.0 # radians, animated on icon change


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
	process_mode = Node.PROCESS_MODE_ALWAYS # keep animating while the game is paused
	set_process(false)
	UiFx.add_press_bounce(self)


func _process(delta: float) -> void:
	_pulse_time = fmod(_pulse_time + delta, PULSE_PERIOD)
	queue_redraw()


func _spin_icon() -> void:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_icon_turn = -PI * 0.5
	tween.tween_property(self, "_icon_turn", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_method(func(_v: float) -> void: queue_redraw(), 0.0, 1.0, 0.3)


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 2.0
	var is_down := get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED
	if pulse:
		# Expanding, fading ring around the button.
		var k := _pulse_time / PULSE_PERIOD
		if k < 0.6:
			var p := k / 0.6
			draw_arc(c, r + 4.0 + p * 18.0, 0.0, TAU, 48, Color(fill_color, 0.55 * (1.0 - p)), 4.0 * (1.0 - p) + 1.0, true)
	r *= 0.94 if is_down else 1.0
	draw_circle(c + Vector2(0.0, 3.0), r, Color(0.0, 0.0, 0.0, 0.18)) # soft shadow
	draw_circle(c, r, ring_color)
	draw_circle(c, r - maxf(3.0, r * 0.08), fill_color.darkened(0.15) if is_down else fill_color)
	if _icon_turn != 0.0:
		draw_set_transform(c, _icon_turn, Vector2.ONE)
		c = Vector2.ZERO
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
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
