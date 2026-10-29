# Technical reference

This document is the detailed counterpart to `README.md`. It describes the
runtime entrypoints, custom code, dependency loading, hardening boundaries and
known limitations of **SM Custom Game**.

## Runtime

`config.json` declares a Custom Game with `baseGameContent: "Survival"`:

```json
{
  "baseGameContent": "Survival",
  "gameScript": {
    "class": "SurvivalGame",
    "file": "$CONTENT_DATA/Scripts/game/SurvivalGame.lua"
  },
  "playerScript": {
    "class": "SurvivalPlayer",
    "file": "$CONTENT_DATA/Scripts/game/SurvivalPlayer.lua"
  }
}
```

`$CONTENT_DATA` is the mounted mod root. The game script loads the stock
survival managers and then the custom runtime:

- `Scripts/smserver/core.lua` — shared `std` class system, network-caller
  helpers, admin checks, range/finite/clamp helpers, blocklist loading.
- `Scripts/game/SurvivalGame.lua` — stock survival plus recipe registration,
  chat commands, admin handlers and blocklist enforcement.
- `Scripts/game/SurvivalPlayer.lua` — stock player plus caller validation and
  the custom-item achievement guard.

Target version: **Scrap Mechanic 1.0.6.889**.

## Repository layout

```text
.
├── config.json / description.json   # Custom Game metadata
├── CraftingRecipes/                # custom + sanitized dependency recipes
├── Gui/                            # item descriptions and icons
├── Objects/                        # custom shapesets, meshes, renderables
├── ScriptableObjects/              # world-bound SmserverSpawner
├── Scripts/
│   ├── game/                       # mostly vendored stock survival scripts
│   ├── shared/api/                 # vendored std.class + weak table
│   ├── smserver/                   # custom block runtime + blocklist
│   └── terrain/                    # vendored stock terrain scripts
├── tests/                          # Python save-porting tests
├── tools/                          # save porting and recipe filtering
└── Terrain/, Characters/, ...      # template databases
```

### Vendored stock scripts

`Scripts/game` and `Scripts/terrain` are largely copies of the stock Survival
scripts, kept so the custom game can override individual files while remaining
self-contained. They are **not** the place for new gameplay code.

Compared with `$SURVIVAL_DATA/Scripts/game` on 1.0.6.889, only these files
differ or are extra:

| File | Custom purpose |
| --- | --- |
| `Scripts/game/SurvivalGame.lua` | recipe registration, chat commands, admin handlers, blocklist |
| `Scripts/game/SurvivalPlayer.lua` | network-caller guards, achievement guard |
| `Scripts/game/interactables/CustomCrafter.lua` | `craftbot_custom` category discovery |
| `Scripts/game/quests/BosstrainQuest.lua` | quest resume/fallback recovery |

The vendored `Scripts/game/tools` tree is byte-identical to stock; keep it in
sync with the game version like the rest of the vendored tree.

`Scripts/terrain` is byte-identical to the stock terrain scripts. Root helpers
(`achievement_common.lua`, `blueprint_util.lua`, `camera_util.lua`,
`kinematic_util.lua`, `util.lua`) are also identical.

