# party.gd
#
# A group of customers that arrives together: a SINGLE (1), a DUO (2), or a
# GROUP (4-5). The party is what the player SEATS; once seated its members order
# beers and run up a tab. When the visit ends the party gets up, frees its table,
# and walks to the CASH REGISTER to pay -- that's where the player collects the
# money (serving no longer pays).
#
# Still just a coordinator: it relays member events and reports pay events to the
# GameManager, which owns the score. No money logic here.
extends Node3D

const CUSTOMER_SCENE := preload("res://scenes/Customer.tscn")

enum State { QUEUING, SEATED, PAYING, LEAVING }

@export var door_patience: float = 55.0        # seconds to be seated before leaving
@export var visit_time_min: float = 75.0       # how long a seated party stays
@export var visit_time_max: float = 95.0
@export var pay_patience: float = 30.0         # seconds to be rung up before dashing

# Relayed to the GameManager (it connects with the party bound, like the rest):
signal order_served(correct: bool, quality: float)
signal order_expired()
signal left_unseated()
signal wants_to_pay()                           # we've reached the pay line
signal dashed(lost: int)                        # left without paying (lost tab)

var kind: int = Globals.PartyKind.SINGLE
var size: int = 1
var pay_method: int = Globals.PayMethod.CASH
var wants_split: bool = false

var _state: int = State.QUEUING
var _patience_left: float = 0.0
var _visit_left: float = 0.0
var _pay_left: float = 0.0
var _exit_position: Vector3
var _pay_slot: Vector3

var _members: Array[Node3D] = []
var _table: Node = null
var _seat_indices: Array[int] = []

var _bar_holder: Node3D                         # floating patience bar (door + pay)
var _bar_fill: MeshInstance3D


func setup(party_kind: int, door_position: Vector3, exit_position: Vector3) -> void:
	kind = party_kind
	size = _size_for_kind(party_kind)
	pay_method = randi() % 3
	wants_split = size > 1 and randf() < _split_chance()
	_exit_position = exit_position
	global_position = door_position
	_patience_left = door_patience

	_spawn_members()
	_build_bar()
	_state = State.QUEUING


func is_queuing() -> bool:
	return _state == State.QUEUING


func is_paying() -> bool:
	return _state == State.PAYING


func seat_at(table: Node) -> void:
	_table = table
	_seat_indices = table.claim_seats(size)
	for i in _members.size():
		var seat_pos: Vector3 = table.get_seat_global_position(_seat_indices[i])
		_members[i].walk_to_seat(seat_pos)
	_bar_holder.visible = false
	_visit_left = randf_range(visit_time_min, visit_time_max)
	_state = State.SEATED


func _process(delta: float) -> void:
	match _state:
		State.QUEUING:
			_patience_left -= delta
			_update_bar(_patience_left / door_patience, Color(0.3, 0.6, 0.95))
			if _patience_left <= 0.0:
				left_unseated.emit()
				_leave(true)
		State.SEATED:
			_visit_left -= delta
			if _visit_left <= 0.0:
				_begin_paying()
		State.PAYING:
			_pay_left -= delta
			_update_bar(_pay_left / pay_patience, Color(0.95, 0.8, 0.2))
			if _pay_left <= 0.0:
				dashed.emit(total_tab())
				_leave(true)
		State.LEAVING:
			pass


# ------------------------------------------------------------------------------
# Paying
# ------------------------------------------------------------------------------
func _begin_paying() -> void:
	_state = State.PAYING
	_pay_left = pay_patience
	_release_seats()                 # they've vacated the table
	_bar_holder.visible = true
	wants_to_pay.emit()              # GameManager enqueues us + sets our pay slot


# Called by the GameManager to place us in the register line (and re-called if the
# line shifts forward). Members walk to a little cluster at the slot.
func set_pay_slot(slot_position: Vector3) -> void:
	_pay_slot = slot_position
	for i in _members.size():
		var offset_x := (float(i) - float(_members.size() - 1) / 2.0) * 0.6
		_members[i].walk_to(slot_position + Vector3(offset_x, 0, 0))
	_bar_holder.global_position = slot_position + Vector3(0, 2.6, 0)


