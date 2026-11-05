extends Node
## QA-copy probe only; keep this file outside the production PCK.
## Godot 4.7.2 official templates disable CLI --script/--path overrides.
## Copy the unchanged final exe/PCK/licenses to a separate QA directory and
## place an override.cfg there selecting an external Node scene with this script.
## The production directory must never contain that override or test scene.
## Each mode needs a fresh isolated APPDATA:
##   -- --only=headless --user-root=<absolute isolation ancestor>
##   -- --only=visual --user-root=<fresh isolation ancestor> --output=<absolute dir>
## The supplied root is verified before default user:// save paths are exercised.

const GLYPHS := "劫余录尸潮炊饼糯米守夜Ⅱ▶←→子丑寅卯辰巳午未申酉戌亥0123456789，。！？"
const WEIGHT_AXIS := 0x77676874
var _checks := 0
var _completed := false
var _only := "headless"
var _user_root := ""
var _output := ""
var root: Window


func _ready() -> void:
	root = get_tree().root
	_start.call_deferred()


func quit(code := 0) -> void:
	get_tree().quit(code)


func create_timer(seconds: float) -> SceneTreeTimer:
	return get_tree().create_timer(seconds)


func _require(ok: bool, message: String) -> bool:
	_checks += 1
	if not ok:
		push_error("[windows_release_probe] FAIL: " + message)
		quit(1)
	return ok


func _normalized(path: String) -> String:
	return path.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()


func _inside(path: String, parent: String) -> bool:
	return _normalized(path).begins_with(_normalized(parent) + "/")


func _frames(count := 6) -> void:
	for index in count:
		await get_tree().process_frame


