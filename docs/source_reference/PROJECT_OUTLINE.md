# Hearthvale Project Outline

The project is rooted in `AGENTS.md`, `CODEX_HANDOFF.md`, `README.md`, and this `PROJECT_OUTLINE.md`. `AGENTS.md` is the authoritative operating rulebook. This outline is a compact, non-authoritative roadmap for project direction, protected contracts, and phase ordering. It does not approve broad rewrites, risky changes, generated-art refreshes, or destructive cleanup by itself.

## Authority Order

1. `AGENTS.md`: active repo rules, safety policy, validation policy, final-response format, and project constraints.
2. Current user request: active scope and approval gates.
3. `CODEX_HANDOFF.md`: compact continuation state for multi-step work.
4. `README.md`: user-facing setup, run, test, feature, and controls orientation.
5. `PROJECT_OUTLINE.md`: roadmap and reference only.

If this outline conflicts with `AGENTS.md`, follow `AGENTS.md` unless the user explicitly approves a scope change.

## Mission

Build an original, grindable single-player RPG prototype where the core loop is:

Gather -> process/craft -> sell/use -> level up -> unlock better content.

The project should steadily improve skill progression, inventory, equipment, drops, shops, banking, gathering nodes, crafting, combat, NPC dialogue, quests, UI feedback, local save/load reliability, and playtestability.

## Protected Contracts

- Stack: Python 3.11, Panda3D, pytest.
- Run command: `python -m game.main`.
- Full test command: `python -m pytest`.
- Data validation command: `python -m game.tools.validate_data`.
- Progression smoke command: `python -B -m game.tools.smoke_progression`.
- Main data files: `game/data/items.json`, `game/data/skills.json`, `game/data/world.json`, `game/data/recipes.json`, and `game/data/quests.json`.
- Asset manifest: `game/assets/asset_manifest.json`.
- Save/account files: local `users.db`, `saves/<username>.json`, and legacy `savegame.json`.
- Save/versioning code: `game/engine/save.py`.
- Data validation code: `game/engine/validation.py`.
- Main source: `game/`.
- Tests: `tests/`.

## Development Rules

- Prefer small, shippable increments that reuse existing systems.
- Keep gameplay content data-driven in `game/data/*.json` where practical.
- Add or update focused tests for changed logic.
- Provide manual smoke steps for visible gameplay changes.
- Preserve original names, content, UI text, maps, quests, art, audio, balancing, and progression curves.
- Do not add dependencies, online accounts, networking, cloud sync, real-money flows, model training, or automated optimization without explicit approval.

## Data And Save Rules

- When changing data schemas or adding content fields, update `game/engine/validation.py`, add focused tests, and run `python -m game.tools.validate_data`.
- When changing save shape, update migration logic in `game/engine/save.py`, preserve older save compatibility, respect or bump `SAVE_VERSION`, and add save migration tests.
- Local account behavior must stay local-only unless the user explicitly changes scope.
- Do not inspect, print, mutate, stage, or delete `users.db`, `saves/`, raw telemetry, or logs unless the task explicitly requires it.

## Originality Rules

All new content must be original Hearthvale content. Do not copy proprietary names, near-branded substitutes, map layouts, formulas, quest beats, dialogue, icons, music, or art from inspiration games. If older prototype drift is touched, prefer a scoped rename or migration path rather than expanding the drift.

## Generated Artifact Policy

Generated and local runtime outputs should normally stay out of version control:

- `reports/audit/`
- `reports/repo_intelligence/`
- `reports/telemetry/`
- `telemetry/*.jsonl`
- `logs/`
- `saves/`
- `users.db` and sidecar database files
- `build/`, `dist/`, launcher build output, and spec files
- cache folders and binary runtime artifacts

Some generated artifacts may already be tracked from prior history. Do not remove or refresh tracked generated artifacts unless the user explicitly approves that cleanup.

## Phase Roadmap

1. Foundation and drift review: keep workflow docs, validation gates, and source-of-truth boundaries clear.
2. Core loop expansion: improve gather -> process/craft -> sell/use -> level progression.
3. Inventory, banking, shops, and economy: prevent duplication/loss and improve transaction feedback.
4. Combat, equipment, and loot: keep combat readable and rewarding.
5. Quests, NPCs, and world interaction: add small original quests that teach existing systems.
6. UI feedback and readability: make state, errors, loot, XP, unlocks, and saves obvious.
7. Save, account, telemetry, and tooling reliability: harden local persistence and offline diagnostics.
8. Assets, audio, animation, and packaging: improve presentation with original or properly licensed assets.
9. Performance and playtest smoothness: improve responsiveness without changing gameplay semantics accidentally.
10. Content balance and starter-area readiness: tune early XP, prices, drops, quests, and unlock pacing.
11. Readiness review: decide whether to continue feature work, run a playtest pass, clear blockers, or pause for user decision.

## Phase Gates

Each implementation phase should end with files changed, commands run, validation results, manual test steps when behavior is visible, unresolved blockers, and the exact next recommended step only when real follow-up remains.

Do not promote work as ready if validation did not run and should have, data validation fails, save migration compatibility is untested, visible behavior lacks a manual smoke path, the result depends on generated local state, or the work introduces unapproved originality drift.
