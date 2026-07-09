# Audio Review Notes Template

Use this for the `workflow-evidence-audio` evidence path. Keep the pass bounded and observational. Do not change gameplay, content, data, scenes, assets, save behavior, scripts, buses, import settings, or queue items while collecting these notes.

## Session

- Date/time:
- Tester:
- Repo path: `C:\Users\donny\Desktop\hearthvale_godot`
- Git status summary:
- Build/run method:
- Audio device/output:
- Volume settings:
- Timebox: 10-15 minutes
- Stop condition: stop at the timebox, no audible output, a crash, a softlock, or one severe blocker.

## Route

Play the actual game from `scenes/main.tscn`.

1. Start or load a local account.
2. Open and close inventory/equipment/state panels.
3. Open bank, shop, and NPC dialogue panels.
4. Gather at least one resource.
5. Process or craft at least one item.
6. Fight one hostile mob and recover if needed.
7. Buy or sell one item.
8. Save and reload if practical.
9. Check pause, focus loss, or window background behavior if available.
10. Check scene/start-flow transitions if practical.

## Checklist

Record only behavior directly heard during this pass. Mark unsupported surfaces as `not supported`.

| Area | Observed behavior | Evidence detail | Severity | Candidate follow-up |
| --- | --- | --- | --- | --- |
| Missing cues |  |  |  |  |
| Wrong cues |  |  |  |  |
| Timing/cutoff |  |  |  |  |
| Overlap/repetition |  |  |  |  |
| Mix balance |  |  |  |  |
| Bus/volume behavior |  |  |  |  |
| Pause/focus behavior |  |  |  |  |
| Scene transition behavior |  |  |  |  |
| Spatial behavior if used |  |  |  |  |
| Unsupported surfaces |  |  |  |  |

## Concrete Defects

List only reproducible issues or clearly observed audio defects. Include exact action, context, expected result, actual result, and whether it blocks play or comprehension.

- Defect 1:
- Defect 2:
- Defect 3:

## Subjective Notes

Subjective notes can inform prioritization, but they are not implementation proof by themselves.

- Mix comfort:
- Repetition fatigue:
- Missing feedback moments:
- Harsh or distracting sounds:

## Evidence Decision

- Audio review evidence present: yes/no
- Any gameplay/content/code/asset/bus change authorized by this note alone: no
- Queue item this can close: `workflow-evidence-audio`
- Remaining evidence gaps:
