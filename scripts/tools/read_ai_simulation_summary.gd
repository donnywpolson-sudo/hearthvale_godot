extends SceneTree

const DEFAULT_SUMMARY_PATH := "res://.godot/ai_simulation/_working/current/summary.json"

var summary_path = DEFAULT_SUMMARY_PATH
var output_file = ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _parse_args():
		quit(1)
		return
	var values = _summary_values(summary_path)
	var lines = []
	for key in ["SUMMARY_RUNS", "SUMMARY_ISSUE_OCCURRENCES", "SUMMARY_ISSUE_SAMPLES", "SUMMARY_PUBLISH_STATUS"]:
		lines.append("%s=%s" % [key, str(values.get(key, ""))])
	var text = "\n".join(lines)
	if output_file.strip_edges().is_empty():
		print(text)
	else:
		var file = FileAccess.open(output_file, FileAccess.WRITE)
		if file == null:
			push_error("Could not write summary output file: %s" % output_file)
			quit(1)
			return
		file.store_string(text)
		file.store_string("\n")
	quit(0)


func _parse_args() -> bool:
	var args = OS.get_cmdline_user_args()
	var index = 0
	while index < args.size():
		var arg = str(args[index])
		match arg:
			"--summary-path":
				var value = _arg_value(args, index, arg)
				if value.is_empty():
					return false
				index += 1
				summary_path = _resolve_repo_path(value)
			"--output-file":
				var value = _arg_value(args, index, arg)
				if value.is_empty():
					return false
				index += 1
				output_file = _resolve_repo_path(value)
			_:
				push_error("Unknown summary reader argument: %s" % arg)
				return false
		index += 1
	return true


func _arg_value(args: Array, index: int, flag: String) -> String:
	if index + 1 >= args.size():
		push_error("%s requires a value." % flag)
		return ""
	var value = str(args[index + 1])
	if value.begins_with("--"):
		push_error("%s requires a value." % flag)
		return ""
	return value


func _resolve_repo_path(path_value: String) -> String:
	if path_value.strip_edges().is_empty():
		return path_value
	var normalized = path_value.replace("\\", "/")
	if normalized.begins_with("res://") or normalized.begins_with("user://") or normalized.begins_with("/") or (normalized.length() > 1 and normalized[1] == ":"):
		return normalized
	return "res://%s" % normalized


func _summary_values(path: String) -> Dictionary:
	var result = {
		"SUMMARY_RUNS": "",
		"SUMMARY_ISSUE_OCCURRENCES": "",
		"SUMMARY_ISSUE_SAMPLES": "",
		"SUMMARY_PUBLISH_STATUS": "",
	}
	if not FileAccess.file_exists(path):
		return result
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return result
	var summary: Dictionary = parsed
	var config = summary.get("config", {})
	if config is Dictionary:
		result["SUMMARY_RUNS"] = _value_text(config.get("runs", ""))
	result["SUMMARY_ISSUE_OCCURRENCES"] = _value_text(summary.get("issue_occurrences", ""))
	result["SUMMARY_ISSUE_SAMPLES"] = _value_text(summary.get("issue_samples", ""))
	var trust = summary.get("trust", {})
	if trust is Dictionary:
		result["SUMMARY_PUBLISH_STATUS"] = str(trust.get("latest_publish_status", ""))
	return result


func _value_text(value) -> String:
	if typeof(value) == TYPE_FLOAT and is_equal_approx(float(value), round(float(value))):
		return str(int(round(float(value))))
	return str(value)
