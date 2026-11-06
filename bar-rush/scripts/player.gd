# player.gd
#
# The bartender you drive with WASD / arrows (camera-relative, Overcooked-style).
#
# The drink loop now uses a TRAY so you can pour a whole round and deliver it:
#   POUR  - walk to a tap and HOLD Space. The tap decides the beer. Liquid rises
#           but FOAM builds; if it overflows it's spilled. Stop pouring and the
#           foam settles, so you pour -> pause -> top off.
#   STOCK - STEP AWAY from the tap and the glass you were filling is set on your
#           tray (up to 4 beers, mixed types). A spilled glass is tossed.
#   SERVE - walk to a seated customer and press E. If your tray has the beer they
#           ordered, it's handed over (reward scaled by how well it was poured).
#
# The player never changes the score -- it calls customer.serve(); the customer
# and GameManager handle the rest.
extends CharacterBody3D

@export var move_speed: float = 6.0
@export var gravity: float = 20.0
@export var serve_range: float = 2.0

# --- Camera / look -----------------------------------------------------------
@export var mouse_sensitivity: float = 0.0025   # radians of turn per pixel moved
@export var third_person_distance: float = 3.5  # SpringArm length in third person
@export var interact_range: float = 3.0          # how far the look-raycast reaches
const PITCH_LIMIT := 1.4                          # ~80 deg up/down

@onready var _head: Node3D = $Head
@onready var _spring: SpringArm3D = $Head/SpringArm3D
@onready var _camera: Camera3D = $Head/SpringArm3D/Camera3D
@onready var _raycast: RayCast3D = $Head/SpringArm3D/Camera3D/RayCast3D
@onready var _body: MeshInstance3D = $Body

var _third_person := false     # start in first person
var _pitch := 0.0              # current head pitch (radians)
# Cached each frame for the register key handler.
var _gm: Node
var _at_register := false
# The customer we're currently looking at (so we can hide the panel on look-away).
var _looked_customer: Node = null

# --- Pour model (modeled on a real keg; see research notes) -------------------
# A full pour takes ~4s. Foam grows from AGITATION, which is worse when the glass
# is upright/full (auto-tilt). Foam always settles, turning partly back to liquid.
# (fill_rate is the single knob for pour speed -- raise it for faster pours.)
@export var fill_rate: float = 0.25     # liquid per second at full flow
@export var foam_conv: float = 0.8      # foam made per unit beer at max agitation (lower = more forgiving)
@export var agit_min: float = 0.10      # agitation when tilted/gentle (low fill)
@export var agit_max: float = 0.85      # agitation when upright/full
@export var foam_settle: float = 0.5    # fraction of foam that collapses per second (higher = settles faster)
@export var return_frac: float = 0.25   # settled foam that becomes liquid

const CAPACITY := 1.0
# A PERFECT pour: beer near the brim with a 1-2 finger head and no spill.
const PERFECT_LIQ_LO := 0.82
const PERFECT_LIQ_HI := 0.90
const PERFECT_FOAM_LO := 0.08
const PERFECT_FOAM_HI := 0.18
const PERFECT_TOTAL_MAX := 0.98
const GOOD_LIQ := 0.6
const MIN_SERVE := 0.2
const MAX_TRAY := 4                     # most slots we ever build; capacity is dynamic

# Pour grades -> a "quality" number the price/tip reads (price_for in globals).
enum Grade { POOR, GOOD, PERFECT }
const GRADE_QUALITY := [0.5, 0.8, 1.0]  # POOR/GOOD/PERFECT -> quality for pricing

const GLASS_H := 0.34
const GLASS_BOTTOM := -0.17
# Beer mug glass model (imported from Beer_Mug_Glass.usdz -> OBJ). MUG_MODEL_H is its
# natural height in model units (base at y=0); GLASS_INNER_R is the beer/foam column
# radius that sits just inside the mug's wall once it's scaled down to GLASS_H.
const MUG_MESH := preload("res://assets/beer_mug/beer_mug.obj")
const MUG_MODEL_H := 15.7113
const GLASS_INNER_R := 0.075
# While pouring, the active glass sits on the counter UNDER the tap (so you watch it
# fill where you're looking), then goes to the hand-tray once stocked. The counter top
# is at world y=1.1, so the glass root sits at 1.1 - GLASS_BOTTOM.
const GLASS_SIT_Y := 1.27

