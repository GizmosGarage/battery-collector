# Battery Collector — Change Log

A plain-language record of every change to the game: what changed, why, and which
files hold the snapshot. Newest entries first.

Script snapshots live in `Scripts/<ScriptName>/V<n>.txt`. Each version is a full
copy of the script as it existed at that point, so you can diff any two versions.
(Those numbered snapshots are retired as of 2026-09-10 — `src/` + git history +
this file are the record now. The `Scripts/` folder was removed 2026-09-10.)

---

## 2026-09-12 — Field unlock progression: LifetimeCash gates Yellow/Blue/Red

**Goal:** priority #3 on the recommended roadmap. Nothing stopped a player
from walking straight from Green to Red and collecting D batteries on day
one -- there was no access restriction at all, so the whole point of
"working up to a bigger field" had no teeth. Yellow, Blue, and Red are now
PERMANENTLY gated behind a lifetime-Cash-earned threshold, roughly scaled
to what buying into that tier's GPUs already costs:

| Field | Requirement | ~ Matches |
| --- | --: | --- |
| Green | none | always open |
| Yellow | $2,500 lifetime Cash | a Basic GPU + slot 2 ($2,000) |
| Blue | $25,000 lifetime Cash | an Advanced GPU + slot 3 ($22,500) |
| Red | $250,000 lifetime Cash | a Data Center GPU + slot 4 ($200,000) |

Reaching a field now roughly lines up with being able to actually USE what
it offers, tying field progression to GPU pacing like the roadmap asked.

### New leaderstat: LifetimeCash
- Total Cash ever EARNED -- unlike Cash, it never goes back down when you
  spend on upgrades or GPUs, so an unlock is truly permanent, never
  something a shopping spree could undo. [DataCenter.server.lua](src/server/DataCenter.server.lua)
  bumps it by the exact same amount as every Cash payout.
- Persists via [PlayerData.lua](src/server/PlayerData.lua) (added to
  `defaultData()` and [PlayerSetup.server.lua](src/server/PlayerSetup.server.lua)'s
  saver) alongside Cash.

### [Fields.lua](src/shared/Fields.lua) — `unlockCash` per field, plus lookup helpers
- Each field def gained `unlockCash` (0 for Green). Added `Fields.getDef(name)`
  (look up one field's def without scanning `Fields.defs`) and
  `Fields.isUnlockedFor(name, lifetimeCash)` for anything that wants a
  yes/no answer.

### [BatterySpawner.server.lua](src/server/BatterySpawner.server.lua) — collection gated, spawning isn't
- Batteries still spawn completely normally on a locked field -- the LOOT
  is real and visible, you just can't pick it up yet, which is what makes
  the field worth working toward instead of an empty grey square. The
  Touched handler now checks the toucher's LifetimeCash against
  `field.unlockCash` before doing anything else; below it, the touch is a
  no-op -- the battery stays right where it was.
- This is enforced PER PLAYER, not per field globally -- fields are shared
  world objects that any number of players at different progress levels
  might stand on at once, so "is this field unlocked" can only ever be a
  question about the TOUCHER, never a single shared on/off switch for the
  whole field.

### [FieldLockDisplay.client.lua](src/client/FieldLockDisplay.client.lua) — new, the "why can't I collect" answer
- For Yellow/Blue/Red (Green is skipped entirely -- no lock, no sign), caches
  each Pad's real color once at startup, then every time LifetimeCash
  changes: locked -> Pad dims to flat grey + 35% transparent, its floating
  sign (cloned from the Data Center's Sign/Billboard/Title structure, new
  world geometry) lights up with "LOCKED" and "Need $X lifetime Cash (have
  $Y)"; unlocked -> Pad snaps back to its cached true color, sign turns off.
- Same per-viewer trick `DataCenterDisplay.client.lua` already used for the
  ONLINE glow: the Pad is one shared Workspace part, but a LocalScript
  setting its Color only changes what THAT player sees -- someone who's
  already unlocked Blue sees it in full color while a newer player
  standing right next to them still sees it dimmed grey.

### A real bug caught and fixed while building this: schema evolution
Adding a NEW save field (`lifetimeCash`) to an already-shipped save format
exposed a gap: `PlayerSetup.server.lua` did `cash.Value = data.lifetimeCash`
with no fallback, and an EXISTING save (saved before this field existed)
naturally doesn't have it -- `data.lifetimeCash` was `nil`, and assigning
`nil` to an `IntValue.Value` throws. Fixed two ways: `PlayerSetup.server.lua`
now falls back to `0` defensively (matching the `or 1`/`or 0` pattern
already used elsewhere for exactly this reason), AND
[PlayerData.lua](src/server/PlayerData.lua) gained `fillMissingDefaults`,
which backfills any field present in `defaultData()` but missing from a
freshly-LOADED save, so the NEXT field added later won't need this same
fix repeated by hand.

**Concept:** a save file's SHAPE is not fixed forever -- a real, live save
made under an older version of the game will keep showing up after the
game changes, and code that assumes every field it expects is always
present will eventually crash on exactly the players who've played the
longest. Treating "fields might be missing" as the normal case (one
central backfill, not a scattered `or default` at every read site) is what
makes adding save data later routine instead of risky.

