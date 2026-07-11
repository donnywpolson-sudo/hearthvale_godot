# Hearthvale Godot Agent Guide

These instructions are repo-local guidance for this repository. For work inside this repo, follow this file over broader repository or global Codex guidance when there is a conflict, where allowed by higher-priority system or developer instructions.

Minimize tokens, reads, edits, commands, and output. Make the smallest safe change.

## 1. Project-Specific Guidance

### Runtime Preference

- Use `gpt 5.6 luna high` as the default startup profile for this project whenever model and reasoning/mode settings are user-controllable.
- Use lighter/faster models or reasoning only for clearly trivial, low-risk work such as status checks, simple reads, or tiny mechanical edits.
- When model choice is uncertain, bias upward to the stronger model and reasoning setting.
- Switch back to stronger reasoning before continuing if a task becomes ambiguous, risky, multi-file, gameplay-critical, persistence-related, audit-related, visual/UI judgment-heavy, or test-failure/debugging-heavy.
- Treat Luna High as the conservative baseline, not an exclusive model lock, unless the user explicitly asks to pin a model.

### Project Vision

Hearthvale is an original, grindable single-player RPG prototype with simple controls, progression, skilling, combat, gathering, crafting, inventory management, NPC interaction, quests, shops, banking, economy, and long-term account growth.

Use inspiration games only for broad progression structure and game feel. Do not copy RuneScape/OSRS/Stardew proprietary assets, names, dialogue, maps, quests, icons, music, formulas, or copyrighted content. Do not add new branded or near-branded terms such as RuneScape, OSRS, Stardew, rune, runite, or direct equivalents.

Some migrated reference data may still contain prototype drift from earlier work. When touching nearby code or data, flag that drift and prefer original Hearthvale names, progression curves, world lore, assets, and UI text.

### Project Facts

- Destination repo: `C:\Users\donny\Desktop\hearthvale_godot`.
- Source reference: `C:\Users\donny\Desktop\hearthvale`; use it only as a read-only behavioral and content reference.
- Keep `C:\Users\donny\Desktop\hearthvale` read-only unless the user explicitly requests a Python repo edit.
- Godot version: 4.7 stable.
- Local Godot executable: `C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe`.
- Main scene workflow: open or run the Godot project from this repo and launch `scenes/main.tscn`.
- Save compatibility with the Python project was intentionally reset; do not add Python save migration unless explicitly requested.
- `.godot_logs/` and `.godot_smoke_saves/` are generated verification state and should stay untracked.

### Gameplay Priorities

Prioritize changes that make the game more playable, grindable, and complete:

1. Core loop: gather -> process/craft -> sell/use -> level up -> unlock better content.
2. Skill progression with XP, levels, unlocks, and meaningful rewards.
3. Simple but satisfying combat.
4. Inventory, equipment, drops, shops, and banking.
5. NPCs, dialogue, quests, and world interaction.
6. Clear UI feedback for actions, XP, levels, loot, errors, saves, and unlocks.
7. Incremental content additions over broad rewrites.

### Implementation Rules

- Prefer small, shippable increments that reuse existing Godot scenes, scripts, autoloads, data files, and UI patterns.
- Keep gameplay content data-driven in `data/*.json` where practical.
- Keep a clear separation between game state, gameplay rules, scenes, HUD/UI, assets, and persistence.
- Avoid broad rewrites, unused abstractions, speculative future work, and new dependencies unless clearly justified.
- Do not present old Python/Panda3D setup as current workflow. The Godot project should not rely on `requirements.txt`, Panda3D, pytest as the primary stack, `python -m game.main`, PyInstaller launcher builds, `Hearthvale.spec`, Python `users.db` migration, or old `game/engine/save.py` rules.
- For visual work, keep the current original 3D direction and avoid copying proprietary assets, maps, UI, icons, names, or formulas from inspiration games.

### Protected Game Contracts

Do not change these unless explicitly requested or required by the task:

- `project.godot` autoload names such as `StateStore`.
- Documented scene entry paths under `scenes/`.
- Save-state keys, persistence schema, and save/load behavior.
- Data schemas, IDs, and cross-file references in `data/items.json`, `data/skills.json`, `data/recipes.json`, `data/world.json`, and `data/quests.json`.
- Logical asset keys and paths in `assets/asset_manifest.json`.
- Documented smoke script entry points and expected pass messages.
- Interaction behavior that is documented or covered by smoke checks.

This does not freeze normal UI, control, balance, or gameplay iteration. It requires deliberate handling only for documented or smoke-covered contracts. When changing a protected contract, update the relevant smoke, data validation, or documentation in the same scoped change, or report why that was not done.

### Godot Validation

