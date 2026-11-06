# touch_action_button.gd
#
# A round on-screen button for touch that presses/releases an input ACTION, so it supports
# both HOLD (hold to pour / swipe a card) and TAP (serve a beer, give change, scan) with no
# changes to player.gd -- it just reads is_action_pressed / is_action_just_pressed as always.
extends Control

@export var action: StringName = &"pour"
@export var label_text := "POUR"
@export var button_color := Color(0.90, 0.55, 0.20, 0.55)

var _touch_index := -1
var _down := false
var _label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE            # never grab the keyboard (don't eat Space)
	_label = Label.new()
	_label.text = label_text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	add_child(_label)
	visibility_changed.connect(_force_release)
	tree_exiting.connect(_force_release)


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	var col := button_color
	if _down:
		col = Color(col.r, col.g, col.b, 0.9)
	draw_circle(c, r, col)
	draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 3.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_down = true
			Input.action_press(action)
			queue_redraw()
			accept_event()
		elif not event.pressed and event.index == _touch_index:
			_end()
			accept_event()


func _end() -> void:
	_touch_index = -1
	_down = false
	Input.action_release(action)
	queue_redraw()


func _force_release() -> void:
	if _down:
		Input.action_release(action)
	_touch_index = -1
	_down = false
