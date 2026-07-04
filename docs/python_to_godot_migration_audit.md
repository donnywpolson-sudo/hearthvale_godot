# Python To Godot Migration Audit

## Scope

Old source read-only path: `C:\Users\donny\Desktop\hearthvale`

New Godot repo path: `C:\Users\donny\Desktop\hearthvale_godot`

Audit date: 2026-07-03

Allowed write scope: this report only.

This is a first-pass migration audit. It compares by gameplay and content concept, not by raw filename, and treats the Python project as a behavioral/content reference rather than code to copy. Recommendations below should be implemented as Godot-native work in later changes.

## Commands Used

```powershell
Get-Location
git status --short
Get-ChildItem -Force
Get-ChildItem -Force C:\Users\donny\Desktop\hearthvale
rg --files .
rg --files C:\Users\donny\Desktop\hearthvale
Get-Content -Raw data\items.json
Get-Content -Raw data\recipes.json
Get-Content -Raw data\skills.json
Get-Content -Raw data\world.json
Get-Content -Raw data\quests.json
@'<structured JSON comparison script>'@ | python -
rg -n -i "runescape|osrs|stardew|runite|\brune\b|\brunes\b" C:\Users\donny\Desktop\hearthvale\game C:\Users\donny\Desktop\hearthvale\docs C:\Users\donny\Desktop\hearthvale_godot\data C:\Users\donny\Desktop\hearthvale_godot\docs
rg -n "^(class|def) |^    def " C:\Users\donny\Desktop\hearthvale\game\systems C:\Users\donny\Desktop\hearthvale\game\engine C:\Users\donny\Desktop\hearthvale\game\world C:\Users\donny\Desktop\hearthvale\game\entities C:\Users\donny\Desktop\hearthvale\game\ui
rg -n "^(func|class_name|const|var|signal) " scripts autoload
Get-Content -Raw docs\migration_notes.md
Get-Content -Raw docs\core_gameplay_parity.md
Get-Content -Raw docs\economy_quest_parity.md
Get-Content -Raw docs\playable_shell_parity.md
Get-Content -Raw docs\3d_presentation_pass.md
Get-Content -Raw docs\save_state_parity.md
Get-Content -Raw docs\ui_state_display_parity.md
Get-Content -Raw docs\asset_conversion_inventory.md
Get-Content -Raw docs\smoke_verification_workflow.md
Get-ChildItem C:\Users\donny\Desktop\hearthvale\tests
Get-ChildItem C:\Users\donny\Desktop\hearthvale\game\tools
Get-Content -Raw C:\Users\donny\Desktop\hearthvale\reports\design\CARPENTRY_SKILL_SPEC.md
Get-Content -Raw C:\Users\donny\Desktop\hearthvale\PROJECT_OUTLINE.md
Get-Content -Raw C:\Users\donny\Desktop\hearthvale\game\engine\validation.py
rg -n "validate|protected|asset_manifest|property|capacity|pathfind|poison|burn|telemetry|playtest|report|simulation|dialog|quantity|cooldown|respawn|chance|success" scripts autoload docs data
rg -n "burn|chance|capacity|respawn|poison|range|passive|attack_seconds|success|cooldown|quantity|dialog|telemetry|pathfinding|blocked" C:\Users\donny\Desktop\hearthvale\game\systems C:\Users\donny\Desktop\hearthvale\game\engine C:\Users\donny\Desktop\hearthvale\game\world
Get-Content -Raw C:\Users\donny\Desktop\hearthvale\game\tools\smoke_progression.py
Get-Content -Raw C:\Users\donny\Desktop\hearthvale\game\tools\playtest_sim.py
Get-ChildItem C:\Users\donny\Desktop\hearthvale\tests | Measure-Object
Get-ChildItem C:\Users\donny\Desktop\hearthvale\game\tools | Measure-Object
Get-ChildItem scripts -Filter *.gd | Measure-Object
Get-ChildItem docs -Filter *.md | Measure-Object
Test-Path docs\python_to_godot_migration_audit.md
```

## Executive Summary

The core portable content migrated cleanly. The five main data files are canonically identical between old Python and new Godot:

| File | Old summary | New summary | Canonical status |
| --- | --- | --- | --- |
| `items.json` | 112 items | 112 items | Identical |
| `recipes.json` | 4 smelting, 12 smithing, 22 carpentry, 9 herbalism recipes | Same | Identical |
| `skills.json` | 14 skills | 14 skills | Identical |
| `world.json` | 37 resources, 33 decorations, 12 mobs, 19 NPCs | Same | Identical |
| `quests.json` | 19 quests | 19 quests | Identical |