**Tested:** Play mode -- and, as a bonus, DataStore API access turned out
to already be enabled for this place (confirmed live: `GetAsync` returned
a REAL save from earlier testing, `{cash=420, reserve=12640, ...}`, missing
`lifetimeCash` entirely -- exactly the old-save scenario `fillMissingDefaults`
was built for). Confirmed it loaded without error, backfilled `lifetimeCash`
to 0, and the payout loop resumed correctly from the restored reserve
(watched both Cash and LifetimeCash climb by the identical amount over
several real ticks). Verified all three locked fields' Pads read dimmed
grey with correct per-field requirement text, Green untouched. Physically
teleported the player onto a Yellow battery while locked -- confirmed
`Batteries`/`mAh` didn't change and the battery wasn't destroyed. Set
LifetimeCash to 3000 (past Yellow's $2500) and confirmed, live and
per-player: Yellow's Pad snapped back to its real color, its sign
disabled, Blue stayed locked, and a real touch on a Yellow battery now
successfully collected it. No console errors.

---

## 2026-09-12 — Progress now saves: Cash, levels, GPU rig, and power reserve

**Goal:** priority #2 on the recommended roadmap. Every stat reset to zero
the moment you rejoined -- fine for a single sitting, but it made the whole
"reach Blue, then Red" progression (and the new GPU economy) pointless
across multiple sessions. Cash, upgrade levels, unlocked slots, owned/
equipped GPUs, and the banked power reserve now survive leaving and
rejoining. Batteries/mAh currently CARRIED still reset each session, same
as always -- an in-progress collecting trip was never meant to be "progress."
Offline earnings (whether the data center keeps draining/paying while
you're away) is an explicitly separate decision, not attempted here -- the
reserve just resumes exactly where it was the instant you're back.

### [PlayerData.lua](src/server/PlayerData.lua) — new, the only script that talks to DataStores
- One `DataStore("PlayerSave_v1")`, keyed per player by `Player_<UserId>`.
- `PlayerData.load(player)` fetches (or, for a new player / a failed
  fetch, DEFAULTS) a save table and caches it -- safe to call from more
  than one script's `PlayerAdded` handler; a second caller just waits for
  the first's in-flight request instead of firing a duplicate one.
- `PlayerData.registerSaver(fn)` lets each system (PlayerSetup, Shop,
  DataCenter) contribute its own slice of the save table right before a
  save actually happens, without PlayerData needing to know what Cash,
  levels, or a GPU rig even ARE -- the same "every plugin implements one
  method" shape a plain interface would have in a language with real
  interfaces.
- Saves happen on a 120-second timer, when a player leaves, and once more
  in `game:BindToClose` (server shutdown) -- never after every single
  purchase, which would blow through DataStore's request-rate limits fast.
- Every DataStore call is wrapped in `pcall` -- a failed load falls back to
  fresh defaults (a Studio playtest with API access off still plays
  normally, just without persistence); a failed save just warns and moves
  on, rather than erroring the whole server.
- `PlayerData.onReleased(fn)` -- see below; this is the piece that took
  the most thought.

### The ordering bug this design avoids
The three systems that own live per-player state (Shop's `levels`/`rigs`,
DataCenter's `runs`) already had their own `Players.PlayerRemoving`
cleanup, nulling their tables when someone left. Naively, PlayerData's own
save-on-leave would ALSO be a `Players.PlayerRemoving` connection -- and
Roblox does not guarantee which of two connections to the same event fires
first. If a system's cleanup happened to run BEFORE PlayerData's save got
its turn, that system's registered saver would read an already-nulled
table and silently save incomplete (or crash reading nil) data -- losing
whatever changed in a player's last moments online, unpredictably, based
on script load order alone.

Fix: PlayerData owns the ONE `Players.PlayerRemoving` connection that
matters for saving, and does save -> release -> `onReleased` callbacks in
that exact order, every time, inside a single handler. Shop.server.lua and
DataCenter.server.lua no longer connect to `Players.PlayerRemoving`
directly at all -- they register their cleanup via `PlayerData.onReleased`
instead, which is guaranteed to run only after their data was already
captured into the save.

### [PlayerSetup.server.lua](src/server/PlayerSetup.server.lua), [Shop.server.lua](src/server/Shop.server.lua), [DataCenter.server.lua](src/server/DataCenter.server.lua)
- Each now calls `PlayerData.load(player)` at the top of its own
  `setupPlayer`, and initializes its live state (leaderstats.Cash,
  `levels`, the `rigs` table, `runs`) from the loaded data instead of
  always starting at defaults.
- Each registers ONE saver contributing its own fields, and (Shop and
  DataCenter) one `onReleased` cleanup callback in place of their old
  `Players.PlayerRemoving` connections.
- Shop's rig saves as a plain 4-entry array (`data.slots`, `"" `= empty)
  and a plain list (`data.storage`) -- NOT the sparse `gpus` table it uses
  live -- because DataStores handle a plain array far more predictably
  than a table with gaps in its numeric keys. Loading rebuilds the sparse
  table from the array, skipping any id the catalog no longer recognizes
  (defensive, in case a GPU is ever removed from `GPUs.lua` later).

**Concept:** a plugin-style registration pattern (`registerSaver`,
`onReleased`) instead of one big script that knows about Cash AND levels
AND GPUs AND the reserve all at once -- each system stays responsible for
its own slice, and the orchestrator (PlayerData) just calls whoever signed
up, in a guaranteed order. This is also why the earlier "ordering bug"
section matters as a lesson on its own: TWO listeners on the SAME event,
in DIFFERENT scripts, have no guaranteed relative order in Roblox --
anywhere that matters, funnel through one connection instead of two.

**Tested:** Play mode, with Studio's "Enable Studio Access to API Services"
left OFF on purpose (the default) to specifically verify the failure path:
confirmed `PlayerData.load` catches the resulting 502 and falls back to
correct defaults (`UnlockedSlots=1`, `Slot1GPU="Starter"`, `Cash=0`, empty
storage) with no crash. Bought an upgrade and confirmed normal gameplay is
completely unaffected by persistence being unavailable. Manually called
`PlayerData.save` and confirmed the matching 403 is caught and warned, not
thrown. Stopped Play mode (firing `PlayerRemoving` and `BindToClose`) and
confirmed both the leave-triggered save and the shutdown save each failed
gracefully with a warning and no server error. Real load/save ROUND-TRIP
(does data survive a real rejoin) still needs "Enable Studio Access to API
Services" turned on to verify -- noted in the README's Requirements.

---

## 2026-09-12 — GPU storage and swapping: buying never gets stuck again

**Goal:** the GPU system's biggest gap -- once every slot was full, buying
was flatly REFUSED, even with plenty of Cash, and there was no way to pull
an installed GPU back out. Fill four slots with cheap Starters and you were
locked out of the Advanced/Data Center/Neural tiers forever. This closes
that gap: every GPU you buy is now yours to keep, and moving one between a
slot and storage is free -- so upgrading is unequip the old, equip the new.

### [Shop.server.lua](src/server/Shop.server.lua) — storage + two new RemoteEvents
- Each player's rig gained a third field: `storage` -- a plain list of
  owned-but-not-installed GPU ids (duplicates allowed; two owned Basics
  with one equipped is a completely normal state).
- `BuyGPU` no longer refuses a purchase when every slot is full -- it still
  auto-installs into an empty slot if one exists, but now falls back to
  `table.insert(rig.storage, ...)` instead of returning early. Buying only
  ever fails for being unaffordable now, never for having a full rig.
- Two new RemoteEvents: `UnequipGPU(slotNumber)` moves that slot's GPU into
  storage and empties the slot; `EquipGPU(gpuId)` finds a matching id in
  storage and moves it into the first empty slot. Both are FREE (no Cash
  check) -- they're rearranging hardware already owned, not buying
  anything. A "swap" is just these two calls back to back.
- `storage` publishes as a NEW attribute, `GPUStorageJSON` --
  `HttpService:JSONEncode`d, because an attribute can only hold one simple
  value and storage's length varies. (`JSONEncode`/`JSONDecode` are pure
  local functions -- no network access or the "Allow HTTP Requests" game
  setting needed for these two, unlike `HttpService:GetAsync` etc.)

### [ShopUI.client.lua](src/client/ShopUI.client.lua) — slot rows + a Buy/Equip catalog
- The old single aggregated "Slots: X/4, Installed: ..." row is now FOUR
  per-slot rows (always built, regardless of how many are unlocked) --
  each shows Locked / Empty / "<GPU> + stats" and, when occupied, an
  Unequip button.
- Every catalog row now has TWO buttons: **Buy** (unchanged) and a new
  **Equip** that reads "Equip (17->22/s)" -- the rig's CURRENT total
  Cash/sec and what it would become, computed live, right on the button.
  That's the "before equipping, show how the total would change" preview
  -- always visible, not a hover tooltip, so it works the same on any
  input device. The button instead reads "None Stored" or "No Empty Slot"
  when equipping isn't currently possible.
- New `makeGPURow` (two stacked buttons, taller) alongside the existing
  `makeRowFrame` (one button) -- and `setBuyState` was generalized into
  `setButtonState(button, canDo, text)`, since it now sets buttons
  directly rather than assuming a row has exactly one.
- Panel height is no longer a single magic formula -- `planRowHeights`
  builds the actual list of row heights a shop will use (mixing the normal
  74px rows with the new 112px two-button GPU rows) and sums them, so the
  panel is sized exactly right instead of estimated.

### Deferred (unchanged from before, still intentional)
- **No persistence** -- a rig (slots, storage, everything) still resets on
  rejoin. Saving progress is next on the recommended roadmap, not this pass.
- **All-or-nothing power draw**, not per-GPU brownouts.
- The Data Center Shop panel is now quite tall (5 GPU types at 112px plus
  4 slot rows plus the unlock row) -- a scrollable or collapsible redesign
  would be a good follow-up UI-polish pass, not attempted here.

**Concept:** representing a variable-length list as a single JSON string
inside one attribute, because Roblox attributes can only hold ONE simple
value each (a number, a string, a color -- never an array or nested
table) -- the same kind of constraint that pushed the four battery-field
Pad names into a shared module instead of one attribute each, just solved
differently here since the LENGTH itself varies, not just the count of
named slots.

**Tested:** Play mode, all real RemoteEvents (matching exactly what each
button fires). Filled all 4 slots (Starter/Basic/Advanced/DataCenter), then
bought a 5th GPU (another Basic) with the rig completely full -- it landed
in storage (`GPUStorageJSON` -> `["Basic"]`) instead of being refused, and
Cash dropped by exactly its price. Unequipped slot 2 -- slot emptied,
storage grew to two Basics, and the Data Center's power-draw sign
correctly dropped by exactly that GPU's draw (only counting EQUIPPED GPUs,
confirmed by checking the sign read 520 mAh/s with slot 2 empty, matching
Starter+Advanced+DataCenter by hand). Equipped a Basic back from storage --
slot refilled, storage shrank back to one, sign rose to exactly 600 (+80).
Confirmed the Equip button's preview text matched hand-calculated totals
exactly in two different states (45->57 and 45->110). Read every row's
actual `Text` off the live GUI and confirmed "Owned N -- E equipped, S
stored" matched the real rig state precisely. No console errors.

---

## 2026-09-12 — Each field gets its own battery mix, not a shared falloff

**Goal:** every field picked from the SAME global rarity curve (falloff^3),
just renormalized to whatever sizes it allowed -- so Blue's mix (AAA/AA/C
renormalized from weights 27/9/3) worked out to roughly 69/23/8, nothing
like "AA is the normal battery here." Ethan wants each field to raise what
counts as a NORMAL pickup on purpose: AAA-only on Green, AA becomes routine
on Blue, C becomes routine on Red with D as a rare exciting exception --
using an explicit percentage table per field instead of one shared formula.

