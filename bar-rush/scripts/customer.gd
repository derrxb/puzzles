# customer.gd
#
# A Customer walks in the door, goes to an assigned seat, orders a random drink,
# and waits -- but only so long. A patience bar above their head ticks down. If
# you serve the right drink in time they pay and leave happy; the wrong drink
# annoys them (and costs you reputation) but they keep waiting; if patience runs
# out they storm off and reputation drops.
#
# The customer reports what happens through two SIGNALS (`served` and
# `left_angry`). It does NOT touch reputation or money itself -- the GameManager
# listens to these signals and is the only thing that changes the score. This
# keeps all game state in one place (important for future multiplayer).
#
# This is a plain Node3D (no physics). It reaches its target by moving in a
# straight line each frame -- simple and perfect for placeholder art. Real
# pathfinding around furniture is a good later upgrade (see the README).
extends Node3D

# The three things a customer can be doing.
enum State { WALKING_TO_SEAT, WAITING, LEAVING }

@export var move_speed: float = 2.5      # meters per second
@export var patience_time: float = 20.0  # seconds before they give up

# Signals the GameManager connects to. `correct` is true if we got the right drink.
signal served(correct: bool)
signal left_angry()

# --- State ---
var _state: int = State.WALKING_TO_SEAT
var _order: int = 0               # which drink (Globals.Drink enum value)
var _patience_left: float = 0.0
var _target: Vector3              # where we are currently walking toward
var _served_happy: bool = false   # true once correctly served (suppresses anger)

# Seat bookkeeping so we can free the seat when we leave.
var _table: Node = null
var _seat_index: int = -1

# Where to walk to when leaving (set by the GameManager -- usually the door).
var exit_position: Vector3 = Vector3.ZERO

# --- Visual pieces we build in code (see _build_visuals) ---
var _body: MeshInstance3D          # the capsule body (lives in the scene)
var _body_material: StandardMaterial3D
var _bubble: MeshInstance3D        # floating sphere showing the ordered color
var _patience_fill: MeshInstance3D # shrinking/colored bar showing patience


func _ready() -> void:
	add_to_group("customers")

	# Grab the body mesh defined in Customer.tscn and give it its own material
	# instance so we can recolor THIS customer without affecting others.
	_body = $Body
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color(0.85, 0.75, 0.55)  # neutral "person" tan
	_body.material_override = _body_material

	# Pick a random order (0, 1, or 2) and build the floating UI above the head.
	_order = randi() % Globals.DRINK_COUNT
	_patience_left = patience_time
	_build_visuals()


func _process(delta: float) -> void:
	match _state:
		State.WALKING_TO_SEAT:
			_move_toward_target(delta)
			if _reached_target():
				_begin_waiting()

		State.WAITING:
			_patience_left -= delta
			_update_patience_bar()
			if _patience_left <= 0.0:
				_give_up()

		State.LEAVING:
			_move_toward_target(delta)
			if _reached_target():
				# We've reached the door -- remove ourselves from the game.
				queue_free()


# ------------------------------------------------------------------------------
# Called by the GameManager right after spawning us.
# ------------------------------------------------------------------------------
func assign_seat(table: Node, seat_index: int, seat_position: Vector3) -> void:
	_table = table
	_seat_index = seat_index
	_target = seat_position
	_state = State.WALKING_TO_SEAT


# What drink did this customer order? Used by the player when delivering.
func get_order() -> int:
	return _order


# Can the player currently hand this customer a drink? (Only while seated/waiting.)
func is_waiting() -> bool:
	return _state == State.WAITING


# The player calls this to deliver a drink of `drink_color`.
# Returns true if it was the correct drink. Either way we report via `served`.
func serve(drink_color: int) -> bool:
	if _state != State.WAITING:
		return false

	var correct := (drink_color == _order)
	served.emit(correct)

	if correct:
		_served_happy = true
		_leave(Color(0.25, 0.85, 0.35))  # turn green and head for the door
	# A wrong drink: we already emitted served(false) so the GameManager docks
	# reputation. The customer stays and keeps waiting for the right one.
	return correct


