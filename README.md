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

The project explicitly uses Godot's OpenGL Compatibility renderer for stable
Windows startup on this PC. This avoids relying on the default Vulkan renderer
when running the editor or an exported `Hearthvale.exe`.

## What Is Playable

The current version is a systems prototype, not final art.

It already includes a simple 3D world, player movement, gathering, processing,
combat, drops, XP, inventory, equipment, shops, banking, NPC dialogue, quests,
saving, and loading.

Progress is saved automatically one second after gameplay, movement, or camera
changes, and pending progress is flushed on an orderly exit. Local account names
are case-insensitive (`Alice` and `alice` open the same save) while the original
display capitalization is retained. If both the primary save and its backup are
invalid, the start screen reports the problem instead of overwriting the account.

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
New-Item -ItemType Directory -Force .godot_logs | Out-Null
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/boot_flow_smoke.gd --log-file .godot_logs\boot_flow.log
```

Windows export readiness:

The project includes a `Windows Desktop` export preset targeting x86_64. Install
the matching Godot 4.7 export templates from the editor before exporting, then
run:

```powershell
New-Item -ItemType Directory -Force .godot\export | Out-Null
New-Item -ItemType Directory -Force .godot_logs | Out-Null
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --export-release 'Windows Desktop' .godot\export\Hearthvale.exe --log-file .godot_logs\windows_export.log
```

  The output is kept under `.godot/` so local build artifacts remain ignored. A
  content-only PCK can be tested without platform templates with:

  ```powershell
  New-Item -ItemType Directory -Force .godot_logs | Out-Null
  & 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --export-pack 'Windows Desktop' .godot\export\Hearthvale.pck --log-file .godot_logs\windows_pack_smoke.log
  ```

  This validates project packing, not the exported Windows executable.

  For a repeatable export-and-launch check after templates are installed, run:

  ```powershell
  .\_ai_audit_workflow\_internal\run_export_platform_smoke.ps1
  ```

For the full smoke check list, see `docs/smoke_verification_workflow.md`.
