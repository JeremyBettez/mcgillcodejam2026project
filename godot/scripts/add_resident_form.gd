class_name AddResidentForm
extends Control
## "Add a friend" / "Add a location" card: photo (camera or library), name,
## (for places) an optional flag, Generate. `open("friend")` or `open("place")`.
## The photo stays in memory only; it is handed out with `submitted` and then dropped.

signal submitted(display_name: String, jpeg: PackedByteArray)
signal closed

const TEXTS := {
	"friend": {"heading": "Add a friend", "tip": "Full body in the photo: head to feet, facing the camera, arms a little away from the body.", "placeholder": "Their name", "button": "Tap to enter their name", "prompt": "Their name"},
	"place": {"heading": "Add a location", "tip": "Photo of the building or place from the front, with the whole thing in view.", "placeholder": "Place name", "button": "Tap to enter the place's name", "prompt": "Place name"},
}

## "friend" or "place" (read by whoever handles `submitted`).
var mode := "friend"

var bridge: PhotoBridge

var _jpeg := PackedByteArray()
var _card: PanelContainer
var _preview: TextureRect
var _preview_hint: Label
var _name_edit: LineEdit # holds the name on every platform (hidden on web)
var _name_button: Button # web only: opens the browser prompt
var _status: Label
var _generate: Button
var _camera_button: Button
var _library_button: Button
var _heading: Label
var _tip: Label
var _flag_check: CheckBox
var _detailed_check: CheckBox


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP # taps on the form never reach the world
	visible = false

	bridge = PhotoBridge.new()
	add_child(bridge)
	bridge.photo_ready.connect(_on_photo_ready)
	bridge.photo_failed.connect(_on_photo_failed)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	_card = card
	card.custom_minimum_size = Vector2(500.0, 0.0)
	card.add_theme_stylebox_override("panel", UiStyle.bubble())
	center.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)

	_heading = _label("", 28)
	_heading.add_theme_font_override("font", UiStyle.bold())
	box.add_child(_heading)
	_tip = _label("", 16)
	_tip.add_theme_color_override("font_color", UiStyle.BROWN_SOFT)
	box.add_child(_tip)

	var preview_frame := PanelContainer.new()
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = UiStyle.CREAM_DARK
	frame_style.set_corner_radius_all(22)
	frame_style.set_border_width_all(3)
	frame_style.border_color = UiStyle.TAN
	frame_style.anti_aliasing = true
	preview_frame.add_theme_stylebox_override("panel", frame_style)
	preview_frame.custom_minimum_size = Vector2(0.0, 280.0)
	box.add_child(preview_frame)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_frame.add_child(_preview)
	_preview_hint = _label("No photo yet", 18)
	_preview_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview_hint.add_theme_color_override("font_color", UiStyle.BROWN_SOFT)
	preview_frame.add_child(_preview_hint)

	var photo_row := HBoxContainer.new()
	photo_row.add_theme_constant_override("separation", 10)
	box.add_child(photo_row)
	_camera_button = _button("Take photo", photo_row)
	_camera_button.pressed.connect(_pick.bind("camera"))
	_library_button = _button("Choose photo", photo_row)
	_library_button.pressed.connect(_pick.bind("library"))

	# Name: a text field on desktop. On phones Godot's text field and on-screen
	# keyboard are unreliable, so a button opens the browser's own name prompt.
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Their name"
	_name_edit.max_length = 40
	_name_edit.custom_minimum_size = Vector2(0.0, 52.0)
	_name_edit.add_theme_font_size_override("font_size", 20)
	_name_edit.text_changed.connect(func(_t: String) -> void: _refresh())
	box.add_child(_name_edit)
	_name_button = _button("", box)
	_name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name_button.pressed.connect(_on_name_button)
	var on_web := OS.has_feature("web")
	_name_edit.visible = not on_web
	_name_button.visible = on_web


	# Places only: fly a flag (its known flag, or one in colours from the photo).
	_flag_check = CheckBox.new()
	_flag_check.text = "Add a flag in its colors"
	_flag_check.focus_mode = Control.FOCUS_NONE
	_flag_check.add_theme_font_size_override("font_size", 18)
	box.add_child(_flag_check)
	# Places only: Quick build (low-poly, built in code from what Claude sees in
	# the photo, ~20 s) is the default; Detailed 3D asks TRELLIS for a full mesh.
	_detailed_check = CheckBox.new()
	_detailed_check.text = "Detailed 3D scan (slower, 1-3 min)"
	_detailed_check.focus_mode = Control.FOCUS_NONE
	_detailed_check.add_theme_font_size_override("font_size", 18)
	box.add_child(_detailed_check)

	_status = _label("", 16)
	_status.add_theme_color_override("font_color", Color(0.85, 0.3, 0.25))
	_status.visible = false
	box.add_child(_status)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	box.add_child(actions)
	var cancel := _button("Cancel", actions)
	cancel.pressed.connect(close)
	_generate = _button("Generate", actions)
	_generate.pressed.connect(_on_generate)
	# Main action: a green pill with white text.
	_generate.add_theme_stylebox_override("normal", UiStyle.pill(UiStyle.LEAF, 4, UiStyle.LEAF_DARK))
	_generate.add_theme_stylebox_override("hover", UiStyle.pill(UiStyle.LEAF.lightened(0.08), 4, UiStyle.LEAF_DARK))
	_generate.add_theme_stylebox_override("pressed", UiStyle.pill(UiStyle.LEAF_DARK, 1, UiStyle.LEAF_DARK))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		_generate.add_theme_color_override(state, Color.WHITE)

	if not bridge.is_available():
		_camera_button.disabled = true
		_library_button.disabled = true
		_show_status("Photo input isn't available in this browser.")
	_refresh()


