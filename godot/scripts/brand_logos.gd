class_name BrandLogos
extends RefCounted
## Simple brand emblems drawn into Images in code (no image assets), shown on
## flat quads on the storefronts:
## - "arches": McDonald's-style golden arches (two parabolic arches).
## - "starbucks": a round green badge with a simplified white twin-tailed siren
##   (our own simplified drawing of the emblem).
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


## Round green coffee badge with a simplified twin-tailed siren in white: a
## crowned face with a star on the crown, long wavy hair falling on both
## sides, and her two tails raised up beside her head. Our own simplified
## drawing in the spirit of the Starbucks emblem.
static func _starbucks() -> Image:
	var green := Color(0.0, 0.44, 0.29)
	var crown_star := _star_polygon(Vector2(0.0, 0.47), 0.075)
	var crown := PackedVector2Array([
		Vector2(-0.24, 0.33), Vector2(-0.26, 0.47), Vector2(-0.15, 0.40), Vector2(-0.09, 0.57),
		Vector2(0.0, 0.62), Vector2(0.09, 0.57), Vector2(0.15, 0.40), Vector2(0.26, 0.47), Vector2(0.24, 0.33),
	])
	# Each tail: a centre line from under the hair, sweeping out and up, plus a
	# forked fin at the top.
	var tail_line := PackedVector2Array()
	for i in 21:
		var t := i / 20.0
		tail_line.append(Vector2(0.34 + 0.30 * sin(t * PI * 0.85), -0.58 + 1.08 * t - 0.12 * t * t))
	var fins: Array[PackedVector2Array] = []
	for side in [-1.0, 1.0]:
		fins.append(PackedVector2Array([
			Vector2(0.56 * side, 0.34), Vector2(0.44 * side, 0.70), Vector2(0.55 * side, 0.58),
			Vector2(0.62 * side, 0.78), Vector2(0.68 * side, 0.56), Vector2(0.66 * side, 0.34),
		]))
	return _draw(SIZE, SIZE, func(u: float, v: float) -> Color:
		var p := Vector2(u, v * 2.0 - 1.0)
		var r := p.length()
		if r > 1.0:
			return Color(0, 0, 0, 0)
		if r > 0.9 and r < 0.94:
			return Color.WHITE # thin rim
		if r >= 0.94:
			return green
		# Crown with a green star in it.
		if Geometry2D.is_point_in_polygon(p, crown):
			return green if Geometry2D.is_point_in_polygon(p, crown_star) else Color.WHITE
		# Face: a white oval with green eyes and a small smile.
		var face := Vector2(p.x / 0.2, (p.y - 0.1) / 0.25)
		if face.length() < 1.0:
			for ex in [-0.075, 0.075]:
				if Vector2((p.x - ex) / 0.035, (p.y - 0.14) / 0.02).length() < 1.0:
					return green
			var mouth := Vector2(p.x / 0.08, (p.y - 0.02) / 0.05)
			if mouth.length() < 1.0 and mouth.length() > 0.7 and p.y < 0.02:
				return green
			return Color.WHITE
		# Hair: wavy locks framing the face and flaring out towards the
		# shoulders, with green partings between the strands.
		var ax := absf(p.x)
		var outer := 0.27 + 0.13 * clampf(-p.y + 0.3, 0.0, 1.0) + 0.03 * sin(p.y * 10.0)
		if p.y < 0.33 and p.y > -0.66 and ax < outer and (ax > 0.18 or p.y < -0.14):
			if p.y < -0.62 + 0.04 * sin(ax * 30.0):
				return green # wavy hair ends
			var wave := sin((ax - 0.04 * sin(p.y * 11.0)) * 38.0)
			return green if wave > 0.78 else Color.WHITE
		# Tails sweeping up on both sides (thicker low down), with forked fins.
		var q := Vector2(ax, p.y)
		for i in tail_line.size() - 1:
			var closest := Geometry2D.get_closest_point_to_segment(q, tail_line[i], tail_line[i + 1])
			if q.distance_to(closest) < lerpf(0.085, 0.05, i / 20.0):
				return Color.WHITE
		for fin in fins:
			if Geometry2D.is_point_in_polygon(p, fin):
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
