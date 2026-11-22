class_name OldPortModel
extends RefCounted
## Montreal's Old Port, built in code: the big white Ferris wheel by the river
## (slowly turning, its gondolas always hanging upright) on a wooden boardwalk,
## with the quay, water behind it, lamp posts and an "Old Port" sign.
## Faces +Z (the boardwalk side). About 2.5k triangles.

const WHITE := Color(0.93, 0.94, 0.96)
const STEEL := Color(0.74, 0.77, 0.82)
const PLANK := Color(0.64, 0.48, 0.34)
const QUAY := Color(0.66, 0.64, 0.60)
const WATER := Color(0.36, 0.60, 0.86)
const NAVY := Color(0.17, 0.27, 0.50)
const LAMP := Color(0.25, 0.24, 0.30)
## Gondolas in the app's painted pastel colours.
const POD_COLORS: Array[Color] = [
	Color(0.95, 0.40, 0.48), Color(0.37, 0.61, 0.94), Color(1.0, 0.82, 0.37),
	Color(0.54, 0.44, 0.90), Color(0.45, 0.80, 0.66),
]

const WHEEL_RADIUS := 3.9
const HUB_HEIGHT := 4.7
const PODS := 16
## Footprint of the solid part (wheel base, quay and water) in local XZ.
const FOOTPRINT := Rect2(Vector2(-5.2, -3.6), Vector2(10.4, 4.8))


## Turns the wheel and keeps every gondola level.
class Spinner extends Node3D:
	var pods: Array[Node3D] = []
	var speed := 0.12 # radians per second

	func _process(delta: float) -> void:
		rotation.z = fmod(rotation.z + speed * delta, TAU)
		for pod in pods:
			pod.rotation.z = -rotation.z


static func build() -> Node3D:
	var kit := ModelKit.new("OldPort")

	# River behind, a stone quay, and the boardwalk in front.
	kit.box(WATER, Vector3(12.0, 0.04, 2.0), Vector3(0, 0.02, -2.6))
	kit.box(QUAY, Vector3(12.0, 0.35, 0.5), Vector3(0, 0.17, -1.45))
	kit.box(PLANK, Vector3(11.0, 0.1, 2.6), Vector3(0, 0.05, 0.1))
	for x in range(-5, 6):
		kit.box(PLANK.darkened(0.15), Vector3(0.05, 0.11, 2.6), Vector3(x, 0.055, 0.1))
	kit.box(PLANK, Vector3(1.8, 0.06, 3.6), Vector3(0, 0.03, 3.0)) # path to the front

	# Legs: two A-frames (front and back) up to the hub, and the axle.
	for z in [-0.75, 0.75]:
		for x in [-2.3, 2.3]:
			kit.beam(WHITE, Vector3(x, 0.1, z * 1.6), Vector3(0, HUB_HEIGHT, z), 0.18)
		kit.beam(WHITE, Vector3(-1.4, 1.9, z * 1.25), Vector3(1.4, 1.9, z * 1.25), 0.12)
	var axle := kit.cylinder(STEEL, 0.25, 1.8, Vector3(0, HUB_HEIGHT, 0), 10)
	axle.rotation.x = PI * 0.5

	# The wheel: two rims with spokes, cross ties and hanging gondolas.
	var wheel := Spinner.new()
	wheel.name = "Wheel"
	wheel.position = Vector3(0, HUB_HEIGHT, 0)
	kit.root.add_child(wheel)
	for z in [-0.4, 0.4]:
		var rim := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = WHEEL_RADIUS - 0.09
		torus.outer_radius = WHEEL_RADIUS + 0.09
		torus.rings = 40
		torus.ring_segments = 6
		rim.mesh = torus
		rim.material_override = kit.mat(WHITE)
		rim.rotation.x = PI * 0.5
		rim.position.z = z
		wheel.add_child(rim)
	for i in PODS:
		var angle := TAU * i / PODS
		var out := Vector3(cos(angle), sin(angle), 0.0)
		for z in [-0.4, 0.4]:
			kit.beam(STEEL, Vector3(0, 0, z * 0.6), out * WHEEL_RADIUS + Vector3(0, 0, z), 0.05, wheel)
		kit.beam(WHITE, out * WHEEL_RADIUS + Vector3(0, 0, -0.4), out * WHEEL_RADIUS + Vector3(0, 0, 0.4), 0.07, wheel)
		var pivot := Node3D.new()
		pivot.position = out * WHEEL_RADIUS
		wheel.add_child(pivot)
		wheel.pods.append(pivot)
		var color: Color = POD_COLORS[i % POD_COLORS.size()]
		var pod := kit.box(color, Vector3(0.55, 0.5, 0.55), Vector3(0, -0.42, 0), pivot)
		kit.box(Color(0.2, 0.24, 0.32), Vector3(0.57, 0.2, 0.57), Vector3(0, 0.06, 0), pod) # windows
		kit.box(WHITE, Vector3(0.6, 0.06, 0.6), Vector3(0, 0.27, 0), pod) # roof

	# Lamp posts along the boardwalk and the sign.
	for x in [-4.6, 4.6]:
		kit.cylinder(LAMP, 0.06, 2.2, Vector3(x, 1.1, 1.1), 6)
		kit.box(Color(1.0, 0.9, 0.6), Vector3(0.28, 0.28, 0.28), Vector3(x, 2.3, 1.1))
	kit.sign("Old Port", NAVY, Vector3(-3.0, 0, 3.4), 1.9)
	kit.tree(Vector3(5.6, 0, 3.0))
	kit.tree(Vector3(-5.6, 0, 2.6))

	kit.walls(FOOTPRINT, 3.0)
	return kit.root
