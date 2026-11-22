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

const WORLD_RADIUS := 400.0 # how far from the middle friends can be thrown or carried
const GROUND_SIZE := 600.0 # grass square that follows the camera, so the land never ends
const TOWN_MARGIN := 40.0 # the camera can pan this far past the outermost building
const PLACE_GAP := 0.6 # each building keeps this much clear ground around its footprint
const NEW_PLACE_ROOM := Rect2(-5.0, -5.0, 10.0, 10.0) # kept free for a new place's model
const ROTATE_STEP := PI / 4.0 # one tap on Rotate turns a building this much
const BLUE := UiStyle.SKY
const MAX_PLACES := 20 # places the player can add (phone performance budget)
const DEMO_MODEL := "res://demo/resident_demo.glb"
const DEMO_NAME := "Kevin Tse"
const DEMO_MODEL_2 := "res://demo/stephen_demo.glb"
const DEMO_NAME_2 := "Stephen Chen"
const DEMO_MODEL_3 := "res://demo/jeremy_demo.glb"
const DEMO_NAME_3 := "Jeremy Bettez"
const MAX_RESIDENTS := 15 # phone performance budget, demo friend included
const SAVE_INTERVAL := 15.0
const HINT := "Drag to look around, pinch to zoom. Tap the camera to add a friend."
const TEAL := UiStyle.LEAF
const ORANGE := UiStyle.ORANGE
const DARK := UiStyle.BROWN

var camera_rig: CameraRig
var residents: Node3D
var selected: Resident
var hud_status: Label
var pause_button: RoundIconButton
var add_button: RoundIconButton
var friends_button: RoundIconButton
var location_button: RoundIconButton
var locations := {} # location id -> Location
var locations_root: Node3D
var districts := {} # district id -> District (only cells that have a place in them)
var ground: MeshInstance3D
var thumbnailer: Thumbnailer
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
var _place_candidate: Location # building under the finger at touch-down
var _moving: Location # building being carried somewhere else
var _move_from := Vector3.ZERO
var _move_finger := Vector2(-1.0, -1.0)
var _drop_at := Vector3.ZERO # where the carried building would land
var _drop_ok := false # ...and whether there is room for it there
var _drop_marker: MeshInstance3D
var _last_status := ""


func _ready() -> void:
	# Pausing freezes only the residents; the camera, HUD and this script keep
	# running so the player can look around and resume.
	process_mode = Node.PROCESS_MODE_ALWAYS
	UiStyle.apply(get_tree().root) # cozy font + cream panels for every Control
	_build_environment()
	_build_ground()
	residents = Node3D.new()
	residents.name = "Residents"
	residents.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(residents)
	camera_rig = CameraRig.new()
	camera_rig.name = "CameraRig"
	# Start looking at Downtown (McGill), zoomed out enough to see the building.
	camera_rig.position = Vector3(0.0, 1.0, 3.0)
	camera_rig.distance = 18.0
	add_child(camera_rig)
	var leaves := FallingLeaves.new() # gentle autumn leaves around the view
	leaves.follow = camera_rig
	add_child(leaves)
	camera_rig.tapped.connect(_on_tapped)
	camera_rig.can_grab = _can_grab
	camera_rig.can_hold_grab = _can_hold_grab
	camera_rig.grab_started.connect(_on_grab_started)
	camera_rig.grab_moved.connect(_on_grab_moved)
	camera_rig.grab_ended.connect(_on_grab_ended)
	_build_hud()
	_build_pause_ui()
	_build_bottom_bar()
	_build_action_bar()
	_build_friends_sheet()
	UiStyle.apply_to_layers(self) # CanvasLayer UIs don't inherit the window theme
	relay = RelayClient.new()
	add_child(relay)
	relay.finished.connect(_on_relay_finished)
	relay.failed.connect(_on_relay_failed)
	thumbnailer = Thumbnailer.new()
	add_child(thumbnailer)
	_build_locations()
	_restore_layout() # built-in places the player moved or turned
	_restore_places() # before friends, so their saved homes can be found
	_sync_districts() # neighbourhood lawns under every place, camera area
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
	env.background_color = Color(0.98, 0.83, 0.68) # hazy autumn afternoon sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.86, 0.72) # golden autumn light
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.92, 0.80) # low, warm fall sun
	sun.shadow_enabled = false # keep phones fast
	add_child(sun)


## Plain grass that follows the camera (see _process): one colour, so moving
## it is invisible and the land never runs out.
func _build_ground() -> void:
	ground = MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.60, 0.62, 0.32) # late-season golden grass
	ground.material_override = mat
	add_child(ground)


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
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	# Title as a little green wooden-sign pill.
	var sign := PanelContainer.new()
	sign.add_theme_stylebox_override("panel", UiStyle.title_sign())
	sign.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(sign)
	var title := Label.new()
	title.text = "Photo Town"
	title.add_theme_font_override("font", UiStyle.bold())
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_shadow_color", UiStyle.LEAF_DARK)
	title.add_theme_constant_override("shadow_offset_y", 2)
	sign.add_child(title)
	# Status line inside a cream speech bubble.
	var bubble := PanelContainer.new()
	var bubble_style := UiStyle.bubble()
	bubble_style.set_corner_radius_all(22)
	bubble_style.set_content_margin_all(12)
	bubble_style.content_margin_left = 16
	bubble.add_theme_stylebox_override("panel", bubble_style)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bubble)
	hud_status = Label.new()
	hud_status.text = HINT
	hud_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud_status.add_theme_font_size_override("font_size", 17)
	bubble.add_child(hud_status)


func _build_pause_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)

	# Round Pause button, top right. The icon switches to Play while paused.
	# No overlay, so the camera can still orbit and zoom while paused.
	pause_button = RoundIconButton.new(RoundIconButton.Icon.PAUSE, 64.0, UiStyle.CREAM, UiStyle.BROWN)
	pause_button.ring_color = UiStyle.TAN
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 18)
	pause_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	pause_button.pressed.connect(toggle_pause)
	layer.add_child(pause_button)


