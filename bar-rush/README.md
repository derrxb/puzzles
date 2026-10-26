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
4. **Pour the round.** Walk to the matching **tap** and **hold Space**. Beer
   rises — but **foam builds while you pour**; if it overflows the glass, it's
   spilled. Stop to let the foam settle, then top off. Once the pour hits the
   **green**, it's **automatically added to your tray** (holds up to 4, mixed
   types). Poured the wrong beer? Press **Q** to dump one (it costs a little
   money).
5. **Serve.** Carry the tray to a seated customer and press **Space** — if your
   tray has the beer they ordered, it's handed over. A fuller pour earns more.
6. Served customers drink happily and order again; a party eventually leaves
   satisfied. But if anyone's patience runs out, the **whole party storms off**
   and your reputation drops.

Reputation (0–100) starts at **50** and climbs slowly with good service. Money
goes up with every beer sold.

### Controls

| Action | Input |
| --- | --- |
| Move | **W A S D** or **Arrow keys** (relative to the camera) |
| Pour a beer (at a tap) | **hold Space** |
| Serve a customer | **Space** (next to them) |
| Dump a wrong beer | **Q** |
| Seat a party | **click a table** in the seating panel |

Space is the one action key: held at a tap it pours; tapped next to a customer
you can serve, it hands over their beer.

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
│   └── UI.tscn             # HUD labels (the pour meter & seating panel are code-built)
│
└── scripts/
    ├── globals.gd          # AUTOLOAD "Globals": constants (beers, party/seat kinds)
    ├── game_manager.gd     # Owns ALL state: score, party queue, spawning, seating API
    ├── main.gd             # Builds the room shell + places all furniture in code
    ├── player.gd           # Movement, pouring (foam!), the tray, serving
    ├── party.gd            # A party: queues, gets seated, relays member events, leaves
    ├── customer.gd         # One person's order cycle (order → served → reorder) + patience
    ├── counter.gd          # Recolors the taps; reports the nearest tap to pour from
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
