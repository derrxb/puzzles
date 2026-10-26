# game_manager.gd
#
# The GameManager is the "brain" of the game. It owns ALL the live game state:
#   - reputation and money
#   - which seats are free
#   - spawning customers over time
#   - reacting when a customer is served or storms off
#
# Everything that changes the score flows through here. That is deliberate:
# when we add networked multiplayer later, THE SERVER will run this one node and
# be the single source of truth, while clients just display what it reports.
# Because no other script mutates reputation/money directly, that change will be
# localized here instead of scattered across the codebase.
#
# This node lives inside Main.tscn (it is NOT an autoload). Other scripts find it
# with `get_tree().get_first_node_in_group("game_manager")` -- see player.gd.
extends Node

# --- Tunable settings (editable in the Inspector because of @export) ----------
# @export makes a variable show up in the Godot editor's Inspector panel, so you
# can tweak balance without touching code.
@export var starting_reputation: int = 100
@export var starting_money: int = 0
@export var reward_money: int = 10        # money gained for a correct drink
@export var reward_reputation: int = 5    # reputation gained for a correct drink
@export var penalty_wrong: int = 8        # reputation lost for a wrong drink
@export var penalty_angry: int = 15       # reputation lost when a customer gives up
@export var spawn_interval: float = 4.0   # seconds between spawn attempts

# The Customer scene we instance (create copies of) each time someone arrives.
@export var customer_scene: PackedScene

# Where customers appear (the door) and where we parent them in the tree.
# These are wired up in the editor via the Inspector (set from Main.tscn).
@export var spawn_point: Node3D
@export var customer_container: Node3D

# --- Live state ---------------------------------------------------------------
var reputation: int
var money: int

# Signals let other nodes react WITHOUT the GameManager needing to know about them.
# The UI connects to this signal and refreshes its labels whenever we emit it.
signal stats_changed(reputation: int, money: int)

# Internal timer used to pace customer spawns.
var _spawn_timer: Timer


func _ready() -> void:
	# Put ourselves in a group so any script can find us by name.
	add_to_group("game_manager")

	# Resolve our collaborators. They can be wired in the Inspector (the @export
	# fields), but we also fall back to finding the sibling nodes by name so the
	# game works no matter how the scene was saved. GameManager, Door and
	# CustomerContainer all live side by side under Main.
	if spawn_point == null:
		spawn_point = get_node_or_null("../Door")
	if customer_container == null:
		customer_container = get_node_or_null("../CustomerContainer")

	if spawn_point == null or customer_container == null:
		push_error("GameManager needs a 'Door' and 'CustomerContainer' node beside it.")
		return

	reputation = starting_reputation
	money = starting_money

	# Create a Timer in code and start it. Every time it "times out" we try to
	# spawn a customer. (We could also have added a Timer node in the scene; doing
	# it in code keeps the GameManager self-contained and easy to follow.)
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = spawn_interval
	_spawn_timer.autostart = true
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)

	# Tell the UI the starting numbers (emit once so labels aren't blank).
	# call_deferred waits one frame so the UI has finished connecting first.
	stats_changed.emit.call_deferred(reputation, money)


# ------------------------------------------------------------------------------
# SPAWNING
# ------------------------------------------------------------------------------
func _on_spawn_timer_timeout() -> void:
	_try_spawn_customer()


func _try_spawn_customer() -> void:
	# Only spawn if we actually have a free seat AND a customer scene assigned.
	if customer_scene == null:
		push_warning("GameManager has no customer_scene assigned.")
		return

	var seat := _find_free_seat()
	if seat.is_empty():
		return  # Bar is full -- try again on the next timer tick.

	# Instantiate() makes a fresh copy of the Customer scene.
	var customer := customer_scene.instantiate()
	customer_container.add_child(customer)

	# Start the customer at the door, then tell it where to sit. The door also
	# doubles as the exit they walk back to when they leave.
	customer.global_position = spawn_point.global_position
	customer.exit_position = spawn_point.global_position

	# React to what the customer does. We connect to its signals here so that ALL
	# score changes happen inside the GameManager.
	customer.served.connect(_on_customer_served)
	customer.left_angry.connect(_on_customer_left_angry)

	# Hand the customer its assigned seat (table node + seat index).
	var table: Node = seat["table"]
	var seat_index: int = seat["index"]
	table.occupy_seat(seat_index)
	customer.assign_seat(table, seat_index, table.get_seat_global_position(seat_index))


# Look through every table (they are all in the "tables" group) and return the
# first free seat as a small dictionary, or an empty dictionary if none are free.
func _find_free_seat() -> Dictionary:
	for table in get_tree().get_nodes_in_group("tables"):
		var index: int = table.get_free_seat_index()
		if index != -1:
			return {"table": table, "index": index}
	return {}


# ------------------------------------------------------------------------------
# SCORE EVENTS (the only place reputation/money change)
# ------------------------------------------------------------------------------
func _on_customer_served(correct: bool) -> void:
	if correct:
		_add_reputation(reward_reputation)
		_add_money(reward_money)
	else:
		_add_reputation(-penalty_wrong)


func _on_customer_left_angry() -> void:
	_add_reputation(-penalty_angry)


func _add_reputation(amount: int) -> void:
	# clamp() keeps reputation inside 0..100 so the bar never overflows.
	reputation = clampi(reputation + amount, 0, 100)
	stats_changed.emit(reputation, money)


func _add_money(amount: int) -> void:
	money = maxi(money + amount, 0)
	stats_changed.emit(reputation, money)
