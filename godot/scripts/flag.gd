class_name Flag
extends RefCounted
## Flags and emblems for locations (universities, companies, restaurants...).
## The flag artwork is drawn into an Image in code (no image assets) and shown on
## a cloth that waves in the wind via a small shader, on a pole with a gold finial.
##
## Designs:
##   "mcgill"             McGill University: red field, white shield with three red
##                        martlets and an open book on a red chief (stylized).
##   {"colors": [a, b]}   Generic brand flag for places without a famous emblem:
##                        field colour + a band and a disc in the accent colour.
## Add new named designs in `_draw_design` when a place has a recognizable symbol.

const TEX_W := 256
const TEX_H := 160

const WAVE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D flag_texture : source_color, filter_linear_mipmap;
uniform float amplitude = 0.06;
uniform float speed = 3.0;
void vertex() {
	// Pinned at the pole (UV.x = 0), rippling more towards the free edge.
	float k = UV.x;
	VERTEX.z += sin(UV.x * 7.0 - TIME * speed) * amplitude * k;
	VERTEX.y += sin(UV.x * 5.0 - TIME * speed * 0.8) * amplitude * 0.3 * k;
}
void fragment() {
	vec4 c = texture(flag_texture, UV);
	ALBEDO = c.rgb;
	ROUGHNESS = 0.9;
}
"""


## A known design for a place name, or null. Add recognizable places here.
static func design_for_name(place_name: String) -> Variant:
	var lower := place_name.to_lower()
	if "mcgill" in lower:
		return "mcgill"
	return null


## Generic flag colours picked from a photo: the most vivid colour as the field,
## white or brown as the accent so it stays readable.
static func design_from_photo(jpeg: PackedByteArray) -> Dictionary:
	var img := Image.new()
	if jpeg.is_empty() or img.load_jpg_from_buffer(jpeg) != OK:
		return {"colors": [UiStyle.SKY, Color.WHITE]}
	img.resize(16, 16, Image.INTERPOLATE_BILINEAR)
	var best := Color(0.42, 0.66, 0.93)
	var best_score := -1.0
	for y in 16:
		for x in 16:
			var c := img.get_pixel(x, y)
			var score := c.s * (0.4 + c.v)
			if score > best_score:
				best_score = score
				best = c
	if best.s < 0.25: # a grey/white photo: give it a friendly default
		best = UiStyle.SKY
	var field := Color.from_hsv(best.h, clampf(best.s, 0.45, 0.85), clampf(best.v, 0.55, 0.9))
	var accent := Color.WHITE if field.get_luminance() < 0.6 else UiStyle.BROWN
	return {"colors": [field, accent]}


## A pole with a waving flag. The pole stands at the node's origin; the flag
## flies towards +X near the top, facing +Z.
static func build(design: Variant, pole_height := 1.6, flag_width := 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "Flag"
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.85, 0.86, 0.88)
	metal.metallic = 0.6
	metal.roughness = 0.4
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.035
	cyl.height = pole_height
	cyl.radial_segments = 8
	cyl.rings = 1
	pole.mesh = cyl
	pole.material_override = metal
	pole.position.y = pole_height * 0.5
	root.add_child(pole)
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.95, 0.76, 0.25)
	gold.metallic = 0.7
	gold.roughness = 0.35
	var finial := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.06
	ball.height = 0.12
	ball.radial_segments = 10
	ball.rings = 5
	finial.mesh = ball
	finial.material_override = gold
	finial.position.y = pole_height + 0.05
	root.add_child(finial)

	var flag_height := flag_width * float(TEX_H) / TEX_W
	var cloth := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Z
	plane.size = Vector2(flag_width, flag_height)
	plane.subdivide_width = 16
	plane.subdivide_depth = 4
	cloth.mesh = plane
	var shader := Shader.new()
	shader.code = WAVE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("flag_texture", texture_for(design))
	cloth.material_override = mat
	cloth.position = Vector3(flag_width * 0.5 + 0.03, pole_height - flag_height * 0.5 - 0.04, 0.0)
	root.add_child(cloth)
	return root


## The flag artwork as a texture (also handy for menus).
static func texture_for(design: Variant) -> ImageTexture:
	var img := Image.create(TEX_W, TEX_H, true, Image.FORMAT_RGBA8)
	_draw_design(img, design)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _draw_design(img: Image, design: Variant) -> void:
	if design is String and design == "mcgill":
		_draw_mcgill(img)
	elif design is Dictionary:
		var colors: Array = design.get("colors", [Color(0.2, 0.4, 0.8), Color.WHITE])
		var field: Color = colors[0]
		var accent: Color = colors[1] if colors.size() > 1 else Color.WHITE
		img.fill(field)
		img.fill_rect(Rect2i(0, TEX_H * 5 / 8, TEX_W, TEX_H / 8), accent)
		_disc(img, Vector2(TEX_W * 0.5, TEX_H * 0.4), TEX_H * 0.2, accent)
	else:
		img.fill(Color(0.85, 0.85, 0.85))


## McGill (stylized): red field; white shield with a thin dark outline; red chief
## with a gold open book; three red martlets (two above, one below).
static func _draw_mcgill(img: Image) -> void:
	var red := Color(0.93, 0.11, 0.19)
	var white := Color(0.98, 0.98, 0.98)
	var outline := Color(0.35, 0.05, 0.08)
	var gold := Color(0.98, 0.80, 0.25)
	img.fill(red)
	var cx := TEX_W * 0.5
	var top := 20.0
	var bottom := TEX_H - 14.0
	var half_w := 46.0
	_shield(img, cx, top - 3.0, bottom + 3.0, half_w + 3.0, outline)
	_shield(img, cx, top, bottom, half_w, white)
	# Chief: red band across the top of the shield, with an open book.
	var chief_h := 34.0
	for y in range(int(top), int(top + chief_h)):
		for x in range(int(cx - half_w), int(cx + half_w)):
			img.set_pixel(x, y, red)
	var book_y := top + chief_h * 0.5
	img.fill_rect(Rect2i(int(cx - 22), int(book_y - 8), 20, 16), gold)
	img.fill_rect(Rect2i(int(cx + 2), int(book_y - 8), 20, 16), gold)
	img.fill_rect(Rect2i(int(cx - 1), int(book_y - 9), 2, 18), outline)
	# Three martlets.
	for spot in [Vector2(cx - 22, top + chief_h + 22), Vector2(cx + 22, top + chief_h + 22), Vector2(cx, top + chief_h + 56)]:
		_martlet(img, spot, red)


## Shield: straight sides, then a rounded point at the bottom.
static func _shield(img: Image, cx: float, top: float, bottom: float, half_w: float, color: Color) -> void:
	var mid := top + (bottom - top) * 0.45
	for y in range(int(top), int(bottom)):
		var w := half_w
		if y > mid:
			var t := (y - mid) / (bottom - mid)
			w = half_w * sqrt(maxf(0.0, 1.0 - t * t))
		for x in range(int(cx - w), int(cx + w)):
			img.set_pixel(clampi(x, 0, TEX_W - 1), clampi(y, 0, TEX_H - 1), color)


## Tiny bird: oval body, round head, swept wing and forked tail.
static func _martlet(img: Image, at: Vector2, color: Color) -> void:
	_ellipse(img, at, Vector2(10, 5), color)
	_disc(img, at + Vector2(-9, -3), 4.0, color)
	_ellipse(img, at + Vector2(1, -6), Vector2(7, 3), color)
	_ellipse(img, at + Vector2(12, 2), Vector2(5, 2), color)


static func _disc(img: Image, c: Vector2, r: float, color: Color) -> void:
	_ellipse(img, c, Vector2(r, r), color)


static func _ellipse(img: Image, c: Vector2, r: Vector2, color: Color) -> void:
	for y in range(int(c.y - r.y), int(c.y + r.y) + 1):
		for x in range(int(c.x - r.x), int(c.x + r.x) + 1):
			var d := Vector2((x - c.x) / r.x, (y - c.y) / r.y)
			if d.length_squared() <= 1.0 and x >= 0 and y >= 0 and x < TEX_W and y < TEX_H:
				img.set_pixel(x, y, color)
