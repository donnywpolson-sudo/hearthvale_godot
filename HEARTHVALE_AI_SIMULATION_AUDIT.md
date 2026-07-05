# AI Simulation Workflow Adversarial Audit

Audit target: existing Hearthvale workflow:

```text
C:\Users\donny\Desktop\hearthvale_godot\HEARTHVALE_AI_SIMULATION.bat
  -> res://scripts/playtest_simulation_runner.gd
  -> .godot/ai_simulation timestamped prompt and JSON reports
```

Audit date: 2026-07-05.

## Current State Snapshot

Current evidence is from live repo inspection, not memory or generated claims. This is an uncommitted current repo state snapshot because the worktree is dirty.

- `git status --short` shows active dirty work:
  - `M CODEX_HANDOFF.md`
  - `D docs/ai_simulation_workflow_audit.md`
  - `M docs/smoke_verification_workflow.md`
  - `M scripts/gameplay_core.gd`
  - `M scripts/playtest_simulation_runner.gd`
  - `?? HEARTHVALE_AI_SIMULATION.bat`
  - `?? HEARTHVALE_AI_SIMULATION_AUDIT.md`
- The project-root launcher is the current user-facing workflow. It exposes Strategy Smoke, Medium, Deep, and Overnight tiers, plus positional automation args.
- The launcher calls `scripts/playtest_simulation_runner.gd` directly through Godot headless and publishes through `.godot/ai_simulation`.
- Public outputs are timestamped files directly under `.godot/ai_simulation`: `ai_simulation_codex_prompt_YYYY_MM_DD_HHMM.md` and `ai_simulation_data_YYYY_MM_DD_HHMM.json`.
- Older `.godot/ai_simulation/latest/...` references are legacy/stale for the current workflow.
- Generated `.godot/` and `.godot_logs/` artifacts remain ignored runtime evidence, not durable project truth.
- No Godot smoke check or simulation run was executed for this audit pass; this document evaluates workflow shape and inspected files only.

## Verdict

The existing AI simulation workflow is worth keeping and improving. It is useful as an advisory evidence generator, but it must not be treated as proof that Hearthvale is fun, visually clear, balanced, or fully playable.

Adversarial estimated automation confidence after this pass: medium-high for catching implementation-relevant gameplay issues through automation. That is a rough audit judgment, not a measured validation result. It can improve with stronger scene/screenshot review, but screenshot review and manual playtesting remain separate evidence lanes and are not automated proof.

Proceed status:

- Proceed: keep and use `HEARTHVALE_AI_SIMULATION.bat` as the existing launcher.
- Proceed: use `scripts/playtest_simulation_runner.gd` for direct simulation, telemetry, replay, balance, polish, and scenario-probe diagnostics.
- Do not proceed: broad gameplay implementation from a generated prompt without verifying current code, data, replay hashes, focused smokes, and manual review where relevant.

## Coverage Lanes

| Lane | Current role | What it catches | What it cannot prove |
| --- | --- | --- | --- |
| Existing launcher | `HEARTHVALE_AI_SIMULATION.bat` selects run size, scenario/profile, trace, timeout, publishing, and probe mode. | Wrong path wiring, missing Godot/project files, invalid args, lower-coverage publish blocking. | Gameplay quality by itself. |
| Direct API simulation | `playtest_simulation_runner.gd` runs seeded bot actions through game scenes/scripts. | Runtime errors, no-progress loops, bad feedback, inventory pressure, quest/economy/combat friction, replayable issue samples. | Real player input timing, visuals, audio, subjective feel. |
| Scenario probes | Deterministic report-only probes inside the existing runner. | Curated core loop, quest, combat/loot, economy, inventory, skill, recipe, and mob diagnostics. | Pass/fail contract health; focused smokes remain authoritative. |
| Focused Godot smokes | Independent smoke scripts in `docs/smoke_verification_workflow.md`. | Protected behavior for data, core gameplay, golden scenarios, save/load, debug tools, UI state, visuals, camera/minimap. | Long-run balance or subjective play feel. |
| Scene and screenshot review | Real `scenes/main.tscn`/UI captures, reviewed by AI or human. | Overlap, clipping, blank panels, unreadable contrast, missing assets, bad z-order, confusing selected/disabled states. | Whether the game feels good. |
| Manual playtesting | Human run through the actual game. | Fun, pacing, comprehension, grind feel, reward satisfaction, visual/audio feel. | High-volume deterministic regression coverage. |

## Findings

### Medium: The Launcher Is Correctly Central, But Was Underdocumented

Evidence:

- `HEARTHVALE_AI_SIMULATION.bat` already exposes Strategy Smoke, Medium, Deep, and Overnight.
- It validates scenarios: `all`, `core_loop`, `quest_chaser`, `economy_stress`, `combat_loot`, `inventory_pressure`, and `random_guard`.
- It validates balance profiles: `default`, `progression`, `economy`, `combat`, and `coverage`.
- It supports publish controls through `HV_SIM_ALLOW_LATEST_DOWNGRADE` and `HV_SIM_REQUIRE_PUBLISH_LATEST`.