| Field | AAA | AA | C | D |
| --- | --: | --: | --: | --: |
| Green | 100% | -- | -- | -- |
| Yellow | 65% | 35% | -- | -- |
| Blue | 20% | 55% | 25% | -- |
| Red | 10% | 20% | 60% | 10% |

A battery's mAh and lifetime are UNCHANGED (still 500/1500/4500/13500 mAh,
60/30/15/7.5s) -- only how often each size turns up on a given field does.

### [Fields.lua](src/shared/Fields.lua) — `templateNames` (a list) → `chances` (a weighted table)
- Each field def now has `chances = { Battery_AAA = 65, Battery = 35 }`
  (etc.) instead of a bare list of allowed names. The numbers are read
  naturally as percentages here (each field's own add up to 100), but
  functionally they're just relative weights -- BatterySpawner sums
  whatever's there and rolls against the total, so they'd still work
  un-normalized.
- A size left out of a field's `chances` still can't spawn there at all --
  same "which sizes are allowed" behavior as before, just alongside an
  explicit "how often," instead of that being an accident of a shared curve.

### [BatterySpawner.server.lua](src/server/BatterySpawner.server.lua) — per-field weights, not a global one
- `templates[name]` no longer carries a `weight` -- that was the global
  falloff-based spawn odds, which no longer exist. It still carries
  `mah`/`rarity`/`lifetime`, which stay global (a AAA is worth the same and
  lives the same length everywhere).
- `buildField` now reads `def.chances` directly as each allowed size's
  weight for THAT field (with an `assert` catching a typo'd battery name in
  Fields.lua immediately, at boot, instead of that size silently never
  spawning). `pickTemplate` is otherwise the same weighted-roulette pick as
  before -- only where the weight comes from changed.
- `RARITY_FALLOFF` is still here, but now purely for mAh scaling (its
  original second job) -- the "spawn odds fall off exponentially" comment
  that described its OTHER old job is gone.

**Concept:** separating two things that used to be accidentally coupled
through one constant -- how RARE a battery is (spawn odds) and how VALUABLE
it is (mAh) -- into two independent settings. They still happen to move
together globally (mAh scaling is still exponential), but now a field's
spawn MIX is a deliberate, per-field design choice instead of a side effect
of "renormalize the global curve to whatever this field allows."

**Tested:** a 200,000-sample Monte Carlo simulation (the exact same
roulette-wheel algorithm BatterySpawner uses, run against the real
`Fields.lua` data) landed within ~0.2 percentage points of every target on
every field: Green 100% AAA; Yellow 65.0/35.0; Blue 19.9/55.2/24.9; Red
10.0/20.2/59.9/9.9. Then in Play mode, checked currently-live batteries'
`Rarity` attributes per field -- Green all AAA, Yellow mostly AAA with some
AA, Blue mostly AA with some AAA and C, Red spread across AAA/AA/C with no D
in that small snapshot -- consistent with the odds AND with rarer sizes
(shorter-lived) being under-represented in any single live snapshot, same
effect Ethan called out in his own notes. No console errors, including no
assertion failures (which would have fired immediately at server boot if
any `chances` name didn't match a real battery template).

---

## 2026-09-12 — Cash upgrade replaced with real GPU hardware (first pass)

**Goal:** the old Cash-per-second upgrade was one number that went up
forever. Ethan wants actual hardware instead: 1-4 equipment SLOTS, filled
from a GPU catalog where a better card pays more but also draws more
power -- so racking up GPUs is a real tradeoff against your power reserve,
not a free stack. This is an explicitly first-pass implementation (chosen
scope: "core mechanic first" over a full swap/storage UI) -- see "Deferred"
below for what's intentionally left out.

### [GPUs.lua](src/shared/GPUs.lua) — new shared module, the GPU catalog
- 5 GPUs, cheapest first: Starter ($100, 5 Cash/s, 40 mAh/s draw), Basic AI
  ($1500, 12, 80), Advanced AI ($12500, 28, 160), Data Center ($100000, 65,
  320), Neural Accelerator ($750000, 150, 640). Each tier roughly DOUBLES
  the power draw of the last but pays slightly MORE than double the Cash/s
  -- "one better card beats two of the last one, by a little."
- `GPUs.MAX_SLOTS = 4`, `GPUs.SLOT_PRICES = {0, 500, 10000, 100000}` (slot 1
  free), `GPUs.STARTER_ID` (the free GPU every player starts with),
  `GPUs.get(id)` to look a catalog entry up by its stored id.

### [Upgrades.lua](src/shared/Upgrades.lua) — Cash removed, Efficiency renamed
- Deleted the `Cash` def and `Upgrades.powerNeeded` entirely -- Cash/sec is
  hardware now, not a level.
- `Efficiency`'s display name changed to "Power Conversion" (Ethan's
  request) -- distinct from a GPU's own cash-per-mAh efficiency. Same id,
  same numbers, only the label changed.
- `Upgrades.shops`'s Data Center Shop entry is now `{ ids = {"Efficiency"},
  gpuSection = true }` -- that flag tells ShopUI to build the GPU section
  there without Upgrades.lua needing to know anything about GPUs itself.

### [Shop.server.lua](src/server/Shop.server.lua) — owns the GPU rig now too
- New per-player `rigs` table: `{ unlockedSlots, gpus = {[slot] = gpuId} }`.
  Every player starts with 1 unlocked slot holding a free Starter GPU --
  the ONLY GPU anyone gets without paying.
- Published as attributes (`UnlockedSlots`, `Slot1GPU`..`Slot4GPU`, empty
  string = empty slot) -- same decoupled pattern as upgrade levels, so
  DataCenter.server.lua and the client never touch this script's tables.
- Two new RemoteEvents: `BuyGPUSlot` (unlock the next slot at its price) and
  `BuyGPU` (buy a catalog GPU into the first empty unlocked slot). Both
  validate everything server-side -- real id, affordable, room to install.

### [DataCenter.server.lua](src/server/DataCenter.server.lua) — payout from the whole rig
- `rigTotals(player)` sums installed GPUs' `cashPerSec`/`powerDraw` straight
  off the attributes Shop.server.lua publishes. The payout tick and the
  "seconds left" display both switched from `Upgrades.powerNeeded(CashLevel)`
  to this sum.
- Kept the SAME all-or-nothing-per-second model the game already had: if
  the reserve covers the WHOLE rig's draw, everything pays out and drains;
  if not, the whole rig idles that tick. (Noted as a candidate for a more
  granular per-GPU "brownout" model later -- not needed for this pass.)

### [DataCenterDisplay.client.lua](src/client/DataCenterDisplay.client.lua) & [ShopUI.client.lua](src/client/ShopUI.client.lua)
- The sign's power-draw readout now sums installed GPUs client-side the
  same way, listening for changes on `UnlockedSlots` and every `Slot<N>GPU`.
- ShopUI's Data Center Shop panel gained a GPU section: one row to unlock
  the next slot (shows `X / 4 unlocked` plus the names of installed GPUs),
  and one row per catalog GPU (price, Cash/sec, power draw) with a Buy
  button that reads "No Empty Slot" when the rig is full or "Buy $price"
  otherwise. Row-building was factored into a shared `makeRowFrame` helper
  so upgrade rows, the slot row, and GPU rows all use one code path instead
  of three copies of the same Frame/TextLabel/TextButton setup.

### Deferred (by design -- this was the chosen scope for this pass)
- **No swapping or storage.** A bought GPU auto-installs into the first
  empty slot; there's no way yet to pull an installed GPU back out or bank
  a spare. Buying with every slot full is just refused.
- **No persistence.** Like every other stat in this game, a player's rig
  resets on rejoin -- saving across sessions (mentioned in Ethan's own
  design notes as eventually necessary for this progression) is a separate,
  later piece of work.
- **All-or-nothing power**, not per-GPU brownouts (see DataCenter.server.lua
  section above).

**Concept:** replacing a single scalar (a "level" that only goes up) with a
small INVENTORY -- a fixed number of slots, each holding one item from a
catalog. The same server-owns-state/publish-as-attributes pattern the level
upgrades already used extends cleanly to it: the server never has to trust
what a client claims to have installed, because the client never has write
access to anything but a purchase REQUEST.

**Tested:** Play mode, all server-side. Confirmed a fresh player starts with
`UnlockedSlots=1`, `Slot1GPU="Starter"`. Dumped 500 mAh -- reserve/power
math matched hand-calculated numbers exactly every step (12s → drained
40/tick, landed on 3s left after 9 ticks paying $45 total). Bought slot 2
($500) and a Basic AI GPU ($1500) via the real RemoteEvents (same calls the
Buy buttons make) -- Cash dropped exactly $2000, `Slot2GPU="Basic"`, the
Data Center's power-draw sign updated to "120 mAh/s" (40+80), and a second
dump showed the COMBINED payout (2 ticks × $17 = $34) and drain (120/tick)
landing exactly on the hand-calculated numbers. Filled all 4 slots (Cash
math exact: 500000 → 277500 across 4 purchases) and confirmed a 5th GPU
purchase was silently refused -- slot 4 kept its GPU, no cash lost, no
error. Verified the ShopUI panel text and every Buy button's label/state
("All Slots Unlocked", "No Empty Slot") matched the underlying attributes
throughout. No console errors.

---

## 2026-09-12 — One Upgrade Shop split into two: Player Shop and Data Center Shop

**Goal:** all four upgrades lived on one pad. Ethan wants them separated by
WHO they benefit -- Speed and Capacity make the PLAYER better at collecting;
Efficiency and Cash make the DATA CENTER better at cashing out -- as two
distinct platforms.

### World geometry (built live in Studio, not tracked in this repo)
- Cloned the existing `Workspace.Shop` model (Pad + floating Sign +
  Billboard) to get a second platform with identical structure and text
  styling, rather than rebuilding it from scratch.
- Renamed the original to `Shop_Player`, kept its blue Pad and position
  (6, 0.5, 75), relabeled its sign "PLAYER SHOP".
- The clone became `Shop_DataCenter`: purple Pad
  (`Color3.fromRGB(150, 90, 200)`) at (28, 0.5, 75) -- a 10-stud gap from
  Shop_Player's edge -- sign relabeled "DATA CENTER SHOP". Verified with the
  same bounding-box overlap check used for the four fields: no overlaps
  with each other, the Spawn pad, the Data Center, or any field.

### [Upgrades.lua](src/shared/Upgrades.lua) — new `Upgrades.shops` grouping
- Added `Upgrades.shops`: an ordered list of `{ title, ids }`, one entry per
  physical shop platform -- `PLAYER SHOP` = `{Speed, Capacity}`,
  `DATA CENTER SHOP` = `{Efficiency, Cash}`. This is the single source of
  truth for which upgrade lives on which platform.
- `Upgrades.order` (used nowhere else) is now DERIVED from `Upgrades.shops`
  by concatenation, instead of being listed separately -- so the grouping
  and the flat list can't quietly drift apart.

### [ShopUI.client.lua](src/client/ShopUI.client.lua) — one panel per shop
- The whole panel-building block (title, Cash line, rows, Buy buttons,
  refresh) is now `buildShopPanel(shopDef, padName)`, called once per entry
  in `Upgrades.shops` -- each call makes its OWN `ScreenGui` (named
  `ShopUI_Shop_Player` / `ShopUI_Shop_DataCenter`) sized to however many
  rows that shop actually has (`94 + 84 * #shopDef.ids`), instead of one
  hardcoded 4-row panel.
