# touch_joystick.gd
#
# A floating virtual movement stick for touch screens (phones). Touch anywhere in this
# (bottom-left) region and the stick appears under your thumb; drag to move. It drives the
# existing move_* input actions with analog STRENGTH, so player.gd's camera-relative
# get_vector() movement works completely unchanged -- keyboard and touch share one path.
extends Control

@export var dead_radius := 16.0     # px of slack before movement starts
@export var max_radius := 95.0      # px tilt that maps to full speed

var _touch_index := -1              # the finger we're tracking (-1 = none)
var _center := Vector2.ZERO         # base centre (where the touch began)
var _knob := Vector2.ZERO           # knob centre (follows the drag)
var _home := Vector2.ZERO           # resting spot shown as a hint when idle
var _active := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP   # consume our touches (don't orbit the cam)
	resized.connect(_recenter_home)
	visibility_changed.connect(_release_all)
	tree_exiting.connect(_release_all)
	call_deferred("_recenter_home")


func _recenter_home() -> void:
	_home = Vector2(max_radius + 40.0, size.y - max_radius - 40.0)
	if not _active:
		_center = _home
		_knob = _home
		queue_redraw()


func _draw() -> void:
	var ring_a := 0.30 if _active else 0.16
	draw_circle(_center, max_radius, Color(1, 1, 1, 0.08))
	draw_arc(_center, max_radius, 0.0, TAU, 48, Color(1, 1, 1, ring_a + 0.2), 3.0)
	draw_circle(_knob, max_radius * 0.42, Color(1, 1, 1, 0.45 if _active else 0.28))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_active = true
			_center = event.position
			_knob = event.position
			queue_redraw()
			accept_event()
		elif not event.pressed and event.index == _touch_index:
			_end_touch()
			accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index != _touch_index:
			return
		var off := drag.position - _center
		var dist := off.length()
		var mag := clampf((dist - dead_radius) / (max_radius - dead_radius), 0.0, 1.0)
		var dir := off.normalized() if dist > 0.001 else Vector2.ZERO
		_knob = _center + dir * minf(dist, max_radius)
		_drive(dir, mag)
		queue_redraw()
		accept_event()


func _end_touch() -> void:
	_touch_index = -1
	_active = false
	_release_all()
	_recenter_home()


# Feed the stick into the four move_* actions. get_vector(left,right,up,down) then yields
# (dir.x*mag, dir.y*mag), matching player.gd's camera-relative math (screen-up = forward).
func _drive(dir: Vector2, mag: float) -> void:
	_axis(&"move_right", &"move_left", dir.x * mag)
	_axis(&"move_down", &"move_up", dir.y * mag)


func _axis(pos: StringName, neg: StringName, v: float) -> void:
	if v > 0.0:
		Input.action_release(neg)
		Input.action_press(pos, v)
	elif v < 0.0:
		Input.action_release(pos)
		Input.action_press(neg, -v)
	else:
		Input.action_release(pos)
		Input.action_release(neg)


# Never leave a move action stuck on (lost touch-up, control hidden, scene exit).
func _release_all() -> void:
	for a in [&"move_up", &"move_down", &"move_left", &"move_right"]:
		Input.action_release(a)
