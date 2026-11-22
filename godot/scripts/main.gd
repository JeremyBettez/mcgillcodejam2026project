extends Node3D
## Photo Town world: a blank grassy space where your friends wander.
## (In code a friend is a `Resident`; players only ever see the word "friend".)
## Spawns the built-in demo friend, restores the player's saved friends, and
## turns new photos into friends: placeholder first, real 3D model when ready.
##
## HUD layout: title + status top-left, Pause top-right; bottom-left Friends
## list button, bottom-right camera button to add a friend.
##
## Debug (desktop): pass `-- --shot=<png path> [--shot-delay=<seconds>]` to save a
## screenshot and quit, e.g. for automated checks.

const WORLD_RADIUS := 10.0
const DEMO_MODEL := "res://demo/resident_demo.glb"
const DEMO_NAME := "Kevin Tse"
const MAX_RESIDENTS := 15 # phone performance budget, demo friend included
const SAVE_INTERVAL := 15.0
const HINT := "Drag to look around, pinch to zoom. Tap the camera to add a friend."
const TEAL := Color(0.12, 0.6, 0.58)
const ORANGE := Color(0.98, 0.55, 0.2)
const DARK := Color(0.13, 0.15, 0.19)

var camera_rig: CameraRig
var residents: Node3D
var selected: Resident
var hud_status: Label
var pause_button: RoundIconButton
var add_button: RoundIconButton
var friends_button: RoundIconButton
var add_form: AddResidentForm
var relay: RelayClient

var friends_sheet: PanelContainer
var friends_title: Label
var friends_rows: VBoxContainer

var action_bar: PanelContainer
var action_label: Label
var action_row: HBoxContainer
var _remove_button: Button # armed by the first tap on "Remove friend"

var _jobs := {} # job id -> {resident: Resident, jpeg: PackedByteArray, error: String}
var _next_job := 1
var _storage_warned := false
var _dragged: Resident # friend currently held by the player's finger
var _grab_candidate: Resident # friend under the finger when it touched down
var _following: Resident # thrown friend the camera follows until they land


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
	camera_rig.can_grab = _can_grab
	camera_rig.grab_started.connect(_on_grab_started)
	camera_rig.grab_moved.connect(_on_grab_moved)
	camera_rig.grab_ended.connect(_on_grab_ended)
	_build_hud()
	_build_pause_ui()
	_build_bottom_bar()
	_build_action_bar()
	_build_friends_sheet()
	relay = RelayClient.new()
	add_child(relay)
	relay.finished.connect(_on_relay_finished)
	relay.failed.connect(_on_relay_failed)
	_spawn_demo()
	_restore_world()
	var autosave := Timer.new()
	autosave.wait_time = SAVE_INTERVAL
	autosave.autostart = true
	autosave.timeout.connect(_save_world)
	add_child(autosave)
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
	margin.add_theme_constant_override("margin_right", 100) # room for the Pause button
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
	hud_status.text = HINT
	hud_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud_status.add_theme_font_size_override("font_size", 18)
	hud_status.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_status.add_theme_constant_override("outline_size", 5)
	box.add_child(hud_status)


func _build_pause_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)

	# Round Pause button, top right. The icon switches to Play while paused.
	# No overlay, so the camera can still orbit and zoom while paused.
	pause_button = RoundIconButton.new(RoundIconButton.Icon.PAUSE, 64.0, Color(1.0, 1.0, 1.0, 0.92), DARK)
	pause_button.ring_color = Color(1.0, 1.0, 1.0, 0.6)
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 18)
	pause_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pause_button.pressed.connect(toggle_pause)
	layer.add_child(pause_button)


## Bottom row: Friends list button (left) and add-a-friend camera button (right).
func _build_bottom_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	const MARGIN := 22.0
	const SIZE := 84.0

	friends_button = RoundIconButton.new(RoundIconButton.Icon.FRIENDS, SIZE, TEAL)
	friends_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, MARGIN)
	friends_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	friends_button.pressed.connect(_open_friends_sheet)
	layer.add_child(friends_button)

	add_button = RoundIconButton.new(RoundIconButton.Icon.CAMERA, SIZE, ORANGE)
	add_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, MARGIN)
	add_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_button.pressed.connect(_open_add_form)
	layer.add_child(add_button)

	add_form = AddResidentForm.new()
	layer.add_child(add_form)
	add_form.submitted.connect(_on_photo_submitted)
	add_form.closed.connect(_on_add_form_closed)


