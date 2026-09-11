# Battery Collector

A Roblox game, and Ethan's project for **learning software development from
scratch** — every change is made one small step at a time, explained as it
happens, so the "why" sticks, not just the "what."

**The game so far:** walk a field collecting batteries (rarer sizes glow
bigger and are worth more, but vanish faster if you don't rush them) →
carrying capacity is limited, so you decide when to head back → dump your
batteries at the AI Data Center, which converts them into a power reserve and
burns through it every second to pay you Cash → spend Cash at the Upgrade Shop
on four upgrades that compete for the same money (better at collecting, or
better at cashing out — buying more Cash output also makes the data center
hungrier for power, so it's a real tradeoff, not just "buy everything").

The full, dated story of every change — what, why, and what it taught — is in
[CHANGELOG.md](CHANGELOG.md). Read that before making changes; it explains the
reasoning behind the current numbers far better than the code alone can.

## Working agreement (read this first, human or AI)

- **Explain everything simply.** Ethan is building software literacy through
  this project. Every change — in chat *and* in code comments — should teach
  the underlying concept, not just state what the code does. Assume no prior
  programming background; define terms the first time they come up.
- **`src/` is the source of truth, and every change gets committed and pushed
  to GitHub automatically** once it's built and tested — no need to ask first.
  `github.com/GizmosGarage/battery-collector`, branch `main`. No attribution
  lines in commit messages.
- **The `Scripts/` folder of old numbered snapshots is retired** (removed
  2026-09-10). `git log` and `CHANGELOG.md` are the history now — don't
  recreate that pattern.
- **World geometry (the battery models, the Data Center, the Shop platform)
  lives only in the `.rbxl` place file, not in this repo** — see "What isn't
  tracked" below. Only the code is version-controlled.

## Folder layout

```
Battery Collector/
├── default.project.json   Rojo's map: which folder goes to which Roblox service
├── .gitignore              files Git should ignore (mainly the .rbxl place file)
├── README.md               this file
├── CHANGELOG.md            dated, plain-language history of every change — read this
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
│   │   └── ShopUI.client.lua             the upgrade shop panel (built entirely in code)
│   └── shared/             → ReplicatedStorage
│       └── Upgrades.lua    single source of truth for all 4 upgrades' costs/effects
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
- `Workspace.DataCenter` (Pad + floating sign) and `Workspace.Shop` (Pad + sign)

If the place file is ever lost, these have to be rebuilt by hand (the
`Prompts/` and `Models/` folders document how the original battery look was
generated, as a starting point).

## Requirements

- [Rojo](https://rojo.space) 7.7.0 (CLI + Roblox Studio plugin + VS Code extension) — only needed for workflow A
- Git
- Roblox Studio
