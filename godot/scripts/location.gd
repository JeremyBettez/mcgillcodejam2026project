class_name Location
extends Node3D
## A place on the map: a 3D model plus a hangout area. Friends whose `home` is
## this location pick their wander targets inside the area (and walk back to it
## if they get thrown somewhere else).
##
## Today the model is built in code (see McGillModel). Later, generated models
## (photo -> 3D, like friends) can be dropped in with `set_model`.

var location_id := ""
var display_name := "Location"
## Friends wander within this radius around the location's centre...
var hangout_radius := 6.0
## ...but not inside the building footprint (local XZ rectangle, centred).
var footprint := Rect2(Vector2(-1.0, -1.0), Vector2(2.0, 2.0))

var model_root: Node3D
var _pad: MeshInstance3D


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
	mat.albedo_color = Color(0.62, 0.85, 0.48)
	_pad.material_override = mat
	_pad.position.y = 0.005
	add_child(_pad)


func set_model(model: Node3D) -> void:
	for child in model_root.get_children():
		model_root.remove_child(child)
		child.queue_free()
	model_root.add_child(model)


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


## True if a world point is inside this location's hangout area.
func contains(world_point: Vector3) -> bool:
	var local := to_local(world_point)
	return Vector2(local.x, local.z).length() <= hangout_radius
