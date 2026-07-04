extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var main = preload("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var has_start_screen := main.get("start_screen") != null
	var state_store = main.get("state_store")
	if state_store != null:
		state_store.save_dir = "res://.godot_smoke_saves"
	if main.has_method("_start_world"):
		main.call("_start_world", "codex_boot_smoke")
	await process_frame
	await process_frame
	var has_world := main.get("world") != null
	var has_hud := main.get("hud") != null
	var has_gameplay := main.get("gameplay") != null
	var state = state_store.current_state if state_store != null else {}
	var has_state := state is Dictionary and str(state.get("username", "")) == "codex_boot_smoke"
	if has_start_screen and has_world and has_hud and has_gameplay and has_state:
		print("Hearthvale boot flow smoke passed.")
		quit(0)
	else:
		push_error("Hearthvale boot flow smoke failed.")
		quit(1)
