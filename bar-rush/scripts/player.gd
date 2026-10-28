# player.gd
#
# The bartender you drive with WASD / arrows (camera-relative, Overcooked-style).
#
# The drink loop now uses a TRAY so you can pour a whole round and deliver it:
#   POUR  - walk to a tap and HOLD Space. The tap decides the beer. Liquid rises
#           but FOAM builds; if it overflows it's spilled. Stop pouring and the
#           foam settles, so you pour -> pause -> top off.
#   STOCK - STEP AWAY from the tap and the glass you were filling is set on your
#           tray (up to 4 beers, mixed types). A spilled glass is tossed.
#   SERVE - walk to a seated customer and press E. If your tray has the beer they
#           ordered, it's handed over (reward scaled by how well it was poured).
#
# The player never changes the score -- it calls customer.serve(); the customer
# and GameManager handle the rest.
extends CharacterBody3D

@export var move_speed: float = 6.0
@export var gravity: float = 20.0
@export var serve_range: float = 2.0

@export var pour_rate: float = 0.6      # how fast liquid rises while pouring
@export var foam_gain: float = 0.45     # how fast foam builds while pouring
@export var foam_settle: float = 1.1    # how fast foam settles when NOT pouring

const CAPACITY := 1.0
const PERFECT := 0.9
const GOOD := 0.75
const MIN_SERVE := 0.2
# Once a pour reaches this ("the green"), it is auto-added to the tray so you
# don't have to step back for it.
const AUTO_COMMIT := 0.75
const TRAY_CAP := 4                     # how many beers fit on the tray

const GLASS_H := 0.34
const GLASS_BOTTOM := -0.17

# The tray's contents: each entry is {"type": int, "quality": float}.
signal tray_changed(types: Array)
# The glass being poured right now (drives the on-screen pour meter).
signal pour_state_changed(active: bool, liquid: float, foam: float, ruined: bool, beer_type: int)

var _tray: Array = []

# The "active" glass being filled at a tap (-1 = not currently pouring one).
var _beer_type: int = -1
var _liquid: float = 0.0
var _foam: float = 0.0
var _ruined: bool = false
# After a glass finishes (auto-added to the tray, or spilled) we lock pouring
# until Space is released, so holding it down doesn't instantly pour the next.
var _pour_locked: bool = false

# Visuals (built in code at the Hold point).
var _tray_glasses: Array[MeshInstance3D] = []
var _tray_materials: Array[StandardMaterial3D] = []
var _active_root: Node3D
var _active_liquid: MeshInstance3D
var _active_liquid_mat: StandardMaterial3D
var _active_foam: MeshInstance3D

var _last_hint: String = ""


func _ready() -> void:
	add_to_group("player")
	_build_carry_visuals()
	tray_changed.emit(_tray_types())


func _physics_process(delta: float) -> void:
	_handle_movement(delta)


func _process(delta: float) -> void:
	var counter := get_tree().get_first_node_in_group("counter")
	var tap := {}
	if counter != null:
		tap = counter.nearest_tap(global_position)
	var near_tap := not tap.is_empty()

	# Releasing Space clears the pour lock, so the next pour needs a fresh press.
	if not Input.is_action_pressed("pour"):
		_pour_locked = false

	var gm := get_tree().get_first_node_in_group("game_manager")
	var register := get_tree().get_first_node_in_group("register")
	var at_register: bool = register != null and gm != null \
		and register.is_in_range(global_position) and gm.register_party() != null

	# Space is the single action key. Priority: ring up at the register > serve a
	# nearby customer > pour at a tap.
	var pouring := false
	if at_register:
		_handle_register(gm, delta)
	else:
		if gm != null and gm.register_active():
			gm.register_end()                    # we walked away from the register
		var customer := _nearest_waiting_customer()
		var can_serve := customer != null and _find_tray_glass(customer.get_order()) != -1
		if can_serve:
			if Input.is_action_just_pressed("pour"):
				_serve_to(customer)
		else:
			pouring = _handle_pour(tap, delta)

	_settle_foam(pouring, delta)
	_maybe_stock(near_tap)          # stepping away from the tap stocks a partial pour

	if Input.is_action_just_pressed("dump"):
		_dump_one()

	_update_active_visual()
	pour_state_changed.emit(_beer_type != -1, _liquid, _foam, _ruined, _beer_type)
	_update_hint(tap, near_tap, at_register, gm)


