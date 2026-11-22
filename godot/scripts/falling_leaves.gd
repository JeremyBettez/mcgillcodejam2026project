class_name FallingLeaves
extends CPUParticles3D
## A light drift of autumn leaves around wherever the camera is looking: a few
## dozen small billboard leaves (texture drawn in code) in fall colours that
## tumble slowly down and fade out. CPU particles, so it works on WebGL2/phones.

const AREA := 16.0 # half-size of the square the leaves fall over
const TOP := 9.0 # height they start from
const COLORS: Array[Color] = [
	Color(0.90, 0.45, 0.16), Color(0.80, 0.24, 0.20), Color(0.96, 0.72, 0.24),
	Color(0.66, 0.20, 0.24), Color(0.93, 0.56, 0.20),
]

const BREEZE := Vector3(0.25, -0.55, 0.1) # gentle drift when the view is still
const GUST_PUSH := 0.9 # how strongly a fast-moving view drags the leaves along
const GUST_LIFT := 0.12 # ...and swirls them up
const MAX_GUST := 9.0

## The emitter follows this node's XZ position (the camera rig's focus point).
## If it has a `velocity` (CameraRig), fast pans and flicks stir the leaves up.
var follow: Node3D

var _gust := Vector3.ZERO


func _init() -> void:
	name = "FallingLeaves"
	amount = 44
	lifetime = 11.0
	preprocess = 11.0 # leaves already in the air when the game starts
	local_coords = false # leaves keep falling where they are when the view moves
	emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emission_box_extents = Vector3(AREA, 0.5, AREA)
	direction = Vector3(1.0, 0.0, 0.4)
	spread = 60.0
	initial_velocity_min = 0.2
	initial_velocity_max = 0.7
	gravity = BREEZE
	damping_min = 0.05
	damping_max = 0.15
	angle_min = 0.0
	angle_max = 360.0
	angular_velocity_min = -80.0
	angular_velocity_max = 80.0
	scale_amount_min = 0.22
	scale_amount_max = 0.38
	# Random colour per leaf (stepped gradient = one of COLORS), fading out at the end.
	var picks := Gradient.new()
	picks.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets := PackedFloat32Array()
	for i in COLORS.size():
		offsets.append(float(i) / COLORS.size())
	picks.offsets = offsets
	picks.colors = PackedColorArray(COLORS)
	color_initial_ramp = picks
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.08, 0.85, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color.WHITE, Color(1, 1, 1, 0)])
	color_ramp = fade

	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = _leaf_texture()
	quad.material = mat
	mesh = quad


func _process(delta: float) -> void:
	if not follow:
		return
	global_position = Vector3(follow.global_position.x, TOP, follow.global_position.z)
	# Wind from the camera: leaves get swept along behind a quick pan and tumble
	# faster, then settle back to the breeze when the view stops.
	var view_velocity: Vector3 = follow.get("velocity") if follow.get("velocity") is Vector3 else Vector3.ZERO
	var flat := Vector3(view_velocity.x, 0.0, view_velocity.z)
	var goal := flat * GUST_PUSH + Vector3.UP * flat.length() * GUST_LIFT
	# Gusts build quickly and die down slowly.
	var rate := 6.0 if goal.length() > _gust.length() else 1.2
	_gust = _gust.lerp(goal.limit_length(MAX_GUST), 1.0 - exp(-rate * delta))
	gravity = BREEZE + _gust
	speed_scale = 1.0 + minf(_gust.length() * 0.08, 0.8)


## A simple pointed leaf with a stem and a pale vein, white so particle colours tint it.
static func _leaf_texture() -> ImageTexture:
	const N := 48
	var image := Image.create(N, N, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0))
	for y in N:
		for x in N:
			# Leaf axis runs diagonally; u along it (-1..1), v across it.
			var px := (x + 0.5) / N * 2.0 - 1.0
			var py := (y + 0.5) / N * 2.0 - 1.0
			var u := (px - py) * 0.7071
			var v := (px + py) * 0.7071
			var half_width := 0.42 * (1.0 - u * u) * (1.0 - 0.25 * u)
			var shade := 1.0 - 0.18 * absf(v) / maxf(half_width, 0.01)
			if absf(u) < 0.92 and absf(v) < half_width:
				var c := Color(shade, shade, shade, 1.0)
				if absf(v) < 0.025 and u > -0.85:
					c = Color(1.0, 1.0, 0.92, 1.0) # vein
				image.set_pixel(x, y, c)
			elif u < -0.9 and u > -1.25 and absf(v) < 0.03:
				image.set_pixel(x, y, Color(0.8, 0.8, 0.8, 1.0)) # stem
	return ImageTexture.create_from_image(image)
