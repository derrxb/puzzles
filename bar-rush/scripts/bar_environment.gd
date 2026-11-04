# bar_environment.gd
#
# Attached to the imported "Old bar" model (BarEnvironment in Main.tscn).
# The game uses a top-down angled camera that looks INTO the room, so the
# model's ceiling and overhead frame get in the way. This hides those meshes on
# load (names are from the glTF: FrontSide_N), leaving the walls, bar, shelves
# and furniture intact:
#   FrontSide_4  - ceiling panel
#   FrontSide_10 - overhead beam
#   FrontSide_16 - overhead beam
#   FrontSide_28 - the overhead frame (diagonal rafters + perimeter top rails)
#   FrontSide_6/17/33/46/59/66 - overhead beam/rafter layers + perimeter railings
#     that cross the view at low angles (all elevated: AABB bottom > 1.6, so none
#     are floor-standing walls).
# Add more names here if other overhead pieces ever intrude.
extends Node3D

const HIDDEN_MESHES: Array[String] = [
	"FrontSide_4", "FrontSide_10", "FrontSide_16", "FrontSide_28",
	"FrontSide_6", "FrontSide_17", "FrontSide_33", "FrontSide_46",
	"FrontSide_59", "FrontSide_66",
]


func _ready() -> void:
	for mesh_name in HIDDEN_MESHES:
		var node := find_child(mesh_name, true, false)
		if node:
			node.visible = false
