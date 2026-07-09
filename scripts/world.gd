extends Node3D

signal selection_changed(label: String)
signal hover_changed(label: String)
signal feedback_changed(message: String)
signal player_tile_changed(tile: Vector2i)
signal object_activated(object_data: Dictionary)
signal camera_heading_changed(heading_degrees: float)

const WORLD_DATA_PATH := "res://data/world.json"
const TILE_SIZE := 1.0
const PLAYER_SPEED := 3.2
const CAMERA_PAN_SPEED := 7.0
const CAMERA_ROTATE_SPEED := 1.4
const CAMERA_PITCH_DEGREES := -38.0
const CAMERA_HEIGHT := 5.8
const CAMERA_DISTANCE := 7.8
const CAMERA_FOV := 48.0
const CAMERA_PIVOT_HEIGHT := 0.55
const CAMERA_DRAG_PAN_SCALE := 0.025
const ZOOM_FOV_STEP := 3.0
const MIN_CAMERA_FOV := 30.0
const MAX_CAMERA_FOV := 82.0
const INTERACTION_RANGE := 1
const SHELL_MIN_TILE := Vector2i(5, 8)
const SHELL_MAX_TILE := Vector2i(50, 25)
const VISUAL_BASE_Y := -0.075
const VISUAL_OVERLAY_Y := -0.025
const VISUAL_DETAIL_Y := 0.015

const MATERIAL_COLORS := {
	"grass_dark": Color(0.17, 0.36, 0.19, 1.0),
	"grass_mid": Color(0.22, 0.46, 0.24, 1.0),
	"grass_light": Color(0.29, 0.53, 0.27, 1.0),
	"dirt_dark": Color(0.36, 0.25, 0.13, 1.0),
	"dirt_mid": Color(0.50, 0.36, 0.18, 1.0),
	"dirt_light": Color(0.62, 0.46, 0.25, 1.0),
	"water_dark": Color(0.08, 0.24, 0.38, 1.0),
	"water_mid": Color(0.13, 0.34, 0.53, 0.92),
	"shore": Color(0.42, 0.36, 0.21, 1.0),
	"stone_dark": Color(0.34, 0.34, 0.32, 1.0),
	"stone_mid": Color(0.50, 0.50, 0.46, 1.0),
	"wood_dark": Color(0.30, 0.18, 0.10, 1.0),
	"wood_mid": Color(0.48, 0.30, 0.15, 1.0),
	"wood_light": Color(0.64, 0.43, 0.22, 1.0),
	"cloth": Color(0.76, 0.48, 0.24, 1.0),
	"metal": Color(0.55, 0.56, 0.54, 1.0),
	"skin": Color(0.94, 0.75, 0.55, 1.0),
	"shadow": Color(0.05, 0.06, 0.05, 0.30),
	"highlight": Color(0.95, 0.78, 0.30, 1.0),
}

@onready var terrain_root: Node3D = $Terrain
@onready var objects_root: Node3D = $Objects
@onready var markers_root: Node3D = $Markers
@onready var player: CharacterBody3D = $Player
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $Ambient
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
var camera_center := Vector3.ZERO
var middle_mouse_panning := false
var last_camera_heading_degrees := -999.0
var selected_label: Label3D
var hover_object_key := ""


func _ready() -> void:
	world_data = _load_json(WORLD_DATA_PATH)
	_configure_camera()
	_configure_lighting()
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
	_initialize_camera_from_state(state)
	player_tile_changed.emit(current_tile)
	_emit_camera_heading_if_changed(true)
	feedback_changed.emit("Left-click objects for default actions. Right-click objects for options.")


