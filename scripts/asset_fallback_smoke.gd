extends SceneTree

const MANIFEST_PATH := "res://assets/asset_manifest.json"


func _init() -> void:
	var manifest := _load_json(MANIFEST_PATH)
	var passed := _manifest_defaults_exist(manifest)
	passed = passed and _asset_exists(_manifest_path(manifest, "items", "bronze_sword"))
	passed = passed and _asset_exists(_manifest_path(manifest, "ui", "bank"))
	passed = passed and _asset_exists(_manifest_path(manifest, "audio", "quest_complete"))
	passed = passed and _asset_path(manifest, "items", "missing_item") == _default_path(manifest, "icon")
	passed = passed and _asset_path(manifest, "effects", "missing_effect") == _default_path(manifest, "effect")
	if passed:
		print("Hearthvale asset fallback smoke passed.")
		quit(0)
	else:
		push_error("Hearthvale asset fallback smoke failed.")
		quit(1)


func _load_json(path: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed
	return {}


func _manifest_defaults_exist(manifest: Dictionary) -> bool:
	return _asset_exists(_default_path(manifest, "icon")) and _asset_exists(_default_path(manifest, "effect"))


func _manifest_path(manifest: Dictionary, category: String, asset_id: String) -> String:
	var category_data = manifest.get(category, {})
	if category_data is Dictionary:
		var entry = category_data.get(asset_id, {})
		if entry is Dictionary:
			return _resource_asset_path(str(entry.get("path", "")))
	return ""


func _asset_path(manifest: Dictionary, category: String, asset_id: String) -> String:
	var manifest_path := _manifest_path(manifest, category, asset_id)
	if not manifest_path.is_empty():
		return manifest_path
	if category == "effects":
		return _default_path(manifest, "effect")
	return _default_path(manifest, "icon")


func _default_path(manifest: Dictionary, default_id: String) -> String:
	var defaults = manifest.get("defaults", {})
	if defaults is Dictionary:
		var entry = defaults.get(default_id, {})
		if entry is Dictionary:
			return _resource_asset_path(str(entry.get("path", "")))
	return ""


func _resource_asset_path(relative_path: String) -> String:
	if relative_path.is_empty():
		return ""
	return "res://assets/%s" % relative_path


func _asset_exists(path: String) -> bool:
	return not path.is_empty() and FileAccess.file_exists(path)
