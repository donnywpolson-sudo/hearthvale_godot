# Export Platform Review Notes Template

Use this for the `workflow-evidence-export-platform-parity` evidence path. Keep the pass bounded and observational. Do not change gameplay, content, data, scenes, assets, save behavior, scripts, export presets, build settings, or queue items while collecting these notes.

## Session

- Date/time:
- Tester:
- Repo path: `C:\Users\donny\Desktop\hearthvale_godot`
- Git status summary:
- Godot version:
- Target platform:
- Export preset used:
- Export command or manual export path:
- Build output path:
- Timebox:
- Stop condition: stop after export failure, launch failure, one severe blocker, or the planned smoke route is complete.

## Export Evidence

Record only what was actually run or inspected.

- Export preset present: yes/no/not supported
- Export completed: yes/no/not run
- Build artifact path:
- Build artifact timestamp:
- Launch result: launched/failed/not run
- Generated logs:
- Known unsupported platforms:

## Smoke Route

Run the exported build only when release confidence matters and export/build artifacts are intentionally allowed.

1. Launch the exported build.
2. Start or load a local account.
3. Confirm the main scene renders.
4. Move the player and interact with one world object.
5. Open inventory/equipment/state UI.
6. Open bank, shop, and NPC dialogue if reachable.
7. Gather or process one item if practical.
8. Save and reload if practical.
9. Check window/fullscreen/high-DPI behavior if applicable.
10. Check audio and input availability at a basic level.

## Checklist

Mark unsupported surfaces as `not supported`.

| Area | Observed behavior | Evidence detail | Severity | Candidate follow-up |
| --- | --- | --- | --- | --- |
| Export preset availability |  |  |  |  |
| Export command/result |  |  |  |  |
| Build artifact integrity |  |  |  |  |
| Launch/start flow |  |  |  |  |
| Save/load continuity |  |  |  |  |
| Visual parity |  |  |  |  |
| Audio availability |  |  |  |  |
| Input behavior |  |  |  |  |
| Window/fullscreen behavior |  |  |  |  |
| Platform-specific logs |  |  |  |  |
| Unsupported platforms |  |  |  |  |

## Concrete Defects

List only reproducible export or platform defects. Include exact target platform, command or export path, build artifact, expected result, actual result, and whether it blocks release confidence.

- Defect 1:
- Defect 2:
- Defect 3:

## Evidence Decision

- Export/platform review evidence present: yes/no
- Any gameplay/content/code/asset/export-preset change authorized by this note alone: no
- Queue item this can close: `workflow-evidence-export-platform-parity`
- Remaining evidence gaps:
