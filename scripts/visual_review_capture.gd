extends SceneTree

const MAIN_SCENE := preload("res://scenes/main.tscn")
const WORLD_SCENE := preload("res://scenes/world.tscn")
const HUD_SCENE := preload("res://scenes/hud.tscn")
const GAMEPLAY_CORE := preload("res://scripts/gameplay_core.gd")
const STATE_STORE_SCRIPT := preload("res://autoload/state_store.gd")

const OUTPUT_ROOT := "res://.godot/visual_review"
const CAPTURE_VIEWPORTS := [
	{"id": "compact_960x540", "label": "Compact 16:9", "size": Vector2i(960, 540)},
	{"id": "desktop_1280x720", "label": "Desktop 16:9", "size": Vector2i(1280, 720)},
	{"id": "wide_1600x900", "label": "Wide 16:9", "size": Vector2i(1600, 900)},
]
const SAMPLE_COLUMNS := 16
const SAMPLE_ROWS := 9
const MIN_LUMA_RANGE := 0.02
const MIN_DISTINCT_SAMPLES := 5

var output_dir := ""
var current_output_dir := ""
var current_viewport_id := ""
var current_viewport_label := ""
var current_viewport_size := Vector2i.ZERO
var captures := []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var watchdog := create_timer(30.0)
	watchdog.timeout.connect(func() -> void:
		push_error("Hearthvale visual review capture timed out.")
		quit(1)
	)

	output_dir = "%s/%s" % [OUTPUT_ROOT, _timestamp_slug()]
	if not _prepare_output_dir(output_dir):
		quit(1)
		return

	var passed := true
	for viewport in CAPTURE_VIEWPORTS:
		current_viewport_id = str(viewport.get("id", "viewport"))
		current_viewport_label = str(viewport.get("label", current_viewport_id))
		current_viewport_size = viewport.get("size", Vector2i(1280, 720))
		current_output_dir = "%s/%s" % [output_dir, current_viewport_id]
		if not _prepare_output_dir(current_output_dir):
			passed = false
			continue
		DisplayServer.window_set_size(current_viewport_size)
		root.size = current_viewport_size
		await _wait_render_frames(3)
		print("Capturing visual review viewport: %s %s" % [current_viewport_id, str(current_viewport_size)])
		passed = await _capture_all_states() and passed
	passed = _write_review_prompt() and passed

	await _clear_scene()
	if passed:
		print("Hearthvale visual review capture passed: %s" % output_dir)
		quit(0)
	else:
		push_error("Hearthvale visual review capture failed: %s" % output_dir)
		quit(1)


func _capture_all_states() -> bool:
	var passed := true
	passed = await _capture_start_screen() and passed
	passed = await _capture_hud_idle() and passed
	passed = await _capture_inventory_equipment() and passed
	passed = await _capture_bank_panel() and passed
	passed = await _capture_shop_panel() and passed
	passed = await _capture_dialogue_quest() and passed
	passed = await _capture_combat() and passed
	passed = await _capture_gathering_crafting() and passed
	passed = await _capture_minimap_camera() and passed
	return passed


func _capture_start_screen() -> bool:
	await _clear_scene()
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	return await _capture_current_view("start", "Start screen")


func _capture_hud_idle() -> bool:
	await _clear_scene()
	var fixture := await _create_fixture("visual_hud_idle")
	var hud: CanvasLayer = fixture["hud"]
	hud.select_tab("inventory")
	hud.set_feedback("Ready for a village supply run.")
	return await _capture_current_view("hud_idle", "HUD idle with world, account, inventory, feedback, and minimap")


func _capture_inventory_equipment() -> bool:
	await _clear_scene()
	var fixture := await _create_fixture("visual_inventory_equipment")
	var hud: CanvasLayer = fixture["hud"]
	hud.select_tab("equipment")
	hud.set_feedback("Bronze sword and shield equipped.")
	return await _capture_current_view("inventory_equipment", "Inventory and equipment panel")


func _capture_bank_panel() -> bool:
	await _clear_scene()
	var fixture := await _create_fixture("visual_bank_panel")
	var hud: CanvasLayer = fixture["hud"]
	hud.select_tab("inventory")
	hud.show_bank_panel()
	hud.set_feedback("Bank opened.")
	return await _capture_current_view("bank", "Bank deposit and withdraw panel")


func _capture_shop_panel() -> bool:
	await _clear_scene()
	var fixture := await _create_fixture("visual_shop_panel")
	var hud: CanvasLayer = fixture["hud"]
	hud.select_tab("inventory")
	hud.show_shop_panel({
		"name": "General Store",
		"stock": [
			{"item_id": "trail_ration", "price": 4},
			{"item_id": "bronze_axe", "price": 20},
			{"item_id": "fishing_rod", "price": 18},
		],
	})
	hud.set_feedback("Shop opened.")
	return await _capture_current_view("shop", "Shop buy and sell panel")