The most valuable leftovers are not raw data files. They are Python-side behavior depth, validation discipline, property-style test coverage, playtest simulation, reports, and presentation assets/animation intent that were intentionally not ported.

Biggest gaps worth migrating next:

- Data validation and originality/asset-reference checks have no Godot-native equivalent yet.
- Godot smoke checks are narrower than the old Python progression smoke, property tests, and playtest simulation.
- Gameplay is playable but simplified: immediate actions, deterministic results, no full pathfinding, partial capacity handling, simplified combat/status effects, and no full transaction/dialogue UI.
- Old Panda3D `.egg` models and JSON animation specs remain valuable as reference, but should be converted or recreated, not copied directly.
- Existing prototype drift remains: `magic_logs` is still present in active data and should be renamed before building more high-tier wood content around it.

Recommended next implementation step: port the old Python validation intent into a Godot-side or standalone repo-local validator for `data/*.json` and `assets/asset_manifest.json`, then add a Godot smoke that fails on broken item, skill, recipe, world, quest, asset, and protected-term references.

## Inventory Summary

Python project highlights:

- `game/data/*.json`: migrated exactly into Godot.
- `game/assets/audio`, `icons`, `sprites`, `textures`: copied into Godot with import sidecars generated by Godot.
- `game/assets/models/*.egg`: not copied; Panda3D-native models require conversion or replacement.
- `game/assets/animations/*.json`: not copied; useful as animation intent only.
- `game/systems`, `game/engine`, `game/world`, `game/entities`, `game/ui`: large behavior reference surface.
- `tests`: 48 Python test files, including property/capacity, interaction, validation, HUD, quest, save, combat, gathering, bank, shop, asset, and world tests.
- `game/tools`: 16 Python tools, including validation, smoke progression, playtest simulation, world/quest/economy reports, asset audit, telemetry summary, and repo-intelligence utilities.

Godot project highlights:

- `data`: exact copy of the five core gameplay JSON files.
- `assets`: copied portable PNG/WAV assets plus Godot `.import` sidecars.
- `scripts`: 12 `.gd` scripts covering shell, world, gameplay core, HUD, save state, and smoke checks.
- `docs`: 10 current migration/parity/smoke docs before this audit.
- `scenes`: Godot start, main, world, and HUD scenes.
- `autoload/state_store.gd`: reset Godot save/state layer.

Excluded or deprioritized old material:

- `.git`, `.agents`, `.codex`, `.pytest_cache`, `.venv`, `.vscode`, `__pycache__`
- `build`, `dist`, launcher output, `Hearthvale.spec`, `requirements.txt`
- old Python runtime entrypoints, Panda3D launch flow, and packaging
- `users.db`, `saves`, `logs`, `telemetry`, generated reports, and local runtime state
- Python save migration code except as a historical reference, because Godot save compatibility was intentionally reset

## Migration Matrix

