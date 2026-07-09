# Hearthvale AI Simulation Audit

## Durable Spec Warning

This file is the durable audit workflow/spec for Hearthvale's AI simulation and visual review system.

Run-specific dates, metrics, findings, screenshots, scores, latest output paths, dirty-file snapshots, and improvement priorities belong only in:

```text
C:\Users\donny\Desktop\hearthvale_godot\_ai_audit_workflow\_internal\HEARTHVALE_AI_SIMULATION_AUDIT_REPORT.md
```

Do not treat generated prompts, AI summaries, memory, handoff files, or this durable spec as implementation proof. Current audit conclusions must be backed by live repo files, command output, generated JSON from the intended run, focused smoke results, screenshots, or manual review notes.

## Purpose

Evaluate whether the existing launcher, simulation runner, scenario probes, reports, and visual screenshot workflow provide useful advisory evidence for Hearthvale development without pretending to prove fun, final balance, player comprehension, audio quality, or release readiness.

The correct audit outcome can be "no code change." An audit should improve confidence and decision quality; it should not force implementation work from weak evidence.

## Audit Target

```text
C:\Users\donny\Desktop\hearthvale_godot\_ai_audit_workflow\_internal\HEARTHVALE_AI_SIMULATION.bat
  -> res://scripts/playtest_simulation_runner.gd
  -> .godot/ai_simulation timestamped prompt and JSON reports
```

Related visual review workflow:

```text
res://scripts/visual_review_capture.gd
  -> .godot/visual_review/<timestamp>/*.png
  -> .godot/visual_review/<timestamp>/visual_review_prompt.md
```

## Evidence Discovery Order

Use this order before making or accepting audit claims:

1. Confirm the repository path with `Get-Location` and record `git status --short` in the audit report.
2. Confirm the launcher, runner, visual capture script, smoke workflow doc, and expected paths still match the audit target.
3. Read tracked source/docs first: launcher, runner, focused smoke workflow, relevant smoke scripts, and data/schema files for any finding being evaluated.
4. Inspect generated runtime artifacts only after confirming they are from the intended run. Treat `.godot/`, `.godot_logs/`, `.godot_smoke_saves/`, and `.godot/visual_review/` as ignored runtime evidence, not durable project truth.
5. Use same-timestamp public prompt/JSON pairs for public simulation evidence. Do not use `_working/current` as public evidence after a later simulation run unless it is the intended current run being audited.
6. Use screenshots or manual review notes for visual, UI layout, audio, comprehension, and play-feel claims. Simulation telemetry cannot prove those lanes.
7. For any implementation-driving finding, reconcile generated output against code/data, replay hashes, focused smokes, screenshots, or manual review before recommending a change.

## Minimum Coverage Evidence Bundle

Use this bundle when the audit report needs to claim current automated and screenshot coverage. It is the minimum evidence set for broad coverage claims in this repo: visible screenshots, strategy simulation, the full focused-smoke matrix, and whitespace validation.

Do not call this proof of fun, final balance, audio quality, player comprehension, export parity, or every possible content path. Those require manual notes or dedicated future probes in the report.