func _capture_dialogue_quest() -> bool:
	await _clear_scene()
	var fixture := await _create_fixture("visual_dialogue_quest")
	var hud: CanvasLayer = fixture["hud"]
	var quest_state := {
		"started": true,
		"completed": false,
		"flags": ["cooked_food", "smelted_bar", "smithed_gear", "equipped_weapon"],
	}
	hud.select_tab("quests")
	hud.show_dialogue_panel(
		{"id": "guide_01", "name": "Village Guide", "quest_id": "starter_path"},
		{"display_name": "Starter path"},
		quest_state,
		"Guide: Keep going. Still needed: eat food, defeat an enemy, use the bank, use the shop.",
		"Continue"
	)
	hud.set_feedback("Quest objective updated.")
	return await _capture_current_view("dialogue_quest", "Dialogue and quest objective panel")


func _capture_combat() -> bool:
	await _clear_scene()
	var fixture := await _create_fixture("visual_combat")
	var state: Dictionary = fixture["state"]
	var hud: CanvasLayer = fixture["hud"]
	state["combat"] = {
		"current_hitpoints": 6,
		"mobs": {"rat_01": {"hitpoints": 1, "dead": false}},
		"ground_items": [{"object_id": "visual_drop", "item_id": "coins", "quantity": 3, "tile": [16, 15], "type": "ground_item"}],
		"status_effects": {"poison": {"damage": 1, "rounds_remaining": 2}},
	}
	hud.refresh_state()
	hud.select_tab("state")
	hud.set_feedback("Hit Rat: 1/2 HP left; you: 6/10 HP; poison dealt 1 damage.")
	return await _capture_current_view("combat", "Combat feedback, health, drops, and status state")


func _capture_gathering_crafting() -> bool:
	await _clear_scene()
	var fixture := await _create_fixture("visual_gathering_crafting")
	var state: Dictionary = fixture["state"]
	var hud: CanvasLayer = fixture["hud"]
	state["inventory"] = {
		"bronze_axe": 1,
		"bronze_pickaxe": 1,
		"fishing_rod": 1,
		"logs": 4,
		"plain_plank": 2,
		"copper_ore": 2,
		"tin_ore": 2,
		"bronze_bar": 1,
		"raw_shrimp": 2,
		"cooked_shrimp": 1,
	}
	hud.refresh_state()
	hud.select_tab("skills")
	hud.set_feedback("Cooked shrimp; +30 Cooking XP. Tree will regrow soon.")
	return await _capture_current_view("gathering_crafting", "Gathering, crafting, XP, and resource feedback")


func _capture_minimap_camera() -> bool:
	await _clear_scene()
	var fixture := await _create_fixture("visual_minimap_camera")
	var world: Node = fixture["world"]
	var hud: CanvasLayer = fixture["hud"]
	if world.has_method("_set_camera_heading_degrees"):
		world.call("_set_camera_heading_degrees", 64.0)
	if world.has_method("_force_player_tile"):
		world.call("_force_player_tile", Vector2i(17, 15))
	hud.configure_minimap(world.get_minimap_data())
	hud.set_minimap_player_tile(Vector2i(17, 15))
	hud.set_minimap_heading(64.0)
	hud.set_feedback("Destination set near the crossroads.")
	return await _capture_current_view("minimap_camera", "Minimap, camera heading, destination, and navigation cues")


func _create_fixture(username: String) -> Dictionary:
	var store = STATE_STORE_SCRIPT.new()
	root.add_child(store)
	var state: Dictionary = store.create_default_state(username)
	_seed_visual_state(state)
	var world = WORLD_SCENE.instantiate()
	var hud = HUD_SCENE.instantiate()
	var gameplay = GAMEPLAY_CORE.new()
	root.add_child(world)
	root.add_child(hud)
	root.add_child(gameplay)
	await process_frame
	hud.bind_state(state)
	world.initialize_from_state(state)
	gameplay.setup(state, world, hud)
	if world.has_signal("selection_changed"):
		world.selection_changed.connect(hud.set_selection)
	if world.has_signal("hover_changed"):
		world.hover_changed.connect(hud.set_hover_target)
	if world.has_signal("feedback_changed"):
		world.feedback_changed.connect(hud.set_feedback)
	if world.has_signal("player_tile_changed"):
		world.player_tile_changed.connect(hud.set_player_tile)
		world.player_tile_changed.connect(hud.set_minimap_player_tile)
	if world.has_signal("camera_heading_changed"):
		world.camera_heading_changed.connect(hud.set_minimap_heading)
	if hud.has_signal("compass_reset_requested"):
		hud.compass_reset_requested.connect(world.reset_camera_north)
	hud.configure_minimap(world.get_minimap_data())
	hud.set_account(username)
	hud.set_player_tile(Vector2i(15, 15))
	hud.set_minimap_player_tile(Vector2i(15, 15))
	hud.set_minimap_heading(45.0)
	hud.refresh_state()
	return {"store": store, "state": state, "world": world, "hud": hud, "gameplay": gameplay}


