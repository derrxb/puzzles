# game_manager.gd
#
# The "brain" and single source of truth. It owns ALL live game state:
#   - reputation and money
#   - the queue of parties waiting at the DOOR (to be seated)
#   - the queue of parties waiting at the REGISTER (to pay)
#   - spawning parties over time
#   - the seating API (player clicks a table) and the register/payment API
#   - every change to the score
#
# Nothing else mutates reputation/money -- serving builds a customer's tab, and
# money only changes here when a party is rung up at the register.
extends Node

# --- Tunables -----------------------------------------------------------------
@export var starting_reputation: int = 50
@export var starting_money: int = 0

@export var penalty_wrong: int = 4            # rep lost for the wrong beer
@export var penalty_order_expired: int = 6    # rep lost when a seated order times out
@export var penalty_unseated: int = 8         # rep lost when a party leaves the door
@export var penalty_dash: int = 10            # rep lost when a party leaves without paying
@export var penalty_short_change: int = 2     # rep lost for short-changing / overcharging
@export var dump_cost: int = 4                # money lost when you throw a beer away

@export var tip_rate: float = 0.15            # tip as a fraction of the bill, scaled by speed
@export var card_swipe_time: float = 1.2      # seconds to hold Space to swipe a card

@export var spawn_interval_min: float = 16.0
@export var spawn_interval_max: float = 26.0
@export var first_spawn_delay: float = 3.0    # the first party arrives quickly
@export var max_queue: int = 2                # door-queue cap: slows arrivals when busy

@export var party_scene: PackedScene
@export var spawn_point: Node3D
@export var customer_container: Node3D

# --- Live state ---------------------------------------------------------------
var reputation: int
var money: int
var _queue: Array = []        # parties QUEUING at the door
var _pay_queue: Array = []    # parties waiting at the register
var _session: Dictionary = {} # the payment being rung up right now (empty = none)

signal stats_changed(reputation: int, money: int)
signal queue_changed()                         # seating panel refresh
signal register_state_changed(info: Dictionary)

var _spawn_timer: Timer
var _register_node: Node = null


func _ready() -> void:
	add_to_group("game_manager")

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
	_spawn_timer.start(first_spawn_delay)      # first party shows up soon

	stats_changed.emit.call_deferred(reputation, money)


# ------------------------------------------------------------------------------
# Spawning
# ------------------------------------------------------------------------------
func _on_spawn_timer_timeout() -> void:
	if _queue.size() < max_queue:              # don't pile up a crowd at the door
		_spawn_party()
	_spawn_timer.start(randf_range(spawn_interval_min, spawn_interval_max))


func _spawn_party() -> void:
	var party := party_scene.instantiate()
	customer_container.add_child(party)
	party.setup(_random_party_kind(), spawn_point.global_position, spawn_point.global_position)

	party.order_served.connect(_on_order_served)
	party.order_expired.connect(_on_order_expired)
	party.left_unseated.connect(_on_left_unseated.bind(party))
	party.wants_to_pay.connect(_on_wants_to_pay.bind(party))
	party.dashed.connect(_on_dashed.bind(party))

	_queue.append(party)
	queue_changed.emit()


func _random_party_kind() -> int:
	var r := randf()
	if r < 0.45:
		return Globals.PartyKind.SINGLE
	elif r < 0.85:
		return Globals.PartyKind.DUO
	return Globals.PartyKind.GROUP


# ------------------------------------------------------------------------------
# Seating API (door queue)
# ------------------------------------------------------------------------------
func get_queue() -> Array:
	return _queue


func get_front_party():
	return _queue[0] if not _queue.is_empty() else null


func eligible_tables(party) -> Array:
	var result := []
	for table in get_tree().get_nodes_in_group("tables"):
		if table.can_seat(party.kind, party.size):
			result.append(table)
	return result


func seat_front_party(table) -> bool:
	var party = get_front_party()
	if party == null or not table.can_seat(party.kind, party.size):
		return false
	party.seat_at(table)
	_queue.pop_front()
	queue_changed.emit()
	return true


# ------------------------------------------------------------------------------
# Score events from seated customers (reputation only -- money comes at the register)
# ------------------------------------------------------------------------------
func _on_order_served(correct: bool, quality: float) -> void:
	if correct:
		if quality >= 0.9:
			_add_reputation(2)
		elif quality >= 0.75:
			_add_reputation(1)
	else:
		_add_reputation(-penalty_wrong)


func _on_order_expired() -> void:
	_add_reputation(-penalty_order_expired)


func _on_left_unseated(party) -> void:
	_queue.erase(party)
	_add_reputation(-penalty_unseated)
	queue_changed.emit()


func waste_drink() -> void:
	_add_money(-dump_cost)


# ------------------------------------------------------------------------------
# Register: pay queue
# ------------------------------------------------------------------------------
func _register():
	if _register_node == null or not is_instance_valid(_register_node):
		_register_node = get_tree().get_first_node_in_group("register")
	return _register_node


func _on_wants_to_pay(party) -> void:
	_pay_queue.append(party)
	_assign_pay_slots()


func _on_dashed(_lost: int, party) -> void:
	_pay_queue.erase(party)
	if not _session.is_empty() and _session.get("party") == party:
		_end_session()
	_add_reputation(-penalty_dash)
	_assign_pay_slots()


