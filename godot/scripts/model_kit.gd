class_name ModelKit
extends RefCounted
## Small helpers for low-poly location models built in code (no assets):
## shared flat materials, boxes, cylinders, trees, a name sign and solid walls.

const TRUNK := Color(0.42, 0.30, 0.20)
const LEAF := Color(0.27, 0.55, 0.28)

var root: Node3D
var _mats := {}


func _init(model_name: String) -> void:
	root = Node3D.new()
	root.name = model_name


func mat(color: Color) -> StandardMaterial3D:
	if not _mats.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		if color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[color] = m
	return _mats[color]


func box(color: Color, size: Vector3, at: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mesh.mesh = b
	mesh.material_override = mat(color)
	mesh.position = at
	(parent if parent else root).add_child(mesh)
	return mesh


func cylinder(color: Color, radius: float, height: float, at: Vector3, sides := 10, parent: Node3D = null) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = sides
	c.rings = 1
	mesh.mesh = c
	mesh.material_override = mat(color)
	mesh.position = at
	(parent if parent else root).add_child(mesh)
	return mesh


## A thin beam from `a` to `b` (a stretched box), for struts, spokes and legs.
func beam(color: Color, a: Vector3, b: Vector3, thickness: float, parent: Node3D = null) -> MeshInstance3D:
	var mesh := box(color, Vector3(thickness, a.distance_to(b), thickness), (a + b) * 0.5, parent)
	var dir := (b - a).normalized()
	var axis := Vector3.UP.cross(dir)
	if axis.length() > 0.0001:
		mesh.quaternion = Quaternion(axis.normalized(), Vector3.UP.angle_to(dir))
	return mesh


func tree(at: Vector3, height := 1.6) -> void:
	cylinder(TRUNK, 0.12, 0.8, at + Vector3(0, 0.4, 0), 6)
	var crown := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.75 * height / 1.6
	cone.height = height
	cone.radial_segments = 8
	cone.rings = 1
	crown.mesh = cone
	crown.material_override = mat(LEAF)
	crown.position = at + Vector3(0, 0.75 + height * 0.5, 0)
	root.add_child(crown)


## A low sign on a stone base with the name in the app font, facing +Z.
func sign(text: String, fill: Color, at: Vector3, width := 2.4) -> void:
	box(Color(0.68, 0.65, 0.58), Vector3(width + 0.2, 0.35, 0.4), at + Vector3(0, 0.175, 0))
	box(fill, Vector3(width, 0.6, 0.12), at + Vector3(0, 0.65, 0))
	var label := Label3D.new()
	label.text = text
	label.font = UiStyle.bold()
	label.font_size = 64
	label.pixel_size = 0.0038
	label.outline_size = 0
	label.modulate = Color.WHITE
	label.position = at + Vector3(0, 0.65, 0.07)
	root.add_child(label)


## Solid box walls (physics layer 1) over `footprint` so friends walk around.
func walls(footprint: Rect2, height: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Walls"
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(footprint.size.x, height, footprint.size.y)
	shape.shape = b
	shape.position = Vector3(footprint.get_center().x, height * 0.5, footprint.get_center().y)
	body.add_child(shape)
	root.add_child(body)
