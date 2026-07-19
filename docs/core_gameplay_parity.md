# Core Gameplay Parity

The Godot core loop is data-driven and state-first. It now includes timed actions,
resource respawns, blocked-tile routing, interaction-range checks, inventory
capacity guards, and focused regression coverage in addition to the original
Step 7 gathering, processing, combat, drop, and progression paths.

## Implemented

- Resource gathering from copied `data/world.json`
- Tool and level checks for gathering
- Cooking from raw item definitions in `data/items.json`
- Smelting, smithing, carpentry, and herbalism recipes from `data/recipes.json`
- Combat against copied mob definitions
- Collision-safe ground drops with persistent IDs, deterministic nearest-tile placement, reload, and isolated pickup
- XP grants and level-up feedback using `data/skills.json` thresholds and milestones
- Save-state mutation for inventory, skills, combat HP, mob state, ground items, resource depletion, and world resource state
- HUD refresh after gameplay actions
- Realtime active-play clocks for cooldowns, buffs, resource respawns, and mob respawns; deterministic harnesses request manual clock mode
- Atomic Carpentry specialization returns, authoritative shop-stock pricing, and combat XP based on actual HP removed

## Python Reference Comparison

Matched intentionally:

- Gathering checks required tools and skill levels, grants item rewards and XP.
- Cooking consumes raw fish, creates cooked items, and grants Cooking XP.
- Processing recipes consume inputs, create outputs, and grant the recipe skill XP.
- Combat grants style XP plus Hitpoints XP, applies basic enemy damage, defeats mobs, and creates drops.
- Drops are picked up into inventory and removed from ground state.
- Level-up feedback is appended when XP crosses copied skill thresholds.

Intentional parity deltas:

- Actions use deterministic timers and data-driven respawns; richer progress UI,
  cancellation, and randomized balance tuning remain future work.
- Gathering uses deterministic smoke coverage for respawn and secondary-drop
  chances; randomized success/burn balance and broader node-capacity behavior
  remain simplified.
- Cooking never burns food in this shell; Python uses burn chance.
- Recipe pickers now expose the available cooking, smelting, smithing, carpentry,
  and herbalism recipes; quantity processing and burn chances remain future work.
- Combat now includes selected-style XP, poison, and cleansing persistence; hit
  chance, cadence, richer enemy behavior, and broader status systems remain
  simplified.
- Inventory capacity and all-or-nothing reward/transaction guards are covered by
  progression, interaction, and save/load smokes; Python property-test depth is
  not yet matched.
- Drops render as simple ground item markers, not full Python loot windows.
- Quest rewards and progression logic are now covered by Step 8.

## Verification

The focused smoke covers gathering, carpentry, smelting, smithing, cooking, combat, drop creation, and drop pickup. `runtime_integration_smoke.gd` covers the real scene clock/autosave wiring, while `ground_loot_regression_smoke.gd` covers multi-drop collision safety and reload.

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/core_gameplay_smoke.gd --log-file .godot_logs\core_gameplay.log
```

Observed output:

```text
Hearthvale core gameplay smoke passed.
```

Manual interactive check:

1. Open `C:\Users\donny\Desktop\hearthvale_godot` in Godot 4.
2. Run `scenes/main.tscn`.
3. Start from the login screen.
4. Click a resource marker and confirm inventory and skill XP update.
5. Click a processing station with matching materials and confirm output/XP update.
6. Click a mob marker until defeated, then click the drop marker and confirm loot enters inventory.