func _start() -> void:
	create_timer(30.0).timeout.connect(func():
		if not _completed:
			push_error("[windows_release_probe] FAIL: 30 second timeout before completion")
			quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg == "--visual":
			_only = "visual"
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
		elif arg.begins_with("--user-root="):
			_user_root = arg.trim_prefix("--user-root=")
		elif arg.begins_with("--output="):
			_output = arg.trim_prefix("--output=")
		else:
			_require(false, "unknown argument: " + arg)
			return
	if not _require(_only in ["headless", "visual"], "--only must select headless or visual"):
		return
	# A development editor or a portable editor renamed to the game must fail.
	if not _require(OS.has_feature("template") and not OS.has_feature("editor") and not OS.is_debug_build(), "actual release template required"):
		return
	if not _require(OS.get_name() == "Windows", "actual Windows release executable required"):
		return
	if not _require(_user_root.is_absolute_path() and not _normalized(_user_root).ends_with(":"), "explicit isolated --user-root required"):
		return
	if not _require(_inside(OS.get_user_data_dir(), _user_root), "user:// escapes the declared isolated root"):
		return
	await _frames(3)
	var game = root.get_node_or_null("Game")
	var director = root.get_node_or_null("StoryDirector")
	if not _require(game != null and director != null, "packaged autoloads missing"):
		return
	if not _require(director.offline_build() and director.offline_override == -1, "genuine offline build detection required"):
		return
	if not _require(not game.no_save and game.save_path == "user://save.json" and game.meta_path == "user://meta.json" and game.memory_path == "", "default save paths must be exercised without overrides"):
		return
	if not _require(game.resolved_memory_path() == "user://Memory.md", "template Memory must resolve to user://"):
		return
	for path in [game.save_path, game.meta_path, "user://Memory.md"]:
		if not _require(_inside(ProjectSettings.globalize_path(path), _user_root), "save target escapes isolation: " + path):
			return
		if not _require(not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"), "fresh isolated user directory required: " + path):
			return
	if not _require(not FileAccess.file_exists("res://project.godot"), "development project.godot leaked into package"):
		return
	for path in ["res://tests", "res://tools", "res://docs", "res://build", "res://.workbuddy"]:
		if not _require(not DirAccess.dir_exists_absolute(path), "development directory leaked into package: " + path):
			return
	for path in ["res://tests/windows_release_probe.gd", "res://tests/check_scripts.tscn", "res://tools/build_windows.ps1", "res://docs/50-windows-release.md"]:
		if not _require(not FileAccess.file_exists(path), "development file leaked into package: " + path):
			return
	if _only == "headless":
		if not _resources():
			return
		if not _require(game.quick_start() == "", "new game could not persist to default save path"):
			return
		var first_event := _first_offline_event(game)
		if first_event.is_empty():
			return
		var events = load("res://scripts/core/events.gd")
		if not _require(events != null and game.act(func(): return events.choose(game.run, int(first_event.choice))) == "", "packaged offline fallback choice failed"):
			return
		if not _offline_receipt(game, first_event):
			return
		if not _roundtrip(game, "post"):
			return
		print("[windows_release_probe] HEADLESS PASS: template/release/offline; 20 tables; 57 textures/55 atlas; 2 fonts actual 400/700; 2 OFL; 72 events/60 active/49 new; first-day 08:00 offline decision resolved; default save roundtrip; Memory=user://")
	else:
		if not await _visual(game):
			return
		print("[windows_release_probe] VISUAL PASS: title mouse quick-start; first-day 08:00 offline event mouse choice; courtyard HUD/clock; 57 inventory cards; 4 screenshots; default save roundtrip")
	_completed = true
	print("[windows_release_probe] COMPLETE PASS only=%s checks=%d" % [_only, _checks])
	quit(0)


func _resources() -> bool:
	var fonts = load("res://scripts/ui/fonts.gd")
	var data = load("res://scripts/core/data.gd")
	var art = load("res://scripts/ui/inventory_art.gd")
	if not _require(fonts != null and data != null and art != null, "runtime resource entry missing"):
		return false
	var seen := {}
	for font in [fonts.book(), fonts.body(), fonts.bold()]:
		var base: Font = font.base_font if font is FontVariation else font
		if not _require(base is FontFile and not base.allow_system_fallback and base.fallbacks.is_empty() and not base.data.is_empty(), "font is empty or uses system fallback"):
			return false
		seen[base.resource_path] = true
		for character in GLYPHS:
			if not _require(font.has_char(character.unicode_at(0)), "missing native glyph " + character):
				return false
	var server := TextServerManager.get_primary_interface()
	var weight_rids := []
	for pair in [[fonts.body(), 400], [fonts.bold(), 700]]:
		var rids: Array[RID] = pair[0].get_rids()
		if not _require(not rids.is_empty(), "font variation has no native RID"):
			return false
		var coordinates := server.font_get_variation_coordinates(rids[0])
		if not _require(int(coordinates.get(WEIGHT_AXIS, -1)) == pair[1], "actual font weight is not %d" % pair[1]):
			return false
		weight_rids.append(rids[0])
	if not _require(seen.size() == 2 and weight_rids[0] != weight_rids[1], "two embedded fonts and distinct weight RIDs required"):
		return false
	var license_path := OS.get_executable_path().get_base_dir().path_join("字体许可.txt")
	if not _require(FileAccess.file_exists(license_path), "adjacent font license missing"):
		return false
	var license_text := FileAccess.get_file_as_string(license_path)
	if not _require(license_text.count("SIL OPEN FONT LICENSE Version 1.1") == 2 and "LXGW" in license_text and "Google" in license_text, "two complete OFL font licenses missing"):
		return false
	if not _require(data.TABLES.size() == 20, "unexpected data table inventory"):
		return false
	for table_name in data.TABLES:
		var path := "res://data/%s.json" % table_name
		if not _require(FileAccess.file_exists(path), "packaged table file missing: " + path):
			return false
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not _require((parsed is Dictionary or parsed is Array) and not parsed.is_empty() and not data.table(table_name).is_empty(), "invalid or empty data table: " + path):
			return false
	var entries: Dictionary = data.table("events")
	var active_events := 0
	var new_events := 0
	for id in entries:
		var entry: Dictionary = entries[id]
		var active: bool = str(entry.get("story", "")) == "" and not id in ["neighbor_girl", "girl_gift", "paper_crane", "paper_crane_wood", "taoist"]
		if active:
			active_events += 1
		if str(id).begins_with("oe_") or str(id).begins_with("os_"):
			if not _require(active, "new offline event cannot be selected: " + id):
				return false
			new_events += 1
	if not _require(entries.size() == 72 and active_events == 60 and new_events == 49, "packaged event pool must contain 72 total, 60 active, 49 new offline decisions"):
		return false
	var expected: Array = data.table("items").keys()
	var actual: Array = art.ids()
	expected.sort()
	actual.sort()
	if not _require(expected.size() == 57 and actual == expected, "57 item textures must exactly match packaged items"):
		return false
	var atlases := 0
	for id in expected:
		var texture: Texture2D = art.texture(id)
		if not _require(texture != null and texture.get_width() > 0 and texture.get_height() > 0, "missing texture: " + id):
			return false
		if texture is AtlasTexture:
			if not _require(texture.atlas != null and texture.filter_clip and texture.region.has_area(), "invalid atlas texture: " + id):
				return false
			atlases += 1
	if not _require(atlases == 55, "55 atlas regions required"):
		return false
	return true


func _first_offline_event(game) -> Dictionary:
	var pre = load("res://scripts/core/pre.gd")
	var post = load("res://scripts/core/post.gd")
	var events = load("res://scripts/core/events.gd")
	if not _require(pre != null and post != null and events != null, "packaged first-day event rules missing"):
		return {}
	if str(game.run.get("phase", "")) == "pre":
		pre.start_disaster(game.run)
	if not _require(game.run.get("phase", "") == "post" and int(game.run.get("pday", -1)) == 1 and int(game.run.get("t", -1)) == 0 and game.run.get("pending_event", "") == "", "offline decision must begin at the real first-day dawn"):
		return {}
	var stop: String = str(post.advance(game.run, 120))
	game.refresh()
	var id: String = str(game.run.get("pending_event", ""))
	if not _require(stop == "event" and int(game.run.get("pday", -1)) == 1 and int(game.run.get("t", -1)) == 120 and id.begins_with("oe_"), "real first-day 08:00 did not present a new offline event"):
		return {}
	var entry: Dictionary = events.entry(game.run)
	if not _require(not str(entry.get("title", "")).is_empty() and not str(entry.get("text", "")).is_empty() and entry.get("choices", []).size() >= 2, "packaged offline event presentation is incomplete"):
		return {}
	var fallback := -1
	for index in entry.choices.size():
		var choice: Dictionary = entry.choices[index]
		if choice.get("req", {}).is_empty() and events.choice_ok(game.run, choice):
			fallback = index
	if not _require(fallback >= 0, "first-day event has no affordable choice without material requirements"):
		return {}
	return {"id": id, "title": str(entry.title), "text": str(entry.text), "choice": fallback, "choice_text": str(entry.choices[fallback].text), "result": str(entry.choices[fallback].get("result", ""))}


func _offline_receipt(game, event: Dictionary) -> bool:
	if not _require(str(game.run.get("pending_event", "")) == "" and event.id in game.run.get("seen_events", []) and not str(game.run.get("event_result", "")).is_empty(), "offline choice did not resolve, record its result, and enter seen events"):
		return false
	if not _require(str(game.run.event_result) == str(event.result), "offline fallback result differs from its packaged choice receipt"):
		return false
	return true


func _roundtrip(game, expected_phase: String) -> bool:
	game.run.flags["windows_release_probe"] = "default-path-roundtrip"
	game.meta["seen_manual"] = true
	game.save_game()
	for path in ["user://save.json", "user://meta.json", "user://Memory.md"]:
		if not _require(FileAccess.file_exists(path) and not FileAccess.get_file_as_string(path).is_empty(), "default save did not reach disk: " + path):
			return false
	var disk_save: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://save.json"))
	var disk_meta: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://meta.json"))
	if not _require(disk_save is Dictionary and disk_save.get("run", {}).get("flags", {}).get("windows_release_probe", "") == "default-path-roundtrip", "saved run marker missing"):
		return false
	if not _require(disk_meta is Dictionary and bool(disk_meta.get("seen_manual", false)), "default meta did not persist"):
		return false
	if not _require("survivors-memory:v1" in FileAccess.get_file_as_string("user://Memory.md") and game.memory_status == "updated", "runtime Memory archive not written to user://"):
		return false
	var before: Dictionary = game.run.duplicate(true)
	game.run = {}
	game.snapshots = {}
	if not _require(game.continue_game(), "saved game could not reload"):
		return false
	if not _require(str(game.run.get("phase", "")) == expected_phase and str(game.run.get("role", "")) == str(before.role) and int(game.run.get("t", -1)) == int(before.t) and game.run.get("flags", {}).get("windows_release_probe", "") == "default-path-roundtrip", "reloaded run differs from saved phase/role/time/marker"):
		return false
	if not _require(game.run.get("seen_events", []) == before.get("seen_events", []) and str(game.run.get("event_result", "")) == str(before.get("event_result", "")), "resolved offline event receipt did not survive the default save roundtrip"):
		return false
	return true


func _button(parent: Node, text: String) -> Button:
	for candidate in parent.find_children("*", "Button", true, false):
		if candidate.text == text and candidate.is_visible_in_tree():
			return candidate
	return null


func _click(target: Button) -> bool:
	if not _require(target != null and not target.disabled, "mouse target button missing or disabled"):
		return false
	var point := target.get_global_rect().get_center()
	if not _require(root.get_visible_rect().has_point(point), "mouse target is outside viewport"):
		return false
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion)
	await _frames(2)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event)
		await _frames(2)
	await _frames(8)
	return true


