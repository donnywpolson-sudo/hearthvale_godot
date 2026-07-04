# Codex Handoff

## Current Status

- Destination repo: `C:\Users\donny\Desktop\hearthvale_godot`.
- Source reference: `C:\Users\donny\Desktop\hearthvale`; keep it read-only.
- Godot executable used for verification: `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe`.
- Save compatibility remains reset; no Python save migration helpers were added.
- All Step 9 focused Godot smoke checks passed with the `--log-file` workaround.
- The flat 2D placeholder world has been replaced with a minimal 3D presentation shell.

## Verification Workflow

Read `docs/smoke_verification_workflow.md` first. It lists the focused checks for boot, save/load, movement, interaction, inventory UI, gathering, combat, bank, shop, quests, and asset fallback behavior.

## Important Local Notes

- Headless Godot without `--log-file` crashes before project script execution on this machine because it cannot create `user://logs`.
- Save smoke checks set `StateStore.save_dir` to `res://.godot_smoke_saves`; normal runtime still uses `user://saves`.
- `.godot_logs/` and `.godot_smoke_saves/` are ignored generated verification state.
- Read `docs/3d_presentation_pass.md` before continuing visual or movement work.