func _assign_pay_slots() -> void:
	var reg = _register()
	if reg == null:
		return
	var i := 0
	for party in _pay_queue:
		if is_instance_valid(party):
			party.set_pay_slot(reg.slot_position(i))
			i += 1


func register_party():
	return _pay_queue[0] if not _pay_queue.is_empty() else null


# ------------------------------------------------------------------------------
# Register: the payment session (driven by player input + UI buttons)
# ------------------------------------------------------------------------------
func register_active() -> bool:
	return not _session.is_empty()


func register_method() -> int:
	return _session.get("method", -1)


func register_begin() -> void:
	var party = register_party()
	if party == null or not _session.is_empty():
		return
	_session = {
		"party": party,
		"method": party.pay_method,
		"charges": party.get_charges(),
		"index": 0,
		"collected": 0,
		"clean": true,
	}
	_load_charge()
	_emit_register_state()


func register_end() -> void:
	if _session.is_empty():
		return
	_end_session()


func _end_session() -> void:
	_session = {}
	_emit_register_state()


# --- Cash ---
func register_change_add(amount: int) -> void:
	if register_method() == Globals.PayMethod.CASH:
		_session["change_given"] += amount
		_emit_register_state()


func register_change_reset() -> void:
	if register_method() == Globals.PayMethod.CASH:
		_session["change_given"] = 0
		_emit_register_state()


func register_cash_give() -> void:
	if register_method() != Globals.PayMethod.CASH:
		return
	var tab: int = _session["tab"]
	var tender: int = _session["tender"]
	var given: int = _session["change_given"]
	var due := tender - tab
	var net := maxi(tender - given, 0)        # what stays in the register
	_add_money(net)
	_session["collected"] += net
	if given != due:
		_session["clean"] = false
		if given < due:                        # customer got short-changed
			_add_reputation(-penalty_short_change)
	_advance_charge()


# --- Card (type the total, then swipe) ---
func register_type_digit(digit: int) -> void:
	if register_method() == Globals.PayMethod.CARD:
		_session["typed"] = mini(_session["typed"] * 10 + digit, 9999)
		_emit_register_state()


func register_type_clear() -> void:
	if register_method() == Globals.PayMethod.CARD:
		_session["typed"] = 0
		_emit_register_state()


func register_card_swipe(delta: float) -> void:
	if register_method() != Globals.PayMethod.CARD or _session["typed"] <= 0:
		return
	_session["swipe"] = minf(_session["swipe"] + delta / card_swipe_time, 1.0)
	if _session["swipe"] >= 1.0:
		var amt: int = _session["typed"]
		var tab: int = _session["tab"]
		_add_money(maxi(amt, 0))
		_session["collected"] += amt
		if amt != tab:
			_session["clean"] = false
			if amt > tab:                      # customer overcharged
				_add_reputation(-penalty_short_change)
		_advance_charge()
	else:
		_emit_register_state()


func register_card_release() -> void:
	if register_method() == Globals.PayMethod.CARD and _session.get("swipe", 0.0) < 1.0:
		_session["swipe"] = 0.0
		_emit_register_state()


# --- LINE Pay (scan) ---
func register_line_scan() -> void:
	if register_method() != Globals.PayMethod.LINE:
		return
	var tab: int = _session["tab"]
	_add_money(tab)
	_session["collected"] += tab
	_advance_charge()


# --- Session bookkeeping ---
func _load_charge() -> void:
	var charge: Dictionary = _session["charges"][_session["index"]]
	_session["tab"] = charge["tab"]
	_session["beers"] = charge["beers"]
	_session["tender"] = Globals.tender_for(charge["tab"])
	_session["change_given"] = 0
	_session["typed"] = 0
	_session["swipe"] = 0.0


func _advance_charge() -> void:
	_session["index"] += 1
	if _session["index"] >= _session["charges"].size():
		_finish_party()
	else:
		_load_charge()
		_emit_register_state()


func _finish_party() -> void:
	var party = _session["party"]
	# Tip: a fraction of the bill, bigger the sooner you rang them up, halved if
	# the payment wasn't handled cleanly.
	if is_instance_valid(party):
		var base: int = party.total_tab()
		var tip := int(round(base * tip_rate * party.pay_fraction()))
		if not _session["clean"]:
			tip = tip / 2
		if tip > 0:
			_add_money(tip)
		party.finish_paid()
		_pay_queue.erase(party)
	_end_session()
	_assign_pay_slots()


func _emit_register_state() -> void:
	if _session.is_empty():
		register_state_changed.emit({"active": false})
		return
	var party = _session["party"]
	register_state_changed.emit({
		"active": true,
		"method": _session["method"],
		"party_label": Globals.party_label(party.kind) if is_instance_valid(party) else "",
		"split": party.wants_split if is_instance_valid(party) else false,
		"index": _session["index"],
		"count": _session["charges"].size(),
		"tab": _session["tab"],
		"beers": _session["beers"],
		"tender": _session["tender"],
		"change_due": _session["tender"] - _session["tab"],
		"change_given": _session["change_given"],
		"typed": _session["typed"],
		"swipe": _session["swipe"],
	})


# ------------------------------------------------------------------------------
func _add_reputation(amount: int) -> void:
	reputation = clampi(reputation + amount, 0, 100)
	stats_changed.emit(reputation, money)


func _add_money(amount: int) -> void:
	money = maxi(money + amount, 0)
	stats_changed.emit(reputation, money)
