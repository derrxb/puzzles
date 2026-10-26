# player.gd
#
# The player character: a capsule you drive with WASD / arrow keys. Movement is
# CAMERA-RELATIVE (pressing "up" moves away from the camera, not along a fixed
# world axis), which feels natural for an Overcooked-style angled view.
#
# The player's job in the gameplay loop:
#   1. Stand near the bar counter and press 1 / 2 / 3 to pour a Red/Blue/Green
#      drink. The drink appears carried in front of the player.
#   2. Walk the drink to a seated customer and press E to serve it.
#
# The player reports what it's carrying and a context hint through signals, which
# the UI listens to. The player never changes the score directly -- it calls the
# customer's serve() method, and the customer/GameManager handle the score.
extends CharacterBody3D

@export var move_speed: float = 6.0
@export var gravity: float = 20.0
@export var serve_range: float = 2.0   # how close to a customer to serve them

# Signals the UI connects to so it can show what we carry and what to do next.
signal held_drink_changed(drink_index: int)  # -1 means empty-handed
signal hint_changed(text: String)

# Which drink we are carrying (-1 = none), and the mesh that visualizes it.
var _held_drink: int = -1
var _held_material: StandardMaterial3D
var _held_mesh: MeshInstance3D

var _last_hint: String = ""


func _ready() -> void:
	add_to_group("player")

	# The carried-drink mesh lives in Player.tscn at "Hold/HeldDrink". Give it a
	# unique material so recoloring it doesn't affect anything else.
	_held_mesh = $Hold/HeldDrink
	_held_material = StandardMaterial3D.new()
	_held_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_held_mesh.material_override = _held_material
	_held_mesh.visible = false


func _physics_process(delta: float) -> void:
	_handle_movement(delta)


func _process(_delta: float) -> void:
	_handle_actions()
	_update_hint()


# ------------------------------------------------------------------------------
# MOVEMENT (camera-relative)
# ------------------------------------------------------------------------------
func _handle_movement(delta: float) -> void:
	# get_vector returns a Vector2 in the range of a unit circle:
	#   x = right(+) / left(-),  y = down(+) / up(-)
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	var direction := Vector3.ZERO
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		# Flatten the camera's forward and right vectors onto the ground plane so
		# movement stays horizontal regardless of the camera's downward tilt.
		var forward := -camera.global_transform.basis.z
		var right := camera.global_transform.basis.x
		forward.y = 0.0
		right.y = 0.0
		forward = forward.normalized()
		right = right.normalized()
		# "Up" on the keyboard (input.y negative) should push us forward.
		direction = (forward * -input.y + right * input.x)

	# Horizontal velocity from input; vertical velocity from gravity.
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	move_and_slide()

	# Turn the capsule to face the way we're moving (purely cosmetic).
	if direction.length() > 0.1:
		var target_yaw := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 12.0 * delta)


# ------------------------------------------------------------------------------
# ACTIONS: pour drinks at the counter, serve customers
# ------------------------------------------------------------------------------
func _handle_actions() -> void:
	# Pour a drink -- only allowed while standing near the counter.
	if _is_near_counter():
		if Input.is_action_just_pressed("drink_red"):
			_pick_up(Globals.Drink.RED)
		elif Input.is_action_just_pressed("drink_blue"):
			_pick_up(Globals.Drink.BLUE)
		elif Input.is_action_just_pressed("drink_green"):
			_pick_up(Globals.Drink.GREEN)

	# Serve the nearest waiting customer with E.
	if Input.is_action_just_pressed("interact"):
		_try_serve()


func _pick_up(drink_index: int) -> void:
	_held_drink = drink_index
	_held_material.albedo_color = Globals.color_for(drink_index)
	_held_mesh.visible = true
	held_drink_changed.emit(_held_drink)


func _try_serve() -> void:
	if _held_drink == -1:
		return  # nothing to hand over

	var customer := _nearest_waiting_customer()
	if customer == null:
		return  # no one in reach to serve

	customer.serve(_held_drink)
	# The drink is handed over either way (right or wrong), so our hands are empty.
	_held_drink = -1
	_held_mesh.visible = false
	held_drink_changed.emit(_held_drink)


# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
func _is_near_counter() -> bool:
	var counter := get_tree().get_first_node_in_group("counter")
	if counter == null:
		return false
	return counter.is_in_range(global_position)


# Find the closest customer who is seated and waiting, within serve_range.
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


# Work out the helpful on-screen hint and emit it (only when it changes).
func _update_hint() -> void:
	var hint := ""
	if _held_drink == -1:
		if _is_near_counter():
			hint = "Press 1 / 2 / 3 to pour Red / Blue / Green"
		else:
			hint = "Go to the bar counter to pour a drink"
	else:
		var drink_name := Globals.name_for(_held_drink)
		if _nearest_waiting_customer() != null:
			hint = "Press E to serve the %s drink" % drink_name
		else:
			hint = "Carrying %s -- take it to a waiting customer" % drink_name

	if hint != _last_hint:
		_last_hint = hint
		hint_changed.emit(hint)