When updating the game version, diff the vendored trees against the new
`$SURVIVAL_DATA/Scripts` before overwriting anything. See
[Review notes](#review-notes) for the cleanup recommendation.

## Custom content

### Blocks

Workshop UUIDs are preserved:

| Block | UUID |
| --- | --- |
| Ender Chest | `8581c92f-9390-48bf-a291-4bb786effbd7` |
| Sky Container (hidden backend) | `1041ace6-6df4-4a85-b2a5-cf4e76308e4d` |
| Generator | `3e1c8de8-2dd8-4397-bd25-7a0e38b0f619` |
| Sun-Light Panel | `f8fb8503-3af8-489f-9244-465d7d5df1eb` |
| Private Block | `e85e06c9-628d-4327-a6dc-10a19e7fbf47` |

Custom block scripts live in `Scripts/smserver/` and are registered through
`Objects/Database/ShapeSets/customblocks.shapeset`. Ender chests store their
contents in hidden `skycontainer` parts at `(-10, -10, 2000)`, matching the
original server behaviour.

### Icons

Inventory/craftbot icons live in `Gui/IconMap.xml` and `Gui/IconMap.png`
(96×96 frames cropped from the original workshop atlas). The game merges this
`ItemIconsSet0` resource with the stock, SComputers and Modpack maps, so adding
it does not hide stock icons. Add an `<Index>` plus frame for any new block.

### Craftbot

`Objects/Database/ShapeSets/customcraftbot.shapeset` re-declares the five stock
craftbot UUIDs with `CustomCrafter.lua`. The custom recipes live in
`CraftingRecipes/craftbot/craftbot_custom.json` and are unlocked at server
start; there is no schematic source for them.

`CustomCrafter` keeps a static category order (`craftbot_core`,
`craftbot_custom`, `craftbot_scomputers`, ...) and appends any other loaded
`craftbot_*` set in sorted order, so client grid indices remain stable.

## Dependency and recipe loading

`description.json` declares:

| Mod | fileId | localId |
| --- | --- | --- |
| SComputers [Fork] | `2949350596` | `3aeb81c2-71b9-45a1-9479-1f48f1e8ff21` |
| The Modpack Continuation | `2448492759` | `b7443f95-67b7-4f1e-82f4-9bef0c62c4b3` |
| atstd lift | `3829430797` | `2d9d788c-db36-4ab9-8445-b70e2f59bd91` |

SComputers pulls in **ClassHook** (`3800269749`,
`9ec648d4-095c-4dc1-a97e-cd5b5bdfa798`). `atstd lift` pulls in **atstd lib**
(`3768959679`) and its shared resources (`3768960327`).

Dependency recipes are not loaded by the stock game. `SurvivalGame` registers
`$CONTENT_<SComputers-localId>/CraftingRecipes/craftbot.json` as the
`craftbot_scomputers` set. `CustomCrafter` adds that set to the craftbot UI and
safely skips sets that are not mounted.

This matters for the Ender Chest recipe: its third ingredient is SComputers'
**Lua Computer** (`356ecbf5-d4fa-480f-8409-15d9d8add6a5`). Without the
dependency, the ingredient is unknown and `LoadCraftingRecipes` drops the
recipe.

`The Modpack Continuation` is registered as `craftbot_modpack` (122 recipes
when mounted). Recipes referencing shapes from missing mods are dropped by
`LoadCraftingRecipes`.

### Adding another mod's craftbot recipes

1. Declare the mod in `description.json` `dependencies` (`fileId`, `localId`,
   `name`) so its content is mounted as `$CONTENT_<localId>`.
2. Register its recipe file in `SurvivalGame.loadCraftingRecipes`, e.g.
   `craftbot_mymod = "$CONTENT_<localId>/CraftingRecipes/craftbot.json"`.
3. Add the set name to the unlock list if its recipes should be craftable
   immediately.
4. `CustomCrafter` discovers every loaded `craftbot_*` set automatically; no
   category list edit is needed.

## Lift dependency

The modified Lift is the published Workshop mod **atstd lift**
(`fileId 3829430797`, `localId 2d9d788c-db36-4ab9-8445-b70e2f59bd91`), not a
local script.

Its `Tools/Database/ToolSets/Lifts.toolset` overrides both lift UUIDs:

- `5cc12f03-275e-4c8e-b013-79fc0f913e1b` (creative lift)
- `8f190ce2-3a59-423e-8483-a7aa67bd5bc0` (survival lift)

with `Scripts/LiftTool.lua`. The mod declares `atstd lib` as its own dependency,
so the library and shared resources mount transitively and do not need to be
copied into this repository.

Do not reimplement the lift locally. If the lift fails to load, verify that the
Workshop dependency (and its nested `atstd lib`/shared-resources dependencies)
is mounted before debugging the custom game. A `LiftTool.lua` error like
`attempt to index field 'json' (a nil value)` means `std.json` from `atstd lib`
was not initialized, i.e. the nested dependency chain is incomplete.

## Network hardening

All privileged server handlers validate the **network caller**, not a player
object from the payload. The engine appends the sending player as the final
argument of every network-invoked method; handlers read it with
`smserver_getNetworkCaller(...)` and reject unknown callers. Internal
server-to-server calls have no caller and remain trusted.

Hardened entry points include `/give`, `/spawnpart`, `/teleport`, cell/tile
loading, time and inventory cheats, unit spawning, kick/ban, and internal
`sv_e_*` event handlers. Administrator rights are keyed by **Steam id**, not
nickname; the host is always an administrator.

Custom blocks add their own checks:

- Ender chest requests require the player's character within 12 m of the chest
  and are rate limited; open GUIs are force-closed beyond 24 m.
- Personal ender chests are keyed by Steam id, so renaming does not change
  ownership.
- Private blocks store the owner's Steam id and validate distance before
  returning or changing ownership.
- Sky-container names/sizes and spawned part UUIDs are validated.

### Block stack / free-resource blueprint

The vanilla block container `3d127db0-da28-4483-86fd-3eeed20fb85d`
(`obj_interactive_blockcontainersmall`, used by the "40 free component kits"
blueprint) is replaced in `customblocks.shapeset` by an invisible inert shape:

- no `itemStack`, so blueprints cannot fill it,
- `blockstack_dummy.lua` empties/removes any container the importer attaches
  during the first ticks,
- no inventory entry, no recipe, not liftable/connectable/usable,
- `erasable` only, so imported placeholders can be cleaned up,
- rejected by `/give` and `/spawnpart`.

## Class system (`std.class`)

`atstd lib`'s class system is vendored under `Scripts/shared/api/`:

- `Class2.lua` — `std.class`, `std.event`, `std.broadcast`
- `WeakTable.lua` — weak-table helper used by broadcasts

`Scripts/smserver/core.lua` loads both once and exposes `std` to game, player
and block scripts. Stock-derived classes keep the engine `class`; new code can
use `std.class` for isolated `client`/`server`/`shared` contexts and
token-checked events:

```lua
MyThing = std.class()

function MyThing.shared.event.onSomething( self, data, caller )
    -- Reachable only through std.event.sendToXxx, not a guessed event name.
end

std.event.sendToPlayer( player, "onSomething", { value = 1 } )
```

`std.event` wrappers generate a random receiver name and per-call token, so a
modified client cannot invoke arbitrary handlers by name.

## Production item blacklist

`Scripts/smserver/production_blacklist.json` lists UUIDs that must not be
craftable or spawnable:

```json
{ "items": { "<uuid>": "reason" } }
```

At world start, recipes for these items are removed from every loaded recipe
set and from the unlock/crafter maps. `/give`, `/spawnpart` and the
world-bound spawner reject them too. The removed-recipe count is logged.

Currently blocked (The Modpack Continuation):

- `c9e34f58-b30d-4ab5-92c5-76f707090c45` — gravity module, FPS-dependent
  per-creation gravity impulses.
- `e93ca226-4166-49e3-97cd-bb8df20242d7` — gravity modulator, changes world
  gravity for the entire server.

The craftbot grid is loaded by the engine straight from the recipe file, so the
Lua filter alone would hide only craftability, not the grid entry. The repo
therefore ships a sanitized copy of the Modpack recipe file
(`CraftingRecipes/dependencies/craftbot_modpack.json`) and points the
`craftbot_modpack` set at it. Regenerate it after a mod update:

```sh
python3 tools/filter_recipes.py \
  "$MOD_DATA/CraftingRecipes/craftbot.json" \
  CraftingRecipes/dependencies/craftbot_modpack.json \
  Scripts/smserver/production_blacklist.json
```

The tool removes a recipe when its output `itemId` or any ingredient is
blacklisted, so it also drops recipes that would consume blocked parts.

The Lua post-filter remains a second line of defence for sets registered
without a sanitized file. Blueprint/garage imports and already-placed shapes
are engine-level and are not retroactively removed; produce a clean production
save and avoid importing creations with blocked UUIDs.

## Save compatibility

A custom game save is a normal Scrap Mechanic SQLite save whose mod metadata
references this custom game. Server and every client need the mod installed.
Old "server software" saves reference missing workshop files and are not
compatible; start a new Custom Game save.

`tools/port_save.py` copies a survival SQLite save and rewrites its custom-game
metadata without touching the source. Validate the result in game.

## Security limits

Some issues are engine/client-authoritative and cannot be fixed in Lua: a
modified client can still spawn projectiles locally, and vanilla
container/garage interfaces do not validate distance server-side. This project
hardens every custom-game-controlled path and reachable Lua handler that
mutates server state, but cannot retroactively secure stock C++ behaviour.

Never commit Steam credentials, API tokens or server environment files. Keep
them in the deployment environment.

## Validation

Static checks:

```sh
python3 -m json.tool config.json >/dev/null
python3 -m json.tool description.json >/dev/null
python3 -m unittest discover -s tests -v

# Lua syntax for custom files (luac 5.4 parser is sufficient)
find Scripts/smserver Scripts/shared/api -name '*.lua' -print0 \
  | xargs -0 -n1 luac -p
luac -p Scripts/game/SurvivalGame.lua Scripts/game/SurvivalPlayer.lua \
  Scripts/game/interactables/CustomCrafter.lua
```

Live smoke test:

1. Delete the mod's `Cache` directory.
2. Launch a Custom Game world with the mod and its dependencies mounted.
3. Check the game log for Lua errors and for custom block/tool loading.
4. Verify a custom block places, the craftbot shows `craftbot_custom`, an admin
   command works, and the lift tool opens.
5. Re-check the save after a restart.

`-dedicated_server -open <save>` can instantiate stock scripts before UGC
scripts are mounted; use a normal client/world load when validating custom
script execution.

## Review notes

Findings from the 2026-10-29 review:

- `README.md` had grown to ~280 lines and duplicated architecture, security and
  installation detail. It is now player-facing; the details moved here.
- `Scripts/game` and `Scripts/terrain` are mostly verbatim stock copies. Only
  the four files listed above differ. This makes the repository large and
  noisy; keep the vendored tree only if self-containment is required.
- Dead/local artifacts: `Scripts/game/interactables/Crafter.lua.backup`,
  `Crafter.lua.backup2`, and `Scripts/game/loot/generate_loot_includes.bat`.
  They are not loaded by the game; remove them only after confirming no local
  workflow depends on them.
- `tests/` covers only save porting. There are no automated Lua or in-game
  tests, and CI does not syntax-check Lua files or validate dependency IDs.
- The lift is now a Workshop dependency; the previous local
  `lift_hardening`/`lift_config` implementation was removed.

Recommended cleanup, in order of risk:

1. Add a `tools/check_vendored_scripts.py` or CI job that diffs
   `Scripts/game`/`Scripts/terrain` against `$SURVIVAL_DATA/Scripts` and lists
   only intentional overrides.
2. Delete byte-identical stock copies once the diff check is green and the
   game is confirmed to resolve all classes from `$SURVIVAL_DATA`.
3. Add Lua syntax checks to CI when `luac` is available.
4. Remove the `.backup*` files and decide whether the loot `.bat` helper is
   still part of the build workflow.

## Publishing

Use the Scrap Mechanic **Mod Tool** to open this folder as a project and upload
it to Steam Workshop. Keep `description.json` fields stable:

- `type`: `Custom Game`
- `name`: player-facing name
- `localId`: stable UUID for this custom game
- `fileId`: updated by the upload flow after first publication

## Template attribution

The project structure and template assets originate from Scrap Mechanic's
official Survival Custom Game template. The MIT license covers the original
tooling and scripts added here; Scrap Mechanic and its template assets remain
subject to Axolot Games' terms.
