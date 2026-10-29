# SM Custom Game

A survival-based Custom Game for **Scrap Mechanic 1.0.6.889**. It keeps the
stock survival loop and adds the custom blocks, recipes, admin commands and
server-side hardening ported from the old "server software" custom game
(`3440826317`).

Validated locally on 1.0.6.889: custom blocks load, the `craftbot_custom`
category appears, ender chests work, and the admin commands pass server-side
checks.

## Features

- Five custom blocks: Ender Chest, hidden Sky Container, Generator, Sun-Light
  Panel and Private Block.
- Inventory/craftbot icons for all custom blocks.
- A `craftbot_custom` recipe category, plus SComputers and Modpack recipe
  integration.
- Server-side admin and utility commands (`/op`, `/tp`, `/give`, `/spawnpart`,
  `/ender`, ...).
- Network caller validation and per-block distance/ownership checks.
- The `atstd lift` tool, mounted as a Workshop dependency.

## Install

Copy the repository into the Scrap Mechanic user mods folder:

```text
%AppData%\Axolot Games\Scrap Mechanic\User\User_<steamid>\Mods\SM-CustomGame
```

On Linux/Proton:

```text
.../compatdata/387990/pfx/drive_c/users/steamuser/AppData/Roaming/
Axolot Games/Scrap Mechanic/User/User_<steamid>/Mods/SM-CustomGame
```

Launch Scrap Mechanic, open **Custom Games**, and select **SM Custom Game**.
Delete the mod's `Cache` directory after changing Lua or database files so the
game recompiles them.

## Dependencies

Declared in `description.json` and downloaded through Steam Workshop:

| Mod | fileId | Purpose |
| --- | --- | --- |
| SComputers [Fork] | `2949350596` | Lua computers and ClassHook |
| The Modpack Continuation | `2448492759` | Recipe/content pack |
| atstd lift | `3829430797` | Modified Lift tool; pulls `atstd lib` and shared resources |

Dependency recipes are not loaded by the stock game. `SurvivalGame` registers
the SComputers craftbot set, and `CustomCrafter` discovers every loaded
`craftbot_*` set at runtime.

## Commands

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

All privileged commands are enforced server-side. Handler and hardening
details live in [TECHNICAL.md](TECHNICAL.md).

## Documentation

- [TECHNICAL.md](TECHNICAL.md) — architecture, custom content, network
  hardening, dependency loading, blacklist, save porting, known limits.
- [AGENTS.md](AGENTS.md) — repository rules, validation commands and review
  checklist for contributors and coding agents.

## Saves and publishing

Custom Games use separate save files. Existing Survival saves are untouched.
`tools/port_save.py` can rewrite the custom-game metadata of a copied Survival
save; validate the result in game. Publish through the Scrap Mechanic Mod Tool
and keep the `localId` in `description.json` stable.

## Security

This repository must never contain Steam credentials, API tokens, or server
environment files. Keep those in the deployment environment only.

## License

The MIT license covers the tooling and scripts added here. Scrap Mechanic and
its template assets remain subject to Axolot Games' terms.
