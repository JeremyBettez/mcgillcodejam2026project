class_name OratoryModel
extends RefCounted
## Saint Joseph's Oratory, built in code: the great stone basilica up on the
## mountainside with its huge green copper dome, a columned front, the long
## staircase leading up to it, and a cross on top. Faces +Z.

const STONE := Color(0.80, 0.77, 0.70)
const STONE_DARK := Color(0.66, 0.63, 0.57)
const COPPER := Color(0.40, 0.64, 0.56)
const WINDOW := Color(0.22, 0.25, 0.32)

## Footprint of the solid part (terrace, basilica and stairs) in local XZ.
const FOOTPRINT := Rect2(Vector2(-4.8, -3.6), Vector2(9.6, 6.8))


static func build() -> Node3D:
	var kit := ModelKit.new("Oratory")
	# Raised terrace (the mountainside) with stairs up the front.
	kit.box(STONE_DARK, Vector3(9.6, 1.2, 5.0), Vector3(0, 0.6, -1.1))
	for i in 6:
		var depth := 0.3
		kit.box(STONE, Vector3(3.2, 0.2 * (i + 1), depth), Vector3(0, 0.1 * (i + 1), 3.0 - i * depth))
	# Basilica body, a lower apse behind, and side wings.
	kit.box(STONE, Vector3(5.6, 3.4, 3.6), Vector3(0, 2.9, -1.4))
	for side in [-1.0, 1.0]:
		kit.box(STONE, Vector3(1.6, 2.4, 3.0), Vector3(3.5 * side, 2.4, -1.6))
		for z in [-2.4, -1.2]:
			kit.box(WINDOW, Vector3(0.05, 0.9, 0.4), Vector3(4.31 * side, 2.6, z))
	# Front portico: columns, entablature and a pediment.
	for x in [-1.8, -1.0, -0.2, 0.6, 1.4]:
		kit.cylinder(STONE, 0.17, 2.6, Vector3(x + 0.2, 2.5, 0.55), 10)
	kit.box(STONE_DARK, Vector3(4.6, 0.35, 0.8), Vector3(0, 3.95, 0.5))
	var pediment := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(4.6, 0.9, 0.8)
	pediment.mesh = prism
	pediment.material_override = kit.mat(STONE)
	pediment.position = Vector3(0, 4.57, 0.5)
	kit.root.add_child(pediment)
	kit.box(WINDOW, Vector3(1.0, 1.8, 0.05), Vector3(0, 2.1, 0.42))
	# Drum with windows, the big copper dome, lantern and cross.
	kit.cylinder(STONE, 2.0, 1.6, Vector3(0, 5.4, -1.4), 20)
	for i in 10:
		var a := TAU * i / 10.0
		var w := kit.box(WINDOW, Vector3(0.35, 0.8, 0.05), Vector3(sin(a) * 2.01, 5.4, -1.4 + cos(a) * 2.01))
		w.rotation.y = a
	kit.cylinder(STONE_DARK, 2.15, 0.2, Vector3(0, 6.25, -1.4), 20)
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 2.05
	sphere.height = 4.6 # a little taller than a half sphere, like the real one
	sphere.is_hemisphere = true
	sphere.radial_segments = 20
	sphere.rings = 8
	dome.mesh = sphere
	dome.material_override = kit.mat(COPPER)
	dome.position = Vector3(0, 6.35, -1.4)
	kit.root.add_child(dome)
	kit.cylinder(COPPER.darkened(0.15), 0.35, 0.7, Vector3(0, 8.95, -1.4), 10)
	kit.box(Color(0.92, 0.86, 0.60), Vector3(0.08, 0.7, 0.08), Vector3(0, 9.65, -1.4))
	kit.box(Color(0.92, 0.86, 0.60), Vector3(0.4, 0.08, 0.08), Vector3(0, 9.75, -1.4))
	# Evergreens on the mountainside.
	for spot in [Vector3(-5.6, 0, -2.6), Vector3(5.6, 0, -2.4), Vector3(-5.2, 0, 1.8), Vector3(5.4, 0, 1.6)]:
		kit.tree(spot, 2.2)
	kit.walls(FOOTPRINT, 4.0)
	return kit.root
