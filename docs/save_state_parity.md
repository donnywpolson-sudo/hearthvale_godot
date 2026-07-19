# Save And State Layer

The active save contract is `hearthvale_godot_v2`, version `2`. Python save compatibility remains intentionally reset; only prior Godot v1 saves migrate.

## Godot State Surface

- Account state: `account.username`, case-insensitive `account.key`, `account.created_at`, `account.last_login_at`
- Player state: `player.tile`, `player.position`, `camera`
- Inventory: `inventory`
- Bank: `bank`
- Equipment: `equipment`
- Canonical quest progress: `quest_state.active_quest_id` and `quest_state.quests`
- Settings: `settings`
- Canonical combat/effects/time: top-level `combat`, `active_effects`, and `time`; `world` contains resource/cooldown/action-clock state only
- Save/load path: `user://saves/<sanitized_username>.json`
- Transaction paths: validated `.tmp`, primary `.json`, and last validated `.json.bak`
- Autosave: one-second debounce after gameplay/world changes, plus orderly-exit flush

## Python Reference Comparison

Matched intentionally:

- JSON save files
- per-user save paths
- sanitized, case-insensitive local account filenames while preserving display capitalization
- starter inventory tools
- empty bank and equipment
- default skills, including level 10 hitpoints
- player start tile/position
- camera defaults
- combat/world/time scaffolding
- validation before promotion and a recoverable validated backup

Intentional parity deltas:

- Godot v1 (`hearthvale_godot_reset_v1`) migrates once to `hearthvale_godot_v2`; Python saves remain unsupported.
- Python legacy migrations are omitted because Step 1 chose reset save compatibility.
- Python SQLite account/password storage is not ported in Step 4; the Godot shell stores only local account metadata in the save state.
- V1 migration prefers nested `quest_state.quests`, then `quest_progress`, then flat legacy quest state; top-level combat wins over `world.combat`.
- Godot uses `user://saves` instead of the Python repo-local `saves/` directory.

## Failure And Recovery Rules

- A save is serialized to `.tmp`, flushed, re-read, schema-validated, and only then promoted.
- Only a validated primary is rotated to `.bak`. Failed promotion restores the previous primary.
- Loading tries the primary and then the backup. Corrupt or ambiguous existing data is never replaced with a default account.
- Multiple legacy files claiming the same case-insensitive account fail closed.
- Runtime action timers record active play only; closing the game does not advance cooldowns, buffs, resources, or mob respawns.

## Verification

Focused smoke command:

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/save_roundtrip_smoke.gd --log-file .godot_logs\save_roundtrip_step9.log
```

Observed output:

```text
Hearthvale save round-trip smoke passed.
```

The deeper persistence matrix is `res://scripts/persistence_v2_smoke.gd`; runtime autosave and real-frame timing are covered by `res://scripts/runtime_integration_smoke.gd`.

The smoke writes to `res://.godot_smoke_saves` through a test-only `StateStore.save_dir` override. Normal runtime still uses `user://saves`.