| Area | Python source | Godot target | Status | Value | Recommendation |
| --- | --- | --- | --- | --- | --- |
| Core data/content | `game/data/*.json` | `data/*.json` | Migrated | High | Keep as source content; future edits need validation parity. |
| Portable art/audio | `game/assets/audio`, `icons`, `sprites`, `textures` | `assets/` | Migrated | High | Wire more icons/audio into runtime UI and feedback. |
| Panda3D models | `game/assets/models/*.egg` | none yet | Missing valuable | Medium | Convert or recreate as original Godot `.glb`/`.gltf` assets; do not depend on Panda3D runtime. |
| Animation specs | `game/assets/animations/*.json` | none yet | Missing valuable | Medium | Translate intent into Godot `AnimationPlayer`, state machines, or imported clips. |
| Data validation | `game/engine/validation.py`, `game/tools/validate_data.py`, validation tests | no equivalent beyond smoke checks | Missing valuable | Very high | Port validation rules to Godot or a standalone repo-local script. |
| Progression smoke | `game/tools/smoke_progression.py` | focused Godot smoke scripts | Partially migrated | Very high | Add broader Godot smoke coverage for capacity, quest reward blocking, sounds, persistence, and core-loop sequences. |
| Playtest simulation | `game/tools/playtest_sim.py` | none yet | Missing valuable | High | Rebuild as Godot-native/headless simulation once systems stabilize. |
| Reports | `world_report.py`, `quest_report.py`, `economy_report.py`, `skill_balance_audit.py`, `asset_audit.py` | none yet | Missing valuable | Medium | Port only the reports that guide Godot data balancing and asset QA. |
| Save/account | `game/engine/save.py`, `auth.py`, `users.db` | `autoload/state_store.gd` | Partially migrated / Reject old compatibility | Medium | Keep reset Godot saves; do not port Python account DB or legacy migration unless explicitly requested. |
| Inventory/equipment | `game/systems/inventory.py`, `equipment.py`, property tests | `gameplay_core.gd`, `state_store.gd`, `hud.gd` | Partially migrated | High | Strengthen capacity, stackability, equip/unequip, item use, examine, and drop paths. |
| Bank/shop/economy | `bank.py`, `shop.py`, app transaction UI | one-click Godot actions | Partially migrated | High | Add transaction dialogs, quantity controls, sell-all/buy capacity feedback, and stronger tests. |
| Gathering/cooking/processing | `gathering.py`, `cooking.py`, `smithing.py`, interaction timers | immediate Godot actions | Partially migrated | High | Add timed actions, success/burn chances, respawns, quantity processing, cancellation, and clear feedback. |
| Combat/training | `combat.py`, `combat_training.py`, combat app hooks | simplified click combat | Partially migrated | High | Add cadence, hit chance, range behavior, training styles, status effects, passive training targets, and richer drops/feedback. |
| Pathfinding/world interaction | `world/grid.py`, `pathfinding.py`, `map.py`, `interaction.py` | direct click-to-tile movement | Partially migrated | High | Add blocked-tile routing and interaction range pathing using Godot-native navigation/grid logic. |
| NPC dialogue/quests | `quest.py`, app dialogue hooks, quest tests | HUD feedback quest flow | Partially migrated | Medium | Add dialogue panels, clearer objective feedback, reward capacity recovery UI, and quest-specific tests. |
| UI/HUD | `game/ui/hud.py`, `login.py`, HUD tests | `hud.gd`, `start_screen.gd` | Partially migrated | High | Port useful UI interactions, icon display, compact state, full feedback history/chat, and transaction/dialogue panels. |
| Telemetry/diagnostics | `telemetry.py`, `summarize_telemetry.py` | none yet | Later | Medium | Consider after core systems stabilize; keep local-only. |
| Repo-intelligence/RAG tooling | `repo_intelligence.py`, `repo_rag.py` | none | Later / Reject runtime | Low | Not game-runtime migration; only reuse if repo-analysis tooling is still desired. |
| Launcher/packaging | `launcher`, `Hearthvale.spec`, `requirements.txt`, `python -m game.main` | Godot project workflow | Obsolete | Low | Do not migrate unless a Godot export/package task is requested. |

## High-Value Migration Candidates

### P0: Data Validation And Drift Guard

Old source:

- `C:\Users\donny\Desktop\hearthvale\game\engine\validation.py`
- `C:\Users\donny\Desktop\hearthvale\game\tools\validate_data.py`
- `C:\Users\donny\Desktop\hearthvale\tests\test_validation.py`

Current Godot equivalent:

- Smoke checks load and exercise data, but there is no comprehensive data validator.

What is valuable:

- Required keys and type checks for items, skills, recipes, quests, world objects, drops, shop stock, NPC quest links, asset manifests, icon refs, duplicate IDs, tile bounds, blocked overlaps, and protected-term scans.

Required transformation:

- Reimplement as a Godot-side smoke script or small standalone validator that reads `data/*.json` and `assets/asset_manifest.json`.
- Keep the old rules as intent, not code to paste.

Risk/drift notes:

- Old validator contains protected-term policy and legacy Python assumptions. Keep the policy, drop Python runtime coupling.

Suggested implementation size:

- Small-to-medium, high value.

### P0: Stronger Godot Progression Smoke

Old source:

- `game/tools/smoke_progression.py`
- related tests for bank, shop, inventory, quest, save, combat, gathering, cooking, smithing, and HUD.

Current Godot equivalent:

- `scripts/core_gameplay_smoke.gd`
- `scripts/economy_quest_smoke.gd`
- `scripts/save_roundtrip_smoke.gd`
- `scripts/ui_state_smoke.gd`

What is valuable:

- The old smoke checks capacity guards, quest reward blocking/recovery, sound hooks, save round trips, bank/shop round trips, level-up feedback, equipment persistence, and multi-step progression.

Required transformation:

- Add one or more focused Godot smokes that cover the same behavior promises using current `gameplay_core.gd` and `state_store.gd`.

Risk/drift notes:

- Do not reintroduce Python save compatibility, Panda3D fakes, or app scaffolding.

Suggested implementation size:

- Medium.

### P0: Inventory, Reward, And Transaction Capacity Guarantees

Old source:

