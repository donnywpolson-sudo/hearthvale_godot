# Core Gameplay Parity

Step 7 adds a minimal playable Godot core loop. It is intentionally data-driven and state-first; it does not port every Python timing, pathfinding, animation, capacity, shop, bank, or quest rule.

## Implemented

- Resource gathering from copied `data/world.json`
- Tool and level checks for gathering
- Cooking from raw item definitions in `data/items.json`
- Smelting, smithing, carpentry, and herbalism recipes from `data/recipes.json`
- Combat against copied mob definitions
- Ground drops and pickup
- XP grants and level-up feedback using `data/skills.json` thresholds and milestones
- Save-state mutation for inventory, skills, combat HP, mob state, ground items, resource depletion, and world resource state
- HUD refresh after gameplay actions

## Python Reference Comparison

Matched intentionally:

- Gathering checks required tools and skill levels, grants item rewards and XP.
- Cooking consumes raw fish, creates cooked items, and grants Cooking XP.
- Processing recipes consume inputs, create outputs, and grant the recipe skill XP.
- Combat grants style XP plus Hitpoints XP, applies basic enemy damage, defeats mobs, and creates drops.
- Drops are picked up into inventory and removed from ground state.
- Level-up feedback is appended when XP crosses copied skill thresholds.

Intentional parity deltas:

- Actions complete immediately in Godot Step 7; Python systems use pending timers and repeated updates.
- Gathering success is deterministic and depletes a node after one reward; Python has success chance, node capacity, and respawn timing.
- Cooking never burns food in this shell; Python uses burn chance.
- Recipe choice dialogs are not ported; the first available matching recipe for a station is processed.
- Combat is simplified to deterministic damage and click-driven attacks; Python has hit chance, attack cadence, range-specific retaliation, poison, passive training behavior, and richer bonuses.
- Inventory capacity is partially enforced for some economy/reward paths but not yet covered to Python property-test depth.
- Drops render as simple ground item markers, not full Python loot windows.
- Quest rewards and progression logic are now covered by Step 8.

## Verification

The focused smoke covers gathering, carpentry, smelting, smithing, cooking, combat, drop creation, and drop pickup.

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
