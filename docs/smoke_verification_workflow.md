# Smoke Verification Workflow

Step 9 recreates the lightweight verification workflow on the Godot side. The Python repo at `C:\Users\donny\Desktop\hearthvale` remains the read-only behavioral reference.

## Local Godot Command Pattern

This local Godot 4.7 build crashes before script execution if it tries to create its default `user://logs` directory. Run smoke checks with an explicit project-local log file:

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/<smoke>.gd --log-file .godot_logs\<smoke>.log
```

The root certificate warning printed by Godot on this PC does not affect these smoke assertions.

## Focused Checks

| Area | Script | Expected output |
| --- | --- | --- |
| Boot/start flow | `res://scripts/boot_flow_smoke.gd` | `Hearthvale boot flow smoke passed.` |
| Save/load | `res://scripts/save_roundtrip_smoke.gd` | `Hearthvale save round-trip smoke passed.` |
| 3D movement and object interaction shell | `res://scripts/playable_shell_smoke.gd` | `Hearthvale playable shell smoke passed.` |
| Inventory/equipment/skills/state UI | `res://scripts/ui_state_smoke.gd` | `Hearthvale UI state smoke passed.` |
| Gathering, processing, combat, drops, XP | `res://scripts/core_gameplay_smoke.gd` | `Hearthvale core gameplay smoke passed.` |
| Bank, shop, NPC dialogue, quests, rewards | `res://scripts/economy_quest_smoke.gd` | `Hearthvale economy and quest smoke passed.` |
| Asset manifest fallback paths | `res://scripts/asset_fallback_smoke.gd` | `Hearthvale asset fallback smoke passed.` |

## Step 9 Result

All focused checks passed with `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe`.

The save smoke overrides `StateStore.save_dir` to `res://.godot_smoke_saves` so verification writes inside this workspace. Normal runtime still defaults to `user://saves`.

## Python Reference Parity

Matched intentionally:

- Boot enters a start/login scene, then creates or loads local account state and enters the world.
- Save/load persists account, player, inventory, bank, quest, settings, skills, combat, world, and time state as JSON.
- Movement and click interaction use the classic default/context split: empty ground clicks walk, left-click performs default object actions, and right-click opens object options.
- Inventory/equipment/skills/HUD panels mirror current player state.
- Gathering, cooking, processing, combat, drops, XP, and level-up reward state mutate from copied JSON data.
- Bank, shop, NPC dialogue, quest progression, and quest rewards work end-to-end from copied data.
- Asset fallback defaults exist for missing icons/effects, and copied art/audio paths are present.

Remaining parity gaps:

- Godot visuals are now minimal 3D placeholders; Panda3D model conversion, production animations, and final art are not ported.
- Movement has direct tile travel and no Python pathfinding/blocked-tile routing yet.
- Gameplay actions are immediate and deterministic; Python timing, success chances, burn chance, respawns, richer combat formulas, and status effects are simplified.
- Bank/shop use first-valid one-click transactions instead of full transaction dialogs.
- Quest dialogue is HUD feedback only, not a full dialogue UI.
- Inventory capacity and reward-capacity handling are partial compared with the Python property tests.
- Asset fallback verification checks manifest/file availability; runtime icon/audio binding into every UI surface remains future polish.
