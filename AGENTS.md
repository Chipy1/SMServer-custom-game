# AGENTS.md

Repository rules for coding agents and contributors working on **SM Custom
Game**, a Scrap Mechanic Custom Game.

Read `README.md` for the player-facing overview and `TECHNICAL.md` for
architecture, dependency loading, hardening and known limits. This file is the
working contract: what to change, what not to touch, and how to verify.

## Hard constraints

- Target **Scrap Mechanic 1.0.6.889**. Game Lua is Lua 5.1-era; do not use
  Lua 5.4-only syntax in shipped scripts.
- Keep `description.json` `localId` and all content UUIDs stable. Changing a
  UUID breaks saves, blueprints and Workshop references.
- Keep the mod idempotent: `Cache/` is generated, ignored, and must never be
  committed. Logs, credentials and `.env` files are forbidden.
- Preserve the stock survival loop. Custom game code extends stock scripts; it
  must not replace stock behaviour without a concrete requirement.
- The modified Lift is the Workshop dependency **atstd lift**
  (`fileId 3829430797`). Do not reimplement it locally.
- All privileged network handlers must validate the **network caller** with
  `smserver_getNetworkCaller(...)`, not trust a player object in the payload.
  Add range/ownership/admin checks at the server boundary.

## Repository map

| Path | Role |
| --- | --- |
| `config.json` | Custom Game entrypoints (`SurvivalGame`, `SurvivalPlayer`) |
| `description.json` | Workshop metadata and dependencies |
| `Scripts/game/` | Mostly vendored stock survival scripts; only four files are custom |
| `Scripts/smserver/` | Custom block runtime, network helpers, blocklist |
| `Scripts/shared/api/` | Vendored `std.class` and weak-table helpers |
| `Scripts/terrain/` | Verbatim stock terrain scripts |
| `CraftingRecipes/` | Custom recipes and sanitized Modpack recipes |
| `Objects/`, `Gui/`, `ScriptableObjects/` | Custom content and metadata |
| `tools/` | Save porting and recipe filtering |
| `tests/` | Python tests for save porting |

Custom game files that differ from stock on 1.0.6.889:

- `Scripts/game/SurvivalGame.lua`
- `Scripts/game/SurvivalPlayer.lua`
- `Scripts/game/interactables/CustomCrafter.lua`
- `Scripts/game/quests/BosstrainQuest.lua`

Do not add new gameplay code to the vendored stock tree. Prefer
`Scripts/smserver/` or a new custom directory, and document the entrypoint in
`TECHNICAL.md`.

## Validation

Run these before yielding:

```sh
python3 -m json.tool config.json >/dev/null
python3 -m json.tool description.json >/dev/null
python3 -m unittest discover -s tests -v

# Syntax-check every custom Lua file.
find Scripts/smserver Scripts/shared/api -name '*.lua' -print0 \
  | xargs -0 -n1 luac -p
luac -p Scripts/game/SurvivalGame.lua Scripts/game/SurvivalPlayer.lua \
  Scripts/game/interactables/CustomCrafter.lua
```

If `luac` is unavailable, say so explicitly and rely on an in-game load test.
A syntax check is not proof of behaviour.

For a behavioural change, add or update a focused Python test when the logic
can be tested outside the game. For Lua/gameplay changes, run a live smoke test:

1. Delete the mod's `Cache` directory.
2. Launch a Custom Game world with all dependencies mounted.
3. Check the game log for Lua errors and expected custom load messages.
4. Exercise the changed block, command or tool and restart the save once.

`-dedicated_server -open <save>` may instantiate stock scripts before UGC
scripts are mounted. Use a normal client/world load for custom-script
validation.

## Change workflow

1. Read the relevant section of `TECHNICAL.md`; do not infer stock API
   behaviour from a filename.
2. Find the smallest existing pattern and reuse it. Custom blocks live in
   `Scripts/smserver/`; network hardening uses `smserver_*` helpers.
3. Make the minimal edit. Do not refactor vendored stock files while fixing a
   custom path.
4. Validate JSON, Lua syntax and Python tests.
5. Update `TECHNICAL.md` for architecture changes and `README.md` only for
   player-visible changes.
6. Remove throwaway scripts, temporary diagnostics and generated caches.

## Review checklist

- Caller identity, admin rights, distance and ownership are checked
  server-side; no client-supplied player is trusted.
- UUIDs, `localId` and recipe set names are unchanged unless the task requires
  a migration.
- New recipes are registered and unlocked, and blocked items are filtered from
  both Lua maps and the shipped recipe file.
- `Cache/`, `Logs/`, `*.pyc`, credentials and local paths are not committed.
- `README.md` stays short; details belong in `TECHNICAL.md`; agent workflow
  belongs here.
- The behaviour was exercised, not just compiled. State exactly what was run.

## Known pitfalls

- `sm.isHost` is a property in some stock scripts and a function in others;
  match the surrounding API.
- Lua classes copy inherited methods at class creation. Patching a base class
  after a subclass is created does not update the subclass.
- `sm.isServerMode()` may not be usable at file-load time; prefer installing
  server hooks from `server_onCreate` or a guaranteed server path.
- The game can keep stale compiled scripts in `Cache/`; delete that directory
  after changing Lua or databases.
- Dependency mods mount transitively, but their content is only available at
  `$CONTENT_<localId>` after UGC installation; do not hardcode local paths.
- The Modpack recipe grid is engine-loaded; filtering only in Lua leaves grid
  entries visible. Keep the sanitized recipe file in sync.
