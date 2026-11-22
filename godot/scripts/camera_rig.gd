class_name CameraRig
extends Node3D
## Orbit camera for touch and mouse.
## One finger (or left mouse) drag: orbit. Two-finger pinch (or wheel): zoom.
## Mouse drags arrive as touch events (input_devices/pointing/emulate_touch_from_mouse).

signal tapped(screen_pos: Vector2)

const ORBIT_SPEED := 0.006
const MIN_PITCH := deg_to_rad(-80.0)
const MAX_PITCH := deg_to_rad(-12.0)
const MIN_DISTANCE := 3.0
const MAX_DISTANCE := 28.0
const TAP_SLOP := 12.0 # pixels a finger may move and still count as a tap
const MOUSE_INDEX := 1000 # touch slot used for a real mouse in browsers

var yaw := deg_to_rad(25.0)
var pitch := deg_to_rad(-30.0)
var distance := 10.0
var camera: Camera3D

var _touches := {} # index -> current position
var _touch_start := {} # index -> start position
var _pinch_start_distance := 0.0
var _pinch_start_zoom := 0.0
var _was_multi := false
var _focus := Vector3.ZERO


func _ready() -> void:
	_focus = position
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
			distance = clampf(distance * 0.9, MIN_DISTANCE, MAX_DISTANCE)
			_apply()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance * 1.1, MIN_DISTANCE, MAX_DISTANCE)
			_apply()
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
		_touches[index] = pos
		_touch_start[index] = pos
		if _touches.size() == 2:
			_was_multi = true
			_start_pinch()
	else:
		var start: Vector2 = _touch_start.get(index, pos)
		var is_tap := not _was_multi and start.distance_to(pos) < TAP_SLOP
		_touches.erase(index)
		_touch_start.erase(index)
		if _touches.is_empty():
			_was_multi = false
		if is_tap:
			tapped.emit(pos)


func _drag(index: int, pos: Vector2, relative: Vector2) -> void:
	if not _touches.has(index):
		return
	_touches[index] = pos
	if _touches.size() == 1:
		yaw -= relative.x * ORBIT_SPEED
		pitch = clampf(pitch - relative.y * ORBIT_SPEED, MIN_PITCH, MAX_PITCH)
		_apply()
	elif _touches.size() == 2:
		var points: Array = _touches.values()
		var d: float = (points[0] as Vector2).distance_to(points[1] as Vector2)
		if _pinch_start_distance > 1.0:
			distance = clampf(_pinch_start_zoom * _pinch_start_distance / maxf(d, 1.0), MIN_DISTANCE, MAX_DISTANCE)
			_apply()


func _start_pinch() -> void:
	var points: Array = _touches.values()
	_pinch_start_distance = (points[0] as Vector2).distance_to(points[1] as Vector2)
	_pinch_start_zoom = distance


## Glide the orbit centre to a point (e.g. a friend picked from the list).
func focus_on(point: Vector3) -> void:
	_focus = point + Vector3(0.0, 1.0, 0.0)


func _process(delta: float) -> void:
	if position.distance_squared_to(_focus) > 0.0001:
		position = position.lerp(_focus, 1.0 - exp(-5.0 * delta))


func _apply() -> void:
	rotation = Vector3(pitch, yaw, 0.0)
	camera.position = Vector3(0.0, 0.0, distance)
