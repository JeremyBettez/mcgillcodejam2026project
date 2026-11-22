class_name UiStyle
extends RefCounted
## Painted fall look (matches the goose mascot art): warm paper speech-bubble
## panels with plum-brown text, terracotta borders and warm shadows, pill-shaped buttons and a
## soft pastel palette. Applied once to the whole window (`apply`), so every
## Control inherits it; a few helpers return styleboxes for custom panels.
##
## Font: Grandstander (SIL Open Font License), godot/fonts/Grandstander.ttf +
## Grandstander-OFL.txt. Bouncy hand-drawn letters to match the painted art.

const FONT_PATH := "res://fonts/Grandstander.ttf"

# Palette: a rich fall take on the painted mascot art (oil-pastel strokes):
# burnt orange, maple crimson, mustard gold and a cool teal on warm paper.
# Names are kept from the first cozy palette so existing code keeps working.
const CREAM := Color(1.0, 0.957, 0.90)        # panels: warm paper
const CREAM_DARK := Color(0.97, 0.89, 0.78)   # pressed / insets
const TAN := Color(0.88, 0.64, 0.46)          # borders: soft terracotta
const BROWN := Color(0.30, 0.15, 0.17)        # text: deep plum brown
const BROWN_SOFT := Color(0.56, 0.38, 0.36)   # secondary text
const LEAF := Color(0.89, 0.46, 0.18)         # main accent / title sign: burnt orange
const LEAF_DARK := Color(0.68, 0.30, 0.12)
const SKY := Color(0.18, 0.53, 0.55)          # locations: teal
const ORANGE := Color(0.80, 0.23, 0.25)       # add a friend: maple crimson
const YELLOW := Color(0.96, 0.73, 0.25)       # mustard highlights
const SHADOW := Color(0.36, 0.16, 0.10, 0.24)  # warm brown shadow


static var _font: Font
static var _bold: Font


static func font() -> Font:
	if _font == null:
		_font = _variation(500)
	return _font


static func bold() -> Font:
	if _bold == null:
		_bold = _variation(700)
	return _bold


static func _variation(weight: int) -> Font:
	var base: Variant = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else null
	if not base is Font:
		return ThemeDB.fallback_font # font missing: keep Godot's default, never crash
	var variation := FontVariation.new()
	variation.base_font = base
	# OpenType variation axes are keyed by tag id (TextServer.name_to_tag), not by name.
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	variation.variation_opentype = {wght: weight}
	return variation


static var _theme: Theme


static func theme() -> Theme:
	if _theme == null:
		_theme = build_theme()
	return _theme


## Install the theme on the whole window.
static func apply(window: Window) -> void:
	window.theme = theme()


## Controls under a CanvasLayer don't inherit the window's theme, so give every
## top-level Control of every CanvasLayer below `root` the theme directly.
static func apply_to_layers(root: Node) -> void:
	for layer in root.find_children("*", "CanvasLayer", true, false):
		for child in layer.get_children():
			if child is Control:
				(child as Control).theme = theme()


static func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = font()
	theme.default_font_size = 20

	theme.set_color("font_color", "Label", BROWN)

	# Pill buttons: cream with a tan rim and a soft drop shadow.
	theme.set_stylebox("normal", "Button", pill(CREAM))
	theme.set_stylebox("hover", "Button", pill(Color(1.0, 0.985, 0.93)))
	theme.set_stylebox("pressed", "Button", pill(CREAM_DARK, 1))
	theme.set_stylebox("hover_pressed", "Button", pill(CREAM_DARK, 1))
	theme.set_stylebox("disabled", "Button", pill(Color(CREAM, 0.6), 0))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(state, "Button", BROWN)
	theme.set_color("font_disabled_color", "Button", Color(BROWN_SOFT, 0.6))
	theme.set_font("font", "Button", bold())

	theme.set_stylebox("panel", "PanelContainer", bubble())

	var field := pill(Color(1, 1, 1), 2)
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", pill(Color(1, 1, 1), 2, LEAF))
	theme.set_color("font_color", "LineEdit", BROWN)
	theme.set_color("font_placeholder_color", "LineEdit", Color(BROWN_SOFT, 0.7))
	theme.set_color("caret_color", "LineEdit", BROWN)

	theme.set_color("font_color", "CheckBox", BROWN)
	theme.set_stylebox("normal", "CheckBox", StyleBoxEmpty.new())
	return theme


## Big rounded speech-bubble panel (lists, friend bar, cards).
static func bubble(fill := CREAM) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(30)
	box.set_border_width_all(4)
	box.border_color = TAN
	box.shadow_color = SHADOW
	box.shadow_size = 8
	box.shadow_offset = Vector2(0, 6)
	box.set_content_margin_all(18)
	box.anti_aliasing = true
	return box


## Pill-shaped button background. `lift` = shadow depth (0 when pressed in).
static func pill(fill: Color, lift := 4, rim := TAN) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(999)
	box.set_border_width_all(3)
	box.border_color = rim
	box.shadow_color = SHADOW
	box.shadow_size = 0
	box.shadow_offset = Vector2(0, lift)
	if lift > 0:
		box.shadow_size = 1
	box.set_content_margin_all(10)
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.anti_aliasing = true
	return box


## Small solid sign (e.g. the "Photo Town" title) with white text.
static func title_sign(fill := LEAF) -> StyleBoxFlat:
	var box := pill(fill, 4, Color(1, 1, 1, 0.9))
	box.set_border_width_all(4)
	box.content_margin_left = 22
	box.content_margin_right = 22
	box.content_margin_top = 6
	box.content_margin_bottom = 8
	return box
