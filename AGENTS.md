# Hearthvale Godot Agent Guide

## Project Vision

Hearthvale is an original, grindable single-player RPG prototype with simple controls, progression, skilling, combat, gathering, crafting, inventory management, NPC interaction, quests, shops, banking, economy, and long-term account growth.

Do not copy RuneScape/OSRS/Stardew proprietary assets, names, dialogue, maps, quests, icons, music, formulas, or copyrighted content. Do not add new branded or near-branded terms such as RuneScape, OSRS, Stardew, rune, runite, or direct equivalents. Use inspiration games only for broad progression structure and game feel.

Some migrated reference data may still contain prototype drift from earlier work. When touching nearby code or data, flag that drift and prefer original Hearthvale names, progression curves, world lore, assets, and UI text.

## Working Defaults

- Keep work focused on the user's latest request.
- Prefer small, safe, reviewable changes.
- Read targeted files only; search before opening many files.
- Use concise summaries instead of long copied output.
- Implement directly when the task is clear.
- Plan first for broad, risky, destructive, or ambiguous work.
- Ask only when needed to avoid wrong, unsafe, or destructive changes.

## Repository Safety

- Before editing, run `Get-Location` and `git status --short` from `C:\Users\donny\Desktop\hearthvale_godot`.
- Do not overwrite, revert, delete, move, rename, stage, commit, or push unless explicitly asked.
- Do not run destructive commands unless explicitly approved.
- Preserve user work, generated verification logs, local saves, imported assets, and existing migration notes unless the task explicitly requires touching them.
- If files are dirty, work with those changes and do not assume they are yours.
- Keep `C:\Users\donny\Desktop\hearthvale` read-only unless the user explicitly requests a Python repo edit.

## Godot Project Facts

- Destination repo: `C:\Users\donny\Desktop\hearthvale_godot`.
- Source reference: `C:\Users\donny\Desktop\hearthvale`; use it only as a read-only behavioral and content reference.
- Godot version: 4.7 stable.
- Local Godot executable: `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe`.
- Save compatibility with the Python project was intentionally reset; do not add Python save migration unless explicitly requested.
- Main scene workflow: open or run the Godot project from this repo and launch `scenes/main.tscn`.
- Headless smoke checks require an explicit project-local log file:

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/<smoke>.gd --log-file .godot_logs\<smoke>.log
```

- See `docs/smoke_verification_workflow.md` for the current smoke list and parity gaps.
- `.godot_logs/` and `.godot_smoke_saves/` are generated verification state and should stay untracked.

## Core Design Goals

Prioritize features that make the game feel more playable, grindable, and complete:

1. Core loop: gather -> process/craft -> sell/use -> level up -> unlock better content.
2. Skill progression with XP, levels, unlocks, and meaningful rewards.
3. Simple but satisfying combat.
4. Inventory, equipment, drops, shops, and banking.
5. NPCs, dialogue, quests, and world interaction.
6. Clear UI feedback for actions, XP, levels, loot, errors, saves, and unlocks.
7. Incremental content additions over broad rewrites.

## Implementation Rules

- Prefer small, shippable increments that reuse existing Godot scenes, scripts, autoloads, data files, and UI patterns.
- Keep gameplay content data-driven in `data/*.json` where practical.
- Keep a clear separation between game state, gameplay rules, scenes, HUD/UI, assets, and persistence.
- Avoid broad rewrites, unused abstractions, speculative future work, and new dependencies unless clearly justified.
- Do not present old Python/Panda3D setup as current workflow. The new project should not rely on `requirements.txt`, Panda3D, pytest as the primary stack, `python -m game.main`, PyInstaller launcher builds, `Hearthvale.spec`, Python `users.db` migration, or old `game/engine/save.py` rules.
- For visual work, keep the current original 3D direction and avoid copying proprietary assets, maps, UI, icons, names, or formulas from inspiration games.

## Testing Rules

- Run the smallest relevant Godot smoke check first.
- Use the `--log-file` smoke command pattern above; this local Windows Godot build can fail before script execution without it.
- The Windows root certificate warning is non-blocking if the smoke assertion prints its expected passed message.
- For visible gameplay or UI changes, provide short manual verification steps.
- Run `git diff --check` before finalizing edits.
- Report exact commands run and meaningful pass/fail results.

## Handoffs

- Use repo-local `CODEX_HANDOFF.md` only for meaningful multi-step work or fresh-thread continuation.
- Do not create or update handoff files for simple one-shot tasks.
- Treat handoff files as mutable continuation state, not proof; reconcile them against current files, command output, and git status.
- If `CODEX_HANDOFF.md` is updated, keep the latest status, validation, blockers, and next recommended step easy to find.