- `game/systems/inventory.py`
- `game/systems/bank.py`
- `game/systems/shop.py`
- `tests/test_inventory_properties.py`
- `tests/test_bank_properties.py`
- `tests/test_equipment_properties.py`
- `tests/test_smithing_properties.py`

Current Godot equivalent:

- `autoload/state_store.gd`
- `scripts/gameplay_core.gd`
- `scripts/hud.gd`

What is valuable:

- Preventing item duplication/loss, enforcing slot capacity, preserving stackability rules, and blocking rewards/actions cleanly when inventory is full.

Required transformation:

- Add Godot-native helpers and smoke coverage around inventory transactions before expanding content.

Risk/drift notes:

- Avoid over-porting Python object model. Keep a simple dictionary state shape if that remains the Godot architecture.

Suggested implementation size:

- Medium, high return.

### P1: Pathfinding And Interaction Range

Old source:

- `game/world/grid.py`
- `game/world/pathfinding.py`
- `game/world/map.py`
- `game/systems/interaction.py`

Current Godot equivalent:

- `scripts/world.gd` direct click-to-tile movement and direct interaction dispatch.

What is valuable:

- Blocked-tile routing, adjacent interaction paths, water/obstacle avoidance, and range-aware combat positioning.

Required transformation:

- Implement Godot-native grid pathing or navigation logic using `world.json` blocked, water, resource, and decoration state.

Risk/drift notes:

- Keep it scoped to current grid world; do not import Panda3D world objects.

Suggested implementation size:

- Medium.

### P1: Timed Action And Respawn Semantics

Old source:

- `game/systems/gathering.py`
- `game/systems/cooking.py`
- `game/systems/smithing.py`
- `game/world/map.py`

Current Godot equivalent:

- Immediate action methods in `scripts/gameplay_core.gd`.

What is valuable:

- Action duration, cancellation, node depletion, respawn timing, quantity processing, success chance, burn chance, secondary drops, and better feedback.

Required transformation:

- Add per-action pending state to Godot gameplay, update it during process ticks, and persist necessary world state.

Risk/drift notes:

- Balance formulas should be reviewed for originality and fun, not copied blindly.

Suggested implementation size:

- Medium-to-large.

### P1: Bank, Shop, Inventory, And Dialogue UI

Old source:

- `game/engine/app.py`
- `game/ui/hud.py`
- `game/ui/login.py`
- related HUD and interaction tests.

Current Godot equivalent:

- `scripts/hud.gd`
- `scripts/start_screen.gd`
- one-click station and NPC actions in `gameplay_core.gd`.

What is valuable:

- Quantity selection, item examine/drop/use, equip/unequip, buy/sell-all, transaction feedback, dialogue panels, and richer quest objective presentation.

Required transformation:

- Build Godot UI panels and signals around existing dictionary state and gameplay core.

Risk/drift notes:

- Preserve original Hearthvale tone and avoid copying old styled UI if it is too inspiration-game-adjacent.

Suggested implementation size:

- Medium.

### P1: Prototype Drift Cleanup

Old source:

- `reports/design/CARPENTRY_SKILL_SPEC.md`
- active data in both projects.

Current Godot equivalent:

- `data/items.json`
- `data/skills.json`
- `data/recipes.json`
- `data/world.json`

What is valuable:

- The old design note explicitly flags `magic_logs` as prototype drift and suggests an original replacement before future high-tier Carpentry expands.

Required transformation:

- Make a scoped Godot data rename pass with validation and save-state consideration.

Risk/drift notes:

- This touches active content. Do it separately from system work.

Suggested implementation size:

- Small-to-medium.

### P2: Combat Depth And Status Effects

Old source:

- `game/systems/combat.py`
- `game/systems/combat_training.py`
- combat sections of `game/engine/app.py`
- combat tests.

Current Godot equivalent:

- Simplified combat in `scripts/gameplay_core.gd`.

What is valuable:

- Attack cadence, hit/miss, style-specific XP, range behavior, status effects, consumable effects, enemy respawns, player defeat handling, and feedback/audio hooks.

Required transformation:

- Incrementally deepen combat in Godot with smoke coverage per mechanic.

Risk/drift notes:

- Keep formulas original and readable; do not port old formulas without design review.

Suggested implementation size:

- Large.

### P2: Visuals, Models, And Animations

Old source:

- `game/assets/models/*.egg`
- `game/assets/animations/*.json`
- `game/world/visuals.py`
- `game/world/animation.py`

Current Godot equivalent:

- `scripts/world.gd` low-poly placeholder mesh generation.

What is valuable:

- Model silhouettes, animation intent, hit/impact/projectile/float text/respawn feedback, and material/visual hierarchy.

