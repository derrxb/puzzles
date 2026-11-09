# bar_environment.gd
#
# Attached to the imported "Old bar" model (BarEnvironment in Main.tscn).
#
# Two jobs on load:
#
# 1. HIDE the overhead meshes. The game uses a top-down angled camera that looks
#    INTO the room, so the model's ceiling and overhead frame get in the way.
#    (names are from the glTF: FrontSide_N)
#      FrontSide_4  - ceiling panel
#      FrontSide_10 - overhead beam
#      FrontSide_16 - overhead beam
#      FrontSide_28 - the overhead frame (diagonal rafters + perimeter top rails)
#      FrontSide_6/17/33/46/59/66 - overhead beam/rafter layers + perimeter railings
#        that cross the view at low angles (all elevated: AABB bottom > 1.6, so none
#        are floor-standing walls).
#    Add more names here if other overhead pieces ever intrude.
#
# 2. GIVE the model collision. Until now the model was purely decorative -- the
#    only physics came from a few hand-placed invisible boxes (the room perimeter,
#    the counter, the tables), so you could walk straight THROUGH the visible bar,
#    shelves and back wall, and the follow-camera could slide through those same
#    walls and show the empty void behind them. We fix both at once by building a
#    collider that matches the model's actual geometry: for every visible mesh we
#    call create_trimesh_collision(), which adds a StaticBody3D whose shape is the
#    mesh's own triangles. Now "solid to the eye" == "solid to the body and the
#    camera". The hidden overhead pieces are skipped (you can't see them, so they
#    shouldn't block you). The model's own floor DOES get a collider, but the flat
#    invisible floor at y=0 from main.gd is what actually carries the player, so
#    the two just sit coincident -- no jitter.
extends Node3D

const HIDDEN_MESHES: Array[String] = [
	"FrontSide_4", "FrontSide_10", "FrontSide_16", "FrontSide_28",
	"FrontSide_6", "FrontSide_17", "FrontSide_33", "FrontSide_46",
	"FrontSide_59", "FrontSide_66",
]


func _ready() -> void:
	var hidden := {}
	for mesh_name in HIDDEN_MESHES:
		hidden[mesh_name] = true
		var node := find_child(mesh_name, true, false)
		if node:
			node.visible = false

	_add_collision(self, hidden)


# Walk the model tree and give every VISIBLE mesh a trimesh collider that matches
# its triangles exactly. Skipping the hidden overhead meshes keeps the player from
# being blocked by things they can't see.
func _add_collision(node: Node, hidden: Dictionary) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null and not hidden.has(child.name):
			# create_trimesh_collision() adds a StaticBody3D child using the mesh's
			# own faces, on collision layer 1 -- the layer the player body collides
			# with and the follow-camera's spring arm retracts from.
			child.create_trimesh_collision()
		_add_collision(child, hidden)
