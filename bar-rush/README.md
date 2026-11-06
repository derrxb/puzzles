# Bar Rush 🍺

A tiny, Overcooked-style **co-op bar management** game built in **Godot 4.7**
(GDScript only, Compatibility renderer so it can run in a web browser).

This is a learning project: everything is placeholder shapes (boxes, capsules,
cylinders) and the code is heavily commented. It's structured so that **local
co-op** and later **networked multiplayer** can be added without a rewrite.

Right now it's single-player: you host the bar — seat the parties who arrive,
pour their beers, and serve them before they get fed up.

---

## The gameplay loop ("Beers" — level 1)

1. **Parties arrive** at the door as **singles**, **duos**, or **groups** (4–5).
   Each party has a patience bar while it waits to be seated.
2. **You seat them.** The seating panel at the top of the screen shows the next
   party and every table. Click a table that fits them:
   - singles → a **bar stool**
   - duos → a **small table**
   - groups → a **big table**
3. **They order beers.** Once seated, each person floats a beer-mug bubble (the
   beer they want: **Lager**, **Amber**, or **Stout**) and a draining patience bar.
4. **Pour the round.** Walk to the matching **tap** and **hold Space**. It pours
   like a real keg — slow, and **foam builds the harder/fuller you pour**; ease
   off and let it settle, then top off. Fill into the **green window** (near the
   brim with a small head) for a **perfect pour** — it **auto-adds to your tray**
   (holds **2** for now; unlocks up to 4 as you progress) and builds your
   **perfect-pour combo**. Spills and sloppy pours reset
   the combo. Perfect pours earn **XP** toward bartender **levels** (which grow
   your tips). Press **Q** to dump a wrong beer.
5. **Serve.** Carry the tray to a seated customer and press **Space** — if your
   tray has the beer they ordered, it's handed over. A fuller pour earns more.
6. Served customers drink happily and order again, running up a **tab**. If
   anyone's patience runs out, the **whole party storms off** and reputation drops.
7. **They pay at the register.** When a party is done it frees its table and
   lines up at the **cash register**. Stand at the register and ring up the
   front party with **Space** — but how depends on their payment method:
   - **Cash:** click **$1 / $5 / $10** to make the right change, then **Space**.
   - **Credit card:** **type the total** on the keypad, then **hold Space** to swipe.
   - **LINE Pay:** press **Space** to scan their QR.
   Prompt, accurate service earns a **tip**. Groups may **split the bill** (ring
   up each person). Ignore the line too long and they **dine & dash** — you lose
   the tab and reputation. Prompt, accurate service earns a **tip** (into your
   **Tip Jar**).

Every customer has a **personality** — **Patience**, **Generosity**, **Thirst**,
and **Volatility**, each a random amount. **Click a customer** to inspect their
traits so you can prioritize who to serve; the seating panel also summarizes the
next party at the door.

Reputation (0–100) starts at **50** and climbs slowly with good service. **Money**
comes in only when you collect bills at the register. **Tips** accumulate
separately in the **Tip Jar** (for future bar upgrades), and perfect pours raise
your **bartender level**, which grows your tips.

**Easing in:** the early game is gentle so you can learn the ropes — at first only
**1–2 parties** are in the bar at once and they're all **singles & duos**. As your
bartender level rises you unlock **big groups** (Lv 3) and room for **more parties
at once** (3 at Lv 3, 4 at Lv 6), with a toast when each unlocks.

### Controls

| Action | Input |
| --- | --- |
| Move | **W A S D** or **Arrow keys** (relative to the camera) |
| Pour a beer (at a tap) | **hold Space** |
| Serve a customer | **Space** (next to them) |
| Dump a wrong beer | **Q** |
| Seat a party | **click a table** in the seating panel |
| Ring up / pay | **Space** at the register (+ click $ or keypad buttons) |
| Inspect a customer | **click** them (shows their personality) |

Space is the one action key — by context it pours (at a tap), serves (next to a
customer), or rings up (at the register). Money/keypad buttons are mouse-clicked.

---

## Project structure

