class_name Location
extends Node3D
## A place on the map: a 3D model plus a hangout area. Friends whose `home` is
## this location pick their wander targets inside the area (and walk back to it
## if they get thrown somewhere else).
##
## Models: built in code (McGillModel, ConstructionModel while generating) or a
## generated GLB (photo -> 3D via the relay's /generate_place), fitted with
## `set_generated_model`, which also builds solid walls from its bounds.
## Front of every location = local +Z.

const PLACE_MAX_WIDTH := 9.0 # generated buildings are fitted inside this...
const PLACE_MAX_HEIGHT := 7.0 # ...and this, keeping their proportions
## Generated models face -Z (like the AniGen friends); turn them to face +Z.
const GENERATED_MODEL_YAW := PI

var location_id := ""
var display_name := "Location":
	set(value):
		display_name = value
		_update_tag()
## Friends wander within this radius around the location's centre...
var hangout_radius := 6.0
## ...but not inside the building footprint (local XZ rectangle, centred).
var footprint := Rect2(Vector2(-1.0, -1.0), Vector2(2.0, 2.0))
## Camera distance when flying here from the Locations list (0 = fit the footprint).
var view_distance := 0.0
var user_added := false # added by the player (saved, removable)
## The neighbourhood it stands in (District id; follows its position).
var district_id := ""
var flag_design: Variant = null # null, "mcgill", or {"colors": [field, accent]}
## Second line on the name sign, e.g. "building 3D..." while generating.
var status_text := "":
	set(value):
		status_text = value
		_update_tag()

var model_root: Node3D
var name_tag: Label3D
var _pad: MeshInstance3D
var _walls: StaticBody3D
var _flag: Node3D


func _ready() -> void:
	model_root = Node3D.new()
	model_root.name = "Model"
	add_child(model_root)
	# A slightly lighter lawn marks the hangout area on the grass.
	_pad = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = hangout_radius
	disc.bottom_radius = hangout_radius
	disc.height = 0.02
	disc.radial_segments = 40
	disc.rings = 1
	_pad.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.69, 0.67, 0.38)
	_pad.material_override = mat
	_pad.position.y = 0.005
	add_child(_pad)


func set_model(model: Node3D) -> void:
	for child in model_root.get_children():
		model_root.remove_child(child)
		child.queue_free()
	model_root.add_child(model)


## Show a floating name sign (for player-added places; McGill has its own sign).
func show_name_tag(height: float) -> void:
	if name_tag == null:
		name_tag = Label3D.new()
		name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_tag.no_depth_test = true
		name_tag.fixed_size = true
		name_tag.pixel_size = 0.0014
		name_tag.font_size = 34
		name_tag.outline_size = 12
		name_tag.font = UiStyle.bold()
		name_tag.outline_modulate = UiStyle.BROWN
		add_child(name_tag)
	name_tag.position.y = height
	_update_tag()


func _update_tag() -> void:
	if name_tag:
		name_tag.text = display_name if status_text.is_empty() else "%s\n(%s)" % [display_name, status_text]


## Put a generated GLB in: turned to face +Z, scaled to fit PLACE_MAX_* with its
## base on the ground and centred, then solid walls and the footprint from its
## bounds (so friends walk around it), and the name sign above it.
func set_generated_model(model: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Generated"
	holder.add_child(model)
	model.rotation.y = GENERATED_MODEL_YAW
	var box := _bounds(holder)
	var size := box.size
	var s := 1.0
	if size.x > 0.0 and size.y > 0.0 and size.z > 0.0:
		s = minf(PLACE_MAX_WIDTH / maxf(size.x, size.z), PLACE_MAX_HEIGHT / size.y)
	holder.scale = Vector3.ONE * s
	var centre := box.get_center()
	holder.position = Vector3(-centre.x * s, -box.position.y * s, -centre.z * s)
	set_model(holder)
	var w := size.x * s
	var d := size.z * s
	footprint = Rect2(Vector2(-w * 0.5, -d * 0.5), Vector2(w, d))
	# Leave a ring of lawn around the building for friends to hang out on.
	set_hangout_radius(maxf(hangout_radius, Vector2(w, d).length() * 0.5 + 3.5))
	set_walls(Vector3(w, size.y * s, d))
	show_name_tag(size.y * s + 0.8)
	refresh_flag()


## Put in a Quick build model (RecipeModel.build() result): it already faces +Z
## and has its own walls, so just take its footprint and height.
func set_recipe_model(built: Dictionary) -> void:
	set_model(built.model)
	footprint = built.footprint
	if _walls:
		_walls.queue_free() # the construction site's walls
		_walls = null
	set_hangout_radius(maxf(hangout_radius, footprint.size.length() * 0.5 + 3.5))
	show_name_tag(float(built.height) + 0.8)
	# Step the camera back far enough to see towers and roofs.
	view_distance = clampf(float(built.height) * 2.4 + 8.0, 15.0, 28.0)
	refresh_flag()


func set_hangout_radius(radius: float) -> void:
	hangout_radius = radius
	if _pad and _pad.mesh is CylinderMesh:
		(_pad.mesh as CylinderMesh).top_radius = radius
		(_pad.mesh as CylinderMesh).bottom_radius = radius


## Solid box walls (physics layer 1) so friends walk around the building.
func set_walls(size: Vector3) -> void:
	if _walls:
		_walls.queue_free()
	_walls = StaticBody3D.new()
	_walls.name = "Walls"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(size.x, 0.5), maxf(size.y, 0.5), maxf(size.z, 0.5))
	shape.shape = box
	shape.position.y = box.size.y * 0.5
	_walls.add_child(shape)
	add_child(_walls)