- Run the smallest relevant Godot smoke check first when behavior changes warrant runtime validation.
- Headless smoke checks require an explicit project-local log file:

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/<smoke>.gd --log-file .godot_logs\<smoke>.log
```

- See `docs/smoke_verification_workflow.md` for the current smoke list and parity gaps.
- The Windows root certificate warning is non-blocking if the smoke assertion prints its expected passed message.
- For visible gameplay or UI changes, provide short manual verification steps.

## 2. General Codex Repo Workflow

### Scope And Efficiency

- Keep work focused on the user's latest request.
- Prefer small, safe, reviewable changes.
- Be concise: prefer concrete findings, file paths, commands, test results, and next actions over narration.
- Do not produce filler, praise, or repeated status updates that do not add new information.
- Read targeted files only; search before opening many files.
- Skip generated, vendor, cache, build, data, log, and binary files unless relevant.
- Read files directly by path instead of asking for pasted large files, reports, logs, or full test output.
- Use concise summaries instead of long copied output. Ask for full logs only when a short summary is not enough.
- Implement directly when the task is clear.
- Plan first for broad, risky, destructive, or ambiguous work.
- Ask only when needed to avoid wrong, unsafe, destructive, or unactionable changes.
- Do not expose hidden chain-of-thought; provide brief rationale, assumptions, evidence, and decisions instead.

### Coordination Source Of Truth

- `AGENTS.md` is the durable agent-rule authority for repo safety, validation policy, output format, and project constraints.
- `README.md` is the user-facing setup, run, and current workflow entry point.
- `docs/smoke_verification_workflow.md` is the authoritative smoke/check list and smoke command reference.
- `CODEX_HANDOFF.md` is mutable continuation state only. Reconcile it against current files, command output, and `git status` before acting.
- Active docs under `docs/*.md` can be evidence for parity state, visual state, migration notes, and verification gaps, but they do not override `AGENTS.md`, `README.md`, `docs/smoke_verification_workflow.md`, or current repo files.
- `docs/source_reference/**` is read-only Python/source-reference material, not active Godot workflow authority.
- Do not create parallel root coordination docs unless explicitly requested.

### Repository Safety

- Work only in the active Git repo unless explicitly asked.
- Before editing, run `Get-Location` and `git status --short` from `C:\Users\donny\Desktop\hearthvale_godot`.
- Before editing files, state the intended edit briefly.
- Do not overwrite, revert, delete, move, rename, stage, commit, or push unless explicitly asked.
- Before any requested push, verify `git remote -v` shows the `origin` push URL is `https://github.com/donnywpolson-sudo/hearthvale_godot.git`. If the `origin` push URL differs, stop and ask for explicit approval before changing remotes or pushing.
- Do not run destructive commands unless explicitly approved.
- Preserve user work, secrets, credentials, lockfiles, migrations, generated artifacts, generated verification logs, local saves, imported assets, and existing migration notes unless the task explicitly requires touching them.
- Never store secrets, tokens, API keys, credentials, or private keys in repo files, prompts, memory, or config.
- Do not stage, commit, or treat ignored generated verification state or local editor/runtime cache as durable project evidence; use those artifacts only as disposable evidence for the current validation run. Examples include `.godot/`, `.godot_logs/`, `.godot_smoke_saves/`, `.import/`, `*.log`, cache files, and generated verification reports.
- Do not treat tracked Godot metadata such as `.uid` files as disposable generated output.
- If validation incidentally changes already-tracked generated or metadata artifacts, report the paths and do not stage them without explicit approval.
- If files are dirty, work with those changes and do not assume they are yours.

### Evidence And Failure Handling

- Do not invent facts, files, commands, outputs, dependencies, APIs, metrics, or prior decisions.
- Distinguish evidence from assumptions. Evidence includes inspected files, command output, tests, and cited documentation.
- Treat Codex/OpenAI memory, handoff files, and model output as unverified until checked against repo files, command output, user-provided sources, or official documentation.
- If evidence is missing, say so plainly, label assumptions, and verify before relying on the claim.
- Anti-loop rule: if the same approach fails twice, stop repeating it. Summarize the failure, change strategy, and proceed with a different diagnostic path.
- Blocker rule: after three unsuccessful attempts against the same blocker, stop and ask for the smallest missing input or approval needed to continue.

### Validation Rules

- Run the narrowest relevant check only when warranted by the change, safety risk, protected core logic, or explicit request.
- Prefer targeted tests while working.
- Ask before running full or expensive test suites.
- If a check fails before Godot or script execution due to sandbox, spawn, or permission handling, retry once with scoped approval if available.
- Do not treat pre-launch sandbox or spawn failures as project failures.
- Treat validation as failed only if Godot, a script, or another invoked tool launches and returns a traceback, failed assertion, failed test, or nonzero exit code.
- Run `git diff --check` before finalizing edits.
- After validation, run `git status --short` when practical and check that generated verification artifacts remain untracked.
- Report exact commands run and meaningful pass/fail results.

### Bounded Execution

Before running expensive, broad, mutating, or high-risk commands, the current prompt, current plan, or verified current `CODEX_HANDOFF.md` section must specify the command family, maximum scope, timeout or stop budget, expected generated artifacts, forbidden patterns, output/log path when relevant, and stop condition.

This gate applies to broad Godot smoke batches, playtest simulations, asset import or regeneration, data/content rewrites, cleanup/archive/quarantine actions, generated report runs, and operations touching saves, logs, imported assets, or many files.

Targeted single-smoke validation and narrow read-only inspection do not need the full bounded-execution gate. If the gate is required but incomplete, do not run the command; ask for the missing decision or produce a bounded plan instead.

### Handoffs

- Use repo-local `CODEX_HANDOFF.md` only for meaningful multi-step work or fresh-thread continuation.
- For non-trivial work, inspect `CODEX_HANDOFF.md` if it exists after checking the repo path and `git status --short`.
- Update `CODEX_HANDOFF.md` after meaningful multi-step work, fresh-thread continuation, major completed features, discovered blockers, changed strategy, or changed next recommended step.
- Do not create or update handoff files for simple one-shot tasks.
- Treat handoff files as mutable continuation state, not proof; reconcile them against current files, command output, and git status.
- If `CODEX_HANDOFF.md` is updated, keep the newest status, blockers, validation, and exact next recommended step before historical detail, and keep final `Suggestions` aligned with it.

### Final Responses

- Output language has three levels. Default is `Level 1: Simple Action Format`.
- `Level 1: Simple Action Format`: use short, clear English. Include only what I need to know. Use this shape:
  1. What happened.
  2. Real problems, if any.
  3. What I should do next.
  If more work is needed, give one copy-paste-ready prompt.
- `Level 2: Plain Explanation`: use when I ask for more detail. Explain the reason, files, checks, and tradeoffs in plain English. Avoid coder jargon unless needed.
- `Level 3: Full Audit`: use for audits, risky changes, bugs, protected contracts, or when I ask for rigorous detail. Include evidence, risks, assumptions, and exact next steps.
- Start with a concise opening outcome when there is a completed result to report. Include the concrete result, files touched, and checks run there instead of using a `Done` section.
- For normal implementation, status, and handoff runs, use only these real final sections in this order:
  - `Problems`: write `None. Proceed status: yes.` when clear. Otherwise list only real problems or caveats as `Low`, `Medium`, or `Severe`, with concrete evidence where practical. End with `Proceed status: yes.`, `Proceed status: yes with medium problems.`, or `Proceed status: no.`
  - `Suggestions`: write `None.` only when the request is complete and no useful continuation remains. Otherwise give exactly one next action: one human decision, one bounded executable phase, or one fenced paste-ready prompt.
- Mention successful validation briefly in the opening outcome. Mention only unresolved failed checks, generated-artifact risks, row-count/model-metric risks, or material caveats under `Problems`.
- Do not add extra final sections such as `Done`, `Tests`, `Validation`, `Notes`, `Changed`, or `Next Steps` unless the user explicitly asks for that format.
- If the user asks for an audit, review, or prompt template with a specific structure, use the requested structure while preserving all repo safety rules.
- Required system/developer appendages, app directives, git directives, and memory citations may appear after the repo-local final sections, but keep them minimal.
- For `Suggestions`, use `None.` only for true terminal one-shot work. If any nontrivial, risky, broad, provider/network, generated-artifact, cleanup, mutating, fresh-thread, gameplay/content, protected-contract, smoke-validation, or visual/UI follow-up remains, prefer one fenced paste-ready prompt.
- Use a human decision only when the agent cannot safely choose.
- Use a bounded executable phase only when follow-up is ready to run. For expensive, broad, data/model, provider/network, generated-artifact, cleanup, or mutating work, include command family, scope limit, timeout or stop budget, artifacts, forbidden patterns, expected generated files, and stop condition.
- A paste-ready prompt must state whether the next agent should plan only or execute, name the target objective, require repo path and `git status --short` inspection, require reconciliation against `CODEX_HANDOFF.md`, `README.md`, `docs/smoke_verification_workflow.md`, and current evidence, and include exact bounded scope, forbidden actions, artifacts, timeout or stop budget, stop condition, and validation expectations.
- If execution is not already safely bounded, the paste-ready prompt must request one implementable `<proposed_plan>` and explicitly say not to mutate files or run Godot, asset, save, smoke-batch, cleanup, or broad content commands yet.
- When `CODEX_HANDOFF.md` was updated or fresh-thread continuation is likely, start the paste-ready prompt with `Continue from CODEX_HANDOFF.md.`
- Do not use vague suggestions such as `continue implementation`, `run next phase`, or `improve the game`; convert them into `None.`, one human decision, one bounded executable phase, or one fenced paste-ready prompt.
- When `CODEX_HANDOFF.md` is updated, final `Suggestions` must match its exact next recommended step.
