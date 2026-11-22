class_name AddResidentForm
extends Control
## "Add a resident" card: photo (camera or library), name, consent, Generate.
## The photo stays in memory only; it is handed out with `submitted` and then dropped.

signal submitted(display_name: String, jpeg: PackedByteArray)
signal closed

const CONSENT_TEXT := "I have this person's permission"
const NAME_PLACEHOLDER := "Tap to enter their name"
const PRIVACY_TEXT := "The photo is sent to Hugging Face to build the 3D model. It is not saved in the game."

var bridge: PhotoBridge

var _jpeg := PackedByteArray()
var _preview: TextureRect
var _preview_hint: Label
var _name_edit: LineEdit # holds the name on every platform (hidden on web)
var _name_button: Button # web only: opens the browser prompt
var _consent: CheckBox
var _status: Label
var _generate: Button
var _camera_button: Button
var _library_button: Button


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
	card.custom_minimum_size = Vector2(500.0, 0.0)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.13, 0.15, 0.19)
	card_style.set_corner_radius_all(14)
	card_style.set_content_margin_all(18)
	card.add_theme_stylebox_override("panel", card_style)
	center.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)

	box.add_child(_label("Add a resident", 28))
	var tip := _label("Full body in the photo: head to feet, facing the camera, arms a little away from the body.", 16)
	tip.modulate = Color(0.8, 0.85, 0.9)
	box.add_child(tip)

	var preview_frame := PanelContainer.new()
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.08, 0.09, 0.11)
	frame_style.set_corner_radius_all(10)
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
	_preview_hint.modulate = Color(0.6, 0.65, 0.7)
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
	_name_button = _button(NAME_PLACEHOLDER, box)
	_name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name_button.pressed.connect(_on_name_button)
	var on_web := OS.has_feature("web")
	_name_edit.visible = not on_web
	_name_button.visible = on_web

	_consent = CheckBox.new()
	_consent.text = CONSENT_TEXT
	_consent.add_theme_font_size_override("font_size", 18)
	_consent.focus_mode = Control.FOCUS_NONE
	_consent.toggled.connect(func(_on: bool) -> void: _refresh())
	box.add_child(_consent)
	var privacy := _label(PRIVACY_TEXT, 15)
	privacy.modulate = Color(0.8, 0.85, 0.9)
	box.add_child(privacy)

	_status = _label("", 16)
	_status.modulate = Color(1.0, 0.6, 0.55)
	_status.visible = false
	box.add_child(_status)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	box.add_child(actions)
	var cancel := _button("Cancel", actions)
	cancel.pressed.connect(close)
	_generate = _button("Generate", actions)
	_generate.pressed.connect(_on_generate)

	if not bridge.is_available():
		_camera_button.disabled = true
		_library_button.disabled = true
		_show_status("Photo input isn't available in this browser.")
	_refresh()


func open() -> void:
	_reset()
	visible = true


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
	_consent.button_pressed = false
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
	var value: Variant = bridge.ask_name(_name_edit.text)
	if value is String:
		_set_name(value)


func _set_name(value: String) -> void:
	_name_edit.text = value
	_name_button.text = value if not value.is_empty() else NAME_PLACEHOLDER
	_refresh()


func _on_generate() -> void:
	var display_name := _name_edit.text.strip_edges()
	if _jpeg.is_empty() or display_name.is_empty() or not _consent.button_pressed:
		return
	var jpeg := _jpeg
	submitted.emit(display_name, jpeg)
	close()


func _refresh() -> void:
	_generate.disabled = _jpeg.is_empty() or _name_edit.text.strip_edges().is_empty() or not _consent.button_pressed


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
	parent.add_child(button)
	return button