- `SHOP_PAD_NAMES = { "Shop_Player", "Shop_DataCenter" }` maps each
  `Upgrades.shops` entry (by matching index) to its Workspace pad name --
  world-geometry names stay in the client script that needs them, same as
  before the split, not inside the shared `Upgrades` module.
- The show/hide `RunService.Heartbeat` loop now runs the SAME
  footprint-bounding-box check (yesterday's Shop fix) once per panel, so
  standing on one shop's pad shows only that panel -- never both, never
  neither incorrectly.
- No change to `Shop.server.lua`: purchases were always validated purely by
  upgrade id, never by which pad the request came from, so the server-side
  half of the shop needed zero edits.

**Concept:** turning a single hardcoded thing (one panel, four rows, one
pad) into a small function parameterized over a LIST of configs
(`Upgrades.shops`), called once per entry -- adding a third shop later would
mean adding one entry to that list and one name to `SHOP_PAD_NAMES`, not
copy-pasting a whole panel's worth of GUI code again.

**Tested:** Play mode. Teleported the player onto `Shop_Player` -- confirmed
only `ShopUI_Shop_Player` enabled, showing exactly Walk Speed and Capacity;
teleported onto `Shop_DataCenter` -- confirmed the SWAP (Player panel off,
Data Center panel on) showing exactly Efficiency and Cash. Gave the player
1000 Cash and fired the real `BuyUpgrade` RemoteEvent for Speed the same
way the Buy button does -- `SpeedLevel` went 0 → 1, Cash dropped 1000 → 950
(the level-0 cost), and the Player Shop panel's row text refreshed live to
show the new level and effect. No console errors (only the expected
server-side purchase print).

---

## 2026-09-11 — Instant field speed switching; Shop no longer opens off-pad

Two separate responsiveness bugs, both about checking the WRONG thing (or
checking it too rarely) to detect "am I actually on this platform."

### [PlayerSpeed.server.lua](src/server/PlayerSpeed.server.lua) — polling was the delay
- **Bug:** the on/off-field check ran on a `task.wait(0.2)` loop -- up to a
  fifth of a second between actually crossing a field's edge and
  `Humanoid.WalkSpeed` catching up. Noticeable as a "lag" right at the
  boundary.
- **Fix:** replaced the timed loop with `RunService.Heartbeat:Connect(...)`
  -- the SAME per-frame-check pattern `ShopUI.client.lua` already used for
  its own pad. Now the check runs every server frame; `appliedSpeed[player]`
  still guards against writing `WalkSpeed` when nothing actually changed, so
  this isn't doing more real work most frames -- just checking more often.

### [ShopUI.client.lua](src/client/ShopUI.client.lua) — wrong shape of check
- **Bug:** `(root.Position - shopPad.Position).Magnitude <= 12` is a
  12-stud-radius CIRCLE around the pad's centre. `Shop.Pad` is a 12x12
  SQUARE (half-width 6) -- so standing up to ~6 studs past any edge (still
  inside the circle, outside the square) opened the panel while off the
  platform entirely.
- **Fix:** replaced the radius check with `isOnPad(position)` -- the exact
  same 2-D bounding-box test `Fields.lua`/`BatterySpawner` use for the
  battery fields, read live off `shopPad.Size`/`Position`. Only opens once
  you're actually standing on the pad's real footprint.

**Concept:** a circle and a square that happen to be roughly the same size
are NOT the same shape -- a radius check silently over- or under-covers a
non-circular area depending on where you approach from. When something
already has a real geometric footprint (a `Part`'s `Size`), test against
THAT footprint directly instead of approximating it with a magnitude
check. Also: a periodic poll trades responsiveness for a (here,
unnecessary) cut in how often a cheap check runs -- when the check is cheap
and the guard against redundant writes already exists, per-frame is free.

**Tested:** Play mode. Speed: teleported onto Field_Green and sampled
`Humanoid.WalkSpeed` frame-by-frame -- caught up within 1 extra frame
(~16-33ms), down from up to 200ms. Shop: teleported the player 9 studs off
the pad's centre (inside the OLD 12-stud radius, outside the pad's real
6-stud half-width) and confirmed `ShopUI.Enabled` stayed `false`; teleported
onto the pad and confirmed it flipped `true`. No console errors.

---

## 2026-09-11 — A field's population never drops below half its cap

**Goal:** yesterday's random refill let a field's count drift anywhere from
1 up to its cap -- Ethan wants a floor: never below half the cap (rounded
up), even though the climb from there back up to the cap should stay random.

### [BatterySpawner.server.lua](src/server/BatterySpawner.server.lua)
- Added `MIN_POPULATION_RATIO = 0.5` and, per field, `minCount =
  math.ceil(count * MIN_POPULATION_RATIO)` -- rounded UP so an odd cap (Red's
  15) still gets a real floor (8), not a fraction. Green's cap of 1 gives a
  floor of 1 too -- there's no room for "half" below the only possible state.
- `removeBattery()` now checks `field.liveCount < field.minCount`
  immediately after decrementing, and spawns a replacement RIGHT THERE if
  so -- no waiting for `startFieldLoop`'s next check or its `SPAWN_CHANCE`
  roll. The floor is enforced the instant it would be crossed, not
  eventually; only the climb from floor to cap stays left to chance.
- `startFieldLoop` is unchanged -- it still only rolls the dice for growth
  ABOVE the floor, since removeBattery already guarantees the field never
  falls under it.
- The random head-start range on server boot moved from
  `math.random(1, field.count)` to `math.random(field.minCount, field.count)`
  -- a field can't even start below its own floor.

**Concept:** splitting one number ("how full should this field be") into
two thresholds with different enforcement styles -- a HARD floor enforced
synchronously the moment it would be crossed, and a SOFT ceiling approached
only probabilistically. Same idea as a thermostat: heat kicks on
immediately at the low setpoint, but doesn't have to run constantly once
above it.

**Tested:** Play mode -- confirmed the head-start already respects both
bounds (Green 1, Yellow 4, Blue 7, Red 14 -- all within their floor..cap
ranges). Then, using REAL collection (teleporting the player's actual
character onto each battery so its Hitbox.Touched fires genuinely, not a
bypassed Destroy), collected Field_Blue (cap 8, floor 4) down repeatedly:
8 → 7 → 6 → 5 → 4 → 4 → 4 -- it stopped descending exactly at the floor,
with each further collection instantly backfilled. Also collected
Field_Green's only battery (cap 1, floor 1) and confirmed it came right
back. No console errors.

---

## 2026-09-11 — A field's count is now a CAP, not a fixed number it's always at

**Goal:** every field always held exactly its `count` -- the instant a
battery was collected or expired, this script immediately spawned a
replacement on the same field. Ethan wants that number to mean "the most
this field can ever hold," with the ACTUAL number drifting randomly at or
below it -- a field doesn't have to be full.

### The mechanic changed, not the numbers
- **Before:** `removeBattery(delay)` always queued its own replacement via
  `task.delay(delay, spawnBattery)` -- collected or expired, a fresh battery
  was guaranteed, just after a short pause. A field was ALWAYS at `count`
  after that pause.
- **Now:** `removeBattery()` just destroys the battery and decrements the
  field's `liveCount` -- no replacement queued. A new per-field loop
  (`startFieldLoop`) is what independently decides whether to add one:
  every `SPAWN_CHECK_INTERVAL` (2s), if `liveCount < count`, it rolls
  `SPAWN_CHANCE` (50%) odds of spawning one more. Most checks either find
  the field already full (nothing to do) or fail the roll (nothing happens
  this time) -- so the population drifts, rather than snapping to the cap.

### [BatterySpawner.server.lua](src/server/BatterySpawner.server.lua)
- Added `field.liveCount` (how many of this field's batteries exist right
  now) alongside the existing `field.count` (the cap).
- `spawnBattery` increments `liveCount`; `removeBattery` (now argument-less
  -- there's no "respawn after N seconds" left to parameterize) decrements it.
- Added `startFieldLoop(field)`: the probabilistic refill loop described
  above, one per field, started once at boot.
- Startup no longer fills every field straight to `count` -- each field now
  gets a random HEAD START between 1 and its cap
  (`math.random(1, field.count)`), then `startFieldLoop` takes over growing
  or draining it from there. `RESPAWN_DELAY` is gone; nothing reads it
  anymore.

**Concept:** the difference between an ALWAYS-triggered follow-up action
("when X happens, Y always happens next") and an INDEPENDENT periodic check
("every so often, maybe do Y if some condition holds"). The second is what
turns a fixed number into a genuine cap with real variation under it --
similar to how a slot machine or a loot table rolls odds on a timer rather
than guaranteeing an outcome after every event.

**Tested:** Play mode, restarted twice -- confirmed the head-start count
actually varies (one run: Green 1 / Yellow 4 / Blue 8 / Red 15; next run:
Green 1 / Yellow 4 / Blue 4 / Red 5), not always maxed. Sampled Field_Blue's
live count every 2s for 16s with no player interaction and watched it drift
between 7 and 8 purely from natural expiry + refill rolls -- never exceeding
its cap of 8. No console errors.

---

## 2026-09-11 — Every field's battery count is now an explicit, adjustable number

**Goal:** yesterday's `count` override only existed on Yellow and Blue --
Green and Red were still silently falling through to the area-based
formula. Ethan wants ALL FOUR fields' battery counts adjustable in the same
obvious place, not "two are a number you can edit, two are a formula you'd
have to go find and understand first."

### [Fields.lua](src/shared/Fields.lua) — every field gets a `count`
- Added `count = 1` to `Field_Green` and `count = 15` to `Field_Red` --
  the exact numbers the area formula already produced for them, just
  written down explicitly now instead of computed silently.
- The formula itself (in BatterySpawner.server.lua) is untouched and still
  there as a fallback for a field with no `count` set -- so a brand new
  fifth field, added later with no `count`, would still get a sensible
  default instead of erroring.

**Concept:** the difference between a computed default and a written-down
config value. Both produce the same number here, but one is discoverable
(open Fields.lua, see `count = 1`, change it) and the other isn't (you'd
have to find BatterySpawner.server.lua's `BATTERIES_PER_SQUARE_STUD` and do
the math yourself to know what a field currently holds, let alone change
it). Making a value EXPLICIT, even when a formula could derive the same
number, is often the more maintainable choice once a human needs to tune it
by hand.

**Tested:** Play mode -- `CollectionService:GetTagged("BatteryPickup")`
counts per field unchanged from before: Green 1, Yellow 4, Blue 8, Red 15
(28 total). No console errors.

---

## 2026-09-11 — Yellow and Blue fields: pinned battery counts (4 and 8)

**Goal:** yesterday's density formula gave Field_Yellow and Field_Blue 1 and
4 batteries -- technically consistent with the original field's density, but
Ethan wants those two busier than their small footprints imply. Let a field
override the formula with an exact number instead of always deriving one.

### [Fields.lua](src/shared/Fields.lua) — optional `count` per field
- Added `count = 4` to `Field_Yellow` and `count = 8` to `Field_Blue`.
  `Field_Green` and `Field_Red` have no `count` -- they still fall through
  to the area-based formula (which happens to land on 1 and 15).

### [BatterySpawner.server.lua](src/server/BatterySpawner.server.lua) — one-line change
- `buildField` now does `local count = def.count or <the formula>` -- an
  explicit number in Fields.lua wins; otherwise nothing changed from
  yesterday.

**Concept:** an optional override sitting ALONGSIDE a computed default
(`X or fallback`), rather than replacing the formula outright -- Green and
Red keep benefiting from "resize the Pad and the count follows," while
Yellow and Blue get an exact, deliberately-chosen number. Same idea as a
function argument having a default value.

**Tested:** Play mode -- `CollectionService:GetTagged("BatteryPickup")`
sorted by field: Green 1, Yellow 4, Blue 8, Red 15 (28 total). No console errors.

---

## 2026-09-11 — One field split into four, gated by battery size

**Goal:** turn the single field into a size/color/rarity progression: four
separate raised platforms, each bigger than the last, each unlocking one
more (rarer, more valuable) battery size. Reaching a bigger field is now
what gets you access to the sizes above AAA.

The final field (`Field_Red`) is literally the field this game already had
-- same 150x150 size, same position, same 15 batteries, same odds -- just
recolored. The other three are progressively smaller/halved slices of the
same idea, doubling up to it: Green 18.75 → Yellow 37.5 → Blue 75 → Red 150.

| Field | Size | Color | Allowed sizes | Battery count |
| --- | --- | --- | --- | --- |
| `Field_Green` | 18.75x18.75 | green | AAA | 1 |
| `Field_Yellow` | 37.5x37.5 | yellow | AAA, AA | 1 |
| `Field_Blue` | 75x75 | blue | AAA, AA, C | 4 |
| `Field_Red` | 150x150 | red | AAA, AA, C, D | 15 |

Battery counts aren't arbitrary -- they come from the SAME density the
original field used (120x120 spawn square / 15 batteries = 960 sq studs per
battery), just applied to each field's own (much smaller, for the early
ones) spawn area, rounded to the nearest whole battery with a floor of 1.
That's also why Field_Red's count comes back out to exactly 15 -- it's the
same area, so the same formula reproduces the same number.

