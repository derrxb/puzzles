# counter.gd
#
# The bar counter. It holds three TAPS, one per beer (Lager / Amber / Stout).
# The player pours by standing next to a tap and holding Space -- WHICH tap they
# stand at decides the beer, so there are no number keys to remember.
#
# The counter stays "dumb": it just recolors its taps to match the beers and
# reports which tap (if any) the player is standing near. The pouring itself
# lives in player.gd.
extends StaticBody3D

# How near the player must be to a tap to pour from it (flat X/Z distance).
@export var tap_range: float = 2.0

# The three tap meshes, in beer order: index 0 = Lager, 1 = Amber, 2 = Stout.
# (They are named TapRed/TapBlue/TapGreen in Counter.tscn from the old version;
# we simply recolor them here to the beer colors.)
var _taps: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("counter")

	var tap_names := ["TapRed", "TapBlue", "TapGreen"]
	for i in tap_names.size():
		var tap := get_node_or_null(tap_names[i]) as MeshInstance3D
		if tap == null:
			continue
		_taps.append(tap)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Globals.color_for(i)
		tap.material_override = mat


# Return the tap the player is standing closest to (within tap_range) as
# {"type": beer_index, "position": Vector3}, or an empty dictionary if none.
func nearest_tap(world_position: Vector3) -> Dictionary:
	var here := Vector2(world_position.x, world_position.z)
	var best := {}
	var best_distance := tap_range
	for i in _taps.size():
		var tap_pos := _taps[i].global_position
		var d := here.distance_to(Vector2(tap_pos.x, tap_pos.z))
		if d <= best_distance:
			best_distance = d
			best = {"type": i, "position": tap_pos}
	return best
