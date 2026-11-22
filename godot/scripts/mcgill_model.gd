class_name McGillModel
extends RefCounted
## Low-poly McGill University campus building, built in code (no assets), in the
## spirit of the Arts Building: limestone main block and wings, a columned portico
## with a pediment, a green copper cupola dome with the McGill flag on top,
## windows, a front path, a red "McGill University" sign and a few trees.
## Faces +Z. A few hundred triangles.
## Also returns a StaticBody3D so friends walk around it, not through it.

const STONE := Color(0.80, 0.77, 0.70)
const STONE_DARK := Color(0.68, 0.65, 0.58)
const ROOF := Color(0.36, 0.38, 0.42)
const COPPER := Color(0.42, 0.66, 0.58)
const WINDOW := Color(0.18, 0.22, 0.28)
const DOOR := Color(0.30, 0.20, 0.14)
const PATH := Color(0.78, 0.74, 0.66)
const MCGILL_RED := Color(0.93, 0.11, 0.19)
const LEAF := Color(0.27, 0.55, 0.28)
const TRUNK := Color(0.42, 0.30, 0.20)

## Footprint of the solid part in local XZ (for Location.footprint).
const FOOTPRINT := Rect2(Vector2(-4.7, -1.4), Vector2(9.4, 3.6))


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "McGill"
	var mats := {}

	# Steps / podium and the main block with two lower wings.
	_box(root, mats, STONE_DARK, Vector3(6.2, 0.3, 3.4), Vector3(0, 0.15, 0.3))
	_box(root, mats, STONE, Vector3(5.0, 2.6, 2.6), Vector3(0, 1.6, 0))
	for side in [-1.0, 1.0]:
		_box(root, mats, STONE, Vector3(2.2, 2.1, 2.4), Vector3(3.55 * side, 1.05, -0.05))
		_box(root, mats, ROOF, Vector3(2.35, 0.2, 2.55), Vector3(3.55 * side, 2.2, -0.05))
	_box(root, mats, ROOF, Vector3(5.2, 0.22, 2.8), Vector3(0, 3.0, 0))

	# Portico: four columns, entablature and a triangular pediment.
	for x in [-1.2, -0.4, 0.4, 1.2]:
		_cylinder(root, mats, STONE, 0.15, 2.3, Vector3(x, 1.45, 1.75), 10)
	_box(root, mats, STONE_DARK, Vector3(3.2, 0.3, 0.7), Vector3(0, 2.75, 1.6))
	var pediment := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(3.3, 0.8, 0.7)
	pediment.mesh = prism
	pediment.material_override = _mat(mats, STONE)
	pediment.position = Vector3(0, 3.3, 1.6)
	root.add_child(pediment)
	_box(root, mats, DOOR, Vector3(0.8, 1.4, 0.05), Vector3(0, 1.0, 1.31))

	# Windows on the front: main block (above/beside the portico) and wings.
	for x in [-2.0, -1.6, 1.6, 2.0]:
		for y in [1.1, 2.2]:
			_box(root, mats, WINDOW, Vector3(0.3, 0.55, 0.05), Vector3(x, y, 1.31))
	for side in [-1.0, 1.0]:
		for x in [2.9, 3.55, 4.2]:
			for y in [0.8, 1.6]:
				_box(root, mats, WINDOW, Vector3(0.32, 0.5, 0.05), Vector3(x * side, y, 1.16))

	# Cupola: drum, columns ring (as a darker band), copper dome and a small spire.
	_cylinder(root, mats, STONE, 0.75, 0.9, Vector3(0, 3.55, 0), 16)
	_cylinder(root, mats, STONE_DARK, 0.8, 0.12, Vector3(0, 4.05, 0), 16)
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.78
	sphere.height = 1.56
	sphere.is_hemisphere = true
	sphere.radial_segments = 16
	sphere.rings = 6
	dome.mesh = sphere
	dome.material_override = _mat(mats, COPPER)
	dome.position = Vector3(0, 4.1, 0)
	root.add_child(dome)
	# McGill flag flying from a pole on top of the dome.
	var flag := Flag.build("mcgill", 1.9, 1.15)
	flag.position = Vector3(0, 4.82, 0)
	root.add_child(flag)

	# Front path and the red McGill sign.
	_box(root, mats, PATH, Vector3(1.6, 0.03, 4.0), Vector3(0, 0.015, 3.9))
	_box(root, mats, STONE_DARK, Vector3(2.4, 0.35, 0.4), Vector3(-2.4, 0.175, 4.2))
	_box(root, mats, MCGILL_RED, Vector3(2.2, 0.6, 0.12), Vector3(-2.4, 0.65, 4.2))
	var sign_text := Label3D.new()
	sign_text.text = "McGill University"
	sign_text.font_size = 64
	sign_text.pixel_size = 0.004
	sign_text.outline_size = 0
	sign_text.modulate = Color.WHITE
	sign_text.position = Vector3(-2.4, 0.65, 4.27)
	root.add_child(sign_text)

	# A few low-poly trees around the lawn.
	for spot in [Vector3(-5.6, 0, 2.6), Vector3(5.6, 0, 2.4), Vector3(-4.2, 0, 4.6), Vector3(4.4, 0, 4.4), Vector3(6.2, 0, -1.2), Vector3(-6.2, 0, -1.0)]:
		_tree(root, mats, spot)

	# Solid walls so friends walk around the building.
	var body := StaticBody3D.new()
	body.name = "Walls"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(FOOTPRINT.size.x, 3.0, FOOTPRINT.size.y)
	shape.shape = box
	shape.position = Vector3(FOOTPRINT.get_center().x, 1.5, FOOTPRINT.get_center().y)
	body.add_child(shape)
	root.add_child(body)
	return root


static func _mat(mats: Dictionary, color: Color) -> StandardMaterial3D:
	if not mats.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.9
		mats[color] = mat
	return mats[color]


static func _box(parent: Node3D, mats: Dictionary, color: Color, size: Vector3, at: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _mat(mats, color)
	mesh.position = at
	parent.add_child(mesh)


static func _cylinder(parent: Node3D, mats: Dictionary, color: Color, radius: float, height: float, at: Vector3, sides: int) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = sides
	cyl.rings = 1
	mesh.mesh = cyl
	mesh.material_override = _mat(mats, color)
	mesh.position = at
	parent.add_child(mesh)


static func _tree(parent: Node3D, mats: Dictionary, at: Vector3) -> void:
	_cylinder(parent, mats, TRUNK, 0.12, 0.8, at + Vector3(0, 0.4, 0), 6)
	var crown := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.75
	cone.height = 1.6
	cone.radial_segments = 8
	cone.rings = 1
	crown.mesh = cone
	crown.material_override = _mat(mats, LEAF)
	crown.position = at + Vector3(0, 1.55, 0)
	parent.add_child(crown)