### World geometry (built live in Studio, not tracked in this repo)
- Renamed the existing `Workspace.Field` to `Field_Red` and recolored its
  Pad red (`Color3.fromRGB(170, 50, 50)`) -- size and position untouched.
- Added `Field_Green`, `Field_Yellow`, `Field_Blue` -- same Model+Pad
  convention as every other platform, laid out in a row east of Field_Red
  (X 89.375 / 127.5 / 193.75, all at Z = -21) with 10-stud gaps on every
  side. Verified with a script that checks every pair of the four fields
  AND the Spawn/DataCenter/Shop pads for bounding-box overlap -- none found.

### [Fields.lua](src/shared/Fields.lua) — new shared module
- The single source of truth for the four fields' Workspace NAMES and which
  battery template names each allows (`Fields.defs`), plus
  `Fields.isOnAnyField(position)` -- a bounding-box test against all four
  Pads' live Size/Position. Both `BatterySpawner` and `PlayerSpeed` read
  this instead of duplicating field logic -- the same "one file owns the
  numbers" pattern `Upgrades.lua` already uses for the shop.

### [BatterySpawner.server.lua](src/server/BatterySpawner.server.lua) — rewritten around N fields
- `templates` is now keyed by name (not a flat list) so a field can pick out
  just the sizes it allows. Global `weight`/`mah`/`rarity`/`lifetime` per
  size are unchanged -- computed once, the same regardless of field.
