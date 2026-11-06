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

# --- Beer tower (the visual dispenser the taps belong to) ---------------------
# A "Beer tower" glTF model (CC-BY-4.0, chris_models) sits on the bar as the
# dispenser. It is purely visual; the three colored knobs below are still what the
# game detects for pouring, so gameplay is unchanged. These @export knobs let the
# tower be nudged in the editor without touching code.
const BEER_TOWER := preload("res://assets/beer_tower/scene.gltf")
@export var tower_scale: float = 1.55
# Lifted so the faucets clear the counter top (base ~y1.1 = legs on the bar); the
# taller scale gives headroom under the spouts so a pour is visible.
@export var tower_offset := Vector3(0.0, 1.9, 0.1)   # local, relative to the counter
@export var tower_yaw_deg: float = 180.0             # face the player side (-Z)

# The three tap meshes, in beer order: index 0 = Lager, 1 = Amber, 2 = Stout.
# (They are named TapRed/TapBlue/TapGreen in Counter.tscn from the old version;
# we simply recolor them here to the beer colors and shrink them into knobs.)
var _taps: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("counter")

	# Turn the old tap cubes into small colored knobs that sit on the FRONT of the
	# tower (player side), one per beer, so you can tell which spout is which. Their
	# X/Z is what nearest_tap() detects, so pouring still works by standing in front
	# of a knob.
	var knob := SphereMesh.new()
	knob.radius = 0.05
	knob.height = 0.1
	var tap_names := ["TapRed", "TapBlue", "TapGreen"]
	for i in tap_names.size():
		var tap := get_node_or_null(tap_names[i]) as MeshInstance3D
		if tap == null:
			continue
		_taps.append(tap)
		tap.mesh = knob
		# Small colored bead at each faucet NOZZLE (low, just above where the glass
		# sits) -- so it reads as the tap output, not a big ball floating up high.
		tap.position = Vector3((i - 1) * 1.4, 1.62, -0.32)
		tap.scale = Vector3.ONE
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Globals.color_for(i)
		mat.emission_enabled = true          # glow a touch so the beer colour reads
		mat.emission = Globals.color_for(i)
		mat.emission_energy_multiplier = 0.5
		tap.material_override = mat

	_add_tower()


# Instance the beer-tower model on the counter top.
func _add_tower() -> void:
	var tower := BEER_TOWER.instantiate()
	add_child(tower)
	tower.position = tower_offset
	tower.rotation_degrees = Vector3(0, tower_yaw_deg, 0)
	tower.scale = Vector3.ONE * tower_scale


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
