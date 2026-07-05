extends SceneTree

const SNAPSHOT_PATH := "res://.godot_logs/state_snapshot_phase6.json"
const StateSnapshot = preload("res://scripts/state_snapshot.gd")


func _init() -> void:
	var store = preload("res://autoload/state_store.gd").new()
	var state: Dictionary = store.create_default_state("codex_state_snapshot_smoke")
	state["inventory"] = {"coins": 42, "logs": 3}
	state["bank"] = {"bronze_sword": 1}
	state["player"] = {"tile": Vector2i(18, 15), "position": [18.5, 15.5]}
	state["quest_state"] = {"active_quest_id": "starter_path", "quests": {"starter_path": {"started": true, "completed": false, "flags": ["created_save"]}}}
	state["quest_progress"] = state["quest_state"]["quests"].duplicate(true)
	state["combat"] = {"current_hitpoints": 7, "mobs": {"debug_dummy": {"hitpoints": 3, "dead": false}}, "ground_items": [{"item_id": "bones", "quantity": 1}], "status_effects": {"poison": {"damage": 1, "rounds_remaining": 2}}}
	state["world"] = {"resource_nodes": {"smoke_tree": {"depleted": true, "respawn_at": 12.0}}, "action_clock_seconds": 3.5, "weather": "rain"}

	var snapshot := StateSnapshot.capture(state, "phase6_smoke", {"source": "state_snapshot_smoke"})
	var passed := _assert_snapshot_shape(snapshot)
	state["inventory"] = {"coins": 999}
	state["player"] = {"tile": [5, 5], "position": [5.5, 5.5]}
	var restore_result: Dictionary = StateSnapshot.restore_into(state, snapshot)
	passed = passed and bool(restore_result.get("success", false))
	passed = passed and int(state.get("inventory", {}).get("coins", 0)) == 42
	passed = passed and state.get("player", {}).get("tile", []) == [18, 15]
	passed = passed and int(state.get("combat", {}).get("current_hitpoints", 0)) == 7

	var export_result: Dictionary = StateSnapshot.export_to_file(SNAPSHOT_PATH, snapshot)
	passed = passed and bool(export_result.get("success", false))
	var import_result: Dictionary = StateSnapshot.import_from_file(SNAPSHOT_PATH)
	passed = passed and bool(import_result.get("success", false))
	var imported_snapshot: Dictionary = import_result.get("snapshot", {})
	var restored := {}
	var imported_restore: Dictionary = StateSnapshot.restore_into(restored, imported_snapshot)
	passed = passed and bool(imported_restore.get("success", false))
	passed = passed and int(restored.get("inventory", {}).get("logs", 0)) == 3
	passed = passed and str(imported_snapshot.get("label", "")) == "phase6_smoke"
	passed = passed and int(imported_snapshot.get("summary", {}).get("quests", {}).get("started", 0)) == 1
	passed = passed and int(StateSnapshot.summarize_state(restored).get("combat", {}).get("alive_mobs", 0)) == 1

	store.free()
	if passed:
		print("Hearthvale state snapshot smoke passed.")
		quit(0)
	else:
		push_error("Hearthvale state snapshot smoke failed.")
		quit(1)


func _assert_snapshot_shape(snapshot: Dictionary) -> bool:
	if str(snapshot.get("schema", "")) != StateSnapshot.SNAPSHOT_SCHEMA:
		return false
	if str(snapshot.get("label", "")) != "phase6_smoke":
		return false
	if not (snapshot.get("state", {}) is Dictionary):
		return false
	var summary = snapshot.get("summary", {})
	if not (summary is Dictionary):
		return false
	if int(summary.get("inventory", {}).get("total_quantity", 0)) != 45:
		return false
	return summary.get("player_tile", []) == [18, 15]