## Hide the floating buttons while a full-screen panel (form, list) is open.
func _set_world_ui(on: bool) -> void:
	for control: Control in [add_button, friends_button, pause_button]:
		control.visible = on
	camera_rig.set_process_unhandled_input(on) # drags on panels must not orbit


# --- Friends list -------------------------------------------------------------

func _build_friends_sheet() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	friends_sheet = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = DARK
	style.set_corner_radius_all(18)
	style.set_content_margin_all(16)
	friends_sheet.add_theme_stylebox_override("panel", style)
	friends_sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE, Control.PRESET_MODE_MINSIZE, 12)
	friends_sheet.grow_vertical = Control.GROW_DIRECTION_BEGIN
	friends_sheet.visible = false
	layer.add_child(friends_sheet)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	friends_sheet.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	friends_title = Label.new()
	friends_title.add_theme_font_size_override("font_size", 26)
	friends_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friends_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(friends_title)
	var close := RoundIconButton.new(RoundIconButton.Icon.CLOSE, 48.0, Color(0.25, 0.28, 0.33), Color.WHITE)
	close.ring_color = Color(0.25, 0.28, 0.33)
	close.pressed.connect(_close_friends_sheet)
	header.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0.0, 380.0)
	box.add_child(scroll)
	friends_rows = VBoxContainer.new()
	friends_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friends_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(friends_rows)


func _open_friends_sheet() -> void:
	_select(null)
	for row in friends_rows.get_children():
		row.queue_free()
	var friends: Array[Resident] = []
	for child in residents.get_children():
		if child is Resident and not child.is_queued_for_deletion():
			friends.append(child)
	friends_title.text = "Your friends (%d)" % friends.size()
	if friends.is_empty():
		var empty := Label.new()
		empty.text = "No friends yet. Tap the camera to add one."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 18)
		friends_rows.add_child(empty)
	for friend in friends:
		var row := Button.new()
		row.text = "%s   ·   %s" % [friend.display_name, _friend_status(friend)]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.focus_mode = Control.FOCUS_NONE
		row.custom_minimum_size = Vector2(0.0, 56.0)
		row.add_theme_font_size_override("font_size", 20)
		row.pressed.connect(_on_friend_row.bind(friend))
		friends_rows.add_child(row)
	friends_sheet.visible = true
	_set_world_ui(false)


func _close_friends_sheet() -> void:
	friends_sheet.visible = false
	_set_world_ui(true)


func _on_friend_row(friend: Resident) -> void:
	_close_friends_sheet()
	if is_instance_valid(friend) and not friend.is_queued_for_deletion():
		camera_rig.focus_on(friend.global_position)
		_select(friend)


func _friend_status(friend: Resident) -> String:
	var job: int = friend.get_meta("job", 0)
	if job and _jobs.has(job):
		return "building 3D..." if str(_jobs[job].error).is_empty() else "couldn't build"
	return "resting" if get_tree().paused else "out for a walk"


## Bottom bar with a message and up to two buttons (Retry/Remove...).
func _build_action_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	action_bar = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.15, 0.19)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(12)
	action_bar.add_theme_stylebox_override("panel", style)
	action_bar.custom_minimum_size = Vector2(500.0, 0.0)
	action_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 140)
	action_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	action_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	action_bar.visible = false
	layer.add_child(action_bar)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	action_bar.add_child(box)
	action_label = Label.new()
	action_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_label.add_theme_font_size_override("font_size", 18)
	box.add_child(action_label)
	action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	box.add_child(action_row)


## Show the bar with a message and buttons: `buttons` is [[label, Callable], ...].
## Returns the created buttons in the same order.
func _show_actions(text: String, buttons: Array) -> Array[Button]:
	action_label.text = text
	for old in action_row.get_children():
		action_row.remove_child(old)
		old.queue_free()
	var made: Array[Button] = []
	for spec: Array in buttons:
		var button := Button.new()
		button.text = spec[0]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0.0, 52.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 20)
		button.pressed.connect(spec[1])
		action_row.add_child(button)
		made.append(button)
	action_bar.visible = true
	return made


func _hide_actions() -> void:
	action_bar.visible = false
	_remove_button = null


func _open_add_form() -> void:
	if _resident_count() >= MAX_RESIDENTS:
		hud_status.text = "You have the most friends a town can hold (%d). Tap one and remove them first." % MAX_RESIDENTS
		return
	_select(null)
	add_form.open()
	_set_world_ui(false)


