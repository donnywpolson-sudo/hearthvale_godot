extends Node3D

signal selection_changed(label: String)
signal feedback_changed(message: String)
signal player_tile_changed(tile: Vector2i)
signal object_activated(object_data: Dictionary)

const WORLD_DATA_PATH := "res://data/world.json"
const TILE_SIZE := 1.0
const PLAYER_SPEED := 5.2
const CAMERA_PAN_SPEED := 7.0
const CAMERA_ROTATE_SPEED := 1.4
const CAMERA_PITCH_DEGREES := -38.0
const CAMERA_HEIGHT := 5.8
const CAMERA_DISTANCE := 7.8
const CAMERA_FOV := 48.0
const ZOOM_FOV_STEP := 3.0
const MIN_CAMERA_FOV := 30.0
const MAX_CAMERA_FOV := 64.0
const INTERACTION_RANGE := 1

@onready var terrain_root: Node3D = $Terrain
@onready var objects_root: Node3D = $Objects
@onready var markers_root: Node3D = $Markers
@onready var player: CharacterBody3D = $Player
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var selected_marker: MeshInstance3D = $Markers/SelectedMarker
@onready var destination_marker: MeshInstance3D = $Markers/DestinationMarker

var world_data := {}
var objects_by_tile: Dictionary = {}
var blocked_tiles: Dictionary = {}
var option_menu: PopupMenu
var option_menu_actions: Array[Dictionary] = []
var destination := Vector3.ZERO
var moving := false
var path_tiles: Array[Vector2i] = []
var pending_interaction := {}
var pending_interaction_action := ""
var current_tile := Vector2i(15, 15)
var state_ref := {}
var camera_offset := Vector3.ZERO
var selected_label: Label3D


func _ready() -> void:
	world_data = _load_json(WORLD_DATA_PATH)
	_configure_camera()
	_configure_player_visuals()
	_setup_option_menu()
	_setup_marker_materials()
	_build_terrain()
	_build_objects()
	_rebuild_blocked_tiles()
	selected_marker.visible = false
	destination_marker.visible = false


func initialize_from_state(state: Dictionary) -> void:
	state_ref = state
	var player_state = state.get("player", {})
	if player_state is Dictionary and player_state.has("tile"):
		current_tile = _array_to_tile(player_state["tile"], current_tile)
	else:
		current_tile = _array_to_tile(world_data.get("player_start", [15, 15]), current_tile)

	player.global_position = _tile_to_player_world(current_tile)
	destination = player.global_position
	camera_pivot.global_position = player.global_position
	player_tile_changed.emit(current_tile)
	feedback_changed.emit("Left-click objects for default actions. Right-click objects for options.")


