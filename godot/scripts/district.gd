class_name District
extends Node3D
## A neighbourhood of the town: a lightly tinted lawn with a row of building
## lots that all face the camera (+Z), and a wooden signpost with its name.
## Empty lots show a dirt plot with corner stakes until a place moves in.
##
## Districts sit on a fixed grid (see SLOTS); the town grows a new one when
## every lot is taken, so lots of places never pile up in one spot.

const LOTS := [-12.0, 0.0, 12.0] # lot x offsets; filled middle first (see FILL_ORDER)
const FILL_ORDER := [1, 0, 2]
const WIDTH := 36.0
const DEPTH := 20.0

## Grid of district slots (Montreal neighbourhoods). The first four always exist.
const SLOTS := [
	{"id": "downtown", "name": "Downtown", "at": Vector3(0, 0, 0), "tint": Color(0.64, 0.64, 0.35)},
	{"id": "old_montreal", "name": "Old Montréal", "at": Vector3(0, 0, 26), "tint": Color(0.67, 0.61, 0.36)},
	{"id": "islands", "name": "The Islands", "at": Vector3(40, 0, 26), "tint": Color(0.57, 0.64, 0.36)},
	{"id": "cote_des_neiges", "name": "Côte-des-Neiges", "at": Vector3(-40, 0, 0), "tint": Color(0.58, 0.62, 0.34)},
	{"id": "plateau", "name": "Plateau", "at": Vector3(40, 0, 0), "tint": Color(0.68, 0.58, 0.34)},
	{"id": "mile_end", "name": "Mile End", "at": Vector3(40, 0, -26), "tint": Color(0.62, 0.60, 0.38)},
	{"id": "outremont", "name": "Outremont", "at": Vector3(0, 0, -26), "tint": Color(0.60, 0.65, 0.37)},
	{"id": "saint_henri", "name": "Saint-Henri", "at": Vector3(-40, 0, 26), "tint": Color(0.66, 0.62, 0.33)},
]

var district_id := ""
var display_name := ""
var slot := 0
## Location id in each lot ("" = free).
var occupants: Array[String] = ["", "", ""]

var _plots: Array[Node3D] = []


static func slot_index(id: String) -> int:
	for i in SLOTS.size():
		if SLOTS[i].id == id:
			return i
	return -1


func _init(slot_number: int) -> void:
	slot = slot_number
	var info: Dictionary = SLOTS[slot]
	district_id = info.id
	display_name = info.name
	name = "District_" + district_id
	position = info.at
	_build(info.tint)


func _build(tint: Color) -> void:
	var kit := ModelKit.new("Ground")
	add_child(kit.root)
	# Rounded lawn patch (a squashed disc) slightly lighter than the map.
	var lawn := kit.cylinder(tint, 1.0, 0.02, Vector3(0, -0.002, 0), 40)
	lawn.scale = Vector3(WIDTH * 0.5, 1.0, DEPTH * 0.5)
	# Signpost at the front-left corner with the district's name.
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
	# Empty-lot plots.
	for i in LOTS.size():
		var plot := Node3D.new()
		plot.position = lot_offset(i)
		kit.root.add_child(plot)
		kit.box(Color(0.55, 0.42, 0.28), Vector3(7.0, 0.02, 5.0), Vector3(0, 0.008, 0), plot)
		for corner in [Vector3(-3.4, 0, -2.4), Vector3(3.4, 0, -2.4), Vector3(-3.4, 0, 2.4), Vector3(3.4, 0, 2.4)]:
			kit.box(Color(0.80, 0.62, 0.40), Vector3(0.12, 0.5, 0.12), corner + Vector3(0, 0.25, 0), plot)
		_plots.append(plot)


func lot_offset(lot: int) -> Vector3:
	return Vector3(LOTS[lot], 0.0, 0.0)


func lot_position(lot: int) -> Vector3:
	return position + lot_offset(lot)


## First free lot in fill order, or -1.
func free_lot() -> int:
	for lot: int in FILL_ORDER:
		if occupants[lot].is_empty():
			return lot
	return -1


func is_free(lot: int) -> bool:
	return lot >= 0 and lot < occupants.size() and occupants[lot].is_empty()


func occupy(lot: int, location_id: String) -> void:
	occupants[lot] = location_id
	_plots[lot].visible = false


func release(location_id: String) -> void:
	for lot in occupants.size():
		if occupants[lot] == location_id:
			occupants[lot] = ""
			_plots[lot].visible = true
