class_name GlbLoader
extends RefCounted
## Loads a GLB at runtime (from bytes or a file) and normalizes it:
## scaled to TARGET_HEIGHT, feet on y = 0, centered on x/z.
## Used for both the bundled demo model and models generated on the phone.

const TARGET_HEIGHT := 1.7


static func from_file(path: String) -> Node3D:
	if not FileAccess.file_exists(path):
		push_warning("GlbLoader: missing file %s" % path)
		return null
	return from_bytes(FileAccess.get_file_as_bytes(path))


## `normalize` = scale to TARGET_HEIGHT with feet on the ground (friends). Places
## pass false and fit the model themselves (Location.set_generated_model).
static func from_bytes(bytes: PackedByteArray, normalize := true) -> Node3D:
	if bytes.is_empty():
		push_warning("GlbLoader: empty buffer")
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_buffer(bytes, "", state)
	if err != OK:
		push_warning("GlbLoader: append_from_buffer failed (%s)" % error_string(err))
		return null
	var scene := doc.generate_scene(state) as Node3D
	if scene == null:
		push_warning("GlbLoader: generate_scene returned nothing")
		return null
	if normalize:
		_normalize(scene)
	_style_points(scene)
	_use_vertex_colors(scene)
	return scene


## Meshes coloured per vertex with no texture (e.g. splat_to_glb.py's smooth
## meshes): make sure their material shows those colours.
static func _use_vertex_colors(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(i) == Mesh.PRIMITIVE_POINTS:
				continue
			if not (mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR):
				continue
			var material := mesh.surface_get_material(i) as StandardMaterial3D
			if material == null:
				material = StandardMaterial3D.new()
				mesh.surface_set_material(i, material)
			if material.albedo_texture == null:
				material.vertex_color_use_as_albedo = true
				material.roughness = 0.9


## Point-cloud models (e.g. an IDOL splat converted by scripts/splat_to_glb.py):
## glTF POINTS primitives have no surface, so each point is drawn as a square
## dot in its vertex colour. The Compatibility renderer ignores POINT_SIZE from
## shaders, so a material with use_point_size is used, and a small PointSizer
## node resizes the dots every frame to stay about POINT_WORLD_SIZE metres
## across whatever the zoom. Skinning still applies, so they animate normally.
const POINT_WORLD_SIZE := 0.03


## Keeps a point-cloud's dots about `world_size` metres wide on screen.
class PointSizer extends Node3D:
	var material: StandardMaterial3D
	var world_size := 0.03

	func _process(_delta: float) -> void:
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam == null or material == null:
			return
		var distance := maxf(cam.global_position.distance_to(global_position), 0.3)
		var pixels_per_metre := get_viewport().get_visible_rect().size.y / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))
		var scale_factor := global_transform.basis.get_scale().y
		material.point_size = clampf(world_size * scale_factor * pixels_per_metre / distance, 1.0, 16.0)


static func _style_points(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		var mesh := mesh_instance.mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		if mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_POINTS:
			continue
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.use_point_size = true
		material.point_size = 3.0
		mesh_instance.material_override = material
		var sizer := PointSizer.new()
		sizer.name = "PointSizer"
		sizer.material = material
		# World size in the model's own units: the root is scaled to 1.7 m later,
		# and the sizer reads that scale back from its global transform.
		sizer.world_size = POINT_WORLD_SIZE / GlbLoader.TARGET_HEIGHT * mesh_bounds(root).size.y if mesh_bounds(root).size.y > 0.0 else POINT_WORLD_SIZE
		mesh_instance.add_child(sizer)


static func _normalize(scene: Node3D) -> void:
	var box := mesh_bounds(scene)
	if box.size.y <= 0.0001:
		return
	var s := TARGET_HEIGHT / box.size.y
	var center := box.get_center()
	scene.scale = Vector3.ONE * s
	scene.position = Vector3(-center.x * s, -box.position.y * s, -center.z * s)


## Bounds of every mesh under root, in root's local space (root's own transform ignored).
static func mesh_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var xf: Transform3D = item[1]
		if node is MeshInstance3D:
			var box: AABB = xf * (node as MeshInstance3D).get_aabb()
			result = box if first else result.merge(box)
			first = false
		for child in node.get_children():
			if child is Node3D:
				stack.append([child, xf * (child as Node3D).transform])
	return result
