class_name AirPodsHeadTrackerSingleton
extends Node

const STATE_PATH := "user://airpods_head_state.json"
const COMMAND_PATH := "user://airpods_head_command.json"
const POLL_INTERVAL: float = 1.0 / 30.0
const STALE_TIMEOUT_MS: int = 550
const SMOOTH_SPEED: float = 12.0
const MAX_YAW_OFFSET: float = deg_to_rad(35.0)
const MAX_PITCH_OFFSET: float = deg_to_rad(23.0)

var _enabled: bool = false
var _poll_accumulator: float = 0.0
var _target_offsets: Vector2 = Vector2.ZERO
var _smoothed_offsets: Vector2 = Vector2.ZERO
var _is_active: bool = false
var _last_state_received_ms: int = 0
var _tracking_state: String = "disabled"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_enabled = OS.get_name() == "iOS"
	if not _enabled:
		_tracking_state = "unsupported_platform"
		return
	_poll_state_file()

func _process(delta: float) -> void:
	if not _enabled:
		_smoothed_offsets = _smoothed_offsets.lerp(Vector2.ZERO, clampf(delta * SMOOTH_SPEED, 0.0, 1.0))
		return

	_poll_accumulator += delta
	while _poll_accumulator >= POLL_INTERVAL:
		_poll_accumulator -= POLL_INTERVAL
		_poll_state_file()

	var now_ms := Time.get_ticks_msec()
	if _is_active and now_ms - _last_state_received_ms > STALE_TIMEOUT_MS:
		_is_active = false
		_target_offsets = Vector2.ZERO
		_tracking_state = "stale"

	var smoothing := clampf(delta * SMOOTH_SPEED, 0.0, 1.0)
	_smoothed_offsets = _smoothed_offsets.lerp(_target_offsets, smoothing)

func get_offsets_rad() -> Vector2:
	return _smoothed_offsets

func is_active() -> bool:
	return _is_active

func get_tracking_state() -> String:
	return _tracking_state

func request_recenter() -> void:
	if not _enabled:
		return
	var absolute_path := ProjectSettings.globalize_path(COMMAND_PATH)
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		return
	var payload := {
		"action": "recenter",
		"request_id": "recenter-%s-%s" % [str(Time.get_unix_time_from_system()), str(Time.get_ticks_msec())],
		"timestamp_ms": Time.get_ticks_msec(),
	}
	file.store_string(JSON.stringify(payload))

func _poll_state_file() -> void:
	var absolute_path := ProjectSettings.globalize_path(STATE_PATH)
	if not FileAccess.file_exists(absolute_path):
		return
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		return

	var raw := file.get_as_text()
	if raw.is_empty():
		return

	var json := JSON.new()
	if json.parse(raw) != OK:
		return
	if typeof(json.data) != TYPE_DICTIONARY:
		return

	var payload := json.data as Dictionary
	_tracking_state = str(payload.get("tracking_state", "unknown"))
	var active := bool(payload.get("active", false))
	if not active:
		_is_active = false
		_target_offsets = Vector2.ZERO
		return

	var yaw := clampf(float(payload.get("yaw_rad", 0.0)), -MAX_YAW_OFFSET, MAX_YAW_OFFSET)
	var pitch := clampf(float(payload.get("pitch_rad", 0.0)), -MAX_PITCH_OFFSET, MAX_PITCH_OFFSET)
	_target_offsets = Vector2(yaw, pitch)
	_is_active = true
	_last_state_received_ms = Time.get_ticks_msec()