Required transformation:

- Recreate or convert into original Godot resources. Prefer `.glb`/`.gltf`, `AnimationPlayer`, materials, particles, and scene subresources.

Risk/drift notes:

- `.egg` is Panda3D-specific. Treat as reference or conversion input only.

Suggested implementation size:

- Large.

### Later: Local Playtest Simulation And Reports

Old source:

- `game/tools/playtest_sim.py`
- `game/tools/world_report.py`
- `game/tools/quest_report.py`
- `game/tools/economy_report.py`
- `game/tools/skill_balance_audit.py`
- `game/tools/asset_audit.py`

Current Godot equivalent:

- No direct equivalent beyond focused smokes and docs.

What is valuable:

- Seeded playtest loops, action success rates, failure reasons, XP gained, final inventory/bank/equipment summaries, and static balance/coverage reports.

Required transformation:

- Rebuild only after the Godot gameplay loop has enough parity to simulate honestly.

Risk/drift notes:

- Do not port old repo-intelligence or reporting frameworks unless the specific report answers an active Godot balancing or QA question.

Suggested implementation size:

- Medium-to-large, lower priority than validators and smokes.

## Obsolete Or Rejected Material

Reject or keep out of the Godot migration unless explicitly requested:

- Python/Panda3D launcher flow, `python -m game.main`, `requirements.txt`, `Hearthvale.spec`, `build`, and `dist`.
- Python account database behavior and `users.db`.
- Python legacy save migration aliases. This includes old `runite` compatibility aliases in `game/engine/save.py`; Godot save compatibility was intentionally reset.
- `.venv`, `.pytest_cache`, `__pycache__`, `.vscode`, logs, saves, telemetry, generated reports, and local runtime outputs.
- Repo-intelligence/RAG tooling as game-runtime work.
- Direct source-code copying from Python systems into GDScript.

## Drift And IP Cleanup Review

Protected-term scan findings:

- Godot hits were limited to policy/reference docs, including `docs/3d_presentation_pass.md` and `docs/source_reference/python_assets_README.md`.
- Python source hits included protected-term validator policy, repo-intelligence policy strings, and legacy save migration aliases.
- Old handoff archive hits included historical phrasing that should not guide new presentation work.

Candidate drift:

- `magic_logs` remains active in copied data. The old Carpentry spec marks it as prototype drift. Rename or redesign before adding higher-tier wood content that depends on it.
- Old design language that asks for a presentation pass toward an inspiration-game look should be ignored. Current Godot work should preserve original Hearthvale names, lore, assets, and UI.

Safe migration rule:

- Extract intent and gameplay value. Do not copy proprietary-looking names, formulas, quest beats, UI styling, maps, icons, art, or music from any inspiration game.

## Prioritized Backlog

| Priority | Candidate | Why |
| --- | --- | --- |
| P0 | Godot data/asset/originality validator | Highest leverage before more content changes; prevents broken references and drift. |
| P0 | Broader Godot progression smoke | Captures old high-value behavior guarantees without porting Python runtime. |
| P0 | Inventory/reward/transaction capacity checks | Prevents item loss/duplication and quest reward edge-case regressions. |
| P1 | Pathfinding and interaction range | Makes the 3D shell feel materially more playable. |
| P1 | Timed actions, respawns, success/burn chances | Restores grind pacing and resource-loop feel. |
| P1 | Bank/shop/dialogue panels and quantity UI | Replaces one-click placeholder economy/quest UX with real game interactions. |
| P1 | Scoped `magic_logs` original-name cleanup | Avoids building more content on known prototype drift. |
| P2 | Deeper combat, training styles, status effects | Valuable, but broader and formula-sensitive. |
| P2 | Convert/recreate models and animations | High presentation value, but larger art/technical scope. |
| Later | Playtest simulation and economy/world/quest reports | Useful once Godot systems are less placeholder. |
| Reject | Python launcher, account DB, legacy saves, packaging | Does not fit the reset Godot project. |

## Recommended Next Implementation Step

Implement a Godot-side validation smoke first:

1. Read `data/items.json`, `data/skills.json`, `data/recipes.json`, `data/world.json`, `data/quests.json`, and `assets/asset_manifest.json`.
2. Validate required keys, references, duplicate IDs, tile bounds, shop stock, quest NPC links, recipe inputs/outputs, item skill requirements, asset keys, and protected-term drift.
3. Add it to `docs/smoke_verification_workflow.md` only after it exists and passes.

This is the safest next step because it does not change gameplay behavior, directly protects future migration work, and converts one of the strongest old Python leftovers into a Godot-relevant gate.
