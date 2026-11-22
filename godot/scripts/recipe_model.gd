class_name RecipeModel
extends RefCounted
## "Quick build" places: turns a building recipe (JSON from the relay's
## /generate_place_recipe, where Claude describes the photo as simple parts)
## into a low-poly model built in code with ModelKit, in the same style as the
## built-in places. Every field is optional and clamped: a missing or odd value
## falls back to a sensible default, so any recipe builds *something*.
##
## build() returns {"model": Node3D, "footprint": Rect2, "height": float,
## "flag": null or {"colors": [field, accent]}, "anchors": {name: Vector3}}.
## Anchors are front-facing spots for extra decoration (e.g. a logo), only
## present when that part exists: "tower_front", "pediment_front", "entrance".
## Faces +Z.

const STONE := Color(0.70, 0.67, 0.60)
const GLASS := Color(0.24, 0.32, 0.42)
const PLINTH := 0.2 # height of the stone base everything stands on
const CEREMONIAL := ["university", "museum", "library", "church", "office", "station"]


static func build(recipe: Dictionary) -> Dictionary:
	var kit := ModelKit.new("QuickBuild")
	var kind := _text(recipe, "kind", "other")
	var w := _num(recipe, "width", 7.0, 4.0, 10.0)
	var d := _num(recipe, "depth", 5.0, 3.0, 8.0)
	var h := _num(recipe, "height", 4.5, 2.5, 8.0)
	var floors := clampi(_int(recipe, "floors", 2), 1, maxi(1, int(h / 1.3)))
	var wall := _color(recipe, "wall_color", Color(0.85, 0.72, 0.58))
	var trim := _color(recipe, "trim_color", Color(0.95, 0.92, 0.85))
	var roof := _color(recipe, "roof_color", Color(0.40, 0.42, 0.48))
	var window := _color(recipe, "window_color", GLASS)
	var door := _color(recipe, "door_color", Color(0.35, 0.24, 0.18))
	var roof_style := _choice(recipe, "roof_style", ["flat", "pitched", "dome", "mansard", "spire"], "flat")
	var floor_h := h / floors
	var top := PLINTH + h # top of the walls
	var front := d * 0.5
	var anchors := {"entrance": Vector3(0, PLINTH + minf(1.9, floor_h * 0.8) + 0.45, front + 0.05)}

	# Base and main block, with a trim band under the roof.
	kit.box(STONE, Vector3(w + 0.4, PLINTH, d + 0.4), Vector3(0, PLINTH * 0.5, 0))
	kit.box(wall, Vector3(w, h, d), Vector3(0, PLINTH + h * 0.5, 0))
	kit.box(trim, Vector3(w + 0.14, 0.22, d + 0.14), Vector3(0, top - 0.11, 0))

	# Lower wings either side.
	var total_w := w
	if _flag(recipe, "wings"):
		var ww := clampf(w * 0.32, 1.5, 3.0)
		var wh := maxf(h * 0.62, 2.0)
		for side in [-1.0, 1.0]:
			var x: float = side * (w * 0.5 + ww * 0.5)
			kit.box(STONE, Vector3(ww + 0.2, PLINTH, d * 0.85 + 0.2), Vector3(x, PLINTH * 0.5, -d * 0.05))
			kit.box(wall, Vector3(ww, wh, d * 0.85), Vector3(x, PLINTH + wh * 0.5, -d * 0.05))
			kit.box(roof, Vector3(ww + 0.18, 0.2, d * 0.85 + 0.18), Vector3(x, PLINTH + wh + 0.1, -d * 0.05))
			var wing_front := -d * 0.05 + d * 0.425
			for f in maxi(1, int(wh / 1.4)):
				_window(kit, window, trim, Vector3(x, PLINTH + 1.4 * (f + 0.55), wing_front + 0.03), Vector2(minf(0.7, ww * 0.4), 0.7))
		total_w = w + ww * 2.0

	# Door, and windows on every floor.
	var door_h := minf(1.9, floor_h * 0.8)
	kit.box(trim, Vector3(1.25, door_h + 0.15, 0.05), Vector3(0, PLINTH + (door_h + 0.15) * 0.5, front + 0.01))
	kit.box(door, Vector3(1.0, door_h, 0.06), Vector3(0, PLINTH + door_h * 0.5, front + 0.03))
	var per_floor := clampi(_int(recipe, "windows_per_floor", 3), 0, mini(8, int(w / 0.9)))
	if per_floor > 0:
		var win_w := minf(0.75, w * 0.85 / per_floor * 0.6)
		var win_h := minf(floor_h * 0.5, 1.2)
		for f in floors:
			for i in per_floor:
				var x := -w * 0.425 + w * 0.85 * (i + 0.5) / per_floor
				if f == 0 and absf(x) < 0.5 + win_w * 0.5 + 0.15:
					continue # leave room for the door
				_window(kit, window, trim, Vector3(x, PLINTH + floor_h * (f + 0.5), front + 0.03), Vector2(win_w, win_h))

	# Portico of columns (with a pediment on grand buildings).
	var porch := 0.0
	var columns := clampi(_int(recipe, "columns", 0), 0, 6)
	if columns > 0:
		var column_color := _color(recipe, "column_color", trim)
		var pw := minf(w * 0.7, columns * 0.9)
		var col_h := minf(h, floor_h * 2.0)
		porch = 1.3
		kit.box(STONE, Vector3(pw + 0.7, PLINTH + 0.05, porch), Vector3(0, (PLINTH + 0.05) * 0.5, front + porch * 0.5))
		for i in columns:
			var x := 0.0 if columns == 1 else -pw * 0.5 + pw * i / (columns - 1)
			kit.cylinder(column_color, 0.15, col_h, Vector3(x, PLINTH + col_h * 0.5, front + porch - 0.35), 10)
		kit.box(column_color, Vector3(pw + 0.6, 0.3, porch), Vector3(0, PLINTH + col_h + 0.15, front + porch * 0.5))
		if kind in CEREMONIAL or roof_style == "pitched":
			var pediment := MeshInstance3D.new()
			var prism := PrismMesh.new()
			prism.size = Vector3(pw + 0.6, 0.75, porch)
			pediment.mesh = prism
			pediment.material_override = kit.mat(column_color)
			pediment.position = Vector3(0, PLINTH + col_h + 0.3 + 0.375, front + porch * 0.5)
			anchors["pediment_front"] = Vector3(0, PLINTH + col_h + 0.3 + 0.28, front + porch + 0.02)
			kit.root.add_child(pediment)

	# Awning over the ground floor.
	if _flag(recipe, "awning"):
		var awning := kit.box(_color(recipe, "awning_color", Color(0.2, 0.55, 0.35)), Vector3(w * 0.92, 0.08, 1.1),
			Vector3(0, PLINTH + minf(floor_h * 0.88, 2.4), front + 0.5))
		awning.rotation.x = deg_to_rad(18.0)

	# Roof.
	var height := top
	match roof_style:
		"pitched":
			var rh := clampf(minf(w, d) * 0.35, 0.8, 2.4)
			var ridge := MeshInstance3D.new()
			var prism := PrismMesh.new()
			prism.size = Vector3(d + 0.4, rh, w + 0.3) # rotated so the ridge runs left-right
			ridge.mesh = prism
			ridge.material_override = kit.mat(roof)
			ridge.rotation.y = PI * 0.5
			ridge.position = Vector3(0, top + rh * 0.5, 0)
			kit.root.add_child(ridge)
			height = top + rh
		"dome":
			var r := clampf(minf(w, d) * 0.32, 1.0, 2.6)
			kit.box(roof.darkened(0.25), Vector3(w + 0.2, 0.25, d + 0.2), Vector3(0, top + 0.125, 0))
			kit.cylinder(trim, r * 1.02, 0.6, Vector3(0, top + 0.55, 0), 16)
			var dome := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = r
			sphere.height = r * 2.2
			sphere.is_hemisphere = true
			sphere.radial_segments = 16
			sphere.rings = 6
			dome.mesh = sphere
			dome.material_override = kit.mat(roof)
			dome.position = Vector3(0, top + 0.85, 0)
			kit.root.add_child(dome)
			kit.cylinder(roof.darkened(0.15), 0.2, 0.5, Vector3(0, top + 0.85 + r * 1.1 + 0.25, 0), 8)
			height = top + 0.85 + r * 1.1 + 0.5
		"mansard":
			kit.box(roof, Vector3(w + 0.2, 0.4, d + 0.2), Vector3(0, top + 0.2, 0))
			kit.box(roof, Vector3(w - 0.4, 0.4, d - 0.4), Vector3(0, top + 0.6, 0))
			kit.box(roof.lightened(0.1), Vector3(w - 0.9, 0.12, d - 0.9), Vector3(0, top + 0.86, 0))
			height = top + 0.92
		"spire":
			kit.box(roof, Vector3(w + 0.2, 0.3, d + 0.2), Vector3(0, top + 0.15, 0))
			var sh := clampf(h * 0.6, 1.5, 4.0)
			_cone(kit, roof, minf(w, d) * 0.2, sh, Vector3(0, top + 0.3 + sh * 0.5, -d * 0.1))
			height = top + 0.3 + sh
		_: # flat, with a parapet and a little rooftop box
			kit.box(roof, Vector3(w + 0.2, 0.3, d + 0.2), Vector3(0, top + 0.15, 0))
			kit.box(roof.darkened(0.15), Vector3(w * 0.3, 0.5, d * 0.3), Vector3(w * 0.2, top + 0.55, -d * 0.2))
			height = top + 0.8

	# Tower rising from the middle.
	var tower := _choice(recipe, "tower", ["none", "spire", "dome", "clock", "flat"], "none")
	if tower != "none":
		var tower_color := _color(recipe, "tower_color", trim)
		var tw := clampf(w * 0.2, 1.0, 2.0)
		var th := clampf(h * 0.55, 1.5, 4.5)
		var base := maxf(top, height - 0.6)
		var tz := -d * 0.15
		kit.box(tower_color, Vector3(tw, th, tw), Vector3(0, base + th * 0.5, tz))
		anchors["tower_front"] = Vector3(0, base + th * 0.5, tz + tw * 0.5 + 0.02)
		var tower_top := base + th
		match tower:
			"spire":
				_cone(kit, roof, tw * 0.62, tw * 1.8, Vector3(0, tower_top + tw * 0.9, tz))
				tower_top += tw * 1.8
			"dome":
				var cap := MeshInstance3D.new()
				var ball := SphereMesh.new()
				ball.radius = tw * 0.55
				ball.height = tw * 1.1
				ball.is_hemisphere = true
				ball.radial_segments = 12
				ball.rings = 4
				cap.mesh = ball
				cap.material_override = kit.mat(roof)
				cap.position = Vector3(0, tower_top, tz)
				kit.root.add_child(cap)
				tower_top += tw * 0.55
			"clock":
				var face := kit.cylinder(Color(0.97, 0.95, 0.88), tw * 0.32, 0.06, Vector3(0, tower_top - tw * 0.5, tz + tw * 0.5 + 0.03), 16)
				face.rotation.x = PI * 0.5
				kit.box(Color(0.15, 0.15, 0.18), Vector3(0.05, tw * 0.25, 0.02), Vector3(0, tower_top - tw * 0.5 + tw * 0.1, tz + tw * 0.5 + 0.07))
				_cone(kit, roof, tw * 0.62, tw * 1.0, Vector3(0, tower_top + tw * 0.5, tz))
				tower_top += tw
			_:
				kit.box(roof, Vector3(tw + 0.2, 0.25, tw + 0.2), Vector3(0, tower_top + 0.125, tz))
				tower_top += 0.25
		height = maxf(height, tower_top)

	# Freestanding name sign out front, like the built-in places.
	var sign_text := _text(recipe, "sign_text", "").substr(0, 20)
	if not sign_text.is_empty():
		var sign_w := clampf(sign_text.length() * 0.2 + 0.7, 1.4, 3.2)
		var at := Vector3(-total_w * 0.5 + sign_w * 0.5, 0, front + porch + 1.6)
		kit.box(STONE, Vector3(sign_w + 0.2, 0.35, 0.4), at + Vector3(0, 0.175, 0))
		kit.box(_color(recipe, "sign_color", Color(0.25, 0.45, 0.35)), Vector3(sign_w, 0.6, 0.12), at + Vector3(0, 0.65, 0))
		var label := Label3D.new()
		label.text = sign_text
		label.font = UiStyle.bold()
		label.font_size = 64
		label.pixel_size = 0.0038
		label.outline_size = 0
		label.modulate = _color(recipe, "sign_text_color", Color.WHITE)
		label.position = at + Vector3(0, 0.65, 0.07)
		kit.root.add_child(label)

	# A few trees around it.
	var trees := clampi(_int(recipe, "trees", 2), 0, 4)
	for i in trees:
		var side := -1.0 if i % 2 == 0 else 1.0
		kit.tree(Vector3(side * (total_w * 0.5 + 1.3), 0, front - 0.6 - (i / 2) * 2.4))

	var footprint := Rect2(Vector2(-total_w * 0.5, -d * 0.5), Vector2(total_w, d + porch))
	kit.walls(footprint, h)

	var flag: Variant = null
	var flag_colors: Variant = recipe.get("flag_colors")
	if flag_colors is Array and not (flag_colors as Array).is_empty() and Color.html_is_valid(str(flag_colors[0])):
		var accent := Color.html(str(flag_colors[1])) if flag_colors.size() > 1 and Color.html_is_valid(str(flag_colors[1])) else Color.WHITE
		flag = {"colors": [Color.html(str(flag_colors[0])), accent]}
	return {"model": kit.root, "footprint": footprint, "height": height, "flag": flag, "anchors": anchors}