# The bartender character (Mixamo-rigged FBX). It's shown only in third person as the
# player's body. Mesh names survived, so the face gets its real texture; the body uses a
# flat colour because that download's body texture is corrupted.
const BARTENDER := preload("res://assets/bartender_rigged/bartender.fbx")
const BARTENDER_HEAD_TEX := preload("res://assets/bartender/textures/275e4ba0ff024a3ebfbf5e712c45975d_Headbust_Diff.png")
# Carry clips: he always holds a tray, so idle = "Carrying tray" (standing with tray),
# move = "Running with tray". (Plain idle/walk .fbx are still in anims/ if we want them.)
const BARTENDER_IDLE := preload("res://assets/bartender_rigged/anims/carry_walk.fbx")
const BARTENDER_WALK := preload("res://assets/bartender_rigged/anims/carry_run.fbx")
@export var character_scale := 0.28           # a touch smaller -- felt big for the bar
# Feet-on-floor offset: the model's lowest point sits at -2.49*scale, and the visible
# bar floor is at y~0.04, so lift by that much (0.04 + 2.49*scale).
@export var character_foot_offset := 0.74
@export var character_body_color := Color(0.62, 0.55, 0.45)
@export var hold_point := Vector3(0, 1.5, -0.22)   # tray position = character's hands
var _char: Node3D
var _char_anim: AnimationPlayer
var _cur_anim := ""

# The tray's contents: each entry is {"type": int, "quality": float}.
signal tray_changed(types: Array)
# The glass being poured right now (drives the on-screen pour meter).
signal pour_state_changed(active: bool, liquid: float, foam: float, ruined: bool, beer_type: int, perfect: bool)

var _tray: Array = []

# The "active" glass being filled at a tap (-1 = not currently pouring one).
var _beer_type: int = -1
var _liquid: float = 0.0
var _foam: float = 0.0
var _ruined: bool = false
# After a glass finishes (auto-added to the tray, or spilled) we lock pouring
# until Space is released, so holding it down doesn't instantly pour the next.
var _pour_locked: bool = false

# Visuals (built in code at the Hold point).
var _tray_glasses: Array[MeshInstance3D] = []
var _tray_materials: Array[StandardMaterial3D] = []
var _active_root: Node3D
var _active_liquid: MeshInstance3D
var _active_liquid_mat: StandardMaterial3D
var _active_foam: MeshInstance3D
var _pour_stream: MeshInstance3D            # beer falling into the glass while pouring
var _pour_stream_mat: StandardMaterial3D
var _pouring_now := false                   # are we actively pouring THIS frame?
var _active_tap_world := Vector3(0, 1.95, 4.7)  # world pos of the tap we're pouring from
var _hold_base_y := 0.0                     # resting height of the Hold point (for bob)
var _bob_time := 0.0

var _last_hint: String = ""


func _ready() -> void:
	add_to_group("player")
	_build_carry_visuals()
	_build_character()
	tray_changed.emit(_tray_types())

	# Mouse-look: hide + lock the cursor to the window centre so moving the mouse
	# turns the view instead of moving an OS pointer.
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# The look-raycast and the third-person spring arm must ignore the player's own
	# body, or they'd immediately hit it.
	_raycast.add_exception(self)
	_spring.add_excluded_object(self.get_rid())
	_set_view(false)


# ------------------------------------------------------------------------------
# LOOK: mouse turns the view; V toggles first/third person; Esc frees the cursor.
# ------------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Horizontal mouse turns the whole body (so WASD stays relative to view);
		# vertical mouse tilts just the head/camera, clamped so you can't flip over.
		rotate_y(-event.relative.x * mouse_sensitivity)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -PITCH_LIMIT, PITCH_LIMIT)
		_head.rotation.x = _pitch
	elif event.is_action_pressed("toggle_view"):
		_set_view(not _third_person)
	elif event.is_action_pressed("ui_cancel"):
		# Esc toggles the cursor free (to reach the window / stop capturing).
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


