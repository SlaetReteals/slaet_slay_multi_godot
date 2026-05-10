extends Node

const LEVEL_INFO: String = "INFO"
const LEVEL_WARN: String = "WARN"
const LEVEL_ERROR: String = "ERROR"

# Enable or disable standard info logs (useful for production builds)
@export var show_info_logs: bool = true

func info(context: String, message: String) -> void:
	if show_info_logs:
		_print_log(LEVEL_INFO, context, message)

func warn(context: String, message: String) -> void:
	_print_log(LEVEL_WARN, context, message)
	push_warning("[%s] %s" % [context, message])

func error(context: String, message: String) -> void:
	_print_log(LEVEL_ERROR, context, message)
	push_error("[%s] %s" % [context, message])

func _print_log(level: String, context: String, message: String) -> void:
	var timestamp: String = Time.get_time_string_from_system()
	print("[%s] [%s] [%s]: %s" % [timestamp, level, context, message])
