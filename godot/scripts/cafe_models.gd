class_name CafeModels
extends RefCounted
## Low-poly downtown storefronts built in code: a Starbucks-style café and a
## McDonald's-style restaurant. Brand colours and a name sign only (no logos).
## Both face +Z.

const STARBUCKS_FOOTPRINT := Rect2(Vector2(-3.3, -2.4), Vector2(6.6, 4.4))
const MCDONALDS_FOOTPRINT := Rect2(Vector2(-3.6, -2.5), Vector2(7.2, 4.6))

const GLASS := Color(0.30, 0.42, 0.50)
const DOOR := Color(0.25, 0.18, 0.14)


static func starbucks() -> Node3D:
	var kit := ModelKit.new("Starbucks")
	var green := Color(0.0, 0.44, 0.29)
	var cream := Color(0.94, 0.90, 0.82)
	var brick := Color(0.55, 0.33, 0.25)
	kit.box(brick, Vector3(6.4, 3.4, 4.2), Vector3(0, 1.7, -0.2)) # two-storey brick building
	kit.box(cream, Vector3(6.6, 0.25, 4.4), Vector3(0, 3.5, -0.2)) # cornice
	kit.box(cream, Vector3(6.5, 1.5, 0.1), Vector3(0, 0.75, 1.92)) # shopfront frame
	for x in [-2.2, -0.75, 1.75]:
		kit.box(GLASS, Vector3(1.2, 1.1, 0.05), Vector3(x, 0.85, 1.98))
	kit.box(DOOR, Vector3(0.8, 1.3, 0.05), Vector3(0.5, 0.65, 1.98))
	for x in [-2.0, 0.0, 2.0]:
		kit.box(GLASS, Vector3(1.1, 0.9, 0.05), Vector3(x, 2.5, 1.92)) # upstairs windows
	# Green awning tilted out over the windows.
	var awning := kit.box(green, Vector3(6.6, 0.08, 1.1), Vector3(0, 1.75, 2.35))
	awning.rotation.x = deg_to_rad(18.0)
	# Sign band with the name, and a plain round green badge.
	kit.box(green, Vector3(3.2, 0.5, 0.08), Vector3(-0.8, 2.05, 1.98))
	_label(kit, "Starbucks", Vector3(-0.8, 2.05, 2.04), Color.WHITE, 0.0042)
	kit.cylinder(Color.WHITE, 0.42, 0.06, Vector3(1.9, 2.05, 1.99), 20).rotation.x = PI * 0.5
	kit.cylinder(green, 0.34, 0.07, Vector3(1.9, 2.05, 2.0), 20).rotation.x = PI * 0.5
	# Patio: tables with green umbrellas.
	for x in [-2.0, 2.2]:
		kit.cylinder(DOOR, 0.35, 0.05, Vector3(x, 0.72, 3.4), 10)
		kit.cylinder(DOOR, 0.04, 0.72, Vector3(x, 0.36, 3.4), 6)
		kit.cylinder(Color(0.8, 0.8, 0.8), 0.03, 1.9, Vector3(x, 0.95, 3.4), 6)
		var shade := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = 0.95
		cone.height = 0.4
		cone.radial_segments = 8
		cone.rings = 1
		shade.mesh = cone
		shade.material_override = kit.mat(green)
		shade.position = Vector3(x, 2.0, 3.4)
		kit.root.add_child(shade)
	kit.tree(Vector3(-4.6, 0, 1.8))
	kit.walls(STARBUCKS_FOOTPRINT, 3.0)
	return kit.root


static func mcdonalds() -> Node3D:
	var kit := ModelKit.new("McDonalds")
	var red := Color(0.84, 0.12, 0.10)
	var yellow := Color(1.0, 0.78, 0.05)
	var roof := Color(0.45, 0.10, 0.10)
	kit.box(Color(0.80, 0.70, 0.58), Vector3(7.0, 0.2, 4.6), Vector3(0, 0.1, -0.2)) # slab
	kit.box(red, Vector3(6.8, 2.6, 4.2), Vector3(0, 1.5, -0.2))
	# Mansard-style roof: a dark sloped band (stacked, stepped in) with a flat top.
	kit.box(roof, Vector3(7.0, 0.35, 4.4), Vector3(0, 3.0, -0.2))
	kit.box(roof, Vector3(6.4, 0.35, 3.9), Vector3(0, 3.35, -0.2))
	kit.box(roof.lightened(0.1), Vector3(5.8, 0.15, 3.4), Vector3(0, 3.6, -0.2))
	kit.box(yellow, Vector3(7.0, 0.18, 4.4), Vector3(0, 2.82, -0.2)) # yellow trim
	# Big front windows, door, and the name in yellow on a red band.
	for x in [-2.4, -1.0, 1.9]:
		kit.box(GLASS, Vector3(1.2, 1.4, 0.05), Vector3(x, 1.15, 1.92))
	kit.box(DOOR, Vector3(0.9, 1.6, 0.05), Vector3(0.45, 1.0, 1.92))
	kit.box(red.darkened(0.2), Vector3(3.6, 0.45, 0.08), Vector3(0, 2.35, 1.95))
	_label(kit, "McDonald's", Vector3(0, 2.35, 2.01), yellow, 0.0042)
	# Tall roadside sign: pole with a yellow board.
	kit.cylinder(Color(0.75, 0.75, 0.78), 0.1, 4.6, Vector3(-4.4, 2.3, 1.6), 8)
	kit.box(yellow, Vector3(1.9, 1.0, 0.18), Vector3(-4.4, 4.7, 1.6))
	_label(kit, "McDonald's", Vector3(-4.4, 4.7, 1.7), red, 0.0036)
	# Drive-through lane on the side.
	kit.box(Color(0.35, 0.35, 0.38), Vector3(1.8, 0.02, 6.0), Vector3(4.6, 0.01, 0.6))
	kit.box(yellow, Vector3(0.1, 0.02, 6.0), Vector3(4.6, 0.02, 0.6))
	kit.walls(MCDONALDS_FOOTPRINT, 3.0)
	return kit.root


static func _label(kit: ModelKit, text: String, at: Vector3, color: Color, pixel: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font = UiStyle.bold()
	label.font_size = 64
	label.pixel_size = pixel
	label.outline_size = 0
	label.modulate = color
	label.position = at
	kit.root.add_child(label)
