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

# Room footprint, centered on the origin. The camera looks from the +Z side, so
# the +Z edge is left open (the counter sits there).
const ROOM_WIDTH := 16.0
const ROOM_DEPTH := 12.0
const WALL_HEIGHT := 3.0
const WALL_THICK := 0.3
const DOOR_WIDTH := 3.0


func _ready() -> void:
	_build_room()
	_place_furniture()


# ------------------------------------------------------------------------------
# Furniture
# ------------------------------------------------------------------------------
func _place_furniture() -> void:
	# Bar stools for SINGLES: flanking the taps along the front of the counter
	# (the counter is at z = 5; taps sit in the middle, so stools go to the sides).
	var bar_x := [-3.5, -2.5, 2.5, 3.5]
	for i in bar_x.size():
		_place(STOOL, Vector3(bar_x[i], 0, 4.0), Globals.SeatKind.BAR, "Bar %d" % (i + 1))

	# Small tables for DUOS.
	var smalls := [Vector3(-5, 0, -0.5), Vector3(5, 0, -0.5), Vector3(0, 0, 1.0)]
	for i in smalls.size():
		_place(SMALL_TABLE, smalls[i], Globals.SeatKind.SMALL, "Table %d" % (i + 1))

	# Big tables for GROUPS, toward the back where there's room for 5 seats.
	var larges := [Vector3(-4, 0, -3.5), Vector3(4, 0, -3.5)]
	for i in larges.size():
		_place(LARGE_TABLE, larges[i], Globals.SeatKind.LARGE, "Big Table %d" % (i + 1))


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


func _add_box(center: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = center
	add_child(body)

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
