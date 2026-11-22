class_name JeanDrapeauModel
extends RefCounted
## Parc Jean-Drapeau, built in code: the big geodesic dome (the Biosphere) with a
## lattice of steel struts over pale glass and the museum inside, on a round
## plaza in a little park with trees, a path and a "Parc Jean-Drapeau" sign.
## Faces +Z. The struts are one MultiMesh (a single draw call), ~6k triangles.

const STRUT := Color(0.86, 0.88, 0.92)
const GLASS := Color(0.74, 0.87, 0.96, 0.32)
const MUSEUM := Color(0.62, 0.64, 0.70)
const PLAZA := Color(0.80, 0.77, 0.71)
const PATH := Color(0.78, 0.74, 0.66)
const PARK_GREEN := Color(0.22, 0.50, 0.32)

const RADIUS := 3.6
const CENTRE_HEIGHT := 2.5 # the sphere is cut by the ground, like the real one
## Footprint of the solid part (the dome where it meets the ground) in local XZ.
const FOOTPRINT := Rect2(Vector2(-2.7, -2.7), Vector2(5.4, 5.4))


static func build() -> Node3D:
	var kit := ModelKit.new("JeanDrapeau")
	var centre := Vector3(0, CENTRE_HEIGHT, 0)

	kit.cylinder(PLAZA, 3.3, 0.08, Vector3(0, 0.04, 0), 24)
	kit.box(PATH, Vector3(1.6, 0.03, 4.4), Vector3(0, 0.015, 5.0))

	# Museum floors inside the dome.
	kit.box(MUSEUM, Vector3(2.6, 1.4, 2.0), Vector3(0, 0.7, 0))
	kit.box(MUSEUM.lightened(0.15), Vector3(1.8, 0.9, 1.4), Vector3(0, 1.85, 0))
	kit.box(Color(0.2, 0.24, 0.32), Vector3(2.0, 0.35, 0.05), Vector3(0, 0.9, 1.01)) # windows

	# Pale glass shell, then the strut lattice over it.
	var glass := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS - 0.05
	sphere.height = (RADIUS - 0.05) * 2.0
	sphere.radial_segments = 28
	sphere.rings = 14
	glass.mesh = sphere
	glass.material_override = kit.mat(GLASS)
	glass.position = centre
	kit.root.add_child(glass)
	kit.root.add_child(_lattice(kit, centre))

	# The park around it.
	for spot in [Vector3(-5.2, 0, 2.2), Vector3(5.0, 0, 2.6), Vector3(-4.6, 0, -2.6), Vector3(4.8, 0, -2.2), Vector3(-5.4, 0, 4.6), Vector3(0.4, 0, -5.0)]:
		kit.tree(spot, 1.9)
	kit.sign("Parc Jean-Drapeau", PARK_GREEN, Vector3(-2.6, 0, 4.0), 2.9)

	kit.walls(FOOTPRINT, 4.0)
	return kit.root


## Geodesic struts: an icosphere subdivided twice; every edge above the ground
## becomes a thin box in one MultiMesh.
static func _lattice(kit: ModelKit, centre: Vector3) -> MultiMeshInstance3D:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var verts: Array[Vector3] = []
	for v in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
			Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
			Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		verts.append((v as Vector3).normalized())
	var faces: Array[Vector3i] = [
		Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
		Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
		Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
		Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1),
	]
	for level in 2:
		var mids := {}
		var next: Array[Vector3i] = []
		for f in faces:
			var a := _midpoint(verts, mids, f.x, f.y)
			var b := _midpoint(verts, mids, f.y, f.z)
			var c := _midpoint(verts, mids, f.z, f.x)
			next.append_array([Vector3i(f.x, a, c), Vector3i(f.y, b, a), Vector3i(f.z, c, b), Vector3i(a, b, c)])
		faces = next
	var edges := {}
	for f in faces:
		for pair in [[f.x, f.y], [f.y, f.z], [f.z, f.x]]:
			edges[Vector2i(mini(pair[0], pair[1]), maxi(pair[0], pair[1]))] = true

	var transforms: Array[Transform3D] = []
	for e: Vector2i in edges:
		var a := centre + verts[e.x] * RADIUS
		var b := centre + verts[e.y] * RADIUS
		if a.y < -0.2 and b.y < -0.2:
			continue # under the ground
		var dir := b - a
		var y_axis := dir.normalized()
		var x_axis := y_axis.cross(Vector3.UP if absf(y_axis.y) < 0.95 else Vector3.RIGHT).normalized()
		var z_axis := x_axis.cross(y_axis)
		var basis := Basis(x_axis, y_axis * dir.length(), z_axis)
		transforms.append(Transform3D(basis, (a + b) * 0.5))

	var strut := BoxMesh.new()
	strut.size = Vector3(0.07, 1.0, 0.07)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = strut
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var lattice := MultiMeshInstance3D.new()
	lattice.name = "Lattice"
	lattice.multimesh = multimesh
	lattice.material_override = kit.mat(STRUT)
	return lattice


static func _midpoint(verts: Array[Vector3], mids: Dictionary, i: int, j: int) -> int:
	var key := Vector2i(mini(i, j), maxi(i, j))
	if not mids.has(key):
		verts.append((verts[i] + verts[j]).normalized())
		mids[key] = verts.size() - 1
	return mids[key]
