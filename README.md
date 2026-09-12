# Battery Collector

A Roblox game, and Ethan's project for **learning software development from
scratch** — every change is made one small step at a time, explained as it
happens, so the "why" sticks, not just the "what."

**The game so far:** walk a field collecting batteries (rarer sizes glow
bigger and are worth more, but vanish faster if you don't rush them) →
carrying capacity is limited, so you decide when to head back → dump your
batteries at the AI Data Center, which converts them into a power reserve and
burns through it every second to pay you Cash → spend Cash at the Player Shop
(Speed, Capacity) to collect better, or at the Data Center Shop (Power
Conversion, plus GPU hardware) to cash out better. Cash/sec isn't a level
upgrade anymore — it's real GPUs: 1-4 equipment slots, each filled from a
5-tier catalog where a better card pays more but also draws more power, so
racking up GPUs is a genuine tradeoff against your power reserve, not just
"buy everything."

## Working agreement (read this first, human or AI)

- **Explain everything simply.** Ethan is building software literacy through
  this project. Every change — in chat *and* in code comments — should teach
  the underlying concept, not just state what the code does. Assume no prior
  programming background; define terms the first time they come up.
- **`src/` is the source of truth, and every change gets committed and pushed
  to GitHub automatically** once it's built and tested — no need to ask first.
  `github.com/GizmosGarage/battery-collector`, branch `main`. No attribution
  lines in commit messages.
- **[CHANGELOG.md](CHANGELOG.md) is Ethan's personal devlog, not onboarding
  material.** After every change, append a dated entry to it (what changed,
  why, which files, what concept it taught, how it was tested) — same as
  always. But **an AI session should never *read* CHANGELOG.md to get
  oriented** — it's grown to hundreds of lines and would burn a large chunk of
  context before any work gets done, for a payoff the code already gives you
  for free. To understand what the game currently does, **read the `src/`
  files directly** (they're the actual, current behavior — shorter and more
  reliable than a historical narrative) plus this README. Write to the
  CHANGELOG; don't read from it.
- **The `Scripts/` folder of old numbered snapshots is retired** (removed
  2026-09-10). `git log` is the code history now — don't recreate that pattern.
- **World geometry (the battery models, the Data Center, the Shop platform)
  lives only in the `.rbxl` place file, not in this repo** — see "What isn't
  tracked" below. Only the code is version-controlled.

## Folder layout

```
Battery Collector/
├── default.project.json   Rojo's map: which folder goes to which Roblox service
├── .gitignore              files Git should ignore (mainly the .rbxl place file)
├── README.md               this file
├── CHANGELOG.md            Ethan's devlog — APPEND after every change, don't read it to get oriented
├── src/                    the live source code — edit these files
│   ├── server/             → ServerScriptService
│   │   ├── PlayerSetup.server.lua      gives each player their leaderstats (Batteries, mAh, Cash)
│   │   ├── BatterySpawner.server.lua   spawns/despawns batteries, handles collection + carry cap
│   │   ├── PlayerSpeed.server.lua      applies the Speed upgrade to walk speed
│   │   ├── DataCenter.server.lua       the dump-and-burn power/Cash loop
│   │   └── Shop.server.lua             owns upgrade levels, validates purchases
│   ├── client/             → StarterPlayer > StarterPlayerScripts
│   │   ├── BatterySpin.client.lua        battery lean + spin animation
│   │   ├── BatteryGlow.client.lua        rarity glow (bigger/brighter = rarer)
│   │   ├── BatteryCollision.client.lua   walk through batteries once you're full
│   │   ├── DataCenterDisplay.client.lua  the Data Center pad/sign, per-player
│   │   └── ShopUI.client.lua             the two upgrade shop panels (built entirely in code)
│   └── shared/             → ReplicatedStorage
│       ├── Upgrades.lua    single source of truth for the 3 level upgrades' costs/effects
│       ├── GPUs.lua        single source of truth for the GPU catalog + equipment slots
│       └── Fields.lua      single source of truth for the 4 fields' names + allowed battery sizes
├── Models/                 reference art (battery renders used to build the 3-D models)
└── Prompts/                the AI prompts used to generate the model and image references
```

### How filenames map to Roblox

| File ending      | Becomes in Roblox |
| ---------------- | ----------------- |
| `.server.lua`    | `Script` (runs on the server) |
| `.client.lua`    | `LocalScript` (runs on each player's machine) |
| `.lua`           | `ModuleScript` (shared library code) |
| `init.lua` in a folder | that folder itself becomes a `ModuleScript` |

## Working on the game

Two ways this happens, and they must not run at the same time (both push
changes into the same Studio place, and would fight each other):

**A) You, editing by hand:**

1. Open a terminal in this folder and run `rojo serve`. Leave it open — it
   prints something like `Rojo server listening on port 34872`.
2. In Roblox Studio: **Plugins** → **Rojo** → **Connect**.
3. Edit the `.lua` files in `src/` with VS Code. Every save updates Studio
   instantly.
4. Commit when something works: `git add -A && git commit -m "..." && git push`.
5. `Ctrl+C` the Rojo window when done.

**B) An AI assistant (e.g. Claude Code), editing live via the Roblox Studio
MCP connection:** it edits the `src/` files *and* mirrors the same change into
the already-open Studio session directly (not through Rojo), so you can test
immediately without `rojo serve` running. It commits and pushes automatically
once a change is built and tested. **If you want to jump in and edit by hand
while an AI session is active, say so first** — don't run `rojo serve` +
Connect at the same time as it's working.

## What isn't tracked here

The `.rbxl` place file itself is deliberately **not** in Git — it's one big
binary blob Git can't diff or merge. That means the world geometry and these
specific things live *only* in the place file, not this repo:
- The baseplate, spawn pad, and camera
- `ServerStorage`: the four battery models (`Battery` = AA, `Battery_AAA`,
  `Battery_C`, `Battery_D`) — each one's pivot is set to its own centre
- `Workspace.DataCenter` (Pad + floating sign) and the two shop platforms,
  `Workspace.Shop_Player` (Speed, Capacity) and `Workspace.Shop_DataCenter`
  (Power Conversion, plus the GPU slot/catalog section) -- each Pad + sign,
  same as before the split; `Upgrades.lua`'s `Upgrades.shops` records which
  LEVEL upgrades belong to which shop, and `GPUs.lua` owns the GPU catalog
  and slot prices shown on the Data Center Shop
- The four raised battery fields — `Workspace.Field_Green` (smallest, AAA
  only), `Field_Yellow` (+ AA), `Field_Blue` (+ C), `Field_Red` (biggest, +
  D — this is the original single field, just recolored). Each is a `Model`
  with one `Pad` part; `Fields.lua` is the only place their NAMES and
  allowed battery sizes are recorded, and `BatterySpawner.server.lua` reads
  each Pad's live size/position, so resizing or moving one in Studio needs
  no code change

If the place file is ever lost, these have to be rebuilt by hand (the
`Prompts/` and `Models/` folders document how the original battery look was
generated, as a starting point).

## Requirements

- [Rojo](https://rojo.space) 7.7.0 (CLI + Roblox Studio plugin + VS Code extension) — only needed for workflow A
- Git
- Roblox Studio
