# Hearthvale Prototype

A small Panda3D vertical slice for a single-player, low-poly, top-down RPG about gathering, crafting, combat, shops, banking, and long-term character progression. It uses committed art where available with procedural fallback geometry for the rest.

Root docs: `AGENTS.md` is the authoritative rules file, `CODEX_HANDOFF.md` is compact mutable continuation state, `PROJECT_OUTLINE.md` is the roadmap/reference, and this `README.md` is the user-facing entry point.

## Setup

```powershell
py -3.11 -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

## Run

For development or troubleshooting, run the game module directly:

```powershell
python -m game.main
```

To build the Windows launcher:

```powershell
.\launcher\build_launcher.ps1
```

The launcher build requires PyInstaller in the project virtual environment. The
build script does not install it by default; install it explicitly with
`.venv\Scripts\python.exe -m pip install pyinstaller`, or rerun the build script
with `-InstallBuildDependencies` to allow that install step.

Then run the built launcher from the project folder:

```powershell
.\dist\Hearthvale.exe
```

If you move the launcher to the Desktop, it will look for `hearthvale` or
`Hearthvale` next to it. For other locations, set `HEARTHVALE_PROJECT_ROOT` to
this checkout before running it.
`Launch Game.bat`, if present, is only an optional manual fallback for running
`python -m game.main`.

## Test

```powershell
python -m pytest
python -m game.tools.validate_data
python -m game.tools.skill_balance_audit
python -m game.tools.playtest_sim --seed 7 --steps 16
python -m game.tools.idle_profile --seconds 30
python -m game.tools.world_tiled export --output-dir reports/world_tiled
python -m game.tools.world_report --write
python -m game.tools.quest_report --write
python -m game.tools.economy_report --write
python -B -m game.tools.smoke_progression
```

`game.tools.smoke_progression` is a non-GUI smoke check for the shipped
gather/cook/use/sell/bulk-bank/combat loop, gathering capacity guard, Carpentry
capacity guard, bank capacity guard, loot capacity guard, full-health food
guard, shop buy/sell-all path, shop capacity guard, quest reward capacity guard,
and the level-up feedback path plus the Workshop order and Practice gear quest
paths. It writes only to temporary storage for its save/load round trip.

## Repo Intelligence RAG

The repo intelligence tool can build a local, offline semantic index over safe
project text files. It uses a deterministic standard-library hashed lexical
embedding backend by default and writes only under `reports/repo_intelligence`.

```powershell
python -B -m tools.repo_intelligence scan
python -B -m tools.repo_intelligence rag-index
python -B -m tools.repo_intelligence rag-status
python -B -m tools.repo_intelligence rag-search "bank persistence"
python -B -m tools.repo_intelligence rag-answer "What evidence proves inventory persists through save/load?"
```

RAG indexing skips private saves/accounts, telemetry/logs, virtualenvs, caches,
build outputs, packaged artifacts, binary assets, and generated reports by
default. Optional embedding backends must already be installed and explicitly
selected; the default path does not call network APIs or require API keys.

## World Authoring

`python -m game.tools.world_tiled export --output-dir reports/world_tiled` writes
a Tiled-compatible snapshot of `game/data/world.json` with editable terrain and
object layers. After editing the exported map in Tiled, import it back with:

```powershell
python -m game.tools.world_tiled import --map-path reports/world_tiled/world.tiled.json --output-path game/data/world.from_tiled.json
```

## World Report

`python -m game.tools.world_report` prints a reachability and placement audit for structures, NPCs, mobs, and resource nodes. Add `--write` to save `reports/world/world_report_latest.md`.

## Quest Report

`python -m game.tools.quest_report` prints quest coverage, quest givers, and reward totals from `game/data/quests.json` plus the current world NPC links. Add `--write` to save `reports/quests/quest_report_latest.md`.

## Economy Report

`python -m game.tools.economy_report` combines skill balance, quest reward totals, and current shop stock prices into one balance-oriented report. Add `--write` to save `reports/economy/economy_report_latest.md`.

## Asset Audit

```powershell
python -m game.tools.asset_audit --write
```

This reports missing manifest files, item/skill icon coverage, orphaned manifest-backed art, and direct texture/model/animation inventory under `game/assets`.
It writes `reports/assets/asset_audit_latest.md`.

## Workflow Docs

- [AGENTS.md](AGENTS.md) is the authoritative operating rulebook for Codex work in this repo.
- [PROJECT_OUTLINE.md](PROJECT_OUTLINE.md) is the non-authoritative roadmap and contract reference.
- [CODEX_HANDOFF.md](CODEX_HANDOFF.md) is compact current continuation state; older handoff history belongs under `docs/handoff_archive/`.

## Manual Smoke Checklist

After code or data changes that affect gameplay reachability, run `python -m game.main`
and verify:

- Gathering gives items and XP, depletes a node, and later respawns it.
- Bank opens from the bank booth and can deposit and withdraw an item stack.
- Shop opens from a shop object and can sell a selected inventory stack.
- Combat starts from a monster, updates player health, grants combat XP, and drops loot.
- Quest dialogue starts or advances a quest and completion rewards apply once.
- `F5` saves, `F9` loads, and the visible inventory, bank, skills, quest, and combat state persist.
- Built launcher starts the same game entry point when launcher behavior changes.

## Controls

- This checkout shows the local login screen at startup. Set
  `AUTO_LOGIN_USERNAME` in `game/settings.py` to a local username only when you
  want development auto-login.
- Enter a username and password, then select `Register` to create a local account.
- Select `Login` to enter the game with an existing local account.
- Press Tab in the username field to move focus to the password field.
- Press Enter in the password field to attempt login.
- Select `Quit` on the login screen to close the prototype.
- `WASD`: pan camera
- `Q` / `E`: rotate camera
- Mouse wheel: zoom camera
- Hover tiles, objects, and scenery to show their name in the top-center status box.
- Left click ground: move player to a tile
- Left click gameplay objects: perform the default action
- Left click scenery: walk to that tile or adjacent to blocked scenery
- Right click ground, gameplay objects, or scenery: choose an action
- Bottom event log `Up` / `Down`: scroll through previous messages
- In-game `File` menu: save, load, or quit
- In-game `Settings` button: toggle the compact HUD layout, ambient audio playback, or ambient volume.
- `F5`: save the currently logged-in account
- `F9`: load the currently logged-in account
- `Esc`: no quit action; use `File` then `Quit` to close the game while playing
- `I` / `C` / `K`: toggle inventory, clothes/equipment, and skills tabs

## Local Account Data

The login/register screen is local-only. This is not an online MMO account
system yet: there is no server, multiplayer, networking, cloud sync, email
recovery, or real-money/security-sensitive account flow.

Local accounts are stored in `users.db`. Passwords are never stored in
plaintext; each account stores a random per-user salt and a PBKDF2-HMAC
password hash.

Character saves are stored per account in `saves/<username>.json`, after making
the username safe for use as a filename. The `saves/` directory is created
automatically when needed.

## Current MVP Features

- 100x100 scalable tile world with the current starter area, grass, dirt paths, blocked rocks, trees, copper rocks, fishing spots, stumps, depleted rocks, shops, bank, crafting stations, NPCs, and monster spawns.
- Angled top-down camera independent from player movement.
- Left-click movement with grid A* pathfinding.
- Classic-style left/right click interactions for ground, gameplay objects, and scenery, including default actions, walk-to behavior, context menus, and examine options.
- Shared gathering activity system for woodcutting, mining, and fishing with JSON-defined XP, level requirements, item rewards, tiered depletion, respawn state, and required starter tools.
- Data-driven inventory display, bottom-right skills/equipment tabs, bankable coin item stack, fixed daytime HUD readout, in-game Settings toggle, File menu, and per-account save/load.
- Bank booth with deposit/withdraw stack handling and bulk bank smoke coverage.
- Shop panel for specific stack sales, buy/sell-all paths, capacity guards, and coin feedback.
- Basic combat skills, equipment requirements, combat-style gates, readable combat feedback, and loot pickup coverage.
- Carpentry recipes and starter quests, including Practice gear and Workshop order paths.
- Local JSONL telemetry and deterministic summary tooling for offline playtest diagnostics.
- Data validation and read-only skill balance auditing for `items.json`, `skills.json`, `world.json`, `recipes.json`, `quests.json`, and asset manifest references.

## Current Development Focus

- Keep root workflow docs concise and current while archiving long handoff history.
- Expand original starter-area content in small, testable increments.
- Improve asset, audio, animation, and map coverage under the license rules in [docs/icon_asset_options.md](docs/icon_asset_options.md).
