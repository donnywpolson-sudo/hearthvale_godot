# AI Simulation Workflow Adversarial Audit

Audit target: Codex thread `019f30bd-56b3-77f3-98bf-4803a964b136`.

Scope: the Markdown audit created for the workflow connected to `C:\Users\donny\Desktop\HEARTHVALE_AI_SIMULATION.bat`, plus the current repo files and generated artifacts needed to verify or falsify its claims.

Audit date: 2026-07-05.

## Verdict

The workflow is promising but not yet trustworthy as an implementation driver. It can generate useful simulation evidence, but the current Markdown audit under-stated several high-risk failure modes:

- The docs, handoff, batch launcher, and latest generated prompt disagree about what the default workflow actually runs.
- The latest public prompt says there are no findings, but it was generated from only `1` run and `5` steps of `core_loop`.
- The core simulation workflow files are untracked, while the generated evidence is intentionally ignored under `.godot/`.
- `CODEX_HANDOFF.md` records broader historical simulation issues that the current latest prompt hides.
- The runner owns execution, classification, reporting, publishing, and prompt generation in one large file, so the same code can create evidence and shape the follow-up agent's interpretation of that evidence.

Proceed status: yes for using the workflow as an advisory tool. Proceed status: no for treating the latest prompt as proof of gameplay health or as a sufficient basis for broad implementation.

## Evidence Inspected

Current-state evidence:

- `git status --short`
- `RUN_AI_SIMULATION_PROMPT.bat`
- `scripts/playtest_simulation_runner.gd`
- `docs/smoke_verification_workflow.md`
- `docs/codex_phase_driver_prompt.md`
- `CODEX_HANDOFF.md`
- `.gitignore`
- `.godot/ai_simulation/latest/ai_simulation_latest_codex_prompt.md`
- `.godot/ai_simulation/latest/ai_simulation_latest.json`
- `.godot/ai_simulation/latest/ai_simulation_latest.md`
- `.godot/ai_simulation/latest/ai_simulation_latest_polish_telemetry.json`
- `.godot/ai_simulation/latest/ai_simulation_latest_manual_polish_review.md`

No new Godot simulation was run for this audit. That is deliberate: this is a document and workflow trust audit, not a validation run.

## Threat Model

The main adversary is not malicious code. The main adversary is false confidence:

- A future Codex agent may paste the latest generated prompt and assume the game has no issues.
- A future reviewer may run `git diff` and miss untracked files that define the simulation behavior.
- A generated report may be treated as durable evidence even though `.godot/` and `.godot_logs/` are ignored runtime state.
- A handoff may claim a workflow behavior that the current batch file no longer matches.
- A small smoke run may replace the latest public report and erase visibility into broader findings.

The workflow should be judged by how well it prevents these mistakes.

## Launch Chain

Observed launch chain:

```text
C:\Users\donny\Desktop\HEARTHVALE_AI_SIMULATION.bat
  -> C:\Users\donny\Desktop\hearthvale_godot\RUN_AI_SIMULATION_PROMPT.bat
  -> C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe --headless
  -> res://scripts/playtest_simulation_runner.gd
```

The Desktop shim is intentionally thin and lives outside the repo. The repo-local launcher is the durable workflow authority, but it is currently untracked.

## Findings

### Severe: The Latest Public Prompt Is Not Strong Enough To Drive Implementation

Evidence:

- `.godot/ai_simulation/latest/ai_simulation_latest_codex_prompt.md` reports `Runs: 1`, `Steps per run: 5`, `Scenario setting: core_loop`, and `Issue occurrences: 0`.
- The same prompt says: `No current findings. Keep the runner in the verification workflow and make no gameplay changes unless code inspection reveals an issue.`
- `CODEX_HANDOFF.md` records broader historical runs, including `RUN_AI_SIMULATION_PROMPT.bat 50 150 1 all issues` with `28 P2 QOL long-path-only occurrences` in `random_guard`.

Adversarial interpretation:

A 1x5 `core_loop` publish smoke can overwrite `.godot/ai_simulation/latest` and produce a prompt that looks authoritative. A future implementation agent may ignore or never inspect the broader handoff evidence. The generated prompt becomes a confidence laundering step: a tiny smoke run produces clean language that masks known broader random-guard friction.

Implemented correction target:

Generated reports should label run strength directly with `run_strength`, `coverage_scope`, and `implementation_ready`. If the latest run is below Strategy Smoke coverage, the prompt must say `NOT IMPLEMENTATION-READY: this run is below strategy-smoke coverage and cannot prove gameplay health.` and must use `No findings observed within this run scope.` instead of broad no-finding claims.

### Severe: Documentation And Launcher Behavior Contradict Each Other

