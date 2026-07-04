# Asset Conversion Inventory

Step 3 copied portable JSON data, PNG artwork, WAV audio, and source reference docs from `C:\Users\donny\Desktop\hearthvale`. The Python source repo remained read-only.

## Copied Portable Content

- `game/data/*.json` -> `data/`
- `game/assets/asset_manifest.json` -> `assets/asset_manifest.json`
- `game/assets/audio/*.wav` -> `assets/audio/`
- `game/assets/icons/**/*.png` -> `assets/icons/`
- `game/assets/sprites/**/*.png` -> `assets/sprites/`
- `game/assets/textures/*.png` -> `assets/textures/`
- `game/assets/README.md` -> `docs/source_reference/python_assets_README.md`
- `docs/graphics_visual_bible.md` -> `docs/source_reference/graphics_visual_bible.md`
- `docs/icon_asset_options.md` -> `docs/source_reference/icon_asset_options.md`
- `README.md` -> `docs/source_reference/README.md`
- `PROJECT_OUTLINE.md` -> `docs/source_reference/PROJECT_OUTLINE.md`

No source `.github` directory was present, so no workflows or templates were copied.

## Excluded Runtime And Local State

- `.git/`, `.agents/`, `.codex/`
- `.pytest_cache/`, `.venv/`, `.vscode/`, `__pycache__/`
- `build/`, `dist/`
- `logs/`, `reports/`, `saves/`, `telemetry/`
- Python code, tests, launcher scripts, packaging files, `requirements.txt`, `users.db`
- `AGENTS.md`, `CODEX_HANDOFF.md`, and handoff archives

## Panda3D Models Requiring Conversion

These `.egg` models were not copied because they are Panda3D-native source assets and need conversion or replacement for Godot:

| Source path | Size | Godot action |
| --- | ---: | --- |
| `game/assets/models/mob.egg` | 32,884 bytes | Convert or recreate as `.glb`/`.gltf`, then import in Godot. |
| `game/assets/models/npc.egg` | 41,495 bytes | Convert or recreate as `.glb`/`.gltf`, then import in Godot. |
| `game/assets/models/player.egg` | 68,809 bytes | Convert or recreate as `.glb`/`.gltf`; preserve named animation intent if still needed. |
| `game/assets/models/rock.egg` | 22,051 bytes | Convert or replace with a Godot-native static mesh/resource. |
| `game/assets/models/tree.egg` | 23,146 bytes | Convert or replace with a Godot-native static mesh/resource. |

## Legacy Animation Specs Requiring Conversion

These JSON animation definitions were not copied into `assets/` because they are Python/Panda3D-side animation specs, not Godot `AnimationPlayer`, `SpriteFrames`, or imported animation resources:

| Source path | Size | Godot action |
| --- | ---: | --- |
| `game/assets/animations/npc_mob_combat_response.json` | 474 bytes | Recreate as Godot animation state or imported clip. |
| `game/assets/animations/npc_mob_idle.json` | 269 bytes | Recreate as Godot animation state or imported clip. |
| `game/assets/animations/player_combat_attack.json` | 876 bytes | Recreate as Godot animation state or imported clip. |
| `game/assets/animations/player_combat_defence.json` | 878 bytes | Recreate as Godot animation state or imported clip. |
| `game/assets/animations/player_combat_magic.json` | 875 bytes | Recreate as Godot animation state or imported clip. |
| `game/assets/animations/player_combat_ranged.json` | 877 bytes | Recreate as Godot animation state or imported clip. |
| `game/assets/animations/player_combat_reaction.json` | 883 bytes | Recreate as Godot animation state or imported clip. |
| `game/assets/animations/player_combat_strength.json` | 883 bytes | Recreate as Godot animation state or imported clip. |
| `game/assets/animations/player_idle.json` | 856 bytes | Recreate as Godot animation state or imported clip. |
| `game/assets/animations/player_walk.json` | 862 bytes | Recreate as Godot animation state or imported clip. |

## Other Non-Native References

- `game/assets/runtime.py` and `game/assets/__init__.py` are Python runtime helpers and were not copied.
- The copied `assets/asset_manifest.json` is useful as source metadata for icons, effects, and audio, but any Godot loader should be implemented later in GDScript rather than reusing Python runtime code.