# Switch between first person (camera at the eyes, own body hidden) and third
# person (camera on a spring arm behind the bartender that avoids walls).
func _set_view(third: bool) -> void:
	_third_person = third
	_spring.spring_length = third_person_distance if third else 0.0
	# Show the bartender model in third person (fall back to the capsule if it's
	# missing). Never show your own body in first person.
	if _char != null:
		_char.visible = third
		_body.visible = false
	else:
		_body.visible = third


# Build the rigged bartender as the third-person body: scaled to ~1.8m, feet on the
# floor, facing the player's forward (-Z). Face uses its texture; body is flat-colored
# (its source texture is corrupted). Static for now -- animations slot in once added.
func _build_character() -> void:
	_char = BARTENDER.instantiate()
	add_child(_char)
	_char.scale = Vector3.ONE * character_scale
	_char.rotation.y = PI
	_char.position = Vector3(0, character_foot_offset, 0)
	for mi in _collect_meshes(_char):
		var mat := StandardMaterial3D.new()
		if "Headbust" in mi.name:
			mat.albedo_texture = BARTENDER_HEAD_TEX
			mat.roughness = 0.6
		else:
			mat.albedo_color = character_body_color
			mat.roughness = 0.85
		mi.material_override = mat
	_char.visible = false

	# Load the idle + walk clips onto the character's own AnimationPlayer. The walk
	# is NOT "In Place" (hips drift forward ~5 units), so we freeze its hip X/Z -- the
	# game moves the body; the animation should only move the legs.
	_char_anim = _char.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _char_anim != null:
		_add_clip(BARTENDER_IDLE, "idle", false)
		_add_clip(BARTENDER_WALK, "walk", true)
		_char_anim.play("idle")
		_cur_anim = "idle"


# Pull the single clip out of a Mixamo FBX and add it to the character's AnimationPlayer
# under `anim_name`, looping. If `in_place`, freeze the Hips horizontal translation.
func _add_clip(scene: PackedScene, anim_name: String, in_place: bool) -> void:
	var tmp: Node = scene.instantiate()
	var ap := tmp.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null and ap.get_animation_list().size() > 0:
		var src := ap.get_animation(ap.get_animation_list()[0])
		var anim: Animation = src.duplicate(true)
		anim.loop_mode = Animation.LOOP_LINEAR
		if in_place:
			_freeze_hips_xz(anim)
		var lib := _char_anim.get_animation_library("")
		if lib == null:
			lib = AnimationLibrary.new()
			_char_anim.add_animation_library("", lib)
		if lib.has_animation(anim_name):
			lib.remove_animation(anim_name)
		lib.add_animation(anim_name, anim)
	tmp.queue_free()


# Freeze the Hips bone's X/Z translation (keep the vertical bounce) so a forward-moving
# walk clip animates in place.
func _freeze_hips_xz(anim: Animation) -> void:
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		if "Hips" not in str(anim.track_get_path(t)):
			continue
		var n := anim.track_get_key_count(t)
		if n == 0:
			continue
		var first: Vector3 = anim.track_get_key_value(t, 0)
		for k in n:
			var v: Vector3 = anim.track_get_key_value(t, k)
			anim.track_set_key_value(t, k, Vector3(first.x, v.y, first.z))


# Play "walk" while moving, "idle" when still (crossfaded). Runs even in first person
# so the body is in the right state the moment you press V.
func _update_character_anim() -> void:
	if _char_anim == null:
		return
	var want := "walk" if Vector2(velocity.x, velocity.z).length() > 0.3 else "idle"
	if want != _cur_anim:
		_cur_anim = want
		_char_anim.play(want, 0.2)


func _collect_meshes(n: Node) -> Array:
	var r := []
	if n is MeshInstance3D and n.mesh:
		r.append(n)
	for c in n.get_children():
		r += _collect_meshes(c)
	return r


func _physics_process(delta: float) -> void:
	_handle_movement(delta)


