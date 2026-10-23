extends Node
## Real settlement/file/prefetch flow, isolated from player files and all networks.
const Archive = preload("res://scripts/core/life_memory_file.gd")
const State = preload("res://scripts/core/state.gd")
const Past = preload("res://scripts/core/past_lives.gd")
const Pre = preload("res://scripts/core/pre.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Events = preload("res://scripts/core/events.gd")
const Data = preload("res://scripts/core/data.gd")
const Core = preload("res://scripts/core/director.gd")
const Ledger = preload("res://scripts/core/ledger.gd")
var failures := 0
var checks := 0
var completed := 0
var scratch := ""
var archive_path := ""
var root_path := ""
var root_before := ""
var first_meta := {}
var second_meta := {}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func contents(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

func fingerprint(path: String) -> String:
	return contents(path).sha256_text() if FileAccess.file_exists(path) else "missing"

func write(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(text)
	file.close()
	return true

func at(run: Dictionary, day: int, minute := 120) -> void:
	run.pday = day
	run.t = (day - 1) * 1440 + minute

func start(meta: Dictionary = {}) -> void:
	if not meta.is_empty(): Game.meta = meta
	Game.new_game("escort")
	Pre.start_disaster(Game.run)
	Game.run.home = {"rice": 4, "plague_powder": 1}
	Game.run.pending_event = ""
	at(Game.run, 2)
	Neighbor.state(Game.run).stage = "waiting"

func donate() -> void:
	check(Neighbor.poll(Game.run) == "n_request", "Real neighbor request did not open")
	var choice := -1
	var choices: Array = Data.table("events").n_request.choices
	for index in choices.size():
		if choices[index].id == "donate_home": choice = index
	check(choice >= 0, "Real neighbor donation choice is absent")
	if choice >= 0: check(Events.choose(Game.run, choice) == "", "Real neighbor donation was blocked")
	check(Game.run.past_lives.trace.any(func(f): return f.actor == "ning" and str(f.fact).contains("交给阿宁")), "Real donation did not record its witnessed fact")

func test_settlement_file_and_idempotence() -> void:
	start(State.new_meta())
	check(not FileAccess.file_exists(archive_path) or Archive.read_context(archive_path).get("markdown", "") == Archive.render(Game.meta), "New scratch archive has unrelated data")
	donate()
	Game.run.phase = "dead"
	Game.end_run()
	check(FileAccess.file_exists(archive_path), "Game.end_run did not create Memory.md")
	check(int(Past.book(Game.meta).count) == 1, "Settlement did not seal exactly one life")
	var text := contents(archive_path)
	check(text.contains("阿宁") and text.contains("交给阿宁"), "Memory.md omitted the executed donation")
	check(text.contains("2") and not Past.book(Game.meta).lives[0].get("summary", {}).is_empty(), "Archived life omitted its actual run summary")
	check(Archive.read_context(archive_path).get("markdown", "") == text, "File context is not the file's actual contents")
	Game.end_run()
	check(int(Past.book(Game.meta).count) == 1 and contents(archive_path) == text, "Repeated settlement duplicated or rewrote the same life")
	first_meta = Game.meta.duplicate(true)
	Game.close_book()
	check(Game.run.is_empty() and int(Past.book(Game.meta).count) == 1, "Closing an already sealed book created another life")
	check(contents(archive_path) == text, "Closing an already sealed book rewrote its archive")
	completed += 1

func test_next_life_uses_actual_file() -> void:
	start()
	check(Game.run.past_lives.awakenings.is_empty(), "A newly opened life already has an awakened fragment")
	var actual := Game.read_life_memory()
	check(actual.get("markdown", "") == contents(archive_path) and str(actual.get("sha256", "")) == contents(archive_path).sha256_text(), "AI input was synthesized instead of read from Memory.md")
	var snapshot := Core.snapshot(Game.run, actual)
	check(snapshot.state.get("archive", {}) == actual, "Director snapshot omitted the actual previous-life file")
	check(str(snapshot.request_id).ends_with("-m" + str(actual.get("sha256", "")).left(16)), "Request identity did not include the file fingerprint")
	check(str(snapshot.state.archive.get("markdown", "")).contains("交给阿宁"), "Unawakened previous-life facts are absent from AI file context")
	check(snapshot.state.recollections.is_empty(), "Reading the archive fabricated a public NPC awakening")
	completed += 1

func test_manual_edit_is_preserved_and_read() -> void:
	var original := Game.read_life_memory()
	var original_request := Core.snapshot(Game.run, original)
	var edited := contents(archive_path) + "\n玩家手记：此轮归档后，我记得阿宁收到了药。\n"
	check(write(archive_path, edited), "Could not edit the scratch Markdown archive")
	Game.save_meta()
	var actual := Game.read_life_memory()
	check(contents(archive_path) == edited, "Same-life save overwrote a manually edited Memory.md")
	check(actual.get("markdown", "") == edited and str(actual.get("sha256", "")) == edited.sha256_text(), "Planner did not read the manually edited file text")
	var changed := Core.snapshot(Game.run, actual)
	check(str(changed.request_id) != str(original_request.request_id), "A changed Memory.md reused the previous planning request ID")
	check(changed.state.archive.get("markdown", "") == edited, "Planner archive still used the old generated summary")
	completed += 1

func test_inflight_response_rejected_after_edit() -> void:
	var sent := Core.snapshot(Game.run, Game.read_life_memory())
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/director-plan.json"))
	for event in plan.days: event.day = int(event.day) + int(sent.current_day)
	check(Core.validate(plan, int(sent.current_day)), "Stale-response replay plan is not otherwise valid")
	StoryDirector._sent = sent
	StoryDirector._sent_run = Game.run
	StoryDirector.last_status = "pending"
	check(write(archive_path, contents(archive_path) + "\n玩家手记补充：这条是在请求发出之后写下的。\n"), "Could not edit archive while request is in flight")
	StoryDirector._completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"source": "ark-plan", "plan": plan}).to_utf8_buffer())
	check(StoryDirector.last_status == "discarded", "An in-flight reply planned against the previous file was accepted")
	check(Core.state(Game.run).queue.is_empty(), "Stale archive reply populated the future queue")
	check(StoryDirector._sent.is_empty() and StoryDirector._sent_run.is_empty(), "Rejected reply left the prefetch client blocked")
	StoryDirector._sent = Core.snapshot(Game.run, Game.read_life_memory())
	StoryDirector._sent_run = Game.run
	StoryDirector._completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"source": "ark-plan", "plan": plan}).to_utf8_buffer())
	check(StoryDirector.last_status == "prepared" and Core.state(Game.run).queue.size() == 3, "A valid replay planned with the current file was incorrectly rejected")
	completed += 1

