# Hearthvale Graphics Visual Bible

## Purpose

Give Hearthvale a coherent retro fantasy MMO look that is original, readable at distance, and consistent across world, UI, animation, and feedback.

## Visual Targets

- Read clearly from a zoomed-out top-down camera.
- Use chunky silhouettes and simple forms before fine detail.
- Favor low-poly shapes, strong value contrast, and a limited family of earthy colors.
- Keep the world bright enough to feel open, but never washed out.
- Make every major system look like it belongs in the same world language.

## What It Should Feel Like

- Hand-built, grounded, slightly stylized, and immediately legible.
- A classic adventure world with practical fantasy tools, towns, ruins, fields, woods, and simple danger cues.
- Familiar in structure, but not borrowed in names, icons, maps, formulas, or specific art assets.

## What It Should Not Feel Like

- Not modern glossy fantasy.
- Not photoreal.
- Not soft pastel cozy-sim.
- Not clone-like or brand-adjacent.
- Not a palette swap over placeholder geometry.

## Core Style Rules

### Silhouette First

- Every object should read by shape before texture.
- Trees, rocks, NPCs, mobs, tools, and buildings need distinct outlines at game camera distance.
- Important gameplay objects should have an obvious top-down silhouette and a visible interaction marker.

### Material Language

- Use a small set of reusable material families: grass, dirt, water, stone, wood, cloth, skin, metal, gold, organic, bone, gel, spark.
- Each family should have a dark, mid, and light value.
- Materials should be stylized, not noisy.
- Procedural patterns must support form, not fight it.

### Color Language

- Base the world on muted natural tones.
- Reserve bright gold, blue, red, and green for gameplay emphasis, not decoration.
- Keep UI warmth separate from world greenery so panels and terrain do not blend together.
- Use stronger contrast for interaction states, unlocks, damage, loot, and level-up feedback.

### Lighting Language

- Prefer a readable daylight look with soft ambient fill and stronger directional highlights.
- Avoid dark, cramped dungeon lighting for the default world read.
- Shadows should help shape and separation, not hide the scene.
- Fog or distance fade should support camera legibility, not flatten the horizon.

### Camera and Read Distance

- The scene must remain readable from a fixed top-down/angled camera.
- Large shapes matter more than tiny texture detail.
- Small props may be simple, but important ones must still pop through value and silhouette.

## World Art Direction

### Terrain

- Grass should feel worn and tiled, not smooth or grassy-plastic.
- Dirt paths should read as trampled and traveled.
- Water should be darker, simple, and reflective enough to separate from grass.
- Shorelines should clearly bridge the two, with a distinct edge treatment.

### Props

- Trees should be chunky and iconic, with a clear trunk/canopy split.
- Rocks should look hand-cut and readable, not like random blobs.
- Resource nodes should be obvious from range and should look different by skill.
- Buildings and stations should read as functional fantasy objects with simple roof, wall, and support shapes.

### Characters

- Player, NPCs, and mobs need strong body proportions and easy-to-read roles.
- Combat stances should be visible in silhouette.
- Tools and weapons must be recognizable at zoomed-out distance.
- Idle motion should be subtle and rhythmic, not floaty.

### Effects

- FX should be sparse, bold, and useful.
- XP, level-up, unlock, hit, miss, loot, respawn, and gather feedback should use distinct visual cues.
- Effects must not overwhelm the low-poly scene.

## UI Art Direction

- Use parchment, stone, leather, and brass cues.
- Panels should feel sturdy and game-like, not glassy or modern.
- Buttons, tabs, and icons should have clear state changes.
- Fonts and labels should prioritize legibility over decoration.
- Feedback text should be short, consistent, and visually coded.

## First Implementation Slice

1. Rebuild the shared world palette and surface helpers.
2. Rework terrain, shoreline, water, trees, and the main gameplay markers.
3. Restyle the HUD and login screen to match the world language.
4. Tune daylight, shadows, and idle motion so the scene reads as one system.

## Forbidden Drift

- Do not copy branded maps, names, icons, dialogue, music, or formulas.
- Do not add near-brand names or obvious lookalike assets.
- Do not use modern UI chrome, neon sci-fi motifs, or hyper-detailed realism.

## Success Criteria

- The world looks intentionally authored, not placeholder-derived.
- UI and world share one visual grammar.
- Gameplay objects are readable at a glance.
- The first graphics rewrite slice produces a visible improvement without breaking unrelated systems.
