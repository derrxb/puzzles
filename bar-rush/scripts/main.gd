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

	# The cash register sits at the left end of the counter; the pay line forms
	# in front of it, out into the room.
	var register := REGISTER.instantiate()
	add_child(register)
	register.global_position = Vector3(-5, 0, 4.3)


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
	var half_w := ROOM_WIDTH / 2.0
	var half_d := ROOM_DEPTH / 2.0

	# Floor: top surface at y = 0.
	_add_box(Vector3(0, -0.15, 0), Vector3(ROOM_WIDTH, 0.3, ROOM_DEPTH), Color(0.22, 0.22, 0.26))

	var wall_color := Color(0.5, 0.5, 0.55)
	var wall_y := WALL_HEIGHT / 2.0

	# Back wall split into two pieces to leave a doorway in the middle.
	var side_len := (ROOM_WIDTH - DOOR_WIDTH) / 2.0
	var side_center := DOOR_WIDTH / 2.0 + side_len / 2.0
	_add_box(Vector3(-side_center, wall_y, -half_d), Vector3(side_len, WALL_HEIGHT, WALL_THICK), wall_color)
	_add_box(Vector3(side_center, wall_y, -half_d), Vector3(side_len, WALL_HEIGHT, WALL_THICK), wall_color)

	# Left and right walls.
	_add_box(Vector3(-half_w, wall_y, 0), Vector3(WALL_THICK, WALL_HEIGHT, ROOM_DEPTH), wall_color)
	_add_box(Vector3(half_w, wall_y, 0), Vector3(WALL_THICK, WALL_HEIGHT, ROOM_DEPTH), wall_color)


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