# ------------------------------------------------------------------------------
# Internal behavior
# ------------------------------------------------------------------------------
func _begin_waiting() -> void:
	_state = State.WAITING
	_bubble.visible = true
	_patience_fill.get_parent().visible = true


func _give_up() -> void:
	if _served_happy:
		return
	left_angry.emit()
	_leave(Color(0.85, 0.2, 0.2))  # turn red and storm out


# Shared "head for the exit and disappear" logic for both happy and angry exits.
func _leave(flash_color: Color) -> void:
	_body_material.albedo_color = flash_color
	_bubble.visible = false
	_patience_fill.get_parent().visible = false
	_free_our_seat()
	_target = exit_position
	_state = State.LEAVING


func _free_our_seat() -> void:
	if _table != null and _seat_index != -1:
		_table.free_seat(_seat_index)
		_table = null
		_seat_index = -1


func _move_toward_target(delta: float) -> void:
	# Move in a straight line toward the target, but keep our Y (height) fixed so
	# we glide along the floor rather than diving toward the target's height.
	var flat_target := Vector3(_target.x, global_position.y, _target.z)
	global_position = global_position.move_toward(flat_target, move_speed * delta)


func _reached_target() -> bool:
	var here := Vector2(global_position.x, global_position.z)
	var there := Vector2(_target.x, _target.z)
	return here.distance_to(there) < 0.15


# ------------------------------------------------------------------------------
# Build the floating order bubble + patience bar in code.
# ------------------------------------------------------------------------------
func _build_visuals() -> void:
	# --- Order bubble: a small sphere colored like the drink they want. ---
	_bubble = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.44
	_bubble.mesh = sphere
	_bubble.position = Vector3(0, 2.3, 0)  # float above the head
	var bubble_mat := StandardMaterial3D.new()
	bubble_mat.albedo_color = Globals.color_for(_order)
	# Unshaded = ignore lighting, so the color reads clearly as an "icon".
	bubble_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bubble.material_override = bubble_mat
	_bubble.visible = false  # hidden until they sit down
	add_child(_bubble)

	# --- Patience bar: a dark background quad with a colored fill quad on top. ---
	# We wrap them in a holder so we can show/hide and billboard them together.
	var bar_holder := Node3D.new()
	bar_holder.position = Vector3(0, 2.0, 0)
	bar_holder.visible = false
	add_child(bar_holder)

	var bg := MeshInstance3D.new()
	var bg_quad := QuadMesh.new()
	bg_quad.size = Vector2(1.1, 0.18)
	bg.mesh = bg_quad
	bg.material_override = _make_bar_material(Color(0.1, 0.1, 0.1))
	bar_holder.add_child(bg)

	_patience_fill = MeshInstance3D.new()
	var fill_quad := QuadMesh.new()
	fill_quad.size = Vector2(1.0, 0.12)
	_patience_fill.mesh = fill_quad
	# Nudge the fill slightly toward the camera so it draws on top of the bg.
	_patience_fill.position = Vector3(0, 0, 0.01)
	_patience_fill.material_override = _make_bar_material(Color(0.25, 0.85, 0.35))
	bar_holder.add_child(_patience_fill)


# A flat, always-faces-camera material for the bar pieces.
func _make_bar_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Billboard mode rotates the quad to always face the camera -- so the bar is
	# readable from our fixed overhead angle.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return mat


func _update_patience_bar() -> void:
	var fraction := clampf(_patience_left / patience_time, 0.0, 1.0)
	# Shrink the fill bar horizontally as patience drains (scales from the center).
	_patience_fill.scale.x = fraction
	# Color goes green (lots of time) -> red (almost out).
	var mat := _patience_fill.material_override as StandardMaterial3D
	mat.albedo_color = Color(0.25, 0.85, 0.35).lerp(Color(0.9, 0.2, 0.2), 1.0 - fraction)
