# ui.gd
#
# The heads-up display. It's a pure VIEW: it never changes game state, it just
# shows what the GameManager and Player report.
#
# It has three parts:
#   1. HUD labels (reputation, money, carried beer, context hint) -- these live
#      in UI.tscn.
#   2. A POUR METER (built here in code) -- a vertical gauge showing the liquid
#      and foam in the glass, with the "perfect" zone marked, so you can time
#      your pour.
#   3. A SEATING PANEL (built here in code) -- shows the next party at the door
#      and a button per table; click a table to seat them.
extends CanvasLayer

@onready var _rep_label: Label = $RepLabel
@onready var _money_label: Label = $MoneyLabel
@onready var _hint_label: Label = $HintLabel
@onready var _held_label: Label = $HeldLabel
@onready var _held_swatch: ColorRect = $HeldSwatch

const MAX_TRAY := 4
var _tray_swatches: Array[ColorRect] = []
var _last_tray_types: Array = []

# Meta HUD (tip jar, level/XP, perfect-pour combo).
var _tipjar_label: Label
var _level_label: Label
var _xp_fill: ColorRect
var _combo_label: Label

# Personality inspect panel.
var _insp_panel: PanelContainer
var _insp_title: Label
var _insp_fills: Array[ColorRect] = []

# Transient "unlocked!" toast.
var _toast_label: Label
var _toast_timer: Timer

# Pour meter pieces.
var _pour_root: Control
var _pour_liquid: ColorRect
var _pour_foam: ColorRect
var _pour_label: Label
const METER_W := 42.0
const METER_H := 300.0
const GREEN_FROM := 0.74   # perfect-pour liquid window (bottom)
const GREEN_TO := 0.95     # perfect-pour liquid window (top)

# Seating panel pieces.
var _seat_header: Label
var _table_grid: HBoxContainer

# Crosshair + look-at interaction prompt (first/third person).
var _crosshair: ColorRect
var _interact_prompt: Label

# Register panel pieces.
var _reg_backdrop: ColorRect
var _reg_panel: PanelContainer
var _reg_header: Label
var _reg_info: Label
var _reg_cash: Container
var _reg_card: VBoxContainer
var _reg_line: Label
var _reg_typed: Label
var _reg_swipe_fill: ColorRect

var _game_manager: Node

# On-screen touch controls (phones / web). Hidden on desktop.
const TOUCH_JOYSTICK := preload("res://scripts/touch_joystick.gd")
const TOUCH_BUTTON := preload("res://scripts/touch_action_button.gd")
var _touch_root: Control


func _ready() -> void:
	add_to_group("ui")
	_build_pour_meter()
	_build_seating_panel()
	_build_tray_display()
	_build_touch_controls()      # before the register modal so the modal stays on top
	_build_register_panel()
	_build_meta_hud()
	_build_inspect_panel()
	_build_toast()
	_build_crosshair()
	# Connect after everyone's _ready has run so the groups are populated.
	_connect_signals.call_deferred()

	# Refresh the seating panel a few times a second so table availability stays
	# current even when it changes without a queue event (e.g. a party leaves).
	var t := Timer.new()
	t.wait_time = 0.4
	t.autostart = true
	t.timeout.connect(_refresh_seating)
	add_child(t)


# Build the on-screen touch controls: a movement joystick (bottom-left), POUR + DUMP
# buttons (bottom-right), and nothing over the rest so background drags orbit the camera.
# Only shown on touch devices / web (keyboard+mouse on desktop is untouched).
func _build_touch_controls() -> void:
	_touch_root = Control.new()
	_touch_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_touch_root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # empty space -> camera drag
	add_child(_touch_root)

	var stick := Control.new()
	stick.set_script(TOUCH_JOYSTICK)
	stick.anchor_left = 0.0
	stick.anchor_right = 0.45
	stick.anchor_top = 0.45
	stick.anchor_bottom = 1.0
	_touch_root.add_child(stick)

	var pour := Control.new()
	pour.set_script(TOUCH_BUTTON)
	pour.set("action", &"pour")
	pour.set("label_text", "POUR")
	pour.set("button_color", Color(0.90, 0.55, 0.20, 0.55))
	_anchor_br(pour, -180, -180, -30, -30)
	_touch_root.add_child(pour)

	var dump := Control.new()
	dump.set_script(TOUCH_BUTTON)
	dump.set("action", &"dump")
	dump.set("label_text", "DUMP")
	dump.set("button_color", Color(0.65, 0.22, 0.20, 0.5))
	_anchor_br(dump, -205, -300, -115, -210)
	_touch_root.add_child(dump)

	_touch_root.visible = DisplayServer.is_touchscreen_available() or OS.has_feature("web")


