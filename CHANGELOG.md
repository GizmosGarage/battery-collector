# Battery Collector — Change Log

A plain-language record of every change to the game: what changed, why, and which
files hold the snapshot. Newest entries first.

Script snapshots live in `Scripts/<ScriptName>/V<n>.txt`. Each version is a full
copy of the script as it existed at that point, so you can diff any two versions.
(Those numbered snapshots are retired as of 2026-09-10 — `src/` + git history +
this file are the record now. The `Scripts/` folder is kept for early history.)

---

## 2026-09-10 — AI data center: dump batteries for timed Cash income

**Goal (theme):** batteries are hoarded power. Carry them to the "AI data centre",
dump them, and it runs for a while generating money. Bigger dump = longer run =
more Cash. Upgrades to this process come later.

### Added: `Cash` stat — `src/server/PlayerSetup.server.lua`
- Second `IntValue` in `leaderstats` next to `Batteries`. Shows as a second
  column in the top-right scoreboard, starts at 0.

### Added (world geometry, place file only): `Workspace.DataCenter`
- `Pad` (Part, 16x1x16, anchored) at (-19, 0.5, -3), just north of the spawn pad.
  Dark when idle; turns Neon green while running.
- `Sign` (tiny invisible part) holding a `BillboardGui` with "AI DATA CENTER" and
  a status line ("OFFLINE" / "ONLINE").
- NOT in the repo (the `.rbxl` is gitignored). If the place is ever rebuilt from
  the repo, this model has to be recreated.

### Added: `DataCenter` script — `src/server/DataCenter.server.lua`
- CONFIG: `SECONDS_PER_BATTERY` (2), `CASH_PER_SECOND` (5), `PAYOUT_INTERVAL` (1),
  `DUMP_DEBOUNCE` (1).
- `Pad.Touched` by a player carrying batteries: set their `Batteries` to 0, add
  `dumped * SECONDS_PER_BATTERY` seconds to that player's run timer (`runs[player]`).
  Dumping again while running just extends the timer.
- Payout loop (`task.spawn` + `while true do task.wait(1)`): once a second, every
  active run pays `CASH_PER_SECOND` and loses 1 second; at 0 the run ends and the
  data centre "powers down".
- So total Cash from a dump = `batteries * SECONDS_PER_BATTERY * CASH_PER_SECOND`
  (e.g. 2 batteries -> 4-second run -> 20 Cash).
- Each player has an independent run; the Pad is only the trigger. Guards: a
  1-second per-player debounce plus the "0 batteries = nothing to dump" check
  (handles the `.Touched` burst).
- Pad colour/material + sign text refresh whenever a run starts or ends. The sign
  is looked up defensively so the feature still works if the model has no sign.

**Concepts introduced:** a second currency and how `leaderstats` shows multiple
columns; a server-owned per-player state table (`runs[player]`) driving a timed
process; a fixed-interval loop (`task.wait(1)`) vs. the per-frame `Heartbeat`
loops we've used before, and why a whole-second interval keeps `IntValue` maths
clean; `PlayerRemoving` for state cleanup; world geometry vs. code (this platform
is not version-controlled, only the script is).

**Tested:** Play mode — dropped a player with 2 batteries on the pad: Batteries
went to 0, pad turned Neon/ONLINE, Cash ticked 5 -> 10 -> 15 -> 20 over 4 seconds,
then the run ended and the pad went dark/OFFLINE. Console logged the dump and the
power-down. No errors.

**Known rough edges:** the pad shows ONLINE if *any* player's run is active (one
shared pad, per-player runs); standing still on the pad while a battery respawns
onto you may not auto-dump until you move (`.Touched` needs a fresh contact);
`DataCenter` model isn't in the repo.

---

## 2026-09-10 — Move speed scales with batteries collected

**Direction:** the game is becoming a parody of the "AI data centres are eating
the power grid" story. First mechanic in that direction: you start barely able to
move, and every battery (unit of power) you hoard makes you faster.

