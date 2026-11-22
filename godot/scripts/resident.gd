class_name Resident
extends CharacterBody3D
## One resident ("friend") of the world.
## Outer body: position, wandering, collision, name tag, selection ring, drop shadow.
## Inner `avatar_root`: the loaded GLB (or a placeholder capsule); only this animates.
##
## States: IDLE -> WALK / ACT (wave, dance) on its own. The player can pick a
## friend up (HELD: lifted, follows the finger, dangles like a ragdoll) and let
## go (FALLING: drops with gravity, one bounce, then back to IDLE).

enum State { IDLE, WALK, ACT, HELD, FALLING }

const WAVE_TIME := 3.0
const DANCE_TIME := 5.0
const SPONTANEOUS_WAVE := 0.12 # chance per idle pause
const SPONTANEOUS_DANCE := 0.08
const WALK_SPEED := 0.9
const TURN_SPEED := 6.0
const ARRIVE_DISTANCE := 0.3
const HEIGHT := GlbLoader.TARGET_HEIGHT
const HOLD_HEIGHT := 1.3 # feet height while held
const HOLD_FOLLOW := 14.0 # how quickly a held friend follows the finger
const GRAVITY := 14.0
const FACE_SPEED := 8.0 # how fast a held friend turns to face the camera
# Throwing
const THROW_SMOOTHING := 18.0 # hand-velocity smoothing (higher = more recent)
const THROW_MAX_SPEED := 12.0 # m/s
const THROW_LIFT := 0.35 # upward speed added per unit of throw speed
const TUMBLE_PER_SPEED := 1.0 # rad/s of end-over-end spin per m/s of throw
const TUMBLE_MAX := 9.0 # rad/s
const AIR_DRAG := 0.25
const RESTITUTION := 0.45 # bounce height kept each bounce
const MIN_BOUNCE_SPEED := 1.2 # slower impacts stop bouncing and skid instead
const BOUNCE_FRICTION := 0.75 # sideways speed kept per bounce
const GROUND_FRICTION := 7.0 # m/s^2 while skidding
const EDGE_BOUNCE := 0.5 # how springy the world edge is
const HARD_LANDING := 7.0 # impact speed that leaves them dazed for a moment
const AIR_SUBSTEP := 1.0 / 120.0 # max seconds per flight sub-step
const SPIN_DRAG := 0.35 # spin slowdown in the air (per second)
const BOUNCE_SPIN_KEEP := 0.8 # spin kept on each bounce
const UPRIGHT_SPRING := 60.0 # how firmly the body rolls back onto its feet
const UPRIGHT_DAMP := 15.5 # ~critical damping for the spring above (2*sqrt(60))
# Ragdoll swing: a damped pendulum hanging from the head, driven by acceleration.
const SWING_SPRING := 30.0
const SWING_DAMP := 2.2
const SWING_GAIN := 0.24
const SWING_MAX := 1.1
const SWING_VEL_SMOOTHING := 25.0

var resident_id := ""
var display_name := "Resident":
	set(value):
		display_name = value
		_update_tag()
## Second line under the name, e.g. "building 3D..." while a model generates.
var status_text := "":
	set(value):
		status_text = value
		_update_tag()
var saved := false # true for residents stored in the player's world (removable)
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
var _face_point: Variant = null # Vector3 to turn toward while performing
var _act_time := 0.0

var _collider: CollisionShape3D
var _shadow: MeshInstance3D
var _hold_target := Vector3.ZERO
var _fall_velocity := Vector3.ZERO
var _hand_velocity := Vector3.ZERO # smoothed while held; becomes the throw
var _impact_peak := 0.0
var _tumble_axis_world := Vector3.RIGHT
var _tumble_speed := 0.0
var _tumble_angle := 0.0
var _prev_pos := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _swing := Vector2.ZERO
var _swing_vel := Vector2.ZERO
var _dangle := 0.0 # 0..1 how much the ragdoll pose/swing applies
var _squash := 0.0 # landing squash, 1 -> 0


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_rng.randomize()

	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = HEIGHT
	_collider = CollisionShape3D.new()
	_collider.shape = shape
	_collider.position.y = HEIGHT * 0.5
	add_child(_collider)

	avatar_root = Node3D.new()
	avatar_root.name = "Avatar"
	add_child(avatar_root)

	name_tag = Label3D.new()
	_update_tag()
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

	# Soft round shadow on the ground, shown while lifted so you can see where they'll land.
	_shadow = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.4
	disc.bottom_radius = 0.4
	disc.height = 0.01
	disc.radial_segments = 24
	disc.rings = 1
	_shadow.mesh = disc
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0.0, 0.0, 0.0, 0.3)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow.material_override = shadow_mat
	_shadow.top_level = true
	_shadow.visible = false
	add_child(_shadow)

	if avatar_root.get_child_count() == 0:
		show_placeholder()
	_prev_pos = global_position
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


