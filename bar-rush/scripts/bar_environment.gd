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
# Add more names here if other overhead pieces ever intrude.
extends Node3D

const HIDDEN_MESHES: Array[String] = [
	"FrontSide_4", "FrontSide_10", "FrontSide_16", "FrontSide_28",
]


func _ready() -> void:
	for mesh_name in HIDDEN_MESHES:
		var node := find_child(mesh_name, true, false)
		if node:
			node.visible = false
