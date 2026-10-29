# SM Custom Game

A survival-based Custom Game for Scrap Mechanic. The stock survival logic is
kept intact and extended with the custom blocks, recipes, and server commands
ported from the old "server software" workshop custom game (3440826317).

## Status

The port targets Scrap Mechanic 1.0.6.889 and has been validated locally:

- all five custom blocks register and load their scripts,
- the `craftbot_custom` recipe category appears on the craftbot,
- ender chests create hidden sky containers and open their container GUI,
- the ported chat commands run server-side with an administrator check.

Existing Survival saves are untouched; Custom Games use their own save files.

## Layout

```text
.
├── config.json                 # declares a Survival custom game
├── description.json            # Workshop metadata
├── CraftingRecipes/craftbot/   # custom craftbot recipe set
├── Gui/Language/English/       # inventory titles/descriptions
├── Objects/
│   ├── Database/ShapeSets/     # customblocks + customcraftbot shapesets
│   ├── Renderable/             # ender chest / sunlight panel renderables
│   ├── Mesh/                   # sunlight panel mesh
│   └── Textures/               # ender chest textures
├── ScriptableObjects/          # world-bound spawner used by admin commands
├── Scripts/
│   ├── game/SurvivalGame.lua   # stock survival + recipe/command integration
│   ├── game/SurvivalPlayer.lua # stock player + custom-item achievement guard
│   ├── game/interactables/CustomCrafter.lua
│   └── smserver/               # ported custom block runtime
└── Terrain/ …                  # template world/databases
```

`config.json` sets `baseGameContent` to `Survival` and points the game/player
scripts at `$CONTENT_DATA`.

## Custom content

Blocks (workshop UUIDs are preserved):

| Block | UUID |
| --- | --- |
| Ender Chest | `8581c92f-9390-48bf-a291-4bb786effbd7` |
| Sky Container (hidden backend) | `1041ace6-6df4-4a85-b2a5-cf4e76308e4d` |
| Generator | `3e1c8de8-2dd8-4397-bd25-7a0e38b0f619` |
| Sun-Light Panel | `f8fb8503-3af8-489f-9244-465d7d5df1eb` |
| Private Block | `e85e06c9-628d-4327-a6dc-10a19e7fbf47` |

`Objects/Database/ShapeSets/customcraftbot.shapeset` re-declares the five
stock craftbot UUIDs with `CustomCrafter.lua`, a fork of the stock crafter that
adds the `craftbot_custom` recipe category. The custom recipes live in
`CraftingRecipes/craftbot/craftbot_custom.json` and are unlocked at server
start (there is no schematic source for them).

Ender chests store their contents in hidden `skycontainer` parts placed at
(-10, -10, 2000), matching the original server behaviour.

## Dependencies

`description.json` declares **SComputers [Fork]** (`fileId 2949350596`,
`localId 3aeb81c2-71b9-45a1-9479-1f48f1e8ff21`). ClassHook is pulled in by
SComputers itself.

Dependency recipes are not loaded by the stock game. `SurvivalGame` registers
`$CONTENT_3aeb81c2-71b9-45a1-9479-1f48f1e8ff21/CraftingRecipes/craftbot.json`
as the `craftbot_scomputers` set, `CustomCrafter` adds that set to the craftbot
UI (and safely skips sets that are not mounted), and both custom and dependency
recipes are unlocked at server start.

This matters for the Ender Chest recipe: its third ingredient is SComputers'
**Lua Computer** (`356ecbf5-d4fa-480f-8409-15d9d8add6a5`). Without the
dependency that ingredient is unknown and `LoadCraftingRecipes` drops the
recipe.

### Adding another mod's craftbot recipes

1. Declare the mod in `description.json` `dependencies` (`fileId`, `localId`,
   `name`), so its content is mounted as `$CONTENT_<localId>`.
2. Register its recipe file in `SurvivalGame.loadCraftingRecipes`, e.g.
   `craftbot_mymod = "$CONTENT_<localId>/CraftingRecipes/craftbot.json"`.
3. Add the set name to the unlock list if its recipes should be craftable
   immediately.
4. `CustomCrafter` automatically discovers every loaded `craftbot_*` set and
   appends it to the craftbot grid in a stable sorted order; no manual category
   list edit is needed.

`The Modpack Continuation` (`fileId 2448492759`) is registered as
`craftbot_modpack` (122 recipes when its content is mounted). Its recipes that
reference parts from other mods are only kept when those shapes are loaded;
`LoadCraftingRecipes` drops recipes with unknown item UUIDs.

## Commands

All commands are bound for every player and enforced server-side. The host is
always an administrator; `/op <name> [on|off]` (host only) grants others
administrator rights for the current save.