# Called by the GameManager once we've been fully rung up.
func finish_paid() -> void:
	_leave(false)


# What the register needs: one charge for the whole party, or one per member if
# they're splitting. Each charge is {"tab": int, "beers": int}.
func get_charges() -> Array:
	var charges := []
	if wants_split:
		for m in _members:
			if is_instance_valid(m):
				charges.append({"tab": m.tab, "beers": m.beers})
	else:
		charges.append({"tab": total_tab(), "beers": total_beers()})
	return charges


func total_tab() -> int:
	var t := 0
	for m in _members:
		if is_instance_valid(m):
			t += m.tab
	return t


func total_beers() -> int:
	var b := 0
	for m in _members:
		if is_instance_valid(m):
			b += m.beers
	return b


func pay_fraction() -> float:
	return clampf(_pay_left / pay_patience, 0.0, 1.0)


# ------------------------------------------------------------------------------
# Members
# ------------------------------------------------------------------------------
func _spawn_members() -> void:
	for i in size:
		var member := CUSTOMER_SCENE.instantiate() as Node3D
		add_child(member)
		var offset_x := (float(i) - float(size - 1) / 2.0) * 0.8
		member.position = Vector3(offset_x, 0, 0.6)
		member.served.connect(_on_member_served)
		member.order_timed_out.connect(_on_member_timed_out)
		_members.append(member)


func _on_member_served(correct: bool, quality: float) -> void:
	order_served.emit(correct, quality)


func _on_member_timed_out() -> void:
	order_expired.emit()
	if _state != State.LEAVING:
		_leave(true)                 # ignored too long -> whole party walks out


# ------------------------------------------------------------------------------
# Leaving
# ------------------------------------------------------------------------------
func _leave(angry: bool) -> void:
	_state = State.LEAVING
	_bar_holder.visible = false
	_release_seats()
	for member in _members:
		if is_instance_valid(member):
			member.leave(_exit_position, angry)
	get_tree().create_timer(10.0).timeout.connect(queue_free)


func _release_seats() -> void:
	if _table != null:
		for idx in _seat_indices:
			_table.release_seat(idx)
		_table = null
		_seat_indices = []


# ------------------------------------------------------------------------------
# Floating patience bar (used for both the door wait and the pay wait)
# ------------------------------------------------------------------------------
func _build_bar() -> void:
	_bar_holder = Node3D.new()
	_bar_holder.position = Vector3(0, 2.6, 0.6)
	add_child(_bar_holder)

	var bg := MeshInstance3D.new()
	var bg_quad := QuadMesh.new()
	bg_quad.size = Vector2(1.3, 0.2)
	bg.mesh = bg_quad
	bg.material_override = _bar_material(Color(0.1, 0.1, 0.1))
	_bar_holder.add_child(bg)

	_bar_fill = MeshInstance3D.new()
	var fill_quad := QuadMesh.new()
	fill_quad.size = Vector2(1.2, 0.13)
	_bar_fill.mesh = fill_quad
	_bar_fill.position = Vector3(0, 0, 0.01)
	_bar_fill.material_override = _bar_material(Color(0.3, 0.6, 0.95))
	_bar_holder.add_child(_bar_fill)


func _bar_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	return mat


func _update_bar(fraction: float, full_color: Color) -> void:
	fraction = clampf(fraction, 0.0, 1.0)
	_bar_fill.scale.x = fraction
	var mat := _bar_fill.material_override as StandardMaterial3D
	mat.albedo_color = full_color.lerp(Color(0.9, 0.2, 0.2), 1.0 - fraction)


func _size_for_kind(party_kind: int) -> int:
	match party_kind:
		Globals.PartyKind.SINGLE: return 1
		Globals.PartyKind.DUO: return 2
		_: return randi_range(4, 5)


func _split_chance() -> float:
	match kind:
		Globals.PartyKind.DUO: return 0.3
		Globals.PartyKind.GROUP: return 0.6
		_: return 0.0