## Bottom row: Locations (left), Friends (centre), add a friend (right).
func _build_bottom_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	const MARGIN := 14.0
	const STICKER := 108.0

	# Painted sticker icons (godot/icons/); each falls back to its drawn icon.
	location_button = RoundIconButton.new(RoundIconButton.Icon.PIN, STICKER, BLUE)
	location_button.picture = _sticker("res://icons/pin.png")
	location_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, MARGIN)
	location_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	location_button.pressed.connect(_open_locations_list)
	layer.add_child(location_button)

	# The middle button is the app's mascot (a travelling goose), a bit bigger.
	# Falls back to the drawn two-friends icon if the picture is missing.
	friends_button = RoundIconButton.new(RoundIconButton.Icon.FRIENDS, 136.0, TEAL)
	friends_button.picture = _sticker("res://icons/goose.png")
	friends_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, MARGIN)
	friends_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	friends_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	friends_button.pressed.connect(_open_friends_sheet)
	layer.add_child(friends_button)

	add_button = RoundIconButton.new(RoundIconButton.Icon.CAMERA, STICKER, ORANGE)
	add_button.picture = _sticker("res://icons/camera.png")
	add_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, MARGIN)
	add_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_button.pressed.connect(_open_add_form)
	add_button.pulse = true # gentle ring that invites you to add a friend
	layer.add_child(add_button)

	add_form = AddResidentForm.new()
	layer.add_child(add_form)
	add_form.submitted.connect(_on_photo_submitted)
	add_form.closed.connect(_on_add_form_closed)


func _sticker(path: String) -> Texture2D:
	var texture: Variant = load(path) if ResourceLoader.exists(path) else null
	return texture as Texture2D


## Hide the floating buttons while a full-screen panel (form, list) is open.
func _set_world_ui(on: bool) -> void:
	var i := 0
	for control: Control in [location_button, friends_button, add_button, pause_button]:
		var was_visible := control.visible
		control.visible = on
		if on and not was_visible:
			UiFx.pop_in(control, 0.05 * i, 0.6) # buttons bounce back in, one after another
			i += 1
	camera_rig.set_process_unhandled_input(on) # drags on panels must not orbit


# --- Friends list -------------------------------------------------------------

func _build_friends_sheet() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	friends_sheet = PanelContainer.new()
	friends_sheet.add_theme_stylebox_override("panel", UiStyle.bubble())
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
	friends_title.add_theme_font_override("font", UiStyle.bold())
	friends_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friends_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(friends_title)
	var close := RoundIconButton.new(RoundIconButton.Icon.CLOSE, 48.0, UiStyle.CREAM_DARK, UiStyle.BROWN)
	close.ring_color = UiStyle.TAN
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


## Show the slide-up list panel. `items` is [{text, action: Callable, disabled?}],
## shown as tappable rows; `empty_text` is shown when there are none.
func _show_list(title: String, items: Array, empty_text := "") -> void:
	_select(null)
	for row in friends_rows.get_children():
		row.queue_free()
	friends_title.text = title
	if items.is_empty() and not empty_text.is_empty():
		var empty := Label.new()
		empty.text = empty_text
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 18)
		friends_rows.add_child(empty)
	for item: Dictionary in items:
		var row := Button.new()
		row.text = item.text
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.focus_mode = Control.FOCUS_NONE
		row.custom_minimum_size = Vector2(0.0, 56.0)
		row.add_theme_font_size_override("font_size", 20)
		row.disabled = item.get("disabled", false)
		if item.has("action"):
			row.pressed.connect(item.action)
		UiFx.add_press_bounce(row)
		friends_rows.add_child(row)
		# Small picture of the friend / location next to its name.
		if item.has("friend") or item.has("location"):
			row.custom_minimum_size.y = 72.0
			row.expand_icon = false
			row.add_theme_constant_override("icon_max_width", 60)
			row.add_theme_constant_override("h_separation", 14)
			var set_icon := func(texture: Texture2D) -> void:
				if is_instance_valid(row):
					row.icon = texture
			if item.has("friend"):
				thumbnailer.friend_portrait(item.friend, set_icon)
			else:
				thumbnailer.location_picture(item.location, set_icon)
	friends_sheet.modulate.a = 0.0 # hidden until laid out, then slides up
	friends_sheet.visible = true
	_set_world_ui(false)
	await get_tree().process_frame
	if not friends_sheet.visible:
		return
	UiFx.slide_up(friends_sheet, 160.0)
	var i := 0
	for row in friends_rows.get_children():
		if row is Control and not row.is_queued_for_deletion():
			UiFx.pop_in(row, 0.08 + 0.05 * i, 0.9)
			i += 1


func _close_friends_sheet() -> void:
	UiFx.slide_down(friends_sheet, func() -> void: _set_world_ui(true), 160.0)


func _open_friends_sheet() -> void:
	var items: Array = []
	for friend in _friends():
		items.append({"text": "%s   ·   %s" % [friend.display_name, _friend_status(friend)], "action": _on_friend_row.bind(friend), "friend": friend})
	_show_list("Your friends (%d)" % items.size(), items, "No friends yet. Tap the camera to add one.")


func _friends() -> Array[Resident]:
	var out: Array[Resident] = []
	for child in residents.get_children():
		if child is Resident and not child.is_queued_for_deletion():
			out.append(child)
	return out


func _on_friend_row(friend: Resident) -> void:
	_close_friends_sheet()
	if is_instance_valid(friend) and not friend.is_queued_for_deletion():
		camera_rig.focus_on(friend.global_position)
		_select(friend)


