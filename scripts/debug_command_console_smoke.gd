extends SceneTree


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := create_timer(4.0)
	watchdog.timeout.connect(func() -> void:
		push_error("Hearthvale debug command console smoke timed out.")
		quit(1)
	)

	var store = preload("res://autoload/state_store.gd").new()
	store.save_dir = "res://.godot_smoke_saves"
	var state: Dictionary = store.create_default_state("codex_debug_command_console_smoke")
	var world = preload("res://scenes/world.tscn").instantiate()
	var hud = preload("res://scenes/hud.tscn").instantiate()
	var gameplay = preload("res://scripts/gameplay_core.gd").new()
	var console = preload("res://scripts/debug_command_console.gd").new()
	root.add_child(world)
	root.add_child(hud)
	root.add_child(gameplay)
	root.add_child(console)
	await process_frame
	hud.bind_state(state)
	world.initialize_from_state(state)
	gameplay.setup(state, world, hud)
	world.object_activated.connect(gameplay.activate_object)
	console.setup(state, world, hud, gameplay)

	var passed := true
	passed = passed and _assert_command(console, "give_item coins 25")
	passed = passed and int(state.get("inventory", {}).get("coins", 0)) == 25
	passed = passed and _assert_command(console, "set_skill woodcutting 8 700")
	passed = passed and int(state.get("skills", {}).get("woodcutting", {}).get("level", 0)) == 8
	passed = passed and _assert_command(console, "set_quest_state starter_path started")
	passed = passed and bool(state.get("quest_state", {}).get("quests", {}).get("starter_path", {}).get("started", false))
	passed = passed and _assert_command(console, "teleport 18 15")
	passed = passed and state.get("player", {}).get("tile", []) == [18, 15]
	passed = passed and world.call("debug_current_tile") == Vector2i(18, 15)
	passed = passed and _assert_command(console, "spawn_enemy debug_dummy 2 3")
	passed = passed and state.get("combat", {}).get("mobs", {}).has("debug_dummy")
	passed = passed and _assert_command(console, "spawn_drop bones 2")
	var drops = state.get("combat", {}).get("ground_items", [])
	passed = passed and drops is Array and drops.size() == 1 and int(drops[0].get("quantity", 0)) == 2
	passed = passed and _assert_command(console, "damage 2")
	passed = passed and int(state.get("combat", {}).get("current_hitpoints", 0)) == 8
	passed = passed and _assert_command(console, "heal")
	passed = passed and int(state.get("combat", {}).get("current_hitpoints", 0)) == 10
	passed = passed and _assert_command(console, "force_weather rain")
	passed = passed and str(state.get("world", {}).get("weather", "")) == "rain"
	passed = passed and not bool(console.execute_command("give_item coins -1").get("success", true))

	store.free()
	if passed:
		print("Hearthvale debug command console smoke passed.")
		quit(0)
	else:
		push_error("Hearthvale debug command console smoke failed.")
		quit(1)


func _assert_command(console: Node, command_line: String) -> bool:
	var result: Dictionary = console.execute_command(command_line)
	if not bool(result.get("success", false)):
		push_error("Debug command failed unexpectedly: %s -> %s" % [command_line, str(result.get("message", ""))])
		return false
	return true