# At the register, Space rings up the front party -- how depends on their method.
func _handle_register(gm: Node, delta: float) -> void:
	if not gm.register_active():
		gm.register_begin()
	match gm.register_method():
		Globals.PayMethod.CASH:
			if Input.is_action_just_pressed("pour"):
				gm.register_cash_give()
		Globals.PayMethod.CARD:
			if Input.is_action_pressed("pour"):
				gm.register_card_swipe(delta)
			else:
				gm.register_card_release()
		Globals.PayMethod.LINE:
			if Input.is_action_just_pressed("pour"):
				gm.register_line_scan()


# ------------------------------------------------------------------------------
# MOVEMENT (camera-relative)
# ------------------------------------------------------------------------------
func _handle_movement(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	var direction := Vector3.ZERO
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var forward := -camera.global_transform.basis.z
		var right := camera.global_transform.basis.x
		forward.y = 0.0
		right.y = 0.0
		forward = forward.normalized()
		right = right.normalized()
		direction = (forward * -input.y + right * input.x)

	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	move_and_slide()

	if direction.length() > 0.1:
		var target_yaw := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 12.0 * delta)


# ------------------------------------------------------------------------------
# POURING / STOCKING THE TRAY
# ------------------------------------------------------------------------------
func _handle_pour(tap: Dictionary, delta: float) -> bool:
	if tap.is_empty() or not Input.is_action_pressed("pour") or _pour_locked:
		return false

	var tap_type: int = tap["type"]

	# Start a fresh glass if we aren't filling one (or the last was spilled/empty).
	if _beer_type == -1 or _ruined or _liquid <= 0.0:
		if _beer_type == -1 and _tray.size() >= TRAY_CAP:
			return false                 # tray is full; serve some first
		_begin_active(tap_type)

	if _beer_type != tap_type:
		return false                     # can't mix two beers in one glass

	_liquid = minf(_liquid + pour_rate * delta, CAPACITY)
	_foam += foam_gain * delta
	if _liquid + _foam >= CAPACITY:
		_ruined = true
		_foam = CAPACITY - _liquid
		_pour_locked = true                         # re-press to pour a fresh one
	elif _liquid >= AUTO_COMMIT and _tray.size() < TRAY_CAP:
		# Reached the green: auto-add to the tray, no need to step back.
		_stock_active()
		_pour_locked = true                         # re-press to pour the next
	return true


func _settle_foam(pouring: bool, delta: float) -> void:
	if pouring or _beer_type == -1 or _ruined:
		return
	_foam = maxf(0.0, _foam - foam_settle * delta)


# Stepping away from the taps finalizes the glass you were filling: a decent pour
# goes on the tray, a spilled or near-empty one is tossed. (Most good pours are
# already auto-added at the green while pouring; this covers partial pours.)
func _maybe_stock(near_tap: bool) -> void:
	if _beer_type == -1 or near_tap:
		return
	if not _ruined and _liquid >= MIN_SERVE and _tray.size() < TRAY_CAP:
		_stock_active()
	else:
		_clear_active()


# Move the active glass onto the tray.
func _stock_active() -> void:
	_tray.append({"type": _beer_type, "quality": _liquid})
	tray_changed.emit(_tray_types())
	_clear_active()


func _begin_active(beer_type: int) -> void:
	_beer_type = beer_type
	_liquid = 0.0
	_foam = 0.0
	_ruined = false


