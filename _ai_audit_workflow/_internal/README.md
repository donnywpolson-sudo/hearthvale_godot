# AI Audit Workflow

Run one visible file:

```powershell
.\_ai_audit_workflow\RUN_AUDIT.ps1
```

By default it runs one bounded improvement cycle: Light audit, evidence queue, one
Codex implementation/remediation pass, and a fresh Light verification audit.
The cycle stops after one pass so each run stays reviewable and predictable.

Use `-MaxPasses 2` or `-MaxPasses 3` when you intentionally want a short batch.
Use `-PlanOnly` for audit and queue generation without applying a change.
Use `-Manual` to open the older Light/Deep review menu.

Before it does anything expensive, the workflow checks the basics. Automatic mode
also requires a clean worktree before the first Codex edit unless
`-AllowDirtyApply` is explicitly supplied:

- PowerShell is new enough
- the workflow is inside the Hearthvale Godot project
- Godot exists before Light or Deep audit
- Light or Deep has a positive simulation timeout budget
- the repo is clean before apply-now unless `-AllowDirtyApply` is passed explicitly as an exceptional override

If something is wrong, it prints what happened and exactly how to fix it. Preflight failures do not run audit, simulation, smoke, or apply steps, but the launcher transcript may already have been written.

Every run writes a full pasteable PowerShell transcript:

- `_internal/current/latest_run.log` - most recent run for choices 1, 2, or 3
- `_internal/current/run_logs/` - timestamped archived copies

Use `-PlanOnly` when you only want a quick Light audit. It runs visual capture, smoke validation, and a roughly three-minute 120-run / 200-step coverage simulation based on the latest smoke timing, with a 10-minute stop budget.

Use `-Tier Deep` when you want the overnight audit/improvement cycle. It uses the coverage preset with 4,500 runs / 1,800 steps, plus the same visual capture and validation, with a 12-hour stop budget. Add `-PlanOnly` to keep it audit-only.

After an automatic pass, the fresh verification audit rebuilds the queue so the next
run starts from current evidence. If no queued item exists, the workflow stops cleanly
after reporting that result. If an audit or Codex pass fails, it stops and preserves the
logs and current worktree for review.

Queue lanes are intentionally separate:

- `evidence-backed code fix` is the only lane allowed to change gameplay code, and it requires current-run evidence plus replay/hash metadata.
- `review-backed polish fix` can change gameplay/UI only after concrete screenshots, logs, telemetry, code, data, manual notes, smokes, reports, or findings are named.
- `workflow-evidence-improvement` can change only audit workflow, report, queue, prompt, handoff, or smoke-doc routing files.

Manual playtesting is a workflow-evidence lane, not an apply-now gameplay lane. To close the manual-playtesting evidence gap, use `_internal/templates/manual_playtest_notes.md` for a bounded 20-30 minute pass through `scenes/main.tscn`: start/load, gather, process/craft, sell/use, quest, combat/recovery, bank/shop, inventory pressure, and save/load continuity. Completed notes must name the git status/build context, route played, observed behavior, concrete defects if any, subjective notes, and stop condition. Manual notes can support later review-backed or evidence-backed work only after a separate item verifies the exact defect against current files or focused checks.

Audio review is also a workflow-evidence lane. To close the audio evidence gap, use `_internal/templates/audio_review_notes.md` for a bounded 10-15 minute pass through `scenes/main.tscn`: start/load, UI panels, bank/shop/dialogue, gathering, processing/crafting, combat/recovery, buy/sell, save/load, pause or focus behavior if available, and scene/start-flow transitions if practical. Completed notes must separate missing or wrong cues, timing, overlap, mix balance, bus/volume behavior, pause/focus behavior, spatial behavior if used, unsupported surfaces, and concrete defects. Audio notes can support later review-backed or evidence-backed work only after a separate item verifies the exact defect against current files or focused checks.

Export/platform parity is a workflow-evidence lane for release-confidence moments. To close the export/platform evidence gap, use `_internal/templates/export_platform_review_notes.md` to document a bounded export or exported-build smoke when build artifacts are intentionally allowed. The note must name the target platform, export preset, command or manual export path, build output path, launch result, start/load behavior, save/load continuity, visual parity, audio availability, input behavior, window/fullscreen behavior, logs, and unsupported platforms. Creating this evidence path does not run an export, create build artifacts, edit export presets, or authorize gameplay/content/code/asset changes.

Do not use `-AllowDirtyApply` while unrelated gameplay/content files are dirty unless you intentionally accept that the workflow may refuse to mark restricted-lane items handled.

Typed commands still work if you want them:

```powershell
.\_ai_audit_workflow\RUN_AUDIT.ps1 -Tier Deep
```

Other useful modes:

```powershell
.\_ai_audit_workflow\RUN_AUDIT.ps1 -PlanOnly
.\_ai_audit_workflow\RUN_AUDIT.ps1 -Tier Deep -MaxPasses 2
.\_ai_audit_workflow\RUN_AUDIT.ps1 -Manual
```

Visible root file:

- `RUN_AUDIT.ps1` - the only file you normally run

Hidden support files:

- `_internal/HEARTHVALE_AI_SIMULATION.bat` - simulation launcher used by the workflow
- `_internal/HEARTHVALE_AI_SIMULATION_AUDIT.md` - audit rules/spec
- `_internal/HEARTHVALE_AI_SIMULATION_AUDIT_REPORT.md` - latest report
- `_internal/current/` - generated workflow state; not durable evidence, and stale until regenerated by an explicitly approved audit run
- `_internal/` - helper scripts; ignore unless maintaining the workflow
