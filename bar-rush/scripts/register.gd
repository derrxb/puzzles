# register.gd
#
# The cash register: a fixed spot where parties come to pay. Like the taps, it's
# "dumb" -- it just reports whether the player is standing at it and where the
# pay line forms. The GameManager runs the pay queue; the player rings people up.
extends StaticBody3D

@export var use_range: float = 2.2      # how near the player must stand to ring up
@export var line_gap: float = 1.1       # spacing between parties in the pay line
@export var line_start: float = 1.7     # distance from the register to the first spot


func _ready() -> void:
	add_to_group("register")


func is_in_range(world_position: Vector3) -> bool:
	var a := Vector2(world_position.x, world_position.z)
	var b := Vector2(global_position.x, global_position.z)
	return a.distance_to(b) <= use_range


# Where the i-th party in the pay line should stand (the line runs out into the
# room, away from the counter).
func slot_position(index: int) -> Vector3:
	return Vector3(global_position.x, 0.0, global_position.z - line_start - line_gap * index)
