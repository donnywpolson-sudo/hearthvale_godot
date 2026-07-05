# Hearthvale Model Assets

This folder is for future original Godot-ready 3D models.

## Format

- Use `.glb` or `.gltf` for authored models.
- Keep source files in a separate art/source folder unless they are meant to be imported by Godot.
- Add runtime model entries to `assets/asset_manifest.json` under the optional `models` section.

## Scale And Origin

- One gameplay tile is `1.0` Godot world unit.
- Small props should fit inside one tile unless they are intentionally large scenery.
- Place the model origin at the bottom center of the object so it can align to `world.json` tile positions.
- Face the model's readable/front side toward negative Z when practical, matching current procedural objects.

## Style

- Keep the look original, chunky, and readable from the angled top-down camera.
- Use low-poly silhouettes, softened edges, and simple material groups.
- Avoid photoreal textures, noisy surface detail, branded lookalikes, copied maps, copied models, or near-branded fantasy terms.

## Import Expectations

- Prefer a small number of reusable materials per model.
- Keep collision and gameplay placement driven by `data/world.json`; models are visual only unless a future task explicitly changes that.
- Verify each model in Godot 4.7 before referencing it from code or data.
