# Battery Collector — Change Log

A plain-language record of every change to the game: what changed, why, and which
files hold the snapshot. Newest entries first.

Script snapshots live in `Scripts/<ScriptName>/V<n>.txt`. Each version is a full
copy of the script as it existed at that point, so you can diff any two versions.
(Those numbered snapshots are retired as of 2026-09-10 — `src/` + git history +
this file are the record now. The `Scripts/` folder was removed 2026-09-10.)

---

## 2026-09-11 — Power draw is real now: dumped mAh is a reserve the GPUs burn

**Goal:** make yesterday's power-need readout actually load-bearing. Upgrading
Cash should genuinely make the data center need more power to run, not just
display a bigger number next to an unaffected timer.

### The mechanic changed, not just the numbers
- **Before:** dumping converted mAh into a precomputed seconds-timer
  (`Seconds` upgrade), and Cash-per-second paid out on that timer regardless of
  Cash level. Power need was a readout with nothing behind it.
- **Now:** dumping adds to a real **power reserve** (mAh banked). Every second
  the data center runs, it draws `Upgrades.powerNeeded(CashLevel)` mAh straight
  out of that reserve -- pay Cash only if there's enough left to cover the
  draw. Run out mid-second and it idles (not destroyed -- next dump tops the
  reserve back up and it resumes).

### `Upgrades.lua` — `Seconds` renamed `Efficiency`, redefined
- Was "seconds of runtime per 1000 mAh" (base 2, +0.5/lvl) -- a number that fed
  a timer unrelated to Cash. Now **"power conversion efficiency"**: a
  multiplier on how much reserve a dump actually delivers (base 1.0x,
  +0.2x/lvl). `reserve added = mAh dumped * Efficiency effect`.
- `Upgrades.order` updated to match. Cost curve (50, x1.5/level) unchanged.
- `powerNeeded`'s doc comment updated -- it's enforced now, not just displayed.

### `DataCenter.server.lua` — rewritten around the reserve
- `runs[player]` is now **mAh banked**, not seconds left.
- Dump: `addedReserve = floor(dumped * Upgrades.effect("Efficiency", level))`.
- Payout tick: `powerDraw = Upgrades.powerNeeded(CashLevel)`; if
  `reserve >= powerDraw`, pay `Upgrades.effect("Cash", CashLevel)` and drain the
  reserve by `powerDraw`; otherwise skip this tick and leave the reserve
  untouched (nothing wasted, no player left short over 1 mAh).
- `DataCenterSecondsLeft` (what the sign shows) is now computed fresh each
  publish as `floor(reserve / currentPowerDraw)` -- an honest estimate, always
  consistent with the live numbers.
- No client changes needed: `DataCenterDisplay.client.lua` and `ShopUI.client.lua`
  already read generically (`Upgrades.order`, `id.."Level"`), so the rename and
  the new mechanic required zero edits on the client side.

**The tradeoff, concretely (tested below):** at Cash level 0, 500 mAh = 1 second,
exactly what was promised. Buy Cash to level 2 and the SAME 2000 mAh dump now
lasts only 2 seconds instead of 4 -- but pays 9 Cash/sec instead of 5. Buy
Efficiency to counter it, and the same dump stretches back out. Cash and
Efficiency now pull directly against each other, the way Speed/Capacity already
pull against Seconds/Cash for the shared pool.

**Tested (Play mode):** 500 mAh @ level 0 -> exactly 1 tick, 5 Cash, reserve hits
0. 2000 mAh @ Cash lvl 0 -> 4 ticks, 20 Cash. Bought Cash to lvl 2 (powerDraw
500->900): same 2000 mAh -> 2 ticks, 18 Cash (shorter, richer). Bought
Efficiency to lvl 2 (1.0x->1.4x): same 2000 mAh -> 2800 reserve -> 3 ticks, 27
Cash (stretched back out). Confirmed leftover reserve (500, insufficient for a
tick) survives idling untouched and combines correctly with a later dump
(500+1400=1900 -> 2 more ticks). No console errors throughout.

---

## 2026-09-11 — Power need anchored to a battery's worth (500, not 10)

