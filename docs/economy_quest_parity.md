# Economy And Quest Parity

Step 8 ports the minimal economy and quest layer needed for playable Godot progression.

## Implemented

- Bank station interaction that deposits one inventory stack, or withdraws one bank stack when nothing can be deposited.
- Shop station interaction that buys the first affordable stock item, or sells one sellable inventory stack when no purchase can be made.
- NPC interaction that starts, advances, completes, and repeats data-defined quests from `data/quests.json`.
- Quest state storage using the reset Godot save format under `quest_state` plus a `quest_progress` mirror for UI display.
- Quest reward application for item rewards and skill XP rewards.
- Quest progress flags from bank use, shop use, gathering, cooking, smelting, smithing, carpentry, herbalism, combat kills, and minimal weapon equip.
- HUD Quest tab showing active, started, available, and completed quest objective text.
- Focused smoke check for NPC dialogue -> shop -> equip -> bank -> quest reward flow.

## Python Reference Comparison

Matched intentionally:

- Bank deposit/withdraw moves item quantities between inventory and bank.
- Shop buy spends coins and adds stock; shop sell converts sellable inventory into coins.
- Bank and shop actions record `used_bank` and `used_shop` quest flags.
- Data-defined quests start on NPC talk, report missing objectives, complete once, then return completed text.
- Quest item and skill rewards are granted only on completion.
- Started/completed quest state and flags persist in save state.

Intentional parity deltas:

- Godot Step 8 has no bank or shop transaction dialog yet; clicking a station performs the first valid minimal transaction.
- Bank withdraw respects inventory slot capacity, but deposit has no bank capacity limit because the Python bank has no separate bank capacity.
- Shop stock is not depleted and quantities are fixed to one item per click.
- Quest reward capacity checks use the Godot shell inventory model and do not yet expose a recovery dialog.
- NPC dialogue is shown through HUD feedback only; full dialogue panels and choice UI remain future polish.
- Quest progress notifications are stored and visible in the Quest tab, but not yet appended to every action feedback string.
- Equipment is still minimal; Step 8 only adds a weapon equip helper needed for quest reward smoke coverage.

## Verification

Focused smoke command run with local Godot 4.7:

```powershell
& 'C:\Users\donny\Desktop\Godot_v4.7-stable_win64.exe' --headless --path . --script res://scripts/economy_quest_smoke.gd --log-file .godot_logs\economy_quest_pass.log
```

Observed output:

```text
Hearthvale economy and quest smoke passed.
```

The no-log variant crashes in this local Godot build before script execution because Godot cannot create `user://logs`. The `--log-file` workaround above allows the script to run and pass. The verifier still emits Godot startup/log-path noise unrelated to the gameplay assertion:

- `ERROR: Could not create directory: 'user://C:'` when using `--log-file` in this local shell.
- Windows root certificate store warning from Godot startup.

Manual verification:

1. Open `C:\Users\donny\Desktop\hearthvale_godot` in Godot 4.7.
2. Run `scenes/main.tscn`.
3. Start from the login scene.
4. Click an NPC marker to start a quest and confirm the HUD feedback changes.
5. Click the shop marker and confirm coins change and `used_shop` appears in the Quest tab.
6. Click the bank marker and confirm inventory/bank quantities change and `used_bank` appears.
7. Return to the matching quest NPC after its flags are complete and confirm rewards apply once.