func _process(delta: float) -> void:
	var counter := get_tree().get_first_node_in_group("counter")
	var tap := {}
	if counter != null:
		tap = counter.nearest_tap(global_position)
	var near_tap := not tap.is_empty()

	# Releasing Space clears the pour lock, so the next pour needs a fresh press.
	if not Input.is_action_pressed("pour"):
		_pour_locked = false

	var gm := get_tree().get_first_node_in_group("game_manager")
	var register := get_tree().get_first_node_in_group("register")
	var at_register: bool = register != null and gm != null \
		and register.is_in_range(global_position) and gm.register_party() != null
	_gm = gm
	_at_register = at_register

	# Space is the single action key. Priority: ring up at the register > serve a
	# nearby customer > pour at a tap.
	var pouring := false
	if at_register:
		_handle_register(gm, delta)
	else:
		if gm != null and gm.register_active():
			gm.register_end()                    # we walked away from the register
		var customer := _nearest_waiting_customer()
		var can_serve := customer != null and _find_tray_glass(customer.get_order()) != -1
		if can_serve:
			if Input.is_action_just_pressed("pour"):
				_serve_to(customer)
		else:
			pouring = _handle_pour(tap, delta)

	_apply_settle(delta)            # foam always settles (and partly becomes beer)

	# When we're NOT actively pouring and the glass has settled into the perfect
	# window, it auto-adds to the tray (hands-free) and counts as a perfect pour.
	if not pouring and _beer_type != -1 and not _ruined and _is_perfect() and _tray.size() < _capacity():
		_stock_active(Grade.PERFECT)

	_maybe_stock(near_tap)          # stepping away stocks a non-perfect pour

	if Input.is_action_just_pressed("dump"):
		_dump_one()

	_pouring_now = pouring
	if not tap.is_empty():
		_active_tap_world = tap["position"]   # remember which faucet to pour under
	_update_hold_bob(delta)
	_update_character_anim()
	_update_active_visual()
	pour_state_changed.emit(_beer_type != -1, _liquid, _foam, _ruined, _beer_type, _is_perfect())
	_update_hint(tap, near_tap, at_register, gm)
	_handle_look(gm)


# ------------------------------------------------------------------------------
# LOOK-AT INTERACTION: what the centre crosshair is pointing at.
#   - a TABLE, while a party waits and it fits: press E to seat them there.
#   - a CUSTOMER: show their mood panel while you look at them.
# ------------------------------------------------------------------------------
func _handle_look(gm: Node) -> void:
	var ui := get_tree().get_first_node_in_group("ui")
	var hit: Object = _raycast.get_collider() if _raycast.is_colliding() else null
	var node := hit as Node

	# Default: no world prompt, and drop any inspect panel we were showing.
	var prompt := ""
	var looking_customer: Node = null

	if node != null:
		var target := _interact_target(node)
		if target != null and target.is_in_group("tables"):
			var front = gm.get_front_party() if gm != null else null
			if front != null and target.can_seat(front.kind, front.size):
				prompt = "Press E to seat the %s here" % Globals.party_label(front.kind)
				if Input.is_action_just_pressed("interact"):
					gm.seat_front_party(target)
			elif front != null:
				prompt = "%s needs a different table" % target.label
		elif target != null and target.is_in_group("customers"):
			looking_customer = target

	# Show / hide the customer inspect panel based on what we're looking at.
	if looking_customer != _looked_customer:
		_looked_customer = looking_customer
		if ui != null:
			if looking_customer != null and ui.has_method("show_personality"):
				ui.show_personality(looking_customer)
			elif ui.has_method("hide_inspect"):
				ui.hide_inspect()

	if ui != null and ui.has_method("set_interact_prompt"):
		ui.set_interact_prompt(prompt)


# The raycast can hit a table's StaticBody, a customer's Area3D, or a child
# collider -- walk up to the node that carries the "tables"/"customers" group.
func _interact_target(node: Node) -> Node:
	var n := node
	while n != null:
		if n.is_in_group("tables") or n.is_in_group("customers"):
			return n
		n = n.get_parent()
	return null


