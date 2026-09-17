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
the floor itself (room for 3 more racks, without buying them). Every slot
in an owned rack comes free with it. The GPU Shop only sells into storage;
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
│   │   └── Shop.server.lua             validates purchases and manages equipment
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
  dump-off `Pad`, its floating `Sign`, and a `Platform` part that houses
  both the pad and the 9-rack grid described next.
- `Workspace.Server_Rack` (one per 4 equipment slots — 9 total, matching
  `GPUs.MAX_RACKS`, arranged in 3 rows of 3 on the `Platform` above) — each a
  `MeshPart` holding its own 4 GPU-card `Model`s, named bottom to top
  `GPU_Bottom`, `GPU_Bottom_Middle`, `GPU_Top_Middle`, `GPU_Top`.
  GPURackDisplay.client.lua and RackShopUI.client.lua both read however
  many racks actually exist, sorted by Z (row by row) then by X within a
  tied row (left to right), so adding another in Studio needs no code
  change — see `GPUs.SLOTS_PER_RACK`/`GPUs.rackSlotRange`. A player's
  `RacksOwned` (bought individually at the Data Center Shop) can be less
  than 9 — an owned-but-not-yet-bought rack still physically exists, its
  slots just show "Locked" until bought.

## Requirements

- [Rojo](https://rojo.space) 7.7.0 (CLI + Roblox Studio plugin + VS Code extension) — only needed for workflow A
- Git
- Roblox Studio
- To test saving/loading progress **in Studio**: Game Settings → Security →
  **Enable Studio Access to API Services** must be on. If loading fails,
  the session uses fresh defaults without saving over existing progress;
  check Studio's Output for warnings.