func _friend_status(friend: Resident) -> String:
	var job: int = friend.get_meta("job", 0)
	if job and _jobs.has(job):
		return "building 3D..." if str(_jobs[job].error).is_empty() else "couldn't build"
	if get_tree().paused:
		return "resting"
	if friend.home and is_instance_valid(friend.home):
		return "at %s" % friend.home.display_name
	return "out for a walk"


# --- Locations ----------------------------------------------------------------

func _build_locations() -> void:
	locations_root = Node3D.new()
	locations_root.name = "Locations"
	add_child(locations_root)
	# Places stand anywhere on the open land; these are where the built-in ones
	# start (the player can move and turn them). Neighbourhood lawns appear
	# under them by themselves (_sync_districts).
	_add_builtin("mcgill", "McGill University", McGillModel.build(), McGillModel.FOOTPRINT, Vector3(0, 0, 0), 8.0)
	_add_builtin("starbucks", "Starbucks", CafeModels.starbucks(), CafeModels.STARBUCKS_FOOTPRINT, Vector3(-12, 0, 0), 6.0, 15.0)
	_add_builtin("mcdonalds", "McDonald's", CafeModels.mcdonalds(), CafeModels.MCDONALDS_FOOTPRINT, Vector3(12, 0, 0), 6.0, 16.0)
	_add_builtin("oratory", "Saint Joseph's Oratory", OratoryModel.build(), OratoryModel.FOOTPRINT, Vector3(-40, 0, 0), 8.0, 30.0)
	var marianopolis := MarianopolisModel.build()
	_add_builtin("marianopolis", "Marianopolis College", marianopolis.model, marianopolis.footprint, Vector3(-52, 0, 0), 8.0,
		clampf(float(marianopolis.height) * 2.4 + 8.0, 15.0, 28.0))
	_add_builtin("old_port", "Old Port", OldPortModel.build(), OldPortModel.FOOTPRINT, Vector3(0, 0, 26), 8.0, 23.0)
	_add_builtin("jean_drapeau", "Parc Jean-Drapeau", JeanDrapeauModel.build(), JeanDrapeauModel.FOOTPRINT, Vector3(40, 0, 26), 7.5, 18.0)