# ------------------------------------------------------------------------------
# REGISTER amount entry via the keyboard (the cursor is captured, so no clicking).
#   CARD: type the total on number keys (Backspace clears), then hold Space.
#   CASH: press 1 / 5 / 0 to hand over $1 / $5 / $10 (Backspace resets), Space gives.
# The actual pay logic stays in GameManager; this only feeds it amounts.
# ------------------------------------------------------------------------------
func _unhandled_key_input(event: InputEvent) -> void:
	if not _at_register or _gm == null or not _gm.register_active():
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = event.keycode
	var digit := key - KEY_0            # 0..9 for the number-row keys
	match _gm.register_method():
		Globals.PayMethod.CARD:
			if digit >= 0 and digit <= 9:
				_gm.register_type_digit(digit)
			elif key == KEY_BACKSPACE:
				_gm.register_type_clear()
		Globals.PayMethod.CASH:
			match key:
				KEY_1: _gm.register_change_add(1)
				KEY_5: _gm.register_change_add(5)
				KEY_0: _gm.register_change_add(10)
				KEY_BACKSPACE: _gm.register_change_reset()


# At the register, Space rings up the front party -- how depends on their method.
func _handle_register(gm: Node, delta: float) -> void:
	if not gm.register_active():
		gm.register_begin()
	match gm.register_method():
		Globals.PayMethod.CASH:
			if Input.is_action_just_pressed("pour"):
				gm.register_cash_give()
		Globals.PayMethod.CARD:
			if Input.is_action_pressed("pour"):
				gm.register_card_swipe(delta)
			else:
				gm.register_card_release()
		Globals.PayMethod.LINE:
			if Input.is_action_just_pressed("pour"):
				gm.register_line_scan()


