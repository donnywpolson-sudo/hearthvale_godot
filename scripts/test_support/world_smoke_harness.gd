extends "res://scripts/world.gd"

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
	var animation_time_before := player_animation_time
	_update_player_animation(1.0 / 60.0)
	if player_animation_time <= animation_time_before:
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