# Anchor a control to the bottom-right corner with the given offsets (px from corner).
func _anchor_br(c: Control, l: float, t: float, r: float, b: float) -> void:
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = l
	c.offset_top = t
	c.offset_right = r
	c.offset_bottom = b


func _connect_signals() -> void:
	_game_manager = get_tree().get_first_node_in_group("game_manager")
	if _game_manager != null:
		_game_manager.stats_changed.connect(_on_stats_changed)
		_game_manager.queue_changed.connect(_refresh_seating)
		_game_manager.register_state_changed.connect(_on_register_state)
		_game_manager.meta_changed.connect(_on_meta_changed)
		_game_manager.unlocked.connect(show_toast)
		_on_stats_changed(_game_manager.reputation, _game_manager.money)
		_on_meta_changed(_game_manager.level(), _game_manager.experience, _game_manager.perfect_combo, _game_manager.tip_jar, _game_manager.tray_capacity)
		_on_register_state({"active": false})

	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		player.tray_changed.connect(_on_tray_changed)
		player.pour_state_changed.connect(_on_pour_state_changed)

	_on_tray_changed([])
	_refresh_seating()


# Called by the player to show a context hint.
func set_hint(text: String) -> void:
	_hint_label.text = text


# ------------------------------------------------------------------------------
# Crosshair + look-at prompt
# ------------------------------------------------------------------------------
func _build_crosshair() -> void:
	# A small centre dot so you know where you're aiming.
	_crosshair = ColorRect.new()
	_crosshair.color = Color(1, 1, 1, 0.0)   # hidden: third-person free-cursor, no center aim
	_crosshair.anchor_left = 0.5
	_crosshair.anchor_right = 0.5
	_crosshair.anchor_top = 0.5
	_crosshair.anchor_bottom = 0.5
	_crosshair.offset_left = -3.0
	_crosshair.offset_right = 3.0
	_crosshair.offset_top = -3.0
	_crosshair.offset_bottom = 3.0
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

	# A prompt just under the crosshair ("Press E to seat ...").
	_interact_prompt = Label.new()
	_interact_prompt.anchor_left = 0.5
	_interact_prompt.anchor_right = 0.5
	_interact_prompt.anchor_top = 0.5
	_interact_prompt.anchor_bottom = 0.5
	_interact_prompt.offset_left = -220.0
	_interact_prompt.offset_right = 220.0
	_interact_prompt.offset_top = 20.0
	_interact_prompt.offset_bottom = 52.0
	_interact_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_prompt.add_theme_font_size_override("font_size", 20)
	_interact_prompt.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6))
	_interact_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_interact_prompt.add_theme_constant_override("outline_size", 6)
	_interact_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_interact_prompt)


# Called by the player each frame with what the crosshair is pointing at ("" = nothing).
func set_interact_prompt(text: String) -> void:
	_interact_prompt.text = text


# ------------------------------------------------------------------------------
# HUD
# ------------------------------------------------------------------------------
func _on_stats_changed(reputation: int, money: int) -> void:
	_rep_label.text = "Reputation: %d" % reputation
	_money_label.text = "Money: $%d" % money


# Build a little row of tray-slot swatches (top-right) showing the beers you
# are carrying. The single swatch from UI.tscn is replaced by this row.
func _build_tray_display() -> void:
	_held_swatch.visible = false
	for i in MAX_TRAY:
		var sw := ColorRect.new()
		sw.anchor_left = 1.0
		sw.anchor_right = 1.0
		sw.offset_right = -16.0 - i * 34.0
		sw.offset_left = -16.0 - i * 34.0 - 28.0
		sw.offset_top = 48.0
		sw.offset_bottom = 78.0
		sw.color = Color(0.2, 0.2, 0.2, 0.5)
		add_child(sw)
		_tray_swatches.append(sw)


