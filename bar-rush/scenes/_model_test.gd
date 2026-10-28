# _model_test.gd — DISPOSABLE SPIKE (safe to delete).
# A tiny viewer that loads the downloaded bar FBX so you can look at it.
# Nothing here touches the real game. Run this scene on its own with F6.
#
# CONTROLS:
#   - Left-drag .................. orbit around the model
#   - Scroll / pinch / +,- keys .. zoom in / out
#   - Up / Down arrows ........... zoom in / out (keyboard fallback)
#   - Right-drag or WASD ......... pan (slide the view)
#   - R .......................... reset the view
#   - Esc ........................ quit
extends Node3D

const MODEL_PATH := "res://assets/bar_test/Bar_002.fbx"

# --- orbit camera state ---
var _target: Vector3 = Vector3.ZERO   # the point we orbit around (model center)
var _distance: float = 10.0            # how far the camera sits from the target
var _yaw: float = 0.6                  # left/right angle (radians)
var _pitch: float = 0.5                # up/down angle (radians)
var _home := {}                        # saved starting view, for the reset key

var _model: Node3D = null
@onready var _cam: Camera3D = $Camera3D


func _ready() -> void:
	var packed := load(MODEL_PATH) as PackedScene
	if packed == null:
		push_error("Could not load %s — open the project in the Godot editor once so it imports the FBX, then run again." % MODEL_PATH)
		return

	_model = packed.instantiate()
	add_child(_model)

	# Measure the model so we can center and frame it no matter its scale.
	var bounds := _merged_bounds(_model)
	print("Model bounds size (x, y, z) = ", bounds.size)
	_target = bounds.get_center()
	_distance = maxf(bounds.size.length(), 1.0)      # start pulled back to fit
	_cam.far = _distance * 20.0                       # don't clip the far side away
	_home = {"t": _target, "d": _distance, "y": _yaw, "p": _pitch}
	_update_camera()


# Convert the orbit angles + distance into an actual camera position.
func _update_camera() -> void:
	var offset := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw)
	) * _distance
	_cam.global_position = _target + offset
	_cam.look_at(_target, Vector3.UP)


# Multiply the orbit distance (factor < 1 zooms in, > 1 zooms out), with a floor.
func _zoom(factor: float) -> void:
	_distance = maxf(_distance * factor, 0.05)
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel = zoom (scale distance so it feels even when near or far).
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.1)

	# Trackpad pinch (macOS) = zoom. factor > 1 means fingers spreading (zoom in).
	elif event is InputEventMagnifyGesture:
		_zoom(1.0 / event.factor)

	# Trackpad two-finger scroll (macOS) often arrives as a pan gesture, not a
	# wheel — treat its vertical component as zoom so scrolling just works.
	elif event is InputEventPanGesture:
		_zoom(1.0 + event.delta.y * 0.05)

	# Mouse drag = orbit (left button) or pan (right button).
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_yaw -= event.relative.x * 0.01
			_pitch = clampf(_pitch + event.relative.y * 0.01, -1.4, 1.4)  # avoid flipping over the poles
			_update_camera()
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_pan(event.relative)

	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_target = _home["t"]; _distance = _home["d"]
			_yaw = _home["y"]; _pitch = _home["p"]
			_update_camera()
		elif event.keycode == KEY_ESCAPE:
			get_tree().quit()


func _process(_delta: float) -> void:
	# Keyboard zoom (works regardless of mouse/trackpad quirks).
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD) or Input.is_key_pressed(KEY_UP):
		_zoom(0.97)
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT) or Input.is_key_pressed(KEY_DOWN):
		_zoom(1.03)

	# WASD also pans, for people who prefer the keyboard.
	var move := Vector2.ZERO
	move.x = (1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
	move.y = (1.0 if Input.is_key_pressed(KEY_S) else 0.0) - (1.0 if Input.is_key_pressed(KEY_W) else 0.0)
	if move != Vector2.ZERO:
		_pan(move * 10.0)


# Slide the orbit target across the screen plane (so panning feels natural).
func _pan(delta: Vector2) -> void:
	var right := _cam.global_transform.basis.x
	var up := _cam.global_transform.basis.y
	_target += (-right * delta.x + up * delta.y) * (_distance * 0.002)
	_update_camera()


# Merge every visual piece's box into one, to learn the model's total size.
func _merged_bounds(root: Node3D) -> AABB:
	var total := AABB()
	var first := true
	for node in root.find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		var world_box := vi.global_transform * vi.get_aabb()
		if first:
			total = world_box
			first = false
		else:
			total = total.merge(world_box)
	return total