## Make the neighbourhood lawns match the places: every grid cell with a place
## in it gets its district, empty ones shrink away. Also tells each place which
## neighbourhood it is in, and widens the camera's area to the whole town.
func _sync_districts() -> void:
	var wanted := {} # district id -> cell
	for id: String in locations:
		var place: Location = locations[id]
		if place.is_queued_for_deletion():
			continue
		var cell := District.cell_of(place.position)
		var info := District.info_for(cell)
		place.district_id = info.id
		wanted[info.id] = cell
	for id: String in wanted:
		if not districts.has(id):
			var district := District.new(wanted[id])
			locations_root.add_child(district)
			districts[id] = district
	for id: String in districts.keys():
		if not wanted.has(id):
			var district: District = districts[id]
			districts.erase(id)
			var tween := create_tween()
			tween.tween_property(district, "scale", Vector3(0.01, 1.0, 0.01), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tween.tween_callback(district.queue_free)
	_update_camera_bounds()


## Let the camera pan over the whole town plus TOWN_MARGIN of open land (room
## to carry buildings further out; the area grows as the town does).
func _update_camera_bounds() -> void:
	var bounds := Rect2()
	var first := true
	for id: String in locations:
		var place: Location = locations[id]
		if place.is_queued_for_deletion():
			continue
		var r := Rect2(Vector2(place.position.x, place.position.z), Vector2.ZERO)
		bounds = r if first else bounds.merge(r)
		first = false
	camera_rig.bounds = bounds.grow(TOWN_MARGIN)


## The neighbourhood name for a place (for status lines).
func _district_name(place: Location) -> String:
	var district: District = districts.get(place.district_id)
	return district.display_name if district else str(District.info_for(District.cell_of(place.position)).name)


## True if a footprint polygon (world XZ, already grown by PLACE_GAP) touches
## no other place's footprint (also grown by PLACE_GAP).
func _spot_free(polygon: PackedVector2Array, ignore: Location = null) -> bool:
	for id: String in locations:
		var other: Location = locations[id]
		if other == ignore or other.is_queued_for_deletion():
			continue
		if not Geometry2D.intersect_polygons(polygon, other.world_footprint(PLACE_GAP)).is_empty():
			return false
	return true


## The nearest free spot to `near` where `room` (a local footprint, facing +Z)
## fits, searching outward in rings. Snapped to half metres. Null if none
## within WORLD_RADIUS (in practice there always is one).
func _free_spot_near(near: Vector3, room: Rect2) -> Variant:
	var grown := room.grow(PLACE_GAP)
	var step := 3.0
	var ring := 0
	while ring * step <= WORLD_RADIUS:
		var radius := ring * step
		var tries := 1 if ring == 0 else int(TAU * radius / step)
		for i in tries:
			var angle := TAU * i / tries
			var at := Vector3(snappedf(near.x + cos(angle) * radius, 0.5), 0.0, snappedf(near.z + sin(angle) * radius, 0.5))
			if _spot_free(Location.footprint_polygon(grown, at, 0.0)):
				return at
		ring += 1
	return null


func _add_builtin(id: String, display_name: String, model: Node3D, footprint: Rect2, at: Vector3, radius: float, view_distance := 0.0) -> void:
	var place := Location.new()
	place.location_id = id
	place.display_name = display_name
	place.hangout_radius = radius
	place.footprint = footprint
	place.view_distance = view_distance
	place.position = at
	locations_root.add_child(place)
	place.set_model(model)
	locations[id] = place


func _open_locations_list() -> void:
	var items: Array = []
	for id: String in locations:
		var place: Location = locations[id]
		var count := 0
		for friend in _friends():
			if friend.home == place:
				count += 1
		items.append({"text": "%s   ·   %d friend%s" % [place.display_name, count, "" if count == 1 else "s"], "action": _on_location_row.bind(place), "location": place})
	items.append({"text": "+  Add a location", "action": _open_add_place_form})
	_show_list("Locations (%d)" % locations.size(), items)


func _on_location_row(place: Location) -> void:
	_close_friends_sheet()
	_fly_to_place(place)
	hud_status.text = "%s: %s" % [place.display_name, _who_is_at(place)]
	_show_place_actions(place)


## Glide the camera to face the front of a location (its +Z side), from slightly
## above, far enough back that the whole building (plus a margin) fits on screen.
func _fly_to_place(place: Location) -> void:
	var front := place.global_transform.basis.z
	front.y = 0.0
	var cam := camera_rig.camera
	var view := get_viewport().get_visible_rect().size
	var aspect := view.x / maxf(view.y, 1.0)
	var half_h_fov := atan(tan(deg_to_rad(cam.fov) * 0.5) * aspect) # portrait phones: narrow
	var width := maxf(place.footprint.size.x, place.footprint.size.y) + 1.0 # building + a little margin
	var fit := width * 0.5 / tan(half_h_fov) + place.footprint.size.y * 0.5
	# Capped and looking a bit more downward, so other buildings between us and the
	# place (places face the middle of the map) don't block the view.
	var distance := clampf(fit, 13.0, 21.0)
	if place.view_distance > 0.0:
		distance = place.view_distance # tall or round models (Ferris wheel, dome)
	camera_rig.view_from(place.global_position + front.normalized() * 1.0, front.normalized(), deg_to_rad(-26.0), distance)


## Bar for a location: Retry/Remove while its model failed; otherwise Rotate,
## plus Remove for places the player added.
func _show_place_actions(place: Location) -> void:
	_hide_actions()
	var job: int = place.get_meta("job", 0)
	if job and _jobs.has(job):
		var error: String = _jobs[job].error
		if not error.is_empty():
			_show_actions("Couldn't build %s: %s" % [place.display_name, error],
				[["Remove", _discard_job.bind(job)], ["Retry", _retry_job.bind(job)]])
		return
	var buttons: Array = [["Rotate", _rotate_place.bind(place)]]
	if place.user_added:
		buttons.append(["Remove place", _remove_place.bind(place)])
	var made := _show_actions("%s · hold to move it" % place.display_name, buttons)
	if place.user_added:
		_remove_button = made[1]


## Turn a building by ROTATE_STEP, if it has room to turn where it stands.
func _rotate_place(place: Location) -> void:
	if not is_instance_valid(place) or place == _moving:
		return
	var from := place.rotation.y
	var to := from + ROTATE_STEP
	if not _spot_free(place.world_footprint(PLACE_GAP, place.position, to), place):
		hud_status.text = "%s has no room to turn here. Hold it to move it first." % place.display_name
		return
	var tween := create_tween()
	tween.tween_property(place, "rotation:y", to, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		place.rotation.y = wrapf(to, -PI, PI)
		_save_world())
	for friend in _friends():
		if friend.home == place:
			friend.go_home()
	hud_status.text = "%s turned." % place.display_name


func _open_add_place_form() -> void:
	_close_friends_sheet()
	if _user_place_count() >= MAX_PLACES:
		hud_status.text = "There's no more room for new places (%d max). Remove one first." % MAX_PLACES
		return
	add_form.open("place")
	_set_world_ui(false)


func _user_place_count() -> int:
	var count := 0
	for id: String in locations:
		if (locations[id] as Location).user_added:
			count += 1
	return count


func _make_place(id: String, display_name: String, at: Vector3, yaw := 0.0) -> Location:
	var place := Location.new()
	place.location_id = id
	place.display_name = display_name
	place.hangout_radius = 7.0
	place.user_added = true
	place.position = at
	place.rotation.y = yaw
	locations_root.add_child(place)
	locations[id] = place
	return place


## `detailed`: Detailed 3D (TRELLIS mesh) instead of the default Quick build
## (Claude describes the photo as a recipe, RecipeModel builds it in code).
func _on_place_submitted(display_name: String, jpeg: PackedByteArray, wants_flag: bool, detailed := false) -> void:
	# The nearest open ground to where you are looking.
	var focus := camera_rig.position
	var spot: Variant = _free_spot_near(Vector3(focus.x, 0.0, focus.z), NEW_PLACE_ROOM)
	if spot == null:
		hud_status.text = "There's no room left in town for another place."
		return
	var place := _make_place(WorldStore.new_id(), display_name, spot)
	_sync_districts()
	# Flag: a known design for the name, otherwise colours from the photo.
	if wants_flag:
		var known: Variant = Flag.design_for_name(display_name)
		place.flag_design = known if known != null else Flag.design_from_photo(jpeg)
	# Show a construction site until the 3D model arrives.
	place.set_model(ConstructionModel.build())
	place.footprint = ConstructionModel.FOOTPRINT
	place.set_walls(Vector3(6.0, 1.0, 4.0))
	place.show_name_tag(4.4)
	place.refresh_flag()
	var job := _next_job
	_next_job += 1
	place.set_meta("job", job)
	_jobs[job] = {"kind": "place", "place": place, "jpeg": jpeg, "error": "",
		"style": "mesh" if detailed else "recipe", "wants_flag": wants_flag}
	_start_job(job)
	_fly_to_place(place)
	hud_status.text = ("Building %s. This takes a few minutes." if detailed else "Designing %s. This takes about 20 seconds.") % display_name


func _remove_place(place: Location) -> void:
	if not is_instance_valid(place):
		return
	if _remove_button and _remove_button.text != "Tap again":
		_remove_button.text = "Tap again" # second tap confirms
		return
	_delete_place(place)


func _delete_place(place: Location) -> void:
	for friend in _friends():
		if friend.home == place:
			friend.home = null # they wander the whole map again
	locations.erase(place.location_id)
	if place.user_added:
		WorldStore.delete_place_model(place.location_id)
	place.queue_free()
	_sync_districts() # its neighbourhood goes if nothing else stands there
	_hide_actions()
	_save_world()
	hud_status.text = "%s was removed from the map." % place.display_name


func _restore_places() -> void:
	for entry in WorldStore.load_places():
		var id := str(entry.id)
		var recipe: Variant = entry.get("recipe")
		var model: Node3D = null
		if not recipe is Dictionary:
			model = GlbLoader.from_bytes(WorldStore.load_place_model(id), false)
			if model == null:
				push_warning("Skipping saved place %s: model unreadable" % id)
				continue
		# Back where it stood; saves from before free placement have only a
		# district and lot; failing both, the nearest open ground.
		var spot: Variant = _saved_spot(entry)
		if spot == null:
			spot = _free_spot_near(Vector3.ZERO, NEW_PLACE_ROOM)
		if spot == null:
			push_warning("Skipping saved place %s: no room" % id)
			continue
		var place := _make_place(id, str(entry.get("name", "Place")), spot, float(entry.get("yaw", 0.0)))
		place.flag_design = _flag_from_json(entry.get("flag"))
		if recipe is Dictionary:
			place.set_recipe_model(RecipeModel.build(recipe))
			place.set_meta("recipe", recipe)
		else:
			place.set_generated_model(model)


## Where a saved place (or built-in layout entry) stood: {x, z}, or the
## {district, lot} older saves used. Null if neither is there.
static func _saved_spot(entry: Dictionary) -> Variant:
	if entry.has("x") and entry.has("z"):
		return Vector3(float(entry.x), 0.0, float(entry.z))
	return District.old_lot_position(str(entry.get("district", "")), int(entry.get("lot", -1)))


static func _flag_to_json(design: Variant) -> Variant:
	if design is Dictionary:
		var colors: Array = design.get("colors", [])
		return {"colors": colors.map(func(c: Color) -> String: return c.to_html(false))}
	return design # null or a named design like "mcgill"


static func _flag_from_json(value: Variant) -> Variant:
	if value is Dictionary:
		var colors: Array = (value as Dictionary).get("colors", [])
		return {"colors": colors.map(func(c: Variant) -> Color: return Color.html(str(c)))}
	if value is String and not (value as String).is_empty():
		return value
	return null


func _who_is_at(place: Location) -> String:
	var names: Array[String] = []
	for friend in _friends():
		if friend.home == place:
			names.append(friend.display_name)
	return "nobody hangs out here yet." if names.is_empty() else ", ".join(names) + " hang%s out here." % ("s" if names.size() == 1 else "")


## Pick where a friend hangs out.
func _choose_home(friend: Resident) -> void:
	var items: Array = []
	for id: String in locations:
		var place: Location = locations[id]
		var mark := "   (current)" if friend.home == place else ""
		items.append({"text": place.display_name + mark, "action": _set_home.bind(friend, place), "location": place})
	items.append({"text": "Anywhere on the map" + ("   (current)" if friend.home == null else ""), "action": _set_home.bind(friend, null)})
	_show_list("Where does %s hang out?" % friend.display_name, items)


func _set_home(friend: Resident, place: Location) -> void:
	_close_friends_sheet()
	if not is_instance_valid(friend):
		return
	friend.home = place
	friend.teleport_home() # pop straight there instead of walking across town
	if place:
		camera_rig.focus_on(friend.global_position)
	_save_world()
	hud_status.text = "%s now hangs out at %s." % [friend.display_name, place.display_name] if place else "%s can wander anywhere now." % friend.display_name


## Bottom bar with a message and up to two buttons (Retry/Remove...).
func _build_action_bar() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	action_bar = PanelContainer.new()
	var style := UiStyle.bubble()
	style.set_content_margin_all(14)
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
		UiFx.add_press_bounce(button)
		action_row.add_child(button)
		made.append(button)
	action_bar.visible = true
	UiFx.pop_in(action_bar, 0.0, 0.9)
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
	if add_form.mode == "place":
		_on_place_submitted(display_name, jpeg, add_form.wants_flag(), add_form.wants_detailed())
		return
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
	if info.get("kind") == "place":
		var place: Location = info.place
		if info.get("style") == "recipe":
			place.status_text = "designing..."
			relay.generate(job, info.jpeg, "generate_place_recipe", [place.display_name])
		else:
			place.status_text = "building 3D..."
			relay.generate(job, info.jpeg, "generate_place")
		return
	(info.resident as Resident).status_text = "building 3D..."
	relay.generate(job, info.jpeg)


## The friend or place a job is building (null if it was removed meanwhile).
func _job_target(job: int) -> Node3D:
	if not _jobs.has(job):
		return null
	var target: Variant = _jobs[job].get("place") if _jobs[job].get("kind") == "place" else _jobs[job].get("resident")
	if target is Node3D and is_instance_valid(target) and not (target as Node3D).is_queued_for_deletion():
		return target
	return null


func _on_relay_finished(job: int, glb: PackedByteArray) -> void:
	if _job_target(job) == null:
		_jobs.erase(job)
		return
	if _jobs[job].get("kind") == "place":
		_on_place_built(job, glb)
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


func _on_place_built(job: int, glb: PackedByteArray) -> void:
	var place: Location = _jobs[job].place
	if _jobs[job].get("style") == "recipe":
		_on_recipe_built(job, glb.get_string_from_utf8())
		return
	var model := GlbLoader.from_bytes(glb, false)
	if model == null:
		_on_relay_failed(job, "The 3D model couldn't be loaded.")
		return
	place.set_generated_model(model)
	place.status_text = ""
	place.remove_meta("job")
	_fly_to_place(place) # re-frame: the real building is bigger than the construction site
	_jobs.erase(job) # drops the photo from memory
	if WorldStore.save_place_model(place.location_id, glb):
		_save_world()
		hud_status.text = "%s is built! Tap a friend, then Home, to have them hang out there." % place.display_name
	else:
		_warn_storage()


## Quick build: the relay sent a recipe; build the low-poly model in code.
func _on_recipe_built(job: int, text: String) -> void:
	var place: Location = _jobs[job].place
	var recipe: Variant = JSON.parse_string(text)
	if not recipe is Dictionary:
		_on_relay_failed(job, "The quick build came back garbled. Please try again.")
		return
	var built := RecipeModel.build(recipe)
	# A flag the player asked for: a known design, else the colours the builder
	# saw (brand colours beat the photo's average colours).
	if _jobs[job].get("wants_flag") and Flag.design_for_name(place.display_name) == null and built.flag != null:
		place.flag_design = built.flag
	place.set_recipe_model(built)
	place.set_meta("recipe", recipe)
	place.status_text = ""
	place.remove_meta("job")
	_jobs.erase(job) # drops the photo from memory
	_glide(place, place.global_position + Vector3(0.0, 2.0, 0.0), place.global_position, true)
	_fly_to_place(place)
	_save_world()
	hud_status.text = "%s is built! Long-press it to move it, or send friends to hang out there." % place.display_name


func _on_relay_failed(job: int, message: String) -> void:
	var target := _job_target(job)
	if target == null:
		_jobs.erase(job)
		return
	_jobs[job].error = message
	if target is Location:
		(target as Location).status_text = "couldn't build"
		_fly_to_place(target)
		_show_place_actions(target) # Retry / Remove right away
		return
	var resident: Resident = target
	resident.status_text = "couldn't build"
	_select(resident) # show Retry / Remove right away


func _retry_job(job: int) -> void:
	var target := _job_target(job)
	if target == null:
		return
	_start_job(job)
	if target is Location:
		_hide_actions()
	else:
		_select(target)


func _discard_job(job: int) -> void:
	var target := _job_target(job)
	_jobs.erase(job) # drops the photo from memory
	if target is Location:
		_delete_place(target)
		return
	if target:
		target.queue_free()
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
		resident.home = locations.get(str(entry.get("home", "")))


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
				"home": resident.home.location_id if resident.home and is_instance_valid(resident.home) else "",
			})
	# Places the player added (only once their model exists).
	var places: Array[Dictionary] = []
	for id: String in locations:
		var place: Location = locations[id]
		if place.user_added and not place.has_meta("job") and not place.is_queued_for_deletion():
			places.append({
				"id": place.location_id,
				"name": place.display_name,
				"x": snappedf(place.position.x, 0.01),
				"z": snappedf(place.position.z, 0.01),
				"yaw": snappedf(place.rotation.y, 0.001),
				"flag": _flag_to_json(place.flag_design),
				"recipe": place.get_meta("recipe") if place.has_meta("recipe") else null,
			})
	# Built-in places: where each one stands now and how it is turned.
	var layout := {}
	for id: String in locations:
		var place: Location = locations[id]
		if not place.user_added and not place.is_queued_for_deletion():
			layout[id] = {"x": snappedf(place.position.x, 0.01), "z": snappedf(place.position.z, 0.01), "yaw": snappedf(place.rotation.y, 0.001)}
	if not WorldStore.save_index(entries, places, layout):
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
	resident.world_radius = WORLD_RADIUS - 2.0
	residents.add_child(resident)
	resident.global_position = at
	if model:
		resident.set_avatar(model)
	return resident