func _on_tray_changed(types: Array) -> void:
	_last_tray_types = types
	_render_tray()


func _render_tray() -> void:
	var cap := _capacity()
	_held_label.text = "Tray: %d/%d" % [_last_tray_types.size(), cap]
	for i in _tray_swatches.size():
		if i >= cap:
			_tray_swatches[i].visible = false            # slot not unlocked yet
		elif i < _last_tray_types.size():
			_tray_swatches[i].visible = true
			_tray_swatches[i].color = Globals.color_for(_last_tray_types[i])
		else:
			_tray_swatches[i].visible = true
			_tray_swatches[i].color = Color(0.2, 0.2, 0.2, 0.5)


func _capacity() -> int:
	if _game_manager != null and "tray_capacity" in _game_manager:
		return _game_manager.tray_capacity
	return 2


# ------------------------------------------------------------------------------
# Pour meter
# ------------------------------------------------------------------------------
func _build_pour_meter() -> void:
	# A slim gauge pinned to the RIGHT edge, vertically centred -- it sits beside the
	# big first-person glass in the pour view (the glass itself is the main read),
	# clear of the joystick (bottom-left) and POUR/DUMP buttons (bottom-right).
	_pour_root = Control.new()
	_pour_root.anchor_left = 1.0
	_pour_root.anchor_right = 1.0
	_pour_root.anchor_top = 0.5
	_pour_root.anchor_bottom = 0.5
	_pour_root.offset_left = -(METER_W + 30.0)
	_pour_root.offset_right = -30.0
	_pour_root.offset_top = -METER_H / 2.0
	_pour_root.offset_bottom = METER_H / 2.0
	_pour_root.clip_contents = false
	_pour_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pour_root.visible = false
	add_child(_pour_root)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1, 0.9)
	bg.size = Vector2(METER_W, METER_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pour_root.add_child(bg)

	_pour_liquid = ColorRect.new()
	_pour_liquid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pour_root.add_child(_pour_liquid)

	_pour_foam = ColorRect.new()
	_pour_foam.color = Globals.FOAM_COLOR
	_pour_foam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pour_root.add_child(_pour_foam)

	# The green PERFECT window (target liquid level). Drawn on top so you can see
	# the beer fill into it. Fill to here, let the foam settle, and it's perfect.
	var green := ColorRect.new()
	green.color = Color(0.3, 1.0, 0.45, 0.35)
	green.position = Vector2(0, METER_H * (1.0 - GREEN_TO))
	green.size = Vector2(METER_W, METER_H * (GREEN_TO - GREEN_FROM))
	green.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pour_root.add_child(green)

	# Label centred over the slim gauge (wider than the gauge so "PERFECT!" fits).
	_pour_label = Label.new()
	_pour_label.text = "POUR"
	_pour_label.position = Vector2(METER_W / 2.0 - 75.0, -44)
	_pour_label.size.x = 150.0
	_pour_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pour_label.add_theme_font_size_override("font_size", 24)
	_pour_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_pour_label.add_theme_constant_override("outline_size", 5)
	_pour_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pour_root.add_child(_pour_label)


func _on_pour_state_changed(active: bool, liquid: float, foam: float, ruined: bool, beer_type: int, perfect: bool) -> void:
	_pour_root.visible = active
	if not active:
		return

	_pour_liquid.color = Color(0.6, 0.5, 0.3) if ruined else Globals.color_for(beer_type)
	_pour_liquid.size = Vector2(METER_W, METER_H * liquid)
	_pour_liquid.position = Vector2(0, METER_H - METER_H * liquid)

	_pour_foam.size = Vector2(METER_W, METER_H * foam)
	_pour_foam.position = Vector2(0, METER_H - METER_H * (liquid + foam))

	if ruined:
		_pour_label.text = "SPILLED!"
		_pour_label.add_theme_color_override("font_color", Color(1, 0.4, 0.3))
	elif perfect:
		_pour_label.text = "PERFECT!"
		_pour_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
	else:
		_pour_label.text = "POUR"
		_pour_label.add_theme_color_override("font_color", Color.WHITE)


# ------------------------------------------------------------------------------
# Seating panel
# ------------------------------------------------------------------------------
# A small top-centre banner telling you who's waiting at the door. You seat them
# by walking up to a free table and pressing E (handled in player.gd) -- there is
# no clickable table list anymore.
func _build_seating_panel() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -300.0
	panel.offset_right = 300.0
	panel.offset_top = 10.0
	panel.mouse_filter = Control.MOUSE_FILTER_PASS   # let the table buttons be clicked
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(vbox)

	_seat_header = Label.new()
	_seat_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seat_header.add_theme_font_size_override("font_size", 18)
	_seat_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_seat_header)

	# A row of buttons -- one per free table the waiting party can use. Click to seat.
	_table_grid = HBoxContainer.new()
	_table_grid.alignment = BoxContainer.ALIGNMENT_CENTER
	_table_grid.add_theme_constant_override("separation", 6)
	vbox.add_child(_table_grid)


