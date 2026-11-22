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

var yaw := deg_to_rad(25.0)
var pitch := deg_to_rad(-30.0)
var distance := 10.0
var camera: Camera3D

var _touches := {} # index -> current position
var _touch_start := {} # index -> start position
var _pinch_start_distance := 0.0
var _pinch_start_zoom := 0.0
var _was_multi := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 55.0
	add_child(camera)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touches[touch.index] = touch.position
			_touch_start[touch.index] = touch.position
			if _touches.size() == 2:
				_was_multi = true
				_start_pinch()
		else:
			var start: Vector2 = _touch_start.get(touch.index, touch.position)
			var is_tap := not _was_multi and start.distance_to(touch.position) < TAP_SLOP
			_touches.erase(touch.index)
			_touch_start.erase(touch.index)
			if _touches.is_empty():
				_was_multi = false
			if is_tap:
				tapped.emit(touch.position)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_touches[drag.index] = drag.position
		if _touches.size() == 1:
			yaw -= drag.relative.x * ORBIT_SPEED
			pitch = clampf(pitch - drag.relative.y * ORBIT_SPEED, MIN_PITCH, MAX_PITCH)
			_apply()
		elif _touches.size() == 2:
			var points: Array = _touches.values()
			var d: float = (points[0] as Vector2).distance_to(points[1] as Vector2)
			if _pinch_start_distance > 1.0:
				distance = clampf(_pinch_start_zoom * _pinch_start_distance / maxf(d, 1.0), MIN_DISTANCE, MAX_DISTANCE)
				_apply()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = clampf(distance * 0.9, MIN_DISTANCE, MAX_DISTANCE)
			_apply()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = clampf(distance * 1.1, MIN_DISTANCE, MAX_DISTANCE)
			_apply()


func _start_pinch() -> void:
	var points: Array = _touches.values()
	_pinch_start_distance = (points[0] as Vector2).distance_to(points[1] as Vector2)
	_pinch_start_zoom = distance


func _apply() -> void:
	rotation = Vector3(pitch, yaw, 0.0)
	camera.position = Vector3(0.0, 0.0, distance)
