# main.gd
#
# Script on the root of Main.tscn. Its only job is to build the ROOM SHELL --
# the floor and walls -- in code. These are simple static boxes you can't walk
# through, so making them in code keeps Main.tscn focused on the interesting
# stuff (camera, lights, furniture, player, managers) instead of a wall of
# geometry data.
#
# Everything else (counter, tables, player, UI, GameManager) is placed visually
# in Main.tscn as nodes/scene instances -- open it in the editor to see them.
extends Node3D

# Room footprint, centered on the origin. X is width (left/right), Z is depth
# (toward/away from the camera). The camera looks from the +Z side, so we leave
# the +Z edge open (no front wall) and let the bar counter sit there instead.
const ROOM_WIDTH := 16.0
const ROOM_DEPTH := 12.0
const WALL_HEIGHT := 3.0
const WALL_THICK := 0.3
const DOOR_WIDTH := 3.0  # gap in the back wall where customers enter


func _ready() -> void:
	_build_room()


func _build_room() -> void:
	var half_w := ROOM_WIDTH / 2.0
	var half_d := ROOM_DEPTH / 2.0

	# Floor: a thin wide box whose TOP surface sits exactly at y = 0.
	_add_box(
		Vector3(0, -0.15, 0),
		Vector3(ROOM_WIDTH, 0.3, ROOM_DEPTH),
		Color(0.22, 0.22, 0.26)
	)

	var wall_color := Color(0.5, 0.5, 0.55)
	var wall_y := WALL_HEIGHT / 2.0

	# Back wall (far from camera, -Z) is split into two pieces to leave a doorway
	# in the middle. Each piece fills from the corner to the edge of the door gap.
	var side_len := (ROOM_WIDTH - DOOR_WIDTH) / 2.0
	var side_center := DOOR_WIDTH / 2.0 + side_len / 2.0
	_add_box(Vector3(-side_center, wall_y, -half_d), Vector3(side_len, WALL_HEIGHT, WALL_THICK), wall_color)
	_add_box(Vector3(side_center, wall_y, -half_d), Vector3(side_len, WALL_HEIGHT, WALL_THICK), wall_color)

	# Left and right walls run the full depth of the room.
	_add_box(Vector3(-half_w, wall_y, 0), Vector3(WALL_THICK, WALL_HEIGHT, ROOM_DEPTH), wall_color)
	_add_box(Vector3(half_w, wall_y, 0), Vector3(WALL_THICK, WALL_HEIGHT, ROOM_DEPTH), wall_color)


# Create one solid, non-walkthrough box: a StaticBody3D with a matching mesh and
# collision shape. Used for the floor and every wall.
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
