extends Node
## Asynchronous prefetch client. HTTPRequest never blocks input or game time.
const Core = preload("res://scripts/core/director.gd")
var _request: HTTPRequest
var _sent := {}
var _sent_run := {}
var _last_key := ""
var _elapsed := 0.0
var _next_allowed := 0
var _debounce := 0
var _observed := ""
var _next_start := 0
var _starts := 0
var last_status := "local"

func _ready() -> void:
	_request = HTTPRequest.new()
	_request.use_threads = true
	_request.timeout = 160.0 # Includes auth check plus the provider's own timeout.
	_request.body_size_limit = 65536
	add_child(_request)
	_request.request_completed.connect(_completed)

func connection() -> Dictionary:
	var base := OS.get_environment("LOCALAPPDATA")
	if base == "": return {}
	var file := base.path_join("SurvivorsLedger/director/connection.json")
	if not FileAccess.file_exists(file): return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not value is Dictionary or not Core.integer_ok(value.get("port"), 1024, 65535) or not Core.text_ok(value.get("token"), 128): return {}
	return value

func _process(delta: float) -> void:
	if Game._rewind_pending(): return
	_elapsed += delta
	if _elapsed < 1.0: return
	_elapsed = 0.0
	# All test scenes stay offline, including window-rendered save/load fixtures.
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path.begins_with("res://tests/"): return
	if Game.no_save or Game.run.is_empty() or not Game.screen in ["pre", "post", "explore"]: return
	var d := Core.state(Game.run)
	if not d.enabled: return
	# Do not spend a request immediately before a buffered choice invalidates it.
	if Game.run.pending_event != "" or not d.active.is_empty(): return
	for event in d.queue:
		if int(event.day) == int(Game.run.pday) and not int(event.day) in d.days: return
	var archive := Game.read_life_memory()
	var signature := "%s-%s-%s" % [d.session, d.revision, archive.get("sha256", "")]
	var now := Time.get_ticks_msec()
	if signature != _observed:
		_debounce = now + (15000 if _observed != "" else 0)
		_observed = signature
	if not _sent.is_empty() or now < _debounce or now < _next_allowed: return
	var sent := Core.snapshot(Game.run, archive)
	if sent.request_id == _last_key: return
	var config := connection()
	if config.is_empty():
		# Also works when opening project.godot instead of the launcher.
		var helper := ProjectSettings.globalize_path("res://tools/director/start.ps1")
		if OS.get_name() == "Windows" and FileAccess.file_exists(helper) and now >= _next_start and _starts < 3:
			OS.create_process("powershell.exe", ["-NoProfile", "-WindowStyle", "Hidden", "-File", helper], false)
			_starts += 1
			_next_start = now + 300000
		return # Offline: leave normal play and local events untouched.
	_last_key = sent.request_id
	_next_allowed = now + 45000
	request_plan(sent, config)

func request_plan(sent: Dictionary, config: Dictionary) -> Error:
	_sent = sent
	_sent_run = Game.run
	var error := _request.request("http://127.0.0.1:%d/plan" % int(config.port), ["Content-Type: application/json", "Authorization: Bearer " + str(config.token)], HTTPClient.METHOD_POST, JSON.stringify(sent))
	if error != OK:
		_sent = {}
		_sent_run = {}
		last_status = "local"
	return error

func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var sent := _sent
	var same_run := is_same(Game.run, _sent_run)
	_sent = {}
	_sent_run = {}
	if Game.no_save or Game._rewind_pending() or Game.run.is_empty() or sent.is_empty(): return
	if not same_run:
		last_status = "discarded"
		return
	var sent_hash: String = sent.get("state", {}).get("archive", {}).get("sha256", "")
	if sent_hash != str(Game.read_life_memory().get("sha256", "")):
		last_status = "discarded"
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		last_status = "local"
		return
	var reply = JSON.parse_string(body.get_string_from_utf8())
	if reply is Dictionary and reply.get("source", "") == "ark-plan" and Core.accept(Game.run, sent, reply.get("plan")):
		last_status = "prepared"
		Game.save_game()
	else:
		last_status = "discarded"

func set_enabled(enabled: bool) -> void:
	if Game.run.is_empty(): return
	Game.act(func():
		if str(Game.run.get("flags", {}).get("daily", "")) != "":
			return "每日一局使用固定世情，保持同一天的条件一致。"
		var d := Core.state(Game.run)
		d.enabled = enabled
		d.revision = int(d.revision) + 1
		d.queue = []
		return "")
