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

const TRAY_CAP := 4
var _tray_swatches: Array[ColorRect] = []

# Pour meter pieces.
var _pour_root: Control
var _pour_liquid: ColorRect
var _pour_foam: ColorRect
var _pour_label: Label
const METER_W := 100.0
const METER_H := 340.0
const GREEN_FROM := 0.75   # bottom of the "good enough" (auto-add) zone
const PERFECT := 0.9       # a perfect pour line

# Seating panel pieces.
var _seat_header: Label
var _table_grid: GridContainer

var _game_manager: Node


func _ready() -> void:
	add_to_group("ui")
	_build_pour_meter()
	_build_seating_panel()
	_build_tray_display()
	# Connect after everyone's _ready has run so the groups are populated.
	_connect_signals.call_deferred()

	# Refresh the seating panel a few times a second so table availability stays
	# current even when it changes without a queue event (e.g. a party leaves).
	var t := Timer.new()
	t.wait_time = 0.4
	t.autostart = true
	t.timeout.connect(_refresh_seating)
	add_child(t)


func _connect_signals() -> void:
	_game_manager = get_tree().get_first_node_in_group("game_manager")
	if _game_manager != null:
		_game_manager.stats_changed.connect(_on_stats_changed)
		_game_manager.queue_changed.connect(_refresh_seating)
		_on_stats_changed(_game_manager.reputation, _game_manager.money)

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
# HUD
# ------------------------------------------------------------------------------
func _on_stats_changed(reputation: int, money: int) -> void:
	_rep_label.text = "Reputation: %d" % reputation
	_money_label.text = "Money: $%d" % money


# Build a little row of tray-slot swatches (top-right) showing the beers you
# are carrying. The single swatch from UI.tscn is replaced by this row.
func _build_tray_display() -> void:
	_held_swatch.visible = false
	for i in TRAY_CAP:
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
	_held_label.text = "Tray: %d/%d" % [types.size(), TRAY_CAP]
	for i in _tray_swatches.size():
		if i < types.size():
			_tray_swatches[i].color = Globals.color_for(types[i])
		else:
			_tray_swatches[i].color = Color(0.2, 0.2, 0.2, 0.5)


# ------------------------------------------------------------------------------
# Pour meter
# ------------------------------------------------------------------------------
func _build_pour_meter() -> void:
	_pour_root = Control.new()
	_pour_root.anchor_top = 1.0
	_pour_root.anchor_bottom = 1.0
	_pour_root.offset_left = 28.0
	_pour_root.offset_right = 28.0 + METER_W
	_pour_root.offset_top = -(METER_H + 140.0)
	_pour_root.offset_bottom = -140.0
	_pour_root.clip_contents = true
	_pour_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pour_root.visible = false
	add_child(_pour_root)

	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.1, 0.9)
	bg.size = Vector2(METER_W, METER_H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pour_root.add_child(bg)

	# The green "good enough" zone (liquid >= GREEN_FROM): fill into here and it's
	# auto-added to your tray. It sits at the TOP of the meter.
	var green := ColorRect.new()
	green.color = Color(0.3, 0.85, 0.4, 0.3)
	green.position = Vector2(0, 0)
	green.size = Vector2(METER_W, METER_H * (1.0 - GREEN_FROM))
	green.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pour_root.add_child(green)

	_pour_liquid = ColorRect.new()
	_pour_liquid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pour_root.add_child(_pour_liquid)

	_pour_foam = ColorRect.new()
	_pour_foam.color = Globals.FOAM_COLOR
	_pour_foam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pour_root.add_child(_pour_foam)

	# A bright line marking a perfect pour.
	var perfect_line := ColorRect.new()
	perfect_line.color = Color(0.4, 1.0, 0.5)
	perfect_line.position = Vector2(0, METER_H * (1.0 - PERFECT) - 1.0)
	perfect_line.size = Vector2(METER_W, 3)
	perfect_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pour_root.add_child(perfect_line)

	_pour_label = Label.new()
	_pour_label.text = "POUR"
	_pour_label.position = Vector2(0, -34)
	_pour_label.add_theme_font_size_override("font_size", 24)
	_pour_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_pour_label.add_theme_constant_override("outline_size", 5)
	_pour_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pour_root.add_child(_pour_label)


func _on_pour_state_changed(active: bool, liquid: float, foam: float, ruined: bool, beer_type: int) -> void:
	_pour_root.visible = active
	if not active:
		return

	_pour_liquid.color = Color(0.6, 0.5, 0.3) if ruined else Globals.color_for(beer_type)
	_pour_liquid.size = Vector2(METER_W, METER_H * liquid)
	_pour_liquid.position = Vector2(0, METER_H - METER_H * liquid)

	_pour_foam.size = Vector2(METER_W, METER_H * foam)
	_pour_foam.position = Vector2(0, METER_H - METER_H * (liquid + foam))

	_pour_label.text = "SPILLED!" if ruined else "POUR"
	_pour_label.add_theme_color_override("font_color",
		Color(1, 0.4, 0.3) if ruined else Color.WHITE)


# ------------------------------------------------------------------------------
# Seating panel
# ------------------------------------------------------------------------------
func _build_seating_panel() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -210.0
	panel.offset_right = 210.0
	panel.offset_top = 10.0
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	_seat_header = Label.new()
	_seat_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seat_header.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_seat_header)

	_table_grid = GridContainer.new()
	_table_grid.columns = 3
	vbox.add_child(_table_grid)


func _refresh_seating() -> void:
	if _game_manager == null or not is_instance_valid(_game_manager):
		return

	var front = _game_manager.get_front_party()
	var waiting: int = _game_manager.get_queue().size()

	if front == null:
		_seat_header.text = "Nobody waiting to be seated"
	else:
		_seat_header.text = "Seat next: %s of %d   (%d waiting)" % [
			Globals.party_label(front.kind), front.size, waiting]

	# Rebuild the table buttons.
	for child in _table_grid.get_children():
		child.queue_free()

	var tables := get_tree().get_nodes_in_group("tables")
	tables.sort_custom(func(a, b): return a.label < b.label)

	for table in tables:
		var eligible: bool = front != null and table.can_seat(front.kind, front.size)
		var btn := Button.new()
		btn.text = "%s\n%d/%d free" % [table.label, table.free_count(), table.seat_count()]
		btn.custom_minimum_size = Vector2(120, 44)
		btn.disabled = not eligible
		# FOCUS_NONE so clicking a table doesn't steal the Space key from pouring.
		btn.focus_mode = Control.FOCUS_NONE
		if eligible:
			btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		btn.pressed.connect(_on_table_pressed.bind(table))
		_table_grid.add_child(btn)


func _on_table_pressed(table) -> void:
	if _game_manager != null:
		_game_manager.seat_front_party(table)
