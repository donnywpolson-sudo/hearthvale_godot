# Save And State Layer

Step 4 implements the first Godot save/state layer. Save compatibility is reset, so this project does not include Python legacy migration helpers.

## Godot State Surface

- Account state: `account.username`, `account.created_at`, `account.last_login_at`
- Player state: `player.tile`, `player.position`, `camera`
- Inventory: `inventory`
- Bank: `bank`
- Equipment: `equipment`
- Quest progress: `quest_progress`, mirrored to `quest_state` and `world.quest_state`
- Settings: `settings`
- Combat/world/time scaffolding: `combat`, `world`, `time`
- Save/load path: `user://saves/<sanitized_username>.json`
- Backup path on overwrite: `user://saves/<sanitized_username>.json.bak`

## Python Reference Comparison

Matched intentionally:

- JSON save files
- per-user save paths
- sanitized save filenames
- starter inventory tools
- empty bank and equipment
- default skills, including level 10 hitpoints
- player start tile/position
- camera defaults
- combat/world/time scaffolding
- backup before overwrite

Intentional parity deltas:

- Godot save schema starts at `hearthvale_godot_reset_v1` / version `1`; Python is save version `6`.
- Python legacy migrations are omitted because Step 1 chose reset save compatibility.
- Python SQLite account/password storage is not ported in Step 4; the Godot shell stores only local account metadata in the save state.
- Inventory slot limits and item stackability rules are deferred until gameplay/UI systems are ported.
- Godot uses `user://saves` instead of the Python repo-local `saves/` directory.

## Verification

Focused smoke command:

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/save_roundtrip_smoke.gd --log-file .godot_logs\save_roundtrip_step9.log
```

Observed output:

```text
Hearthvale save round-trip smoke passed.
```

The smoke writes to `res://.godot_smoke_saves` through a test-only `StateStore.save_dir` override. Normal runtime still uses `user://saves`.