func _spawn_demo() -> void:
	var model := GlbLoader.from_file(DEMO_MODEL)
	if model == null:
		hud_status.text = "Demo model not found. Showing a placeholder."
	# Kevin hangs out at McGill.
	var mcgill: Location = locations.get("mcgill")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var at := mcgill.random_point(rng) if mcgill else Vector3.ZERO
	var kevin := spawn_resident(DEMO_NAME, model, at)
	kevin.home = mcgill
	# A second built-in friend: Stephen Chen (IDOL splat converted with
	# scripts/splat_to_glb.py), also at McGill. Skipped if his model is missing.
	var stephen_model := GlbLoader.from_file(DEMO_MODEL_2)
	if stephen_model:
		var stephen := spawn_resident(DEMO_NAME_2, stephen_model, mcgill.random_point(rng) if mcgill else Vector3(1.5, 0.0, 1.5))
		stephen.home = mcgill
	# Third built-in friend: Jeremy Bettez (same conversion), also at McGill.
	var jeremy_model := GlbLoader.from_file(DEMO_MODEL_3)
	if jeremy_model:
		var jeremy := spawn_resident(DEMO_NAME_3, jeremy_model, mcgill.random_point(rng) if mcgill else Vector3(-1.5, 0.0, 1.5))
		jeremy.home = mcgill


