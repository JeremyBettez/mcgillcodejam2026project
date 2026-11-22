class_name ConstructionModel
extends RefCounted
## Cozy "under construction" lot shown while a place's 3D model is generating:
## a wooden fence, scaffolding, stacked crates, a traffic cone and a sign.
## Faces +Z. A few dozen boxes, cheap on phones.

const WOOD := Color(0.78, 0.60, 0.40)
const WOOD_DARK := Color(0.60, 0.44, 0.28)
const METAL := Color(0.75, 0.77, 0.80)
const CONE := Color(0.98, 0.55, 0.20)
const SIGN := Color(0.98, 0.84, 0.30)
const FOOTPRINT := Rect2(Vector2(-3.0, -2.0), Vector2(6.0, 4.0))


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "Construction"
	var mats := {}
	# Fence around the lot (front left open).
	for x in range(-3, 4):
		_box(root, mats, WOOD_DARK, Vector3(0.1, 0.9, 0.1), Vector3(x, 0.45, -2.0))
		if x != 0 and x != -1:
			_box(root, mats, WOOD_DARK, Vector3(0.1, 0.9, 0.1), Vector3(x, 0.45, 2.0))
	for z in range(-2, 3):
		for x in [-3.0, 3.0]:
			_box(root, mats, WOOD_DARK, Vector3(0.1, 0.9, 0.1), Vector3(x, 0.45, z))
	for rail_y in [0.35, 0.75]:
		_box(root, mats, WOOD, Vector3(6.0, 0.12, 0.06), Vector3(0, rail_y, -2.0))
		_box(root, mats, WOOD, Vector3(0.06, 0.12, 4.0), Vector3(-3.0, rail_y, 0))
		_box(root, mats, WOOD, Vector3(0.06, 0.12, 4.0), Vector3(3.0, rail_y, 0))
		_box(root, mats, WOOD, Vector3(2.0, 0.12, 0.06), Vector3(-2.0, rail_y, 2.0))
		_box(root, mats, WOOD, Vector3(2.0, 0.12, 0.06), Vector3(2.0, rail_y, 2.0))
	# Scaffolding tower.
	for corner in [Vector2(-1.4, -1.0), Vector2(1.4, -1.0), Vector2(-1.4, 0.6), Vector2(1.4, 0.6)]:
		_box(root, mats, METAL, Vector3(0.08, 3.2, 0.08), Vector3(corner.x, 1.6, corner.y))
	for level in [1.1, 2.2, 3.2]:
		_box(root, mats, WOOD, Vector3(3.0, 0.08, 1.8), Vector3(0, level, -0.2))
	# Crates and a cone.
	_box(root, mats, WOOD, Vector3(0.7, 0.7, 0.7), Vector3(-2.1, 0.35, 0.9))
	_box(root, mats, WOOD, Vector3(0.6, 0.6, 0.6), Vector3(-2.0, 1.0, 0.8))
	_box(root, mats, WOOD_DARK, Vector3(0.7, 0.5, 0.7), Vector3(2.2, 0.25, 1.0))
	var cone := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.22
	cyl.height = 0.55
	cyl.radial_segments = 10
	cyl.rings = 1
	cone.mesh = cyl
	cone.material_override = _mat(mats, CONE)
	cone.position = Vector3(0.6, 0.275, 2.6)
	root.add_child(cone)
	# Sign on two posts out front.
	_box(root, mats, WOOD_DARK, Vector3(0.08, 1.1, 0.08), Vector3(-1.0, 0.55, 2.5))
	_box(root, mats, WOOD_DARK, Vector3(0.08, 1.1, 0.08), Vector3(-0.2, 0.55, 2.5))
	_box(root, mats, SIGN, Vector3(1.2, 0.5, 0.06), Vector3(-0.6, 1.0, 2.53))
	var text := Label3D.new()
	text.text = "Coming\nsoon!"
	text.font = UiStyle.bold()
	text.font_size = 48
	text.pixel_size = 0.004
	text.outline_size = 0
	text.modulate = UiStyle.BROWN
	text.position = Vector3(-0.6, 1.0, 2.57)
	root.add_child(text)
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
