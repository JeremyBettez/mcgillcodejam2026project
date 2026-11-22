class_name District
extends Node3D
## A neighbourhood of the town: a lightly tinted lawn with a wooden signpost.
## Purely a label on the land: places stand wherever the player puts them, and
## a neighbourhood appears under any grid cell that has a place in it (see
## main.gd `_sync_districts`). The land itself has no edge.
##
## Cells are CELL_W x CELL_D metres; cell (0, 0) is centred on the origin.

const CELL_W := 40.0
const CELL_D := 26.0
const WIDTH := 36.0 # lawn patch size (a little smaller than a cell)
const DEPTH := 20.0

## Named neighbourhoods at known cells (Montreal). Other cells take a name
## from EXTRA_NAMES, and past those a numbered one.
const SLOTS := [
	{"id": "downtown", "name": "Downtown", "cell": Vector2i(0, 0), "tint": Color(0.64, 0.64, 0.35)},
	{"id": "old_montreal", "name": "Old Montréal", "cell": Vector2i(0, 1), "tint": Color(0.67, 0.61, 0.36)},
	{"id": "islands", "name": "The Islands", "cell": Vector2i(1, 1), "tint": Color(0.57, 0.64, 0.36)},
	{"id": "cote_des_neiges", "name": "Côte-des-Neiges", "cell": Vector2i(-1, 0), "tint": Color(0.58, 0.62, 0.34), "signpost": false},
	{"id": "plateau", "name": "Plateau", "cell": Vector2i(1, 0), "tint": Color(0.68, 0.58, 0.34)},
	{"id": "mile_end", "name": "Mile End", "cell": Vector2i(1, -1), "tint": Color(0.62, 0.60, 0.38)},
	{"id": "outremont", "name": "Outremont", "cell": Vector2i(0, -1), "tint": Color(0.60, 0.65, 0.37)},
	{"id": "saint_henri", "name": "Saint-Henri", "cell": Vector2i(-1, 1), "tint": Color(0.66, 0.62, 0.33)},
	{"id": "verdun", "name": "Verdun", "cell": Vector2i(0, 2), "tint": Color(0.63, 0.63, 0.40)},
	{"id": "rosemont", "name": "Rosemont", "cell": Vector2i(1, 2), "tint": Color(0.69, 0.60, 0.37)},
	{"id": "westmount", "name": "Westmount", "cell": Vector2i(-1, -1), "tint": Color(0.57, 0.63, 0.38)},
	{"id": "little_italy", "name": "Little Italy", "cell": Vector2i(0, -2), "tint": Color(0.66, 0.64, 0.36)},
	{"id": "hochelaga", "name": "Hochelaga", "cell": Vector2i(2, 0), "tint": Color(0.62, 0.58, 0.35)},
	{"id": "lachine", "name": "Lachine", "cell": Vector2i(-1, 2), "tint": Color(0.60, 0.66, 0.39)},
]
const EXTRA_NAMES := [
	"Griffintown", "Villeray", "Ahuntsic", "Saint-Laurent", "LaSalle",
	"Pointe-Claire", "Anjou", "Montréal-Nord", "Parc-Ex", "Notre-Dame-de-Grâce",
	"Saint-Michel", "Rivière-des-Prairies", "Pointe-Saint-Charles", "Shaughnessy",
	"Ville-Marie", "Petite-Patrie", "Cartierville", "Dorval", "Lasalle Shore",
	"Mercier", "Côte-Saint-Luc", "Hampstead", "Mont-Royal", "Saint-Léonard",
]
## Where saves from before free placement put each lot (x offset in its district).
const OLD_LOTS := [-12.0, 0.0, 12.0]

var district_id := ""
var display_name := ""
var cell := Vector2i.ZERO


## The grid cell a world point falls in.
static func cell_of(point: Vector3) -> Vector2i:
	return Vector2i(roundi(point.x / CELL_W), roundi(point.z / CELL_D))


static func center_of(c: Vector2i) -> Vector3:
	return Vector3(c.x * CELL_W, 0.0, c.y * CELL_D)


## {id, name, tint, signpost} for any cell: a named slot, or a generated one.
static func info_for(c: Vector2i) -> Dictionary:
	for info: Dictionary in SLOTS:
		if info.cell == c:
			return {"id": info.id, "name": info.name, "tint": info.tint, "signpost": info.get("signpost", true)}
	# Stable pseudo-random pick per cell, so a cell always has the same name.
	var h := absi(hash(c))
	var id := "cell_%d_%d" % [c.x, c.y]
	var name_ := str(EXTRA_NAMES[h % EXTRA_NAMES.size()])
	# Two far-apart cells can draw the same name; number the repeats.
	var round_ := (h / EXTRA_NAMES.size()) % 4
	if round_ > 0:
		name_ += " %d" % (round_ + 1)
	var tint := Color(0.60, 0.62, 0.35).lerp(Color(0.68, 0.60, 0.37), float(h % 97) / 96.0)
	return {"id": id, "name": name_, "tint": tint, "signpost": true}


## A saved {district, lot} from before free placement, as a world position
## (or null if the district id isn't one of the named ones).
static func old_lot_position(district_id_: String, lot: int) -> Variant:
	for info: Dictionary in SLOTS:
		if info.id == district_id_ and lot >= 0 and lot < OLD_LOTS.size():
			return center_of(info.cell) + Vector3(OLD_LOTS[lot], 0.0, 0.0)
	return null


func _init(c: Vector2i) -> void:
	cell = c
	var info := info_for(c)
	district_id = info.id
	display_name = info.name
	name = "District_" + district_id
	position = center_of(c)
	_build(info.tint, info.signpost)


func _build(tint: Color, signpost: bool) -> void:
	var kit := ModelKit.new("Ground")
	add_child(kit.root)
	# Rounded lawn patch (a squashed disc) slightly lighter than the map.
	var lawn := kit.cylinder(tint, 1.0, 0.02, Vector3(0, -0.002, 0), 40)
	lawn.scale = Vector3(WIDTH * 0.5, 1.0, DEPTH * 0.5)
	# Signpost at the front-left corner with the district's name (a slot can
	# turn it off with "signpost": false, e.g. when it would stand in front of
	# a landmark).
	if signpost:
		var post_at := Vector3(-WIDTH * 0.5 + 1.0, 0, DEPTH * 0.5 - 1.0)
		kit.cylinder(ModelKit.TRUNK, 0.08, 1.8, post_at + Vector3(0, 0.9, 0), 6)
		kit.box(Color(0.82, 0.62, 0.40), Vector3(2.6, 0.62, 0.1), post_at + Vector3(0.9, 1.55, 0))
		var label := Label3D.new()
		label.text = display_name
		label.font = UiStyle.bold()
		label.font_size = 64
		label.pixel_size = 0.0042
		label.outline_size = 0
		label.modulate = UiStyle.BROWN
		label.position = post_at + Vector3(0.9, 1.55, 0.06)
		kit.root.add_child(label)
