# globals.gd
#
# Autoload singleton "Globals": constant, shared data that many scripts need to
# agree on. Mutable game state (score, who's sitting where) lives in GameManager,
# NOT here.
#
# This is the "Beers" level. Drinks are three beer flavors. The code stays
# generic ("drink") on purpose, so later levels (cocktails, custom cocktails)
# can reuse the same structure by swapping this data out.
extends Node

# --- Beers --------------------------------------------------------------------
# The three beers you can pour this level. LAGER == 0, AMBER == 1, STOUT == 2.
enum Drink { LAGER, AMBER, STOUT }

const DRINK_COUNT := 3

# Beer body colors, indexed by the enum above.
const DRINK_COLORS := [
	Color(0.93, 0.74, 0.22),  # LAGER - pale gold
	Color(0.78, 0.42, 0.13),  # AMBER - copper
	Color(0.20, 0.12, 0.08),  # STOUT - near black
]

const DRINK_NAMES := ["Lager", "Amber", "Stout"]

# The creamy head on top of a poured beer.
const FOAM_COLOR := Color(0.97, 0.94, 0.85)


# --- Parties & seating --------------------------------------------------------
# Customers arrive in parties. The party's kind decides how big it is and what
# kind of seating it needs.
enum PartyKind { SINGLE, DUO, GROUP }
const PARTY_LABELS := ["Single", "Duo", "Group"]

# Kinds of seating in the bar. A single sits at the BAR (a stool), a duo at a
# SMALL table, a group at a LARGE table.
enum SeatKind { BAR, SMALL, LARGE }
const SEAT_LABELS := ["Bar", "Table", "Big Table"]

# How a party pays at the register. Each party uses one method:
#   CASH - you make change with $1/$5/$10 buttons
#   CARD - hold Space to swipe the card until it approves
#   LINE - press Space once to scan their LINE Pay QR code
enum PayMethod { CASH, CARD, LINE }
const PAY_LABELS := ["Cash", "Credit Card", "LINE Pay"]


func pay_label(method: int) -> String:
	if method < 0 or method >= PAY_LABELS.size():
		return "Pay"
	return PAY_LABELS[method]


func color_for(drink_index: int) -> Color:
	if drink_index < 0 or drink_index >= DRINK_COLORS.size():
		return Color.WHITE
	return DRINK_COLORS[drink_index]


func name_for(drink_index: int) -> String:
	if drink_index < 0 or drink_index >= DRINK_NAMES.size():
		return "None"
	return DRINK_NAMES[drink_index]


# Which seating kind does a party of this kind need?
func required_seat_kind(party_kind: int) -> int:
	match party_kind:
		PartyKind.SINGLE: return SeatKind.BAR
		PartyKind.DUO: return SeatKind.SMALL
		_: return SeatKind.LARGE


func party_label(party_kind: int) -> String:
	if party_kind < 0 or party_kind >= PARTY_LABELS.size():
		return "Party"
	return PARTY_LABELS[party_kind]


# --- Money -------------------------------------------------------------------
# What one beer costs, based on how well it was poured (quality = fill level).
func price_for(quality: float) -> int:
	if quality >= 0.9:
		return 8
	if quality >= 0.75:
		return 6
	return 4


# The bill a customer hands over: the next whole $10 at or above their tab.
# (So the player usually has to make change.)
func tender_for(tab: int) -> int:
	if tab <= 0:
		return 0
	return int(ceil(tab / 10.0)) * 10

