# Smoke Verification Workflow

Step 9 recreates the lightweight verification workflow on the Godot side. The Python repo at `C:\Users\donny\Desktop\hearthvale` remains the read-only behavioral reference.

## Local Godot Command Pattern

This local Godot 4.7 build crashes before script execution if it tries to create its default `user://logs` directory. Run smoke checks with an explicit project-local log file:

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/<smoke>.gd --log-file .godot_logs\<smoke>.log
```

The root certificate warning printed by Godot on this PC does not affect these smoke assertions.

Run broad smoke batches one script at a time. After each Godot command, check for leftover Godot processes and stop only those stale PIDs before starting the next smoke:

```powershell
Get-Process | Where-Object { $_.ProcessName -like '*Godot*' } | Select-Object Id,ProcessName,CPU,StartTime
Stop-Process -Id <stale_pid> -Force
```

## Headless Playtest Simulation

Use the Godot-native playtest simulation runner for longer seeded automated playtest simulation bot runs that record bugs, softlocks, QOL annoyances, and balance signals. The clickable launcher publishes user-facing outputs directly under `.godot/ai_simulation/`, and detailed generated reports stay under `.godot/ai_simulation/archive/`.

For the simplest workflow, double-click `HEARTHVALE_AI_SIMULATION.bat` in the project root. It is the direct clickable project launcher, opens an interactive tier menu, shows command-line progress while Godot is running, publishes one timestamped Codex prompt and one same-timestamp JSON summary when publish safety allows it, then opens the prompt in Notepad so it can be pasted into Codex.

Clickable tiers:

- Strategy Smoke: estimated ~1 min, 12 runs, 150 steps, scenario/profile `all/default`, seed 1, trace `issues`, scenario probes `auto` -> smoke. This is the recommended first choice.
- Medium: estimated ~10 min, 1000 runs, 300 steps, scenario/profile `all/default`, scenario probes `auto` -> full. Use for normal balance and progression signal after the workflow is stable.
- Deep: estimated ~3 hr, 10000 runs, 720 steps, scenario/profile `all/coverage`, scenario probes `auto` -> full. Use for broad stochastic coverage.
- Overnight: estimated ~10 hr, 16000 runs, 1800 steps, scenario/profile `all/coverage`, scenario probes `auto` -> full. Use only for unattended sweeps.

Tier runtimes are estimates, not enforced caps. The launcher passes `--timeout-seconds 0` for built-in tiers so they can finish naturally.

`--seed` is the base seed. Each run uses `base_seed + run_index`, so `--runs 1000 --seed 1` covers seeds 1 through 1000. Increase `--runs` for more independent seeds. Increase `--steps` for longer play sessions within each seed.

Scenarios:

- `all`: rotate through every scenario.
- `core_loop`: gather, process, sell/use, and progression pressure.
- `quest_chaser`: NPC dialogue and quest start/complete flow.
- `economy_stress`: bank and shop transaction pressure.
- `combat_loot`: combat, drops, and recovery behavior.
- `inventory_pressure`: capacity, drop, bank, and cleanup behavior.
- `random_guard`: broader randomized guard path.

Trace modes:

- `issues`: compact default; records run summaries and replayable issue samples.
- `all`: verbose debug mode; also writes `trace.jsonl` with every bot action.

Balance profiles:

- `default`: broad coverage across every scenario.
- `progression`: emphasizes core loop, quest completion, XP, and inventory pressure.
- `economy`: emphasizes shop/bank pressure, coin flow, sell value, and net worth.
- `combat`: emphasizes combat, survival, recovery pressure, mob defeats, and loot value.
- `coverage`: broad coverage with extra random-guard pressure.

Scenario probes:

- `auto`: reduced deterministic probes for Strategy Smoke/custom/publish-smoke runs; full deterministic probes for Medium, Deep, and Overnight-sized runs.
- `off`: skip deterministic probes.
- `smoke`: run a reduced deterministic probe set for core loop, starter quest, combat/loot, economy, and inventory pressure.
- `full`: run the smoke probes plus broader skill, recipe, quest, and mob probes.

Scenario probes are report-only diagnostics inside `summary.json` and the generated prompt. They do not make the simulation exit nonzero unless the runner itself crashes or cannot write outputs. Focused smokes remain the pass/fail authority for protected behavior.

For automation or tuned runs, prefer the direct Godot command below. The root `.bat` accepts the same practical launch values as positional arguments when a clickable project-root launcher is more convenient:

```powershell
.\HEARTHVALE_AI_SIMULATION.bat 1000 300 1 all issues default 0 auto
```

The optional seventh `.bat` argument is timeout seconds. `0` disables the timeout; positive values restore a runtime cap for a specific run. The optional eighth argument is scenario probes: `auto`, `off`, `smoke`, or `full`.

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/playtest_simulation_runner.gd --log-file .godot_logs\playtest_simulation.log -- --runs 1000 --steps 300 --seed 1 --scenario all --trace issues --balance-profile default --scenario-probes auto --output-dir res://.godot/ai_simulation/_working/current --publish-latest --public-output-root res://.godot/ai_simulation --timeout-seconds 0
```