static func _window(kit: ModelKit, glass: Color, trim: Color, at: Vector3, size: Vector2) -> void:
	kit.box(glass, Vector3(size.x, size.y, 0.05), at)
	kit.box(trim, Vector3(size.x + 0.14, 0.07, 0.1), at + Vector3(0, -size.y * 0.5 - 0.03, 0.02)) # sill


static func _cone(kit: ModelKit, color: Color, radius: float, height: float, at: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = radius
	cone.height = height
	cone.radial_segments = 10
	cone.rings = 1
	mesh.mesh = cone
	mesh.material_override = kit.mat(color)
	mesh.position = at
	kit.root.add_child(mesh)


static func _num(r: Dictionary, key: String, fallback: float, lo: float, hi: float) -> float:
	var v: Variant = r.get(key)
	return clampf(float(v), lo, hi) if (v is float or v is int) else fallback


static func _int(r: Dictionary, key: String, fallback: int) -> int:
	var v: Variant = r.get(key)
	return int(v) if (v is float or v is int) else fallback


static func _flag(r: Dictionary, key: String) -> bool:
	return r.get(key) is bool and r.get(key)


static func _text(r: Dictionary, key: String, fallback: String) -> String:
	var v: Variant = r.get(key)
	return (v as String).strip_edges() if v is String else fallback


static func _choice(r: Dictionary, key: String, options: Array, fallback: String) -> String:
	var v := _text(r, key, fallback)
	return v if v in options else fallback


static func _color(r: Dictionary, key: String, fallback: Color) -> Color:
	var v := _text(r, key, "")
	return Color.html(v) if not v.is_empty() and Color.html_is_valid(v) else fallback