func _on_add_form_closed() -> void:
	_set_world_ui(true)


func _resident_count() -> int:
	var count := 0
	for child in residents.get_children():
		if not child.is_queued_for_deletion():
			count += 1
	return count


# --- Generating new residents -------------------------------------------------

func _on_photo_submitted(display_name: String, jpeg: PackedByteArray) -> void:
	# A placeholder walks around while the relay builds the model (1-3 minutes).
	var angle := randf() * TAU
	var spot := Vector3(cos(angle), 0.0, sin(angle)) * randf_range(1.5, 3.5)
	var resident := spawn_resident(display_name, null, spot)
	var job := _next_job
	_next_job += 1
	resident.set_meta("job", job)
	_jobs[job] = {"resident": resident, "jpeg": jpeg, "error": ""}
	_start_job(job)
	hud_status.text = "Building %s's 3D model. This takes 1-3 minutes." % display_name


func _start_job(job: int) -> void:
	var info: Dictionary = _jobs[job]
	info.error = ""
	(info.resident as Resident).status_text = "building 3D..."
	relay.generate(job, info.jpeg)


func _on_relay_finished(job: int, glb: PackedByteArray) -> void:
	if not _jobs.has(job) or not is_instance_valid(_jobs[job].resident):
		_jobs.erase(job)
		return
	var resident: Resident = _jobs[job].resident
	var model := GlbLoader.from_bytes(glb)
	if model == null:
		_on_relay_failed(job, "The 3D model couldn't be loaded.")
		return
	resident.set_avatar(model)
	resident.status_text = ""
	resident.remove_meta("job")
	_jobs.erase(job) # drops the photo from memory
	resident.resident_id = WorldStore.new_id()
	if WorldStore.save_model(resident.resident_id, glb):
		resident.saved = true
		_save_world()
		hud_status.text = "%s is now your friend!" % resident.display_name
	else:
		_warn_storage()
	if selected == resident:
		_select(resident)


func _on_relay_failed(job: int, message: String) -> void:
	if not _jobs.has(job) or not is_instance_valid(_jobs[job].resident):
		_jobs.erase(job)
		return
	var resident: Resident = _jobs[job].resident
	_jobs[job].error = message
	resident.status_text = "couldn't build"
	_select(resident) # show Retry / Remove right away


func _retry_job(job: int) -> void:
	if _jobs.has(job):
		_start_job(job)
		_select(_jobs[job].resident)


func _discard_job(job: int) -> void:
	if _jobs.has(job):
		var resident: Resident = _jobs[job].resident
		_jobs.erase(job) # drops the photo from memory
		if is_instance_valid(resident):
			resident.queue_free()
	_select(null)


# --- Saving the player's world (per device) ----------------------------------

func _restore_world() -> void:
	for entry in WorldStore.load_index():
		var id := str(entry.id)
		var model := GlbLoader.from_bytes(WorldStore.load_model(id))
		if model == null:
			push_warning("Skipping saved friend %s: model unreadable" % id)
			continue
		var at := Vector3(float(entry.get("x", 0.0)), 0.0, float(entry.get("z", 0.0)))
		var resident := spawn_resident(str(entry.get("name", "Friend")), model, at)
		resident.resident_id = id
		resident.saved = true


func _save_world() -> void:
	var entries: Array[Dictionary] = []
	for child in residents.get_children():
		var resident := child as Resident
		if resident and resident.saved and not resident.is_queued_for_deletion():
			entries.append({
				"id": resident.resident_id,
				"name": resident.display_name,
				"x": snappedf(resident.global_position.x, 0.01),
				"z": snappedf(resident.global_position.z, 0.01),
			})
	if not WorldStore.save_index(entries):
		_warn_storage()


func _warn_storage() -> void:
	if not _storage_warned:
		_storage_warned = true
		hud_status.text = "Couldn't save on this device. Your friends will be gone when you leave."


func _remove_resident(resident: Resident) -> void:
	if not is_instance_valid(resident):
		return
	if _remove_button and _remove_button.text != "Tap again":
		_remove_button.text = "Tap again" # second tap confirms
		return
	if resident.saved:
		WorldStore.delete_model(resident.resident_id)
	resident.queue_free()
	_select(null)
	_save_world()
	hud_status.text = "%s was removed from your friends." % resident.display_name


func toggle_pause() -> void:
	set_paused(not get_tree().paused)


