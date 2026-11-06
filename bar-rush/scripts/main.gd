# main.gd
#
# Script on the root of Main.tscn. It builds the parts of the level that are
# easier to describe in code than to hand-place in the editor:
#   1. the ROOM SHELL (floor + walls)
#   2. the FURNITURE (bar stools, small tables, big tables) and their labels
#
# The camera, lights, counter, player, door, GameManager and UI are placed
# visually in Main.tscn -- open it in the editor to see them.
extends Node3D

# Furniture scenes (all three run table.gd; what kind each is comes from
# table_type, which we set below).
const STOOL := preload("res://scenes/Stool.tscn")
const SMALL_TABLE := preload("res://scenes/Table.tscn")
const LARGE_TABLE := preload("res://scenes/LargeTable.tscn")
const REGISTER := preload("res://scenes/Register.tscn")

# Room footprint, centered on the origin. The camera looks from the +Z side, so
# the +Z edge is left open (the counter sits there).
const ROOM_WIDTH := 16.0
const ROOM_DEPTH := 12.0
const WALL_HEIGHT := 3.0
const WALL_THICK := 0.3
const DOOR_WIDTH := 3.0

# When false, the floor and walls are still built as INVISIBLE colliders (so the
# player and customers can't walk out of the room) but nothing is drawn -- the
# imported "Old bar" model in Main.tscn provides the visible room instead. Flip
# this on in the editor to see the old placeholder box room again.
@export var show_placeholder_room := false


func _ready() -> void:
	_build_room()
	_place_furniture()
	_build_lights()


# ------------------------------------------------------------------------------
# Lighting: warm "pub lamp" pools over the bar and the games room so the space
# reads cosy rather than flatly lit. Kept to a few omni lights (no shadows) for
# the GL Compatibility renderer.
# ------------------------------------------------------------------------------
func _build_lights() -> void:
	var spots := [
		Vector3(-5.0, 2.8, 2.5),   # over the register wing / west
		Vector3(0.0, 2.8, 1.5),    # over the games room / bar front
		Vector3(6.0, 2.8, 2.0),    # over the east games room
		Vector3(2.0, 2.8, 6.8),    # behind the bar (so the back isn't pitch black)
	]
	for p in spots:
		var lamp := OmniLight3D.new()
		lamp.position = p
		lamp.light_color = Color(1.0, 0.82, 0.55)
		lamp.light_energy = 4.0
		lamp.omni_range = 9.0
		lamp.omni_attenuation = 1.3
		lamp.shadow_enabled = false
		add_child(lamp)


# ------------------------------------------------------------------------------
# Furniture
# ------------------------------------------------------------------------------
func _place_furniture() -> void:
	# NOTE: furniture positions are fitted to the imported "Old bar" model's
	# visible interior floor (the bar front + the green games room, which sits
	# center-right). The model only covers roughly x:-6..8, z:-1.4..5, so seats
	# are kept inside that or customers would sit outside the walls. See the
	# BarEnvironment transform in Main.tscn.

	# Bar stools for SINGLES: placed dead-centre on the model's green plaid-topped
	# stools (three along the front of the green room at z~3.8, one on the right).
	var bar_pos := [Vector3(0.9, 0, 3.9), Vector3(2.7, 0, 3.9), Vector3(4.5, 0, 3.9), Vector3(7.0, 0, 0.3)]
	for i in bar_pos.size():
		_place(STOOL, bar_pos[i], Globals.SeatKind.BAR, "Bar %d" % (i + 1))

	# Small tables for DUOS: centred on the model's round wooden pub tables so the
	# two seats (Seat0/Seat1 at x=+/-1.1) flank each table evenly.
	var smalls := [Vector3(1.3, 0, -0.6), Vector3(4.1, 0, 0.3), Vector3(7.9, 0, -0.6)]
	for i in smalls.size():
		_place(SMALL_TABLE, smalls[i], Globals.SeatKind.SMALL, "Table %d" % (i + 1))

	# Big tables for GROUPS: the model has no large tables, so these 5-seat rings
	# sit in the two most open patches of the green games-room carpet.
	var larges := [Vector3(6.3, 0, 1.7), Vector3(2.3, 0, 1.8)]
	for i in larges.size():
		_place(LARGE_TABLE, larges[i], Globals.SeatKind.LARGE, "Big Table %d" % (i + 1))

	# The cash register sits at the EAST end of the counter. The pay line forms
	# running north (-Z) out into the games room (see register.gd slot_position), so
	# the register must sit where the games-room floor extends north of it -- i.e. in
	# region A (x >= -1.5), NOT at the old far-west spot where the line ran off into
	# the empty top-left void.
	var register := REGISTER.instantiate()
	add_child(register)
	register.global_position = Vector3(5.0, 0, 4.3)