- `buildField(def)` turns one `Fields.defs` entry into a spawn-ready field:
  resolves its Pad, computes its own inset spawn square
  (`pad.Size.X * 0.8`) and battery count from the Pad's ACTUAL size, and
  re-sums weight across only its allowed sizes so picking stays correctly
  biased among them.
- `spawnBattery`/`randomCenterPosition`/`pickTemplate` all now take a
  `field` argument instead of reading module-level globals -- a collected
  or expired battery respawns on the SAME field it came from.
- The single `AREA_CENTER`/`AREA_SIZE`/`FIELD_TOP`/`BATTERY_COUNT` config
  constants are gone, replaced by `SPAWN_MARGIN_RATIO` (0.8) and
  `BATTERIES_PER_SQUARE_STUD` (960) -- two numbers that apply to every
  field uniformly instead of one field's worth of hardcoded values.

### [PlayerSpeed.server.lua](src/server/PlayerSpeed.server.lua) — field check delegated
- Replaced the single-Pad `isOnField` with `Fields.isOnAnyField` -- TRUE
  speed now applies on ANY of the four fields, not just one. Everything
  else (NORMAL speed off-field, the 0.2s poll, only writing WalkSpeed on
  change) is unchanged from yesterday's split.

**Concept:** pulling logic that used to live in ONE script (BatterySpawner)
but was needed by a SECOND script (PlayerSpeed) out into a shared module --
`Fields.lua` -- rather than copy-pasting the bounding-box test into both.
Same idea as `Upgrades.lua`: config and shared math belong in ONE place both
sides `require`, not duplicated and hoping they stay in sync. Also: deriving
a count from a formula (`area / density`) instead of hardcoding four
separate numbers, so the relationship between a field's size and how many
batteries it holds is documented IN the code, not just in this changelog
entry.

