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
#    camera".
#
#    But "solid to the body" and "solid to the camera" are two different needs, and
#    lumping them together caused trouble both ways: collide NOTHING and the camera
#    slides through the walls and shows the void behind them; collide EVERYTHING and
#    every free-standing prop (arcade cabinet, jukebox, vending machine, plants)
#    becomes a solid obstacle the player wedges between. So we split them across two
#    collision layers:
#      - WALL-shaped meshes (tall, long, thin slabs -- the room shell + back walls)
#        go on layer 1, which BOTH the player body and the camera collide with. You
#        can't walk through a wall, and the camera stops at it.
#      - every other mesh (the props) goes on layer 4, a "camera-only" layer: the
#        follow-camera's spring arm retracts off it (so it never reveals the void),
#        but the player body -- which only collides with layer 1 -- walks right
#        through, so no more getting stuck on the furniture.
#    The counter, tables and register keep their own hand-placed layer-1 colliders,
#    and the invisible perimeter walls from main.gd still fence the room.
extends Node3D

# A mesh counts as a wall (solid to the body) when it is tall, long, and thin in one
# horizontal direction -- i.e. a slab standing on the floor. Sizes are in world
# (game) units, so this is robust to the model's odd internal scale. Props like the
# arcade cabinet are too short/stubby to match, so they land on the camera-only
# layer instead.
const WALL_MIN_HEIGHT := 1.5   # at least waist-to-head tall
const WALL_MIN_LENGTH := 2.0   # runs for a couple of metres
const WALL_MAX_THICK := 0.9    # thin in its other horizontal axis

# Bit 3 (value 8) == "layer 4" in the editor. The bar model's props sit here so the
# camera (whose spring arm masks layers 1 and 4) retracts off them while the player
# body (which masks only layer 1) passes through. Keep this in sync with the spring
# arm's collision_mask in player.gd.
const CAMERA_ONLY_LAYER := 1 << 3

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


# Walk the model tree and give every VISIBLE mesh a trimesh collider matching its
# triangles. Walls go on layer 1 (solid to body + camera); everything else goes on
# the camera-only layer. Hidden overhead meshes are skipped -- you can't see them,
# so neither the body nor the camera should catch on them.
func _add_collision(node: Node, hidden: Dictionary) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null and not hidden.has(child.name):
			var body := _make_collider(child)
			if body != null and not _looks_like_wall(child):
				# A prop: camera retracts off it, but the body passes through.
				body.collision_layer = CAMERA_ONLY_LAYER
				body.collision_mask = 0
		_add_collision(child, hidden)


# create_trimesh_collision() builds a StaticBody3D child (layer 1 by default) from
# the mesh's faces; return it so the caller can move props to the camera-only layer.
func _make_collider(mi: MeshInstance3D) -> StaticBody3D:
	var before := mi.get_child_count()
	mi.create_trimesh_collision()
	for i in range(before, mi.get_child_count()):
		var c := mi.get_child(i)
		if c is StaticBody3D:
			return c
	return null


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
