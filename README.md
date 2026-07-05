# Hearthvale Godot

Hearthvale is a single-player RPG prototype built in Godot 4.7.

This is the active Godot version of the project. The older Python project at
`C:\Users\donny\Desktop\hearthvale` is only a read-only reference.

## Quick Start

1. Open Godot:
   `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe`
2. Choose this project folder:
   `C:\Users\donny\Desktop\hearthvale_godot`
3. Press Play.

The game starts from `scenes/main.tscn`.

## What Is Playable

The current version is a systems prototype, not final art.

It already includes a simple 3D world, player movement, gathering, processing,
combat, drops, XP, inventory, equipment, shops, banking, NPC dialogue, quests,
saving, and loading.

## How To Use Codex Here

You can ask Codex for normal game improvements in plain English, for example:

- "Make gathering feel better and verify it still works."
- "Add more shop items using the existing data style."
- "Fix confusing UI text in the inventory."
- "Run the smallest smoke check for the thing you changed."

Codex should keep changes small, use this Godot repo as the active project, and
treat the old Python repo as read-only reference material.

## Useful Files

- `scenes/main.tscn` - main game scene
- `data/*.json` - items, skills, recipes, quests, and world data
- `scripts/` - Godot gameplay and UI scripts
- `docs/smoke_verification_workflow.md` - technical verification notes
- `docs/3d_presentation_pass.md` - current 3D presentation notes

## Technical Commands

Most of the time, use the Godot editor instead of these commands. These are
mainly for Codex or manual verification.

Run the project from PowerShell:

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --path .
```

Run one smoke check:

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/boot_flow_smoke.gd --log-file .godot_logs\boot_flow.log
```

For the full smoke check list, see `docs/smoke_verification_workflow.md`.
