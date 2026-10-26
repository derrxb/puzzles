# ui.gd
#
# The heads-up display. It shows reputation, money, a context hint, and what the
# player is currently carrying. The UI is purely a VIEW: it never decides game
# logic. It listens to signals from the GameManager (score) and the Player (hint
# and carried drink) and just updates its labels when those signals fire.
#
# This separation -- state lives in GameManager, display lives here -- is exactly
# what makes future multiplayer tractable: a client would run this UI and simply
# render whatever the server-owned GameManager reports.
extends CanvasLayer

# References to the label/swatch nodes defined in UI.tscn.
@onready var _rep_label: Label = $RepLabel
@onready var _money_label: Label = $MoneyLabel
@onready var _hint_label: Label = $HintLabel
@onready var _held_label: Label = $HeldLabel
@onready var _held_swatch: ColorRect = $HeldSwatch


func _ready() -> void:
	# Connect AFTER every node's _ready has run (deferred), so the "game_manager"
	# and "player" groups are guaranteed to be populated by then.
	_connect_signals.call_deferred()


func _connect_signals() -> void:
	var gm := get_tree().get_first_node_in_group("game_manager")
	if gm != null:
		gm.stats_changed.connect(_on_stats_changed)
		# Pull the current values immediately so labels aren't blank at startup.
		_on_stats_changed(gm.reputation, gm.money)

	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		player.hint_changed.connect(_on_hint_changed)
		player.held_drink_changed.connect(_on_held_drink_changed)

	_on_held_drink_changed(-1)  # start empty-handed


func _on_stats_changed(reputation: int, money: int) -> void:
	_rep_label.text = "Reputation: %d" % reputation
	_money_label.text = "Money: $%d" % money


func _on_hint_changed(text: String) -> void:
	_hint_label.text = text


func _on_held_drink_changed(drink_index: int) -> void:
	if drink_index == -1:
		_held_label.text = "Carrying: nothing"
		_held_swatch.color = Color(0.2, 0.2, 0.2, 0.5)
	else:
		_held_label.text = "Carrying: %s" % Globals.name_for(drink_index)
		_held_swatch.color = Globals.color_for(drink_index)