Evidence:

- `docs/smoke_verification_workflow.md` says double-clicking `RUN_AI_SIMULATION_PROMPT.bat` runs the recommended default profile.
- The same doc lists a default clickable profile of `50` runs, `150` steps, scenario `all`.
- `RUN_AI_SIMULATION_PROMPT.bat` starts with `USE_TIER_MENU=1` and enters `:choose_tier` unless environment overrides or positional args are supplied.
- The menu's recommended first option is `Strategy Smoke`, which runs `12` runs, `150` steps, and a `60` second cap.
- `CODEX_HANDOFF.md` says the launcher is non-interactive by default, but the current batch file is interactive by default.

Adversarial interpretation:

Different agents can truthfully cite different files and reach incompatible conclusions about what "the default run" means. That makes validation claims ambiguous. A user double-clicking the launcher may think they ran the documented 50-run default when they actually selected or were prompted for a tier.

Implemented correction target:

The batch launcher menu is the source of truth. Double-click opens the interactive tier menu, Strategy Smoke is the recommended first option, and the old 50x150 profile is not the clickable default. Docs and handoff should describe the same behavior.

### Severe: Core Workflow Is Untracked While Generated Evidence Is Ignored

Evidence:

- `git status --short` shows `RUN_AI_SIMULATION_PROMPT.bat`, `scripts/playtest_simulation_runner.gd`, `scripts/invariant_checker.gd`, `scripts/state_snapshot.gd`, and several related smoke/debug files as untracked.
- `.gitignore` ignores `.godot/`, `.godot_logs/`, `.godot_smoke_saves/`, `*.log`, and related runtime state.
- The latest public generated reports live under `.godot/ai_simulation/latest`, which is ignored by `.gitignore`.

Adversarial interpretation:

The repository currently has the worst trust split: the code that generates evidence is not tracked, and the generated evidence is also not tracked. A normal review can miss both. Handoff claims can drift from actual untracked code without any normal diff proving it.

Implemented correction target:

Decide and apply a keep set:

- Track durable workflow code and docs: `RUN_AI_SIMULATION_PROMPT.bat`, `scripts/playtest_simulation_runner.gd`, reusable helpers, focused smokes, and workflow docs.
- Keep `.godot/` and `.godot_logs/` ignored.
- Add a tracked sample report fixture only if needed for tests, not as current project truth.

### Medium: The Runner Is Both Evidence Producer And Narrative Author

Evidence:

`scripts/playtest_simulation_runner.gd` owns:

- CLI parsing and config validation.
- Scenario selection and bot action policy.
- Issue detection and grouping.
- Invariant calls.
- Telemetry, balance, performance, and polish aggregation.
- Snapshot writing.
- Markdown improvement plan generation.
- Codex prompt generation.
- Latest/archive publishing.
- Progress reporting.

Adversarial interpretation:

When a single file both detects issues and writes the persuasive Markdown that tells Codex what to do, weak heuristics can become framed as verified findings, and weak coverage can become framed as "no current findings." This is not automatically wrong for a prototype, but it is a trust boundary.

Implemented correction target:

Before adding more feature scope, split or harden the trust boundary:

- Keep bot execution and classification in the runner.
- Keep report generation in the runner for this pass, but add an explicit trust-context helper and record report-writer extraction as a future follow-up.
- Add report self-audits: run size label, scenario coverage label, latest generated timestamp, and explicit stale/smoke warnings.

### Medium: Publish-Latest Can Hide Earlier Stronger Evidence

Evidence:

- `_publish_latest_outputs()` copies current working reports into staging, archives the previous `latest`, and then renames staging to `latest`.
- The latest visible prompt currently reflects a tiny 1x5 core-loop run.
- Previous latest files are moved under `.godot/ai_simulation/archive/<timestamp>/previous_latest`, also ignored generated state.

Adversarial interpretation:

The workflow preserves archives, but the user's natural next action is to open only `latest`. A narrow smoke run after a broader simulation can make the easiest-to-access artifact less useful than older artifacts.

Implemented correction target:

Published latest files should include visible run-strength and implementation-readiness context. Lower-coverage runs should not replace stronger `latest` output by default. `HV_SIM_ALLOW_LATEST_DOWNGRADE=1` may explicitly allow replacement, while `HV_SIM_REQUIRE_PUBLISH_LATEST=1` makes blocked publishing fail automation.

### Medium: Exit Codes Do Not Encode Issue Presence By Default

Evidence:

- `docs/smoke_verification_workflow.md` says the command exits `0` when the harness completes, even if it finds issues.
- `--fail-on-issues` is optional.
- The launcher does not pass `--fail-on-issues`.

Adversarial interpretation:

