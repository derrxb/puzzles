# table.gd
#
# A seating spot in the bar. The SAME script runs on three kinds of furniture:
#   - a bar STOOL  (1 seat, for singles)
#   - a SMALL table (2 seats, for duos)
#   - a LARGE table (5 seats, for groups)
# What kind it is comes from `table_type`; its seats are child marker nodes named
# "Seat0", "Seat1", ... which this script discovers automatically.
#
# The table only tracks which of its seats are free. The GameManager decides who
# sits where (the player chooses via the seating panel).
extends StaticBody3D

# One of Globals.SeatKind (BAR / SMALL / LARGE). Set by main.gd when placed.
@export var table_type: int = Globals.SeatKind.SMALL

# A human label for the seating panel, e.g. "Bar 1" or "Table 2". Set by main.gd.
var label: String = "Table"

# _occupied[i] == true means seat i currently has a customer.
var _seat_markers: Array[Node3D] = []
var _occupied: Array[bool] = []


func _is_seat_marker(node_name: String) -> bool:
	return node_name.begins_with("Seat") and node_name.substr(4).is_valid_int()


func _ready() -> void:
	add_to_group("tables")
	# Seats are the child markers named exactly "Seat0", "Seat1", ... We check
	# for "Seat" + a number so a decorative mesh called "Seat" is NOT mistaken
	# for a seat.
	for child in get_children():
		if child is Node3D and _is_seat_marker(child.name):
			_seat_markers.append(child)
			_occupied.append(false)


# --- Queries ------------------------------------------------------------------
func seat_count() -> int:
	return _seat_markers.size()


func free_count() -> int:
	var n := 0
	for taken in _occupied:
		if not taken:
			n += 1
	return n


func free_seat_indices() -> Array[int]:
	var result: Array[int] = []
	for i in _occupied.size():
		if not _occupied[i]:
			result.append(i)
	return result


func get_seat_global_position(index: int) -> Vector3:
	return _seat_markers[index].global_position


# Can a party of the given kind use this table, and are there enough seats?
func can_seat(party_kind: int, party_size: int) -> bool:
	if table_type != Globals.required_seat_kind(party_kind):
		return false
	return free_count() >= party_size


# --- Claiming / releasing seats ----------------------------------------------
# Reserve `count` free seats and return their indices (so the party can map each
# member to a seat). Returns fewer than requested only if the table lacks room.
func claim_seats(count: int) -> Array[int]:
	var claimed: Array[int] = []
	for i in _occupied.size():
		if claimed.size() >= count:
			break
		if not _occupied[i]:
			_occupied[i] = true
			claimed.append(i)
	return claimed


func release_seat(index: int) -> void:
	if index >= 0 and index < _occupied.size():
		_occupied[index] = false