func test_restart_recovery_and_old_file_guard() -> void:
	Game.run.phase = "dead"
	Game.restart_from_cover()
	check(int(Past.book(Game.meta).count) == 2, "Restart did not seal its current life once")
	check(not Game.run.past_lives.archived and int(Game.run.past_lives.generation) == 3, "Restart did not begin the next life")
	var latest := contents(archive_path)
	check(latest == Archive.render(Game.meta), "A new life did not refresh Memory.md from the new archive")
	second_meta = Game.meta.duplicate(true)
	check(Archive.sync(first_meta, archive_path) == OK and contents(archive_path) == latest, "Old meta overwrote a newer-count Memory.md")
	check(DirAccess.remove_absolute(archive_path) == OK, "Could not delete the scratch archive for recovery")
	var recovered := Game.read_life_memory()
	check(recovered.get("markdown", "") == latest and FileAccess.file_exists(archive_path), "Missing Memory.md was not restored from the latest meta")
	check(write(archive_path, Archive.render(first_meta)), "Could not prepare a lagging-count file")
	check(Game.read_life_memory().get("markdown", "") == latest, "Lagging-count Memory.md was not updated from the latest meta")
	Game.meta = first_meta.duplicate(true)
	Game.save_meta()
	check(contents(archive_path) == latest, "Loading/saving old meta rolled back the newer archive file")
	Game.meta = second_meta.duplicate(true)
	completed += 1

func test_rewind_discards_undone_facts() -> void:
	Game.memory_path = scratch.path_join("rewind.md")
	start(State.new_meta())
	at(Game.run, 1)
	Game.snapshots = {"1": Game.run.duplicate(true)}
	at(Game.run, 2)
	donate()
	Game.rewind()
	check(Game.run.past_lives.trace.is_empty(), "Rewind retained the donation from its discarded timeline")
	check(int(Past.book(Game.meta).count) == 0, "Turning a page created a completed life")
	Game.run.phase = "dead"
	Game.end_run()
	check(int(Past.book(Game.meta).count) == 1, "Rewound life did not seal exactly once")
	check(not contents(Game.memory_path).contains("交给阿宁"), "Memory.md claimed an action undone by rewind")
	completed += 1

func test_daily_summary_without_effects() -> void:
	Game.memory_path = scratch.path_join("daily.md")
	Game.meta = State.new_meta()
	Game.new_game("escort", "normal", [], [], [], false, true)
	Pre.start_disaster(Game.run)
	at(Game.run, 4)
	Past.record(Game.run, "ning", "daily_fact", "每日局中不应进入私人事实的行为。", 1)
	Game.run.phase = "dead"
	Game.end_run()
	check(int(Past.book(Game.meta).count) == 1, "Completed daily life did not produce its run summary")
	var life: Dictionary = Past.book(Game.meta).lives[0]
	check(life.get("facts", []).is_empty() and not life.get("summary", {}).is_empty(), "Daily archive omitted its summary or introduced private facts")
	check(FileAccess.file_exists(Game.memory_path) and not contents(Game.memory_path).contains("每日局中不应"), "Daily Markdown contains an unrecorded private action")
	check(Past.public_memories(Game.run).is_empty(), "Daily run exposed personal NPC recollections")
	check(Core.snapshot(Game.run, Game.read_life_memory()).state.get("archive", {}).is_empty(), "Daily planner was given account-specific archive effects")
	completed += 1