### Added: `PlayerSpeed` — `Scripts/Player_Speed/V1.txt`
- Server Script in `ServerScriptService`.
- CONFIG: `BASE_WALKSPEED` (4 -- Roblox default is 16), `SPEED_PER_BATTERY` (1.5),
  `MAX_WALKSPEED` (60).
- `WalkSpeed = min(BASE + batteryCount * SPEED_PER_BATTERY, MAX)`.
- Sets `StarterPlayer.CharacterWalkSpeed = BASE_WALKSPEED` so fresh spawns start
  slow with no one-frame flash of normal speed.
- Per player: re-applies on `CharacterAdded` (respawns) and on every
  `leaderstats.Batteries.Changed`. Also runs once for anyone already in-game.
- Reads the count defensively (`FindFirstChild` chain, default 0).

**Concepts introduced:** `Humanoid.WalkSpeed` as the movement-speed knob;
`StarterPlayer.CharacterWalkSpeed` as the spawn default; `CharacterAdded` +
`WaitForChild("Humanoid")` (the character's parts stream in after the event);
deriving one system's output (speed) purely from another system's state (score)
by listening to `.Changed` -- the two features stay in sync with no shared code.

**Tested:** Server-side check -- WalkSpeed = 4 at 0 batteries, 19 at 10 (4 + 10*1.5),
back to 4 when the score is reset to 0. No console errors.

**Composes with the future round loop:** when step 3 resets `Batteries` to 0
between rounds, this handler will drop everyone back to `BASE_WALKSPEED`
automatically.

---

## 2026-09-10 — Spin moved to the client; batteries pivot about their centre

**Goal:** (1) run the lean/spin on the client so it costs zero network traffic;
(2) rotate each battery about its middle instead of its base.

### Studio change (one-off): battery template pivot -> centre
Ran a script in Edit mode: `template.WorldPivot = CFrame.new(template:GetBoundingBox().Position)`.
The template's pivot now sits at the model's geometric centre (y = 1.375, half its
2.75 height), so any rotation pivots about the middle.

### Changed: `BatterySpawner` — V3 -> V4 — `Scripts/Battery_Spawner/V4.txt`
- Removed the `RunService.Heartbeat` spin loop, the `activeBatteries` table, and
  the tilt/phase maths. The server no longer animates anything.
- `GROUND_Y` -> `CENTER_HEIGHT` (3): batteries are now positioned by their centre,
  and hover so the 45-deg lean clears the floor.
- Each spawn now: `PivotTo(CFrame.new(centerPos))` (upright), then
  `SetAttribute("SpawnCenter", centerPos)`, then `CollectionService:AddTag(battery,
  "BatteryPickup")`, then set `Parent` LAST so the clone replicates with its
  attribute and tag already attached.
- Touch / score / respawn logic unchanged.

### Added: `BatterySpin` (client LocalScript) — `Scripts/Battery_Spin/V1.txt`
- Lives in `StarterPlayer > StarterPlayerScripts` (copied into each player's
  `PlayerScripts` and run on their machine at join).
- Watches the `BatteryPickup` tag. For each battery: records its `SpawnCenter`, a
  random start `phase`, and every part's rest pose relative to an upright frame at
  the centre (`uprightFrame:ToObjectSpace(part.CFrame)`).
- Every `Heartbeat`: advance one shared `spin`, then for each battery set every
  `part.CFrame = pivot * restPose`, where
  `pivot = CFrame.new(center) * CFrame.Angles(0, phase + spin, 0) * TILT_CFRAME`.
- `TILT_DEGREES` and `SPIN_DEGREES_PER_SEC` live here now (client owns the look).

### Bugs hit and fixed while building this (worth remembering)
1. **`Model:PivotTo()` on the client only moved the stored pivot, not the anchored
   parts.** Fix: set each `Part.CFrame` directly instead. (Direct part writes on
   the client do stick.)
2. **Replication race.** A battery's Model, its tag, its `SpawnCenter` attribute,
   and its child Parts can each arrive on the client on different frames. The
   first attempt cached an *empty* parts list on the first frame the tag existed,
   then animated nothing forever. Fixes: (a) retry `track()` every frame instead
   of once at startup; (b) in `track()`, bail until all 5 parts are present before
   caching poses.

**Concepts introduced:** client vs server (`LocalScript`, `StarterPlayerScripts`,
what replicates and what doesn't); `CollectionService` tags + `GetTagged` /
`GetInstanceRemovedSignal` as a way to mark instances for a behaviour; passing
data server->client with `SetAttribute`; `CFrame:ToObjectSpace` to store a pose
relative to a frame, then `frame * pose` to reconstruct it; replication timing
races and writing self-healing per-frame code instead of assuming one-shot setup.

**Tested:** Play mode — 15 batteries lean 45 deg, spin about their centres at
different phases, animation confirmed client-side (server copies stay upright),
no console errors.

**Note:** in Studio, `execute_luau` / screen captures against the running game
show client state during Play; verified the terminal part orbits (spin) while
tilt stays 45 deg.

---

## 2026-09-10 — Tilt bumped to 45 degrees

**Goal:** steeper lean on the batteries.

### Changed: `BatterySpawner` — V2 -> V3 — `Scripts/Battery_Spawner/V3.txt`
- `TILT_DEGREES` 15 -> 45 (config only; the CFrame math is unchanged).
- `GROUND_Y` 0.5 -> 1.2 — at 45 deg the low edge of the spinning battery reached
  the floor, so the base is lifted enough to clear it. Batteries now hover a
  little, which also helps them stand out against the grey baseplate.

**Tested:** Play mode — batteries lean at 45 deg, hover clear of the floor, still
spinning, no console errors.

## 2026-09-10 — Batteries lean and spin

**Goal:** batteries appear tilted to the side and continuously rotate around the
vertical axis, for a "collectible" look.

### Changed: `BatterySpawner` — V1 -> V2 — `Scripts/Battery_Spawner/V2.txt`
- New CONFIG values: `TILT_DEGREES` (15), `SPIN_DEGREES_PER_SEC` (90). `GROUND_Y`
  raised 0 -> 0.5 so the lean doesn't clip the baseplate.
- `randomSpawnCFrame()` split into `randomBasePosition()` (just a Vector3) plus a
  new `batteryCFrame(basePos, phase)` that composes:
  `CFrame.new(basePos) * CFrame.Angles(0, phase + spin, 0) * TILT_CFRAME`
  — stand at the spot, turn around vertical by (per-battery start angle + global
  spin), then apply the fixed lean. Lean is applied AFTER the turn, so each
  battery's lean direction sweeps around as it spins (a slow wobble).
- Each battery gets a random `phase` (0-359 deg) so they're not all synchronised.
- `activeBatteries` table tracks every live battery as
  `{ model, basePos, phase }`.
- One `RunService.Heartbeat` loop: adds `SPIN_RADIANS_PER_SEC * dt` to a single
  shared `spin` number, then re-`PivotTo`s every active battery. Iterates the
  table backwards and drops any entry whose `model.Parent == nil` (collected /
  destroyed).
- `spin` is one accumulating number, not a per-battery add, so no float drift.

**Concepts introduced:** the per-frame update loop (`RunService.Heartbeat`) and
why you multiply by `dt` (frame-rate independence); composing rotation from
position x yaw x tilt with `CFrame` multiplication, and how multiplication ORDER
changes the result; keeping a table of live objects and cleaning it up by
iterating backwards; one shared accumulator vs. per-object accumulators (drift).

**Tested:** Play mode — 15 batteries spawn leaning ~15 deg, visibly rotate
between two screenshots taken seconds apart, no console errors.

**Note on where this runs:** the spin is done on the SERVER, so 75 parts get
re-positioned and replicated every frame. Fine at this scale. Purely-cosmetic
motion like this usually moves to a client `LocalScript` later (no network cost) —
a good candidate when we add client-side UI.

**One-line variant:** swap to `CFrame.new(basePos) * TILT_CFRAME *
CFrame.Angles(0, phase + spin, 0)` to spin around the battery's OWN tilted axis
instead (less visually obvious for a near-symmetric cylinder).

---

## 2026-09-10 — Spawner: many random batteries + respawn

**Goal:** scatter batteries around the field so there's something to run around
and collect; keep the field stocked as they're taken.

### Retired: the per-battery `Script` (was `Battery_Touched`)
- Deleted from the battery model. `Scripts/Battery_Touched/V1..V5.txt` stay as
  history; there is no longer a script inside the battery.
- Reason: with many batteries we'd have N identical copies of the same logic.
  Collection logic now lives in ONE place.

### Moved: `Workspace.Battery` (Model) -> `ServerStorage.Battery`
- `ServerStorage` is a server-only container: its contents never render in the
  world and never replicate to players. Perfect home for a "template" that only
  exists to be copied.
- Workspace now contains no batteries at edit time — they're created at runtime.

### Added: `BatterySpawner` — `Scripts/Battery_Spawner/V1.txt`
- Server Script in `ServerScriptService`.
- A `CONFIG` block at the top: `BATTERY_COUNT` (15), `AREA_CENTER`, `AREA_SIZE`
  (120-stud square), `GROUND_Y` (0), `RESPAWN_DELAY` (3s). Retune the game by
  editing these five numbers.
- `spawnBattery()`: `:Clone()` the template, `:PivotTo()` a random CFrame in the
  square, parent to `workspace`, connect that clone's `Hitbox.Touched` to a
  collection handler (same `collected` latch + `leaderstats.Batteries += 1` as
  before, no `print` in the hot path).
- On collection: `Destroy()` the battery, then `task.delay(RESPAWN_DELAY,
  spawnBattery)` to queue one replacement — so the total count self-balances
  around `BATTERY_COUNT`.
- Startup: a `for` loop calls `spawnBattery()` 15 times.

**Concepts introduced:** template + `:Clone()` pattern (build once, copy many);
`ServerStorage` as a non-replicated server container; `:PivotTo()` / `CFrame` for
moving a whole model; building a `CFrame` from position × `CFrame.Angles`;
`task.delay` for "run this later without blocking"; a recursive `local function`
(the handler schedules another call to its own function); a `CONFIG` block as the
one place to tune behaviour.

**Tested:** Play mode — 15 batteries spawn scattered across the field, no console
errors. (Collection/respawn verified structurally; walk-over test still to do.)

**Known rough edges (future steps):** random placement can overlap two batteries
or drop one under the spawn pad; batteries sit flat on the grey ground and are
low-contrast (polish: hover + spin + glow); no cap on score, no round/timer.

---

## 2026-09-09 — Flattened the battery from a ProceduralModel to a plain Model

**Goal:** prep for spawning many batteries. Duplicating a `ProceduralModel` would
drag its code generator into every copy; a plain `Model` clones cleanly.

### Structure change (no script edits)
Before:
```
Workspace.Battery (ProceduralModel)
├── ProceduralGeneration (ModuleScript)      -- the "recipe"
│   └── Dependencies (4 helper ModuleScripts)
└── Generated (GeneratedFolder)
    └── Battery (Model)                       -- the "baked result"
        └── lower_body, upper_body, top_cap, terminal, Hitbox, Script
```
After:
```
Workspace.Battery (Model)
└── lower_body, upper_body, top_cap, terminal, Hitbox, Script
```

- Ran a one-off Luau script in Edit mode (not saved in-game): reparented the inner
  `Generated.Battery` model to `Workspace`, then `:Destroy()`d the `ProceduralModel`
  wrapper (which took the recipe, its Dependencies, and the empty `Generated`
  folder with it).
- Parts are `Anchored`, so world positions are unchanged — the battery looks
  identical. Pivot still at approximately (-5, 0, -21).
- The collect `Script` uses only relative references (`script.Parent`,
  `battery.Hitbox`), so it keeps working with no change. Still version V5.
- **Discarded:** the container's attributes (`ColorLower/Upper/Cap/Terminal`,
  `RBX_AI_GENERATED`, `Size`). Those were only *inputs* to the recipe; the colors
  are already baked into each part's `Color` property. We can no longer re-generate
  the mesh from a prompt, which we don't need for this game.

**Concept:** a `ModuleScript` is dormant library code — it only runs when another
script `require()`s it, and nothing did. A `ProceduralModel` keeps the generator
code + its cached output side by side so Studio can re-bake the model when you
tweak a parameter. Once the look is final, that machinery is dead weight;
"flattening" keeps the baked parts and drops the generator.

---

## 2026-09-09 — Scoreboard + score tracking

**Goal:** collecting a battery should actually count for something, visible to the
player, with everyone starting at 0.

### Added: `Player_Setup` (new server script) — `Scripts/Player_Setup/V1.txt`
- Lives in `ServerScriptService` (scripts there run once, on the server, at startup).
- When a player joins, it gives them a `Folder` named exactly `leaderstats`
  containing an `IntValue` named `Batteries` set to `0`.
- The name `leaderstats` is a Roblox convention: the engine automatically draws the
  top-right scoreboard for any stats it finds there. No UI code needed yet.
- Also loops over players already present, to cover the Studio-playtest case where
  the server starts after you've "joined" and `PlayerAdded` already fired.

### Changed: `Battery_Touched` — V4 → V5 — `Scripts/Battery_Touched/V5.txt`
- On collection, now does `player.leaderstats.Batteries.Value += 1` instead of only
  printing. Reads the value through `FindFirstChild` and nil-checks it, so this
  script doesn't error if `Player_Setup` hasn't run for that player yet.
- Added a `collected` boolean guard. `.Touched` fires many times in a few
  milliseconds (once per body part, plus physics jitter), and `Destroy()` isn't
  instant — without the guard one battery could add several points. First valid
  touch flips the latch; later touches return immediately.

**Concepts introduced:** services (`game:GetService`), event + handler
(`PlayerAdded:Connect`), creating instances from code (`Instance.new`, `.Parent`),
platform conventions (`leaderstats`), defensive access (`FindFirstChild` + nil
check), event de-duplication with a boolean latch.

**Tested:** Play mode — scoreboard shows `Batteries: 0`, walking into the battery
ticks it to `1` and prints to Output. Only one battery exists so far, so `1` is the
current max.

---

## Earlier versions (dates not recorded)

Snapshots exist; the notes below are reconstructed from the code.

### `Battery_Touched/V4.txt` — moved the script into the battery, added a Hitbox
- Script now sits inside the battery model itself (`script.Parent` is the battery).
- Listens on a dedicated `Hitbox` part (`battery.Hitbox.Touched`) rather than on the
  visible battery part, so the collision area can be tuned separately from the mesh.
- On a valid player touch: prints, then `battery:Destroy()`.

### `Battery_Touched/V3.txt` — destroy the whole battery on collection
- Added `local battery = batteryPart.Parent` and `battery:Destroy()`, so collecting
  removes the entire battery model, not just registers a touch.

### `Battery_Touched/V2.txt` — only count real players
- Added the `Players` service and `GetPlayerFromCharacter`, so a random part
  brushing the battery no longer counts — only a player's character does.

### `Battery_Touched/V1.txt` — first touch detection
- Bare `Touched` event on the battery part that prints "Something touched the
  battery!". Proof that the event fires.