func _refresh_seating() -> void:
	if _game_manager == null or not is_instance_valid(_game_manager):
		return

	var front = _game_manager.get_front_party()
	var waiting: int = _game_manager.get_queue().size()

	# Clear the old table buttons.
	for c in _table_grid.get_children():
		c.queue_free()

	if front == null:
		_seat_header.text = "Nobody waiting to be seated"
		return

	_seat_header.text = "At the door: %s of %d  (%d waiting)  ·  click a seat below\nPatience %d%%  ·  Tips %d%%  ·  Volatility %d%%" % [
		Globals.party_label(front.kind), front.size, waiting,
		int(front.avg_trait(Globals.Trait.PATIENCE) * 100),
		int(front.avg_trait(Globals.Trait.GENEROSITY) * 100),
		int(front.max_trait(Globals.Trait.VOLATILITY) * 100)]

	# One button per free, eligible table -- click to seat the party there (no walking).
	var tables: Array = _game_manager.eligible_tables(front)
	if tables.is_empty():
		var lbl := Label.new()
		lbl.text = "(no free %s table — bus one first)" % Globals.party_label(front.kind)
		lbl.add_theme_font_size_override("font_size", 14)
		_table_grid.add_child(lbl)
	else:
		for table in tables:
			var btn := Button.new()
			btn.text = str(table.label) if table.get("label") != null else "Seat"
			btn.add_theme_font_size_override("font_size", 14)
			btn.pressed.connect(_on_seat_table_pressed.bind(table))
			_table_grid.add_child(btn)


func _on_seat_table_pressed(table) -> void:
	if _game_manager != null and is_instance_valid(_game_manager):
		_game_manager.seat_front_party(table)
		_refresh_seating()


