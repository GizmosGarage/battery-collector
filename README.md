# Battery Collector

A Roblox game, and Ethan's project for **learning software development from
scratch** — every change is made one small step at a time, explained as it
happens, so the "why" sticks, not just the "what."

Players collect batteries, deposit them to power an AI data center, and
spend its earnings on collection upgrades, GPUs, and additional space.
Better fields unlock through lifetime earnings. Cash, upgrades, GPU
equipment, and deposited power persist between sessions; carried batteries
do not. Buying space is the only way to get more equipment slots, and is
itself two independent purchases at the Data Center Shop: buy the next
physical Server_Rack (+4 slots, capped by the current floor), or upgrade
the floor itself (room for more racks, how many varies by tier — see
`GPUs.floorTiers` — without buying them). The starter floor deliberately
caps out at just 4 racks (one row), so a new player hits that wall fast
and has to buy into the floor to keep growing. Every slot in an owned
rack comes free with it. The GPU Shop only sells into storage;
installing, moving, or removing hardware all happen by walking up to a
specific Server_Rack and picking from a panel of what's installed there
and what's in storage, and equipped GPUs show up physically there too, one
card per occupied slot.

The status panel shows bag fullness, current income, remaining power time,
and progress toward the next field.

## Working agreement (read this first, human or AI)

- **Explain everything simply.** Ethan is building software literacy through
  this project. Every change — in chat *and* in code comments — should teach
  the underlying concept, not just state what the code does. Assume no prior
  programming background; define terms the first time they come up.
- **`src/` is the source of truth, and every change gets committed and pushed
  to GitHub automatically** once it's built and tested — no need to ask first.
  Use [GizmosGarage/battery-collector](https://github.com/GizmosGarage/battery-collector),
  branch `main`. Commit only files belonging to the change. Write a short,
  specific subject describing the result, with a brief body explaining why
  and how it was verified; include important limitations or learning points
  when relevant. No attribution lines in commit messages.
- **To understand the current game, read this README and the `src/` files
  directly.** Keep this README current when behavior, setup, or working
  instructions change; use Git history to understand past changes.

## Folder layout

```
Battery Collector/
├── default.project.json   Rojo's folder-to-service map
├── .gitignore              files excluded from Git
├── README.md               this file
├── src/                    the live source code — edit these files
│   ├── server/             → ServerScriptService
│   │   ├── PlayerData.lua              saves and loads progress
│   │   ├── PlayerSetup.server.lua      initializes player stats
│   │   ├── BatterySpawner.server.lua   spawns batteries and handles collection
│   │   ├── PlayerSpeed.server.lua      applies movement speed
│   │   ├── DataCenter.server.lua       consumes power and pays Cash
│   │   ├── Shop.server.lua             validates purchases and manages equipment
│   │   └── RackNumbering.server.lua    stamps each Server_Rack's permanent number
│   ├── client/             → StarterPlayer > StarterPlayerScripts
│   │   ├── BatterySpin.client.lua        battery animation
│   │   ├── BatteryGlow.client.lua        rarity effects
│   │   ├── BatteryCollision.client.lua   lets players run straight through batteries
│   │   ├── DataCenterDisplay.client.lua  personal data center status display
│   │   ├── FieldLockDisplay.client.lua   personal field lock displays
│   │   ├── StatusPanel.client.lua        always-visible gameplay status
│   │   ├── GPURackDisplay.client.lua     shows equipped GPUs on the Server_Racks
│   │   ├── RackShopUI.client.lua         equip/unequip GPUs at a specific rack
│   │   └── ShopUI.client.lua             shop panels (GPU Shop sells to storage only;
│   │                                        Data Center Shop only expands space)
│   └── shared/             → ReplicatedStorage
│       ├── Upgrades.lua    upgrade costs, effects, and shop definitions
│       ├── GPUs.lua        GPU catalog, space tiers, and output calculations
│       └── Fields.lua      field names, spawn mixes, and unlock requirements
├── Models/                 battery reference art
└── Prompts/                model and image generation prompts
```

### How filenames map to Roblox

| File ending      | Becomes in Roblox |
| ---------------- | ----------------- |
| `.server.lua`    | `Script` (runs on the server) |
| `.client.lua`    | `LocalScript` (runs on each player's machine) |
| `.lua`           | `ModuleScript` (shared library code) |

## Working on the game

Use one of these workflows at a time; both write to the same Studio place.

**A) You, editing by hand:**

1. Open a terminal in this folder and run `rojo serve`. Leave it running.
2. In Roblox Studio: **Plugins** → **Rojo** → **Connect**.
3. Edit the `.lua` files in `src/` with VS Code. Every save updates Studio
   instantly.
4. Verify the change, then use `git add <files>`, `git commit`, and `git push`
   following the working agreement above.
5. `Ctrl+C` the Rojo window when done.

**B) An AI assistant with a Roblox Studio MCP connection:** edit `src/` and
mirror the changes directly into the open Studio session for testing.
Keep Rojo disconnected during this workflow and coordinate before switching
to manual editing.