func _place(scene: PackedScene, pos: Vector3, seat_kind: int, label: String) -> void:
	var furniture := scene.instantiate()
	add_child(furniture)
	furniture.global_position = pos
	furniture.table_type = seat_kind
	furniture.label = label


# ------------------------------------------------------------------------------
# Room shell
# ------------------------------------------------------------------------------
func _build_room() -> void:
	# Invisible collision floor + walls that hug the model's MEASURED visible floor so
	# the player can't walk off into the void AND never hits an invisible wall while
	# real floor is still visible ahead (that mismatch is what felt like getting
	# "stuck"). The floor was measured by sampling the model's floor meshes into an
	# occupancy grid: it is an L (the only void is the top-LEFT corner, x<-1.2 & z<0.8);
	# every other part is floor, all the way back to the far wall at z~9.2. So the
	# collision fills the whole L right up to the visible stone walls:
	#
	#     z=-1.3  +-------- REGION A --------+   <- games-room front (door wall)
	#             |                          |
	#     z= 0.8  +-------------+            |
	#             |  REGION B   | (A cont.)  |
	#             |  (register, |            |
	#             |   back bar) |            |
	#     z= 9.0  +-------------+------------+   <- far wall (behind the bar)
	#            x=-7.5      x=-1.2        x=9.3
	#
	# Region A = x:-1.2..9.3, z:-1.3..4.0 ;  Region B = x:-7.5..9.3, z:0.8..9.0.
	# The counter (StaticBody, x:-4..4, z:4.5..5.5) stays a solid mid-floor obstacle, so
	# you can walk the whole room -- front of the bar AND around behind it -- but can't
	# walk THROUGH the bar. The inner notch (x=-1.2) is a wide doorway: no pinch.
	var wall := Color(0.5, 0.5, 0.55)
	var floor_col := Color(0.22, 0.22, 0.26)

	# Floors (top surface at y=0); the two boxes overlap, which is fine.
	_add_floor(Vector2(-1.2, -1.3), Vector2(9.3, 4.0), floor_col)   # Region A
	_add_floor(Vector2(-7.5, 0.8), Vector2(9.3, 9.0), floor_col)    # Region B

	# Perimeter walls, traced as a closed loop around the L (corner -> corner).
	var corners := [
		Vector2(-1.2, -1.3),   # top-left of A (by the door wall)
		Vector2(9.3, -1.3),    # top-right
		Vector2(9.3, 9.0),     # bottom-right (far wall)
		Vector2(-7.5, 9.0),    # bottom-left
		Vector2(-7.5, 0.8),    # top-left of B
		Vector2(-1.2, 0.8),    # inner notch corner
	]
	for i in corners.size():
		_add_wall(corners[i], corners[(i + 1) % corners.size()], wall)


# Floor slab spanning the rectangle between XZ corners `a` and `b` (top at y=0).
func _add_floor(a: Vector2, b: Vector2, color: Color) -> void:
	var center := Vector3((a.x + b.x) / 2.0, -0.15, (a.y + b.y) / 2.0)
	var size := Vector3(absf(b.x - a.x), 0.3, absf(b.y - a.y))
	_add_box(center, size, color)


# Wall segment running along the floor edge from XZ point `a` to `b` (axis-aligned).
# Its length is padded by WALL_THICK so perpendicular walls overlap cleanly at the
# corners (no pin-hole gaps to slip through).
func _add_wall(a: Vector2, b: Vector2, color: Color) -> void:
	var center := Vector3((a.x + b.x) / 2.0, WALL_HEIGHT / 2.0, (a.y + b.y) / 2.0)
	var dx := absf(b.x - a.x)
	var dz := absf(b.y - a.y)
	var size: Vector3
	if dx >= dz:   # runs along X
		size = Vector3(dx + WALL_THICK, WALL_HEIGHT, WALL_THICK)
	else:          # runs along Z
		size = Vector3(WALL_THICK, WALL_HEIGHT, dz + WALL_THICK)
	_add_box(center, size, color)


# Adds a box as a StaticBody3D. It always gets a collision shape; the visible
# mesh is only added when `visible` is true (gated by show_placeholder_room), so
# the room can exist purely as invisible walls behind the imported bar model.
func _add_box(center: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = center
	add_child(body)

	if show_placeholder_room:
		var mesh_instance := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = size
		mesh_instance.mesh = box_mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		mesh_instance.material_override = material
		body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	collision.shape = box_shape
	body.add_child(collision)
