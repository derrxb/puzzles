# party.gd
#
# A group of customers that arrives together: a SINGLE (1), a DUO (2), or a
# GROUP (4-5). The party is the thing the player SEATS (via the seating panel);
# once seated, its members order beers individually and keep re-ordering until
# the party's visit is over.
#
# The party is a coordinator. It:
#   - spawns its member Customers and lines them up at the door while QUEUING
#   - walks them to their seats when the player seats the party
#   - forwards each member's events up to the GameManager (which owns the score)
#   - sends everyone home (freeing the table) when its visit ends or it waited
#     too long to be seated
#
# It owns NO score logic -- it only relays signals. That keeps the GameManager
# the single source of truth (and makes server-authoritative multiplayer easy
# later).
extends Node3D

const CUSTOMER_SCENE := preload("res://scenes/Customer.tscn")

enum State { QUEUING, SEATED, LEAVING }

@export var door_patience: float = 45.0        # seconds to be seated before leaving
@export var visit_time_min: float = 75.0       # how long a seated party stays
@export var visit_time_max: float = 95.0

# Relayed up to the GameManager:
signal order_served(correct: bool, quality: float)  # a member got a beer
signal order_expired()                              # a member's patience ran out
signal left_unseated()                              # we gave up waiting at the door

var kind: int = Globals.PartyKind.SINGLE
var size: int = 1

var _state: int = State.QUEUING
var _patience_left: float = 0.0
var _visit_left: float = 0.0
var _exit_position: Vector3

var _members: Array[Node3D] = []
var _table: Node = null            # the table we're seated at (to free seats later)
var _seat_indices: Array[int] = []

var _queue_bar_holder: Node3D      # "seat us soon!" bar shown while at the door
var _queue_bar_fill: MeshInstance3D


func setup(party_kind: int, door_position: Vector3, exit_position: Vector3) -> void:
	kind = party_kind
	size = _size_for_kind(party_kind)
	_exit_position = exit_position
	global_position = door_position
	_patience_left = door_patience

	_spawn_members()
	_build_queue_bar()
	_state = State.QUEUING


func is_queuing() -> bool:
	return _state == State.QUEUING


# Called by the GameManager when the player picks a table for us.
func seat_at(table: Node) -> void:
	_table = table
	_seat_indices = table.claim_seats(size)
	for i in _members.size():
		var seat_pos: Vector3 = table.get_seat_global_position(_seat_indices[i])
		_members[i].walk_to_seat(seat_pos)
	_queue_bar_holder.visible = false
	_visit_left = randf_range(visit_time_min, visit_time_max)
	_state = State.SEATED


func _process(delta: float) -> void:
	match _state:
		State.QUEUING:
			_patience_left -= delta
			_update_queue_bar()
			if _patience_left <= 0.0:
				left_unseated.emit()
				_go_home(true)  # leave in a huff
		State.SEATED:
			_visit_left -= delta
			if _visit_left <= 0.0:
				_go_home()
		State.LEAVING:
			pass


# ------------------------------------------------------------------------------
# Members
# ------------------------------------------------------------------------------
func _spawn_members() -> void:
	for i in size:
		var member := CUSTOMER_SCENE.instantiate() as Node3D
		add_child(member)
		# Line them up just inside the door while they wait to be seated.
		var offset_x := (float(i) - float(size - 1) / 2.0) * 0.8
		member.position = Vector3(offset_x, 0, 0.6)
		member.served.connect(_on_member_served)
		member.order_timed_out.connect(_on_member_timed_out)
		_members.append(member)


func _on_member_served(correct: bool, quality: float) -> void:
	order_served.emit(correct, quality)


func _on_member_timed_out() -> void:
	order_expired.emit()
	# A customer who was ignored too long gets the whole party to walk out angry.
	if _state != State.LEAVING:
		_go_home(true)


# ------------------------------------------------------------------------------
# Leaving
# ------------------------------------------------------------------------------
func _go_home(angry: bool = false) -> void:
	_state = State.LEAVING
	_queue_bar_holder.visible = false
	# Free the table seats we were using so new parties can be seated there.
	if _table != null:
		for idx in _seat_indices:
			_table.release_seat(idx)
		_table = null
	for member in _members:
		member.leave(_exit_position, angry)
	# Give everyone time to walk out, then remove the (now empty) party node.
	get_tree().create_timer(10.0).timeout.connect(queue_free)


# ------------------------------------------------------------------------------
# Queue patience bar (floats above the party while waiting at the door)
# ------------------------------------------------------------------------------
func _build_queue_bar() -> void:
	_queue_bar_holder = Node3D.new()
	_queue_bar_holder.position = Vector3(0, 2.6, 0.6)
	add_child(_queue_bar_holder)

	var bg := MeshInstance3D.new()
	var bg_quad := QuadMesh.new()
	bg_quad.size = Vector2(1.3, 0.2)
	bg.mesh = bg_quad
	bg.material_override = _bar_material(Color(0.1, 0.1, 0.1))
	_queue_bar_holder.add_child(bg)

	_queue_bar_fill = MeshInstance3D.new()
	var fill_quad := QuadMesh.new()
	fill_quad.size = Vector2(1.2, 0.13)
	_queue_bar_fill.mesh = fill_quad
	_queue_bar_fill.position = Vector3(0, 0, 0.01)
	_queue_bar_fill.material_override = _bar_material(Color(0.3, 0.6, 0.95))
	_queue_bar_holder.add_child(_queue_bar_fill)


func _bar_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true  # so scaling the fill actually shrinks it
	return mat


func _update_queue_bar() -> void:
	var fraction := clampf(_patience_left / door_patience, 0.0, 1.0)
	_queue_bar_fill.scale.x = fraction
	var mat := _queue_bar_fill.material_override as StandardMaterial3D
	mat.albedo_color = Color(0.3, 0.6, 0.95).lerp(Color(0.9, 0.3, 0.2), 1.0 - fraction)


func _size_for_kind(party_kind: int) -> int:
	match party_kind:
		Globals.PartyKind.SINGLE: return 1
		Globals.PartyKind.DUO: return 2
		_: return randi_range(4, 5)  # GROUP