**Tested:** Play mode -- checked `CollectionService:GetTagged("BatteryPickup")`
against each field's bounding box: Green 1 (AAA), Yellow 1 (AA), Blue 4 (all
AAA that run -- random, but never anything above C), Red 15 (mix up through
C, 21 total across all four) -- every battery landed inside the field it was
supposed to, with only the sizes that field allows. Teleported a player to
the center of all four fields and confirmed WalkSpeed = 4 (level-0 true
speed) on every one, and 16 (normal) well off all of them. No console errors.

---

## 2026-09-11 — Two speeds: flat NORMAL everywhere, upgraded TRUE only on the field

**Goal:** the Speed upgrade was affecting WalkSpeed everywhere, all the time
-- including on the walk to the Data Center and Shop, which are no longer
even part of the field. Split it into two speeds: a flat, constant NORMAL
speed (Roblox's own default, 16 studs/sec) that applies everywhere and is
NEVER touched by the Speed upgrade, and a TRUE speed -- exactly what the
Speed upgrade always computed -- that only takes effect while standing on
`Workspace.Field.Pad`. True speed at level 0 is unchanged (still 4, "a slow
trudge").

### [PlayerSpeed.server.lua](src/server/PlayerSpeed.server.lua) — rewritten around a zone check
- Added `isOnField(position)`: a 2-D bounding-box test against the live
  `Field.Pad` instance's `Size`/`Position` -- the exact same kind of check
  BatterySpawner's `AREA_SIZE` assert does, just reading the Pad directly
  instead of a hardcoded number, so if the Pad ever moves or resizes this
  keeps working with no code change.
- `applySpeed` now picks `trueSpeedForLevel(SpeedLevel)` when `isOnField(...)`
  is true, else the flat `NORMAL_WALKSPEED = 16` -- and only WRITES
  `humanoid.WalkSpeed` when that target actually differs from what was last
  set (tracked in `appliedSpeed[player]`), so a stationary player on or off
  the field isn't getting redundant writes every check.
- Added a `task.spawn` loop that calls `applySpeed` for every player every
  `CHECK_INTERVAL` (0.2s) -- this is what actually detects "walked onto/off
  the field," since nothing else was pushing a per-frame position check
  before.
- `StarterPlayer.CharacterWalkSpeed` now starts characters at
  `NORMAL_WALKSPEED` (they spawn on `Workspace.SpawnLocation`, off the
  field) instead of the old level-0 TRUE speed.

### [Upgrades.lua](src/shared/Upgrades.lua) — doc comment only
- Noted on the `Speed` def that it's a TRUE-speed effect, on-field only --
  the numbers (`base = 4`, `perLevel = 1.5`) didn't change.

**Concept:** polling a cheap condition (a bounding-box test) on an interval
instead of every frame, and writing to a replicated property
(`Humanoid.WalkSpeed`, which every client watching this character receives)
only when its value actually changes -- the same "don't do work, or send
data, that wouldn't change anything" idea as `DataCenterSecondsLeft` only
publishing when the reserve changes.

**Tested:** Play mode, driving a player's `HumanoidRootPart` around via
`execute_luau` -- confirmed 16 WalkSpeed at spawn (off-field), 4 the instant
they're teleported onto the field (level-0 true speed), 8.5 on-field after
setting `SpeedLevel` to 3 (`4 + 3*1.5`, matching `Upgrades.effect` exactly),
and back to flat 16 immediately on teleporting off-field again at that same
level -- the upgrade had zero effect there. No console errors.

---

## 2026-09-11 — Spawn, Data Center, and Shop pads moved off the field

**Goal:** the field platform added earlier today was built centered on top of
where the Spawn pad, `DataCenter.Pad`, and `Shop.Pad` already sat, so all
three were physically overlapping the green field. Move them clear of it so
the field reads as its own space and nothing sits on top of anything else.

### World geometry only (built live in Studio, not tracked in this repo)
- `Workspace.DataCenter` and `Workspace.Shop` — every part in each model
  (Pad + floating Sign) shifted by the same `+78` on Z, so the Sign keeps its
  exact offset above its Pad. New pad centers: DataCenter (-19, 0.5, 75),
  Shop (6, 0.5, 75) -- both were at Z = -3.
- `Workspace.SpawnLocation` moved to (-38, 0.25, 75), clear of DataCenter's
  new footprint too.
- All three now sit in a row just south of `Workspace.Field.Pad` (whose
  footprint is X -80..70, Z -96..54), each with a 13+ stud gap to the field's
  edge -- verified in Studio by comparing each pad's world bounding box
  against the field's, not eyeballed.

No `src/` changes: nothing in the code hardcodes these instances' positions
(`DataCenter.server.lua`, `ShopUI.client.lua`, etc. all just do
`workspace:WaitForChild("DataCenter")` and work off whatever `.Pad` they
find), so relocating them needed zero script edits.

**Tested:** Play mode -- player spawns cleanly on the relocated Spawn pad,
batteries still fill the field, no console errors.

---

## 2026-09-11 — Batteries only spawn on a real field now (a raised platform)

**Goal:** batteries were spawning over a 120x120 square of the bare grey
baseplate, floating over whatever happened to be there. Give them an actual
place to live -- a raised platform like the Data Center's and Shop's pads,
just much bigger, sized to fit and space out all the batteries -- and make it
physically impossible to spawn one off of it.

### World geometry (built live in Studio, not tracked in this repo)
- New `Workspace.Field` model: a `Pad` part, 150 x 1 x 150 studs, green
  (`Color3.fromRGB(58, 125, 68)`) to read as "the field," centered at
  (-5, 0.5, -21) so its top sits flush at Y = 1 -- same convention as
  `DataCenter.Pad` and `Shop.Pad` (both 1 stud thick, resting on the
  baseplate). `PrimaryPart` set to `Pad`, matching those two models.
- 150x150 gives the existing 120x120 spawn square a 15-stud margin on every
  side, so batteries never spawn at the very edge.

### [BatterySpawner.server.lua](src/server/BatterySpawner.server.lua)
- Added `FIELD_TOP = 1` -- the world Y of the Field pad's top surface -- and
  changed `randomCenterPosition` to hover batteries at
  `FIELD_TOP + BASE_HOVER + height/2` instead of `BASE_HOVER + height/2`.
  Before, `BASE_HOVER` was measured from Y = 0 (the bare baseplate); now it's
  measured from the platform's own surface, so batteries sit just above the
  field no matter where that field is in the world.
- Added a startup `assert` comparing `AREA_SIZE` against
  `Workspace.Field.Pad.Size` -- if anyone ever shrinks the platform or grows
  the spawn square past it, the game fails loudly at boot instead of quietly
  spawning batteries off the edge.
- `BATTERY_COUNT` (15) and `AREA_SIZE` (120x120) unchanged -- the existing
  spread was already generous (~960 sq. studs per battery); only the platform
  underneath it changed.

**Concept:** measuring a position **relative to a reference surface**
(`FIELD_TOP + BASE_HOVER`) instead of an absolute world coordinate, so moving
or resizing the platform later doesn't require touching the hover math. Also:
an `assert` as a cheap, permanent guardrail against a future edit silently
breaking an invariant (here, "batteries stay on the platform").

**Tested:** Play mode in Studio, camera positioned above the field -- all 15
batteries spawn spread across the green platform with margin on every side,
the player's spawn point sits on it too, and the console printed no errors
(the assert didn't trip).

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

## 2026-09-12 — Data Center Shop panel scrolls instead of running off-screen

**What changed:** `ShopUI.client.lua`'s shop panel used to size itself to
fit every single row it built, with no limit. The Data Center Shop's panel
(Efficiency upgrade + GPU slot-unlock row + 4 slot rows + 5 GPU catalog
rows) added up to way more than a normal screen's height, so the bottom
rows (the pricier GPUs) were literally off-screen and unreachable. Now a
panel's height is capped at 560px; the title and Cash line always stay
visible at the top, and everything below them (the upgrade/slot/GPU rows)
sits in a `ScrollingFrame` you can scroll with the mouse wheel. The Player
Shop's panel (just 2 rows) never gets close to the cap, so it looks and
behaves exactly like before.

**Why:** Ethan couldn't see or reach all the Data Center Shop's options —
the panel just cut off partway down the GPU catalog.

**Files:** `src/client/ShopUI.client.lua`

**Concept taught:** a `ScrollingFrame` is a container that clips its
children to its own size and lets you scroll through content taller than
that -- paired with `AutomaticCanvasSize`, it grows its scrollable area on
its own to match however tall its `UIListLayout`'d children add up to, so
you never have to compute that by hand.

**How tested:** live in the already-open Studio session (Roblox Studio MCP)
-- started Play, teleported the character onto the Data Center Shop's pad,
screenshotted the panel (title/Cash/first few rows visible, a scrollbar on
the right, more rows implied below), then scrolled the mouse wheel down and
screenshotted again to confirm every GPU catalog row down to the $100,000
Data Center GPU is reachable. Stopped Play afterward.