Replay a specific issue sample with the seed and scenario from `issues.jsonl`:

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/playtest_simulation_runner.gd --log-file .godot_logs\playtest_replay.log -- --runs 1 --steps 300 --seed <seed> --scenario <scenario> --trace all
```

Public outputs are exactly two files under `.godot/ai_simulation/`: `ai_simulation_codex_prompt_YYYY_MM_DD_HHMM.md` and `ai_simulation_data_YYYY_MM_DD_HHMM.json`. Use the prompt as the single Markdown handoff to paste into Codex; use the same-timestamp JSON file only when structured detail is needed. The timestamp is 24-hour local time, for example `ai_simulation_codex_prompt_2026_07_05_0357.md`. The new run's detailed internal reports are still copied into `.godot/ai_simulation/archive/<timestamp>/full_reports`. Internal reports include `runs.jsonl`, `issues.jsonl`, `summary.json`, `replay_manifest.json`, `telemetry_summary.json`, `balance_profiles.json`, `performance_observations.json`, `polish_telemetry.json`, `manual_polish_review.md`, `improvement_plan.md`, and `codex_prompt.md`; `summary.json` also includes the `scenario_probes` block and advisory 0-100 `scorecard` category scores with relevant metrics. `progress.json` is transient live status for the command-line progress bar. `trace.jsonl` is also written when trace mode is `all`, and issue samples can write JSON-safe failed-state snapshots under `snapshots/`. Simulation, scenario probe, scorecard, and polish findings are evidence candidates, not proof; verify each finding against current code, data, deterministic replay, focused smokes, or manual review before changing gameplay. By default the command exits `0` when the harness completes, even if it finds issues; add `--fail-on-issues` only when issue findings should fail the run. A successful command exit can also mean lower-coverage publishing was safely blocked; check `latest_publish_status` before assuming new public prompt/JSON files were written.

Read-only publish artifact checklist:

- Confirm the root `.godot/ai_simulation/ai_simulation_codex_prompt_YYYY_MM_DD_HHMM.md` prompt exists.
- Confirm the root `.godot/ai_simulation/ai_simulation_data_YYYY_MM_DD_HHMM.json` summary exists with the same timestamp as the prompt.
- Confirm the JSON summary includes a `trust` block.
- Confirm replay hashes exist through `replay_metadata.build_hash`, `replay_metadata.data_hashes`, and `replay_metadata.script_hashes`.
- Confirm `_working/current` is not cited as public evidence after a later run; it is disposable working output.

Generated reports include a `trust` block with `run_strength`, `coverage_scope`, `implementation_ready`, `harness_status`, `finding_status`, `latest_publish_status`, and replay hash guidance. `summary.json` also includes a `scorecard` block with advisory 0-100 category scores, confidence labels, score basis text, and the underlying metrics used for the score. `publish_smoke` reports are not implementation-ready and generated Markdown says so in the first screen. Publishing blocks lower-coverage output from becoming the most recent public output by default; set `HV_SIM_ALLOW_LATEST_DOWNGRADE=1` to allow that replacement, or `HV_SIM_REQUIRE_PUBLISH_LATEST=1` when a blocked publish should fail automation. When publishing is blocked and `HV_SIM_REQUIRE_PUBLISH_LATEST` is not set, the command may still exit successfully while leaving the public prompt/JSON pair unchanged. Replay evidence is valid only for the code/data hashes recorded in `replay_manifest.json`; if `build_hash`, any `data_hashes`, or any `script_hashes` differ, the replay is under changed code and cannot close the original issue by itself.

## Quality Tooling Ownership

Use `docs/codex_phase_driver_prompt.md` when advancing the broader quality/dev-tooling plan one phase at a time.

Keep simulation-specific work in `scripts/playtest_simulation_runner.gd` and its generated reports: deterministic replay metadata, AI director/chaos behavior, simulation-step invariant checks, local telemetry summaries, balance simulation profiles, scenario probe diagnostics, human-facing polish telemetry, failed-run state summaries, and advisory simulation performance observations.

Keep validators, golden scenario smokes, save/load torture smokes, debug command console, and debug overlays runnable without the simulation bot. Shared logic such as invariants or future snapshots should live in reusable helpers that both the focused smokes and simulation runner can call.

## Focused Checks

| Area | Script | Expected output |
| --- | --- | --- |
| Boot/start flow | `res://scripts/boot_flow_smoke.gd` | `Hearthvale boot flow smoke passed.` |
| Save/load | `res://scripts/save_roundtrip_smoke.gd` | `Hearthvale save round-trip smoke passed.` |
| 3D movement and object interaction shell | `res://scripts/playable_shell_smoke.gd` | `Hearthvale playable shell smoke passed.` |
| Blocked-tile routing and near-tile interaction range | `res://scripts/pathfinding_interaction_smoke.gd` | `Hearthvale pathfinding interaction smoke passed.` |
| Camera controls and minimap sync | `res://scripts/camera_minimap_smoke.gd` | `Hearthvale camera minimap smoke passed.` |
| Godot-native visual-kind recreation coverage | `res://scripts/visual_recreation_smoke.gd` | `Hearthvale visual recreation smoke passed.` |
| Inventory/equipment/skills/state UI | `res://scripts/ui_state_smoke.gd` | `Hearthvale UI state smoke passed.` |
| Bank, shop, and NPC interaction panels | `res://scripts/interaction_panel_smoke.gd` | `Hearthvale interaction panel smoke passed.` |
| Gathering, processing, combat, drops, XP | `res://scripts/core_gameplay_smoke.gd` | `Hearthvale core gameplay smoke passed.` |
| Combat status effects, training style XP, and persistence | `res://scripts/combat_depth_smoke.gd` | `Hearthvale combat depth smoke passed.` |
| Timed actions, resource respawns, and deterministic chances | `res://scripts/timed_action_smoke.gd` | `Hearthvale timed action smoke passed.` |
| Bank, shop, NPC dialogue, quests, rewards | `res://scripts/economy_quest_smoke.gd` | `Hearthvale economy and quest smoke passed.` |
| Golden fixed gameplay scenarios | `res://scripts/golden_scenarios_smoke.gd` | `Hearthvale golden scenarios smoke passed.` |
| Save/load torture scenarios | `res://scripts/save_load_torture_smoke.gd` | `Hearthvale save/load torture smoke passed.` |
| Dev-only debug command console | `res://scripts/debug_command_console_smoke.gd` | `Hearthvale debug command console smoke passed.` |
| Dev-only debug overlays | `res://scripts/debug_overlay_smoke.gd` | `Hearthvale debug overlay smoke passed.` |
| State snapshot/export/restore helpers | `res://scripts/state_snapshot_smoke.gd` | `Hearthvale state snapshot smoke passed.` |
| Progression regression, capacity, transactions, food, persistence | `res://scripts/progression_regression_smoke.gd` | `Hearthvale progression regression smoke passed.` |
| Data, asset, and originality validation | `res://scripts/data_validation_smoke.gd` | `Hearthvale data validation smoke passed.` |
| Asset manifest fallback paths | `res://scripts/asset_fallback_smoke.gd` | `Hearthvale asset fallback smoke passed.` |

