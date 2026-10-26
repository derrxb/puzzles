# game_manager.gd
#
# The "brain" and single source of truth. It owns ALL live game state:
#   - reputation and money
#   - the queue of parties waiting at the door
#   - spawning parties over time
#   - the seating API the UI calls when the player clicks a table
#   - every change to the score
#
# Nothing else mutates reputation/money -- parties just relay signals to here.
# That's what will let a server own this one node for multiplayer later.
extends Node

# --- Tunables (editable in the Inspector) -------------------------------------
@export var starting_reputation: int = 50     # starts mid so it can climb slowly
@export var starting_money: int = 0

@export var base_money: int = 8               # money for a perfect beer (scaled by quality)
@export var penalty_wrong: int = 4            # rep lost for the wrong beer
@export var penalty_order_expired: int = 6    # rep lost when a seated order times out
@export var penalty_unseated: int = 8         # rep lost when a party leaves the door

@export var spawn_interval_min: float = 16.0
@export var spawn_interval_max: float = 26.0
# When this many parties are already waiting at the door, nobody new shows up --
# so when you're backed up, arrivals slow down instead of piling on.
@export var max_queue: int = 2
@export var dump_cost: int = 4                # money lost when you throw a beer away

@export var party_scene: PackedScene

# Wired in the Inspector, with a code fallback (see _ready).
@export var spawn_point: Node3D               # the door (arrival + exit)
@export var customer_container: Node3D        # where party nodes are parented

# --- Live state ---------------------------------------------------------------
var reputation: int
var money: int
var _queue: Array = []                         # parties QUEUING at the door (FIFO)

signal stats_changed(reputation: int, money: int)
signal queue_changed()                         # UI refreshes the seating panel

var _spawn_timer: Timer


func _ready() -> void:
	add_to_group("game_manager")

	# Resolve collaborators (Inspector first, then sibling nodes, then by path).
	if spawn_point == null:
		spawn_point = get_node_or_null("../Door")
	if customer_container == null:
		customer_container = get_node_or_null("../CustomerContainer")
	if party_scene == null:
		party_scene = load("res://scenes/Party.tscn")

	if spawn_point == null or customer_container == null or party_scene == null:
		push_error("GameManager is missing Door, CustomerContainer, or Party scene.")
		return

	reputation = starting_reputation
	money = starting_money

	_spawn_timer = Timer.new()
	_spawn_timer.one_shot = true
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)
	_restart_spawn_timer()

	stats_changed.emit.call_deferred(reputation, money)


# ------------------------------------------------------------------------------
# Spawning parties
# ------------------------------------------------------------------------------
func _restart_spawn_timer() -> void:
	_spawn_timer.start(randf_range(spawn_interval_min, spawn_interval_max))


func _on_spawn_timer_timeout() -> void:
	# Don't let a crowd pile up at the door: if we're already backed up, this
	# slot is skipped (the next party simply arrives later).
	if _queue.size() < max_queue:
		_spawn_party()
	_restart_spawn_timer()


func _spawn_party() -> void:
	var party := party_scene.instantiate()
	customer_container.add_child(party)
	party.setup(_random_party_kind(), spawn_point.global_position, spawn_point.global_position)

	# Relay the party's events to our score handlers. We bind the party itself to
	# the "left" handler so we know which one to drop from the queue.
	party.order_served.connect(_on_order_served)
	party.order_expired.connect(_on_order_expired)
	party.left_unseated.connect(_on_left_unseated.bind(party))

	_queue.append(party)
	queue_changed.emit()


# Weighted pick: mostly singles and duos, groups are rarer (they're a handful).
func _random_party_kind() -> int:
	var r := randf()
	if r < 0.45:
		return Globals.PartyKind.SINGLE
	elif r < 0.85:
		return Globals.PartyKind.DUO
	return Globals.PartyKind.GROUP


# ------------------------------------------------------------------------------
# Seating API (called by the UI's seating panel)
# ------------------------------------------------------------------------------
func get_queue() -> Array:
	return _queue


func get_front_party():
	if _queue.is_empty():
		return null
	return _queue[0]


# All tables that could seat the given party right now.
func eligible_tables(party) -> Array:
	var result := []
	for table in get_tree().get_nodes_in_group("tables"):
		if table.can_seat(party.kind, party.size):
			result.append(table)
	return result


# Seat the front party at `table`. Returns false if it can't be seated there.
func seat_front_party(table) -> bool:
	var party = get_front_party()
	if party == null or not table.can_seat(party.kind, party.size):
		return false
	party.seat_at(table)
	_queue.pop_front()
	queue_changed.emit()
	return true


# ------------------------------------------------------------------------------
# Score events (the ONLY place reputation/money change)
# ------------------------------------------------------------------------------
func _on_order_served(correct: bool, quality: float) -> void:
	if correct:
		_add_money(maxi(1, roundi(base_money * quality)))
		if quality >= 0.9:
			_add_reputation(2)
		elif quality >= 0.75:
			_add_reputation(1)
		# a weak-but-correct pour: money only, no reputation
	else:
		_add_reputation(-penalty_wrong)


func _on_order_expired() -> void:
	_add_reputation(-penalty_order_expired)


# Called by the player when they throw a beer away: the drink is wasted, so it
# costs money (but no reputation -- better than serving the wrong beer).
func waste_drink() -> void:
	_add_money(-dump_cost)


func _on_left_unseated(party) -> void:
	_queue.erase(party)
	_add_reputation(-penalty_unseated)
	queue_changed.emit()


func _add_reputation(amount: int) -> void:
	reputation = clampi(reputation + amount, 0, 100)
	stats_changed.emit(reputation, money)


func _add_money(amount: int) -> void:
	money = maxi(money + amount, 0)
	stats_changed.emit(reputation, money)
