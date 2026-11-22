class_name BrandLogos
extends RefCounted
## Simple brand emblems drawn into Images in code (no image assets), shown on
## flat quads on the storefronts:
## - "arches": McDonald's-style golden arches (two parabolic arches).
## - "starbucks": a round green coffee-house badge with white rings and stars
##   (our own simplified badge; the real siren artwork is not copied).
## Textures are cached and drawn 2x2 supersampled for smooth edges.

const SIZE := 256

static var _cache := {}


## A flat, unshaded quad showing `logo`, `width` metres wide, facing +Z.
static func quad(logo: String, width: float) -> MeshInstance3D:
	var texture := texture_for(logo)
	var mesh := MeshInstance3D.new()
	var q := QuadMesh.new()
	var aspect := float(texture.get_height()) / float(texture.get_width())
	q.size = Vector2(width, width * aspect)
	mesh.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = texture
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mesh.material_override = mat
	return mesh


static func texture_for(logo: String) -> ImageTexture:
	if not _cache.has(logo):
		var image := _arches() if logo == "arches" else _starbucks()
		image.generate_mipmaps()
		_cache[logo] = ImageTexture.create_from_image(image)
	return _cache[logo]


## Two golden arches side by side, legs on the baseline. 2:1.4 aspect.
static func _arches() -> Image:
	var w := SIZE
	var h := int(SIZE * 0.7)
	var yellow := Color(1.0, 0.78, 0.05)
	return _draw(w, h, func(u: float, v: float) -> Color:
		# u: -1..1 across, v: 0 (bottom) .. 1 (top)
		for c in [-0.5, 0.5]:
			var x: float = (u - c)
			var outer := 0.97 * (1.0 - pow(x / 0.5, 2.0))
			if v > outer or v < 0.0:
				continue
			if absf(x) < 0.27:
				var inner := 0.70 * (1.0 - pow(x / 0.27, 2.0))
				if v < inner:
					continue
			return yellow
		return Color(0, 0, 0, 0))


## Round green badge: green disc, thin white rim, white inner ring, a big white
## star in the middle and small stars either side.
static func _starbucks() -> Image:
	var green := Color(0.0, 0.44, 0.29)
	var big := _star_polygon(Vector2.ZERO, 0.42)
	var left := _star_polygon(Vector2(-0.76, 0.0), 0.085)
	var right := _star_polygon(Vector2(0.76, 0.0), 0.085)
	return _draw(SIZE, SIZE, func(u: float, v: float) -> Color:
		var p := Vector2(u, v * 2.0 - 1.0)
		var r := p.length()
		if r > 1.0:
			return Color(0, 0, 0, 0)
		if (r > 0.9 and r < 0.95) or (r > 0.6 and r < 0.64):
			return Color.WHITE
		if Geometry2D.is_point_in_polygon(p, big) or Geometry2D.is_point_in_polygon(p, left) or Geometry2D.is_point_in_polygon(p, right):
			return Color.WHITE
		return green)


static func _star_polygon(centre: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 10:
		var angle := -PI * 0.5 + i * PI / 5.0
		var r := radius if i % 2 == 0 else radius * 0.45
		# Image v grows upward in _draw, so flip y to keep the star point up.
		points.append(centre + Vector2(cos(angle), -sin(angle)) * r)
	return points


## Fill a w x h image by sampling `shade(u, v)` 4 times per pixel (u: -1..1
## left to right, v: 0..1 bottom to top) and averaging, for soft edges.
static func _draw(w: int, h: int, shade: Callable) -> Image:
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var sum := Color(0, 0, 0, 0)
			for sy in 2:
				for sx in 2:
					var u := ((x + 0.25 + sx * 0.5) / w) * 2.0 - 1.0
					var v := 1.0 - (y + 0.25 + sy * 0.5) / h
					var c: Color = shade.call(u, v)
					sum += Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a)
			var a := sum.a / 4.0
			image.set_pixel(x, y, Color(sum.r / maxf(sum.a, 0.0001), sum.g / maxf(sum.a, 0.0001), sum.b / maxf(sum.a, 0.0001), a) if a > 0.0 else Color(0, 0, 0, 0))
	return image