Adversarial interpretation:

The correct move is not to create a parallel harness. A parallel harness would split trust and make future reports harder to interpret. Improvements belong in the existing launcher and runner.

Current observed state:

The launcher now passes `--scenario-probes` into the existing runner and validates `auto|off|smoke|full`.

### Medium: Direct Simulation Coverage Is Broad But Still Stochastic

Evidence:

- The runner rotates existing scenarios and balance profiles.
- It writes replay metadata, issue samples, telemetry, balance profiles, performance observations, polish telemetry, manual review prompts, and trust labels.

Adversarial interpretation:

Randomized or profile-weighted bot coverage can miss specific branches for a long time. A clean stochastic run is useful but not enough to prove every major loop was exercised.

Current observed state:

Scenario probes add deterministic, report-only coverage for curated cases. They are not pass/fail smokes and do not replace golden scenarios.

### Medium: Scenario Probes Improve Coverage But Must Stay Advisory

Evidence:

- `summary.json` now includes `scenario_probes`.
- Generated Markdown reports include the requested and resolved probe mode.
- Generated JSON and Markdown reports include an advisory 0-100 category scorecard with relevant metrics and score basis text.
- Probe issues are captured separately and do not increment normal issue counts or change exit status.

Adversarial interpretation:

If scenario probes become failing gates too early, conservative thresholds or known prototype gaps could block useful simulation runs. They should highlight diagnostic holes without pretending to be formal acceptance tests.

Current observed state:

Probe findings use labels such as `scenario_no_state_delta`, `scenario_no_xp_gain`, `scenario_quest_branch_not_exercised`, `scenario_combat_unresolved`, `scenario_economy_value_out_of_range`, `scenario_inventory_recovery_failed`, and `scenario_probe_stalled`.

### Medium: Visual And UI Confidence Remains Under-Covered

Evidence:

- The runner has polish telemetry and a manual polish checklist.
- Focused smokes include UI state, visual recreation, boot flow, camera/minimap, and playable shell checks.

Adversarial interpretation:

Polish telemetry can say feedback exists, but it cannot judge visual hierarchy, contrast, clipping, animation feel, sound timing, or whether a new player understands what to do.

Current observed state:

Treat screenshot review as a separate lane. AI can inspect real Godot screenshots for concrete visual defects only. Manual review remains the gate for fun and comprehension.

### Low: Generated Evidence Can Still Be Overquoted

Evidence:

- Reports intentionally produce a paste-ready Codex prompt.
- The prompt now includes trust labels, implementation-readiness warnings, replay guidance, and scenario-probe context.

Adversarial interpretation:

A polished generated prompt can still sound more authoritative than the run deserves. Future agents must treat it as evidence to verify, not an instruction to blindly implement.

Current observed state:

Keep the prompt language explicit: generated findings are candidates, replay hashes matter, and manual/smoke validation is required before broad claims.

## Estimated Coverage Confidence

The runner now emits advisory 0-100 scores for each category in `summary.json` under `scorecard.categories`, and repeats the same category scores in generated Markdown. These scores are measured from the current simulation run's issue counts, scenario probes, telemetry, balance, polish, performance, and scenario metrics.

The scores are not acceptance gates. They are automated evidence signals and do not prove fun, visual quality, audio quality, player comprehension, or release readiness. Low-confidence lanes, especially visual/audio and full playable game confidence, should remain capped until screenshots or manual playtesting are added.

These bands are adversarial audit estimates, not the generated numeric score output. They consider inspected workflow surface area, deterministic probe visibility, replay metadata, focused-smoke separation, and the remaining need for screenshot and human review.

| Area | Existing direct simulation | With scenario probes | With scene/screenshot review | Remaining manual gap |
| --- | --- | --- | --- | --- |
| Runtime/gameplay bugs | High | High | High | Rare human timing bugs |
| Core grind loop | Medium-high | High | High | Whether repetition feels satisfying |
| Skill progression | Medium | Medium-high | Medium-high | Long-term reward pacing |
| Quest flow | Medium | Medium-high | Medium-high | Player comprehension and motivation |
| Economy/bank/shop | Medium-high | High | High | Whether prices feel fair |
| Combat/loot/recovery | Medium | Medium-high | Medium-high | Combat feel and encounter identity |
| Inventory pressure | Medium-high | High | High | Whether friction feels fair |
| UI/action feedback | Medium | Medium | High | Subjective clarity and polish |
| Visual/audio confidence | Low | Low | Medium-high | Art direction, animation, sound feel |
| Full playable game confidence | Medium-low | Medium | Medium-high | Fun, pacing, onboarding |

Overall estimate:

- Existing workflow before deterministic probes: medium automation confidence.
- Existing workflow with scenario probes: medium-high automation confidence.
- With real scene screenshots and AI visual review: high visual-defect confidence for concrete UI/layout issues only.
- Screenshot review is not proof of fun, pacing, or comprehension.
- Manual playtesting is still required and is not represented as replaceable by AI.

Generated scorecard categories:

- `runtime_gameplay_bugs`
- `core_grind_loop`
- `skill_progression`
- `quest_flow`
- `economy_bank_shop`
- `combat_loot_recovery`
- `inventory_pressure`
- `ui_action_feedback`
- `visual_audio_confidence`
- `full_playable_game_confidence`

Generated relevant metrics include issue occurrences, grouped findings, severity/category counts, scenario probe mode and issue count, clean run rate, state changed rate, quest completion rate, average XP, average net worth, average mobs defeated, combat survival rate, full-inventory step rate, failed/no-feedback action rates, polish flag rate, slow action rate, average action cost, and average path length.

## Safe Consumer Checklist

Before using a generated AI simulation prompt for implementation:

1. Confirm the prompt and same-timestamp JSON are from the intended run.
2. Confirm run strength, scenario mix, balance profile, and scenario-probe mode.
3. Reject broad conclusions from `publish_smoke` or narrow replay runs.
4. Compare replay hashes before using a replay to close an issue.
5. Read `scenario_probes` as diagnostics, not hard failures.
6. Use focused smokes for protected behavior.
7. Use screenshots or manual review for UI/visual/audio claims.
8. Preserve unrelated dirty worktree changes.

## Realistic Additions To Track

These concepts are realistic for Hearthvale, but they should strengthen the existing launcher/runner workflow instead of creating a second harness.

| Concept | Audit fit | Realistic scope |
| --- | --- | --- |
| Coverage metrics | Partly implemented through the scorecard and relevant metric output; still high-value to deepen. | Track which quests, NPCs, mobs, resources, recipes, shops, items, UI panels, status effects, and interaction types were actually exercised. A long run should not look broad if it skipped major content. |
| Replay system | Already partly aligned with existing replay metadata. | Treat reproducibility as `seed + scenario config + action/input trace`, not seed alone. A seed without bot decisions, profile, scenario, and runner version is insufficient evidence. |
| Assertions / invariants | Strong fit for runner diagnostics and focused smokes. | Health, inventory counts, quest states, economy totals, reachable objectives, and stuck timers should never enter invalid states. Invariant violations should be reported as concrete bug candidates. |
| Crash/softlock detection | Already central and worth keeping explicit. | Keep detecting hard crashes, stalled progress, unreachable objectives, impossible requirements, blocked interactions, and loops where the bot cannot recover after a bounded time. |
| CI regression testing | Useful only as a small subset. | Run smoke-sized seeded checks in CI or pre-merge workflows; do not run deep, overnight, or broad stochastic simulation on every change. |
| Data mining / balance analysis | Useful later after enough telemetry accumulates. | Analyze XP/hour, coin flow, deaths, inventory pressure, quest completion rates, underused content, and overrepresented routes once report volume is large enough to compare trends. |

Use caution with heavyweight labels:

- Treat Monte Carlo simulation as bounded randomized batch runs, not a promise of thousands of exhaustive runs.
- Treat combinatorial testing as sampled character/item/map/enemy/profile combinations, not full permutation coverage.
- Keep fuzz testing constrained to plausible Hearthvale actions; raw random input spam is less useful than action-aware bot exploration.
- Do not list fixed timestep simulation as a major missing feature unless a bug actually depends on frame-rate sensitivity.

## Primary Next Improvement

Add a small screenshot capture and review workflow for `scenes/main.tscn` states: start, HUD idle, inventory/equipment, bank/shop, dialogue/quest, combat, gathering/crafting, minimap/camera. Pair it with an AI screenshot-review prompt that asks for concrete visual defects only: overlap, clipping, missing assets, low contrast, blank panels, confusing states, and bad z-order.

This should be the next improvement because visual and UI confidence is the clearest under-covered lane. It strengthens the existing launcher/runner workflow without creating a second simulation harness.

## Later Improvements

1. Add a bot-quality calibration loop with a small labeled corpus of known bugs, known non-bugs, fixed issues, and expected detections.
2. Add a data/content coverage matrix for quests, NPCs, mobs, resources, recipes, shops, items, UI panels, status effects, and interaction types.
3. Add stronger replay capture with seed, scenario config, balance profile, runner version, and action/input trace.
4. Add explicit invariant checks for impossible health, negative inventory counts, invalid quest states, impossible economy totals, unreachable objectives, and stuck timers.
5. Add before/after regression comparison for the same seeds and profiles.
6. Tighten structured bug handoffs with expected behavior, actual behavior, repro command, seed, scenario, trace when available, suspect system, confidence, bot-limitation note, and the smallest relevant smoke or manual check.
7. Add an originality/content guard for AI-generated suggestions.
8. Define report retention and triage rules for `.godot/ai_simulation` output.

## Revised Conclusion

The existing Hearthvale AI simulation launcher now has the correct shape for the work being copied from the tower-defense project: one established launcher, one established runner, deterministic report-only probes, trust-labeled generated outputs, and a refreshed audit that separates automated evidence from visual and manual judgment.

The workflow can guide improvements. It cannot replace focused Godot smokes, screenshot review, or manual playtesting.
