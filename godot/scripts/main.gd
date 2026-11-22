extends Node3D
## Photo Town world: a blank grassy space where residents wander.
## For now it spawns the demo resident generated from the demo photo.
##
## Debug (desktop): pass `-- --shot=<png path> [--shot-delay=<seconds>]` to save a
## screenshot and quit, e.g. for automated checks.

const WORLD_RADIUS := 10.0
const DEMO_MODEL := "res://demo/resident_demo.glb"
const DEMO_NAME := "Kevin Tse"

var camera_rig: CameraRig
var residents: Node3D
var selected: Resident
var hud_status: Label
var pause_button: Button
var add_button: Button
var add_form: AddResidentForm


func _ready() -> void:
	# Pausing freezes only the residents; the camera, HUD and this script keep
	# running so the player can look around and resume.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_environment()
	_build_ground()
	residents = Node3D.new()
	residents.name = "Residents"
	residents.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(residents)
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	camera_rig.position = Vector3(0.0, 1.0, 0.0)
	add_child(camera_rig)
	camera_rig.tapped.connect(_on_tapped)
	_build_hud()
	_build_pause_ui()
	_build_add_resident_ui()
	_spawn_demo()
	_setup_debug_screenshot()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.8, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = false # keep phones fast
	add_child(sun)


func _build_ground() -> void:
	var grass := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = WORLD_RADIUS + 2.0
	disc.bottom_radius = WORLD_RADIUS + 2.0
	disc.height = 0.2
	disc.radial_segments = 48
	disc.rings = 1
	grass.mesh = disc
	grass.position.y = -0.1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.68, 0.36)
	grass.material_override = mat
	add_child(grass)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	for side in ["left", "top"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.add_theme_constant_override("margin_right", 162) # room for the Pause button
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(margin)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)
	var title := Label.new()
	title.text = "Photo Town"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 6)
	box.add_child(title)
	hud_status = Label.new()
	hud_status.text = "Drag to look around, pinch to zoom, tap a resident."
	hud_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud_status.add_theme_font_size_override("font_size", 18)
	hud_status.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_status.add_theme_constant_override("outline_size", 5)
	box.add_child(hud_status)


func _build_pause_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)

	# Pause button, top right, sized for a thumb. Its label switches between
	# Pause and Resume; it grows leftward so "Resume" never runs off screen.
	# No overlay, so the camera can still orbit and zoom while paused.
	pause_button = Button.new()
	pause_button.text = "Pause"
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.custom_minimum_size = Vector2(130.0, 56.0)
	pause_button.add_theme_font_size_override("font_size", 22)
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	pause_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pause_button.pressed.connect(toggle_pause)
	layer.add_child(pause_button)


func _build_add_resident_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)

	add_button = Button.new()
	add_button.text = "+  Add a resident"
	add_button.focus_mode = Control.FOCUS_NONE
	add_button.custom_minimum_size = Vector2(300.0, 64.0)
	add_button.add_theme_font_size_override("font_size", 24)
	add_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 28)
	add_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_button.pressed.connect(_open_add_form)
	layer.add_child(add_button)

	add_form = AddResidentForm.new()
	layer.add_child(add_form)
	add_form.submitted.connect(_on_photo_submitted)
	add_form.closed.connect(_on_add_form_closed)


func _open_add_form() -> void:
	add_form.open()
	add_button.visible = false
	pause_button.visible = false
	camera_rig.set_process_unhandled_input(false) # drags on the form must not orbit


func _on_add_form_closed() -> void:
	add_button.visible = true
	pause_button.visible = true
	camera_rig.set_process_unhandled_input(true)


func _on_photo_submitted(display_name: String, jpeg: PackedByteArray) -> void:
	# Phase 4 sends this to the relay and spawns a placeholder while it generates.
	# Until then the photo is dropped here and never stored.
	hud_status.text = "Got %s's photo (%d KB). 3D generation is the next step." % [display_name, jpeg.size() / 1024]


func toggle_pause() -> void:
	set_paused(not get_tree().paused)


func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	pause_button.text = "Resume" if paused else "Pause"


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and (key.keycode == KEY_ESCAPE or key.keycode == KEY_P):
		toggle_pause()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# App sent to the background on a phone: pause so residents don't wander off unseen.
	if what == NOTIFICATION_APPLICATION_PAUSED and is_node_ready():
		set_paused(true)


func spawn_resident(display_name: String, model: Node3D, at: Vector3) -> Resident:
	var resident := Resident.new()
	resident.display_name = display_name
	resident.world_radius = WORLD_RADIUS
	residents.add_child(resident)
	resident.global_position = at
	if model:
		resident.set_avatar(model)
	return resident


func _spawn_demo() -> void:
	var model := GlbLoader.from_file(DEMO_MODEL)
	if model == null:
		hud_status.text = "Demo model not found. Showing a placeholder."
	spawn_resident(DEMO_NAME, model, Vector3.ZERO)


func _on_tapped(screen_pos: Vector2) -> void:
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 200.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	var resident: Resident = null
	if not hit.is_empty():
		resident = hit.get("collider") as Resident
	if selected and is_instance_valid(selected):
		selected.set_selected(false)
	selected = resident
	if selected:
		selected.set_selected(true)
		hud_status.text = "%s is out for a walk." % selected.display_name
	else:
		hud_status.text = "Drag to look around, pinch to zoom, tap a resident."


func _setup_debug_screenshot() -> void:
	var shot := ""
	var delay := 3.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--shot-delay="):
			delay = arg.trim_prefix("--shot-delay=").to_float()
	if shot.is_empty():
		return
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shot)
	get_tree().quit()