# ------------------------------------------------------------------------------
# MOVEMENT (camera-relative)
# ------------------------------------------------------------------------------
func _handle_movement(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	var direction := Vector3.ZERO
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var forward := -camera.global_transform.basis.z
		var right := camera.global_transform.basis.x
		forward.y = 0.0
		right.y = 0.0
		forward = forward.normalized()
		right = right.normalized()
		direction = (forward * -input.y + right * input.x)

	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	move_and_slide()
	# (The player's yaw is driven by mouse-look now, not by movement direction.)


# ------------------------------------------------------------------------------
# POURING / STOCKING THE TRAY
# ------------------------------------------------------------------------------
func _handle_pour(tap: Dictionary, delta: float) -> bool:
	if tap.is_empty() or not Input.is_action_pressed("pour") or _pour_locked:
		return false

	var tap_type: int = tap["type"]

	# Start a fresh glass if we aren't filling one (or the last was spilled/empty).
	if _beer_type == -1 or _ruined or _liquid <= 0.0:
		if _beer_type == -1 and _tray.size() >= _capacity():
			return false                 # tray is full; serve some first
		_begin_active(tap_type)

	if _beer_type != tap_type:
		return false                     # can't mix two beers in one glass

	# Fill rises slowly; foam builds from agitation, which is gentle when the glass
	# is low (tilted) and harsh when it's full (upright) -- the real pouring skill.
	var d_liquid := fill_rate * delta
	_liquid = minf(_liquid + d_liquid, CAPACITY)
	var tilt := clampf(1.0 - _liquid / 0.65, 0.0, 1.0)
	var agitation := agit_min + (agit_max - agit_min) * (1.0 - tilt)
	_foam += foam_conv * agitation * d_liquid

	if _liquid + _foam >= CAPACITY:
		_ruined = true
		_foam = CAPACITY - _liquid
		_pour_locked = true                         # re-press to pour a fresh one
		_report_reset()                             # a spill breaks the combo
	return true


# Foam always collapses over time, and a little of it settles back into beer.
func _apply_settle(delta: float) -> void:
	if _beer_type == -1 or _ruined:
		return
	var s := foam_settle * _foam * delta
	_foam = maxf(0.0, _foam - s)
	_liquid = minf(_liquid + s * return_frac, CAPACITY)


# Stepping away from the taps finalizes the glass you were filling: a decent pour
# goes on the tray, a spilled or near-empty one is tossed. (Most good pours are
# already auto-added at the green while pouring; this covers partial pours.)
func _maybe_stock(near_tap: bool) -> void:
	if _beer_type == -1 or near_tap:
		return
	if not _ruined and _liquid >= MIN_SERVE and _tray.size() < _capacity():
		_stock_active(_grade())
	else:
		# ruined, full, or basically empty: tossed (a spill already broke the combo).
		_clear_active()


# Move the active glass onto the tray and report the pour's grade (combo / XP).
func _stock_active(grade: int) -> void:
	_tray.append({"type": _beer_type, "quality": GRADE_QUALITY[grade]})
	tray_changed.emit(_tray_types())
	_pour_locked = true                 # re-press to pour the next glass
	_report_grade(grade)
	_clear_active()


func _is_perfect() -> bool:
	return _liquid >= PERFECT_LIQ_LO and _liquid <= PERFECT_LIQ_HI \
		and _foam >= PERFECT_FOAM_LO and _foam <= PERFECT_FOAM_HI \
		and _liquid + _foam <= PERFECT_TOTAL_MAX


func _grade() -> int:
	if _is_perfect():
		return Grade.PERFECT
	if _liquid >= GOOD_LIQ:
		return Grade.GOOD
	return Grade.POOR


func _report_grade(grade: int) -> void:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm == null:
		return
	if grade == Grade.PERFECT and gm.has_method("add_perfect"):
		gm.add_perfect()
	elif gm.has_method("reset_combo"):
		gm.reset_combo()


func _report_reset() -> void:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm != null and gm.has_method("reset_combo"):
		gm.reset_combo()


func _begin_active(beer_type: int) -> void:
	_beer_type = beer_type
	_liquid = 0.0
	_foam = 0.0
	_ruined = false


func _clear_active() -> void:
	_beer_type = -1
	_liquid = 0.0
	_foam = 0.0
	_ruined = false


# ------------------------------------------------------------------------------
# SERVING
# ------------------------------------------------------------------------------
func _serve_to(customer: Node3D) -> void:
	var wanted: int = customer.get_order()
	var idx := _find_tray_glass(wanted)
	if idx == -1:
		return                           # no matching beer on the tray
	var glass: Dictionary = _tray[idx]
	_tray.remove_at(idx)
	tray_changed.emit(_tray_types())
	customer.serve(glass["type"], glass["quality"])


# Throw away a beer you don't want (poured the wrong one). It wastes the drink,
# so the GameManager charges a small money penalty. Dumps the glass you're
# pouring first; otherwise the most recently stocked tray glass.
func _dump_one() -> void:
	var wasted := false
	if _beer_type != -1:
		wasted = _liquid >= MIN_SERVE   # only a real beer counts as wasted
		_clear_active()
	elif not _tray.is_empty():
		_tray.pop_back()
		tray_changed.emit(_tray_types())
		wasted = true

	if wasted:
		var gm := get_tree().get_first_node_in_group("game_manager")
		if gm != null and gm.has_method("waste_drink"):
			gm.waste_drink()


func _find_tray_glass(beer_type: int) -> int:
	for i in _tray.size():
		if _tray[i]["type"] == beer_type:
			return i
	return -1


func _nearest_waiting_customer() -> Node3D:
	var best: Node3D = null
	var best_distance := serve_range
	for customer in get_tree().get_nodes_in_group("customers"):
		if not customer.is_waiting():
			continue
		var d := global_position.distance_to(customer.global_position)
		if d <= best_distance:
			best_distance = d
			best = customer
	return best


func _tray_types() -> Array:
	var types := []
	for glass in _tray:
		types.append(glass["type"])
	return types


# How many beers the tray can hold right now (a progression stat on GameManager).
func _capacity() -> int:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm != null and "tray_capacity" in gm:
		return gm.tray_capacity
	return 2


# ------------------------------------------------------------------------------
# Carry visuals: a tray of glasses + the active glass being poured
# ------------------------------------------------------------------------------
func _build_carry_visuals() -> void:
	# Put the carry tray where the bartender's hands are in the carry pose (measured),
	# so in third person the beers sit in his hands.
	$Hold.position = hold_point

	# A flat tray board.
	var tray := MeshInstance3D.new()
	var board := BoxMesh.new()
	board.size = Vector3(0.75, 0.04, 0.3)
	tray.mesh = board
	tray.material_override = _solid(Color(0.25, 0.2, 0.15))
	$Hold.add_child(tray)

	# One beer per tray slot, using the real MUG model (filled beer color), hidden until
	# that slot is stocked. We always build the max; capacity limits how many are used.
	var mug_scale := GLASS_H / MUG_MODEL_H * 0.62      # a bit smaller than the pour mug
	for i in MAX_TRAY:
		var glass := MeshInstance3D.new()
		glass.mesh = MUG_MESH
		glass.scale = Vector3.ONE * mug_scale
		glass.rotation_degrees = Vector3(0, 150, 0)
		var slot_x := (float(i) - float(MAX_TRAY - 1) / 2.0) * 0.17
		glass.position = Vector3(slot_x, 0.03, 0)
		var mat := _solid(Color.WHITE)
		glass.material_override = mat
		glass.visible = false
		$Hold.add_child(glass)
		_tray_glasses.append(glass)
		_tray_materials.append(mat)

	# The active glass we're pouring. It's top_level so we can park it in WORLD space
	# under the tap you're pouring from (you watch it fill where you're looking),
	# rather than down at your hip.
	_active_root = Node3D.new()
	_active_root.top_level = true
	$Hold.add_child(_active_root)

	# The mug is the imported glass model (Beer_Mug_Glass.usdz -> OBJ), shown as clear
	# glass. Its model is MUG_MODEL_H tall with its base at y=0, so we scale it to
	# GLASS_H and sit its base at GLASS_BOTTOM; the liquid/foam cylinders below fill it.
	var mug := MeshInstance3D.new()
	mug.mesh = MUG_MESH
	var s := GLASS_H / MUG_MODEL_H
	mug.scale = Vector3(s, s, s)
	mug.position = Vector3(0, GLASS_BOTTOM, 0)
	mug.rotation_degrees = Vector3(0, 150, 0)      # turn the handle to a natural angle
	var mug_mat := _solid(Color(0.82, 0.88, 0.95, 0.16))
	mug_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mug_mat.roughness = 0.05
	mug_mat.metallic = 0.0
	mug_mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # thin glass: show both faces
	mug.material_override = mug_mat
	_active_root.add_child(mug)

	# Beer + foam sit INSIDE the glass (radius kept just under the mug's inner wall).
	_active_liquid = MeshInstance3D.new()
	_active_liquid.mesh = _unit_cylinder(GLASS_INNER_R)
	_active_liquid_mat = _solid(Color.WHITE)
	_active_liquid.material_override = _active_liquid_mat
	_active_root.add_child(_active_liquid)

	_active_foam = MeshInstance3D.new()
	_active_foam.mesh = _unit_cylinder(GLASS_INNER_R)
	_active_foam.material_override = _solid(Globals.FOAM_COLOR)
	_active_root.add_child(_active_foam)

	# A thin "stream" of beer that appears above the glass while actively pouring,
	# reaching down from the rim to the current beer surface. Sells the pour.
	_pour_stream = MeshInstance3D.new()
	_pour_stream.mesh = _unit_cylinder(0.008)
	_pour_stream_mat = _solid(Color.WHITE)
	_pour_stream_mat.emission_enabled = true
	_pour_stream.material_override = _pour_stream_mat
	_pour_stream.visible = false
	_active_root.add_child(_pour_stream)

	_hold_base_y = $Hold.position.y


func _update_active_visual() -> void:
	# Tray glasses reflect what's stocked.
	for i in MAX_TRAY:
		if i < _tray.size():
			_tray_glasses[i].visible = true
			_tray_materials[i].albedo_color = Globals.color_for(_tray[i]["type"])
		else:
			_tray_glasses[i].visible = false

	# Active glass fills up as we pour -- parked on the counter under the tap.
	_active_root.visible = _beer_type != -1
	if _beer_type == -1:
		return
	_active_root.global_position = Vector3(_active_tap_world.x, GLASS_SIT_Y, _active_tap_world.z)
	_active_root.global_rotation = Vector3.ZERO
	var liquid_h := GLASS_H * _liquid
	var foam_h := GLASS_H * _foam
	_active_liquid.visible = liquid_h > 0.001
	_active_liquid.scale.y = maxf(liquid_h, 0.001)
	_active_liquid.position.y = GLASS_BOTTOM + liquid_h / 2.0
	_active_liquid_mat.albedo_color = Color(0.6, 0.5, 0.3) if _ruined else Globals.color_for(_beer_type)
	_active_foam.visible = foam_h > 0.001
	_active_foam.scale.y = maxf(foam_h, 0.001)
	_active_foam.position.y = GLASS_BOTTOM + liquid_h + foam_h / 2.0

	# Pour stream: a thin beer column from the FAUCET spout down to the beer surface,
	# visible only while actively holding the pour.
	var surface := GLASS_BOTTOM + liquid_h + foam_h
	var spout_local := (_active_tap_world.y - GLASS_SIT_Y) - 0.05   # faucet tip in root space
	var stream_h := maxf(spout_local - surface, 0.001)
	_pour_stream.visible = _pouring_now and not _ruined
	_pour_stream.scale.y = stream_h
	_pour_stream.position.y = surface + stream_h / 2.0
	_pour_stream_mat.albedo_color = Globals.color_for(_beer_type)
	_pour_stream_mat.emission = Globals.color_for(_beer_type)
	_pour_stream_mat.emission_energy_multiplier = 0.4


# A gentle idle bob on the carried tray/glass so it reads as "held", with a little
# extra bounce while walking.
func _update_hold_bob(delta: float) -> void:
	var moving := Vector2(velocity.x, velocity.z).length() > 0.2
	_bob_time += delta * (9.0 if moving else 2.0)
	var amp := 0.012 if moving else 0.004
	$Hold.position.y = _hold_base_y + sin(_bob_time) * amp


func _solid(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	return mat


func _unit_cylinder(radius: float) -> CylinderMesh:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 1.0
	return cyl


# ------------------------------------------------------------------------------
# On-screen hint
# ------------------------------------------------------------------------------
func _update_hint(tap: Dictionary, near_tap: bool, at_register: bool, gm: Node) -> void:
	var hint := ""
	var tray_count := _tray.size()

	if at_register and gm != null and gm.register_active():
		match gm.register_method():
			Globals.PayMethod.CASH:
				hint = "Cash: press 1 / 5 / 0 for $1 / $5 / $10 (Backspace resets), then Space to give"
			Globals.PayMethod.CARD:
				hint = "Card: type the total on the number keys, then hold Space to swipe"
			Globals.PayMethod.LINE:
				hint = "LINE Pay: press Space to scan their QR code"
		if hint != _last_hint:
			_last_hint = hint
			var ui0 := get_tree().get_first_node_in_group("ui")
			if ui0 != null and ui0.has_method("set_hint"):
				ui0.set_hint(hint)
		return

	var customer := _nearest_waiting_customer()

	if customer != null and _find_tray_glass(customer.get_order()) != -1:
		# Something we can hand over is right here -- serving takes priority.
		hint = "Press Space to serve their %s" % Globals.name_for(customer.get_order())
	elif _beer_type != -1:
		# We're filling a glass.
		if _ruined:
			hint = "Spilled! Ease off the pour -- or press Q to toss it"
		elif _is_perfect():
			hint = "Perfect pour! let go -- it trays up on its own"
		else:
			hint = "Hold Space to fill, then ease off and let the foam settle into the green"
	elif near_tap:
		if tray_count >= _capacity():
			hint = "Tray full (%d) -- go serve some beers" % tray_count
		else:
			hint = "Hold Space to pour a %s" % Globals.name_for(tap["type"])
	elif customer != null:
		hint = "They want a %s -- none on your tray (Q to dump a wrong one)" % Globals.name_for(customer.get_order())
	elif tray_count == 0:
		hint = "Go to a tap and hold Space to pour beers"
	else:
		hint = "Carrying %d beer(s) -- serve them (Q dumps a wrong beer)" % tray_count

	if hint != _last_hint:
		_last_hint = hint
		var ui := get_tree().get_first_node_in_group("ui")
		if ui != null and ui.has_method("set_hint"):
			ui.set_hint(hint)


func _quality_word() -> String:
	match _grade():
		Grade.PERFECT: return "perfect"
		Grade.GOOD: return "good"
		_: return "low"