Automation can treat a simulation with findings as a pass unless it reads report content. That is acceptable for advisory balance exploration, but dangerous for CI-style gates or "is the workflow clean?" checks.

Implemented correction target:

Use separate language:

- "Harness completed" for process success.
- "No issue findings" for clean findings.
- "Advisory findings present" for completed runs with issues.

Do not call a run "passed" without qualifying which layer passed.

### Medium: Replay Commands Are Helpful But Not Complete Proof

Evidence:

- Issue samples include `replay_command` values using the same runner, same step count, seed, scenario, and `--trace all`.
- Replay metadata includes build/data/script hashes.

Adversarial interpretation:

This is good, but replay still depends on the current untracked runner and mutable dirty data/scripts unless the hashes are compared before replay. A future agent can replay under changed code and think it disproved an older issue.

Implemented correction target:

The replay instructions should require checking `replay_manifest.json` hashes against current files before using a replay to close an issue. If hashes differ, generated reports must say the replay is under changed code and cannot close the original issue by itself.

### Medium: The Audit's Original "Proceed Status: Yes" Was Too Broad

Evidence:

The original audit concluded "Proceed status: yes" with caveats.

Adversarial interpretation:

That wording is too easy to quote without the caveats. It does not distinguish between proceeding with workflow stabilization, proceeding with advisory review, and proceeding with gameplay implementation from the latest prompt.

Required correction:

Use scoped proceed statuses:

- Proceed: workflow is worth keeping.
- Proceed: stabilize tracked workflow files.
- Do not proceed: broad implementation from the current latest prompt alone.

### Low: Manual Polish Review Is Correctly Scoped But Easy To Skip

Evidence:

The generated manual polish review explicitly covers start screen, HUD, inventory/equipment, bank/shop, dialogue/quests, combat, gathering/crafting, minimap, and camera.

Adversarial interpretation:

The bot correctly admits it cannot judge visual quality, fun, audio, animation, and player confusion. The risk is that future agents cite clean polish telemetry and skip the manual checklist.

Required correction:

Keep manual polish review as a required human gate for any visual/UI/fun claim. Automated polish telemetry can only flag candidates; it cannot clear subjective polish.

## What The Current Latest Output Actually Proves

The latest `.godot/ai_simulation/latest` output proves only this:

- The runner can execute at least one tiny `core_loop` smoke.
- The publishing path can write latest JSON, Markdown, prompt, polish telemetry, and manual review files.
- That tiny run found no issue occurrences.

It does not prove:

- The `all` scenario mix is clean.
- The `random_guard` long-path findings are resolved.
- Balance is acceptable.
- Quest, economy, combat, inventory pressure, and random coverage are healthy.
- UI polish is acceptable.
- Generated prompt instructions are safe enough for implementation without human/repo verification.

## Minimum Bar Before Using The Generated Prompt For Implementation

Before pasting `ai_simulation_latest_codex_prompt.md` into a new implementation thread, require all of the following:

1. The workflow files that generated it are tracked or intentionally documented as local-only.
2. The prompt states the run strength and scenario coverage clearly.
3. The run is at least the strategy-smoke tier for general implementation planning.
4. If the run is a narrow replay or publish smoke, the prompt says so in the first screen.
5. `CODEX_HANDOFF.md` does not contain newer or broader contradictory findings.
6. For any issue closure, replay hashes are compared against current file hashes.
7. Any UI/visual/fun conclusion includes manual review evidence, not only bot telemetry.

## Trust-Hardening Fix Order

1. Fix docs/handoff/launcher agreement about the default workflow.
2. Track or explicitly exclude the untracked workflow files.
3. Add run-strength labeling to `summary.json`, `replay_manifest.json`, `improvement_plan.md`, and `codex_prompt.md`.
4. Block lower-coverage publish-latest downgrades by default and require explicit opt-in to replace stronger latest output.
5. Keep report generation in the runner for this pass, but isolate trust wording in a helper and record report-writer extraction as future work.
6. Re-run a bounded strategy smoke after stabilization:

```powershell
$env:HV_NO_OPEN='1'; $env:HV_NO_PAUSE='1'; .\RUN_AI_SIMULATION_PROMPT.bat 12 150 1 all issues default 60
```

7. Only after the strategy smoke is stable, consider a medium balance pass.

## Revised Conclusion

Keep the AI simulation workflow, but treat the current Markdown audit's earlier confidence as too weak. The adversarial read is that this workflow is useful precisely because it can generate evidence quickly, but that speed creates a risk of stale, narrow, ignored, or untracked artifacts being mistaken for authoritative truth.

The next correct move is workflow stabilization, not gameplay changes from the current latest prompt.