| Command | Purpose |
| --- | --- |
| `/op <name> [on\|off]` | Grant/revoke administrator rights |
| `/kick <name>` / `/ban <name>` | Host/administrator moderation |
| `/tp <name>` / `/tpr <name>` | Teleport to / bring a player |
| `/tpp <x> <y> <z>` | Teleport to coordinates |
| `/ppos` | Print your world position |
| `/give <uuid> [quantity]` | Give yourself an item |
| `/spawnpart <uuid>` | Spawn a part in front of you |
| `/ender [name]` | Open the public or a player's ender chest |

Shape spawning runs through the world-bound `SmserverSpawner` scriptable
object because the game script has no world context.

## Network hardening

All privileged server handlers validate the **network caller** instead of
trusting a player object from the payload. The engine appends the sending
player as the final argument of every network-invoked method, so handlers read
that position via `smserver_getNetworkCaller(...)` and reject unknown callers.
Internal server-to-server calls have no caller and remain trusted.

Hardened entry points include `/give`, `/spawnpart`, `/teleport`, cell/tile
loading, time and inventory cheats, unit spawning, kick/ban, and the internal
`sv_e_*` event handlers. Administrator rights are keyed by **Steam id**, not
nickname, and the host is always an administrator.

Custom blocks add their own checks:

- ender chest requests require the player's character to be within 12 m of the
  chest and are rate limited; open GUIs are force-closed beyond 24 m,
- personal ender chests are keyed by Steam id, so renaming a player does not
  change ownership,
- private blocks store the owner's Steam id and validate distance before
  returning or changing ownership,
- sky-container names/sizes and spawned part UUIDs are validated.

### Block stack / free-resource blueprint

The vanilla block container `3d127db0-da28-4483-86fd-3eeed20fb85d`
(`obj_interactive_blockcontainersmall`, the glass "block stack" used by the
"40 free component kits" blueprint) is replaced in `customblocks.shapeset` by
an invisible inert shape:

- no `itemStack`, so it has no item container to fill from a blueprint,
- `blockstack_dummy.lua` empties and removes any container the importer still
  attaches during the first ticks,
- no inventory entry, no crafting recipe, not liftable/connectable/usable,
- `erasable` only, so imported placeholders can be cleaned up,
- the UUID is rejected by `/give` and `/spawnpart` on the server.

## Class system (`std.class`)

`atstd lib`'s class system is vendored under `Scripts/shared/api/`:

- `Class2.lua` — `std.class`, `std.event`, `std.broadcast`,
- `WeakTable.lua` — weak-table helper used by broadcasts.

`Scripts/smserver/core.lua` loads both once and exposes `std` to game, player,
and block scripts. Existing stock-derived classes keep the engine `class`;
new code can use `std.class` to get isolated `client`/`server`/`shared`
contexts and token-checked events:

```lua
MyThing = std.class()

function MyThing.shared.event.onSomething( self, data, caller )
    -- Only reachable through std.event.sendToXxx, not a guessed event name.
end

std.event.sendToPlayer( player, "onSomething", { value = 1 } )
```

`std.event` wrappers generate a random receiver name and per-call token, so a
modified client cannot invoke arbitrary event handlers by name.

## Security limits

Some reported issues are engine/client-authoritative and cannot be fixed in
Lua: a modified client can still spawn projectiles locally, and vanilla
container/garage interfaces do not validate distance server-side. The port
hardens every customGame-controlled path and all reachable Lua handlers that
mutate server state, but it cannot retroactively secure stock C++ behaviour.

## Local installation

Copy this directory into the Scrap Mechanic user mods folder:

```text
%AppData%\Axolot Games\Scrap Mechanic\User\User_<steamid>\Mods\SM-CustomGame
```

On Linux/Proton the equivalent path is under:

```text
.../compatdata/387990/pfx/drive_c/users/steamuser/AppData/Roaming/
Axolot Games/Scrap Mechanic/User/User_<steamid>/Mods/SM-CustomGame
```

Launch Scrap Mechanic, choose **Custom Games**, and select the mod.

Delete the mod's `Cache` directory after changing scripts or databases so the
game recompiles them; the game otherwise keeps the previous raw script cache.

## Publishing

Use the Scrap Mechanic **Mod Tool** to open this folder as a project and upload
it to Steam Workshop. Keep `description.json` fields:

- `type`: `Custom Game`
- `name`: a player-facing name
- `localId`: stable UUID for this custom game
- `fileId`: updated by the upload flow after the first publication

## Save compatibility

A custom game save is a normal Scrap Mechanic SQLite save whose mod metadata
references this custom game. Server and every client need the mod installed.
Old "server software" saves reference missing workshop files and are not
compatible; start a new Custom Game save.

`tools/port_save.py` copies a survival SQLite save and rewrites its
custom-game metadata without touching the source file. The resulting save must
still be validated in game.

## Template attribution

The project structure and template assets originate from Scrap Mechanic's
official Survival Custom Game template. The MIT license in this repository
covers the original tooling and scripts added here; Scrap Mechanic and its
template assets remain subject to Axolot Games' terms.

## Security

This repository must never contain Steam credentials, API tokens, or server
environment files. Keep those in the deployment environment only.