func _process(delta: float) -> void:
	_update_camera(delta)
	_update_player(delta)
	_update_hover()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			middle_mouse_panning = event.pressed
			get_viewport().set_input_as_handled()
			return
		if not event.pressed:
			return
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_open_options_or_walk(event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_default_action_at_screen_position(event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_out()
	elif event is InputEventMouseMotion and middle_mouse_panning:
		_pan_camera_by_screen_delta(event.relative)
		get_viewport().set_input_as_handled()


func run_playable_shell_smoke() -> bool:
	var start_tile := current_tile
	var camera_position_start := camera_pivot.global_position
	_set_destination_tile(current_tile + Vector2i(1, 0))
	for _index in range(120):
		_update_player(1.0 / 60.0)
		_update_camera(1.0 / 60.0)
	if current_tile == start_tile:
		return false
	if camera_pivot.global_position.distance_to(camera_position_start) > 0.001:
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
	var hover_text := _hover_text_for_object(resource)
	if hover_text.is_empty() or not hover_text.contains(str(resource.get("label", ""))):
		return false
	var fishing_resource := _first_resource_with_skill("fishing")
	if fishing_resource.is_empty():
		return false
	state_ref["inventory"] = {"fishing_rod": 1}
	var rod_only_options := _menu_options_for_object(fishing_resource)
	if not _menu_has_label(rod_only_options, "Fish") or _menu_has_label(rod_only_options, "Rod"):
		return false
	state_ref["inventory"] = {"small_fishing_net": 1, "fishing_rod": 1}
	var multi_tool_options := _menu_options_for_object(fishing_resource)
	if not _menu_has_label(multi_tool_options, "Net") or not _menu_has_label(multi_tool_options, "Rod") or _menu_has_label(multi_tool_options, "Fish"):
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


func run_camera_minimap_smoke() -> bool:
	_force_player_tile(Vector2i(15, 15))
	_set_camera_center(_tile_to_player_world(current_tile))
	_set_camera_heading_degrees(35.0)
	var start_camera_center := camera_pivot.global_position
	var target_tile := _first_camera_smoke_walk_target()
	if target_tile == current_tile:
		return false
	if not _set_destination_tile(target_tile):
		return false
	for _index in range(180):
		_update_player(1.0 / 60.0)
		_update_camera(1.0 / 60.0)
		if not moving:
			break
	if current_tile != target_tile:
		return false
	if camera_pivot.global_position.distance_to(start_camera_center) > 0.001:
		return false
	_pan_camera_by_screen_delta(Vector2(48.0, -28.0))
	var panned_camera_center := camera_pivot.global_position
	if panned_camera_center.distance_to(start_camera_center) <= 0.001:
		return false
	reset_camera_north()
	if absf(_camera_heading_degrees()) > 0.1:
		return false
	if camera_pivot.global_position.distance_to(panned_camera_center) > 0.001:
		return false
	var minimap_data := get_minimap_data()
	var minimap_objects = minimap_data.get("objects", [])
	return int(minimap_data.get("width", 0)) > 0 and int(minimap_data.get("height", 0)) > 0 and minimap_objects is Array and not minimap_objects.is_empty()


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
	if world_environment == null or world_environment.environment == null:
		return false
	if terrain_root.find_child("TerrainBase", false, false) == null:
		return false
	if terrain_root.find_child("TerrainOverlays", false, false) == null:
		return false
	if terrain_root.find_child("TerrainDetails", false, false) == null:
		return false
	var bevel_mesh := _beveled_box_mesh(Vector3(0.5, 0.5, 0.5), 0.06)
	if bevel_mesh == null or bevel_mesh.get_surface_count() == 0:
		return false
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


func debug_current_tile() -> Vector2i:
	return current_tile


func debug_teleport_to_tile(tile: Vector2i) -> bool:
	if not _tile_in_bounds(tile) or _is_tile_blocked(tile):
		feedback_changed.emit("Debug teleport failed: tile is blocked or out of bounds")
		return false
	_clear_pending_interaction()
	_force_player_tile(tile)
	destination_marker.visible = false
	player_tile_changed.emit(current_tile)
	feedback_changed.emit("Debug teleported to %d, %d" % [tile.x, tile.y])
	return true


func debug_spawn_mob(mob_data: Dictionary) -> Dictionary:
	var tile := _debug_open_tile_near_player()
	if tile == Vector2i(-1, -1):
		feedback_changed.emit("Debug spawn failed: no open adjacent tile")
		return {}
	var data := mob_data.duplicate(true)
	var mob_id := str(data.get("id", data.get("mob_id", "debug_mob")))
	data["type"] = "mob"
	data["id"] = mob_id
	data["mob_id"] = mob_id
	data["label"] = str(data.get("label", data.get("display_name", mob_id.replace("_", " ").capitalize())))
	data["display_name"] = str(data["label"])
	data["tile"] = tile
	data["position"] = [tile.x, tile.y]
	_add_world_object(tile, str(data["label"]), Color(0.72, 0.20, 0.20, 1.0), data, "mob")
	_rebuild_blocked_tiles()
	feedback_changed.emit("Debug spawned %s at %d, %d" % [str(data["label"]), tile.x, tile.y])
	return data


func debug_spawn_ground_drop(item_id: String, quantity: int) -> Dictionary:
	var tile := _debug_open_tile_near_player(false)
	if tile == Vector2i(-1, -1):
		feedback_changed.emit("Debug drop failed: no open adjacent tile")
		return {}
	var item := {
		"object_id": "debug_drop_%d" % Time.get_ticks_msec(),
		"item_id": item_id,
		"quantity": quantity,
		"tile": [tile.x, tile.y],
		"type": "ground_item",
	}
	add_ground_drop(tile, item)
	feedback_changed.emit("Debug dropped %d %s at %d, %d" % [quantity, item_id.replace("_", " "), tile.x, tile.y])
	return item


func _update_camera(delta: float) -> void:
	var movement := Vector3.ZERO
	var forward := _camera_ground_forward()
	var right := _camera_ground_right()
	if Input.is_key_pressed(KEY_W):
		movement += forward
	if Input.is_key_pressed(KEY_S):
		movement -= forward
	if Input.is_key_pressed(KEY_A):
		movement -= right
	if Input.is_key_pressed(KEY_D):
		movement += right
	if movement != Vector3.ZERO:
		_pan_camera_world(movement.normalized() * CAMERA_PAN_SPEED * delta)
	if Input.is_key_pressed(KEY_Q):
		_rotate_camera(-CAMERA_ROTATE_SPEED * delta)
	if Input.is_key_pressed(KEY_E):
		_rotate_camera(CAMERA_ROTATE_SPEED * delta)
	_apply_camera_center()


func _pan_camera_by_screen_delta(screen_delta: Vector2) -> void:
	var right := _camera_ground_right()
	var forward := _camera_ground_forward()
	_pan_camera_world((-right * screen_delta.x + forward * screen_delta.y) * CAMERA_DRAG_PAN_SCALE)


func _pan_camera_world(offset: Vector3) -> void:
	camera_center += Vector3(offset.x, 0.0, offset.z)
	_apply_camera_center()
	_sync_camera_state()


func _rotate_camera(amount_radians: float) -> void:
	camera_pivot.rotation.y += amount_radians
	_emit_camera_heading_if_changed()
	_sync_camera_state()


func _camera_ground_forward() -> Vector3:
	var forward := -camera_pivot.global_transform.basis.z
	forward.y = 0.0
	if forward.length() <= 0.001:
		return Vector3(0.0, 0.0, -1.0)
	return forward.normalized()


func _camera_ground_right() -> Vector3:
	var right := camera_pivot.global_transform.basis.x
	right.y = 0.0
	if right.length() <= 0.001:
		return Vector3(1.0, 0.0, 0.0)
	return right.normalized()


func _apply_camera_center() -> void:
	camera_center.y = CAMERA_PIVOT_HEIGHT
	camera_pivot.global_position = camera_center


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


func _update_hover() -> void:
	if camera == null:
		return
	if option_menu != null and option_menu.visible:
		_set_hover_target("", "")
		return
	var mouse_position := get_viewport().get_mouse_position()
	var viewport_size := get_viewport().get_visible_rect().size
	if mouse_position.x < 0.0 or mouse_position.y < 0.0 or mouse_position.x > float(viewport_size.x) or mouse_position.y > float(viewport_size.y):
		_set_hover_target("", "")
		return
	var tile := _screen_to_ground_tile(mouse_position)
	var object_data = objects_by_tile.get(tile)
	if object_data is Dictionary:
		var object_key := "%d,%d:%s" % [tile.x, tile.y, str(object_data.get("id", object_data.get("label", "")))]
		_set_hover_target(object_key, _hover_text_for_object(object_data))
	else:
		_set_hover_target("", "")


func _set_hover_target(object_key: String, label: String) -> void:
	if object_key == hover_object_key:
		return
	hover_object_key = object_key
	hover_changed.emit(label)


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
	_sync_camera_state()


func _zoom_in() -> void:
	_apply_zoom(-ZOOM_FOV_STEP)


func _zoom_out() -> void:
	_apply_zoom(ZOOM_FOV_STEP)


func reset_camera_north() -> void:
	_set_camera_heading_degrees(0.0)


func get_minimap_data() -> Dictionary:
	var markers: Array[Dictionary] = []
	for object_data in objects_by_tile.values():
		if not (object_data is Dictionary):
			continue
		var tile := _object_tile(object_data)
		if tile == Vector2i(-1, -1):
			continue
		markers.append({
			"tile": [tile.x, tile.y],
			"type": str(object_data.get("type", "object")),
			"label": str(object_data.get("label", "Object")),
		})
	return {
		"width": int(world_data.get("width", 30)),
		"height": int(world_data.get("height", 30)),
		"dirt_tiles": _tiles_from_values(world_data.get("dirt_tiles", [])),
		"water_tiles": _tiles_from_values(world_data.get("water_tiles", [])),
		"blocked_tiles": _tiles_from_dictionary(blocked_tiles),
		"objects": markers,
	}


func debug_overlay_data() -> Dictionary:
	var objects: Array[Dictionary] = []
	for object_data in objects_by_tile.values():
		if not (object_data is Dictionary):
			continue
		var tile := _object_tile(object_data)
		if tile == Vector2i(-1, -1):
			continue
		objects.append({
			"id": str(object_data.get("id", "")),
			"type": str(object_data.get("type", "object")),
			"label": str(object_data.get("label", object_data.get("display_name", "Object"))),
			"tile": [tile.x, tile.y],
			"blocks_movement": _object_blocks_movement(object_data),
			"level": int(object_data.get("level", 0)),
		})
	var destination_tile := _world_to_tile(destination)
	return {
		"width": int(world_data.get("width", 30)),
		"height": int(world_data.get("height", 30)),
		"player_tile": [current_tile.x, current_tile.y],
		"destination_tile": [destination_tile.x, destination_tile.y],
		"path_tiles": _tiles_from_vector2i_array(path_tiles),
		"blocked_tiles": _tiles_from_dictionary(blocked_tiles),
		"water_tiles": _tiles_from_values(world_data.get("water_tiles", [])),
		"dirt_tiles": _tiles_from_values(world_data.get("dirt_tiles", [])),
		"objects": objects,
		"moving": moving,
		"pending_interaction": str(pending_interaction.get("label", "")) if pending_interaction is Dictionary else "",
		"hover_object_key": hover_object_key,
		"camera_heading": _camera_heading_degrees(),
	}


func camera_heading_for_smoke() -> float:
	return _camera_heading_degrees()


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
			if str(object_data.get("skill_id", "")) == "fishing":
				var has_net := _has_inventory_item("small_fishing_net")
				var has_rod := _has_inventory_item("fishing_rod")
				if has_net:
					options.append(_menu_option("Net", "fish_net", object_data))
				if has_net and has_rod:
					options.append(_menu_option("Rod", "fish_rod", object_data))
				elif not has_net:
					options.append(_menu_option(_resource_action_label(object_data), "default", object_data))
			else:
				options.append(_menu_option(_resource_action_label(object_data), "default", object_data))
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


func _hover_text_for_object(object_data: Dictionary) -> String:
	var label := str(object_data.get("label", "Object"))
	match str(object_data.get("type", "")):
		"resource":
			var skill_id := str(object_data.get("skill_id", ""))
			if skill_id.is_empty():
				return label
			var required_level := int(object_data.get("required_level", 1))
			var reward_id := str(object_data.get("item_reward", ""))
			var reward_text := _display_label(reward_id) if not reward_id.is_empty() else "reward"
			var level_text := "Lv %d %s" % [required_level, _display_label(skill_id)]
			var skills = state_ref.get("skills", {})
			if skills is Dictionary and _state_skill_level(skills, skill_id, 1) < required_level:
				return "%s (%s needed; gives %s)" % [label, level_text, reward_text]
			return "%s (%s; gives %s)" % [label, level_text, reward_text]
		"mob":
			return "%s (level %d)" % [label, int(object_data.get("level", 1))]
		"npc":
			return "%s (NPC)" % label
		"station":
			return "%s" % label
		"ground_item":
			return "%s" % label
		_:
			return label


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


func _first_resource_with_skill(skill_id: String) -> Dictionary:
	for value in objects_by_tile.values():
		if value is Dictionary and str(value.get("type", "")) == "resource" and str(value.get("skill_id", "")) == skill_id:
			return value
	return {}


func _first_mob_above_player_level() -> Dictionary:
	var player_level := _player_combat_level()
	for value in objects_by_tile.values():
		if value is Dictionary and str(value.get("type", "")) == "mob" and int(value.get("level", 1)) > player_level:
			return value
	return {}


func _menu_has_label(options: Array[Dictionary], label: String) -> bool:
	for option in options:
		if str(option.get("label", "")) == label:
			return true
	return false


func _configure_camera() -> void:
	camera_pivot.rotation = Vector3.ZERO
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = CAMERA_FOV
	camera.position = Vector3(0.0, CAMERA_HEIGHT, CAMERA_DISTANCE)
	camera.rotation_degrees = Vector3(CAMERA_PITCH_DEGREES, 0.0, 0.0)
	camera_center = Vector3(15.5, CAMERA_PIVOT_HEIGHT, 15.5)
	_apply_camera_center()


func _initialize_camera_from_state(state: Dictionary) -> void:
	var camera_state = state.get("camera", {})
	if not (camera_state is Dictionary):
		camera_state = {}
	var fallback_camera = world_data.get("camera", {})
	if not (fallback_camera is Dictionary):
		fallback_camera = {}
	var center_x := float(camera_state.get("center_x", fallback_camera.get("center_x", player.global_position.x)))
	var center_y := float(camera_state.get("center_y", fallback_camera.get("center_y", player.global_position.z)))
	camera_center = Vector3(center_x, CAMERA_PIVOT_HEIGHT, center_y)
	var heading := float(camera_state.get("heading", fallback_camera.get("heading", 0.0)))
	_set_camera_heading_degrees(heading)
	var saved_zoom := float(camera_state.get("zoom", CAMERA_FOV))
	camera.fov = saved_zoom if saved_zoom >= MIN_CAMERA_FOV and saved_zoom <= MAX_CAMERA_FOV else CAMERA_FOV
	_apply_camera_center()
	_sync_camera_state()


func _set_camera_center(center: Vector3) -> void:
	camera_center = Vector3(center.x, CAMERA_PIVOT_HEIGHT, center.z)
	_apply_camera_center()
	_sync_camera_state()


func _set_camera_heading_degrees(heading_degrees: float) -> void:
	camera_pivot.rotation.y = deg_to_rad(_normalize_degrees(heading_degrees))
	_emit_camera_heading_if_changed(true)
	_sync_camera_state()


func _camera_heading_degrees() -> float:
	return _normalize_degrees(rad_to_deg(camera_pivot.rotation.y))


func _normalize_degrees(value: float) -> float:
	return fposmod(value, 360.0)


func _emit_camera_heading_if_changed(force: bool = false) -> void:
	var heading := _camera_heading_degrees()
	if force or absf(heading - last_camera_heading_degrees) > 0.05:
		last_camera_heading_degrees = heading
		camera_heading_changed.emit(heading)


func _sync_camera_state() -> void:
	if not (state_ref is Dictionary):
		return
	var camera_state = state_ref.get("camera", {})
	if not (camera_state is Dictionary):
		camera_state = {}
	camera_state["center_x"] = camera_center.x
	camera_state["center_y"] = camera_center.z
	camera_state["heading"] = _camera_heading_degrees()
	camera_state["zoom"] = camera.fov
	state_ref["camera"] = camera_state


func _configure_lighting() -> void:
	sun.light_color = Color(1.0, 0.88, 0.68, 1.0)
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	sun.shadow_blur = 2.4
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.48, 0.54, 0.54, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.70, 0.66, 0.55, 1.0)
	environment.ambient_light_energy = 0.72
	environment.ssao_enabled = true
	environment.ssao_radius = 1.15
	environment.ssao_intensity = 1.2
	environment.ssao_power = 1.4
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.02
	environment.adjustment_contrast = 1.08
	environment.adjustment_saturation = 1.08
	world_environment.environment = environment


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
	var occupied_tiles := _visual_object_tiles()
	var base_root := Node3D.new()
	base_root.name = "TerrainBase"
	terrain_root.add_child(base_root)
	var overlay_root := Node3D.new()
	overlay_root.name = "TerrainOverlays"
	terrain_root.add_child(overlay_root)
	var detail_root := Node3D.new()
	detail_root.name = "TerrainDetails"
	terrain_root.add_child(detail_root)
	_add_terrain_base(base_root)
	for x in range(width):
		for y in range(height):
			var tile := Vector2i(x, y)
			if not _near_shell_area(tile):
				continue
			if dirt_tiles.has(tile):
				_add_path_tile(overlay_root, detail_root, tile)
			elif water_tiles.has(tile):
				_add_water_tile(overlay_root, detail_root, tile, water_tiles)
			else:
				_add_grass_detail(detail_root, tile, occupied_tiles)


func _add_terrain_base(parent: Node3D) -> void:
	var shell_size := SHELL_MAX_TILE - SHELL_MIN_TILE + Vector2i.ONE
	var center := Vector3(
		float(SHELL_MIN_TILE.x + SHELL_MAX_TILE.x + 1) * 0.5 * TILE_SIZE,
		VISUAL_BASE_Y,
		float(SHELL_MIN_TILE.y + SHELL_MAX_TILE.y + 1) * 0.5 * TILE_SIZE
	)
	var size := Vector3(float(shell_size.x) * TILE_SIZE, 0.08, float(shell_size.y) * TILE_SIZE)
	_add_flat_box(parent, center, size, MATERIAL_COLORS["grass_mid"], "continuous_grass_base")


func _add_path_tile(overlay_root: Node3D, detail_root: Node3D, tile: Vector2i) -> void:
	var color := _tile_variant_color(tile, "dirt_mid", 0.10, 7)
	_add_flat_box(
		overlay_root,
		_tile_to_ground_world(tile) + Vector3(0.0, VISUAL_OVERLAY_Y, 0.0),
		Vector3(TILE_SIZE * 1.04, 0.035, TILE_SIZE * 1.04),
		color,
		"path_%d_%d" % [tile.x, tile.y]
	)
	if _tile_noise(tile, 13) > 0.72:
		_add_flat_box(
			detail_root,
			_tile_to_ground_world(tile) + _tile_detail_offset(tile, 0.46, 14) + Vector3(0.0, VISUAL_DETAIL_Y, 0.0),
			Vector3(0.30 + _tile_noise(tile, 15) * 0.26, 0.018, 0.10 + _tile_noise(tile, 16) * 0.08),
			_tile_variant_color(tile, "dirt_light", 0.08, 17),
			"path_wear_%d_%d" % [tile.x, tile.y]
		)
	if _tile_noise(tile, 18) > 0.86:
		_add_flat_box(
			detail_root,
			_tile_to_ground_world(tile) + _tile_detail_offset(tile, 0.44, 19) + Vector3(0.0, VISUAL_DETAIL_Y + 0.002, 0.0),
			Vector3(0.44, 0.024, 0.075),
			_tile_variant_color(tile, "wood_mid", 0.07, 20),
			"path_plank_%d_%d" % [tile.x, tile.y]
		)


func _add_water_tile(overlay_root: Node3D, detail_root: Node3D, tile: Vector2i, water_tiles: Dictionary) -> void:
	var water_color := _tile_variant_color(tile, "water_mid", 0.08, 30)
	_add_flat_box(
		overlay_root,
		_tile_to_ground_world(tile) + Vector3(0.0, VISUAL_OVERLAY_Y - 0.032, 0.0),
		Vector3(TILE_SIZE * 1.04, 0.030, TILE_SIZE * 1.04),
		water_color,
		"water_%d_%d" % [tile.x, tile.y],
		true
	)
	if _tile_noise(tile, 31) > 0.62:
		_add_flat_box(
			detail_root,
			_tile_to_ground_world(tile) + _tile_detail_offset(tile, 0.50, 32) + Vector3(0.0, VISUAL_DETAIL_Y - 0.024, 0.0),
			Vector3(0.50, 0.010, 0.045),
			Color(0.56, 0.78, 0.86, 0.42),
			"water_glint_%d_%d" % [tile.x, tile.y],
			true
		)
	for raw_direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var direction: Vector2i = raw_direction
		var neighbor: Vector2i = tile + direction
		if water_tiles.has(neighbor):
			continue
		_add_shore_edge(detail_root, tile, direction)


func _add_shore_edge(parent: Node3D, tile: Vector2i, direction: Vector2i) -> void:
	var offset := Vector3(float(direction.x) * 0.48, 0.0, float(direction.y) * 0.48)
	var size := Vector3(0.88, 0.014, 0.10)
	if direction.x != 0:
		size = Vector3(0.10, 0.014, 0.88)
	_add_flat_box(
		parent,
		_tile_to_ground_world(tile) + offset + Vector3(0.0, VISUAL_DETAIL_Y - 0.015, 0.0),
		size,
		MATERIAL_COLORS["shore"],
		"shore_%d_%d_%d_%d" % [tile.x, tile.y, direction.x, direction.y]
	)


func _add_grass_detail(parent: Node3D, tile: Vector2i, occupied_tiles: Dictionary) -> void:
	if occupied_tiles.has(tile):
		return
	if _tile_noise(tile, 40) > 0.70:
		_add_grass_tuft(parent, tile, _tile_detail_offset(tile, 0.58, 41), "grass_tuft_%d_%d" % [tile.x, tile.y])
	if _tile_noise(tile, 42) > 0.88:
		_add_pebble(parent, tile, _tile_detail_offset(tile, 0.54, 43), "pebble_%d_%d" % [tile.x, tile.y])
	if _tile_noise(tile, 44) > 0.94:
		_add_flower(parent, tile, _tile_detail_offset(tile, 0.46, 45), "flower_%d_%d" % [tile.x, tile.y])
	if _tile_noise(tile, 46) > 0.91:
		_add_flat_box(
			parent,
			_tile_to_ground_world(tile) + _tile_detail_offset(tile, 0.54, 47) + Vector3(0.0, VISUAL_DETAIL_Y - 0.006, 0.0),
			Vector3(0.20, 0.012, 0.07),
			_tile_variant_color(tile, "dirt_dark", 0.06, 48),
			"root_scuff_%d_%d" % [tile.x, tile.y]
		)


func _add_grass_tuft(parent: Node3D, tile: Vector2i, offset: Vector3, name: String) -> void:
	var root := Node3D.new()
	root.name = name
	root.position = _tile_to_ground_world(tile) + offset
	root.rotation_degrees.y = _tile_noise(tile, 51) * 360.0
	parent.add_child(root)
	var color := _tile_variant_color(tile, "grass_light", 0.10, 52)
	_add_box(root, Vector3(-0.055, 0.035, 0.0), Vector3(0.035, 0.10, 0.035), color, "blade_a")
	_add_box(root, Vector3(0.0, 0.048, 0.02), Vector3(0.035, 0.13, 0.035), color.darkened(0.04), "blade_b")
	_add_box(root, Vector3(0.055, 0.030, -0.01), Vector3(0.035, 0.085, 0.035), color.lightened(0.05), "blade_c")


func _add_pebble(parent: Node3D, tile: Vector2i, offset: Vector3, name: String) -> void:
	_add_box(
		parent,
		_tile_to_ground_world(tile) + offset + Vector3(0.0, VISUAL_DETAIL_Y + 0.020, 0.0),
		Vector3(0.16, 0.07, 0.12),
		_tile_variant_color(tile, "stone_mid", 0.10, 53),
		name
	)


func _add_flower(parent: Node3D, tile: Vector2i, offset: Vector3, name: String) -> void:
	var root := Node3D.new()
	root.name = name
	root.position = _tile_to_ground_world(tile) + offset
	parent.add_child(root)
	_add_box(root, Vector3(0.0, 0.045, 0.0), Vector3(0.030, 0.09, 0.030), MATERIAL_COLORS["grass_light"], "stem")
	var bloom_color := Color(0.88, 0.38, 0.28, 1.0) if _tile_noise(tile, 54) > 0.5 else Color(0.86, 0.72, 0.24, 1.0)
	_add_box(root, Vector3(0.0, 0.105, 0.0), Vector3(0.075, 0.045, 0.075), bloom_color, "bloom")


func _tile_detail_offset(tile: Vector2i, radius: float, salt: int) -> Vector3:
	return Vector3((_tile_noise(tile, salt) - 0.5) * radius, 0.0, (_tile_noise(tile, salt + 1) - 0.5) * radius)


func _tile_noise(tile: Vector2i, salt: int) -> float:
	var value := sin(float(tile.x) * 12.9898 + float(tile.y) * 78.233 + float(salt) * 37.719) * 43758.5453
	return fposmod(value, 1.0)


func _tile_variant_color(tile: Vector2i, palette_key: String, amount: float, salt: int) -> Color:
	return _vary_color(MATERIAL_COLORS.get(palette_key, Color.WHITE), _tile_noise(tile, salt), amount)


func _object_variant_color(color: Color, object_key: String, amount: float) -> Color:
	return _vary_color(color, _string_noise(object_key, 3), amount)


func _vary_color(color: Color, noise: float, amount: float) -> Color:
	if noise < 0.5:
		return color.darkened((0.5 - noise) * 2.0 * amount)
	return color.lightened((noise - 0.5) * 2.0 * amount)


func _string_noise(value: String, salt: int) -> float:
	var total := salt * 7919
	for index in range(value.length()):
		total += value.unicode_at(index) * (index + 3)
	var noise_value := sin(float(total) * 0.0174533) * 43758.5453
	return fposmod(noise_value, 1.0)


func _visual_object_tiles() -> Dictionary:
	var tiles := {}
	for node in world_data.get("resource_nodes", []):
		if node is Dictionary:
			tiles[_array_to_tile(node.get("position", [0, 0]), Vector2i.ZERO)] = true
	for decoration in world_data.get("decorations", []):
		if decoration is Dictionary:
			tiles[_array_to_tile(decoration.get("position", [0, 0]), Vector2i.ZERO)] = true
	for npc in world_data.get("npcs", []):
		if npc is Dictionary:
			tiles[_array_to_tile(npc.get("tile", [0, 0]), Vector2i.ZERO)] = true
	for mob in world_data.get("mobs", []):
		if mob is Dictionary:
			tiles[_array_to_tile(mob.get("position", [0, 0]), Vector2i.ZERO)] = true
	for key in ["bank", "shop", "cooking_range", "furnace", "anvil", "carpentry_bench", "apothecary_table"]:
		var station = world_data.get(key)
		if station is Dictionary:
			tiles[_array_to_tile(station.get("tile", [0, 0]), Vector2i.ZERO)] = true
	tiles[_array_to_tile(world_data.get("player_start", [15, 15]), Vector2i(15, 15))] = true
	return tiles


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
	var object_key := str(data.get("id", label))
	var visual_color := _object_variant_color(color, object_key, 0.10)
	var root := Node3D.new()
	root.name = "Object_%s" % object_key.replace(" ", "_")
	root.position = _tile_to_ground_world(tile)
	objects_root.add_child(root)

	match kind:
		"resource":
			_add_resource_visual(root, data, visual_color)
		"decoration":
			_add_decoration_visual(root, data, visual_color)
		"npc":
			_add_npc_visual(root, visual_color)
		"mob":
			_add_mob_visual(root, data, visual_color)
		"drop":
			_add_drop_visual(root, visual_color)
		"bank":
			_add_bank_visual(root, visual_color)
		"shop":
			_add_shop_visual(root, visual_color)
		"cooking_range", "furnace", "anvil", "carpentry_bench", "apothecary_table":
			_add_station_visual(root, kind, visual_color)
		_:
			_add_box(root, Vector3(0.0, 0.32, 0.0), Vector3(0.54, 0.52, 0.54), visual_color, "marker")

	var label_node := Label3D.new()
	label_node.name = "Label"
	label_node.text = label
	label_node.position = Vector3(0.0, 1.15, 0.0)
	label_node.pixel_size = 0.008
	label_node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_node.outline_size = 2
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
			_add_signpost_visual(parent, "sign")
		"guidepost":
			_add_signpost_visual(parent, "guide")
		"crate":
			_add_crate_visual(parent, color)
		"barrel":
			_add_barrel_visual(parent)
		"lamp":
			_add_lamp_visual(parent)
		"well":
			_add_well_visual(parent)
		"noticeboard":
			_add_noticeboard_visual(parent)
		"tool_rack":
			_add_tool_rack_visual(parent)
		"supply_cart":
			_add_supply_cart_visual(parent)
		"banner":
			_add_banner_visual(parent, color)
		"fence":
			_add_fence_visual(parent)
		"stall":
			_add_stall_visual(parent, color)
		"dock":
			_add_dock_visual(parent)
		"bush":
			_add_bush_visual(parent)
		"fish_rack":
			_add_fish_rack_visual(parent)
		"boat":
			_add_boat_visual(parent)
		"bridge":
			_add_bridge_visual(parent)
		"campfire":
			_add_campfire_visual(parent)
		"mushroom":
			_add_mushroom_visual(parent)
		"reeds":
			_add_reeds_visual(parent)
		"ruins":
			_add_ruins_visual(parent)
		_:
			_add_box(parent, Vector3(0.0, 0.24, 0.0), Vector3(0.48, 0.38, 0.48), color, "decoration_marker")


func _add_signpost_visual(parent: Node3D, variant: String) -> void:
	_add_cylinder(parent, Vector3(0.0, 0.38, 0.0), 0.055, 0.76, MATERIAL_COLORS["wood_dark"], "%s_post" % variant)
	_add_box(parent, Vector3(0.0, 0.78, -0.04), Vector3(0.58, 0.22, 0.08), MATERIAL_COLORS["wood_mid"], "%s_board" % variant)
	if variant == "guide":
		_add_box(parent, Vector3(-0.20, 0.84, -0.11), Vector3(0.24, 0.06, 0.05), MATERIAL_COLORS["highlight"], "guide_arrow_left")
		_add_box(parent, Vector3(0.20, 0.72, -0.11), Vector3(0.24, 0.06, 0.05), MATERIAL_COLORS["highlight"], "guide_arrow_right")


func _add_crate_visual(parent: Node3D, color: Color) -> void:
	_add_box(parent, Vector3(0.0, 0.26, 0.0), Vector3(0.54, 0.48, 0.54), color.darkened(0.10), "crate_body")
	_add_box(parent, Vector3(0.0, 0.50, -0.285), Vector3(0.60, 0.08, 0.06), color.lightened(0.12), "crate_top_slat")
	_add_box(parent, Vector3(-0.27, 0.27, -0.285), Vector3(0.07, 0.42, 0.06), MATERIAL_COLORS["wood_dark"], "crate_side_slat_a")
	_add_box(parent, Vector3(0.27, 0.27, -0.285), Vector3(0.07, 0.42, 0.06), MATERIAL_COLORS["wood_dark"], "crate_side_slat_b")


func _add_barrel_visual(parent: Node3D) -> void:
	_add_cylinder(parent, Vector3(0.0, 0.34, 0.0), 0.24, 0.56, MATERIAL_COLORS["wood_mid"], "barrel_body")
	_add_cylinder(parent, Vector3(0.0, 0.58, 0.0), 0.25, 0.045, MATERIAL_COLORS["metal"], "barrel_top_band")
	_add_cylinder(parent, Vector3(0.0, 0.20, 0.0), 0.25, 0.045, MATERIAL_COLORS["metal"], "barrel_bottom_band")


func _add_lamp_visual(parent: Node3D) -> void:
	_add_cylinder(parent, Vector3(0.0, 0.42, 0.0), 0.045, 0.84, MATERIAL_COLORS["wood_dark"], "lamp_post")
	_add_box(parent, Vector3(0.0, 0.88, 0.0), Vector3(0.20, 0.20, 0.20), Color(0.95, 0.70, 0.28, 0.72), "lamp_glow", true)
	_add_box(parent, Vector3(0.0, 1.02, 0.0), Vector3(0.28, 0.08, 0.28), MATERIAL_COLORS["metal"], "lamp_cap")


func _add_well_visual(parent: Node3D) -> void:
	_add_cylinder(parent, Vector3(0.0, 0.20, 0.0), 0.34, 0.34, MATERIAL_COLORS["stone_mid"], "well_ring")
	_add_cylinder(parent, Vector3(0.0, 0.42, 0.0), 0.22, 0.06, MATERIAL_COLORS["water_dark"], "well_water")
	_add_box(parent, Vector3(-0.28, 0.70, 0.0), Vector3(0.08, 0.60, 0.08), MATERIAL_COLORS["wood_dark"], "well_post_a")
	_add_box(parent, Vector3(0.28, 0.70, 0.0), Vector3(0.08, 0.60, 0.08), MATERIAL_COLORS["wood_dark"], "well_post_b")
	_add_box(parent, Vector3(0.0, 1.00, 0.0), Vector3(0.78, 0.12, 0.44), MATERIAL_COLORS["wood_mid"], "well_roof")


func _add_noticeboard_visual(parent: Node3D) -> void:
	_add_box(parent, Vector3(-0.24, 0.38, 0.0), Vector3(0.07, 0.76, 0.08), MATERIAL_COLORS["wood_dark"], "notice_post_a")
	_add_box(parent, Vector3(0.24, 0.38, 0.0), Vector3(0.07, 0.76, 0.08), MATERIAL_COLORS["wood_dark"], "notice_post_b")
	_add_box(parent, Vector3(0.0, 0.70, -0.03), Vector3(0.72, 0.44, 0.08), MATERIAL_COLORS["wood_mid"], "notice_board")
	_add_box(parent, Vector3(-0.16, 0.76, -0.085), Vector3(0.16, 0.14, 0.025), Color(0.86, 0.77, 0.56, 1.0), "notice_note_a")
	_add_box(parent, Vector3(0.14, 0.62, -0.085), Vector3(0.18, 0.12, 0.025), Color(0.86, 0.77, 0.56, 1.0), "notice_note_b")


func _add_tool_rack_visual(parent: Node3D) -> void:
	_add_box(parent, Vector3(0.0, 0.58, 0.0), Vector3(0.78, 0.08, 0.10), MATERIAL_COLORS["wood_dark"], "rack_bar")
	_add_box(parent, Vector3(-0.34, 0.34, 0.0), Vector3(0.08, 0.66, 0.08), MATERIAL_COLORS["wood_dark"], "rack_post_a")
	_add_box(parent, Vector3(0.34, 0.34, 0.0), Vector3(0.08, 0.66, 0.08), MATERIAL_COLORS["wood_dark"], "rack_post_b")
	_add_box(parent, Vector3(-0.14, 0.42, -0.08), Vector3(0.05, 0.44, 0.05), MATERIAL_COLORS["metal"], "rack_tool_a")
	_add_box(parent, Vector3(0.12, 0.42, -0.08), Vector3(0.05, 0.44, 0.05), MATERIAL_COLORS["metal"], "rack_tool_b")


func _add_supply_cart_visual(parent: Node3D) -> void:
	_add_box(parent, Vector3(0.0, 0.34, 0.0), Vector3(0.78, 0.38, 0.52), MATERIAL_COLORS["wood_mid"], "cart_box")
	_add_cylinder(parent, Vector3(-0.42, 0.16, -0.22), 0.12, 0.08, MATERIAL_COLORS["wood_dark"], "cart_wheel_a")
	_add_cylinder(parent, Vector3(0.42, 0.16, -0.22), 0.12, 0.08, MATERIAL_COLORS["wood_dark"], "cart_wheel_b")
	_add_box(parent, Vector3(0.0, 0.58, 0.0), Vector3(0.46, 0.16, 0.34), Color(0.62, 0.50, 0.32, 1.0), "cart_sack")


func _add_banner_visual(parent: Node3D, color: Color) -> void:
	_add_cylinder(parent, Vector3(-0.22, 0.50, 0.0), 0.045, 1.0, MATERIAL_COLORS["wood_dark"], "banner_pole")
	_add_box(parent, Vector3(0.10, 0.78, -0.02), Vector3(0.52, 0.34, 0.055), color.lightened(0.08), "banner_cloth")
	_add_box(parent, Vector3(0.10, 0.60, -0.025), Vector3(0.36, 0.06, 0.045), color.darkened(0.16), "banner_trim")


func _add_fence_visual(parent: Node3D) -> void:
	_add_box(parent, Vector3(-0.32, 0.28, 0.0), Vector3(0.08, 0.56, 0.08), MATERIAL_COLORS["wood_dark"], "fence_post_a")
	_add_box(parent, Vector3(0.32, 0.28, 0.0), Vector3(0.08, 0.56, 0.08), MATERIAL_COLORS["wood_dark"], "fence_post_b")
	_add_box(parent, Vector3(0.0, 0.40, 0.0), Vector3(0.76, 0.08, 0.08), MATERIAL_COLORS["wood_mid"], "fence_rail_top")
	_add_box(parent, Vector3(0.0, 0.22, 0.0), Vector3(0.76, 0.08, 0.08), MATERIAL_COLORS["wood_mid"], "fence_rail_low")


func _add_stall_visual(parent: Node3D, color: Color) -> void:
	_add_box(parent, Vector3(0.0, 0.28, 0.0), Vector3(0.86, 0.34, 0.62), MATERIAL_COLORS["wood_mid"], "stall_counter")
	_add_box(parent, Vector3(0.0, 0.78, 0.0), Vector3(1.02, 0.14, 0.76), color.lightened(0.08), "stall_canopy")
	_add_box(parent, Vector3(-0.38, 0.54, 0.0), Vector3(0.07, 0.52, 0.07), MATERIAL_COLORS["wood_dark"], "stall_post_a")
	_add_box(parent, Vector3(0.38, 0.54, 0.0), Vector3(0.07, 0.52, 0.07), MATERIAL_COLORS["wood_dark"], "stall_post_b")
	_add_box(parent, Vector3(-0.20, 0.50, -0.20), Vector3(0.18, 0.10, 0.16), MATERIAL_COLORS["highlight"], "stall_goods_a")
	_add_box(parent, Vector3(0.18, 0.50, -0.14), Vector3(0.18, 0.10, 0.16), Color(0.54, 0.72, 0.28, 1.0), "stall_goods_b")


func _add_dock_visual(parent: Node3D) -> void:
	_add_box(parent, Vector3(0.0, 0.09, 0.0), Vector3(0.92, 0.12, 0.68), MATERIAL_COLORS["wood_mid"], "dock_planks")
	for x in [-0.34, 0.0, 0.34]:
		_add_box(parent, Vector3(float(x), 0.18, 0.0), Vector3(0.055, 0.13, 0.74), MATERIAL_COLORS["wood_light"], "dock_board_%s" % str(x))
	_add_cylinder(parent, Vector3(-0.42, 0.28, 0.28), 0.055, 0.50, MATERIAL_COLORS["wood_dark"], "dock_post_a")
	_add_cylinder(parent, Vector3(0.42, 0.28, 0.28), 0.055, 0.50, MATERIAL_COLORS["wood_dark"], "dock_post_b")


func _add_bush_visual(parent: Node3D) -> void:
	_add_sphere(parent, Vector3(0.0, 0.28, 0.0), Vector3(0.42, 0.24, 0.36), MATERIAL_COLORS["grass_dark"], "bush_core")
	_add_sphere(parent, Vector3(-0.18, 0.34, -0.04), Vector3(0.28, 0.18, 0.24), MATERIAL_COLORS["grass_light"], "bush_leaf_a")
	_add_sphere(parent, Vector3(0.20, 0.32, 0.04), Vector3(0.30, 0.18, 0.26), MATERIAL_COLORS["grass_mid"], "bush_leaf_b")


func _add_fish_rack_visual(parent: Node3D) -> void:
	_add_box(parent, Vector3(-0.32, 0.38, 0.0), Vector3(0.07, 0.76, 0.07), MATERIAL_COLORS["wood_dark"], "fish_rack_post_a")
	_add_box(parent, Vector3(0.32, 0.38, 0.0), Vector3(0.07, 0.76, 0.07), MATERIAL_COLORS["wood_dark"], "fish_rack_post_b")
	_add_box(parent, Vector3(0.0, 0.72, 0.0), Vector3(0.72, 0.07, 0.07), MATERIAL_COLORS["wood_mid"], "fish_rack_beam")
	_add_box(parent, Vector3(-0.16, 0.52, -0.02), Vector3(0.10, 0.20, 0.05), Color(0.52, 0.68, 0.66, 1.0), "drying_fish_a")
	_add_box(parent, Vector3(0.14, 0.50, -0.02), Vector3(0.10, 0.20, 0.05), Color(0.48, 0.64, 0.62, 1.0), "drying_fish_b")


func _add_boat_visual(parent: Node3D) -> void:
	_add_box(parent, Vector3(0.0, 0.16, 0.0), Vector3(0.92, 0.20, 0.38), MATERIAL_COLORS["wood_dark"], "boat_hull")
	_add_box(parent, Vector3(0.0, 0.25, 0.0), Vector3(0.70, 0.12, 0.24), MATERIAL_COLORS["wood_mid"], "boat_inner")
	_add_box(parent, Vector3(0.0, 0.34, -0.02), Vector3(0.08, 0.46, 0.08), MATERIAL_COLORS["wood_light"], "boat_oar")


func _add_bridge_visual(parent: Node3D) -> void:
	_add_box(parent, Vector3(0.0, 0.08, 0.0), Vector3(0.90, 0.14, 0.52), MATERIAL_COLORS["wood_mid"], "bridge_planks")
	_add_box(parent, Vector3(-0.32, 0.22, 0.0), Vector3(0.08, 0.28, 0.58), MATERIAL_COLORS["wood_dark"], "bridge_rail_a")
	_add_box(parent, Vector3(0.32, 0.22, 0.0), Vector3(0.08, 0.28, 0.58), MATERIAL_COLORS["wood_dark"], "bridge_rail_b")


func _add_campfire_visual(parent: Node3D) -> void:
	_add_box(parent, Vector3(-0.12, 0.08, 0.0), Vector3(0.42, 0.08, 0.12), MATERIAL_COLORS["wood_dark"], "camp_log_a")
	_add_box(parent, Vector3(0.12, 0.08, 0.0), Vector3(0.42, 0.08, 0.12), MATERIAL_COLORS["wood_dark"], "camp_log_b")
	_add_box(parent, Vector3(0.0, 0.22, 0.0), Vector3(0.16, 0.28, 0.16), Color(0.95, 0.32, 0.12, 0.86), "camp_flame", true)
	_add_box(parent, Vector3(0.0, 0.28, 0.0), Vector3(0.09, 0.20, 0.09), Color(1.0, 0.78, 0.22, 0.82), "camp_flame_core", true)


func _add_mushroom_visual(parent: Node3D) -> void:
	_add_cylinder(parent, Vector3(0.0, 0.16, 0.0), 0.08, 0.30, Color(0.84, 0.77, 0.58, 1.0), "mushroom_stem")
	_add_sphere(parent, Vector3(0.0, 0.34, 0.0), Vector3(0.28, 0.12, 0.28), Color(0.78, 0.24, 0.22, 1.0), "mushroom_cap")


func _add_reeds_visual(parent: Node3D) -> void:
	for index in range(5):
		var x := -0.18 + float(index) * 0.09
		var height := 0.36 + float(index % 2) * 0.10
		_add_cylinder(parent, Vector3(x, height * 0.5, 0.0), 0.018, height, Color(0.38, 0.58, 0.28, 1.0), "reed_%d" % index)


func _add_ruins_visual(parent: Node3D) -> void:
	_add_box(parent, Vector3(-0.20, 0.18, 0.02), Vector3(0.26, 0.32, 0.30), MATERIAL_COLORS["stone_mid"], "ruin_block_a")
	_add_box(parent, Vector3(0.14, 0.12, -0.04), Vector3(0.34, 0.20, 0.26), MATERIAL_COLORS["stone_dark"], "ruin_block_b")
	_add_box(parent, Vector3(0.28, 0.30, 0.06), Vector3(0.14, 0.48, 0.18), MATERIAL_COLORS["stone_mid"], "ruin_pillar")


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
	_add_box(parent, Vector3(-0.32, 0.54, -0.34), Vector3(0.18, 0.16, 0.12), MATERIAL_COLORS["highlight"], "bank_coin_stack_a")
	_add_box(parent, Vector3(0.30, 0.52, -0.34), Vector3(0.16, 0.12, 0.12), MATERIAL_COLORS["highlight"], "bank_coin_stack_b")


func _add_shop_visual(parent: Node3D, color: Color) -> void:
	_add_stall_visual(parent, color)
	_add_box(parent, Vector3(0.46, 0.23, 0.34), Vector3(0.28, 0.36, 0.28), MATERIAL_COLORS["wood_light"], "shop_side_crate")
	_add_box(parent, Vector3(0.46, 0.44, 0.18), Vector3(0.24, 0.10, 0.18), MATERIAL_COLORS["highlight"], "shop_side_goods")
	_add_box(parent, Vector3(-0.20, 0.54, -0.26), Vector3(0.18, 0.12, 0.16), Color(0.82, 0.28, 0.18, 1.0), "shop_red_goods")
	_add_box(parent, Vector3(0.08, 0.54, -0.28), Vector3(0.18, 0.12, 0.16), Color(0.26, 0.62, 0.30, 1.0), "shop_green_goods")


func _add_station_visual(parent: Node3D, station_id: String, color: Color) -> void:
	match station_id:
		"cooking_range":
			_add_box(parent, Vector3(0.0, 0.28, 0.0), Vector3(0.68, 0.50, 0.56), MATERIAL_COLORS["stone_dark"], "range_stone")
			_add_box(parent, Vector3(0.0, 0.58, -0.22), Vector3(0.36, 0.18, 0.10), Color(0.95, 0.34, 0.14, 1.0), "range_fire")
			_add_cylinder(parent, Vector3(0.0, 0.72, 0.05), 0.18, 0.16, Color(0.14, 0.14, 0.13, 1.0), "range_pot")
			_add_box(parent, Vector3(0.0, 0.96, 0.02), Vector3(0.24, 0.38, 0.24), MATERIAL_COLORS["stone_mid"], "range_chimney")
		"furnace":
			_add_cylinder(parent, Vector3(0.0, 0.40, 0.0), 0.36, 0.78, MATERIAL_COLORS["stone_mid"], "furnace_shell")
			_add_cylinder(parent, Vector3(0.0, 0.82, 0.0), 0.26, 0.12, MATERIAL_COLORS["stone_dark"], "furnace_lip")
			_add_box(parent, Vector3(0.0, 0.40, -0.32), Vector3(0.38, 0.28, 0.08), color.lightened(0.15), "furnace_glow")
			_add_box(parent, Vector3(0.0, 0.64, -0.34), Vector3(0.46, 0.07, 0.08), MATERIAL_COLORS["metal"], "furnace_door_band")
		"anvil":
			_add_box(parent, Vector3(0.0, 0.20, 0.0), Vector3(0.40, 0.26, 0.32), MATERIAL_COLORS["stone_dark"], "anvil_base")
			_add_box(parent, Vector3(0.0, 0.42, 0.0), Vector3(0.62, 0.18, 0.28), color.lightened(0.14), "anvil_top")
			_add_box(parent, Vector3(-0.42, 0.44, 0.0), Vector3(0.28, 0.12, 0.18), color.lightened(0.20), "anvil_horn")
			_add_box(parent, Vector3(0.36, 0.52, 0.0), Vector3(0.16, 0.14, 0.20), color.darkened(0.08), "anvil_tail")
		"carpentry_bench":
			_add_box(parent, Vector3(0.0, 0.34, 0.0), Vector3(0.94, 0.16, 0.46), MATERIAL_COLORS["wood_mid"], "bench_top")
			_add_box(parent, Vector3(-0.30, 0.16, 0.0), Vector3(0.10, 0.34, 0.10), MATERIAL_COLORS["wood_dark"], "bench_leg_a")
			_add_box(parent, Vector3(0.30, 0.16, 0.0), Vector3(0.10, 0.34, 0.10), MATERIAL_COLORS["wood_dark"], "bench_leg_b")
			_add_box(parent, Vector3(-0.16, 0.48, -0.14), Vector3(0.36, 0.06, 0.08), MATERIAL_COLORS["metal"], "bench_saw")
			_add_box(parent, Vector3(0.28, 0.48, 0.10), Vector3(0.20, 0.06, 0.12), MATERIAL_COLORS["wood_light"], "bench_mallet")
		"apothecary_table":
			_add_box(parent, Vector3(0.0, 0.32, 0.0), Vector3(0.78, 0.14, 0.46), MATERIAL_COLORS["wood_dark"], "apothecary_table")
			_add_cylinder(parent, Vector3(-0.18, 0.52, 0.0), 0.08, 0.22, Color(0.22, 0.68, 0.36, 1.0), "green_bottle")
			_add_cylinder(parent, Vector3(0.14, 0.50, 0.06), 0.07, 0.18, Color(0.66, 0.34, 0.76, 1.0), "purple_bottle")
			_add_box(parent, Vector3(0.30, 0.48, -0.08), Vector3(0.14, 0.05, 0.14), Color(0.82, 0.76, 0.48, 1.0), "herb_bundle")
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


func _add_flat_box(parent: Node, position: Vector3, size: Vector3, color: Color, name: String, transparent: bool = false) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = name
	mesh_instance.mesh = _box_mesh(size)
	mesh_instance.material_override = _material(color, transparent)
	mesh_instance.position = position
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_box(parent: Node, position: Vector3, size: Vector3, color: Color, name: String, transparent: bool = false) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = name
	mesh_instance.mesh = _beveled_box_mesh(size) if _should_bevel_box(size, transparent) else _box_mesh(size)
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


func _beveled_box_mesh(size: Vector3, bevel: float = -1.0) -> ArrayMesh:
	var min_axis: float = min(size.x, min(size.y, size.z))
	var bevel_size: float = bevel if bevel > 0.0 else clamp(min_axis * 0.16, 0.025, 0.075)
	bevel_size = min(bevel_size, min_axis * 0.42)
	var x0: float = -size.x * 0.5
	var x1: float = size.x * 0.5
	var y0: float = -size.y * 0.5
	var y1: float = size.y * 0.5
	var z0: float = -size.z * 0.5
	var z1: float = size.z * 0.5
	var b: float = bevel_size
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_mesh_quad(st, Vector3(x0 + b, y1, z0 + b), Vector3(x1 - b, y1, z0 + b), Vector3(x1 - b, y1, z1 - b), Vector3(x0 + b, y1, z1 - b))
	_add_mesh_quad(st, Vector3(x0 + b, y0, z1 - b), Vector3(x1 - b, y0, z1 - b), Vector3(x1 - b, y0, z0 + b), Vector3(x0 + b, y0, z0 + b))
	_add_mesh_quad(st, Vector3(x0 + b, y0 + b, z0), Vector3(x1 - b, y0 + b, z0), Vector3(x1 - b, y1 - b, z0), Vector3(x0 + b, y1 - b, z0))
	_add_mesh_quad(st, Vector3(x1 - b, y0 + b, z1), Vector3(x0 + b, y0 + b, z1), Vector3(x0 + b, y1 - b, z1), Vector3(x1 - b, y1 - b, z1))
	_add_mesh_quad(st, Vector3(x0, y0 + b, z1 - b), Vector3(x0, y0 + b, z0 + b), Vector3(x0, y1 - b, z0 + b), Vector3(x0, y1 - b, z1 - b))
	_add_mesh_quad(st, Vector3(x1, y0 + b, z0 + b), Vector3(x1, y0 + b, z1 - b), Vector3(x1, y1 - b, z1 - b), Vector3(x1, y1 - b, z0 + b))
	_add_mesh_quad(st, Vector3(x0 + b, y1, z0 + b), Vector3(x0 + b, y1 - b, z0), Vector3(x1 - b, y1 - b, z0), Vector3(x1 - b, y1, z0 + b))
	_add_mesh_quad(st, Vector3(x1 - b, y1, z1 - b), Vector3(x1 - b, y1 - b, z1), Vector3(x0 + b, y1 - b, z1), Vector3(x0 + b, y1, z1 - b))
	_add_mesh_quad(st, Vector3(x0 + b, y0, z1 - b), Vector3(x0 + b, y0 + b, z1), Vector3(x1 - b, y0 + b, z1), Vector3(x1 - b, y0, z1 - b))
	_add_mesh_quad(st, Vector3(x1 - b, y0, z0 + b), Vector3(x1 - b, y0 + b, z0), Vector3(x0 + b, y0 + b, z0), Vector3(x0 + b, y0, z0 + b))
	_add_mesh_quad(st, Vector3(x0, y1 - b, z0 + b), Vector3(x0 + b, y1, z0 + b), Vector3(x0 + b, y1, z1 - b), Vector3(x0, y1 - b, z1 - b))
	_add_mesh_quad(st, Vector3(x1 - b, y1, z0 + b), Vector3(x1, y1 - b, z0 + b), Vector3(x1, y1 - b, z1 - b), Vector3(x1 - b, y1, z1 - b))
	_add_mesh_quad(st, Vector3(x0 + b, y0, z0 + b), Vector3(x0, y0 + b, z0 + b), Vector3(x0, y0 + b, z1 - b), Vector3(x0 + b, y0, z1 - b))
	_add_mesh_quad(st, Vector3(x1, y0 + b, z0 + b), Vector3(x1 - b, y0, z0 + b), Vector3(x1 - b, y0, z1 - b), Vector3(x1, y0 + b, z1 - b))
	_add_mesh_quad(st, Vector3(x0, y0 + b, z0 + b), Vector3(x0 + b, y0 + b, z0), Vector3(x0 + b, y1 - b, z0), Vector3(x0, y1 - b, z0 + b))
	_add_mesh_quad(st, Vector3(x1 - b, y0 + b, z0), Vector3(x1, y0 + b, z0 + b), Vector3(x1, y1 - b, z0 + b), Vector3(x1 - b, y1 - b, z0))
	_add_mesh_quad(st, Vector3(x0 + b, y0 + b, z1), Vector3(x0, y0 + b, z1 - b), Vector3(x0, y1 - b, z1 - b), Vector3(x0 + b, y1 - b, z1))
	_add_mesh_quad(st, Vector3(x1, y0 + b, z1 - b), Vector3(x1 - b, y0 + b, z1), Vector3(x1 - b, y1 - b, z1), Vector3(x1, y1 - b, z1 - b))
	for raw_sx in [-1.0, 1.0]:
		var sx: float = float(raw_sx)
		for raw_sy in [-1.0, 1.0]:
			var sy: float = float(raw_sy)
			for raw_sz in [-1.0, 1.0]:
				var sz: float = float(raw_sz)
				var cx: float = x1 if sx > 0.0 else x0
				var cy: float = y1 if sy > 0.0 else y0
				var cz: float = z1 if sz > 0.0 else z0
				_add_mesh_triangle(
					st,
					Vector3(cx, cy - float(sy) * b, cz - float(sz) * b),
					Vector3(cx - float(sx) * b, cy, cz - float(sz) * b),
					Vector3(cx - float(sx) * b, cy - float(sy) * b, cz)
				)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	return mesh


func _add_mesh_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_add_mesh_triangle(st, a, b, c)
	_add_mesh_triangle(st, a, c, d)


func _add_mesh_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _should_bevel_box(size: Vector3, transparent: bool) -> bool:
	if transparent:
		return false
	return min(size.x, min(size.y, size.z)) >= 0.10


func _material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.82
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if transparent or color.a < 0.99:
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


func _tiles_from_values(values) -> Array:
	var tiles := []
	if not (values is Array):
		return tiles
	for value in values:
		var tile := _array_to_tile(value, Vector2i(-1, -1))
		if tile != Vector2i(-1, -1):
			tiles.append([tile.x, tile.y])
	return tiles


func _tiles_from_dictionary(tile_dictionary: Dictionary) -> Array:
	var tiles := []
	for tile in tile_dictionary.keys():
		if tile is Vector2i:
			tiles.append([tile.x, tile.y])
	return tiles


func _tiles_from_vector2i_array(tiles: Array[Vector2i]) -> Array:
	var result := []
	for tile in tiles:
		result.append([tile.x, tile.y])
	return result


func _first_camera_smoke_walk_target() -> Vector2i:
	var candidates: Array[Vector2i] = [
		current_tile + Vector2i(4, 0),
		current_tile + Vector2i(0, 4),
		current_tile + Vector2i(-4, 0),
		current_tile + Vector2i(0, -4),
		current_tile + Vector2i(2, 0),
		current_tile + Vector2i(0, 2),
	]
	for candidate in candidates:
		if _is_walkable_tile(candidate) and (not _find_path(current_tile, candidate).is_empty() or candidate == current_tile):
			return candidate
	return current_tile


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
	var route_info := _interaction_target_route(object_data)
	var tile = route_info.get("tile", Vector2i(-1, -1))
	if tile is Vector2i:
		return tile
	return Vector2i(-1, -1)


func _interaction_target_route(object_data: Dictionary) -> Dictionary:
	var object_tile := _object_tile(object_data)
	if object_tile == Vector2i(-1, -1):
		return {"tile": object_tile, "path": []}
	var candidates := {}
	for dx in range(-INTERACTION_RANGE, INTERACTION_RANGE + 1):
		for dy in range(-INTERACTION_RANGE, INTERACTION_RANGE + 1):
			var candidate := object_tile + Vector2i(dx, dy)
			if not _is_within_interaction_range(candidate, object_tile):
				continue
			if not _is_walkable_tile(candidate):
				continue
			candidates[candidate] = true
	return _nearest_route_to_any_tile(candidates)


func _nearest_route_to_any_tile(target_tiles: Dictionary) -> Dictionary:
	if target_tiles.is_empty() or not _is_walkable_tile(current_tile):
		return {"tile": Vector2i(-1, -1), "path": []}
	if target_tiles.has(current_tile):
		return {"tile": current_tile, "path": []}
	var frontier: Array[Vector2i] = [current_tile]
	var came_from := {}
	came_from[current_tile] = current_tile
	var directions: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var cursor := 0
	var max_visits := int(world_data.get("width", 30)) * int(world_data.get("height", 30))
	while cursor < frontier.size() and cursor < max_visits:
		var current: Vector2i = frontier[cursor]
		cursor += 1
		for direction in directions:
			var next_tile: Vector2i = current + direction
			if came_from.has(next_tile) or not _is_walkable_tile(next_tile):
				continue
			came_from[next_tile] = current
			if target_tiles.has(next_tile):
				return {"tile": next_tile, "path": _path_from_came_from(current_tile, next_tile, came_from, max_visits)}
			frontier.append(next_tile)
	return {"tile": Vector2i(-1, -1), "path": []}


func _path_from_came_from(start: Vector2i, goal: Vector2i, came_from: Dictionary, max_visits: int) -> Array[Vector2i]:
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


func _debug_open_tile_near_player(require_empty_object: bool = true) -> Vector2i:
	var offsets: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(1, 1),
		Vector2i(-1, 1),
		Vector2i(1, -1),
		Vector2i(-1, -1),
		Vector2i(2, 0),
		Vector2i(0, 2),
	]
	for offset in offsets:
		var tile := current_tile + offset
		if not _tile_in_bounds(tile) or _is_tile_blocked(tile):
			continue
		if require_empty_object and objects_by_tile.has(tile):
			continue
		return tile
	return Vector2i(-1, -1)


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
	return tile.x >= SHELL_MIN_TILE.x and tile.x <= SHELL_MAX_TILE.x and tile.y >= SHELL_MIN_TILE.y and tile.y <= SHELL_MAX_TILE.y


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