func set_paused(paused: bool) -> void:
	get_tree().paused = paused
	pause_button.icon_kind = RoundIconButton.Icon.PLAY if paused else RoundIconButton.Icon.PAUSE


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and (key.keycode == KEY_ESCAPE or key.keycode == KEY_P):
		toggle_pause()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	# App sent to the background on a phone: pause so residents don't wander off unseen.
	if what == NOTIFICATION_APPLICATION_PAUSED:
		set_paused(true)
	# Leaving or switching away: save positions now.
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		_save_world()


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
	_select(_resident_at(screen_pos))


## The friend under a screen point, or null.
func _resident_at(screen_pos: Vector2) -> Resident:
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 200.0
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))
	if hit.is_empty():
		return null
	return hit.get("collider") as Resident


## Where a screen point lands on the ground (y = 0), kept inside the world.
func _ground_point(screen_pos: Vector2) -> Variant:
	var cam := camera_rig.camera
	var point: Variant = Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
	if point == null:
		return null
	var flat := Vector2((point as Vector3).x, (point as Vector3).z).limit_length(WORLD_RADIUS)
	return Vector3(flat.x, 0.0, flat.y)


# --- Picking friends up -------------------------------------------------------

## Called on touch-down: remember who is under the finger, so the grab (which
## starts a moment later) gets that friend even if they've moved since.
func _can_grab(screen_pos: Vector2) -> bool:
	_grab_candidate = _resident_at(screen_pos)
	return _grab_candidate != null


func _on_grab_started(screen_pos: Vector2) -> void:
	var friend := _grab_candidate
	_grab_candidate = null
	if friend == null or not is_instance_valid(friend) or friend.is_queued_for_deletion():
		friend = _resident_at(screen_pos)
	if friend == null or friend.is_held():
		return
	if get_tree().paused:
		set_paused(false) # they can't dangle or fall while the world is frozen
	_select(null)
	_dragged = friend
	friend.pick_up()
	hud_status.text = "Wheee! Move %s around and let go to drop them." % friend.display_name


func _process(_delta: float) -> void:
	if _following:
		if is_instance_valid(_following) and _following.is_held():
			var p := _following.global_position
			camera_rig.focus_on(Vector3(p.x, 0.0, p.z))
		else:
			_following = null


func _on_grab_moved(screen_pos: Vector2) -> void:
	if _dragged and is_instance_valid(_dragged):
		var point: Variant = _ground_point(screen_pos)
		if point is Vector3:
			_dragged.drag_to(point)


func _on_grab_ended(_screen_pos: Vector2) -> void:
	if _dragged and is_instance_valid(_dragged):
		var speed := _dragged.drop()
		if speed > 2.0:
			_following = _dragged # keep a thrown friend in view until they land
		if speed > 6.0:
			hud_status.text = "You launched %s!" % _dragged.display_name
		elif speed > 2.0:
			hud_status.text = "You tossed %s." % _dragged.display_name
		else:
			hud_status.text = "You dropped %s." % _dragged.display_name
	_dragged = null


## Highlight a resident (or none) and show what can be done with it.
func _select(resident: Resident) -> void:
	if selected and is_instance_valid(selected):
		selected.set_selected(false)
	selected = resident
	_hide_actions()
	if selected == null:
		hud_status.text = HINT
		return
	selected.set_selected(true)
	var job: int = selected.get_meta("job", 0)
	if job and _jobs.has(job):
		var error: String = _jobs[job].error
		if error.is_empty():
			hud_status.text = "%s's 3D model is still being built." % selected.display_name
		else:
			hud_status.text = HINT
			_show_actions("Couldn't build %s: %s" % [selected.display_name, error],
				[["Remove", _discard_job.bind(job)], ["Retry", _retry_job.bind(job)]])
		return
	hud_status.text = "%s is out for a walk." % selected.display_name
	var buttons: Array = [["Wave", _ask_to.bind(selected, "wave")], ["Dance", _ask_to.bind(selected, "dance")]]
	if selected.saved:
		buttons.append(["Remove", _remove_resident.bind(selected)])
	var made := _show_actions(selected.display_name, buttons)
	if selected.saved:
		_remove_button = made[2]


## Ask a friend to wave or dance; they turn to face the player first.
func _ask_to(friend: Resident, action: String) -> void:
	if not is_instance_valid(friend):
		return
	if get_tree().paused:
		set_paused(false) # an action you can't see would feel broken
	friend.perform(action, camera_rig.camera.global_position)
	hud_status.text = "%s is %s!" % [friend.display_name, "waving at you" if action == "wave" else "dancing"]


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
