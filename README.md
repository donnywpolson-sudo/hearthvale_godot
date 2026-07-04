# Hearthvale Godot

Godot 4 migration shell for Hearthvale.

This repository is a fresh Godot destination with save compatibility reset. The original Python project at `C:\Users\donny\Desktop\hearthvale` remains the read-only reference implementation for later migration steps.

Verified local engine: `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe` (`4.7.stable.official.5b4e0cb0f`).

## Current Workflow

Run the main scene in Godot:

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --path .
```

Run focused smoke checks with an explicit log file:

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/boot_flow_smoke.gd --log-file .godot_logs\boot_flow.log
```

See `docs/smoke_verification_workflow.md` for the full Step 9 smoke list and parity deltas.

## Current Presentation

The current playable view is a minimal 3D scene with a visible `CharacterBody3D` player, isometric camera, 3D tile markers, and 3D placeholders for resources, NPCs, mobs, bank, shop, and stations. It is a systems-backed prototype, not final art.

See `docs/3d_presentation_pass.md` for the current 3D scope and remaining visual gaps.