func _shot(name: String) -> bool:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	if not _require(picture != null and not picture.is_empty() and picture.get_width() >= 1280 and picture.get_height() >= 720, "actual viewport image missing: " + name):
		return false
	if not _require(picture.save_png(_output.path_join(name + ".png")) == OK, "could not save viewport PNG: " + name):
		return false
	return true


func _visual(game) -> bool:
	if not _require(DisplayServer.get_name() != "headless", "visual mode requires an actual rendered window"):
		return false
	if not _require(_output.is_absolute_path(), "visual --output must be an absolute directory"):
		return false
	if not _require(DirAccess.make_dir_recursive_absolute(_output) == OK, "cannot create screenshot output directory"):
		return false
	root.size = Vector2i(1280, 720)
	game.speed = 0
	game.meta["seen_manual"] = true
	game.go("title")
	var scene = load("res://scenes/main.tscn")
	if not _require(scene is PackedScene, "packaged main scene missing"):
		return false
	var main = scene.instantiate()
	root.add_child(main)
	get_tree().current_scene = main
	await create_timer(1.2).timeout
	await _frames(10)
	if not _require(game.screen == "title", "main scene did not display title"):
		return false
	if not await _shot("title"):
		return false
	if not await _click(_button(main._screen, "新开一卷")):
		return false
	if not _require(game.screen == "pre" and game.run.get("phase", "") == "pre", "actual title mouse click did not start a game"):
		return false
	var pre = load("res://scripts/core/pre.gd")
	if not _require(pre != null, "packaged pre-disaster rules missing"):
		return false
	pre.start_disaster(game.run)
	game.refresh()
	await _frames(16)
	if not _require(game.screen == "post" and game.run.get("phase", "") == "post", "disaster transition did not build courtyard HUD"):
		return false
	var first_event := _first_offline_event(game)
	if first_event.is_empty():
		return false
	await _frames(8)
	if not _require(main.has_modal("event"), "first-day offline event modal did not open"):
		return false
	var body_visible := false
	for label in main._modals["event"].find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and label.text == first_event.text:
			body_visible = true
	if not _require(body_visible, "actual offline event text was not presented in the rendered modal"):
		return false
	if not await _shot("offline-event"):
		return false
	if not await _click(_button(main._modals["event"], str(first_event.choice_text))):
		return false
	if not _offline_receipt(game, first_event):
		return false
	if not _require(main.has_modal("event"), "offline event result modal disappeared before acknowledgement"):
		return false
	if not await _click(_button(main._modals["event"], "知道了")):
		return false
	if not _require(not main.has_modal("event"), "offline event result did not close through real mouse input"):
		return false
	var clocks := 0
	for control in main._screen.find_children("*", "Control", true, false):
		if control.get_script() != null and control.get_script().resource_path == "res://scripts/ui/widgets/clock_dial.gd" and control.is_visible_in_tree():
			clocks += 1
	if not _require(clocks == 1, "courtyard must display one real clock dial"):
		return false
	if not await _shot("courtyard-hud"):
		return false
	var data = load("res://scripts/core/data.gd")
	if not _require(data != null and data.table("items").size() == 57, "inventory fixture needs the actual packaged 57 items"):
		return false
	var stock := {}
	for id in data.table("items"):
		stock[id] = 2
	game.run.home = stock
	if not _roundtrip(game, "post"):
		return false
	await _frames(8)
	var dialogs = root.get_node_or_null("Dialogs")
	if not _require(dialogs != null, "packaged dialogs autoload missing"):
		return false
	dialogs.inventory()
	await _frames(8)
	if not _require(main.has_modal("inventory"), "inventory modal did not open"):
		return false
	var cards := {}
	var illustrations := {}
	for control in main._modals["inventory"].find_children("*", "Control", true, false):
		if control.has_meta("inventory_item"):
			cards[str(control.get_meta("inventory_item"))] = true
		if control is TextureRect and control.has_meta("inventory_art"):
			if not _require(control.texture != null and control.texture.get_width() > 0, "inventory control has an empty texture"):
				return false
			illustrations[str(control.get_meta("inventory_art"))] = true
	if not _require(cards.size() == 57 and illustrations.size() == 57, "rendered inventory must construct all 57 illustrated item cards"):
		return false
	if not await _shot("inventory"):
		return false
	return true