# ------------------------------------------------------------------------------
# Register panel (paying at the cash register)
# ------------------------------------------------------------------------------
func _build_register_panel() -> void:
	# A semi-transparent full-screen backdrop behind the modal. mouse_filter STOP
	# so clicks outside the buttons don't leak through to the game world.
	_reg_backdrop = ColorRect.new()
	_reg_backdrop.color = Color(0, 0, 0, 0.55)
	_reg_backdrop.anchor_right = 1.0
	_reg_backdrop.anchor_bottom = 1.0
	_reg_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reg_backdrop.visible = false
	add_child(_reg_backdrop)

	_reg_panel = PanelContainer.new()
	_reg_panel.anchor_left = 0.5
	_reg_panel.anchor_right = 0.5
	_reg_panel.anchor_top = 0.5
	_reg_panel.anchor_bottom = 0.5
	_reg_panel.offset_left = -300.0
	_reg_panel.offset_right = 300.0
	_reg_panel.offset_top = -230.0
	_reg_panel.offset_bottom = 230.0
	_reg_panel.visible = false
	add_child(_reg_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	_reg_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	_reg_header = _centered_label("", 30)
	vbox.add_child(_reg_header)
	_reg_info = _centered_label("", 22)
	vbox.add_child(_reg_info)

	# CASH: tap the amount buttons to make change (or use 1/5/0 keys on desktop), then
	# tap/press POUR to give.
	_reg_cash = VBoxContainer.new()
	_reg_cash.add_theme_constant_override("separation", 8)
	_reg_cash.add_child(_centered_label("Make the change, then tap POUR to give  (keys: 1 / 5 / 0)", 16))
	var cash_row := HBoxContainer.new()
	cash_row.alignment = BoxContainer.ALIGNMENT_CENTER
	cash_row.add_theme_constant_override("separation", 8)
	cash_row.add_child(_make_button("+$1", func(): _game_manager.register_change_add(1)))
	cash_row.add_child(_make_button("+$5", func(): _game_manager.register_change_add(5)))
	cash_row.add_child(_make_button("+$10", func(): _game_manager.register_change_add(10)))
	cash_row.add_child(_make_button("Reset", func(): _game_manager.register_change_reset()))
	_reg_cash.add_child(cash_row)
	vbox.add_child(_reg_cash)

	# CARD: tap the digit pad to enter the total, then HOLD POUR to swipe.
	_reg_card = VBoxContainer.new()
	_reg_card.add_theme_constant_override("separation", 8)
	_reg_typed = _centered_label("Typed: $0", 28)
	_reg_card.add_child(_reg_typed)
	_reg_card.add_child(_centered_label("Enter the total, then HOLD POUR to swipe", 16))
	var pad := GridContainer.new()
	pad.columns = 5
	for d in range(1, 10):
		pad.add_child(_make_digit(d))
	pad.add_child(_make_digit(0))
	pad.add_child(_make_button("<", func(): _game_manager.register_type_clear()))
	var pad_center := HBoxContainer.new()
	pad_center.alignment = BoxContainer.ALIGNMENT_CENTER
	pad_center.add_child(pad)
	_reg_card.add_child(pad_center)
	var swipe_bg := ColorRect.new()
	swipe_bg.color = Color(0.15, 0.15, 0.18)
	swipe_bg.custom_minimum_size = Vector2(360, 22)
	_reg_swipe_fill = ColorRect.new()
	_reg_swipe_fill.color = Color(0.3, 0.9, 0.7)
	_reg_swipe_fill.size = Vector2(0, 22)
	swipe_bg.add_child(_reg_swipe_fill)
	_reg_card.add_child(swipe_bg)
	vbox.add_child(_reg_card)

	# LINE Pay: just a prompt.
	_reg_line = _centered_label("Tap POUR to scan their QR code", 16)
	vbox.add_child(_reg_line)


func _on_register_state(info: Dictionary) -> void:
	if not info.get("active", false):
		_reg_panel.visible = false
		_reg_backdrop.visible = false
		return
	_reg_panel.visible = true
	_reg_backdrop.visible = true

	var method: int = info["method"]
	var person := ""
	if info["split"] and info["count"] > 1:
		person = "   (person %d of %d)" % [info["index"] + 1, info["count"]]
	_reg_header.text = "%s pays by %s%s" % [info["party_label"], Globals.pay_label(method), person]

	_reg_cash.visible = method == Globals.PayMethod.CASH
	_reg_card.visible = method == Globals.PayMethod.CARD
	_reg_line.visible = method == Globals.PayMethod.LINE

	match method:
		Globals.PayMethod.CASH:
			_reg_info.text = "%d beer(s) — Bill $%d\nPaid $%d · change due $%d · given $%d" % [
				info["beers"], info["tab"], info["tender"], info["change_due"], info["change_given"]]
		Globals.PayMethod.CARD:
			_reg_info.text = "%d beer(s) — Bill $%d" % [info["beers"], info["tab"]]
			_reg_typed.text = "Typed: $%d" % info["typed"]
			_reg_swipe_fill.size = Vector2(360.0 * info["swipe"], 22)
		Globals.PayMethod.LINE:
			_reg_info.text = "%d beer(s) — Bill $%d" % [info["beers"], info["tab"]]


func _centered_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	return l


func _make_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE       # so clicking doesn't steal the Space key
	b.custom_minimum_size = Vector2(92, 58)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(on_press)
	return b


func _make_digit(d: int) -> Button:
	return _make_button(str(d), func(): _game_manager.register_type_digit(d))


# ------------------------------------------------------------------------------
# Meta HUD: tip jar, bartender level + XP, perfect-pour combo
# ------------------------------------------------------------------------------
func _build_meta_hud() -> void:
	_tipjar_label = _hud_label(76.0)
	_level_label = _hud_label(108.0)

	var xp_bg := ColorRect.new()
	xp_bg.color = Color(0.12, 0.12, 0.15, 0.9)
	xp_bg.offset_left = 16.0
	xp_bg.offset_top = 140.0
	xp_bg.offset_right = 216.0
	xp_bg.offset_bottom = 150.0
	xp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(xp_bg)

	_xp_fill = ColorRect.new()
	_xp_fill.color = Color(0.4, 0.8, 1.0)
	_xp_fill.offset_left = 16.0
	_xp_fill.offset_top = 140.0
	_xp_fill.offset_right = 16.0
	_xp_fill.offset_bottom = 150.0
	_xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_xp_fill)

	_combo_label = _hud_label(158.0)
	_combo_label.add_theme_font_size_override("font_size", 26)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_combo_label.visible = false