func test_bad_files_and_render_bounds() -> void:
	var path := scratch.path_join("invalid.md")
	check(Archive.read_context(path).is_empty(), "Missing file produced invented AI context")
	check(write(path, "") and Archive.read_context(path).is_empty(), "Empty file produced AI context")
	check(write(path, "字".repeat(8001)) and Archive.read_context(path).is_empty(), "Oversized file was accepted for AI context")
	var oversized := contents(path)
	check(Archive.sync(second_meta, path) != OK and contents(path) == oversized, "Sync overwrote a user's oversized Markdown file instead of returning an error")
	var emoji := "😀".repeat(4001)
	check(emoji.length() < 8000 and emoji.to_utf16_buffer().size() > 16000, "Emoji boundary fixture did not distinguish code points from UTF-16 units")
	check(write(path, emoji) and Archive.read_context(path).is_empty(), "UTF-16 oversized emoji file was accepted because its Godot character count is smaller")
	check(Archive.sync(second_meta, path) != OK and contents(path) == emoji, "Sync overwrote a UTF-16 oversized emoji archive")
	check(Archive.read_context(scratch).is_empty(), "A directory was accepted as a Markdown file")
	check(Archive.sync(second_meta, scratch.path_join("missing-parent/Memory.md")) != OK, "Unwritable archive destination did not return an error")
	var large := second_meta.duplicate(true)
	var large_book := Past.book(large)
	var template: Dictionary = large_book.lives[-1].duplicate(true)
	large_book.lives = []
	large_book.count = 8
	for ordinal in range(1, 9):
		var life: Dictionary = template.duplicate(true)
		life.life = ordinal
		life["facts"] = []
		for i in range(12): life.facts.append({"actor": "ning", "fact_id": "fact_%d" % i, "fact": "真实事实".repeat(32), "valence": 1})
		large_book.lives.append(life)
	var rendered := Archive.render(large)
	check(not rendered.is_empty() and rendered.length() <= 8000, "Rendered Memory.md exceeded the bounded context budget")
	check(rendered.contains("第 8 世") and not rendered.contains("第 1 世"), "Bounded rendering failed to prioritize the latest completed life")
	completed += 1

func test_no_save_and_old_ui_isolation() -> void:
	var blocked := scratch.path_join("no-save.md")
	Game.memory_path = blocked
	Game.no_save = true
	Game.meta = second_meta.duplicate(true)
	Game.save_meta()
	check(Game.read_life_memory().is_empty() and not FileAccess.file_exists(blocked), "no_save performed Markdown IO")
	Game.no_save = false
	Game.memory_path = ""
	Game.save_meta()
	check(Game.read_life_memory().is_empty(), "Legacy test paths with no explicit archive path resolved to the real project file")
	check(fingerprint(root_path) == root_before, "Scratch tests changed the real root Memory.md")
	completed += 1

func cleanup() -> void:
	Game.no_save = true
	for file in DirAccess.get_files_at(scratch):
		DirAccess.remove_absolute(scratch.path_join(file))
	DirAccess.remove_absolute(scratch)

func _ready() -> void:
	Game.no_save = true
	StoryDirector.set_process(false)
	Data.ensure()
	root_path = ProjectSettings.globalize_path("res://Memory.md")
	root_before = fingerprint(root_path)
	scratch = OS.get_environment("TEMP").path_join("ledger-memory-flow-%d-%s" % [Time.get_ticks_msec(), Crypto.new().generate_random_bytes(4).hex_encode()])
	if DirAccess.make_dir_recursive_absolute(scratch) != OK:
		push_error("Could not create isolated memory flow directory")
		get_tree().quit(1)
		return
	archive_path = scratch.path_join("Memory.md")
	Game.save_path = scratch.path_join("save.json")
	Game.meta_path = scratch.path_join("meta.json")
	Game.memory_path = archive_path
	Game.no_save = false
	var cases := [test_settlement_file_and_idempotence, test_next_life_uses_actual_file,
		test_manual_edit_is_preserved_and_read, test_inflight_response_rejected_after_edit,
		test_restart_recovery_and_old_file_guard, test_rewind_discards_undone_facts,
		test_daily_summary_without_effects, test_bad_files_and_render_bounds,
		test_no_save_and_old_ui_isolation]
	for test in cases: test.call()
	check(completed == cases.size(), "A memory file test group aborted before its completion sentinel (%d/%d)" % [completed, cases.size()])
	check(fingerprint(root_path) == root_before, "Real root Memory.md changed during the file flow test")
	cleanup()
	print("Memory file flow: %d/%d completed, %d checks, %d failures; no ARK calls; root archive unchanged" % [completed, cases.size(), checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