func _seed_visual_state(state: Dictionary) -> void:
	state["inventory"] = {
		"coins": 125,
		"bronze_axe": 1,
		"bronze_pickaxe": 1,
		"fishing_rod": 1,
		"logs": 3,
		"plain_plank": 2,
		"copper_ore": 2,
		"tin_ore": 2,
		"raw_shrimp": 2,
		"cooked_shrimp": 1,
		"trail_ration": 2,
		"bronze_sword": 1,
	}
	state["bank"] = {"coins": 50, "copper_ore": 6, "logs": 8, "cooked_shrimp": 3}
	state["equipment"] = {"weapon": "bronze_sword", "shield": "bronze_shield"}
	state["quest_state"] = {
		"active_quest_id": "starter_path",
		"quests": {
			"starter_path": {
				"started": true,
				"completed": false,
				"flags": ["cooked_food", "smelted_bar", "smithed_gear", "equipped_weapon"],
			},
			"trail_supplies": {"started": true, "completed": false, "flags": ["gathered_wood"]},
		},
	}
	state["quest_progress"] = {}
	state["combat"] = {"current_hitpoints": 8, "mobs": {}, "ground_items": [], "status_effects": {}}


func _capture_current_view(state_id: String, label: String) -> bool:
	await _wait_render_frames(3)
	var image := root.get_texture().get_image()
	if not _image_has_content(image):
		push_error("Visual capture was blank or near-blank: %s" % state_id)
		return false
	var path := "%s/%s.png" % [current_output_dir, state_id]
	var err := image.save_png(path)
	if err != OK:
		push_error("Could not save visual capture %s: error %d" % [path, err])
		return false
	captures.append({
		"state_id": state_id,
		"label": label,
		"path": path,
		"viewport_id": current_viewport_id,
		"viewport_label": current_viewport_label,
		"viewport_size": current_viewport_size,
	})
	print("Captured visual review state: %s" % path)
	return true


func _image_has_content(image: Image) -> bool:
	if image == null or image.get_width() <= 0 or image.get_height() <= 0:
		return false
	var width := image.get_width()
	var height := image.get_height()
	var min_luma := 999.0
	var max_luma := -999.0
	var distinct := {}
	for row in range(SAMPLE_ROWS):
		var y := int(round(float(row) * float(height - 1) / float(max(1, SAMPLE_ROWS - 1))))
		for column in range(SAMPLE_COLUMNS):
			var x := int(round(float(column) * float(width - 1) / float(max(1, SAMPLE_COLUMNS - 1))))
			var color := image.get_pixel(x, y)
			var luma := (color.r + color.g + color.b) / 3.0
			min_luma = min(min_luma, luma)
			max_luma = max(max_luma, luma)
			var key := "%02d%02d%02d" % [int(color.r * 15.0), int(color.g * 15.0), int(color.b * 15.0)]
			distinct[key] = true
	return max_luma - min_luma >= MIN_LUMA_RANGE and distinct.size() >= MIN_DISTINCT_SAMPLES


func _write_review_prompt() -> bool:
	var lines := []
	lines.append("# Hearthvale Visual Review Prompt")
	lines.append("")
	lines.append("Review these real Godot screenshots for concrete visual defects only.")
	lines.append("")
	lines.append("Allowed findings: overlapping text/UI, clipping, missing assets, blank panels, unreadable or low-contrast text, confusing selected/disabled states, bad z-order, cropped controls, and obvious viewport framing problems.")
	lines.append("")
	lines.append("Do not judge fun, balance, subjective art direction, feature priority, or whether the game is complete. Do not infer gameplay bugs from screenshots alone.")
	lines.append("")
	lines.append("For each finding, cite the screenshot filename and describe the exact visible defect and affected UI/object.")
	lines.append("")
	lines.append("## Screenshots")
	lines.append("")
	for capture in captures:
		if capture is Dictionary:
			var size: Vector2i = capture.get("viewport_size", Vector2i.ZERO)
			lines.append("- `%s/%s.png` - %s %dx%d - %s" % [
				str(capture.get("viewport_id", "")),
				str(capture.get("state_id", "")),
				str(capture.get("viewport_label", "")),
				size.x,
				size.y,
				str(capture.get("label", "")),
			])
	var prompt_path := "%s/visual_review_prompt.md" % output_dir
	var file := FileAccess.open(prompt_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not write visual review prompt: %s" % prompt_path)
		return false
	file.store_string("\n".join(lines))
	print("Wrote visual review prompt: %s" % prompt_path)
	return true


func _prepare_output_dir(path: String) -> bool:
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("Could not create visual review output directory %s: error %d" % [path, err])
		return false
	return true


func _clear_scene() -> void:
	for child in root.get_children():
		child.queue_free()
	await process_frame
	await process_frame


func _wait_render_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _timestamp_slug() -> String:
	var now := Time.get_datetime_dict_from_system()
	return "%04d_%02d_%02d_%02d%02d%02d" % [
		int(now.get("year", 0)),
		int(now.get("month", 0)),
		int(now.get("day", 0)),
		int(now.get("hour", 0)),
		int(now.get("minute", 0)),
		int(now.get("second", 0)),
	]