func _on_meta_changed(level: int, xp: int, combo: int, tipjar: int, _tray_capacity: int) -> void:
	_tipjar_label.text = "Tip Jar: $%d" % tipjar
	_level_label.text = "Bartender Lv.%d" % level
	var frac := float(Globals.xp_into_level(xp)) / float(Globals.XP_PER_LEVEL)
	_xp_fill.offset_right = 16.0 + 200.0 * clampf(frac, 0.0, 1.0)
	_combo_label.visible = combo >= 2
	if combo >= 2:
		_combo_label.text = "Perfect x%d!" % combo
	_render_tray()                                   # capacity may have changed


func _hud_label(top: float) -> Label:
	var l := Label.new()
	l.offset_left = 16.0
	l.offset_top = top
	l.offset_right = 360.0
	l.offset_bottom = top + 30.0
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_font_size_override("font_size", 22)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


# ------------------------------------------------------------------------------
# Personality inspect panel (click a customer to open)
# ------------------------------------------------------------------------------
func _build_inspect_panel() -> void:
	_insp_panel = PanelContainer.new()
	_insp_panel.anchor_left = 1.0
	_insp_panel.anchor_right = 1.0
	_insp_panel.offset_left = -290.0
	_insp_panel.offset_right = -16.0
	_insp_panel.offset_top = 96.0
	_insp_panel.visible = false
	add_child(_insp_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	_insp_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_insp_title = _centered_label("Customer", 18)
	vbox.add_child(_insp_title)
	for i in Globals.TRAIT_LABELS.size():
		vbox.add_child(_trait_row(Globals.TRAIT_LABELS[i]))
	# No Close button: the panel shows while you LOOK at a customer and hides when
	# you look away (driven by player.gd via show_personality / hide_inspect).


func _trait_row(trait_name: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = trait_name
	l.custom_minimum_size = Vector2(96, 0)
	l.add_theme_font_size_override("font_size", 15)
	row.add_child(l)
	var bg := ColorRect.new()
	bg.color = Color(0.15, 0.15, 0.18)
	bg.custom_minimum_size = Vector2(130, 16)
	var fill := ColorRect.new()
	fill.color = Color(0.4, 0.8, 1.0)
	fill.size = Vector2(0, 16)
	bg.add_child(fill)
	row.add_child(bg)
	_insp_fills.append(fill)
	return row


# ------------------------------------------------------------------------------
# Unlock toast (shown briefly when the GameManager announces an unlock)
# ------------------------------------------------------------------------------
func _build_toast() -> void:
	_toast_label = Label.new()
	_toast_label.anchor_left = 0.5
	_toast_label.anchor_right = 0.5
	_toast_label.offset_left = -320.0
	_toast_label.offset_right = 320.0
	_toast_label.offset_top = 120.0
	_toast_label.offset_bottom = 164.0
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 30)
	_toast_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.4))
	_toast_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast_label.add_theme_constant_override("outline_size", 8)
	_toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_label.visible = false
	add_child(_toast_label)

	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func(): _toast_label.visible = false)
	add_child(_toast_timer)


func show_toast(text: String) -> void:
	_toast_label.text = text
	_toast_label.visible = true
	_toast_timer.start(3.0)


# Called by the player while the crosshair is on a customer.
func show_personality(customer) -> void:
	if not is_instance_valid(customer):
		return
	var vals: Array = customer.personality()
	for i in _insp_fills.size():
		if i < vals.size():
			_insp_fills[i].size = Vector2(130.0 * clampf(vals[i], 0.0, 1.0), 16)
	_insp_panel.visible = true


# Called by the player when the crosshair leaves the customer.
func hide_inspect() -> void:
	_insp_panel.visible = false
