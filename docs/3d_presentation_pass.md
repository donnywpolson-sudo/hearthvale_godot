# 3D Presentation Pass

This pass replaces the flat 2D placeholder world with a minimal 3D Godot presentation while keeping the existing save/state/gameplay/economy/quest systems.

## Implemented

- `scenes/world.tscn` now uses `Node3D`.
- `scripts/world.gd` now uses:
  - `CharacterBody3D` player placeholder
  - perspective third-person `Camera3D` looking forward/down at the player
  - click-to-move raycast against the ground plane
  - `W/A/S/D` camera pan relative to the camera angle, `Q/E` camera rotate, mouse wheel zoom
  - classic default/context interactions: left-click default actions, right-click object options
  - 3D ground tiles for grass, path, and water
  - readable low-poly placeholders for resources, NPCs, mobs, bank, shop, and stations
  - 3D selection and destination markers
  - object labels that appear only for the current selection to keep the world readable
- The world still emits the same gameplay signals consumed by `gameplay_core.gd`.
- The HUD panel is narrower and shorter so it no longer dominates the viewport.

## Behavior Kept

- Save/load and state binding
- Login/start flow
- Object click/select and interaction dispatch
- Gathering, processing, combat, drops, XP, bank, shop, NPC dialogue, quests, and rewards
- Existing smoke script entry points

## Design Boundary

This is an original classic top-down RPG presentation pass. It does not copy RuneScape assets, names, map layouts, UI, or proprietary content.

## Remaining Gaps

- Player, NPC, mob, station, and resource visuals are still generated placeholder meshes, but now use distinct silhouettes and material families.
- There are no walk/combat/gathering animations yet.
- Movement is still direct click-to-tile travel, not full pathfinding around blocked tiles.
- Terrain is generated from individual placeholder tiles, not a production terrain/mesh pipeline.
- HUD and labels are cleaner, but still utilitarian and not final game UI.

## Verification

Focused smoke command:

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/playable_shell_smoke.gd --log-file .godot_logs\playable_shell_3d.log
```

Observed output:

```text
Hearthvale playable shell smoke passed.
```

Additional regression checks passed after the 3D conversion:

- `boot_flow_smoke.gd`
- `core_gameplay_smoke.gd`
- `economy_quest_smoke.gd`
- `ui_state_smoke.gd`

Manual check:

1. Open `C:\Users\donny\Desktop\hearthvale_godot` in Godot 4.7.
2. Run `scenes/main.tscn`.
3. Click Start.
4. Confirm the world is 3D with a visible player character.
5. Left-click or right-click empty ground to move.
6. Left-click visible resources, NPCs, mobs, bank, shop, or stations and confirm the default action runs.
7. Right-click an object and confirm the option menu appears.
