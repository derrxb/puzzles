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
#    camera". We only do this for the big WALL-shaped meshes, though: a first pass
#    that collided every mesh turned every free-standing prop (arcade machine,
#    jukebox, vending machine, potted plants) into a solid obstacle, and the player
#    kept getting wedged in the pockets between them. So _looks_like_wall() keeps
#    just the room shell + back walls (tall, long, thin), which is what the camera
#    and "don't leave the room" actually need. Props stay walk-through (you can
#    brush past them, which is far better than getting stuck), and the counter,
#    tables and register keep their own hand-placed colliders from before.
extends Node3D

# A mesh counts as a wall (gets a collider) when it is tall, long, and thin in one
# horizontal direction -- i.e. a slab standing on the floor. Sizes are in world
# (game) units, so this is robust to the model's odd internal scale. Props like the
# arcade cabinet are too short/stubby to match and are left pass-through.
const WALL_MIN_HEIGHT := 1.5   # at least waist-to-head tall
const WALL_MIN_LENGTH := 2.0   # runs for a couple of metres
const WALL_MAX_THICK := 0.9    # thin in its other horizontal axis

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


# Walk the model tree and give every VISIBLE, WALL-shaped mesh a trimesh collider
# that matches its triangles exactly. Skipping the hidden overhead meshes and the
# free-standing props keeps the player from being blocked by things they either
# can't see or should be able to brush past.
func _add_collision(node: Node, hidden: Dictionary) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null and not hidden.has(child.name):
			if _looks_like_wall(child):
				# create_trimesh_collision() adds a StaticBody3D child using the
				# mesh's own faces, on collision layer 1 -- the layer the player
				# body collides with and the spring-arm camera retracts from.
				child.create_trimesh_collision()
		_add_collision(child, hidden)


# True when the mesh's world-space bounding box is a tall, long, thin slab -- a
# wall. Walls are flat, so a trimesh collider on them has no concave pockets to
# wedge in.
func _looks_like_wall(mi: MeshInstance3D) -> bool:
	var aabb := mi.get_aabb()
	var gt := mi.global_transform
	var mn := Vector3.INF
	var mx := -Vector3.INF
	for i in 8:
		var corner := aabb.position + Vector3(
			aabb.size.x * (i & 1), aabb.size.y * ((i >> 1) & 1), aabb.size.z * ((i >> 2) & 1))
		var p := gt * corner
		mn = Vector3(minf(mn.x, p.x), minf(mn.y, p.y), minf(mn.z, p.z))
		mx = Vector3(maxf(mx.x, p.x), maxf(mx.y, p.y), maxf(mx.z, p.z))
	var size := mx - mn
	var thin := minf(size.x, size.z)
	var long := maxf(size.x, size.z)
	return size.y >= WALL_MIN_HEIGHT and long >= WALL_MIN_LENGTH and thin <= WALL_MAX_THICK