```
bar-rush/
├── project.godot          # Project settings: renderer, input map, autoloads
├── export_presets.cfg      # Web export preset (see "Export to web")
├── icon.svg
│
├── scenes/
│   ├── Main.tscn           # The level: camera, lights, counter, player, door, managers, UI
│   ├── Player.tscn         # The bartender capsule + its tray "Hold" point
│   ├── Customer.tscn       # One person (body capsule; bubble/bar built in code)
│   ├── Party.tscn          # A group container (spawns Customers) -- see party.gd
│   ├── Counter.tscn        # The bar counter with 3 taps
│   ├── Table.tscn          # Small (2-seat) table for duos
│   ├── LargeTable.tscn     # Big (5-seat) table for groups
│   ├── Stool.tscn          # A single bar stool
│   ├── Register.tscn       # The cash register (where parties pay)
│   └── UI.tscn             # HUD labels (pour meter, seating & register panels are code-built)
│
└── scripts/
    ├── globals.gd          # AUTOLOAD "Globals": constants (beers, party/seat kinds)
    ├── game_manager.gd     # Owns ALL state: score, party queue, spawning, seating API
    ├── main.gd             # Builds the room shell + places all furniture in code
    ├── player.gd           # Movement, pouring (foam!), the tray, serving
    ├── party.gd            # A party: queues, gets seated, relays member events, leaves
    ├── customer.gd         # One person's order cycle (order → served → reorder) + patience
    ├── counter.gd          # Recolors the taps; reports the nearest tap to pour from
    ├── register.gd         # The cash register: proximity + pay-line positions
    ├── table.gd            # A seat group (bar/small/large): tracks free seats
    └── ui.gd               # HUD + pour meter + seating panel (a pure view of state)
```

### How it fits together (the important idea)

- **`Globals`** holds *constants* only (beer colors/names, party & seat kinds).
- **`GameManager`** holds all *live state* — reputation, money, the door queue —
  and is the **only** thing that changes the score. Parties relay their members'
  events (`order_served`, `order_expired`, `left_unseated`) up to it.
- A **`Party`** coordinates a group of **`Customer`** people: it lines them up at
  the door, walks them to the seats you pick, and sends them home (freeing the
  table) when they finish or get fed up.
- Nodes find each other through **groups** (`game_manager`, `player`, `counter`,
  `customers`, `tables`, `ui`) and talk through **signals**, so pieces stay
  loosely coupled.
- The **UI is a pure view**: it listens to signals and renders. It never decides
  anything.

This matters for multiplayer: a server would run the one `GameManager`, and
clients would just display what it reports. Because nothing else mutates the
score, that change stays contained.

### Tuning the game

Most feel/balance values are `@export` variables, editable in the Inspector:
- **GameManager** (select it in `Main.tscn`): spawn rate, money/reputation rewards
  and penalties.
- **Player** (`Player.tscn`): `pour_rate`, `foam_gain`, `foam_settle`, serve range.
- **Customer** (`Customer.tscn`): `patience_time`, drinking time before reorder.
- **Party** (`Party.tscn`): `door_patience`, visit length.

Furniture layout (how many stools/tables and where) lives in
`scripts/main.gd` → `_place_furniture()`.

---

## How to run it

**You need Godot 4.7+** (GDScript only; the C#/.NET build is not required).

### From the editor
1. Launch Godot, **Import** `bar-rush/project.godot`, and press **F5** (▶).
   `Main.tscn` is the main scene, so it starts automatically.

### From the command line
```bash
cd bar-rush
godot res://scenes/Main.tscn    # run the game
```

### Verifying with no window (headless)
```bash
cd bar-rush
godot --headless --import
godot --headless --quit-after 1200 res://scenes/Main.tscn   # run ~20s, no errors
```
(The leaked-resource warnings on a headless exit are normal — the engine was
force-quit mid-frame.)

---

## Export to web

The **"Web" export preset** is set up in `export_presets.cfg` (output →
`build/web/index.html`).

One-time setup — download the export templates (~1 GB; Godot can't export
without them), easiest via the editor:
> **Editor → Manage Export Templates… → Download and Install**

Then:
```bash
cd bar-rush
mkdir -p build/web
godot --headless --export-release "Web" build/web/index.html
cd build/web && python3 -m http.server 8000   # then open http://localhost:8000
```
(A web build must be *served* over HTTP, not opened as a file. For real hosting,
see Godot's "Exporting for the Web" docs about the COOP/COEP headers.)

---

## Suggested next steps

1. **Local second player.** Add a second `Player` + input set; groups/signals
   already support more than one bartender.
2. **Juice.** Sounds on pour/serve/spill, a tip popup, a day timer and a
   win/lose screen.
3. **Networking.** Make `GameManager` server-authoritative (it already owns all
   state), replicate player positions with a `MultiplayerSynchronizer`, and turn
   pour/serve/seat into RPCs the server validates.
4. **More levels (the plan).** Level 2 = **cocktails** (multi-step drinks);
   level 3 = **custom cocktails** (follow a recipe). The drink data lives in
   `globals.gd`, so new drinks slot in there.
5. **Events & chaos.** Fights that block a table until broken up, spills/clogged
   toilets to clean, timed rushes.
```

A note on today's simplifications you may want to revisit: customers only ever
deliver a *matching* beer from the tray (so you can't hand over the wrong one by
accident), and members walk to seats in a straight line (no pathfinding around
furniture yet).
# puzzles
