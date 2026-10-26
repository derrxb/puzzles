# Bar Rush 🍹

A tiny, Overcooked-style **co-op bar management** game built in **Godot 4.7**
(GDScript only, Compatibility renderer so it can run in a web browser).

This is a learning project: everything is placeholder shapes (boxes, capsules,
cylinders) and the code is heavily commented. It is structured so that **local
co-op** and later **networked multiplayer** can be added without rewriting the
core.

Right now it's single-player: you run the bar, serve drinks, and try to keep
your reputation up.

---

## The gameplay loop

1. Customers walk in the back door every few seconds and sit at a free seat.
2. Each seated customer shows a **colored bubble** (the drink they want) and a
   **patience bar** that drains from green to red.
3. You walk to the **bar counter** and press **1 / 2 / 3** to pour a
   Red / Blue / Green drink. You carry it visibly (a colored cube in your hand).
4. Walk to a waiting customer and press **E** to serve.
   - Right drink → **+money, +reputation**, the customer turns green and leaves.
   - Wrong drink → **−reputation** (the customer keeps waiting for the right one).
5. If a customer's patience runs out, they turn red and storm off → **−reputation**.

Your **reputation** (0–100) and **money** are shown in the top corners.

### Controls

| Action | Keys |
| --- | --- |
| Move | **W A S D** or **Arrow keys** (relative to the camera) |
| Pour a drink (near the counter) | **1** = Red, **2** = Blue, **3** = Green |
| Serve a customer | **E** |

---

## Project structure

```
bar-rush/
├── project.godot          # Project settings: renderer, input map, autoloads
├── export_presets.cfg      # Web export preset (see "Export to web" below)
├── icon.svg                # Window/app icon (placeholder cocktail glass)
│
├── scenes/                 # Reusable "things" are each their own scene
│   ├── Main.tscn           #   The whole level: camera, lights, room, player, managers
│   ├── Player.tscn         #   The player capsule + its "hand" for carrying drinks
│   ├── Customer.tscn       #   One customer (body capsule; bubble/bar built in code)
│   ├── Table.tscn          #   A round table with 2 seats
│   ├── Counter.tscn        #   The bar counter with 3 colored taps
│   └── UI.tscn             #   The on-screen reputation / money / hint labels
│
└── scripts/                # One script per concept
    ├── globals.gd          #   AUTOLOAD "Globals": shared constants (drink colors/names)
    ├── game_manager.gd     #   Owns ALL game state: score, spawning, seat allocation
    ├── main.gd             #   Builds the floor + walls in code
    ├── player.gd           #   Movement, picking up & delivering drinks
    ├── customer.gd         #   Walking, ordering, patience, reacting to service
    ├── counter.gd          #   "Am I close enough to pour a drink?" helper
    ├── table.gd            #   Tracks which of its seats are free
    └── ui.gd               #   Updates the HUD labels from signals
```

### How it fits together (the important idea)

- **`Globals`** holds *constants* only — the three drink colors and their names.
  It's an autoload, so any script can read `Globals.DRINK_COLORS`, etc.
- **`GameManager`** holds all *live state* — reputation, money, who's sitting
  where — and is the **only** thing that changes the score. Other nodes just
  send it signals (`customer.served`, `customer.left_angry`).
- Nodes find each other through **groups** (`"game_manager"`, `"player"`,
  `"counter"`, `"customers"`, `"tables"`) instead of hard-wired paths, so pieces
  stay loosely coupled.
- The **UI is a pure view**: it listens to signals and updates labels. It never
  decides anything.

This matters for multiplayer: when you add a server later, the server runs the
one `GameManager`, and every client just displays what it reports. Because no
other script mutates the score, that change stays contained.

---

## How to run it

**You need Godot 4.7+** (the `.NET`/C# version is *not* required — this is
GDScript only). On macOS it was installed here with `brew install --cask godot`.

### From the editor (easiest)
1. Launch Godot, click **Import**, and select
   `bar-rush/project.godot`.
2. Press **F5** (or the ▶ "Play" button, top-right) to run. `Main.tscn` is set
   as the main scene, so it starts automatically.

### From the command line
```bash
cd bar-rush
godot                         # opens the editor on this project
godot res://scenes/Main.tscn  # runs the game directly
```

### Verifying with no window (headless)
Useful for checking the project has no script errors:
```bash
cd bar-rush
godot --headless --import                       # import assets
godot --headless --quit-after 600 res://scenes/Main.tscn   # run ~10s, then quit
```
(The leaked-resource warnings printed on a headless exit are normal — they just
mean the engine was force-quit mid-frame.)

---

## Export to web

The **"Web" export preset is already set up** in `export_presets.cfg`
(output goes to `build/web/index.html`).

One-time setup — **download the export templates** (about 1 GB; Godot can't
export without them). The easiest way is in the editor:
> **Editor → Manage Export Templates… → Download and Install**

Then export from the command line:
```bash
cd bar-rush
mkdir -p build/web
godot --headless --export-release "Web" build/web/index.html
```

A browser can't open `index.html` directly (it needs to be *served* over HTTP).
Serve the folder and open the printed URL:
```bash
cd build/web
python3 -m http.server 8000
# now visit http://localhost:8000
```
> Tip: web builds run best with "cross-origin isolation". The simple Python
> server above works for local testing; for real hosting (itch.io, GitHub
> Pages, etc.) follow Godot's "Exporting for the Web" docs for the required
> COOP/COEP headers.

---

## Suggested next steps

A rough order that keeps each step small:

1. **Local second player.** Add a second `Player` instance and a second input
   set (e.g. IJKL + Enter). The groups/signals already support more than one
   player. You'll want each player to look up *its own* input actions — pass an
   action-prefix into `player.gd`.
2. **Juice & polish.** Sounds on serve/fail, a little jump/scale when a customer
   is served, a timer or "shift" length, a win/lose screen when reputation hits
   0 or a day ends.
3. **Networking (the big one).** Godot's high-level multiplayer fits the design:
   - Make `GameManager` **server-authoritative** — only the server spawns
     customers and changes score (it already is the sole owner of that state).
   - Replicate player positions with a `MultiplayerSynchronizer`, and turn
     "pour"/"serve" into RPCs the server validates.
   - Clients keep running this same UI, just displaying the server's state.
4. **Events & chaos** (what makes it fun):
   - **Fights**: occasionally two customers start brawling and block a seat
     until a player walks over and breaks it up.
   - **Clogged toilet / spills**: a hazard tile appears that must be cleaned
     (hold E) before customers nearby get unhappy.
   - **Rushes**: speed up `spawn_interval` in waves for difficulty curves.
   - **Recipes**: drinks that need 2 steps (pour + garnish) before serving.

---

## Tweaking the balance

Open `Main.tscn`, select the **GameManager** node, and edit the values in the
Inspector (they're the `@export` variables in `game_manager.gd`):
spawn interval, rewards, penalties. Customer `move_speed` and `patience_time`
live on the **Customer** scene.
