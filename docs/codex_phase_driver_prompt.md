# Codex Phase-Driver Prompt

Use this prompt when you want Codex to advance Hearthvale quality and developer tooling one phase at a time.

```text
In C:\Users\donny\Desktop\hearthvale_godot, implement the next incomplete phase from this phased quality/dev-tooling plan.

Rules:
- Inspect current path and run git status --short first.
- Read AGENTS.md, docs/smoke_verification_workflow.md, docs/codex_phase_driver_prompt.md, and CODEX_HANDOFF.md before editing.
- Preserve all existing dirty/user work.
- Implement exactly one phase per turn: the first phase not already completed in CODEX_HANDOFF.md or current repo evidence.
- Keep changes small, Godot-native, and consistent with existing smoke/test patterns.
- Use shared helpers where possible. Do not bury reusable invariants, snapshots, validators, or report formatting only inside the simulation runner.
- Route bot-owned work into scripts/playtest_simulation_runner.gd and its generated reports.
- Keep independent validators, golden smokes, save/load torture checks, debug console commands, and debug overlays runnable without the simulation bot.
- Run only the narrowest relevant smoke checks for that phase.
- Run git diff --check and git status --short before final.
- Update CODEX_HANDOFF.md with completed phase, validation, blockers, and the next recommended phase.
- Do not stage, commit, push, delete, move, or touch normal user saves.

Phase ownership:
- Shared/reusable: invariant checker, state snapshot/export/restore helpers, data/content reference helpers, and report formatting helpers.
- Simulation bot-owned: deterministic replay metadata, AI director/chaos mode, simulation-step invariant calls, local telemetry summaries, balance simulation profiles, failed-run state summaries, and advisory performance observations for simulation step cost.
- Separate but reusable by the bot: content validators, golden scenario smokes, save/load torture smokes, debug command console, and debug overlays.

Phases:
1. Shared invariant checks.
2. Stronger content validators.
3. Golden scenario smokes.
4. Save/load torture smoke.
5. Dev-only debug command console.
6. State snapshot/export/restore helpers.
7. Playtest simulation runner upgrade.
8. Local telemetry summaries.
9. Debug overlays.
10. Balance simulation profiles.
11. Minimal performance budget observations.

For the selected phase:
- Inspect the relevant existing scripts/data/docs.
- Reuse existing helpers and smoke patterns.
- Avoid broad rewrites.
- If the phase depends on a previous phase that is missing or incomplete, implement the smallest prerequisite needed or report the blocker.

Validation:
Run the smallest relevant Godot smoke command using the documented --log-file pattern, then git diff --check and git status --short.

Final:
Use the repo's required final format. Report files changed, exact checks run, pass/fail result, and the next phase.
```

After a phase is complete, use:

```text
Continue with the next incomplete phase from CODEX_HANDOFF.md.
```