func _process(delta: float) -> void:
	_update_camera(delta)
	_update_player(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_open_options_or_walk(event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_default_action_at_screen_position(event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_out()


func run_playable_shell_smoke() -> bool:
	var start_tile := current_tile
	_set_destination_tile(current_tile + Vector2i(1, 0))
	for _index in range(120):
		_update_player(1.0 / 60.0)
	if current_tile == start_tile:
		return false
	if not (player is CharacterBody3D and camera is Camera3D and camera.projection == Camera3D.PROJECTION_PERSPECTIVE and not objects_by_tile.is_empty()):
		return false

	var zoom_position_start := camera.position
	var zoom_start := camera.fov
	_zoom_in()
	if camera.fov >= zoom_start or camera.position != zoom_position_start:
		return false
	_zoom_out()
	_zoom_out()
	if camera.fov <= zoom_start or camera.position != zoom_position_start:
		return false

	var resource := _first_object_of_type("resource")
	if resource.is_empty() or _default_action_for_object(resource) == "walk":
		return false
	var high_level_mob := _first_mob_above_player_level()
	if high_level_mob.is_empty():
		return false
	if _default_action_for_object(high_level_mob) != "walk":
		return false
	for option in _menu_options_for_object(high_level_mob):
		if option is Dictionary and str(option.get("action", "")) == "attack":
			return true
	return false


func run_pathfinding_interaction_smoke() -> bool:
	_force_player_tile(Vector2i(15, 15))
	if _set_destination_tile(Vector2i(6, 17)):
		return false
	if current_tile != Vector2i(15, 15) or moving:
		return false

	var checks := [
		{"type": "resource", "tile": Vector2i(10, 11)},
		{"type": "npc", "tile": Vector2i(16, 13)},
		{"type": "station", "tile": Vector2i(13, 14)},
		{"type": "station", "tile": Vector2i(23, 15)},
	]
	add_ground_drop(Vector2i(16, 15), {"object_id": "path_smoke_drop", "item_id": "coins", "quantity": 1})
	checks.append({"type": "ground_item", "tile": Vector2i(16, 15)})

	for check in checks:
		_force_player_tile(Vector2i(15, 15))
		var tile: Vector2i = check["tile"]
		var object_data = objects_by_tile.get(tile, {})
		if not (object_data is Dictionary) or str(object_data.get("type", "")) != str(check["type"]):
			return false
		var target_tile := _interaction_target_tile(object_data)
		if target_tile == Vector2i(-1, -1):
			return false
		if not _set_destination_tile(target_tile):
			return false
		_force_player_tile(target_tile)
		if not _is_within_interaction_range(current_tile, tile):
			return false
		if _is_tile_blocked(current_tile):
			return false
		if str(check["type"]) == "resource" and current_tile == tile:
			return false
	return true


func run_visual_recreation_smoke() -> bool:
	var checks := {
		"rat": "rat_tail",
		"skeleton": "skeleton_skull",
		"wolf": "wolf_ear_a",
		"slime": "slime_blob",
		"mire_bat": "bat_left_wing",
		"fen_crawler": "crawler_shell",
		"target_dummy": "dummy_center_mark",
		"mage_imp": "imp_spell",
		"archer_goblin": "archer_bow",
		"bandit": "bandit_blade",
		"goblin": "mob_body",
	}
	for visual_kind in checks.keys():
		var root := Node3D.new()
		_add_mob_visual(root, {"visual_kind": visual_kind, "level": 5}, Color(0.44, 0.60, 0.38, 1.0))
		var expected_name := str(checks[visual_kind])
		var found := root.find_child(expected_name, true, false) != null
		root.queue_free()
		if not found:
			return false
	return true


func add_ground_drop(tile: Vector2i, item: Dictionary) -> void:
	var label := "%d %s" % [int(item.get("quantity", 1)), str(item.get("item_id", "item")).replace("_", " ")]
	var data: Dictionary = item.duplicate(true)
	data["type"] = "ground_item"
	data["id"] = str(item.get("object_id", "ground_item"))
	data["label"] = label
	data["tile"] = tile
	var marker: Node3D = _add_world_object(tile, label, Color(0.95, 0.78, 0.25, 1.0), data, "drop")
	data["marker"] = marker
	objects_by_tile[tile] = data


func remove_ground_item(object_data: Dictionary) -> void:
	var tile = object_data.get("tile", Vector2i(-1, -1))
	if tile is Array:
		tile = _array_to_tile(tile, Vector2i(-1, -1))
	if not (tile is Vector2i):
		return
	var existing = objects_by_tile.get(tile)
	if existing is Dictionary and str(existing.get("id", "")) == str(object_data.get("id", object_data.get("object_id", ""))):
		var marker = existing.get("marker")
		if marker is Node:
			marker.queue_free()
		objects_by_tile.erase(tile)


func _update_camera(delta: float) -> void:
	var movement := Vector3.ZERO
	var forward := -camera_pivot.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera_pivot.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	if Input.is_key_pressed(KEY_W):
		movement += forward
	if Input.is_key_pressed(KEY_S):
		movement -= forward
	if Input.is_key_pressed(KEY_A):
		movement -= right
	if Input.is_key_pressed(KEY_D):
		movement += right
	if movement != Vector3.ZERO:
		camera_offset += movement.normalized() * CAMERA_PAN_SPEED * delta
		camera_offset = camera_offset.limit_length(8.0)
	if Input.is_key_pressed(KEY_Q):
		camera_pivot.rotation.y -= CAMERA_ROTATE_SPEED * delta
	if Input.is_key_pressed(KEY_E):
		camera_pivot.rotation.y += CAMERA_ROTATE_SPEED * delta
	camera_pivot.global_position = player.global_position + camera_offset


func _update_player(delta: float) -> void:
	if not moving:
		return
	var offset := destination - player.global_position
	var step := PLAYER_SPEED * delta
	if offset.length() <= step:
		player.global_position = destination
		current_tile = _world_to_tile(player.global_position)
		state_ref["player"] = {"tile": [current_tile.x, current_tile.y], "position": [current_tile.x + 0.5, current_tile.y + 0.5]}
		player_tile_changed.emit(current_tile)
		if not path_tiles.is_empty():
			_advance_path()
			return
		moving = false
		feedback_changed.emit("Arrived at %d, %d" % [current_tile.x, current_tile.y])
		_complete_pending_interaction_if_ready()
		return
	player.global_position += offset.normalized() * step
	player.look_at(Vector3(destination.x, player.global_position.y, destination.z), Vector3.UP)


func _walk_to_screen_position(screen_position: Vector2) -> void:
	var tile := _screen_to_ground_tile(screen_position)
	_clear_pending_interaction()
	_set_destination_tile(tile)


func _default_action_at_screen_position(screen_position: Vector2) -> void:
	var tile := _screen_to_ground_tile(screen_position)
	var object_data = objects_by_tile.get(tile)
	if object_data == null:
		_clear_selection()
		_clear_pending_interaction()
		_set_destination_tile(tile)
		return
	_select_object(tile, object_data)
	var action := _default_action_for_object(object_data)
	if action == "walk":
		_clear_pending_interaction()
		_set_destination_near_object(object_data)
		feedback_changed.emit("%s is stronger than you. Right-click and choose Attack." % str(object_data.get("label", "Target")))
		return
	_start_object_action(object_data, action)


func _open_options_or_walk(screen_position: Vector2) -> void:
	var tile := _screen_to_ground_tile(screen_position)
	var object_data = objects_by_tile.get(tile)
	if object_data == null:
		_clear_selection()
		_clear_pending_interaction()
		_set_destination_tile(tile)
		return
	_select_object(tile, object_data)
	_show_option_menu(object_data, screen_position)


func _select_object(tile: Vector2i, object_data: Dictionary) -> void:
	selected_marker.global_position = _tile_to_ground_world(tile) + Vector3(0.0, 0.035, 0.0)
	selected_marker.visible = true
	_show_object_label(object_data)
	var label := str(object_data.get("label", "Object"))
	selection_changed.emit(label)
	feedback_changed.emit("Selected %s" % label)


func _clear_selection() -> void:
	selected_marker.visible = false
	_hide_selected_label()
	selection_changed.emit("none")


func _set_destination_tile(tile: Vector2i) -> bool:
	if not _is_walkable_tile(tile):
		feedback_changed.emit("No path")
		return false
	var route := _find_path(current_tile, tile)
	if route.is_empty() and tile != current_tile:
		feedback_changed.emit("No path")
		return false
	path_tiles = route
	if path_tiles.is_empty():
		destination = _tile_to_player_world(tile)
		destination_marker.global_position = _tile_to_ground_world(tile) + Vector3(0.0, 0.04, 0.0)
		destination_marker.visible = true
		feedback_changed.emit("Walking here")
		_complete_pending_interaction_if_ready()
		return true
	_advance_path()
	destination_marker.global_position = _tile_to_ground_world(tile) + Vector3(0.0, 0.04, 0.0)
	destination_marker.visible = true
	feedback_changed.emit("Walking here")
	return true


func _set_destination_near_object(object_data: Dictionary) -> bool:
	var target_tile := _interaction_target_tile(object_data)
	if target_tile == Vector2i(-1, -1):
		feedback_changed.emit("No path")
		return false
	return _set_destination_tile(target_tile)


func _advance_path() -> void:
	if path_tiles.is_empty():
		moving = false
		return
	var next_tile: Vector2i = path_tiles.pop_front()
	destination = _tile_to_player_world(next_tile)
	moving = true


func _screen_to_ground_tile(screen_position: Vector2) -> Vector2i:
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.001:
		return current_tile
	var distance := -origin.y / direction.y
	if distance < 0.0:
		return current_tile
	return _world_to_tile(origin + direction * distance)


func _apply_zoom(amount: float) -> void:
	camera.fov = clamp(camera.fov + amount, MIN_CAMERA_FOV, MAX_CAMERA_FOV)


func _zoom_in() -> void:
	_apply_zoom(-ZOOM_FOV_STEP)


func _zoom_out() -> void:
	_apply_zoom(ZOOM_FOV_STEP)


func _setup_option_menu() -> void:
	option_menu = PopupMenu.new()
	option_menu.name = "OptionMenu"
	add_child(option_menu)
	option_menu.id_pressed.connect(_on_option_menu_id_pressed)


func _show_option_menu(object_data: Dictionary, screen_position: Vector2) -> void:
	option_menu.clear()
	option_menu_actions = _menu_options_for_object(object_data)
	for index in range(option_menu_actions.size()):
		var option: Dictionary = option_menu_actions[index]
		option_menu.add_item(str(option.get("label", "Use")), index)
	option_menu.position = Vector2i(int(screen_position.x), int(screen_position.y))
	option_menu.reset_size()
	option_menu.popup()


func _on_option_menu_id_pressed(id: int) -> void:
	if id < 0 or id >= option_menu_actions.size():
		return
	var option: Dictionary = option_menu_actions[id]
	var object_data = option.get("object_data", {})
	if not (object_data is Dictionary):
		return
	var action := str(option.get("action", "default"))
	if action == "walk":
		var tile = object_data.get("tile", current_tile)
		if tile is Array:
			tile = _array_to_tile(tile, current_tile)
		if tile is Vector2i:
			_clear_pending_interaction()
			_set_destination_near_object(object_data)
		return
	_start_object_action(object_data, action)


func _start_object_action(object_data: Dictionary, action: String) -> void:
	var object_tile := _object_tile(object_data)
	if _is_within_interaction_range(current_tile, object_tile):
		_clear_pending_interaction()
		_emit_object_action(object_data, action)
		return
	pending_interaction = object_data.duplicate(false)
	pending_interaction_action = action
	if not _set_destination_near_object(object_data):
		_clear_pending_interaction()


func _complete_pending_interaction_if_ready() -> void:
	if pending_interaction.is_empty():
		return
	var object_tile := _object_tile(pending_interaction)
	if not _is_within_interaction_range(current_tile, object_tile):
		return
	var action := pending_interaction_action
	var object_data := pending_interaction.duplicate(false)
	_clear_pending_interaction()
	_emit_object_action(object_data, action)


func _clear_pending_interaction() -> void:
	pending_interaction = {}
	pending_interaction_action = ""


func _emit_object_action(object_data: Dictionary, action: String) -> void:
	var action_data := object_data.duplicate(false)
	action_data["action"] = action
	object_activated.emit(action_data)


func _default_action_for_object(object_data: Dictionary) -> String:
	var object_type := str(object_data.get("type", ""))
	if object_type == "mob":
		return "attack" if int(object_data.get("level", 1)) <= _player_combat_level() else "walk"
	if object_type in ["resource", "station", "ground_item", "npc"]:
		return "default"
	return "walk"


func _menu_options_for_object(object_data: Dictionary) -> Array[Dictionary]:
	var object_type := str(object_data.get("type", ""))
	var label := str(object_data.get("label", "object"))
	var options: Array[Dictionary] = []
	match object_type:
		"resource":
			options.append(_menu_option(_resource_action_label(object_data), "default", object_data))
			if str(object_data.get("skill_id", "")) == "fishing":
				if _has_inventory_item("small_fishing_net"):
					options.append(_menu_option("Net", "fish_net", object_data))
				if _has_inventory_item("fishing_rod"):
					options.append(_menu_option("Rod", "fish_rod", object_data))
			options.append(_menu_option("Examine %s" % label, "examine", object_data))
		"mob":
			options.append(_menu_option("Attack %s" % label, "attack", object_data))
			options.append(_menu_option("Walk here", "walk", object_data))
			options.append(_menu_option("Examine %s" % label, "examine", object_data))
		"ground_item":
			options.append(_menu_option("Take %s" % label, "default", object_data))
			options.append(_menu_option("Examine %s" % label, "examine", object_data))
		"npc":
			options.append(_menu_option("Talk-to %s" % label, "default", object_data))
			options.append(_menu_option("Examine %s" % label, "examine", object_data))
		"station":
			options.append(_menu_option("%s %s" % [_station_action_label(object_data), label], "default", object_data))
			options.append(_menu_option("Examine %s" % label, "examine", object_data))
		_:
			options.append(_menu_option("Walk here", "walk", object_data))
			options.append(_menu_option("Examine %s" % label, "examine", object_data))
	return options


func _menu_option(label: String, action: String, object_data: Dictionary) -> Dictionary:
	return {"label": label, "action": action, "object_data": object_data}


func _resource_action_label(object_data: Dictionary) -> String:
	match str(object_data.get("skill_id", "")):
		"woodcutting":
			return "Chop"
		"mining":
			return "Mine"
		"fishing":
			return "Fish"
		"herbalism":
			return "Pick"
		"foraging":
			return "Gather"
		_:
			return "Gather"


func _station_action_label(object_data: Dictionary) -> String:
	match str(object_data.get("station_id", "")):
		"bank":
			return "Open"
		"shop":
			return "Trade"
		_:
			return "Use"


func _player_combat_level() -> int:
	var skills = state_ref.get("skills", {})
	if not (skills is Dictionary):
		return 1
	var attack := _state_skill_level(skills, "attack", 1)
	var strength := _state_skill_level(skills, "strength", 1)
	var defence := _state_skill_level(skills, "defence", 1)
	var hitpoints := _state_skill_level(skills, "hitpoints", 10)
	var ranged := _state_skill_level(skills, "ranged", 1)
	var magic := _state_skill_level(skills, "magic", 1)
	return max(1, int(floor(float(attack + strength + defence + hitpoints + max(ranged, magic)) / 5.0)))


func _state_skill_level(skills: Dictionary, skill_id: String, fallback: int) -> int:
	var values = skills.get(skill_id, {})
	if values is Dictionary:
		return int(values.get("level", fallback))
	return fallback


func _has_inventory_item(item_id: String) -> bool:
	var inventory = state_ref.get("inventory", {})
	return inventory is Dictionary and int(inventory.get(item_id, 0)) > 0


func _first_object_of_type(object_type: String) -> Dictionary:
	for value in objects_by_tile.values():
		if value is Dictionary and str(value.get("type", "")) == object_type:
			return value
	return {}


func _first_mob_above_player_level() -> Dictionary:
	var player_level := _player_combat_level()
	for value in objects_by_tile.values():
		if value is Dictionary and str(value.get("type", "")) == "mob" and int(value.get("level", 1)) > player_level:
			return value
	return {}


func _configure_camera() -> void:
	camera_pivot.rotation = Vector3.ZERO
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = CAMERA_FOV
	camera.position = Vector3(0.0, CAMERA_HEIGHT, CAMERA_DISTANCE)
	camera.rotation_degrees = Vector3(CAMERA_PITCH_DEGREES, 0.0, 0.0)


func _configure_player_visuals() -> void:
	if player.has_node("ReadabilityRig"):
		return
	var rig := Node3D.new()
	rig.name = "ReadabilityRig"
	player.add_child(rig)
	_add_box(rig, Vector3(0.0, 0.04, 0.0), Vector3(0.56, 0.08, 0.56), Color(0.10, 0.12, 0.16, 0.55), "player_shadow", true)
	_add_box(rig, Vector3(0.0, 0.58, -0.28), Vector3(0.34, 0.18, 0.16), Color(0.94, 0.73, 0.28, 1.0), "player_chest")
	_add_box(rig, Vector3(0.0, 0.96, -0.19), Vector3(0.18, 0.18, 0.30), Color(0.18, 0.25, 0.46, 1.0), "player_direction")
	_add_box(rig, Vector3(-0.16, 0.20, 0.0), Vector3(0.14, 0.22, 0.18), Color(0.14, 0.11, 0.08, 1.0), "left_boot")
	_add_box(rig, Vector3(0.16, 0.20, 0.0), Vector3(0.14, 0.22, 0.18), Color(0.14, 0.11, 0.08, 1.0), "right_boot")


func _build_terrain() -> void:
	var width := int(world_data.get("width", 30))
	var height := int(world_data.get("height", 30))
	var dirt_tiles := _tile_set(world_data.get("dirt_tiles", []))
	var water_tiles := _tile_set(world_data.get("water_tiles", []))
	for x in range(width):
		for y in range(height):
			var tile := Vector2i(x, y)
			if not _near_shell_area(tile):
				continue
			var color := Color(0.20, 0.43, 0.22, 1.0)
			var height_offset := 0.0
			if dirt_tiles.has(tile):
				color = Color(0.48, 0.35, 0.18, 1.0)
				height_offset = 0.01
			elif water_tiles.has(tile):
				color = Color(0.13, 0.32, 0.53, 1.0)
				height_offset = -0.025
			_add_box(
				terrain_root,
				_tile_to_ground_world(tile) + Vector3(0.0, -0.035 + height_offset, 0.0),
				Vector3(TILE_SIZE * 0.98, 0.06, TILE_SIZE * 0.98),
				color,
				"tile_%d_%d" % [tile.x, tile.y]
			)


func _build_objects() -> void:
	for node in world_data.get("resource_nodes", []):
		if node is Dictionary:
			var data: Dictionary = node.duplicate(true)
			data["type"] = "resource"
			data["id"] = str(node.get("node_id", ""))
			data["label"] = str(node.get("display_name", "Resource"))
			data["tile"] = _array_to_tile(node.get("position", [0, 0]), Vector2i.ZERO)
			_add_world_object(data["tile"], data["label"], Color(0.18, 0.56, 0.25, 1.0), data, "resource")
	for decoration in world_data.get("decorations", []):
		if decoration is Dictionary:
			var label := str(decoration.get("display_name", _display_label(str(decoration.get("kind", "Decoration")))))
			var data: Dictionary = decoration.duplicate(true)
			data["type"] = "decoration"
			data["id"] = str(decoration.get("id", ""))
			data["label"] = label
			data["tile"] = _array_to_tile(decoration.get("position", [0, 0]), Vector2i.ZERO)
			_add_world_object(data["tile"], data["label"], Color(0.52, 0.42, 0.30, 1.0), data, "decoration")
	for npc in world_data.get("npcs", []):
		if npc is Dictionary:
			var data: Dictionary = npc.duplicate(true)
			data["type"] = "npc"
			data["id"] = str(npc.get("id", ""))
			data["label"] = str(npc.get("name", "NPC"))
			data["tile"] = _array_to_tile(npc.get("tile", [0, 0]), Vector2i.ZERO)
			_add_world_object(data["tile"], data["label"], Color(0.84, 0.62, 0.28, 1.0), data, "npc")
	for mob in world_data.get("mobs", []):
		if mob is Dictionary:
			var data: Dictionary = mob.duplicate(true)
			data["type"] = "mob"
			data["id"] = str(mob.get("mob_id", ""))
			data["label"] = str(mob.get("display_name", "Mob"))
			data["tile"] = _array_to_tile(mob.get("position", [0, 0]), Vector2i.ZERO)
			_add_world_object(data["tile"], data["label"], Color(0.72, 0.20, 0.20, 1.0), data, "mob")
	for key in ["bank", "shop", "cooking_range", "furnace", "anvil", "carpentry_bench", "apothecary_table"]:
		var station = world_data.get(key)
		if station is Dictionary:
			var data: Dictionary = station.duplicate(true)
			data["type"] = "station"
			data["station_id"] = key
			data["id"] = str(station.get("id", key))
			data["label"] = str(station.get("name", _display_label(key)))
			data["tile"] = _array_to_tile(station.get("tile", [0, 0]), Vector2i.ZERO)
			_add_world_object(data["tile"], data["label"], _station_color(key), data, key)


func _rebuild_blocked_tiles() -> void:
	blocked_tiles = _tile_set(world_data.get("blocked_tiles", []))
	for tile in _tile_set(world_data.get("water_tiles", [])).keys():
		blocked_tiles[tile] = true
	for node in world_data.get("resource_nodes", []):
		if node is Dictionary and bool(node.get("blocks_movement", false)):
			blocked_tiles[_array_to_tile(node.get("position", [0, 0]), Vector2i.ZERO)] = true
	for decoration in world_data.get("decorations", []):
		if decoration is Dictionary and bool(decoration.get("blocking", false)):
			blocked_tiles[_array_to_tile(decoration.get("position", [0, 0]), Vector2i.ZERO)] = true
	for object_data in objects_by_tile.values():
		if object_data is Dictionary and _object_blocks_movement(object_data):
			blocked_tiles[_object_tile(object_data)] = true


func _add_world_object(tile: Vector2i, label: String, color: Color, data: Dictionary = {}, kind: String = "object") -> Node3D:
	if not _near_shell_area(tile):
		return null
	var root := Node3D.new()
	root.name = "Object_%s" % str(data.get("id", label)).replace(" ", "_")
	root.position = _tile_to_ground_world(tile)
	objects_root.add_child(root)

	match kind:
		"resource":
			_add_resource_visual(root, data, color)
		"decoration":
			_add_decoration_visual(root, data, color)
		"npc":
			_add_npc_visual(root, color)
		"mob":
			_add_mob_visual(root, data, color)
		"drop":
			_add_drop_visual(root, color)
		"bank":
			_add_bank_visual(root, color)
		"shop":
			_add_shop_visual(root, color)
		"cooking_range", "furnace", "anvil", "carpentry_bench", "apothecary_table":
			_add_station_visual(root, kind, color)
		_:
			_add_box(root, Vector3(0.0, 0.32, 0.0), Vector3(0.54, 0.52, 0.54), color, "marker")

	var label_node := Label3D.new()
	label_node.name = "Label"
	label_node.text = label
	label_node.position = Vector3(0.0, 1.15, 0.0)
	label_node.pixel_size = 0.014
	label_node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_node.outline_size = 3
	label_node.visible = false
	root.add_child(label_node)

	if not data.is_empty():
		data["marker"] = root
		data["label_node"] = label_node
		objects_by_tile[tile] = data
	else:
		objects_by_tile[tile] = {"label": label, "marker": root, "label_node": label_node}
	return root


func _add_resource_visual(parent: Node3D, data: Dictionary, color: Color) -> void:
	match str(data.get("skill_id", "")):
		"woodcutting":
			_add_cylinder(parent, Vector3(0.0, 0.42, 0.0), 0.16, 0.84, Color(0.42, 0.25, 0.12, 1.0), "tree_trunk")
			_add_sphere(parent, Vector3(0.0, 1.04, 0.0), Vector3(0.62, 0.42, 0.62), Color(0.13, 0.43, 0.20, 1.0), "tree_canopy")
			_add_sphere(parent, Vector3(-0.28, 0.87, 0.05), Vector3(0.34, 0.24, 0.34), Color(0.19, 0.54, 0.27, 1.0), "tree_left_clump")
			_add_sphere(parent, Vector3(0.30, 0.90, -0.02), Vector3(0.34, 0.24, 0.34), Color(0.16, 0.48, 0.23, 1.0), "tree_right_clump")
		"mining":
			_add_box(parent, Vector3(-0.16, 0.22, -0.05), Vector3(0.42, 0.34, 0.34), Color(0.43, 0.43, 0.40, 1.0), "rock_left")
			_add_box(parent, Vector3(0.18, 0.30, 0.08), Vector3(0.46, 0.48, 0.38), Color(0.56, 0.55, 0.50, 1.0), "rock_center")
			_add_box(parent, Vector3(0.03, 0.52, -0.08), Vector3(0.22, 0.16, 0.18), color.lightened(0.35), "ore_glint")
		"fishing":
			_add_cylinder(parent, Vector3(0.0, 0.025, 0.0), 0.38, 0.05, Color(0.12, 0.34, 0.58, 0.92), "water_ring")
			_add_cylinder(parent, Vector3(0.0, 0.23, 0.0), 0.10, 0.36, Color(0.93, 0.34, 0.23, 1.0), "fishing_float")
			_add_box(parent, Vector3(0.21, 0.34, 0.0), Vector3(0.08, 0.12, 0.34), Color(0.93, 0.88, 0.58, 1.0), "float_tip")
		"herbalism":
			_add_sphere(parent, Vector3(0.0, 0.22, 0.0), Vector3(0.46, 0.24, 0.46), Color(0.23, 0.50, 0.24, 1.0), "herb_leaf_cluster")
			_add_box(parent, Vector3(-0.16, 0.36, 0.0), Vector3(0.10, 0.18, 0.10), Color(0.76, 0.50, 0.86, 1.0), "herb_bloom_a")
			_add_box(parent, Vector3(0.14, 0.32, -0.08), Vector3(0.10, 0.16, 0.10), Color(0.93, 0.76, 0.30, 1.0), "herb_bloom_b")
		"foraging":
			_add_sphere(parent, Vector3(0.0, 0.32, 0.0), Vector3(0.54, 0.36, 0.54), Color(0.18, 0.45, 0.20, 1.0), "bush_body")
			_add_box(parent, Vector3(-0.16, 0.44, -0.13), Vector3(0.10, 0.10, 0.10), Color(0.86, 0.14, 0.19, 1.0), "berry_a")
			_add_box(parent, Vector3(0.18, 0.38, 0.10), Vector3(0.10, 0.10, 0.10), Color(0.95, 0.25, 0.21, 1.0), "berry_b")
		_:
			_add_cylinder(parent, Vector3(0.0, 0.42, 0.0), 0.18, 0.72, color, "resource_marker")
			_add_box(parent, Vector3(0.0, 0.88, 0.0), Vector3(0.48, 0.24, 0.48), color.lightened(0.2), "resource_top")


func _add_decoration_visual(parent: Node3D, data: Dictionary, color: Color) -> void:
	match str(data.get("kind", "")):
		"signpost":
			_add_cylinder(parent, Vector3(0.0, 0.38, 0.0), 0.06, 0.76, Color(0.38, 0.23, 0.12, 1.0), "sign_post")
			_add_box(parent, Vector3(0.0, 0.78, -0.04), Vector3(0.56, 0.24, 0.08), Color(0.58, 0.38, 0.18, 1.0), "sign_board")
		"bridge":
			_add_box(parent, Vector3(0.0, 0.08, 0.0), Vector3(0.86, 0.14, 0.48), Color(0.47, 0.31, 0.16, 1.0), "bridge_planks")
			_add_box(parent, Vector3(-0.32, 0.22, 0.0), Vector3(0.08, 0.28, 0.56), Color(0.31, 0.20, 0.11, 1.0), "bridge_rail_a")
			_add_box(parent, Vector3(0.32, 0.22, 0.0), Vector3(0.08, 0.28, 0.56), Color(0.31, 0.20, 0.11, 1.0), "bridge_rail_b")
		_:
			_add_box(parent, Vector3(0.0, 0.24, 0.0), Vector3(0.48, 0.38, 0.48), color, "decoration_marker")


func _add_npc_visual(parent: Node3D, color: Color) -> void:
	_add_cylinder(parent, Vector3(0.0, 0.46, 0.0), 0.22, 0.86, color, "npc_tunic")
	_add_sphere(parent, Vector3(0.0, 1.02, 0.0), Vector3(0.30, 0.30, 0.30), Color(0.95, 0.76, 0.52, 1.0), "npc_head")
	_add_box(parent, Vector3(-0.28, 0.60, 0.0), Vector3(0.12, 0.42, 0.12), Color(0.62, 0.43, 0.24, 1.0), "npc_left_arm")
	_add_box(parent, Vector3(0.28, 0.60, 0.0), Vector3(0.12, 0.42, 0.12), Color(0.62, 0.43, 0.24, 1.0), "npc_right_arm")
	_add_box(parent, Vector3(0.0, 1.25, 0.0), Vector3(0.42, 0.10, 0.42), Color(0.24, 0.18, 0.12, 1.0), "npc_hat_brim")


func _add_mob_visual(parent: Node3D, data: Dictionary, color: Color) -> void:
	var level := int(data.get("level", 1))
	var danger_color := color.lightened(0.18) if level <= 4 else Color(0.88, 0.15, 0.15, 1.0)
	match str(data.get("visual_kind", "")):
		"rat":
			_add_sphere(parent, Vector3(0.0, 0.22, 0.0), Vector3(0.42, 0.20, 0.24), Color(0.43, 0.34, 0.27, 1.0), "rat_body")
			_add_sphere(parent, Vector3(0.0, 0.30, -0.25), Vector3(0.20, 0.16, 0.18), Color(0.36, 0.28, 0.22, 1.0), "rat_head")
			_add_box(parent, Vector3(0.0, 0.22, 0.31), Vector3(0.08, 0.06, 0.42), Color(0.72, 0.47, 0.43, 1.0), "rat_tail")
		"slime":
			_add_sphere(parent, Vector3(0.0, 0.24, 0.0), Vector3(0.54, 0.28, 0.46), Color(0.24, 0.78, 0.40, 0.88), "slime_blob")
			_add_box(parent, Vector3(-0.14, 0.32, -0.30), Vector3(0.08, 0.08, 0.08), Color(0.05, 0.14, 0.07, 1.0), "slime_eye_a")
			_add_box(parent, Vector3(0.14, 0.32, -0.30), Vector3(0.08, 0.08, 0.08), Color(0.05, 0.14, 0.07, 1.0), "slime_eye_b")
		"skeleton":
			_add_box(parent, Vector3(0.0, 0.42, 0.0), Vector3(0.28, 0.54, 0.18), Color(0.86, 0.84, 0.72, 1.0), "skeleton_ribs")
			_add_sphere(parent, Vector3(0.0, 0.82, -0.02), Vector3(0.24, 0.22, 0.22), Color(0.92, 0.90, 0.78, 1.0), "skeleton_skull")
			_add_box(parent, Vector3(-0.22, 0.32, 0.0), Vector3(0.08, 0.42, 0.08), Color(0.82, 0.80, 0.68, 1.0), "skeleton_arm_a")
			_add_box(parent, Vector3(0.22, 0.32, 0.0), Vector3(0.08, 0.42, 0.08), Color(0.82, 0.80, 0.68, 1.0), "skeleton_arm_b")
		"wolf":
			_add_sphere(parent, Vector3(0.0, 0.36, 0.0), Vector3(0.66, 0.30, 0.34), Color(0.33, 0.34, 0.34, 1.0), "wolf_body")
			_add_box(parent, Vector3(0.0, 0.48, -0.38), Vector3(0.26, 0.20, 0.32), Color(0.25, 0.25, 0.25, 1.0), "wolf_muzzle")
			_add_box(parent, Vector3(-0.12, 0.66, -0.26), Vector3(0.10, 0.22, 0.08), Color(0.22, 0.22, 0.22, 1.0), "wolf_ear_a")
			_add_box(parent, Vector3(0.12, 0.66, -0.26), Vector3(0.10, 0.22, 0.08), Color(0.22, 0.22, 0.22, 1.0), "wolf_ear_b")
		"mire_bat":
			_add_sphere(parent, Vector3(0.0, 0.52, 0.0), Vector3(0.30, 0.24, 0.24), Color(0.22, 0.16, 0.29, 1.0), "bat_body")
			_add_box(parent, Vector3(-0.34, 0.52, 0.0), Vector3(0.46, 0.06, 0.24), Color(0.18, 0.12, 0.24, 1.0), "bat_left_wing")
			_add_box(parent, Vector3(0.34, 0.52, 0.0), Vector3(0.46, 0.06, 0.24), Color(0.18, 0.12, 0.24, 1.0), "bat_right_wing")
			_add_box(parent, Vector3(0.0, 0.66, -0.20), Vector3(0.18, 0.10, 0.12), Color(0.58, 0.92, 0.58, 1.0), "bat_glow_face")
		"fen_crawler":
			_add_sphere(parent, Vector3(0.0, 0.24, 0.0), Vector3(0.54, 0.22, 0.40), Color(0.19, 0.38, 0.28, 1.0), "crawler_shell")
			for index in range(4):
				var x := -0.36 + float(index) * 0.24
				_add_box(parent, Vector3(x, 0.14, -0.28), Vector3(0.08, 0.08, 0.34), Color(0.12, 0.24, 0.18, 1.0), "crawler_leg_f_%d" % index)
				_add_box(parent, Vector3(x, 0.14, 0.28), Vector3(0.08, 0.08, 0.34), Color(0.12, 0.24, 0.18, 1.0), "crawler_leg_b_%d" % index)
		"target_dummy":
			_add_cylinder(parent, Vector3(0.0, 0.42, 0.0), 0.11, 0.84, Color(0.44, 0.28, 0.14, 1.0), "dummy_post")
			_add_box(parent, Vector3(0.0, 0.72, -0.06), Vector3(0.48, 0.42, 0.12), Color(0.72, 0.52, 0.26, 1.0), "dummy_target_board")
			_add_box(parent, Vector3(0.0, 0.72, -0.14), Vector3(0.20, 0.18, 0.04), Color(0.88, 0.18, 0.18, 1.0), "dummy_center_mark")
		"mage_imp":
			_add_default_mob_visual(parent, danger_color, color)
			_add_box(parent, Vector3(0.0, 0.86, -0.12), Vector3(0.34, 0.18, 0.20), Color(0.46, 0.20, 0.72, 1.0), "imp_cowl")
			_add_sphere(parent, Vector3(0.26, 0.54, -0.22), Vector3(0.10, 0.10, 0.10), Color(0.68, 0.38, 0.96, 1.0), "imp_spell")
		"archer_goblin":
			_add_default_mob_visual(parent, danger_color, color)
			_add_box(parent, Vector3(0.36, 0.42, -0.10), Vector3(0.08, 0.70, 0.08), Color(0.48, 0.29, 0.12, 1.0), "archer_bow")
			_add_box(parent, Vector3(0.24, 0.42, -0.10), Vector3(0.22, 0.04, 0.04), Color(0.88, 0.78, 0.48, 1.0), "archer_arrow")
		"bandit":
			_add_default_mob_visual(parent, danger_color, color)
			_add_box(parent, Vector3(0.32, 0.46, -0.18), Vector3(0.08, 0.46, 0.08), Color(0.72, 0.72, 0.70, 1.0), "bandit_blade")
		_:
			_add_default_mob_visual(parent, danger_color, color)


func _add_default_mob_visual(parent: Node3D, danger_color: Color, color: Color) -> void:
	_add_sphere(parent, Vector3(0.0, 0.34, 0.0), Vector3(0.56, 0.36, 0.44), danger_color, "mob_body")
	_add_box(parent, Vector3(0.0, 0.52, -0.26), Vector3(0.34, 0.24, 0.24), color.darkened(0.08), "mob_head")
	_add_box(parent, Vector3(-0.14, 0.58, -0.40), Vector3(0.08, 0.08, 0.08), Color(0.95, 0.88, 0.55, 1.0), "mob_eye_a")
	_add_box(parent, Vector3(0.14, 0.58, -0.40), Vector3(0.08, 0.08, 0.08), Color(0.95, 0.88, 0.55, 1.0), "mob_eye_b")
	_add_box(parent, Vector3(0.0, 0.12, 0.0), Vector3(0.70, 0.06, 0.52), Color(0.09, 0.04, 0.04, 0.40), "mob_shadow", true)


func _add_drop_visual(parent: Node3D, color: Color) -> void:
	_add_box(parent, Vector3(0.0, 0.12, 0.0), Vector3(0.34, 0.18, 0.28), Color(0.50, 0.32, 0.13, 1.0), "loot_bag")
	_add_box(parent, Vector3(0.0, 0.27, 0.0), Vector3(0.18, 0.08, 0.18), color.lightened(0.2), "loot_tie")


func _add_bank_visual(parent: Node3D, color: Color) -> void:
	_add_box(parent, Vector3(0.0, 0.32, 0.0), Vector3(0.86, 0.58, 0.70), color.darkened(0.08), "bank_booth")
	_add_box(parent, Vector3(0.0, 0.70, -0.12), Vector3(0.98, 0.18, 0.28), Color(0.82, 0.66, 0.26, 1.0), "bank_counter")
	_add_box(parent, Vector3(0.0, 1.00, 0.0), Vector3(0.76, 0.18, 0.50), Color(0.19, 0.24, 0.48, 1.0), "bank_sign")
	_add_box(parent, Vector3(0.0, 1.18, -0.02), Vector3(0.28, 0.08, 0.08), Color(0.95, 0.82, 0.34, 1.0), "bank_gold_mark")


func _add_shop_visual(parent: Node3D, color: Color) -> void:
	_add_box(parent, Vector3(0.0, 0.28, 0.0), Vector3(0.86, 0.42, 0.70), Color(0.54, 0.34, 0.16, 1.0), "shop_counter")
	_add_box(parent, Vector3(0.0, 0.78, 0.0), Vector3(1.02, 0.18, 0.82), color, "shop_canopy")
	_add_box(parent, Vector3(-0.40, 0.56, 0.0), Vector3(0.08, 0.54, 0.08), Color(0.32, 0.21, 0.12, 1.0), "shop_post_a")
	_add_box(parent, Vector3(0.40, 0.56, 0.0), Vector3(0.08, 0.54, 0.08), Color(0.32, 0.21, 0.12, 1.0), "shop_post_b")


func _add_station_visual(parent: Node3D, station_id: String, color: Color) -> void:
	match station_id:
		"cooking_range":
			_add_box(parent, Vector3(0.0, 0.28, 0.0), Vector3(0.64, 0.48, 0.52), Color(0.36, 0.34, 0.31, 1.0), "range_stone")
			_add_box(parent, Vector3(0.0, 0.58, -0.18), Vector3(0.34, 0.18, 0.10), Color(0.95, 0.34, 0.14, 1.0), "range_fire")
		"furnace":
			_add_cylinder(parent, Vector3(0.0, 0.40, 0.0), 0.34, 0.78, Color(0.40, 0.38, 0.36, 1.0), "furnace_shell")
			_add_box(parent, Vector3(0.0, 0.40, -0.30), Vector3(0.34, 0.26, 0.08), color.lightened(0.15), "furnace_glow")
		"anvil":
			_add_box(parent, Vector3(0.0, 0.22, 0.0), Vector3(0.40, 0.28, 0.32), Color(0.28, 0.29, 0.31, 1.0), "anvil_base")
			_add_box(parent, Vector3(0.0, 0.46, 0.0), Vector3(0.74, 0.18, 0.28), color.lightened(0.14), "anvil_top")
		"carpentry_bench":
			_add_box(parent, Vector3(0.0, 0.34, 0.0), Vector3(0.90, 0.16, 0.44), Color(0.55, 0.33, 0.16, 1.0), "bench_top")
			_add_box(parent, Vector3(-0.28, 0.16, 0.0), Vector3(0.10, 0.34, 0.10), Color(0.35, 0.22, 0.12, 1.0), "bench_leg_a")
			_add_box(parent, Vector3(0.28, 0.16, 0.0), Vector3(0.10, 0.34, 0.10), Color(0.35, 0.22, 0.12, 1.0), "bench_leg_b")
		"apothecary_table":
			_add_box(parent, Vector3(0.0, 0.32, 0.0), Vector3(0.78, 0.14, 0.46), Color(0.38, 0.26, 0.14, 1.0), "apothecary_table")
			_add_cylinder(parent, Vector3(-0.18, 0.52, 0.0), 0.08, 0.22, Color(0.22, 0.68, 0.36, 1.0), "green_bottle")
			_add_cylinder(parent, Vector3(0.14, 0.50, 0.06), 0.07, 0.18, Color(0.66, 0.34, 0.76, 1.0), "purple_bottle")
		_:
			_add_box(parent, Vector3(0.0, 0.32, 0.0), Vector3(0.54, 0.52, 0.54), color, "station_marker")


func _show_object_label(object_data: Dictionary) -> void:
	_hide_selected_label()
	var label_node = object_data.get("label_node")
	if label_node is Label3D:
		selected_label = label_node
		selected_label.visible = true


func _hide_selected_label() -> void:
	if selected_label != null:
		selected_label.visible = false
		selected_label = null


func _setup_marker_materials() -> void:
	selected_marker.mesh = _box_mesh(Vector3(TILE_SIZE, 0.035, TILE_SIZE))
	selected_marker.material_override = _material(Color(1.0, 0.88, 0.20, 0.42), true)
	destination_marker.mesh = _box_mesh(Vector3(TILE_SIZE, 0.03, TILE_SIZE))
	destination_marker.material_override = _material(Color(0.25, 0.60, 1.0, 0.36), true)


func _add_box(parent: Node, position: Vector3, size: Vector3, color: Color, name: String, transparent: bool = false) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = name
	mesh_instance.mesh = _box_mesh(size)
	mesh_instance.material_override = _material(color, transparent)
	mesh_instance.position = position
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_cylinder(parent: Node, position: Vector3, radius: float, height: float, color: Color, name: String) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = name
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(color)
	mesh_instance.position = position
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_sphere(parent: Node, position: Vector3, scale: Vector3, color: Color, name: String) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 4
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = name
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(color)
	mesh_instance.position = position
	mesh_instance.scale = scale
	parent.add_child(mesh_instance)
	return mesh_instance


func _box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _load_json(path: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed
	return {}


func _tile_to_ground_world(tile: Vector2i) -> Vector3:
	return Vector3((tile.x + 0.5) * TILE_SIZE, 0.0, (tile.y + 0.5) * TILE_SIZE)


func _tile_to_player_world(tile: Vector2i) -> Vector3:
	return _tile_to_ground_world(tile) + Vector3(0.0, 0.55, 0.0)


func _world_to_tile(world_position: Vector3) -> Vector2i:
	return Vector2i(floori(world_position.x / TILE_SIZE), floori(world_position.z / TILE_SIZE))


func _array_to_tile(value, fallback: Vector2i) -> Vector2i:
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return fallback


func _tile_set(values) -> Dictionary:
	var result := {}
	if not (values is Array):
		return result
	for value in values:
		var tile := _array_to_tile(value, Vector2i(-1, -1))
		result[tile] = true
	return result


func _find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if start == goal:
		return []
	if not _is_walkable_tile(goal):
		return []
	if not _is_walkable_tile(start):
		return []
	var frontier: Array[Vector2i] = [start]
	var came_from := {}
	came_from[start] = start
	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var cursor := 0
	var max_visits := int(world_data.get("width", 30)) * int(world_data.get("height", 30))
	while cursor < frontier.size() and cursor < max_visits:
		var current: Vector2i = frontier[cursor]
		cursor += 1
		if current == goal:
			break
		for direction in directions:
			var next_tile: Vector2i = current + direction
			if came_from.has(next_tile) or not _is_walkable_tile(next_tile):
				continue
			came_from[next_tile] = current
			frontier.append(next_tile)
	if not came_from.has(goal):
		return []
	var reversed_path: Array[Vector2i] = []
	var step := goal
	var guard := 0
	while step != start and guard < max_visits:
		reversed_path.append(step)
		step = came_from[step]
		guard += 1
	if guard >= max_visits:
		return []
	var path: Array[Vector2i] = []
	for index in range(reversed_path.size() - 1, -1, -1):
		path.append(reversed_path[index])
	return path


func _interaction_target_tile(object_data: Dictionary) -> Vector2i:
	var object_tile := _object_tile(object_data)
	if object_tile == Vector2i(-1, -1):
		return object_tile
	var best_tile := Vector2i(-1, -1)
	var best_distance := 999999
	for dx in range(-INTERACTION_RANGE, INTERACTION_RANGE + 1):
		for dy in range(-INTERACTION_RANGE, INTERACTION_RANGE + 1):
			var candidate := object_tile + Vector2i(dx, dy)
			if not _is_within_interaction_range(candidate, object_tile):
				continue
			if not _is_walkable_tile(candidate):
				continue
			var route := _find_path(current_tile, candidate)
			if route.is_empty() and candidate != current_tile:
				continue
			var distance := route.size()
			if candidate == current_tile:
				distance = 0
			if distance < best_distance:
				best_distance = distance
				best_tile = candidate
	return best_tile


func _is_walkable_tile(tile: Vector2i) -> bool:
	return _tile_in_bounds(tile) and not _is_tile_blocked(tile)


func _is_tile_blocked(tile: Vector2i) -> bool:
	return blocked_tiles.has(tile)


func _is_within_interaction_range(from_tile: Vector2i, object_tile: Vector2i) -> bool:
	return max(absi(from_tile.x - object_tile.x), absi(from_tile.y - object_tile.y)) <= INTERACTION_RANGE


func _object_tile(object_data: Dictionary) -> Vector2i:
	var tile = object_data.get("tile", Vector2i(-1, -1))
	if tile is Array:
		return _array_to_tile(tile, Vector2i(-1, -1))
	if tile is Vector2i:
		return tile
	return Vector2i(-1, -1)


func _object_blocks_movement(object_data: Dictionary) -> bool:
	match str(object_data.get("type", "")):
		"resource":
			return bool(object_data.get("blocks_movement", false))
		"npc", "mob", "station":
			return true
		"decoration":
			return bool(object_data.get("blocking", false))
	return false


func _force_player_tile(tile: Vector2i) -> void:
	current_tile = tile
	player.global_position = _tile_to_player_world(tile)
	destination = player.global_position
	moving = false
	path_tiles = []
	state_ref["player"] = {"tile": [tile.x, tile.y], "position": [tile.x + 0.5, tile.y + 0.5]}


func _drain_path_for_smoke() -> bool:
	for _index in range(80):
		if not moving:
			return true
		player.global_position = destination
		_update_player(0.0)
	return false


func _tile_in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < int(world_data.get("width", 30)) and tile.y < int(world_data.get("height", 30))


func _near_shell_area(tile: Vector2i) -> bool:
	return tile.x >= 5 and tile.x <= 50 and tile.y >= 8 and tile.y <= 25


func _station_color(station_id: String) -> Color:
	return {
		"bank": Color(0.22, 0.34, 0.72, 1.0),
		"shop": Color(0.74, 0.53, 0.20, 1.0),
		"cooking_range": Color(0.72, 0.30, 0.16, 1.0),
		"furnace": Color(0.75, 0.25, 0.10, 1.0),
		"anvil": Color(0.38, 0.39, 0.42, 1.0),
		"carpentry_bench": Color(0.56, 0.34, 0.18, 1.0),
		"apothecary_table": Color(0.35, 0.55, 0.26, 1.0),
	}.get(station_id, Color(0.70, 0.58, 0.22, 1.0))


func _display_label(value: String) -> String:
	return value.replace("_", " ").capitalize()
