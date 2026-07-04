# Migration Notes

## Step 2 Scope

- Destination: `C:\Users\donny\Desktop\hearthvale_godot`
- Repository model: fresh repo, no history continuity
- Save compatibility: reset
- Repo-local `.github` files: none to keep at this stage
- Source project: keep `C:\Users\donny\Desktop\hearthvale` read-only
- Gameplay porting: intentionally deferred

## Current Godot Shell

The project now contains a playable Godot 4.7 shell with focused smoke coverage:

- `project.godot`
- `scenes/main.tscn`
- `scenes/start.tscn`
- `scenes/world.tscn`
- `scenes/hud.tscn`
- `scripts/game_shell.gd`
- `scripts/gameplay_core.gd`
- focused smoke scripts under `scripts/`
- `assets/`
- `data/`
- `autoload/`
- `docs/`

Verified Godot executable: `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe`.

See `docs/smoke_verification_workflow.md` for the Step 9 verification workflow and remaining parity gaps.