func _update_tag() -> void:
	if name_tag:
		name_tag.text = display_name if status_text.is_empty() else "%s\n(%s)" % [display_name, status_text]


func set_selected(selected: bool) -> void:
	ring.visible = selected


func _clear_avatar() -> void:
	for child in avatar_root.get_children():
		avatar_root.remove_child(child)
		child.queue_free()
	avatar_root.transform = Transform3D.IDENTITY


# --- Picking up and dropping ---------------------------------------------------

## Lift this friend off the ground; they then follow `drag_to` until `drop`.
func pick_up() -> void:
	_gait.stop_action()
	_state = State.HELD
	_hold_target = Vector3(global_position.x, 0.0, global_position.z)
	_collider.disabled = true # don't shove other friends while flying overhead
	velocity = Vector3.ZERO
	_hand_velocity = Vector3.ZERO
	_tumble_speed = 0.0
	_tumble_angle = 0.0


## Ground point (y = 0) the held friend should hang above.
func drag_to(ground_point: Vector3) -> void:
	_hold_target = Vector3(ground_point.x, 0.0, ground_point.z)


## Let go. The finger's recent velocity carries over: a still finger just drops
## them, a flick throws them in an arc, tumbling. Returns the throw speed (m/s).
func drop() -> float:
	if _state != State.HELD:
		return 0.0
	_state = State.FALLING
	var throw := Vector3(_hand_velocity.x, 0.0, _hand_velocity.z).limit_length(THROW_MAX_SPEED)
	var speed := throw.length()
	throw.y = speed * THROW_LIFT # a flick also lobs them upward
	_fall_velocity = throw
	_impact_peak = 0.0
	# Tumble end over end around the axis perpendicular to the throw.
	if speed > 1.0:
		_tumble_axis_world = Vector3(throw.z, 0.0, -throw.x).normalized()
		_tumble_speed = minf(speed * TUMBLE_PER_SPEED, TUMBLE_MAX)
	else:
		_tumble_speed = 0.0
	return speed


func is_held() -> bool:
	return _state == State.HELD or _state == State.FALLING


func _physics_process(delta: float) -> void:
	# Walking uses the physics tick (move_and_slide); held/thrown motion runs in _process.
	if not is_held():
		_ground_physics(delta)


## Held/thrown motion runs every rendered frame (not on the fixed physics tick)
## so it stays smooth at any frame rate, split into small sub-steps so bounces
## and spin stay stable even when a phone drops frames.
func _air_frame(delta: float) -> void:
	var steps := clampi(ceili(delta / AIR_SUBSTEP), 1, 8)
	var dt := delta / steps
	for i in steps:
		if not is_held():
			break
		_air_step(dt)


func _air_step(delta: float) -> void:
	if _state == State.HELD:
		var before := global_position
		var goal := _hold_target + Vector3(0.0, HOLD_HEIGHT, 0.0)
		global_position = before.lerp(goal, 1.0 - exp(-HOLD_FOLLOW * delta))
		# Smoothed hand velocity, used as the throw when let go.
		var vel := (global_position - before) / maxf(delta, 0.0001)
		_hand_velocity = _hand_velocity.lerp(vel, 1.0 - exp(-THROW_SMOOTHING * delta))
		_face_camera(delta)
		return

	# FALLING / skidding: gravity, air drag, tumbling, bounces, ground friction.
	var v := _fall_velocity
	v.y -= GRAVITY * delta
	var drag := exp(-AIR_DRAG * delta)
	v.x *= drag
	v.z *= drag
	var pos := global_position + v * delta
	# Bounce off the edge of the world instead of flying off it.
	var flat := Vector2(pos.x, pos.z)
	if flat.length() > world_radius:
		var normal := flat.normalized()
		flat = normal * world_radius
		pos.x = flat.x
		pos.z = flat.y
		var hv := Vector2(v.x, v.z)
		var outward := hv.dot(normal)
		if outward > 0.0:
			hv -= normal * outward * (1.0 + EDGE_BOUNCE)
			v.x = hv.x
			v.z = hv.y
	var grounded := pos.y <= 0.0
	if grounded:
		pos.y = 0.0
		var impact := -v.y
		_impact_peak = maxf(_impact_peak, impact)
		if impact > MIN_BOUNCE_SPEED:
			# Bounce: lose energy, scrub some sideways speed and a little spin.
			v.y = impact * RESTITUTION
			v.x *= BOUNCE_FRICTION
			v.z *= BOUNCE_FRICTION
			_tumble_speed *= BOUNCE_SPIN_KEEP
			_gait.impulse(clampf(impact / 8.0, 0.2, 1.0)) # limbs flop on impact
			_squash = maxf(_squash, clampf(impact / 8.0, 0.35, 1.0))
			grounded = false
		else:
			# On the ground: skid to a stop.
			v.y = 0.0
			var hv := Vector2(v.x, v.z).move_toward(Vector2.ZERO, GROUND_FRICTION * delta)
			v.x = hv.x
			v.z = hv.y
	_fall_velocity = v
	global_position = pos
	_spin_step(delta, grounded)
	# Done once they've stopped sliding and rolled back onto their feet.
	if grounded and Vector2(v.x, v.z).length() < 0.15 and _is_upright():
		_land()


## Spin: in the air it keeps going with a little drag; on the ground a critically
## damped spring rolls the body onto the nearest upright angle, so it never snaps.
func _spin_step(delta: float, grounded: bool) -> void:
	if grounded:
		var target := roundf(_tumble_angle / TAU) * TAU
		var accel := UPRIGHT_SPRING * (target - _tumble_angle) - UPRIGHT_DAMP * _tumble_speed
		_tumble_speed += accel * delta
	else:
		_tumble_speed *= exp(-SPIN_DRAG * delta)
	_tumble_angle += _tumble_speed * delta


func _is_upright() -> bool:
	var target := roundf(_tumble_angle / TAU) * TAU
	return absf(_tumble_angle - target) < 0.05 and absf(_tumble_speed) < 0.5


func _land() -> void:
	_squash = maxf(_squash, 0.4)
	_collider.disabled = false
	_fall_velocity = Vector3.ZERO
	_tumble_angle = wrapf(_tumble_angle, -PI, PI) # finish settling from here
	_enter_idle()
	if _impact_peak > HARD_LANDING:
		_state_time += 1.2 # catch their breath after a big throw


## After landing, finish any last bit of the roll with the same spring.
func _recover_from_tumble(delta: float) -> void:
	if _tumble_angle == 0.0 and _tumble_speed == 0.0:
		return
	_spin_step(delta, true)
	if absf(_tumble_angle) < 0.002 and absf(_tumble_speed) < 0.01:
		_tumble_angle = 0.0
		_tumble_speed = 0.0


