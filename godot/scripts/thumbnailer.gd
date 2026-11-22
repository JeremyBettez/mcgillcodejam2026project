class_name Thumbnailer
extends Node
## Renders small pictures of 3D things (a friend's model, a location's building)
## for the menus. Each picture is rendered once in an offscreen SubViewport from a
## copy of the model, then cached. Works on web (Compatibility renderer).

const SIZE := 128

var _cache := {} # key -> ImageTexture
var _pending := {} # key -> Array[Callable] waiting for that picture


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # still renders while the game is paused


## Picture of a friend: waist-up portrait, facing the viewer. Calls `done(texture)`.
func friend_portrait(friend: Resident, done: Callable) -> void:
	var model := friend.avatar_root.get_child(0) as Node3D if friend.avatar_root.get_child_count() > 0 else null
	if model == null:
		return
	var key := "friend:%d" % model.get_instance_id()
	# Model faces -Z, so the camera stands on the -Z side looking back at it.
	_request(key, model, Vector3(0.0, 1.45, -1.9), Vector3(0.0, 1.3, 0.0), 30.0, true, done)


## Picture of a location's model, seen from the front and a little above.
func location_picture(place: Location, done: Callable) -> void:
	var model := place.model_root.get_child(0) as Node3D if place.model_root.get_child_count() > 0 else null
	if model == null:
		return
	# Keyed by the model too, so a place re-renders once its real model replaces
	# the construction site.
	var key := "location:%s:%d" % [place.location_id, model.get_instance_id()]
	_request(key, model, Vector3(7.0, 6.0, 13.0), Vector3(0.0, 1.6, 0.5), 38.0, false, done)


func cached(key: String) -> Texture2D:
	return _cache.get(key)


func _request(key: String, model: Node3D, eye: Vector3, look: Vector3, fov: float, transparent: bool, done: Callable) -> void:
	if _cache.has(key):
		done.call(_cache[key])
		return
	if _pending.has(key):
		_pending[key].append(done)
		return
	_pending[key] = [done]
	var texture := await _render(model, eye, look, fov, transparent)
	if texture:
		_cache[key] = texture
	for callback: Callable in _pending.get(key, []):
		if texture and callback.is_valid():
			callback.call(texture)
	_pending.erase(key)


func _render(model: Node3D, eye: Vector3, look: Vector3, fov: float, transparent: bool) -> ImageTexture:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.own_world_3d = true
	viewport.transparent_bg = transparent
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.98, 0.83, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.85, 0.75)
	env.ambient_light_energy = 0.7
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 150.0, 0.0)
	viewport.add_child(sun)

	# The copy keeps the model's own transform (friends are scaled to 1.7 m with
	# feet at y = 0 by GlbLoader), so the camera framing above always fits.
	var copy := model.duplicate() as Node3D
	viewport.add_child(copy)
	# Friends: relaxed arms-down pose instead of whatever frame they were in.
	var skeletons := copy.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var gait := ProceduralGait.new()
		gait.setup(skeletons[0] as Skeleton3D)

	var cam := Camera3D.new()
	cam.fov = fov
	viewport.add_child(cam)
	cam.look_at_from_position(eye, look, Vector3.UP)
	cam.current = true

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)