func open(form_mode := "friend") -> void:
	mode = form_mode if TEXTS.has(form_mode) else "friend"
	var t: Dictionary = TEXTS[mode]
	_heading.text = t.heading
	_tip.text = t.tip
	_name_edit.placeholder_text = t.placeholder
	_flag_check.visible = mode == "place"
	_flag_check.button_pressed = false
	_detailed_check.visible = mode == "place"
	_detailed_check.button_pressed = false
	_reset()
	visible = true
	UiFx.pop_in(_card, 0.0, 0.8)


func close() -> void:
	_reset() # drop the photo from memory
	visible = false
	closed.emit()


func _reset() -> void:
	_jpeg = PackedByteArray()
	_preview.texture = null
	_preview_hint.text = "No photo yet"
	_preview_hint.visible = true
	_set_name("")
	_show_status("")
	_refresh()


func _pick(source: String) -> void:
	_show_status("")
	_preview_hint.text = "Opening camera..." if source == "camera" else "Opening photos..."
	bridge.pick(source)


func _on_photo_ready(jpeg: PackedByteArray, texture: ImageTexture) -> void:
	_jpeg = jpeg
	_preview.texture = texture
	_preview_hint.visible = false
	_show_status("")
	_refresh()


func _on_photo_failed(message: String) -> void:
	_preview_hint.text = "No photo yet" if _jpeg.is_empty() else ""
	_show_status(message) # empty when the player just cancelled


func _on_name_button() -> void:
	var value: Variant = bridge.ask_name(_name_edit.text, str(TEXTS[mode].prompt))
	if value is String:
		_set_name(value)


func _set_name(value: String) -> void:
	_name_edit.text = value
	_name_button.text = value if not value.is_empty() else str(TEXTS[mode].button)
	# A place with a known flag (e.g. McGill) gets it ticked automatically.
	if mode == "place":
		var known := Flag.design_for_name(value) != null
		_flag_check.text = "Add its flag" if known else "Add a flag in its colors"
		if known:
			_flag_check.button_pressed = true
	_refresh()


func _on_generate() -> void:
	var display_name := _name_edit.text.strip_edges()
	if _jpeg.is_empty() or display_name.is_empty():
		return
	var jpeg := _jpeg
	submitted.emit(display_name, jpeg)
	close()


## For places: true = Detailed 3D (TRELLIS mesh), false = Quick build (recipe).
func wants_detailed() -> bool:
	return mode == "place" and _detailed_check.button_pressed


## For places: whether to fly a flag.
func wants_flag() -> bool:
	return mode == "place" and _flag_check.button_pressed


func _refresh() -> void:
	_generate.disabled = _jpeg.is_empty() or _name_edit.text.strip_edges().is_empty()


func _show_status(message: String) -> void:
	_status.text = message
	_status.visible = not message.is_empty()


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	return label


func _button(text: String, parent: Control) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, 56.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 20)
	UiFx.add_press_bounce(button)
	parent.add_child(button)
	return button
