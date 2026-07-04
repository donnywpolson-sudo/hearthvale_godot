# Smoke Verification Workflow

Step 9 recreates the lightweight verification workflow on the Godot side. The Python repo at `C:\Users\donny\Desktop\hearthvale` remains the read-only behavioral reference.

## Local Godot Command Pattern

This local Godot 4.7 build crashes before script execution if it tries to create its default `user://logs` directory. Run smoke checks with an explicit project-local log file:

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/<smoke>.gd --log-file .godot_logs\<smoke>.log
```

The root certificate warning printed by Godot on this PC does not affect these smoke assertions.

Run broad smoke batches one script at a time. After each Godot command, check for leftover Godot processes and stop only those stale PIDs before starting the next smoke:

```powershell
Get-Process | Where-Object { $_.ProcessName -like '*Godot*' } | Select-Object Id,ProcessName,CPU,StartTime
Stop-Process -Id <stale_pid> -Force
```

## Focused Checks

| Area | Script | Expected output |
| --- | --- | --- |
| Boot/start flow | `res://scripts/boot_flow_smoke.gd` | `Hearthvale boot flow smoke passed.` |
| Save/load | `res://scripts/save_roundtrip_smoke.gd` | `Hearthvale save round-trip smoke passed.` |
| 3D movement and object interaction shell | `res://scripts/playable_shell_smoke.gd` | `Hearthvale playable shell smoke passed.` |
| Blocked-tile routing and near-tile interaction range | `res://scripts/pathfinding_interaction_smoke.gd` | `Hearthvale pathfinding interaction smoke passed.` |
| Godot-native visual-kind recreation coverage | `res://scripts/visual_recreation_smoke.gd` | `Hearthvale visual recreation smoke passed.` |
| Inventory/equipment/skills/state UI | `res://scripts/ui_state_smoke.gd` | `Hearthvale UI state smoke passed.` |
| Bank, shop, and NPC interaction panels | `res://scripts/interaction_panel_smoke.gd` | `Hearthvale interaction panel smoke passed.` |
| Gathering, processing, combat, drops, XP | `res://scripts/core_gameplay_smoke.gd` | `Hearthvale core gameplay smoke passed.` |
| Combat status effects, training style XP, and persistence | `res://scripts/combat_depth_smoke.gd` | `Hearthvale combat depth smoke passed.` |
| Timed actions, resource respawns, and deterministic chances | `res://scripts/timed_action_smoke.gd` | `Hearthvale timed action smoke passed.` |
| Bank, shop, NPC dialogue, quests, rewards | `res://scripts/economy_quest_smoke.gd` | `Hearthvale economy and quest smoke passed.` |
| Progression regression, capacity, transactions, food, persistence | `res://scripts/progression_regression_smoke.gd` | `Hearthvale progression regression smoke passed.` |
| Data, asset, and originality validation | `res://scripts/data_validation_smoke.gd` | `Hearthvale data validation smoke passed.` |
| Asset manifest fallback paths | `res://scripts/asset_fallback_smoke.gd` | `Hearthvale asset fallback smoke passed.` |

## Step 9 Result

All focused checks passed with `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe`.

The save smoke overrides `StateStore.save_dir` to `res://.godot_smoke_saves` so verification writes inside this workspace. Normal runtime still defaults to `user://saves`.

The progression regression smoke expands the old Python progression-smoke intent into Godot-native assertions for full-inventory gather/drop blocking, stackable additions at capacity, gather -> process -> cook/smith progression, shop buy/sell capacity and affordability guards, bank deposit/withdraw and partial-withdraw round trips, all-or-nothing quest reward blocking and recovery, invalid transaction quantity guards, food healing/full-health guard behavior, level-up unlock feedback, equipment, drop pickup, and save round-trip preservation of inventory, bank, equipment, skills, combat/world, and quest state.

The timed action smoke checks that gather/cook/process actions cannot be repeated while their action timers are active, depleted resources stay unavailable until their data-driven respawn time has elapsed, and secondary resource rewards respect deterministic 0% and 100% success chances.

The interaction panel smoke checks that bank, shop, and NPC dialogue panels open through the HUD, show usable rows, and route deposit, withdraw, buy, sell, quest start, and quest completion requests through `gameplay_core.gd` without using the previous first-valid one-click placeholders.

The combat depth smoke checks that poison-capable mobs apply a persistent poison status, poison deals damage on later combat rounds, poison-cleansing consumables remove the status, combat training style routes XP to the selected style, and `combat.status_effects` survives a save/load round trip.

The visual recreation smoke checks that existing `world.json` mob `visual_kind` values produce distinct Godot-native procedural silhouettes without copying or bulk-converting old Panda3D `.egg` files.

The pathfinding interaction smoke checks that blocked/water tiles are rejected as destinations, blocking resources route to an adjacent walkable tile before activation, and NPC, bank, shop, and ground-drop interactions activate only from interaction range.

The data validation smoke reads `data/items.json`, `data/skills.json`, `data/recipes.json`, `data/world.json`, `data/quests.json`, and `assets/asset_manifest.json`. It fails on malformed or missing JSON, broken item/skill/recipe/quest/world/asset references, invalid core field types and ranges, obvious placement conflicts, missing manifest-backed assets, and protected-term drift in active data.

## Python Reference Parity

Matched intentionally:

- Boot enters a start/login scene, then creates or loads local account state and enters the world.
- Save/load persists account, player, inventory, bank, quest, settings, skills, combat, world, and time state as JSON.
- Movement and click interaction use the classic default/context split: empty ground clicks walk, left-click performs default object actions, and right-click opens object options.
- Click movement now uses a small Godot-native tile route around blocked/water/object tiles and object interactions can defer until the player reaches an adjacent walkable tile.
- Inventory/equipment/skills/HUD panels mirror current player state.
- Gathering, cooking, processing, combat, drops, XP, and level-up reward state mutate from copied JSON data.
- Bank, shop, NPC dialogue, quest progression, and quest rewards work end-to-end from copied data.
- Progression regression coverage now guards inventory capacity, stackable/non-stackable transaction checks, quest reward blocking/recovery, bank/shop edge cases, food use, equipment, drop pickup, and save persistence paths.
- Data, asset, quest, world, shop, mob, recipe, and originality references are validated by a Godot-side smoke.
- Asset fallback defaults exist for missing icons/effects, and copied art/audio paths are present.

Remaining parity gaps:

- Godot visuals now include distinct generated mob silhouettes by `visual_kind`; authored player/NPC/resource models, Panda3D model conversion, production animations, and final art are not ported.
- Movement uses simple cardinal tile routing over the shell map; it is not yet full production pathfinding with diagonal movement, dynamic obstacles, or action-specific ranges beyond the current one-tile interaction shell.
- Gameplay actions now have deterministic timer, respawn, and secondary-drop chance coverage; richer progress UI, cancellation, burn chance, randomized balance tuning, and richer combat formulas are still simplified.
- Combat now includes selected-style XP routing and a small poison status/cleanse loop; full enemy AI, encounter pacing, equipment rebalance, and broader status systems remain future work.
- Bank/shop/dialogue now use functional HUD panels for single/all deposit, withdraw, sell, single-item buy, quest start, and quest completion; quantity text entry, multi-buy, item-drop, unequip, and richer dialogue branching are still future work.
- Asset fallback verification checks manifest/file availability; runtime icon/audio binding into every UI surface remains future polish.
