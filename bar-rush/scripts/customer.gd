# customer.gd
#
# ONE person. Customers always belong to a Party (see party.gd) -- a single, a
# duo, or a group -- but each person orders and is served individually.
#
# Lifecycle (driven partly by the Party, partly by itself):
#   WALKING  - walking from the door to their assigned seat
#   ORDERING - sitting with an order bubble + draining patience bar
#   DRINKING - just got their beer; happily drinking before ordering again
#   IDLE     - gave up on an order (annoyed); no longer ordering this visit
#   LEAVING  - walking back to the door to exit
#
# The customer reports what happens via signals (`served`, `order_timed_out`);
# the Party forwards those to the GameManager, which owns the score. The customer
# never touches reputation/money itself.
extends Node3D

enum State { WALKING, ORDERING, DRINKING, IDLE, LEAVING }

@export var move_speed: float = 2.5
@export var patience_time: float = 50.0           # seconds to fill one order
@export var drink_time_min: float = 8.0           # happy drinking before reorder
@export var drink_time_max: float = 16.0

signal served(correct: bool, quality: float)
signal order_timed_out()

# Starts IDLE: a freshly spawned member just stands at the door until its Party
# either seats it (walk_to_seat) or sends it home (leave).
# Running bill for this one person: money owed and how many beers they drank.
# Collected later at the register (serving no longer pays instantly).
var tab: int = 0
var beers: int = 0

var _state: int = State.IDLE
var _order: int = 0                 # which beer they currently want
var _patience_left: float = 0.0
var _drink_left: float = 0.0
var _target: Vector3
var _order_on_arrival: bool = true   # false when walking to the pay line

var _body: MeshInstance3D
var _body_material: StandardMaterial3D
var _bubble: Node3D                 # the floating beer-mug "I want this" icon
var _mug_fill: MeshInstance3D       # colored part of the mug icon
var _bar_holder: Node3D             # patience bar wrapper (shown while ordering)
var _patience_fill: MeshInstance3D


func _ready() -> void:
	add_to_group("customers")
	_body = $Body
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color(0.85, 0.75, 0.55)  # neutral "person" tan
	_body.material_override = _body_material
	_build_visuals()


func _process(delta: float) -> void:
	match _state:
		State.WALKING:
			_move_toward(_target, delta)
			if _reached(_target):
				if _order_on_arrival:
					_begin_order()
				else:
					_state = State.IDLE      # arrived at the pay line; just wait
		State.ORDERING:
			_patience_left -= delta
			_update_patience_bar()
			if _patience_left <= 0.0:
				_give_up()
		State.DRINKING:
			_drink_left -= delta
			if _drink_left <= 0.0:
				_begin_order()  # order another round
		State.LEAVING:
			_move_toward(_target, delta)
			if _reached(_target):
				queue_free()
		State.IDLE:
			pass


# ------------------------------------------------------------------------------
# Called by the Party
# ------------------------------------------------------------------------------
func walk_to_seat(seat_position: Vector3) -> void:
	_target = seat_position
	_state = State.WALKING
	_order_on_arrival = true


# Walk somewhere and just wait there (used for the pay line) -- no ordering.
func walk_to(target_position: Vector3) -> void:
	_target = target_position
	_state = State.WALKING
	_order_on_arrival = false
	_hide_order_ui()


func leave(exit_position: Vector3, angry: bool = false) -> void:
	_target = exit_position
	_state = State.LEAVING
	_hide_order_ui()
	if angry:
		_flash(Color(0.85, 0.2, 0.2))


# ------------------------------------------------------------------------------
# Serving (called by the player)
# ------------------------------------------------------------------------------
func is_waiting() -> bool:
	return _state == State.ORDERING


func get_order() -> int:
	return _order


# Deliver a beer. Returns true if it was the right one. Reports via `served`.
func serve(beer_type: int, quality: float) -> bool:
	if _state != State.ORDERING:
		return false
	var correct := (beer_type == _order)
	served.emit(correct, quality)
	if correct:
		# Add this beer to their running tab (paid later at the register).
		tab += Globals.price_for(quality)
		beers += 1
		_hide_order_ui()
		_flash(Color(0.3, 0.85, 0.4))          # happy green
		_state = State.DRINKING
		_drink_left = randf_range(drink_time_min, drink_time_max)
	# A wrong beer: they stay put and keep waiting for the right one.
	return correct


