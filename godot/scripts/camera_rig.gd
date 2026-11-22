class_name CameraRig
extends Node3D
## Fixed-angle town camera for touch and mouse (no orbiting: every building
## faces the camera, like a board you look down on).
## One finger (or left mouse) drag: pan, the ground stays under your finger, and
## a quick flick keeps gliding. Two-finger pinch (or wheel): smooth zoom; the view
## tilts down more as you zoom out. Press on something grabbable (see `can_grab`)
## and hold or drag: grab_* signals instead of panning. A quick tap: `tapped`.
## Mouse drags arrive as touch events (input_devices/pointing/emulate_touch_from_mouse).

signal tapped(screen_pos: Vector2)
signal grab_started(screen_pos: Vector2)
signal grab_moved(screen_pos: Vector2)
signal grab_ended(screen_pos: Vector2)

const HOLD_TIME := 0.22 # seconds a finger must rest on a friend to pick them up
const LONG_HOLD := 0.45 # ...or on a building (dragging sooner pans instead)

const YAW := 0.0 # fixed: looking north (-Z), fronts face +Z
const NEAR_PITCH := deg_to_rad(-24.0) # zoomed in: closer to eye level
const FAR_PITCH := deg_to_rad(-58.0) # zoomed out: more of a map view
const MIN_DISTANCE := 5.0
const MAX_DISTANCE := 70.0
const ZOOM_SMOOTH := 10.0
const FLING_FRICTION := 3.2 # how fast a flick's glide slows down
const MAX_FLING := 35.0 # m/s
const TAP_SLOP := 12.0 # pixels a finger may move and still count as a tap
const MOUSE_INDEX := 1000 # touch slot used for a real mouse in browsers

var distance := 10.0 # current zoom (eases towards _zoom_goal)
var camera: Camera3D
## Where the view centre may go (XZ); empty = anywhere.
var bounds := Rect2()
## How fast the view is moving, in m/s (for effects like the falling leaves).
var velocity := Vector3.ZERO
## func(screen_pos: Vector2) -> bool: is there something to pick up at this point?
var can_grab := Callable()
## func(screen_pos) -> bool: something that can only be picked up by a long
## press (buildings), so a drag that starts on it still pans the view.
var can_hold_grab := Callable()

var _zoom_goal := 10.0
var _touches := {} # index -> current position
var _touch_start := {} # index -> start position
var _pinch_start_distance := 0.0
var _pinch_start_zoom := 0.0
var _was_multi := false
var _focus := Vector3.ZERO
var _panning := false
var _fling := Vector3.ZERO
var _last_position := Vector3.ZERO
var _pending_index := -1
var _pending_time := 0.0
var _hold_only := false # the pending grab needs a long, still press
var _grab_index := -1


func _ready() -> void:
	_focus = position
	_last_position = position
	_zoom_goal = distance
	camera = Camera3D.new()
	camera.fov = 55.0
	add_child(camera)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		_touch(touch.index, touch.pressed, touch.position)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_drag(drag.index, drag.position, drag.relative)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_goal = clampf(_zoom_goal * 0.88, MIN_DISTANCE, MAX_DISTANCE)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_goal = clampf(_zoom_goal * 1.14, MIN_DISTANCE, MAX_DISTANCE)
		elif mb.button_index == MOUSE_BUTTON_LEFT and _is_real_web_mouse(mb):
			_touch(MOUSE_INDEX, mb.pressed, mb.position)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _touches.has(MOUSE_INDEX) and _is_real_web_mouse(motion):
			_drag(MOUSE_INDEX, motion.position, motion.relative)


## On desktop builds, mouse input already arrives as touch events
## (emulate_touch_from_mouse). In browsers that setting has no effect, so real
## mouse input is handled here; mouse events the browser derives from a touch
## (device == DEVICE_ID_EMULATION) are skipped so a phone tap isn't counted twice.
func _is_real_web_mouse(event: InputEvent) -> bool:
	return OS.has_feature("web") and event.device != InputEvent.DEVICE_ID_EMULATION


func _touch(index: int, pressed: bool, pos: Vector2) -> void:
	if pressed:
		if _grab_index != -1:
			return # holding a friend: ignore other fingers
		_touches[index] = pos
		_touch_start[index] = pos
		_fling = Vector3.ZERO # a new touch catches a gliding view
		if _touches.size() == 1 and can_grab.is_valid() and can_grab.call(pos):
			_pending_index = index # becomes a grab if held or dragged
			_pending_time = 0.0
			_hold_only = false
		elif _touches.size() == 1 and can_hold_grab.is_valid() and can_hold_grab.call(pos):
			_pending_index = index # becomes a grab only if held still
			_pending_time = 0.0
			_hold_only = true
		elif _touches.size() == 2:
			_pending_index = -1
			_hold_only = false
			_was_multi = true
			_panning = false
			_start_pinch()
	else:
		if index == _grab_index:
			_grab_index = -1
			_touches.erase(index)
			_touch_start.erase(index)
			_was_multi = false
			grab_ended.emit(pos)
			return
		if index == _pending_index:
			_pending_index = -1
		var start: Vector2 = _touch_start.get(index, pos)
		var is_tap := not _was_multi and start.distance_to(pos) < TAP_SLOP
		_touches.erase(index)
		_touch_start.erase(index)
		if _panning and _touches.is_empty():
			_panning = false
			# Keep gliding with the finger's recent speed.
			_fling = (velocity * Vector3(1, 0, 1)).limit_length(MAX_FLING)
		if _touches.is_empty():
			_was_multi = false
		if is_tap:
			tapped.emit(pos)


