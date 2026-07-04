# Model And Animation Recreation Plan

This pass audits the current Godot visual state and begins the safest model/animation path without bulk-converting old Panda3D assets.

## Current Godot Coverage

- Godot currently uses generated low-poly primitives in `scripts/world.gd`.
- Portable PNG icons, textures, sprites, and WAV audio are already copied and tracked through `assets/asset_manifest.json`.
- `data/world.json` has enough semantic visual data to drive original Godot-native recreation:
  - resources by `skill_id`,
  - decorations by `kind`,
  - mobs by `visual_kind`,
  - stations by `station_id`.
- `scripts/visual_recreation_smoke.gd` checks that mob `visual_kind` values produce distinct Godot-native silhouettes.

## Read-Only Python Reference

The old Python project at `C:\Users\donny\Desktop\hearthvale` remains read-only. The asset files found there are:

| Source | Count | Decision |
| --- | ---: | --- |
| `game/assets/models/*.egg` | 5 | Do not bulk-copy or bulk-convert yet. Use only as shape intent/reference until licensing/originality and Godot import quality are reviewed. |
| `game/assets/animations/*.json` | 10 | Do not copy as runtime animation data. Recreate as Godot `AnimationPlayer` clips or lightweight procedural motion. |
| `game/assets/icons/**/*.png`, `sprites/**/*.png`, `textures/**/*.png`, `audio/**/*.wav` | existing portable assets | Already copied into Godot and covered by asset fallback/data validation smoke. |

Known Panda3D-native model references:

- `mob.egg`
- `npc.egg`
- `player.egg`
- `rock.egg`
- `tree.egg`

Known animation intent references:

- `player_idle.json`
- `player_walk.json`
- `player_combat_attack.json`
- `player_combat_strength.json`
- `player_combat_defence.json`
- `player_combat_ranged.json`
- `player_combat_magic.json`
- `player_combat_reaction.json`
- `npc_mob_idle.json`
- `npc_mob_combat_response.json`

## Asset Decisions

| Category | Decision | Rationale |
| --- | --- | --- |
| Player model | Recreate first in Godot-native primitives or a new original `.glb`; do not import `player.egg` yet. | Player readability matters most, and the old file is Panda3D-specific. |
| NPC model | Recreate after player baseline. | NPCs can share a simple rig/silhouette family. |
| Mob model | Recreate by `visual_kind` before importing old `mob.egg`. | `world.json` has richer mob variety than one generic mob file. |
| Tree and rock models | Recreate as procedural or new original static meshes. | Current resource primitives already work and are safer than conversion churn. |
| Animation specs | Translate intent manually, not mechanically. | The JSON files describe part motion, not Godot animation resources. |
| Bulk conversion | Defer. | No clear Godot import path, ownership review, or quality gate is proven yet. |

## Pipeline

1. Keep using `data/world.json` as the visual taxonomy source.
2. Prefer original Godot-native procedural silhouettes for immediate coverage.
3. For authored models, create or import only original `.glb`/`.gltf` files into `assets/models/`.
4. Add every authored model to a small manifest section before use.
5. Add one smoke per visual slice that proves scene load and expected node/resource availability.
6. Only convert `.egg` files manually after confirming:
   - the source is original Hearthvale material,
   - the conversion toolchain is known,
   - the result imports cleanly in Godot 4.7,
   - the converted asset improves over the current Godot-native placeholder.

## This Pass

Implemented a low-risk Godot-native recreation slice:

- `scripts/world.gd` now uses `visual_kind` to give mobs distinct primitive silhouettes.
- `scripts/visual_recreation_smoke.gd` verifies rat, skeleton, wolf, slime, mire bat, fen crawler, target dummy, mage imp, archer goblin, bandit, and generic goblin visual coverage.

## Remaining Gaps

- No authored `.glb`/`.gltf` model files exist yet.
- No Godot `AnimationPlayer` clips or rigged characters exist yet.
- Player and NPC silhouettes are still generic generated primitives.
- Resource and station visuals are distinct but still procedural placeholders.
- No runtime model manifest exists for future authored 3D assets.
- No visual screenshot/pixel verification exists for model framing.