func _clear_active() -> void:
	_beer_type = -1
	_liquid = 0.0
	_foam = 0.0
	_ruined = false


# ------------------------------------------------------------------------------
# SERVING
# ------------------------------------------------------------------------------
func _serve_to(customer: Node3D) -> void:
	var wanted: int = customer.get_order()
	var idx := _find_tray_glass(wanted)
	if idx == -1:
		return                           # no matching beer on the tray
	var glass: Dictionary = _tray[idx]
	_tray.remove_at(idx)
	tray_changed.emit(_tray_types())
	customer.serve(glass["type"], glass["quality"])


# Throw away a beer you don't want (poured the wrong one). It wastes the drink,
# so the GameManager charges a small money penalty. Dumps the glass you're
# pouring first; otherwise the most recently stocked tray glass.
func _dump_one() -> void:
	var wasted := false
	if _beer_type != -1:
		wasted = _liquid >= MIN_SERVE   # only a real beer counts as wasted
		_clear_active()
	elif not _tray.is_empty():
		_tray.pop_back()
		tray_changed.emit(_tray_types())
		wasted = true

	if wasted:
		var gm := get_tree().get_first_node_in_group("game_manager")
		if gm != null and gm.has_method("waste_drink"):
			gm.waste_drink()


func _find_tray_glass(beer_type: int) -> int:
	for i in _tray.size():
		if _tray[i]["type"] == beer_type:
			return i
	return -1


func _nearest_waiting_customer() -> Node3D:
	var best: Node3D = null
	var best_distance := serve_range
	for customer in get_tree().get_nodes_in_group("customers"):
		if not customer.is_waiting():
			continue
		var d := global_position.distance_to(customer.global_position)
		if d <= best_distance:
			best_distance = d
			best = customer
	return best


func _tray_types() -> Array:
	var types := []
	for glass in _tray:
		types.append(glass["type"])
	return types


# ------------------------------------------------------------------------------
# Carry visuals: a tray of glasses + the active glass being poured
# ------------------------------------------------------------------------------
func _build_carry_visuals() -> void:
	# A flat tray board.
	var tray := MeshInstance3D.new()
	var board := BoxMesh.new()
	board.size = Vector3(0.75, 0.04, 0.3)
	tray.mesh = board
	tray.material_override = _solid(Color(0.25, 0.2, 0.15))
	$Hold.add_child(tray)

	# One small glass per tray slot (hidden until that slot is filled).
	for i in TRAY_CAP:
		var glass := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.06
		cyl.height = 0.2
		glass.mesh = cyl
		var slot_x := (float(i) - float(TRAY_CAP - 1) / 2.0) * 0.17
		glass.position = Vector3(slot_x, 0.12, 0)
		var mat := _solid(Color.WHITE)
		glass.material_override = mat
		glass.visible = false
		$Hold.add_child(glass)
		_tray_glasses.append(glass)
		_tray_materials.append(mat)

	# The active glass we're pouring, held a bit forward of the tray.
	_active_root = Node3D.new()
	_active_root.position = Vector3(0, 0.0, 0.32)
	$Hold.add_child(_active_root)

	var mug := MeshInstance3D.new()
	var mug_mesh := CylinderMesh.new()
	mug_mesh.top_radius = 0.12
	mug_mesh.bottom_radius = 0.1
	mug_mesh.height = GLASS_H
	mug.mesh = mug_mesh
	mug.position = Vector3(0, GLASS_BOTTOM + GLASS_H / 2.0, 0)
	var mug_mat := _solid(Color(0.85, 0.9, 1.0, 0.25))
	mug_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mug.material_override = mug_mat
	_active_root.add_child(mug)

	_active_liquid = MeshInstance3D.new()
	_active_liquid.mesh = _unit_cylinder(0.09)
	_active_liquid_mat = _solid(Color.WHITE)
	_active_liquid.material_override = _active_liquid_mat
	_active_root.add_child(_active_liquid)

	_active_foam = MeshInstance3D.new()
	_active_foam.mesh = _unit_cylinder(0.09)
	_active_foam.material_override = _solid(Globals.FOAM_COLOR)
	_active_root.add_child(_active_foam)