func _drag(index: int, pos: Vector2, _relative: Vector2) -> void:
	if not _touches.has(index):
		return
	var previous: Vector2 = _touches[index]
	_touches[index] = pos
	if index == _grab_index:
		grab_moved.emit(pos)
		return
	if index == _pending_index:
		var start: Vector2 = _touch_start.get(index, pos)
		if _hold_only:
			if start.distance_to(pos) < TAP_SLOP:
				return
			_pending_index = -1 # moved before the long press: it's a pan
			_hold_only = false
		elif start.distance_to(pos) >= TAP_SLOP:
			_begin_grab()
			grab_moved.emit(pos)
			return
		else:
			return # small wiggles on a friend shouldn't move the camera
	if _touches.size() == 1 and not _was_multi:
		var start: Vector2 = _touch_start.get(index, pos)
		if not _panning and start.distance_to(pos) < TAP_SLOP:
			return # still might be a tap
		_panning = true
		# Move so the ground point under the finger stays under the finger.
		var from: Variant = _ground_at(previous)
		var to: Variant = _ground_at(pos)
		if from != null and to != null:
			var shift: Vector3 = (from as Vector3) - (to as Vector3)
			_focus = _clamp_to_bounds(_focus + Vector3(shift.x, 0.0, shift.z))
			position = _focus
	elif _touches.size() == 2:
		var points: Array = _touches.values()
		var d: float = (points[0] as Vector2).distance_to(points[1] as Vector2)
		if _pinch_start_distance > 1.0:
			_zoom_goal = clampf(_pinch_start_zoom * _pinch_start_distance / maxf(d, 1.0), MIN_DISTANCE, MAX_DISTANCE)


func _start_pinch() -> void:
	var points: Array = _touches.values()
	_pinch_start_distance = (points[0] as Vector2).distance_to(points[1] as Vector2)
	_pinch_start_zoom = _zoom_goal


## Where a screen point hits the ground (y = 0), or null.
func _ground_at(screen_pos: Vector2) -> Variant:
	return Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))


func _clamp_to_bounds(point: Vector3) -> Vector3:
	if bounds.size == Vector2.ZERO:
		return point
	return Vector3(clampf(point.x, bounds.position.x, bounds.end.x), point.y, clampf(point.z, bounds.position.y, bounds.end.y))


## Glide the view centre to a point (e.g. a friend picked from the list).
func focus_on(point: Vector3) -> void:
	_fling = Vector3.ZERO
	_focus = _clamp_to_bounds(point + Vector3(0.0, 1.0, 0.0))


## Glide to look at `point` from `view_distance` away. The angle is fixed (every
## front faces the camera), so `facing` and `view_pitch` are kept only for older
## callers and ignored.
func view_from(point: Vector3, _facing: Vector3, _view_pitch: float, view_distance: float) -> void:
	focus_on(point)
	_zoom_goal = clampf(view_distance, MIN_DISTANCE, MAX_DISTANCE)


## Slide the view by `offset` (e.g. edge-panning while carrying a building).
func nudge(offset: Vector3) -> void:
	_fling = Vector3.ZERO
	_focus = _clamp_to_bounds(_focus + Vector3(offset.x, 0.0, offset.z))
	position = _focus


func _begin_grab() -> void:
	_grab_index = _pending_index
	_pending_index = -1
	_hold_only = false
	grab_started.emit(_touches.get(_grab_index, Vector2.ZERO))


func is_grabbing() -> bool:
	return _grab_index != -1


func _process(delta: float) -> void:
	if _pending_index != -1:
		_pending_time += delta
		if _pending_time >= (LONG_HOLD if _hold_only else HOLD_TIME):
			_begin_grab()
	# Flick glide, slowing down; stop at the edge of town.
	if _fling.length_squared() > 0.01:
		var next := _clamp_to_bounds(_focus + _fling * delta)
		if not next.is_equal_approx(_focus + _fling * delta):
			_fling = Vector3.ZERO
		_focus = next
		position = _focus
		_fling *= exp(-FLING_FRICTION * delta)
	elif not _panning and position.distance_squared_to(_focus) > 0.0001:
		position = position.lerp(_focus, 1.0 - exp(-5.0 * delta))
	if absf(distance - _zoom_goal) > 0.001:
		distance = lerpf(distance, _zoom_goal, 1.0 - exp(-ZOOM_SMOOTH * delta))
	_apply()
	# Smoothed speed of the view (pans, flicks and glides).
	if delta > 0.0:
		var raw := (position - _last_position) / delta
		velocity = velocity.lerp(raw, 1.0 - exp(-18.0 * delta))
	_last_position = position


func _apply() -> void:
	var t := inverse_lerp(MIN_DISTANCE, MAX_DISTANCE, distance)
	var pitch := lerpf(NEAR_PITCH, FAR_PITCH, sqrt(clampf(t, 0.0, 1.0)))
	rotation = Vector3(pitch, YAW, 0.0)
	camera.position = Vector3(0.0, 0.0, distance)