## (Re)place the flag pole beside the front corner of the building, if any.
func refresh_flag() -> void:
	if _flag:
		_flag.queue_free()
		_flag = null
	if flag_design == null:
		return
	_flag = Flag.build(flag_design, 3.6, 1.3)
	_flag.position = Vector3(footprint.end.x + 0.9, 0.0, footprint.end.y + 0.6)
	add_child(_flag)


## A random spot in the hangout area, outside the building, in world space.
func random_point(rng: RandomNumberGenerator) -> Vector3:
	var grown := footprint.grow(0.7) # keep a little clearance from the walls
	for attempt in 20:
		var angle := rng.randf() * TAU
		var dist := sqrt(rng.randf()) * hangout_radius
		var local := Vector2(cos(angle), sin(angle)) * dist
		if not grown.has_point(local):
			return to_global(Vector3(local.x, 0.0, local.y))
	# Fallback: straight out in front of the building.
	return to_global(Vector3(0.0, 0.0, footprint.end.y + 1.5))


## The footprint as a world-space XZ polygon (follows position and turning),
## grown by `margin` metres. `at`/`yaw` test a spot before moving there.
func world_footprint(margin := 0.0, at: Variant = null, yaw: Variant = null) -> PackedVector2Array:
	var centre: Vector3 = global_position if at == null else at
	var turn: float = rotation.y if yaw == null else yaw
	return footprint_polygon(footprint.grow(margin), centre, turn)


## A local XZ rectangle placed at `centre`, turned by `yaw` (around +Y), as a
## world XZ polygon.
static func footprint_polygon(rect: Rect2, centre: Vector3, yaw: float) -> PackedVector2Array:
	var basis := Basis(Vector3.UP, yaw)
	var result := PackedVector2Array()
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var w: Vector3 = centre + basis * Vector3(corner.x, 0.0, corner.y)
		result.append(Vector2(w.x, w.z))
	return result


## Parts of the hangout area friends explore: sectors around the building
## (world angle atan2(z, x); towards the camera = +Z = 90 deg). The far side
## is left out, since the fixed camera can't see behind a building. Angles are
## in world space, so a turned building still gets explored on the side you see.
const EXPLORE_FROM := deg_to_rad(-25.0)
const EXPLORE_TO := deg_to_rad(205.0)
const EXPLORE_SECTORS := 6


## A spot to walk to, in the sector visited least among `recent` (ties at
## random), outside the building. Returns {"point": Vector3 (world), "sector": int}.
func explore_point(rng: RandomNumberGenerator, recent: Array[int]) -> Dictionary:
	var best: Array[int] = []
	var fewest := 1 << 30
	for sector in EXPLORE_SECTORS:
		var visits := recent.count(sector)
		if visits < fewest:
			fewest = visits
			best = [sector]
		elif visits == fewest:
			best.append(sector)
	var sector: int = best[rng.randi() % best.size()]
	var width := (EXPLORE_TO - EXPLORE_FROM) / EXPLORE_SECTORS
	var grown := footprint.grow(0.8)
	for attempt in 16:
		var angle := EXPLORE_FROM + width * (sector + rng.randf())
		var dist := lerpf(hangout_radius * 0.35, hangout_radius * 0.95, sqrt(rng.randf()))
		var offset := Vector2(cos(angle), sin(angle)) * dist # world XZ, from the centre
		var local := to_local(global_position + Vector3(offset.x, 0.0, offset.y))
		if not grown.has_point(Vector2(local.x, local.z)):
			return {"point": global_position + Vector3(offset.x, 0.0, offset.y), "sector": sector}
	return {"point": random_point(rng), "sector": sector}


## True if a world point is inside this location's hangout area.
func contains(world_point: Vector3) -> bool:
	var local := to_local(world_point)
	return Vector2(local.x, local.z).length() <= hangout_radius


## Bounds of all meshes under `root` in root's local space (includes children's transforms).
static func _bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var xf: Transform3D = item[1]
		if node is MeshInstance3D:
			var b: AABB = xf * (node as MeshInstance3D).get_aabb()
			result = b if first else result.merge(b)
			first = false
		for child in node.get_children():
			if child is Node3D:
				stack.append([child, xf * (child as Node3D).transform])
	return result