func _on_tapped(screen_pos: Vector2) -> void:
	var friend := _resident_at(screen_pos)
	_select(friend)
	# Tapping a building shows what you can do with it (Rotate, Remove).
	if friend == null:
		var place := _place_at(screen_pos)
		if place:
			_show_place_actions(place)


## The friend under a screen point, or null.
func _resident_at(screen_pos: Vector2) -> Resident:
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(screen_pos)
	var to := from + cam.project_ray_normal(screen_pos) * 200.0
	# Only look for friends, so buildings in the way don't block picking them.
	var query := PhysicsRayQueryParameters3D.create(from, to, Resident.FRIEND_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
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


# --- Moving buildings anywhere on the land -------------------------------------

const CARRY_HEIGHT := 0.9 # a carried building floats this high
const EDGE_PAN := 70.0 # pixels from the screen edge that pan the view
const EDGE_PAN_SPEED := 16.0 # m/s at the very edge


## The building (Location) under a screen point, or null. Buildings have walls
## on physics layer 1.
func _place_at(screen_pos: Vector2) -> Location:
	var cam := camera_rig.camera
	var from := cam.project_ray_origin(screen_pos)
	var query := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(screen_pos) * 300.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var node: Node = hit.get("collider") if not hit.is_empty() else null
	while node and not node is Location:
		node = node.get_parent()
	return node as Location


func _start_move(place: Location) -> void:
	_select(null)
	_hide_actions()
	_moving = place
	_move_from = place.global_position
	_drop_at = _move_from
	_drop_ok = true
	_set_walls_enabled(place, false) # don't shove friends around mid-air
	if _drop_marker == null:
		_drop_marker = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_drop_marker.material_override = mat
		locations_root.add_child(_drop_marker)
	# The marker is the building's footprint (plus its clear ground) on the grass.
	var slab := BoxMesh.new()
	var area := place.footprint.grow(PLACE_GAP)
	slab.size = Vector3(area.size.x, 0.03, area.size.y)
	_drop_marker.mesh = slab
	_drop_marker.visible = false
	hud_status.text = "Drag %s anywhere with room. Let go to put it down." % place.display_name


## Each frame while carrying: pan at the screen edges, float the building under
## the finger, and show where it would land: yellow if it fits, red if not.
func _carry_step(delta: float) -> void:
	if not is_instance_valid(_moving):
		_moving = null
		return
	if _move_finger.x < 0.0:
		return
	var view := get_viewport().get_visible_rect().size
	var push := Vector2.ZERO
	push.x = clampf((EDGE_PAN - _move_finger.x) / EDGE_PAN, 0.0, 1.0) * -1.0 + clampf((_move_finger.x - (view.x - EDGE_PAN)) / EDGE_PAN, 0.0, 1.0)
	push.y = clampf((EDGE_PAN - _move_finger.y) / EDGE_PAN, 0.0, 1.0) * -1.0 + clampf((_move_finger.y - (view.y - EDGE_PAN)) / EDGE_PAN, 0.0, 1.0)
	if push != Vector2.ZERO:
		camera_rig.nudge(Vector3(push.x, 0.0, push.y) * EDGE_PAN_SPEED * delta)
	var point: Variant = _ground_point(_move_finger)
	if point is Vector3:
		var goal := Vector3((point as Vector3).x, CARRY_HEIGHT, (point as Vector3).z)
		_moving.global_position = _moving.global_position.lerp(goal, 1.0 - exp(-14.0 * delta))
	var here := _moving.global_position
	_drop_at = Vector3(snappedf(here.x, 0.5), 0.0, snappedf(here.z, 0.5))
	_drop_ok = _spot_free(_moving.world_footprint(PLACE_GAP, _drop_at), _moving)
	_drop_marker.visible = true
	var turn := Basis(Vector3.UP, _moving.rotation.y)
	var centre := _moving.footprint.grow(PLACE_GAP).get_center()
	_drop_marker.global_transform = Transform3D(turn, _drop_at + turn * Vector3(centre.x, 0.0, centre.y)
		+ Vector3(0.0, 0.02 + 0.01 * sin(Time.get_ticks_msec() * 0.008), 0.0))
	(_drop_marker.material_override as StandardMaterial3D).albedo_color = Color(UiStyle.YELLOW, 0.5) if _drop_ok else Color(0.9, 0.3, 0.25, 0.5)


func _finish_move() -> void:
	var place := _moving
	_moving = null
	_move_finger = Vector2(-1.0, -1.0)
	if _drop_marker:
		_drop_marker.visible = false
	if not is_instance_valid(place):
		return
	var lifted := place.global_position
	var from_flat := Vector3(_move_from.x, 0.0, _move_from.z)
	if not _drop_ok or _drop_at.distance_to(from_flat) < 0.3:
		_glide(place, lifted, _move_from)
		_set_walls_enabled(place, true)
		hud_status.text = ("%s stays where it was." if _drop_ok else "No room there, so %s went back.") % place.display_name
		return
	place.position = _drop_at
	_sync_districts()
	_save_world() # before the landing animation moves it through the air
	_glide(place, lifted, _drop_at, true)
	_set_walls_enabled(place, true)
	hud_status.text = "%s moved to %s." % [place.display_name, _district_name(place)]
	# Friends who hang out there head to the new spot.
	for friend in _friends():
		if friend.home == place:
			friend.go_home()


## Animate a building from `from` to where it now belongs (`to`), landing with a
## bounce; `celebrate` adds the golden ring burst as it lands.
func _glide(place: Location, from: Vector3, to: Vector3, celebrate := false) -> void:
	place.global_position = from
	var tween := create_tween()
	tween.tween_property(place, "global_position", to, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if celebrate:
		tween.tween_callback(_ring_burst.bind(to))


## A small golden ring that pops up around a newly placed building, grows,
## rises a little and fades away, with a puff of gold sparkles flying outward.
func _ring_burst(at: Vector3) -> void:
	var gold := Color(1.0, 0.80, 0.25)
	for i in 2: # a bright ring and a softer, later echo
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.82
		torus.outer_radius = 1.0
		torus.rings = 48
		torus.ring_segments = 6
		ring.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(gold, 0.0)
		ring.material_override = mat
		ring.position = at + Vector3(0.0, 0.15, 0.0)
		ring.scale = Vector3.ONE * 1.5
		locations_root.add_child(ring)
		var delay := 0.12 * i
		var tween := create_tween().set_parallel(true)
		tween.tween_property(mat, "albedo_color:a", 0.95 - 0.35 * i, 0.12).set_delay(delay)
		tween.tween_property(ring, "scale", Vector3(7.0, 1.0, 7.0), 0.9).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(ring, "position:y", at.y + 1.2, 0.9).set_delay(delay).set_ease(Tween.EASE_OUT)
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.6).set_delay(delay + 0.35)
		tween.chain().tween_callback(ring.queue_free)
	# Sparkles bursting out and drifting down.
	var sparkles := CPUParticles3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.08
	dot.height = 0.16
	dot.radial_segments = 6
	dot.rings = 3
	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.vertex_color_use_as_albedo = true
	dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dot.material = dot_mat
	sparkles.mesh = dot
	sparkles.one_shot = true
	sparkles.explosiveness = 0.9
	sparkles.amount = 28
	sparkles.lifetime = 1.0
	sparkles.direction = Vector3.UP
	sparkles.spread = 75.0
	sparkles.initial_velocity_min = 3.0
	sparkles.initial_velocity_max = 6.0
	sparkles.gravity = Vector3(0.0, -6.0, 0.0)
	sparkles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	sparkles.emission_ring_axis = Vector3.UP
	sparkles.emission_ring_radius = 3.5
	sparkles.emission_ring_inner_radius = 2.5
	sparkles.emission_ring_height = 0.1
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	fade.colors = PackedColorArray([gold.lightened(0.3), gold, Color(gold, 0.0)])
	sparkles.color_ramp = fade
	sparkles.position = at + Vector3(0.0, 0.3, 0.0)
	locations_root.add_child(sparkles)
	sparkles.emitting = true
	get_tree().create_timer(2.0).timeout.connect(sparkles.queue_free)


func _set_walls_enabled(place: Location, on: bool) -> void:
	for body in place.find_children("*", "StaticBody3D", true, false):
		(body as StaticBody3D).collision_layer = 1 if on else 0


## Put built-in places back where the player moved and turned them.
func _restore_layout() -> void:
	var layout := WorldStore.load_layout()
	for id: String in layout:
		var place: Location = locations.get(id)
		var entry: Variant = layout[id]
		if place == null or place.user_added or not entry is Dictionary:
			continue
		var spot: Variant = _saved_spot(entry)
		if spot is Vector3:
			place.position = spot
			place.rotation.y = float((entry as Dictionary).get("yaw", 0.0))


# --- Picking friends up -------------------------------------------------------

## Called on touch-down: remember who is under the finger, so the grab (which
## starts a moment later) gets that friend even if they've moved since.
func _can_grab(screen_pos: Vector2) -> bool:
	_grab_candidate = _resident_at(screen_pos)
	_place_candidate = null
	return _grab_candidate != null


## Called on touch-down when no friend is under the finger: is it a building?
## (Picked up by a long press; dragging sooner pans the view as usual.)
func _can_hold_grab(screen_pos: Vector2) -> bool:
	_place_candidate = _place_at(screen_pos)
	return _place_candidate != null


func _on_grab_started(screen_pos: Vector2) -> void:
	if _grab_candidate == null and _place_candidate and is_instance_valid(_place_candidate):
		_start_move(_place_candidate)
		_place_candidate = null
		_move_finger = screen_pos
		return
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


func _on_grab_moved(screen_pos: Vector2) -> void:
	if _moving:
		_move_finger = screen_pos
		return
	if _dragged and is_instance_valid(_dragged):
		var point: Variant = _ground_point(screen_pos)
		if point is Vector3:
			_dragged.drag_to(point)


func _on_grab_ended(_screen_pos: Vector2) -> void:
	if _moving:
		_finish_move()
		return
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


func _process(delta: float) -> void:
	# The grass follows the view, so there is always land under it.
	var view := camera_rig.position
	ground.position = Vector3(view.x, 0.0, view.z)
	if _moving:
		_carry_step(delta)
	# Animate the status line whenever its message changes.
	if hud_status.text != _last_status:
		_last_status = hud_status.text
		UiFx.text_in(hud_status)
	if _following:
		if is_instance_valid(_following) and _following.is_held():
			var p := _following.global_position
			camera_rig.focus_on(Vector3(p.x, 0.0, p.z))
		else:
			_following = null


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
	var where := " · at %s" % selected.home.display_name if selected.home and is_instance_valid(selected.home) else ""
	var buttons: Array = [
		["Wave", _ask_to.bind(selected, "wave")],
		["Dance", _ask_to.bind(selected, "dance")],
		["Home", _choose_home.bind(selected)],
	]
	if selected.saved:
		buttons.append(["Remove", _remove_resident.bind(selected)])
	var made := _show_actions(selected.display_name + where, buttons)
	if selected.saved:
		_remove_button = made[3]


## Ask a friend to wave or dance; they turn to face the player first.
func _ask_to(friend: Resident, action: String) -> void:
	if not is_instance_valid(friend):
		return
	if get_tree().paused:
		set_paused(false) # an action you can't see would feel broken
	if action == "dance":
		# With a friend nearby they dance together (moonwalk or party dance);
		# alone, a regular dance or now and then a moonwalk.
		var partner := friend.nearby_friend()
		if partner:
			var style := "moonwalk" if randf() < 0.5 else "party"
			if style == "moonwalk":
				friend.perform(style, camera_rig.camera.global_position)
				partner.perform(style, camera_rig.camera.global_position)
			else:
				friend.perform(style, partner.global_position)
				partner.perform(style, friend.global_position)
			hud_status.text = "%s and %s are %s!" % [friend.display_name, partner.display_name, "moonwalking" if style == "moonwalk" else "partying"]
			return
		action = "moonwalk" if randf() < 0.3 else "dance"
	friend.perform(action, camera_rig.camera.global_position)
	var doing := {"wave": "waving at you", "dance": "dancing", "moonwalk": "moonwalking"}
	hud_status.text = "%s is %s!" % [friend.display_name, doing.get(action, "dancing")]


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
