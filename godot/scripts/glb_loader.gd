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
	return scene


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
