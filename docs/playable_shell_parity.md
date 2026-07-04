# Playable Shell Parity

Step 5 adds a minimal Godot playable shell without porting gameplay systems.

## Implemented

- Start/login scene: `scenes/start.tscn`
- Main world scene: `scenes/world.tscn`
- HUD scene: `scenes/hud.tscn`
- Main scene orchestration: `scenes/main.tscn` and `scripts/game_shell.gd`
- Camera controls: `W/A/S/D` pan, `Q/E` rotate, mouse wheel zoom
- Player movement: left-click or right-click empty ground to walk there
- Object click/select: left-click copied `world.json` objects to perform the default action and update HUD feedback
- Context options: right-click copied `world.json` objects to open a small "Choose Option" menu with default action and Examine entries
- Save/state connection: launch loads or creates state for the chosen username and updates player tile while walking

## Python Reference Comparison

Matched intentionally:

- Login/start flow enters the world after choosing a local username.
- Camera uses the same input family as the Python prototype: `W/A/S/D`, `Q/E`, and mouse wheel.
- Mouse interaction now follows the classic default/context split: left-click performs default object actions, right-click opens object options, and empty ground clicks walk.
- World shell is generated from copied `data/world.json` labels and tile positions.

Intentional parity deltas:

- Godot shell is 2D and uses colored placeholder rectangles; Panda3D 3D visuals are not ported yet.
- Pathfinding and blocked-tile routing are not implemented; right-click moves directly to the chosen tile.
- Left-click routes default interactions to the currently ported Godot gameplay/economy systems.
- Left-click attacks mobs at or below the player's current combat level; stronger mobs require right-click Attack.
- Right-click menus include Examine, explicit Attack on mobs, and carried rod/net options on fishing resources.
- HUD now includes inventory, equipment, skills, quests, and state panels, though it remains simpler than the Python UI.
- Camera is a `Camera2D`, so rotation/zoom are shell equivalents rather than Panda3D perspective camera parity.

## Verification

Focused smoke command:

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/playable_shell_smoke.gd --log-file .godot_logs\playable_shell.log
```

Observed output:

```text
Hearthvale playable shell smoke passed.
```

Manual interactive check:

1. Open `C:\Users\donny\Desktop\hearthvale_godot` in Godot 4.
2. Run `scenes/main.tscn`.
3. Start from the login screen.
4. Confirm the world appears with HUD account/tile/selection text.
5. Left-click or right-click an empty tile and confirm the player moves.
6. Left-click a resource, station, drop, NPC, or eligible mob and confirm the default action runs.
7. Right-click an object marker and confirm the option menu appears with default action and Examine choices.
