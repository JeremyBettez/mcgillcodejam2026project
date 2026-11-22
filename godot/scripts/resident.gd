class_name Resident
extends CharacterBody3D
## One resident of the world.
## Controls the resident
## Inner `avatar_root`: the loaded GLB (or a placeholder capsule); only this animates.

enum State { IDLE, WALK }

const WALK_SPEED := 0.9
const TURN_SPEED := 6.0
const ARRIVE_DISTANCE := 0.3
const HEIGHT := GlbLoader.TARGET_HEIGHT

var resident_id := ""
var display_name := "Resident":
	set(value):
		display_name = value
		if name_tag:
			name_tag.text = value
var world_radius := 10.0

var avatar_root: Node3D
var name_tag: Label3D
var ring: MeshInstance3D

var _gait := ProceduralGait.new()
var _state := State.IDLE
var _state_time := 0.0
var _target := Vector3.ZERO
var _stuck_time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_rng.randomize()

	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = HEIGHT
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = HEIGHT * 0.5
	add_child(collider)

	avatar_root = Node3D.new()
	avatar_root.name = "Avatar"
	add_child(avatar_root)

	name_tag = Label3D.new()
	name_tag.text = display_name
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.no_depth_test = true
	name_tag.fixed_size = true
	name_tag.pixel_size = 0.0012
	name_tag.font_size = 32
	name_tag.outline_size = 10
	name_tag.position.y = HEIGHT + 0.25
	add_child(name_tag)

	ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.85, 0.2)
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = ring_mat
	ring.position.y = 0.02
	ring.visible = false
	add_child(ring)

	if avatar_root.get_child_count() == 0:
		show_placeholder()
	_enter_idle()


## Replace the avatar with a loaded, normalized GLB scene.
func set_avatar(model: Node3D) -> void:
	_clear_avatar()
	avatar_root.add_child(model)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	var skeleton: Skeleton3D = null
	if not skeletons.is_empty():
		skeleton = skeletons[0] as Skeleton3D
	if not _gait.setup(skeleton):
		push_warning("Resident %s: skeleton not recognized, using simple waddle" % display_name)


## A simple capsule shown while a model is generating or if loading fails.
func show_placeholder(color := Color(0.75, 0.75, 0.8)) -> void:
	_clear_avatar()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.28
	capsule.height = HEIGHT
	body.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	body.material_override = mat
	body.position.y = HEIGHT * 0.5
	avatar_root.add_child(body)
	_gait.setup(null)


func set_selected(selected: bool) -> void:
	ring.visible = selected


func _clear_avatar() -> void:
	for child in avatar_root.get_children():
		avatar_root.remove_child(child)
		child.queue_free()
	avatar_root.position = Vector3.ZERO
	avatar_root.rotation = Vector3.ZERO


func _physics_process(delta: float) -> void:
	_state_time -= delta
	match _state:
		State.IDLE:
			velocity = Vector3.ZERO
			if _state_time <= 0.0:
				_enter_walk()
		State.WALK:
			var to_target := _target - global_position
			to_target.y = 0.0
			if to_target.length() < ARRIVE_DISTANCE or _state_time <= 0.0:
				_enter_idle()
			else:
				var dir := to_target.normalized()
				velocity = dir * WALK_SPEED
				# Model faces -Z: yaw that points -Z along dir.
				var yaw := atan2(-dir.x, -dir.z)
				rotation.y = lerp_angle(rotation.y, yaw, minf(1.0, TURN_SPEED * delta))
	move_and_slide()
	global_position.y = 0.0
	# Blocked by another resident: give up on this target.
	if _state == State.WALK and get_real_velocity().length() < WALK_SPEED * 0.2:
		_stuck_time += delta
		if _stuck_time > 0.8:
			_enter_idle()
	else:
		_stuck_time = 0.0


func _process(delta: float) -> void:
	var walking := _state == State.WALK
	var bob := _gait.apply(delta, walking)
	avatar_root.position.y = bob
	if not _gait.ok:
		# Fallback waddle for unrecognized skeletons and placeholders.
		avatar_root.rotation.z = sin(_gait.phase) * 0.08 * _gait.amount
		avatar_root.position.y = absf(sin(_gait.phase)) * 0.05 * _gait.amount


func _enter_idle() -> void:
	_state = State.IDLE
	_state_time = _rng.randf_range(1.5, 4.0)
	_stuck_time = 0.0


func _enter_walk() -> void:
	_state = State.WALK
	var angle := _rng.randf() * TAU
	var dist := sqrt(_rng.randf()) * world_radius
	_target = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	_state_time = 12.0 # give up if it takes too long