Run the visible screenshot capture without `--headless`; this must create a timestamped `.godot/visual_review/<timestamp>/` folder, expected PNGs, and `visual_review_prompt.md`, and it must fail on blank captures:

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --path . --script res://scripts/visual_review_capture.gd --log-file .godot_logs\visual_review_capture.log
```

Run the strategy simulation; use this for runtime gameplay coverage, scenario probes, performance diagnostics, polish telemetry, scorecard metrics, and the audit report summary:

```powershell
$env:HV_NO_OPEN='1'; $env:HV_NO_PAUSE='1'; .\_ai_audit_workflow\_internal\HEARTHVALE_AI_SIMULATION.bat 24 200 1 all issues coverage 0 auto
```

Run the full focused-smoke matrix; every script must exit successfully and print its documented pass message in `.godot_logs/<smoke>.log`:

```powershell
$godot = 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe'
$smokes = @(
  'boot_flow_smoke',
  'save_roundtrip_smoke',
  'playable_shell_smoke',
  'pathfinding_interaction_smoke',
  'camera_minimap_smoke',
  'visual_recreation_smoke',
  'ui_state_smoke',
  'interaction_panel_smoke',
  'core_gameplay_smoke',
  'combat_depth_smoke',
  'timed_action_smoke',
  'economy_quest_smoke',
  'golden_scenarios_smoke',
  'save_load_torture_smoke',
  'debug_command_console_smoke',
  'debug_overlay_smoke',
  'state_snapshot_smoke',
  'progression_regression_smoke',
  'data_validation_smoke',
  'asset_fallback_smoke'
)
foreach ($smoke in $smokes) {
  & $godot --headless --path . --script "res://scripts/$smoke.gd" --log-file ".godot_logs\$smoke.log"
  if ($LASTEXITCODE -ne 0) { throw "Smoke failed: $smoke ($LASTEXITCODE)" }
}
```

Run the final repository diff check:

```powershell
git diff --check
```

Minimum coverage evidence is complete only when the audit report records:

- The visual review output folder, PNG count, prompt path, and blank-check result.
- The strategy simulation output path, issue counts, scorecard, scenario probe status, performance observations, and polish telemetry.
- The full focused-smoke matrix result, including any failed or skipped smoke by name.
- Any manual-only gaps that remain, especially audio timing/mixing, subjective play feel, export/platform parity, and unsupported audit areas marked `not supported` or `out of scope`.

## Required Checks

Each broad audit pass must check these points before drawing conclusions:

1. The worktree state is recorded, and unrelated dirty files are preserved.
2. The launcher and runner paths still match the audit target.
3. Generated simulation evidence comes from the intended run and includes replay/trust metadata.
4. Scenario probe findings are treated as report-only diagnostics unless intentionally promoted to focused smokes.
5. Focused smokes remain the pass/fail authority for protected behavior.
6. Visual screenshot prompts ask only for concrete visual defects such as overlap, clipping, missing assets, low contrast, blank panels, confusing states, bad z-order, cropped controls, and viewport framing.
7. Visual, audio, subjective fun, onboarding comprehension, export parity, and player-feel claims are not inferred from simulation-only evidence.
8. Any regression comparison uses comparable seeds, scenario mix, balance profile, runner mode, replay metadata, and compatible build/data/script hashes.
9. Findings that drive implementation include the evidence fields required by the report schema below.
10. The final report separates proven facts, partial evidence, unsupported areas, and next recommendations.

## Coverage Classifications

Use these classifications in the audit report for each coverage area and implementation-driving finding:

| Classification | Meaning |
| --- | --- |
| `proven` | Direct evidence from current code/data, command output, passing focused smoke, same-run generated JSON, screenshot, or manual note supports the claim. |
| `partially proven` | Evidence supports part of the claim, but coverage is narrow, stochastic, advisory, or missing one required corroborating source. |
| `not proven` | The audit looked for evidence but did not find enough to support the claim. |
| `not supported` | Hearthvale does not currently implement or target this surface, so the audit should not invent requirements for it. |
| `out of scope` | The surface exists or could exist, but this audit pass intentionally did not evaluate it. |

Do not upgrade a claim because a generated prompt sounds confident. Weak evidence stays weak until corroborated.

## Coverage Lanes And Areas

Use these lanes to structure audit reports and future simulation/smoke coverage.

| Lane | Role | Catches | Cannot prove |
| --- | --- | --- | --- |
| Launcher | Selects run size, scenario/profile, trace, timeout, publish, and probes. | Path wiring, missing project files, invalid args, publish safety. | Gameplay quality. |
| Direct simulation | Runs seeded bot actions through current Godot game code. | Runtime issues, no-progress loops, feedback gaps, inventory/economy/combat friction. | Human input feel, visuals, audio, fun. |
| Scenario probes | Deterministic report-only diagnostics inside the runner. | Curated quest, combat, economy, inventory, skill, recipe, and mob exercise. | Pass/fail contract health. |
| Focused smokes | Independent smoke scripts in `docs/smoke_verification_workflow.md`. | Protected behavior for data, gameplay, save/load, UI, visuals, debug tools. | Long-run balance or subjective quality. |
| Visual screenshots | Real rendered captures reviewed by AI or human. | Overlap, clipping, missing assets, low contrast, blank panels, z-order issues. | Fun, comprehension, audio, final art quality. |
| Manual playtesting | Human play through the actual game. | Fun, pacing, clarity, reward feel, grind feel. | High-volume regression coverage. |

Use these detailed areas in reports. Mark unsupported surfaces as `not supported`, rather than inventing requirements.

| Audit area | What to check |
| --- | --- |
| Core gameplay rules | Win/loss or fail/recovery states, scoring/value changes, damage, cooldowns/timers, movement rules, resource use, progression logic. |
| Player input | Keyboard, mouse, controller if supported, rebinding if supported, input buffering, pause behavior, rapid-input edge cases. |
| Physics and collisions | Collision layers/masks, hitboxes, hurtboxes, raycasts, Area2D/3D, RigidBody, CharacterBody, slopes if used, tunneling, stuck states. |
| Scene and node lifecycle | Scene loading/unloading, duplicate nodes, orphaned nodes, `_ready`, `_process`, `_physics_process`, freed-node errors. |
| Signals and events | Missing/disconnected signals, duplicate signal connections, event-order bugs, UI/gameplay sync issues. |
| Autoloads/singletons | Global state bugs, reset behavior, scene transitions, stale data after death/restart/load. |
| Save/load systems | Corrupt saves, versioning, missing fields, local/cloud conflicts if supported, save during transitions, save-scumming risks. |
| Menus and UI | Pause menu, settings, inventory, tooltips, scaling, focus order, controller navigation if supported, screen-size adaptation. |
| Game balance | Difficulty spikes, dominant strategies, broken upgrades, economy inflation, enemy scaling, reward pacing. |
| AI/enemy behavior | Pathfinding, idle states, target selection, unreachable player cases, swarm behavior if used, stuck enemies, unfair reactions. |
| Level/content validation | Missing assets, broken doors/links if used, unreachable areas, invalid spawn points, softlocks, bad checkpoints. |
| Performance | FPS drops, shader compilation stutter, excessive nodes, physics cost, particles, draw calls, pathfinding spikes. |
| Memory and resource usage | Texture/audio bloat, leaks, unreleased scenes, preload/load misuse, scene transition memory growth. |
| Rendering and visuals | Camera bounds, z-index/layering, lighting, animation glitches, shader errors, resolution/aspect-ratio issues. |
| Audio | Missing sounds, overlapping loops, volume mixing, bus routing, pause behavior, spatial audio bugs if used. |
| Build/export stability | Export presets, missing files, platform-specific crashes, permissions, icon/version metadata, release/debug differences. |
| Platform compatibility | Windows/macOS/Linux/Web/mobile behavior if targeted, controller support, fullscreen/windowed, high-DPI, Steam Deck if targeted. |
| Networking/multiplayer | Not currently supported for single-player Hearthvale; if multiplayer is added, check desync, authority, reconnects, packet loss, duplicate actions, host migration. |
| Security/cheating | Save tampering, speed hacks, debug commands, client-authoritative exploit risks if networking is added. |
| Accessibility | Remapping, subtitles if dialogue/audio needs them, color readability, font size, screen shake toggle if shake is added, hold-vs-toggle options. |
| Localization | Text overflow, missing translations if localization is added, font glyphs, right-to-left text if supported, hardcoded strings. |
| Crash/error logging | Godot errors, warnings, stack traces, failed resource loads, unhandled nulls, bad casts. |
| Telemetry/analytics | Funnel events if used, deaths, completion rates, bug reproduction logs, seed/run metadata. |

### Audio Coverage Details

Use this table when reviewing audio evidence from manual play, future capture workflows, Godot warnings, or targeted smoke/simulation instrumentation. Mark unsupported surfaces as `not supported`.

| Area | What to audit |
| --- | --- |
| Missing sounds | Footsteps, hits, UI clicks, enemy attacks, music triggers, and other expected action cues. |
| Wrong sounds | Incorrect cue plays for an action, event, item, enemy, UI panel, or state transition. |
| Audio timing | Sound plays too early, too late, repeats unexpectedly, overlaps badly, or cuts off. |
| Mixing | Music too loud, effects too quiet, dialogue or notification cues buried, harsh peaks. |
| Audio buses | Music, SFX, and UI routed to correct buses; volume sliders and mute settings affect the intended bus. |
| Looping | Music loops cleanly; ambience and repeated effects do not stack endlessly. |
| Pause behavior | Audio pauses or continues intentionally according to current design. |
| Scene transitions | Music changes correctly; old sounds do not persist into unrelated scenes or panels. |
| Spatial audio | 2D/3D positional audio distance, panning, falloff, and listener behavior if spatial audio is used. |
| Performance | Too many simultaneous sounds, memory-heavy audio assets, or audio-related stutter. |

### Visual Coverage Details

Use this table with `.godot/visual_review/<timestamp>/` screenshots, manual review, focused smokes, and export checks. Keep findings concrete: overlap, clipping, missing assets, low contrast, blank panels, confusing states, bad z-order, or broken rendering.

| Area | What to audit |
| --- | --- |
| Rendering correctness | Missing sprites/assets, broken textures, shader errors, lighting issues, invisible meshes. |
| Animation | Broken animation states, stuck animations, animation desync, bad transitions. |
| Camera | Camera clipping, bad bounds, shake bugs if used, zoom issues, player leaving view. |
| Layering/draw order | Wrong z-index or layer, UI behind game objects, background/foreground overlap bugs. |
| Particles/VFX | Effects not spawning, effects persisting too long, performance-heavy particles if used. |
| UI visuals | Text overflow, unreadable fonts, wrong scaling, broken anchors, bad controller focus highlights if controller focus is supported. |
| Resolution/aspect ratio | 16:9, ultrawide, windowed, fullscreen, high-DPI, and mobile scaling if targeted. |
| Visibility/readability | Enemy readability, projectile clarity, color contrast, important objects blending into background. |
| Export visual parity | Rendered output looks correct in exported builds, not only inside the Godot editor. |

## Validation Commands

Use the minimum bundle commands above when the report needs broad current coverage. For narrower docs-only or targeted refactors, run the smallest relevant validation.

For docs-only refactors of this spec, the required validation is:

```powershell
git diff --check
```

Do not run broad Godot smoke batches, visual capture, or strategy simulation unless the current audit pass requires fresh runtime evidence or the user explicitly requests it.

## Report Schema

The audit report should use this shape when recording a current run:

- `Report date`: local date of the audit report.
- `Evidence used`: commands, generated artifact paths, screenshot folders, manual notes, and tracked files inspected.
- `Current repo state`: `git status --short` summary and any dirty-file caveats.
- `Minimum coverage bundle status`: visible capture, strategy simulation, focused-smoke matrix, and `git diff --check`, each marked passed, failed, skipped, or out of scope with a reason.
- `Coverage classification summary`: each major lane or audit area marked `proven`, `partially proven`, `not proven`, `not supported`, or `out of scope`.
- `Run summary`: only for the intended run; include run size, scenario/profile, issue counts, probe status, publish status, and relevant output paths.
- `Findings`: only implementation-driving findings with the required fields below.
- `Recommended improvements`: prioritized next actions, including `no code change` when evidence does not justify implementation.
- `Validation`: exact commands run and meaningful pass/fail results.

Each implementation-driving finding must include:

- `Evidence source`: file path, command output, generated JSON path, screenshot path, smoke name, replay/hash metadata, or manual note.
- `Classification`: one of the coverage classifications above.
- `Confidence`: high, medium, or low, based on evidence strength.
- `Affected system`: launcher, runner, scenario probe, focused smoke, UI, gameplay rule, data, visual, audio, performance, report workflow, or another concrete system.
- `Reproduction or command path`: smallest command, seed/profile, screenshot, smoke, or manual path that can re-check the finding.
- `Verification gap`: what the current evidence still cannot prove.
- `Recommended smallest next action`: no-code-change, inspect, add evidence, write a focused smoke, adjust report wording, or implement a scoped fix.

Do not include run-specific findings in this durable spec.

## Implementation Guardrails

- Generated simulation prompts, generated report summaries, scorecards, performance observations, polish telemetry, and scenario probes are advisory evidence, not direct implementation instructions.
- No-code-change is a valid audit result when evidence is weak, stale, unsupported, or already covered.
- Reject broad gameplay implementation from generated prompts unless findings are verified against current code, data, replay hashes, focused smokes, screenshots, or manual review.
- Compare replay hashes before using a replay to close, dismiss, or regress an issue. Regression comparisons require comparable seed, scenario mix, balance profile, runner mode, and compatible build/data/script hashes.
- Use focused smokes for protected behavior. Promote stable deterministic scenario probes to focused smokes only when their expected behavior is intentional and durable.
- Use screenshots or manual review for UI, visual, audio, comprehension, and play-feel claims.
- Preserve unrelated dirty worktree changes.
- Keep improvements in the existing launcher, runner, report, smoke, and visual-review workflow instead of creating a parallel harness.
- Keep original Hearthvale naming, data, visuals, and progression intent; do not copy proprietary names, assets, maps, dialogue, formulas, or branded terms from inspiration games.