## While held, turn to look at the player.
func _face_camera(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to_cam := cam.global_position - global_position
	if Vector2(to_cam.x, to_cam.z).length() > 0.1:
		# Model faces -Z: yaw that points -Z at the camera.
		rotation.y = lerp_angle(rotation.y, atan2(-to_cam.x, -to_cam.z), minf(1.0, FACE_SPEED * delta))


func _ground_physics(delta: float) -> void:
	_state_time -= delta
	match _state:
		State.IDLE:
			velocity = Vector3.ZERO
			if _state_time <= 0.0:
				# Now and then a friend waves or dances on their own.
				var roll := _rng.randf()
				if roll < SPONTANEOUS_WAVE:
					perform("wave")
				elif roll < SPONTANEOUS_WAVE + SPONTANEOUS_DANCE:
					perform("dance")
				else:
					_enter_walk()
		State.ACT:
			velocity = Vector3.ZERO
			if _face_point is Vector3:
				var to_face: Vector3 = (_face_point as Vector3) - global_position
				if Vector2(to_face.x, to_face.z).length() > 0.1:
					rotation.y = lerp_angle(rotation.y, atan2(-to_face.x, -to_face.z), minf(1.0, TURN_SPEED * delta))
			if _state_time <= 0.0:
				_enter_idle()
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


## Damped pendulum hanging from the head: moving the friend makes the body lag
## and swing, then settle. Driven by the body's acceleration in its own frame.
func _update_swing(delta: float) -> void:
	if delta <= 0.0:
		return
	# Smooth the velocity before differentiating, so uneven frame times don't
	# turn into jittery acceleration (and a jittery swing).
	var raw_vel := (global_position - _prev_pos) / delta
	var vel := _prev_vel.lerp(raw_vel, 1.0 - exp(-SWING_VEL_SMOOTHING * delta))
	var accel := ((vel - _prev_vel) / delta).limit_length(60.0)
	_prev_pos = global_position
	_prev_vel = vel
	var airborne := _state == State.HELD or _state == State.FALLING
	_dangle = move_toward(_dangle, 1.0 if airborne else 0.0, delta * (6.0 if airborne else 3.0))
	var local := global_transform.basis.inverse() * accel if airborne else Vector3.ZERO
	var force := Vector2(local.z, -local.x) * SWING_GAIN
	_swing_vel += (force - _swing * SWING_SPRING - _swing_vel * SWING_DAMP) * delta
	_swing = (_swing + _swing_vel * delta).clamp(Vector2(-SWING_MAX, -SWING_MAX), Vector2(SWING_MAX, SWING_MAX))


## Play "wave" or "dance". If `face_point` is a Vector3 (e.g. the camera), turn toward it.
func perform(action: String, face_point: Variant = null) -> void:
	if action not in ProceduralGait.ACTIONS or is_held():
		return
	var duration := WAVE_TIME if action == "wave" else DANCE_TIME
	_gait.play(action, duration)
	_state = State.ACT
	_state_time = duration + 0.3 # let the pose blend out before walking on
	_face_point = face_point
	_act_time = 0.0


func is_performing() -> bool:
	return _state == State.ACT


func _process(delta: float) -> void:
	if is_held():
		_air_frame(delta)
	else:
		_recover_from_tumble(delta)
	_update_swing(delta)
	_gait.dangle_weight = _dangle
	_gait.swing = _swing * _dangle
	# Limb flailing: frantic while held, wild in flight, just twitching while skidding.
	if _state == State.HELD:
		_gait.struggle = 1.0
	elif _state == State.FALLING:
		_gait.struggle = 0.75 if global_position.y > 0.02 else 0.2
	else:
		_gait.struggle = 0.2
	_gait.tumble_rate = _tumble_speed
	var bob := _gait.apply(delta, _state == State.WALK)
	var offset := Vector3(0.0, bob, 0.0)
	var body_basis := Basis.IDENTITY
	if not _gait.ok:
		# Fallback for unrecognized skeletons and placeholders: waddle while walking,
		# rock side to side for a wave, hop and spin for a dance.
		_act_time += delta
		var w := _gait.action_weight
		var rock := sin(_act_time * 10.0) * 0.15 * w if _gait.action == "wave" else 0.0
		var spin := _act_time * TAU * 0.5 * w if _gait.action == "dance" else 0.0
		body_basis = Basis.from_euler(Vector3(0.0, spin, sin(_gait.phase) * 0.08 * _gait.amount + rock))
		offset.y = absf(sin(_gait.phase)) * 0.05 * _gait.amount
		if _gait.action == "dance":
			offset.y += absf(sin(_act_time * TAU * 2.0)) * 0.12 * w
	if _dangle > 0.001:
		# Whole body swings from a pivot at the top of the head.
		var swing_basis := Basis.from_euler(Vector3(_swing.x, 0.0, _swing.y) * _dangle)
		var pivot := Vector3(0.0, HEIGHT * 0.95, 0.0)
		offset += pivot - swing_basis * pivot
		body_basis = swing_basis * body_basis
	if _tumble_angle != 0.0:
		# End-over-end spin around the body's middle, keeping the lowest point
		# roughly on the ground (lying flat sits lower than standing).
		var axis := (global_transform.basis.inverse() * _tumble_axis_world).normalized()
		if axis.is_normalized():
			var spin := Basis(axis, _tumble_angle)
			var centre := Vector3(0.0, HEIGHT * 0.5, 0.0)
			offset = spin * (offset - centre) + centre
			body_basis = spin * body_basis
			var c := absf(cos(_tumble_angle))
			var s := absf(sin(_tumble_angle))
			offset.y += (HEIGHT * 0.5 * c + 0.15 * s) - HEIGHT * 0.5
	if _squash > 0.0:
		var s := sin(_squash * PI) * 0.5 + _squash * 0.1
		body_basis = body_basis * Basis.from_scale(Vector3(1.0 + 0.15 * s, 1.0 - 0.22 * s, 1.0 + 0.15 * s))
		_squash = move_toward(_squash, 0.0, delta * 3.0)
	avatar_root.transform = Transform3D(body_basis, offset)

	var height := global_position.y
	_shadow.visible = height > 0.05
	if _shadow.visible:
		var shrink := clampf(1.0 - height * 0.25, 0.5, 1.0)
		_shadow.global_transform = Transform3D(Basis.from_scale(Vector3(shrink, 1.0, shrink)), Vector3(global_position.x, 0.01, global_position.z))


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
