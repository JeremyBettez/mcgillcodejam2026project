class_name MarianopolisModel
extends RefCounted
## Marianopolis College (Westmount, next to Côte-des-Neiges): a grand grey-stone
## college with a long symmetrical front, lower side wings, a columned entrance
## and a copper cupola, built in code from a hand-written recipe with
## RecipeModel (the same builder Quick build places use). Faces +Z.

const RECIPE := {
	"kind": "university",
	"width": 7.5,
	"depth": 6.0,
	"height": 6.4,
	"floors": 3,
	"wall_color": "#b8b2a4",
	"trim_color": "#ece6d8",
	"roof_style": "pitched",
	"roof_color": "#5d8f7e",
	"wings": true,
	"columns": 4,
	"column_color": "#ece6d8",
	"windows_per_floor": 5,
	"window_color": "#2f3e52",
	"door_color": "#3e2b20",
	"awning": false,
	"awning_color": "#000000",
	"tower": "dome",
	"tower_color": "#d9d2c2",
	"sign_text": "Marianopolis College",
	"sign_color": "#1f3a6b",
	"sign_text_color": "#ffffff",
	"flag_colors": [],
	"trees": 4,
}


## Same result shape as RecipeModel.build(). Adds the college emblem
## (BrandLogos "marianopolis", a navy shield with a gold rim and a white M; a
## stand-in, not the official logo) on the cupola tower and the pediment.
static func build() -> Dictionary:
	var built := RecipeModel.build(RECIPE)
	var model: Node3D = built.model
	model.name = "Marianopolis"
	var anchors: Dictionary = built.get("anchors", {})
	for spot: Array in [["tower_front", 1.05], ["pediment_front", 0.5]]:
		if anchors.has(spot[0]):
			var emblem := BrandLogos.quad("marianopolis", spot[1])
			emblem.position = anchors[spot[0]]
			model.add_child(emblem)
	return built
