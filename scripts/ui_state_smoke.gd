extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := create_timer(4.0)
	watchdog.timeout.connect(func() -> void:
		push_error("Hearthvale UI state smoke timed out.")
		quit(1)
	)

	var store = preload("res://autoload/state_store.gd").new()
	var state: Dictionary = store.create_default_state("codex_ui_smoke")
	state["inventory"]["coins"] = 125
	state["inventory"]["logs"] = 3
	state["bank"] = {"coins": 50, "copper_ore": 6}
	state["equipment"] = {"weapon": "bronze_sword", "shield": "bronze_shield"}
	state["quest_progress"] = {"starter_path": {"started": true, "completed": false}}

	var hud = preload("res://scenes/hud.tscn").instantiate()
	root.add_child(hud)
	await process_frame
	hud.bind_state(state)
	var passed: bool = hud.run_ui_state_smoke()
	store.free()
	if passed:
		print("Hearthvale UI state smoke passed.")
		quit(0)
	else:
		push_error("Hearthvale UI state smoke failed.")
		quit(1)