func _update_active_visual() -> void:
	# Tray glasses reflect what's stocked.
	for i in TRAY_CAP:
		if i < _tray.size():
			_tray_glasses[i].visible = true
			_tray_materials[i].albedo_color = Globals.color_for(_tray[i]["type"])
		else:
			_tray_glasses[i].visible = false

	# Active glass fills up as we pour.
	_active_root.visible = _beer_type != -1
	if _beer_type == -1:
		return
	var liquid_h := GLASS_H * _liquid
	var foam_h := GLASS_H * _foam
	_active_liquid.visible = liquid_h > 0.001
	_active_liquid.scale.y = maxf(liquid_h, 0.001)
	_active_liquid.position.y = GLASS_BOTTOM + liquid_h / 2.0
	_active_liquid_mat.albedo_color = Color(0.6, 0.5, 0.3) if _ruined else Globals.color_for(_beer_type)
	_active_foam.visible = foam_h > 0.001
	_active_foam.scale.y = maxf(foam_h, 0.001)
	_active_foam.position.y = GLASS_BOTTOM + liquid_h + foam_h / 2.0


func _solid(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


func _unit_cylinder(radius: float) -> CylinderMesh:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 1.0
	return cyl


# ------------------------------------------------------------------------------
# On-screen hint
# ------------------------------------------------------------------------------
func _update_hint(tap: Dictionary, near_tap: bool, at_register: bool, gm: Node) -> void:
	var hint := ""
	var tray_count := _tray.size()

	if at_register and gm != null and gm.register_active():
		match gm.register_method():
			Globals.PayMethod.CASH:
				hint = "Cash: click the $ buttons to make change, then Space to give it"
			Globals.PayMethod.CARD:
				hint = "Card: type the total on the keypad, then hold Space to swipe"
			Globals.PayMethod.LINE:
				hint = "LINE Pay: press Space to scan their QR code"
		if hint != _last_hint:
			_last_hint = hint
			var ui0 := get_tree().get_first_node_in_group("ui")
			if ui0 != null and ui0.has_method("set_hint"):
				ui0.set_hint(hint)
		return

	var customer := _nearest_waiting_customer()

	if customer != null and _find_tray_glass(customer.get_order()) != -1:
		# Something we can hand over is right here -- serving takes priority.
		hint = "Press Space to serve their %s" % Globals.name_for(customer.get_order())
	elif _beer_type != -1:
		# We're filling a glass.
		if _ruined:
			hint = "Spilled! Ease off the pour -- or press Q to toss it"
		else:
			hint = "Hold Space -- the beer trays up when it reaches the green"
	elif near_tap:
		if tray_count >= TRAY_CAP:
			hint = "Tray full (%d) -- go serve some beers" % tray_count
		else:
			hint = "Hold Space to pour a %s" % Globals.name_for(tap["type"])
	elif customer != null:
		hint = "They want a %s -- none on your tray (Q to dump a wrong one)" % Globals.name_for(customer.get_order())
	elif tray_count == 0:
		hint = "Go to a tap and hold Space to pour beers"
	else:
		hint = "Carrying %d beer(s) -- serve them (Q dumps a wrong beer)" % tray_count

	if hint != _last_hint:
		_last_hint = hint
		var ui := get_tree().get_first_node_in_group("ui")
		if ui != null and ui.has_method("set_hint"):
			ui.set_hint(hint)


func _quality_word() -> String:
	if _liquid >= PERFECT:
		return "perfect"
	if _liquid >= GOOD:
		return "good"
	if _liquid >= MIN_SERVE:
		return "a bit low"
	return "nearly empty"