**The bug report:** the sign read "Needs 10 mAh/s to run" at level 0; expected
500. Checked both the repo and live Studio — they agreed with each other and
with the formula as written (`Cash.base(5) * CASH_POWER_RATIO(2) = 10`), so this
wasn't drift or a mirroring bug. The `500` the user had in mind was `BASE_MAH`,
a *different* constant (a single battery's capacity) that the power formula
never referenced. Once that was clear, the fix was to make power need actually
derive from that number, not to fudge the ratio to coincidentally output 500.

### `Upgrades.lua`
- New `Upgrades.BASE_BATTERY_MAH = 500` -- the shared constant both battery
  value AND data-center power need are now anchored to.
- `CASH_POWER_RATIO` is no longer a bare `2` -- it's computed as
  `Upgrades.BASE_BATTERY_MAH / Upgrades.defs.Cash.base`, so level 0's power
  need is *exactly* one AAA battery's worth per second, by construction. If
  `BASE_BATTERY_MAH` or `Cash.base` ever change, the ratio recalculates itself
  -- it can't quietly drift out of sync the way two independent numbers could.

### `BatterySpawner.server.lua`
- Its own local `BASE_MAH = 500` is gone; battery mAh values now read
  `Upgrades.BASE_BATTERY_MAH` from the shared module instead of keeping a
  private copy of the same number.

**Concepts introduced:** the difference between "the UI is wrong" and "the UI is
right but the code encodes the wrong intent" -- verified both the repo and the
live Studio state before changing anything, rather than assuming either the
report or the code was correct; eliminating a duplicated magic number by moving
it to the one shared module both consumers already required, so it's
structurally impossible for the two to disagree again.

**Tested:** sign reads "Needs 500 mAh/s to run" at Cash level 0. Bought Cash
twice (level 0->2) through the real purchase flow: sign updated to "Needs 900
mAh/s to run" (effect(Cash,2)=9, 9*100=900). Battery mAh values unchanged and
correct (AAA 500, AA 1500). No console errors.

---

## 2026-09-10 — Data center displays the power its GPUs need

**Goal:** upgrading Cash-per-second should visibly cost something -- "adding a
GPU unit" needs more power to run -- and the data center should show that draw
so upgrading feels consequential, not just a bigger number.

### `Upgrades.lua` — a new formula, not a new upgrade
- `Upgrades.powerNeeded(cashLevel)` = `Upgrades.effect("Cash", cashLevel) *
  CASH_POWER_RATIO` (ratio = 2). Derived directly from the Cash payout rate --
  not a separate purchasable stat -- so it's always exactly "2 mAh/sec of draw
  per 1 Cash/sec you've bought." Level 0: 10 mAh/s. Level 2: 18 mAh/s.
- **This is a readout, not a hard limit yet** -- nothing currently stops the data
  center from running even if you have no mAh reserve to match the draw. A
  natural next step if you want it to actually bite.

### World geometry (place file only): `DataCenter.Sign.Billboard`
- Grew from 2 lines to 3 (280x130). New `PowerDraw` TextLabel under `Status`.

### `DataCenterDisplay.client.lua`
- Now also `require`s `Upgrades`. Renders `powerLabel.Text = "Needs %d mAh/s to
  run"` from **the local player's own** `CashLevel` attribute -- same
  per-client-only pattern as the ONLINE/OFFLINE status (one shared sign, each
  player sees their own number). Refreshes on `CashLevel` changes (bought Cash)
  as well as the existing `DataCenterSecondsLeft` trigger.

**Concepts introduced:** deriving a new stat from an EXISTING one instead of
inventing a parallel value (power draw is just Cash-rate times a constant, so it
can never drift out of sync); a readout that's real and wired to live data but
not yet load-bearing -- a deliberate, honest middle step before deciding whether
to make it a hard constraint.

**Tested:** sign read "Needs 10 mAh/s to run" at CashLevel 0. Bought Cash twice
through the real purchase flow (CashLevel 0->2, Cash 500->375); sign updated
live to "Needs 18 mAh/s to run" (effect(Cash,2)=9, 9*2=18), matching the formula
exactly. No console errors.

---

## 2026-09-10 — Walk through batteries once you're full

**Goal:** when your carry capacity is full, BatterySpawner already ignores the
touch (you can't pick it up) -- but the battery's solid body still physically
blocked movement, which just feels like a bug. Now it doesn't.

### Added: `src/client/BatteryCollision.client.lua` (LocalScript)
- Tracks every tagged battery the same way `BatterySpin`/`BatteryGlow` do (wait
  for all 5 parts to replicate before touching anything).
- Computes "am I full?" from `leaderstats.Batteries.Value >=
  Upgrades.effect("Capacity", CapacityLevel)`, and sets `CanCollide` on the 4
  solid body parts (not the already-non-colliding `Hitbox`) to match: full ->
  `false` (walk through), not full -> `true` (normal).
- Re-checks every tracked battery whenever `Batteries.Changed` fires (collect,
  dump) or `CapacityLevel` changes (bought Capacity) -- both fire immediately,
  no polling needed for the full/not-full state itself.
- New batteries get the CURRENT full/not-full state applied the instant they're
  tracked, so one that spawns in while you're already full doesn't start solid.

**This only affects the local player.** `CanCollide` is set purely on this
client's own copy of each battery; the local player's character owns its own
movement physics, so it alone starts walking through. Another player whose
capacity still has room keeps feeling the same battery as solid. (Collection
itself was already server-authoritative and per-player via the `Hitbox`, so this
doesn't change who can pick up what -- only how full-vs-not-full *feels*.)

**Concepts introduced:** per-player physical behaviour without any server
involvement, by exploiting the fact that a player's own movement is simulated
on their own machine; deriving one boolean ("full") from two independently-
changing sources (a leaderstat and an attribute) and refreshing on either.

**Tested:** not full -> `lower_body.CanCollide = true` on live batteries.
Server set `Batteries` to the Capacity cap (5) -> client's copy of every tracked
battery flipped to `CanCollide = false` within one frame. Reduced back below
cap -> flipped back to `true`. No console errors.

---

## 2026-09-10 — Real tradeoffs: Speed & Capacity upgrades, carry cap, despawn timers

**Goal:** progress had become "always more, never a choice." Three changes fix
that: walk speed is now a purchased upgrade (competing with the other three for
the same Cash), carrying is capped by a SLOT count (not mAh, so hoarding rare
batteries is a real strategy), and uncollected batteries expire -- the rarest
fastest -- so grabbing one is a race, not a given.

### `Upgrades.lua` — two new upgrades, four total, one Cash pool
- Added `Speed` (base 4, +1.5/level) and `Capacity` (base 5, +1/level).
- `Upgrades.order = { "Speed", "Capacity", "Seconds", "Cash" }` — the shop's
  display order, and now the single place a new upgrade needs to be added.
- `formatEffect` generalized from a hardcoded "seconds get a decimal" check to a
  `decimal` flag per def (Speed also wants one decimal place).

### `PlayerSpeed.server.lua` — speed no longer comes from carrying
- Completely decoupled from `leaderstats.mAh`. `WalkSpeed = Upgrades.effect(
  "Speed", SpeedLevel)`, capped at 60, reacting to the `SpeedLevel` attribute
  instead of a leaderstat `.Changed`. Simpler script -- no leaderstats dependency
  left at all.

### `PlayerSetup.server.lua` — a new leaderstat: `Batteries`
- A count of how many battery SLOTS you're currently carrying (0 up to your
  Capacity upgrade), separate from `mAh`. Resets on dump.

### `BatterySpawner.server.lua` — capacity gate + expiry timers
- `require(Upgrades)`. On touch: reads the player's `Batteries` count and their
  `Capacity` effect; if `carried.Value >= maxCarry`, the touch is a no-op -- the
  battery stays put, uncollected, full is full. Otherwise both `Batteries` and
  `mAh` go up.
- New `BASE_LIFETIME` (60s, for AAA) / `LIFETIME_FALLOFF` (2): each rarer size
  lives `LIFETIME_FALLOFF` times less long (AAA 60s / AA 30s / C 15s / D 7.5s).
  A `task.delay(pick.lifetime, ...)` expires the battery if nobody grabs it.
- Refactored the collected-guard into one `removeBattery(delay)` helper, called
  by both the `.Touched` handler (RESPAWN_DELAY) and the expiry timer (0 delay)
  -- both set the same `collected` flag first, so a battery collected right as
  its timer fires (or vice versa) is only ever removed/respawned once.

### `Shop.server.lua` — generalized instead of hardcoded
- `levels[player]` and the id-validity check now iterate `Upgrades.defs`
  directly (`for id in Upgrades.defs`) instead of naming "Seconds"/"Cash" by
  hand -- adding a 5th upgrade later won't require touching this file.

### `DataCenter.server.lua` — dumping now empties the whole inventory
- Zeroes `Batteries` alongside `mAh` when you dump, freeing your carry slots.

### `ShopUI.client.lua` — 4 rows, built the same way as 2
- Row-building loops `Upgrades.order` instead of two hardcoded `makeRow` calls;
  panel resized (400x430) to fit.

**Concepts introduced:** an exponential DEcay curve (`base / falloff^n`) as the
mirror image of the growth curve we've used for cost/value; a shared "collected"
flag guarding TWO independent removal paths (touch vs. timer) against a race;
generalizing hardcoded per-upgrade code into a loop over a data table (`Upgrades
.defs`/`.order`) so the data model is the only thing that has to grow.

**Tested (Play mode):** all 4 upgrade attributes present at level 0; bought Speed
(WalkSpeed 4 -> 5.5) and Capacity x2 (cap 5 -> 7) through the real RemoteEvent
flow, costs matched the exponential curve. Walked a player onto 9 real batteries
in sequence: collected exactly 7 (Batteries 0->7, mAh climbing), the 8th and 9th
were left in place, uncollected, cap enforced. Dumped: Batteries and mAh both
reset to 0. Shop panel showed all 4 rows in order with live levels/costs.
Despawn: with lifetimes temporarily shortened to 8/4/2/1s, watched the field for
12s -- total stayed at exactly 15 throughout continuous churn (no duplicate or
lost spawns), confirming the shared-guard fix works; reverted to the real 60/2
values afterward. No console errors at any point.

---

## 2026-09-10 — Rarity glow so battery value reads at a distance

**Goal:** the four sizes look similar from afar. Add a glow that escalates with
rarity: AAA static small gold glow -> AA bigger + pulsing -> C bigger/brighter +
white sparkle particles -> D biggest + most solid, keeping motion and particles.

### Changed: `BatterySpawner.server.lua`
- Each template entry now also carries `rarity` (its 1-based position in
  `BATTERY_TEMPLATES`, 1 = commonest). Every spawned battery gets a `Rarity`
  attribute (1..4) alongside `SpawnCenter` and `mAh`.

### Added: `src/client/BatteryGlow.client.lua` (LocalScript)
- A `TIERS[1..4]` table: `color`, `glowScale` (glow diameter as a multiple of the
  battery's own diameter), `transparency`, `brightness`, and for tiers 2-4
  `pulse`/`pulseAmplitude`/`pulseSpeed`, and for tiers 3-4 `particles` +
  `particleColor`.
- Same tracking pattern as `BatterySpin`: watches the `BatteryPickup` tag, waits
  for `SpawnCenter` + `Rarity` + all 5 parts to have replicated before building
  anything (same replication-race fix learned earlier).
- Per battery, builds a `Neon` `Ball` Part ("RarityGlow") sized off
  `lower_body.Size.Y * tier.glowScale`, plus a `PointLight`, plus (tier 3-4) a
  `ParticleEmitter` of small white-to-gold sparkles.
- **The glow is parented INSIDE the battery model**, not tracked separately -- when
  the server destroys a collected battery, the glow/light/particles are destroyed
  with it automatically. No manual cleanup code needed.
- A `Heartbeat` loop pulses `pulse`-tier glows: `size = base * (1 + sin(t*speed +
  phase) * amplitude)`, each battery's `phase` randomised so they don't sync up.

**Concepts introduced:** parenting client-only cosmetic objects inside a
server-owned instance so their lifetime is handled for free; a per-tier config
table driving both visuals and behaviour from one place; `ParticleEmitter`
basics (`Rate`, `Lifetime`, `Speed`, `Size`/`Transparency` as `NumberSequence`,
`LightEmission` for an additive glint look); a sine-wave pulse with per-instance
phase offsets (same trick as the battery spin's phase).

**Tested (Play mode):** confirmed via script -- AAA glow constant at 1.47 studs
(static); AA glow oscillating 2.20-2.94 studs over time (pulsing); C glow bigger,
brighter, with a live `ParticleEmitter` (`Enabled=true`, emitting). Screenshots:
a wide shot shows glow size/brightness clearly separating battery tiers at a
distance; a close shot on a C battery shows visible white sparkle particles
against its gold glow. No console errors.

---

## 2026-09-10 — Batteries carry mAh; scoreboard is capacity, not count

**Goal:** rarer battery = more power. The score is battery **capacity (mAh)**, not
a count. (Voltage would be wrong — real AAA/AA/C/D are all 1.5 V; only capacity
grows with size.)

### `BatterySpawner.server.lua`
- New config `BASE_MAH = 500`. Each template's mAh =
  `math.floor(BASE_MAH * RARITY_FALLOFF ^ (i - 1))` — the exact inverse of its
  spawn weight, so value tracks rarity off the same knob:
  AAA 500 / AA 1500 / C 4500 / D 13500.
- Each spawned battery gets a `mAh` attribute.
- Collecting adds `pick.mah` to the score (was `+= 1`).

### `PlayerSetup.server.lua`
- The `Batteries` IntValue is now `mAh` (0-based). Scoreboard column reads "mAh".

### `PlayerSpeed.server.lua`
- Reads `leaderstats.mAh`. `SPEED_PER_BATTERY` (1.5/battery) -> `SPEED_PER_1000_MAH`
  (1.5 per 1000 mAh): `WalkSpeed = BASE + (mAh / 1000) * SPEED_PER_1000_MAH`, cap 60.

### `DataCenter.server.lua`
- Dumps `leaderstats.mAh` (was `Batteries`), zeroes it.
- New config `MAH_PER_RUNTIME = 1000`. Run time added =
  `floor((mAh dumped / 1000) * Upgrades.effect("Seconds", level))`.

### `Upgrades.lua`
- "Seconds" upgrade renamed "Run time per 1000 mAh" (base/perLevel/cost unchanged:
  2 s per 1000 mAh at level 0, +0.5 per level).

**Concepts introduced:** picking the right real-world unit (capacity vs voltage);
one knob (`RARITY_FALLOFF`) driving two coupled things (how rare, how valuable);
renaming a value that many systems read, and rescaling the formulas that consumed
the old "count" meaning into a "per 1000 units" form so coefficients stay legible.

**Tested (Play mode):** scoreboard shows mAh + Cash (no Batteries). Live batteries
carry mAh 500 / 1500 / 4500 by type. mAh 0 -> speed 4; mAh 10000 -> speed 19
(4 + 10*1.5). Dumped 10000 mAh -> mAh 0, run 20 s (10 * 2), Cash paid 5/s, speed
back to 4. Shop row reads "Run time per 1000 mAh  2.0s -> 2.5s". No errors.

---

## 2026-09-10 — Battery sizes spawn at exponentially-falling rates

**Goal:** AAA is commonest, D is rarest, and each size in between is a constant
factor rarer than the last.

### Changed: `src/server/BatterySpawner.server.lua`
- `BATTERY_TEMPLATES` reordered commonest → rarest:
  `{ "Battery_AAA", "Battery", "Battery_C", "Battery_D" }`.
- New config `RARITY_FALLOFF = 3`. At startup each template gets
  `weight = RARITY_FALLOFF ^ (#list - i)` → weights 27 / 9 / 3 / 1 (each 3x the
  next), summed into `totalWeight`.
- New `pickTemplate()`: `roll = math.random() * totalWeight`, walk the list
  subtracting weights, return the entry the roll lands in. Replaces the old
  uniform `templates[math.random(#templates)]`.

**Odds** (falloff 3): AAA ~68% · AA ~23% · C ~7% · D ~2%. Change `RARITY_FALLOFF`
to steepen/flatten it.

**Concepts introduced:** weighted random selection (weights → cumulative roll);
an exponential curve from a single knob (`base ^ position`); ordering a config
list so its index carries meaning.

**Tested:** reproduced the weighting over 4000 draws → 67.5 / 23.0 / 7.1 / 2.4 %,
matching the intended curve. Live field of 15 showed AAA x9, AA x3, C x2, D x1.
No console errors.

---

## 2026-09-10 — Battery size variety (AAA / C / D)

**Goal:** the field spawns a random mix of battery sizes for visual variety.
All sizes still count as **1** when collected — cosmetic only.

### Added (world, place file only): 3 new models in `ServerStorage`
- `Battery_AAA`, `Battery_C`, `Battery_D` — clones of the AA `Battery` model,
  re-proportioned to real-world battery ratios (relative to AA 14.5mm x 50.5mm):
  AAA x0.72 dia / x0.88 tall, C x1.81 / x0.99, D x2.36 / x1.22. Built by a one-off
  Luau script (scale each part's Size on its local axes — every part has local X =
  vertical — and its offset from the model centre; re-centre the pivot).
- `Models/*.png` in the repo are the reference renders these were matched to.
- Not version-controlled (`.rbxl` is gitignored; can't export `.rbxmx` via tools).

### Changed: `src/server/BatterySpawner.server.lua`
- `batteryTemplate` (one model) -> `BATTERY_TEMPLATES` list + a `templates` table
  built at startup, each entry `{ model, height }` (height from `GetBoundingBox`).
- `spawnBattery()` picks `templates[math.random(#templates)]`.
- `CENTER_HEIGHT` (fixed centre Y) -> `BASE_HOVER` (1.8): each battery's centre is
  floated at `BASE_HOVER + height/2`, so every size's **bottom** lines up at the
  same height regardless of how tall it is.

**No client change:** `BatterySpin` already works on any battery — all four models
have the same 5 parts (`PART_COUNT`), and it pivots about the `SpawnCenter`
attribute the server sets, whatever the size.

**Concepts introduced:** non-uniform scaling of a model in code (per-part Size on
local axes + per-part offset from centre); a "png is a picture, not a model" —
the 3-D versions were built from the existing model, not imported; looking up a
list of templates once and picking randomly; deriving spawn height from each
template's own measured size so mixed sizes still sit level.

**Tested (Play mode):** 15 batteries spawned as a random mix (saw AAA x4, AA x2,
C x3, D x6), all four sizes present, all tilting/spinning on the client, all with
`bottomY = 1.80`. No console errors.

---

## 2026-09-10 — Upgrade shop (first UI, first RemoteEvent)

**Goal:** a second platform that opens a shop UI with two upgrades — "run time
per battery" and "cash per second" — each with an exponentially growing cost.

### Added: `src/shared/Upgrades.lua` (ModuleScript -> ReplicatedStorage)
- One source of truth for both upgrades. `defs` table holds `base`, `perLevel`,
  `baseCost`, `growth` per upgrade id ("Seconds", "Cash").
- `Upgrades.effect(id, level)` = `base + level * perLevel` (linear effect).
- `Upgrades.cost(id, level)` = `floor(baseCost * growth ^ level)` — **exponential**
  (50, 75, 112, 168, 253, ... at growth 1.5).
- `Upgrades.formatEffect` for display. Server and client both `require` this, so
  the numbers can't drift apart.

### Added (world geometry, place file only): `Workspace.Shop`
- `Pad` (12x1x12, steady blue) at (6, 0.5, -3), beside the data-center pad.
- `Sign` BillboardGui: "UPGRADE SHOP".

### Added: `src/server/Shop.server.lua`
- Creates the `BuyUpgrade` RemoteEvent in ReplicatedStorage.
- Owns `levels[player] = { Seconds = 0, Cash = 0 }`; publishes them as
  `SecondsLevel` / `CashLevel` attributes on the Player.
- `BuyUpgrade.OnServerEvent`: **validates the client's request** — real id?
  can they afford `Upgrades.cost`? — then deducts Cash and bumps the level.
  The client never gets to say "I bought this"; the server decides.

### Added: `src/client/ShopUI.client.lua` (LocalScript)
- Builds the whole `ScreenGui` in code (StarterGui isn't in the Rojo project, so
  a code-built UI is what lives in the repo). Panel, a `makeRow(id)` helper used
  for both upgrades, Buy buttons.
- `Buy` -> `BuyUpgrade:FireServer(id)`. Nothing else.
- `refresh()` redraws from `Upgrades` + the player's own attributes + Cash;
  reconnected on `SecondsLevel`/`CashLevel` attribute changes and `Cash.Changed`.
  Button turns green/grey by affordability.
- A `Heartbeat` loop shows/hides the panel by distance to `Shop.Pad`
  (`SHOW_RANGE = 12`).

### Changed: `src/server/DataCenter.server.lua`
- Removed the fixed `SECONDS_PER_BATTERY` / `CASH_PER_SECOND` constants. Now each
  is computed per player from `Upgrades.effect(id, player:GetAttribute(id.."Level"))`
  — so a player's own upgrades scale their dump. Run time added is `math.floor`ed
  to stay a whole number.

**Concepts introduced:** a **ModuleScript** as shared code both sides `require`;
a **RemoteEvent** as the client->server request channel and *server-authoritative
validation* (never trust the client's claim); building a GUI entirely in code
(`ScreenGui`/`Frame`/`TextButton`/`UICorner`/`UIListLayout`), `Button.Activated`,
`ScreenGui.Enabled` + `ResetOnSpawn`; an exponential cost curve; one system
(DataCenter) reading another system's (Shop's) published per-player state.

**Tested (Play mode):** panel appears on the pad, hides off it. Rows show
"2.0s -> 2.5s" / "5/s -> 7/s" and "Buy $50". Bought Cash once: Cash 500->450,
CashLevel 0->1, row became "7/s -> 9/s" / "Buy $75". Bought Seconds until broke:
levels 0..4 at costs 50/75/112/168, then further buys and an invalid id were
rejected (level and Cash unchanged). Dumped 4 batteries with SecondsLevel 4 +
CashLevel 1: run started at ~16s (4 x 4.0) and paid ~7/s. No errors.

---

## 2026-09-10 — Data-center pad is now per-player, not shared

**Goal:** the pad should look "ONLINE" (glowing) only for the player whose own
dump is currently paying out — not for everyone whenever anyone's run is active.

The payout was already per-player (`runs[player]`); only the *visual* was shared,
because one Part's `Color`/`Material` set on the server replicates to everyone the
same way. Fix: move the visual to the client.

### Changed: `src/server/DataCenter.server.lua`
- Removed all pad `Color`/`Material` and sign `Text` writes, plus `anyRunActive()`
  and `refreshVisuals()`.
- Added `publish(player)` → `player:SetAttribute("DataCenterSecondsLeft", runs[player] or 0)`,
  called on every dump, every payout tick, and on player join. This is the one
  value each client needs.

### Added: `src/client/DataCenterDisplay.client.lua` (LocalScript)
- Reads `LocalPlayer:GetAttribute("DataCenterSecondsLeft")`, and on
  `GetAttributeChangedSignal` sets the Pad's colour/material and the sign text
  **locally**. A local property change to a shared part only affects that
  client's view, so each player sees the pad reflect their own run (sign now also
  shows a live "ONLINE  Ns" countdown).

**Concepts introduced:** why a shared world part can't show different things to
different players from the server, and the fix — publish a per-player value
(here a Player attribute) and let each client render from its own copy; local
vs. replicated property writes on a shared instance.

**Tested:** server sets the attribute → client sees it, pad goes Neon + sign
reads "ONLINE  Ns" on that client only; server's own view of the pad stays
SmoothPlastic throughout (server never touches it). Dump of 3 batteries paid
5→10→15→30 over 6s then powered down. No errors.

**Note:** Player attributes replicate to *all* clients, so technically another
player could read your `DataCenterSecondsLeft`. Harmless here; a RemoteEvent to
just the owner would be the private version if it ever mattered.

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