## What isn't tracked here

The Roblox place file is **not tracked in Git**. Back it up separately; the
source code and reference art cannot restore the complete world. It contains:

- The baseplate, spawn pad, and camera
- `ServerStorage`: the four battery models (`Battery` = AA, `Battery_AAA`,
  `Battery_C`, `Battery_D`) — each one's pivot is set to its own centre
- `Workspace.Shop_Player`, `Workspace.Shop_GPUs`, and `Workspace.Shop_DataCenter`
  — each with a `Pad` and floating sign
- `Workspace.Field_Green`, `Workspace.Field_Yellow`, `Workspace.Field_Blue`,
  and `Workspace.Field_Red` — each a `Model` with a `Pad`; Yellow, Blue, and
  Red also have a `Sign` for their lock display. Green has no sign.
- `Workspace.DataCenter` — a `Model` with the (half-size, 8x8) battery
  dump-off `Pad`, its floating `Sign`, and a `Platform` part built 24
  studs wide (matching the Pad's own footprint) by `GPUs.RACKS_PER_COLUMN`
  rows deep -- big enough for column 1's full 16 racks. `Platform` is a
  single part -- there's no separate floor per column -- so
  GPURackDisplay.client.lua's `updatePlatform` covers however many
  columns the player's floor tier actually reaches using the same
  formula regardless of column count, verified in Studio Play mode
  through floorTier 4/64 racks (all 4 columns -- the last floor tier
  there is, `GPUs.floorTiers[4]`, jumps straight from column 2 to
  column 4). GPURackDisplay.client.lua
  resizes AND repositions `Platform` client-side: DEPTH stays flush with
  the back of whichever row THAT player's FLOOR TIER has room for
  (every column shares the same row positions, so this never changes
  once a whole column's depth is reached). WIDTH grows ONLY from its
  RIGHT edge -- the LEFT edge is always the floor's own BUILT left edge
  and NEVER moves, so the room a player already knows from tiers 1-2
  stays exactly where it was; only the right edge extends, once 2+ whole
  columns are unlocked, to stay flush with the rightmost RACK now in
  play (plus `PLATFORM_RIGHT_MARGIN`, the same breathing room the floor
  already gives column 1 on its fixed left side). A version that
  recentered the WHOLE floor around both outer edges symmetrically was
  tried and reverted -- it moved the tier-1/2 side a player already
  knows, which is exactly what this asymmetric version avoids. Its
  built (Edit-mode) size is just the column-1-only baseline every
  viewer's copy grows from.

  The Pad and its Sign move INDEPENDENTLY of the floor's own shape,
  client-side, to `GPUs.dataCenterCenterX(floorTier, racks)` -- centered
  on the WALKWAY itself (the midpoint between the leftmost and rightmost
  rack now in play), not the floor's own midpoint, since the floor's
  left edge deliberately stops recentering while the pad still needs to
  track the walkway wherever it ends up. Two STATIC pad positions
  (column 1's center, then tier 3's wider center) were each tried and
  reverted before this -- one static spot can only ever be right for
  SOME tiers, wrong for the rest, since every tier's true walkway center
  is a different X. So unlike everything else GPURackDisplay.client.lua
  moves (all pure per-client illusions), this one couldn't stay purely
  cosmetic: `DataCenter.server.lua` computes that SAME formula, per
  player, every frame, and checks THEIR position against it -- replacing
  what used to be a plain `pad.Touched` on the Pad's own fixed position.
  A shared Part can only have one TRUE position, so the deposit trigger
  can't just watch that position anymore; it has to independently
  recompute where each player's own pad-illusion actually
  is, the exact same way the client does, and check against that
  instead. `GPUs.dataCenterCenterX` is the one formula both sides call,
  so they can never quietly disagree about where "the pad" is for a
  given player.
- `Workspace.Server_Rack` (one per 4 equipment slots — 64 total, matching
  `GPUs.MAX_RACKS`) — arranged as 4 columns of 4 rows of 4 racks each,
  racks touching within a row (truly flush -- zero gap, not just close),
  rows 16 studs apart, columns roughly 7-12 studs apart. Column 1's row
  is centered in `Platform`'s BUILT width (not flush to either edge) --
  the confirmed look for "every rack the Starter Row allows, before
  buying a floor upgrade" (`GPUs.floorTiers[1]`, 4 racks). While EXACTLY
  one whole column is unlocked (`GPUs.floorTiers[2]`, "Column 1" -- tier
  2 only), column 1 stays in that SAME one true built row -- tier 2 just
  reveals the rest of it (12 more racks), lined up exactly like tier 1's
  4-rack row, never split into two aisles. (An earlier version DID split
  it into two side-by-side aisles with a walkway down the middle --
  reverted because it didn't match tier 1's look.) From tier 3 on (2+
  whole columns unlocked), column 1 moves for the first time: now a
  whole solid aisle alongside column 2 (also solid) -- but the two
  columns don't just sit at their closer, natural spacing. Column 1 flushes LEFT
  against `Platform`'s own fixed left edge, and whichever column is
  currently the LAST one unlocked flushes RIGHT against `Platform`'s own
  extended right edge (`PLATFORM_RIGHT_MARGIN` -- the same breathing
  room the floor already gives column 1 on its left -- is exactly how
  far each one has to move), widening the walkway between them to fill
  however much room the floor actually has, instead of leaving the
  natural, narrower gap. Any column strictly BETWEEN column 1 and the
  last one (3+ columns covered) stays at its true built position --
  verified in Studio Play mode at floorTier 4/64 racks (the last floor
  tier there is, `GPUs.floorTiers[4]`, jumps straight from column 2 to
  column 4 -- there's no separate 3-column checkpoint): column 1 and
  column 4 flush to the floor's edges exactly as they do at tier 3,
  columns 2-3 sit untouched at their natural spacing between them.
  The racks' BUILT (Edit-mode) position in Studio is always the
  single centered row -- every layout above is a client-side illusion on
  top of it, and `GPUs.dataCenterCenterX` (used for the Pad/Sign) still
  lands on the correct walkway midpoint either way, since flushing both
  sides outward by the same `PLATFORM_RIGHT_MARGIN` amount widens the
  gap without moving its center.
  Each rack is a `MeshPart` holding its own 4 GPU-card `Model`s, named
  bottom to top `GPU_Bottom`, `GPU_Bottom_Middle`, `GPU_Top_Middle`,
  `GPU_Top`. Every shell panel (`Panel_Back`/`Left`/`Right`/`Top`) and
  every BasePart inside those 4 GPU-card models is **unanchored and
  welded (`WeldConstraint`) directly to the rack's own MeshPart** -- so
  the whole assembly (shell + cards) physically rides along whenever a
  script moves the rack part's `CFrame` (see the split layout above),
  and a GPU card is structurally incapable of ending up attached to a
  DIFFERENT rack than the one it's welded to. If a rack or its cards are
  ever rebuilt in Studio, re-weld them the same way before relying on
  GPURackDisplay.client.lua to move racks around.
  GPURackDisplay.client.lua and RackShopUI.client.lua both read however
  many racks actually exist (via `GPUs.getAllRacks`, which waits for the
  full count to stream in) and number them COLUMN first (left to right),
  then ROW within a column (front to back) — so buying up through rack 4
  fills column 1's front row (the Starter Row cap) before rack 5 (row 2)
  is even reachable. That order comes from each rack's own `RackNumber`
  attribute, stamped ONCE by `RackNumbering.server.lua` (a Script, so it
  runs before any client does) using `GPUs.sortRacks` on the racks' TRUE
  built positions — never re-derived from LIVE positions client-side,
  because the split layout above can leave column 1's right aisle closer
  to column 2 than `GPUs.sortRacks`' own gap-detection threshold, which
  would otherwise misread them as one merged column and scramble every
  rack number from there on. `GPUs.getAllRacks`'s result is also MEMOIZED
  (the first scan wins, for the rest of that client session) as a second
  layer of safety. Moving/adding racks or columns in Studio needs no code
  change, but DOES need `RackNumbering.server.lua` to run again (restart
  the server, or re-run it) so the new layout's `RackNumber`s get
  restamped — see `GPUs.SLOTS_PER_RACK`/`GPUs.RACKS_PER_COLUMN`/
  `GPUs.rackSlotRange`/`GPUs.sortRacks`. A player's `RacksOwned`
  (bought individually at the Data Center Shop, gated by `FloorTier`) can be
  less than 64 — an owned-but-not-yet-bought rack still physically exists,
  its slots just show "Locked" until bought, and its whole shell stays
  invisible/non-solid for that player until then.

## Requirements

- [Rojo](https://rojo.space) 7.7.0 (CLI + Roblox Studio plugin + VS Code extension) — only needed for workflow A
- Git
- Roblox Studio
- To test saving/loading progress **in Studio**: Game Settings → Security →
  **Enable Studio Access to API Services** must be on. If loading fails,
  the session uses fresh defaults without saving over existing progress;
  check Studio's Output for warnings.