## Step 9 Result

All focused checks passed with `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe`.

The save smoke overrides `StateStore.save_dir` to `res://.godot_smoke_saves` so verification writes inside this workspace. Normal runtime still defaults to `user://saves`.

The progression regression smoke expands the old Python progression-smoke intent into Godot-native assertions for full-inventory gather/drop blocking, stackable additions at capacity, gather -> process -> cook/smith progression, shop buy/sell capacity and affordability guards, bank deposit/withdraw and partial-withdraw round trips, all-or-nothing quest reward blocking and recovery, invalid transaction quantity guards, food healing/full-health guard behavior, level-up unlock feedback, equipment, drop pickup, and save round-trip preservation of inventory, bank, equipment, skills, combat/world, and quest state.

The golden scenarios smoke runs compact fixed scenarios for gather -> craft/process -> sell/use -> XP progression, inventory overflow and stackable-at-capacity behavior, quest start/objective/reward-blocking/completion, combat -> loot -> recovery, bank/shop round trips, shared state invariants, and save/load after meaningful progression.

The save/load torture smoke saves, reloads, and continues after combat/status effects, poison cleansing, quest reward blocking/completion, bank/shop transactions, full-inventory drop pickup blocking/recovery, and resource depletion/respawn state.

The debug command console is available in non-release/dev runs with F10 and remains independently smoke-testable. It supports `help`, `give_item`, `teleport`, `set_quest_state`, `set_skill`, `spawn_enemy`, `spawn_drop`, `heal`, `damage`, and `force_weather`.