# ------------------------------------------------------------------------------
# Internal
# ------------------------------------------------------------------------------
func _begin_order() -> void:
	_order = randi() % Globals.DRINK_COUNT
	_patience_left = patience_time
	_state = State.ORDERING
	_flash(Color(0.85, 0.75, 0.55))            # back to neutral
	var mug_mat := _mug_fill.material_override as StandardMaterial3D
	mug_mat.albedo_color = Globals.color_for(_order)
	_bubble.visible = true
	_bar_holder.visible = true
	_update_patience_bar()


func _give_up() -> void:
	# Set our state BEFORE emitting: the Party reacts to this signal synchronously
	# (it makes the whole party leave), and we must not overwrite its state change.
	_flash(Color(0.85, 0.2, 0.2))              # annoyed red
	_hide_order_ui()
	_state = State.IDLE
	order_timed_out.emit()


func _hide_order_ui() -> void:
	_bubble.visible = false
	_bar_holder.visible = false


func _flash(color: Color) -> void:
	_body_material.albedo_color = color


func _move_toward(target: Vector3, delta: float) -> void:
	var flat := Vector3(target.x, global_position.y, target.z)
	global_position = global_position.move_toward(flat, move_speed * delta)


func _reached(target: Vector3) -> bool:
	var here := Vector2(global_position.x, global_position.z)
	return here.distance_to(Vector2(target.x, target.z)) < 0.15


# ------------------------------------------------------------------------------
# Floating order bubble (a little beer mug) + patience bar, built in code.
# ------------------------------------------------------------------------------
func _build_visuals() -> void:
	# A mug: a colored cylinder (the beer) with a white cap (the foam) on top.
	_bubble = Node3D.new()
	_bubble.position = Vector3(0, 2.45, 0)
	_bubble.visible = false
	add_child(_bubble)

	_mug_fill = MeshInstance3D.new()
	var mug_mesh := CylinderMesh.new()
	mug_mesh.top_radius = 0.2
	mug_mesh.bottom_radius = 0.2
	mug_mesh.height = 0.32
	_mug_fill.mesh = mug_mesh
	_mug_fill.material_override = _unshaded(Color.WHITE)
	_bubble.add_child(_mug_fill)

	var mug_foam := MeshInstance3D.new()
	var foam_mesh := CylinderMesh.new()
	foam_mesh.top_radius = 0.21
	foam_mesh.bottom_radius = 0.21
	foam_mesh.height = 0.1
	mug_foam.mesh = foam_mesh
	mug_foam.position = Vector3(0, 0.2, 0)
	mug_foam.material_override = _unshaded(Globals.FOAM_COLOR)
	_bubble.add_child(mug_foam)

	# Patience bar: dark background + colored fill that SHRINKS as time runs out.
	_bar_holder = Node3D.new()
	_bar_holder.position = Vector3(0, 2.05, 0)
	_bar_holder.visible = false
	add_child(_bar_holder)

	var bg := MeshInstance3D.new()
	var bg_quad := QuadMesh.new()
	bg_quad.size = Vector2(1.1, 0.18)
	bg.mesh = bg_quad
	bg.material_override = _bar_material(Color(0.1, 0.1, 0.1))
	_bar_holder.add_child(bg)

	_patience_fill = MeshInstance3D.new()
	var fill_quad := QuadMesh.new()
	fill_quad.size = Vector2(1.0, 0.12)
	_patience_fill.mesh = fill_quad
	_patience_fill.position = Vector3(0, 0, 0.01)
	_patience_fill.material_override = _bar_material(Color(0.25, 0.85, 0.35))
	_bar_holder.add_child(_patience_fill)


func _unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _bar_material(color: Color) -> StandardMaterial3D:
	var mat := _unshaded(color)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# THE FIX: without this, billboard mode resets the node's scale every frame,
	# so scaling the fill bar (below) would do nothing. keep_scale lets our
	# scale.x survive, so the bar actually shrinks.
	mat.billboard_keep_scale = true
	return mat


func _update_patience_bar() -> void:
	var fraction := clampf(_patience_left / patience_time, 0.0, 1.0)
	_patience_fill.scale.x = fraction
	var mat := _patience_fill.material_override as StandardMaterial3D
	mat.albedo_color = Color(0.25, 0.85, 0.35).lerp(Color(0.9, 0.2, 0.2), 1.0 - fraction)
