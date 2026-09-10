# Battery Collector

A small Roblox game. Batteries hover and spin around a field; walk into one and
your score goes up. The collected battery disappears and a fresh one shows up
somewhere else a few seconds later.

- **Server** hands every player a `leaderstats` scoreboard, spawns 15 batteries
  from a template in `ServerStorage`, and handles collection + respawn.
- **Client** does the lean-and-spin animation locally, so no movement data has
  to travel over the network.

A running history of every change is in [CHANGELOG.md](CHANGELOG.md).

## Folder layout

```
Battery Collector/
├── default.project.json   Rojo's map: which folder goes to which Roblox service
├── .gitignore             files Git should ignore (mainly the .rbxl place file)
├── README.md              this file
├── CHANGELOG.md           plain-language history of every change
├── src/                   the live source code — edit these files
│   ├── server/            → ServerScriptService
│   │   ├── PlayerSetup.server.lua
│   │   └── BatterySpawner.server.lua
│   ├── client/            → StarterPlayer > StarterPlayerScripts
│   │   └── BatterySpin.client.lua
│   └── shared/            → ReplicatedStorage (empty for now)
├── Scripts/               older numbered snapshots (V1.txt, V2.txt …), kept as history
├── Models/                source art (Battery.png)
└── Prompts/               the AI prompts used to generate the model and image
```

### How filenames map to Roblox

| File ending      | Becomes in Roblox |
| ---------------- | ----------------- |
| `.server.lua`    | `Script` (runs on the server) |
| `.client.lua`    | `LocalScript` (runs on each player's machine) |
| `.lua`           | `ModuleScript` (shared library code) |
| `init.lua` in a folder | that folder itself becomes a `ModuleScript` |

## Working on the game

1. Open a terminal in this folder and start Rojo:

   ```
   rojo serve
   ```

   Leave that window open. It prints something like
   `Rojo server listening on port 34872`.

2. Open the place in Roblox Studio → **Plugins** tab → **Rojo** → **Connect**.

3. Edit the `.lua` files in `src/` with VS Code. Every time you save, Studio
   updates instantly. **Don't edit the scripts inside Studio any more** —
   Rojo overwrites them from the files.

4. When something works, save a checkpoint:

   ```
   git add -A
   git commit -m "short description of what changed"
   git push
   ```

Press `Ctrl+C` in the Rojo window when you're finished for the day.

## What isn't tracked here

The `.rbxl` place file itself is deliberately **not** in Git — it's one big
binary blob that Git can't diff or merge. That means the world geometry
(baseplate, spawn pad) and the **`Battery` model in `ServerStorage`** live only
in the place file, not in this repo. Only the code is version-controlled.

## Requirements

- [Rojo](https://rojo.space) 7.7.0 (CLI + Roblox Studio plugin + VS Code extension)
- Git
- Roblox Studio
