# Godot Manual Verification

## Verified Version

- `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe`
- `4.7.stable.official.5b4e0cb0f`

## Manual Check

1. Open `C:\Users\donny\Desktop\hearthvale_godot` in Godot 4.7.
2. Run `scenes/main.tscn`.
3. Start from the login screen.
4. Confirm the world appears with account, tile, selection, feedback, inventory, equipment, skills, quests, and state tabs.
5. Click resources, stations, mobs, drops, NPCs, the bank, and the shop to verify the same surfaces covered by the smoke scripts.

## Automated Smoke Reference

Use the scripts documented in `docs/smoke_verification_workflow.md`. On this PC, include `--log-file .godot_logs\<name>.log`; the no-log headless variant crashes before script execution because Godot cannot create its default `user://logs` directory.