The debug overlay is available in non-release/dev runs with F9 and remains independently smoke-testable. It shows player/destination tiles, object and blocked-tile counts, active path length, hitpoints, status count, quest counts, camera heading, and a compact tile map for water, blocked tiles, objects, path, destination, and player position.

The state snapshot smoke checks the reusable helper for in-memory capture, restore into an existing state dictionary, JSON-safe export to `.godot_logs`, import, and summary generation for player, inventory, bank, skills, quests, combat, and world state.

The timed action smoke checks that gather/cook/process actions cannot be repeated while their action timers are active, depleted resources stay unavailable until their data-driven respawn time has elapsed, and secondary resource rewards respect deterministic 0% and 100% success chances.

The interaction panel smoke checks that bank, shop, and NPC dialogue panels open through the HUD, show usable rows, and route deposit, withdraw, buy, sell, quest start, and quest completion requests through `gameplay_core.gd` without using the previous first-valid one-click placeholders.

The combat depth smoke checks that poison-capable mobs apply a persistent poison status, poison deals damage on later combat rounds, poison-cleansing consumables remove the status, combat training style routes XP to the selected style, and `combat.status_effects` survives a save/load round trip.

The visual recreation smoke checks that existing `world.json` mob `visual_kind` values produce distinct Godot-native procedural silhouettes without copying or bulk-converting old Panda3D `.egg` files.

The pathfinding interaction smoke checks that blocked/water tiles are rejected as destinations, blocking resources route to an adjacent walkable tile before activation, and NPC, bank, shop, and ground-drop interactions activate only from interaction range.

The data validation smoke reads `data/items.json`, `data/skills.json`, `data/recipes.json`, `data/world.json`, `data/quests.json`, and `assets/asset_manifest.json`. It fails on malformed or missing JSON, broken item/skill/recipe/quest/world/asset references, invalid core field types and ranges, obvious placement conflicts, missing manifest-backed assets, and protected-term drift in active data.

## Python Reference Parity

Matched intentionally:

- Boot enters a start/login scene, then creates or loads local account state and enters the world.
- Save/load persists account, player, inventory, bank, quest, settings, skills, combat, world, and time state as JSON.
- Movement and click interaction use the classic default/context split: empty ground clicks walk, left-click performs default object actions, and right-click opens object options.
- Click movement now uses a small Godot-native tile route around blocked/water/object tiles and object interactions can defer until the player reaches an adjacent walkable tile.
- Inventory/equipment/skills/HUD panels mirror current player state.
- Gathering, cooking, processing, combat, drops, XP, and level-up reward state mutate from copied JSON data.
- Bank, shop, NPC dialogue, quest progression, and quest rewards work end-to-end from copied data.
- Progression regression coverage now guards inventory capacity, stackable/non-stackable transaction checks, quest reward blocking/recovery, bank/shop edge cases, food use, equipment, drop pickup, and save persistence paths.
- Data, asset, quest, world, shop, mob, recipe, and originality references are validated by a Godot-side smoke.
- Asset fallback defaults exist for missing icons/effects, and copied art/audio paths are present.

Remaining parity gaps:

- Godot visuals now include distinct generated mob silhouettes by `visual_kind`; authored player/NPC/resource models, Panda3D model conversion, production animations, and final art are not ported.
- Movement uses simple cardinal tile routing over the shell map; it is not yet full production pathfinding with diagonal movement, dynamic obstacles, or action-specific ranges beyond the current one-tile interaction shell.
- Gameplay actions now have deterministic timer, respawn, and secondary-drop chance coverage; richer progress UI, cancellation, burn chance, randomized balance tuning, and richer combat formulas are still simplified.
- Combat now includes selected-style XP routing and a small poison status/cleanse loop; full enemy AI, encounter pacing, equipment rebalance, and broader status systems remain future work.
- Bank/shop/dialogue now use functional HUD panels for single/all deposit, withdraw, sell, single-item buy, quest start, and quest completion; quantity text entry, multi-buy, item-drop, unequip, and richer dialogue branching are still future work.
- Asset fallback verification checks manifest/file availability; runtime icon/audio binding into every UI surface remains future polish.
