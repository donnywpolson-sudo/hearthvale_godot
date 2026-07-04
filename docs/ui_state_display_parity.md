# UI State Display Parity

Step 6 added the first Godot UI/state display layer. Later steps now feed it gameplay, economy, and quest state.

## Implemented

- HUD account, tile, selection, and feedback text
- Feedback history stored for display in the State panel
- Tabbed state panel:
  - Inventory: inventory slots, stack quantities, bank stacks
  - Equipment: expected equipment slots and equipped item names
  - Skills: skill levels and XP from save state
  - Quests: active, started, available, and completed quest objective text
  - State: time, hitpoints, raw quest progress, settings, feedback history
- Inventory display reads `data/items.json` for names, categories, and stackability.
- Skills display reads `data/skills.json` for display names.
- The shell binds the HUD to `StateStore.current_state` after login/start.

## Python Reference Comparison

Matched intentionally:

- Core HUD surfaces: account/time-like state, feedback, inventory, equipment, skills, and quest/settings summaries.
- Inventory slot behavior expands non-stackable items and groups stackable items.
- Inventory ordering follows the Python category order broadly: currency, tools, weapons, armor, wood, ore, bars, fish, misc.
- Equipment uses the same slot names as the Python HUD.
- Skills show the same level/XP state shape from saves.

Intentional parity deltas:

- Godot UI is a simple Control-based panel, not the full Panda3D styled HUD.
- Item icons are not wired into the panel yet; slot text names are used.
- Context menus, item examine/drop/use, equip/unequip, bank/shop transaction dialogs, skill search/filter details, compact HUD, minimap, and full chat scrolling are not ported yet.
- The Quest tab computes objective text from copied `data/quests.json`, but the UI is still simpler than the Python dialogue and quest surfaces.

## Verification

Focused smoke command:

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/ui_state_smoke.gd --log-file .godot_logs\ui_state.log
```

Observed output:

```text
Hearthvale UI state smoke passed.
```

Manual interactive check:

1. Open `C:\Users\donny\Desktop\hearthvale_godot` in Godot 4.
2. Run `scenes/main.tscn`.
3. Start from the login screen.
4. Confirm the HUD shows account, tile, selection, and feedback.
5. Click Inventory, Equipment, Skills, and State tabs.
6. Confirm each tab mirrors the current save state.
