extends "res://scripts/ui/screens/world_screen.gd"
## 外出搜寻（3D 废墟）：提着灯笼走到发光处按 E 翻找，回到门口按 E 回家。对应原版 ExploreMap 的探索副本。

const Inv = preload("res://scripts/core/inv.gd")
const Explore = preload("res://scripts/core/explore.gd")
const Post = preload("res://scripts/core/post.gd")
const Hud = preload("res://scripts/ui/hud_kit.gd")
const RuinWorld = preload("res://scripts/world/ruin_world.gd")
const Player = preload("res://scripts/world/player.gd")
const CamRig = preload("res://scripts/world/cam_rig.gd")
const K = preload("res://scripts/world/kit.gd")
const Neighbor = preload("res://scripts/core/neighbor.gd")
const Mainline = preload("res://scripts/core/mainline.gd")
const InputCfg = preload("res://scripts/core/input_cfg.gd")
const Expedition = preload("res://scripts/core/expedition.gd")
const SiteJourney = preload("res://scripts/core/site_journey.gd")

## 这个界面上弹的窗用夜色（main.gd 看这个）
var dark_ui := true
var player: CharacterBody3D
var rig: Node3D
var _hint: PanelContainer
var _hint_label: Label
var _near := -1
var _near_feature := ""
var _near_journey := ""
var _fleeing := false
var _acc := 0.0
var _clock: Label
var _return_button: Button
var _work_label: Label
var _work_hint := false
var _budget_label: Label


func build_world() -> void:
	var ex: Dictionary = Game.run.explore
	world = RuinWorld.new()
	add_child(world)
	world.setup(ex.point, ex.spots)
	player = Player.new()
	world.add_child(player)
	player.setup(Game.run.role)
	player.figure.step_sound = "step_wood"
	player.position = RuinWorld.ENTRY + Vector3(0, 0, -1.2)
	player.figure.rotation.y = PI
	K.light(player, Color("#ffb36b"), 3.2, 11.0, Vector3(0.3, 1.8, 0.3), true)
	world.player_ref = player
	rig = CamRig.new()
	rig.target = player
	rig.dist = 12.0
	rig.pitch = -56.0
	world.add_child(rig)
	rig.snap()


func build_overlay() -> void:
	_hint_label = UI.label("", 22, UI.INK)
	_hint = UI.panel(_hint_label, Color(UI.PAPER_LIGHT, 0.92))
	add_child(_hint)
	_hint.visible = false


func sync_world() -> void:
	world.sync(Game.run)
	if Game.run.explore.get("caught", false) and not _fleeing:
		_fleeing = true
		rig.shake = 1.0
		get_tree().create_timer(2.4).timeout.connect(finish)


func _process(delta: float) -> void:
	if world == null or Game.run.explore.is_empty():
		return
	var blocked := modal_open()
	if Game.run.explore.get("curfew_due", false) and not Game.run.explore.get("caught", false) and not blocked and not _fleeing and not Post.is_busy(Game.run) and not Post.blocked(Game.run):
		Game.toast.emit("天快黑透了，得赶紧回家！")
		finish()
		return
	# 废墟里时间照走（正常速度），到酉时（21:00）必须回家
	if not blocked and not _fleeing and not Post.blocked(Game.run) and Game.speed > 0:
		_acc += 4.0 * delta
		if _acc >= 1.0:
			var mins := int(_acc)
			_acc -= mins
			var busy_before := Post.is_busy(Game.run)
			var stop := Post.advance(Game.run, mins)
			if busy_before and not Post.is_busy(Game.run):
				Game.refresh()
				if Game.run.explore.is_empty(): return
			if stop == "curfew":
				Game.toast.emit("天快黑透了，得赶紧回家！")
				finish()
				return
			if stop != "":
				Game.refresh()
	if _clock != null:
		_clock.text = "%s  %s" % [Post.shichen(Game.run), Post.clock_text(Game.run)]
	if is_instance_valid(_budget_label):
		_budget_label.text = "距 21:00 还有 %d 分钟 · 返程 %d 分钟" % [maxi(0, Post.CURFEW_AT - Post.day_minute(Game.run)), int(Post.ACTIONS.travel[1])]
	if is_instance_valid(_return_button): _return_button.disabled = Post.is_busy(Game.run)
	if is_instance_valid(_work_label):
		_work_label.visible = Post.is_busy(Game.run)
		if Post.is_busy(Game.run): _work_label.text = "%s中 · 还需 %d 分钟" % [str(Game.run.busy.get("label", "调查")), maxi(0, int(Game.run.busy.get("end", 0)) - int(Game.run.t))]
	player.enabled = not blocked
	rig.input_enabled = not blocked
	player.cam_yaw = rig.yaw
	var feature: String = "" if blocked else world.nearest_feature(player.global_position)
	var journey: String = "" if blocked or feature != "" else world.nearest_journey(player.global_position)
	var near: int = -1 if blocked or feature != "" or journey != "" else world.nearest(player.global_position)
	if near != _near or feature != _near_feature or journey != _near_journey or Post.is_busy(Game.run) or _work_hint:
		_near = near
		_near_feature = feature
		_near_journey = journey
		_update_hint()
		_work_hint = Post.is_busy(Game.run)


func _update_hint() -> void:
	var ex: Dictionary = Game.run.explore
	if Post.is_busy(Game.run) and Game.run.busy.get("kind", "") == "mainline":
		_hint.visible = true
		_hint_label.text = "%s中 · 还需 %d 分钟；完成后才能继续翻找或返程。" % [str(Game.run.busy.get("label", "调查")), maxi(0, int(Game.run.busy.get("end", 0)) - int(Game.run.t))]
		_hint.reset_size()
		_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 70)
		return
	_hint.visible = _near != -1 or _near_feature != "" or _near_journey != ""
	# 键位提示读 InputMap：玩家改过 interact 就显示新键，不写死 [E]
	var ek := InputCfg.first_key_name("interact")
	if _near_feature != "":
		var profile: Dictionary = Expedition.profile(str(ex.point))
		var progress: Dictionary = Expedition.state(Game.run)
		if _near_feature == "gate":
			_hint_label.text = "[%s] %s" % [ek, "查看通路" if progress.get("unlocked", false) else "查看机关 · 答题耗时 %d 分钟" % int(profile.get("answer_minutes", 0))]
		else:
			var idx := int(_near_feature.trim_prefix("clue_"))
			var found: Array = progress.get("clues", [])
			var known := idx >= 0 and idx < found.size() and bool(found[idx])
			_hint_label.text = "[%s] %s" % [ek, "回看线索" if known else "查探线索 · 耗时 %d 分钟" % int(profile.get("inspect_minutes", 0))]
	elif _near_journey != "":
		var stage := _journey_stage(_near_journey)
		var done: bool = SiteJourney.state(Game.run).get("completed", {}).has(_near_journey)
		_hint_label.text = "[%s] %s · %s" % [ek, "回看现场" if done else "查看现场行动", str(stage.get("title", "探索"))]
	elif _near == -2:
		_hint_label.text = "[%s] 回家（背着 %.1f 斤）" % [ek, Inv.weight(ex.bag)]
	elif _near >= 0 and _near < ex.spots.size():
		var s: Dictionary = ex.spots[_near]
		if s.done and not s.has("mainline") and not s.has("neighbor"):
			_hint_label.text = "[%s] 查看 · %s（可整理背囊）" % [ek, s.name]
		else:
			var verb := "调查" if s.has("mainline") or s.has("neighbor") else "查看选择"
			if not s.has("mainline") and not s.has("neighbor"):
				verb = "特色行动" if Explore.site_options(Game.run, _near).size() > 1 else "翻找"
			_hint_label.text = "[%s] %s · %s" % [ek, verb, s.name] if not s.done else "%s · 已经查过了" % s.name
	_hint.reset_size()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 70)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or modal_open():
		return
	# 翻找 = interact（E）或 confirm（空格），走输入动作，改键不用动这里
	if event.is_action_pressed("interact") or event.is_action_pressed("confirm"):
		if _near_feature != "":
			_interact_feature(_near_feature)
		elif _near_journey != "":
			_open_journey(_near_journey)
		elif _near == -2:
			finish()
		elif _near >= 0:
			search(_near)


func _feature_blocked() -> bool:
	var ex: Dictionary = Game.run.get("explore", {})
	return ex.is_empty() or ex.get("caught", false) or ex.get("curfew_due", false) or Post.is_busy(Game.run) or Post.blocked(Game.run) or modal_open()


func _interact_feature(feature: String) -> void:
	if _feature_blocked(): return
	if feature == "gate":
		_open_expedition("gate")
		return
	if not feature in ["clue_0", "clue_1"]: return
	var idx := int(feature.trim_prefix("clue_"))
	var progress: Dictionary = Expedition.state(Game.run)
	var found: Array = progress.get("clues", [])
	if idx >= found.size() or not bool(found[idx]):
		var res: Dictionary = Game.act(func(): return Post.expedition_inspect(Game.run, idx))
		if str(res.get("blocked", "")) != "":
			Game.toast.emit(str(res.blocked))
			return
		if str(res.get("text", "")) != "": Game.toast.emit(str(res.text))
		if _feature_blocked() or not is_inside_tree() or Game.screen != "explore": return
	_open_expedition("clue", idx)


func _open_expedition(mode: String, idx := -1) -> void:
	if _feature_blocked(): return
	var ex: Dictionary = Game.run.get("explore", {})
	var profile: Dictionary = Expedition.profile(str(ex.point))
	UI.open_modal("expedition", str(profile.get("title", "探索")), _expedition_panel.bind(mode, idx), true, 760)


func _expedition_panel(body: VBoxContainer, mode: String, idx: int) -> void:
	var ex: Dictionary = Game.run.get("explore", {})
	if ex.is_empty():
		body.add_child(UI.label("已离开此处。", 17))
		return
	var profile: Dictionary = Expedition.profile(str(ex.point))
	var progress: Dictionary = Expedition.state(Game.run)
	var clues: Array = profile.get("clues", [])
	var found: Array = progress.get("clues", [])
	var contents := UI.vbox(7)
	for i in clues.size():
		if mode == "clue" and i != idx: continue
		if i < found.size() and bool(found[i]):
			contents.add_child(UI.heading(str(clues[i].get("title", "线索")), 19, UI.GOLD))
			contents.add_child(UI.para(str(clues[i].get("text", "")), 16))
		elif mode != "clue":
			contents.add_child(UI.para("线索 %d：尚未查探。" % (i + 1), 16, UI.INK_SOFT))
	if mode == "gate":
		contents.add_child(UI.para("线索和通路仅保留本次外出，回家后重置。", 15, UI.INK_SOFT))
		if ex.get("only_investigate", false):
			contents.add_child(UI.para("这里的东西还没缓过来，这一趟只为查访，机关后面也翻不出物资；要查的地方不受机关阻拦。", 16, UI.GOLD))
		if progress.get("unlocked", false):
			contents.add_child(UI.para("通路已打开。", 17, UI.GOLD))
		else:
			contents.add_child(UI.heading(str(profile.get("question", "")), 19, UI.GOLD))
			contents.add_child(UI.para("每次尝试耗时 %d 分钟；选错阳气外泄最多增加 %d。" % [int(profile.get("answer_minutes", 0)), int(profile.get("wrong_exposure", 0))], 16))
			var ready := found.size() >= 2 and bool(found[0]) and bool(found[1])
			if not ready: contents.add_child(UI.para("先在现场找到两条线索。", 16, UI.CINNABAR))
			for choice in profile.get("choices", []):
				var b := UI.button(str(choice.get("text", "")), _answer_expedition.bind(str(choice.get("id", ""))), not ready)
				b.set_meta("expedition_choice", str(choice.get("id", "")))
				contents.add_child(b)
	body.add_child(UI.scroll(contents, mini(370, maxi(160, int(get_viewport().get_visible_rect().size.y) - 300))))
	body.add_child(UI.button("先离开", func(): UI.close_modal("expedition")))


func _answer_expedition(id: String) -> void:
	UI.close_modal("expedition")
	if _feature_blocked(): return
	var res: Dictionary = Game.act(func(): return Post.expedition_answer(Game.run, id))
	var message := str(res.get("blocked", ""))
	if message == "": message = str(res.get("text", ""))
	if message != "": Game.toast.emit(message)
	_near_feature = ""


func _journey_stage(id: String) -> Dictionary:
	var ex: Dictionary = Game.run.get("explore", {})
	for stage in SiteJourney.profile(str(ex.get("point", ""))).get("stages", []):
		if str(stage.get("id", "")) == id: return stage
	return {}


func _open_journey(id: String) -> void:
	if _feature_blocked() or Game.run.explore.get("only_investigate", false): return
	var stage := _journey_stage(id)
	if stage.is_empty(): return
	UI.open_modal("site_journey", str(stage.title), _journey_panel.bind(id), true, 760)


func _journey_panel(body: VBoxContainer, id: String) -> void:
	var ex: Dictionary = Game.run.get("explore", {})
	var stage := _journey_stage(id)
	if ex.is_empty() or stage.is_empty():
		body.add_child(UI.label("已离开此处。", 17))
		return
	var s: Dictionary = SiteJourney.state(Game.run)
	var completed: Dictionary = s.get("completed", {})
	var contents := UI.vbox(6)
	contents.add_child(UI.para(str(stage.text), 17))
	if not completed.has(id):
		contents.add_child(UI.para("距 21:00 还有 %d 分钟；返程另需 %d 分钟。时间不足或途中遇事可能中断行动。" % [maxi(0, Post.CURFEW_AT - Post.day_minute(Game.run)), int(Post.ACTIONS.travel[1])], 15, UI.INK_SOFT))
		contents.add_child(UI.para("本次到访此处只能选择一种处理方式，完成后不可改选；取消不消耗时间。", 15, UI.GOLD))
		for choice in stage.get("choices", []):
			var button := UI.button(str(choice.text), _choose_journey.bind(id, str(choice.id)))
			button.set_meta("journey_choice", str(choice.id))
			contents.add_child(button)
			contents.add_child(UI.para(str(choice.description), 15))
	else:
		contents.add_child(UI.para("此处已完成，本次到访不能改选处理方式。", 15, UI.INK_SOFT))
		for choice in stage.get("choices", []):
			if str(choice.id) == str(completed[id]):
				contents.add_child(UI.para("已处理：" + str(choice.text), 17, UI.GOLD))
				break
		var caches: Dictionary = s.get("caches", {})
		if caches.has(id):
			var cache: Dictionary = caches[id]
			var bag: Dictionary = ex.get("bag", {})
			contents.add_child(UI.label("背囊 %.1f / %.1f 斤" % [Inv.weight(bag), Explore.carry(Game.run)], 17, UI.GOLD))
			contents.add_child(UI.para("现场物资本次回家后不能带回；可在此取物或放回背囊物资。", 15))
			contents.add_child(UI.heading("此处物资", 18, UI.GOLD))
			if cache.is_empty(): contents.add_child(UI.label("这里已经空了。", 15))
			for raw_id in cache.keys():
				var item := str(raw_id)
				var row := UI.hbox(8)
				row.add_child(UI.label("%s ×%d · 每件 %.1f 斤" % [Data.item(item).name, Inv.count(cache, item), float(Data.item(item).get("weight", 0))], 16))
				row.add_child(UI.spacer())
				var take := UI.button("取 1", _journey_transfer.bind(id, item, true))
				take.set_meta("journey_take", item)
				row.add_child(take)
				contents.add_child(row)
			contents.add_child(UI.heading("背囊 · 放回此处", 18, UI.GOLD))
			if bag.is_empty(): contents.add_child(UI.label("背囊是空的。", 15))
			for raw_id in bag.keys():
				var item := str(raw_id)
				var row := UI.hbox(8)
				row.add_child(UI.label("%s ×%d" % [Data.item(item).name, Inv.count(bag, item)], 16))
				row.add_child(UI.spacer())
				var put := UI.button("放回 1", _journey_transfer.bind(id, item, false))
				put.set_meta("journey_put", item)
				row.add_child(put)
				contents.add_child(row)
		else:
			contents.add_child(UI.para("这次处理没有留存现场物资。", 15))
	body.add_child(UI.scroll(contents, mini(380, maxi(160, int(get_viewport().get_visible_rect().size.y) - 300))))
	body.add_child(UI.button("先离开", func(): UI.close_modal("site_journey")))


func _choose_journey(id: String, choice: String) -> void:
	UI.close_modal("site_journey")
	if _feature_blocked(): return
	var result: Dictionary = Game.act(func(): return Post.site_journey_action(Game.run, id, choice))
	var message := str(result.get("blocked", result.get("text", "")))
	if message != "": Game.toast.emit(message)
	if not is_inside_tree() or Game.screen != "explore" or _feature_blocked(): return
	_open_journey(id)


func _journey_transfer(id: String, item: String, take: bool) -> void:
	var amount: int = Game.act(func(): return Post.site_journey_take(Game.run, id, item, 1) if take else Post.site_journey_put_back(Game.run, id, item, 1))
	Game.toast.emit(("取走" if take else "放回") + " %s ×%d" % [Data.item(item).name, amount] if amount > 0 else "当前无法转移这件物资。")


## 翻一处（测试也走这里）。
func search(idx: int) -> void:
	var ex: Dictionary = Game.run.explore
	if Post.is_busy(Game.run):
		Game.toast.emit("先完成眼前的工作，不能同时翻找另一处。")
		return
	if ex.is_empty() or ex.caught or idx < 0 or idx >= ex.spots.size():
		return
	var spot: Dictionary = ex.spots[idx]
	if spot.done:
		if not spot.has("mainline") and not spot.has("neighbor"):
			_open_loot(idx)
		return
	if not spot.has("mainline") and not spot.has("neighbor"):
		if Explore.site_options(Game.run, idx).size() > 1:
			_open_site_options(idx)
		else:
			_execute_search(idx, "normal")
		return
	_execute_search(idx, "")


## 先让玩家看清收益与代价。关闭或按 Esc 不会开始搜寻。
func _open_site_options(idx: int) -> void:
	var ex: Dictionary = Game.run.get("explore", {})
	if ex.is_empty() or idx < 0 or idx >= ex.spots.size(): return
	UI.open_modal("explore_options", "查看 · " + str(ex.spots[idx].name), _site_options_panel.bind(idx), true, 760)


func _site_options_panel(body: VBoxContainer, idx: int) -> void:
	var ex: Dictionary = Game.run.get("explore", {})
	if ex.is_empty() or idx < 0 or idx >= ex.spots.size():
		body.add_child(UI.label("已离开此处。", 17))
		return
	var p: Dictionary = Data.table("map_points")[ex.point]
	body.add_child(UI.para(str(p.desc), 16))
	body.add_child(UI.para("选择如何处理这里；合上或按 Esc 可先离开，不消耗时间。", 16, UI.GOLD))
	var choices := UI.vbox(8)
	var options: Array = Explore.site_options(Game.run, idx)
	for option in options:
		var id := str(option.get("id", ""))
		var block := str(option.get("block", ""))
		var group := UI.vbox(3)
		var b := UI.button(str(option.get("title", "查看")), _choose_site_option.bind(idx, id), block != "")
		b.focus_mode = Control.FOCUS_ALL
		b.set_meta("explore_option", id)
		group.add_child(b)
		group.add_child(UI.para(str(option.get("description", "")), 16))
		if block != "": group.add_child(UI.para(block, 15, UI.CINNABAR))
		choices.add_child(group)
	if options.is_empty():
		choices.add_child(UI.label("眼下没有可进行的行动。", 16))
	body.add_child(UI.scroll(choices, mini(240, maxi(150, int(get_viewport().get_visible_rect().size.y) - 300))))
	var cancel := UI.button("先离开", func(): UI.close_modal("explore_options"))
	cancel.focus_mode = Control.FOCUS_ALL
	body.add_child(cancel)


func _choose_site_option(idx: int, option_id: String) -> void:
	UI.close_modal("explore_options")
	_execute_search(idx, option_id)


func _execute_search(idx: int, option_id: String) -> void:
	var field: Dictionary = Game.run.get("explore", {})
	var offering: bool = option_id == "site" and field.get("point", "") == "city_god"
	var mood_before := State.attr(Game.run, "mood") if offering else 0
	var exposure_before := int(field.get("exposure", 0))
	var res = Game.act(func(): return Post.search(Game.run, idx, option_id))
	if typeof(res) == TYPE_DICTIONARY and not res.is_empty():
		if str(res.get("blocked", "")) != "":
			Game.toast.emit(str(res.blocked))
			return
		if res.get("mainline", false):
			Game.toast.emit(str(res.get("text", "已开始调查，完成后再返程。")))
			_near = -99
			return
		if res.get("story", false):
			Game.toast.emit("已检视封存药柜，请选择开锁方式。" if Game.run.pending_event == "n_cabinet" else "药账已贴身收好，回宅决定去向。")
			_near = -99
			return
		if offering:
			# 心情可能受上限及耗时影响；显示真实结算值，不虚报固定收益。
			Game.toast.emit("留下供物 · 心神 %d → %d（含耗时变化） · 阳气外泄 %d → %d" % [mood_before, State.attr(Game.run, "mood"), exposure_before, int(field.get("exposure", 0))])
			_near = -99
			return
		Sfx.play("cloth" if res.found.is_empty() else "leather", -2.0)
		var text := "发现：" + Data.describe_items(res.found) if not res.found.is_empty() else "一无所获"
		Game.toast.emit(text)
		if res.clue != "":
			Game.toast.emit("得残卷一页！")
		# 翻找本身会推进时间，可能已经触发事件、死亡或宵禁。
		var current: Dictionary = Game.run.get("explore", {})
		if not is_inside_tree() or Game.screen != "explore" or Game.run.get("phase", "") != "post" or current.is_empty():
			return
		if not current.get("caught", false) and not current.get("curfew_due", false) and not Post.blocked(Game.run) and not modal_open():
			_open_loot(idx)
	_near = -99


## 搜过的普通容器始终可以重开；遗留物只在这次探索中保留。
func _open_loot(idx: int) -> void:
	var ex: Dictionary = Game.run.get("explore", {})
	if not is_inside_tree() or Game.screen != "explore" or ex.is_empty() or ex.get("caught", false) or ex.get("curfew_due", false) or Post.is_busy(Game.run) or Post.blocked(Game.run) or idx < 0 or idx >= ex.spots.size(): return
	var spot: Dictionary = ex.spots[idx]
	if not spot.done or spot.has("mainline") or spot.has("neighbor"): return
	UI.open_modal("explore_loot", "搜寻 · " + str(spot.name), _loot_panel.bind(idx), true, 760)


func _loot_panel(body: VBoxContainer, idx: int) -> void:
	var ex: Dictionary = Game.run.get("explore", {})
	if ex.is_empty() or ex.get("caught", false) or idx < 0 or idx >= ex.spots.size():
		body.add_child(UI.label("已离开此处，无法取物。", 17))
		return
	var spot: Dictionary = ex.spots[idx]
	var loot: Dictionary = spot.get("loot", {})
	var bag: Dictionary = ex.get("bag", {})
	var left := maxf(0.0, Explore.carry(Game.run) - Inv.weight(bag))
	body.add_child(UI.label("背囊 %.1f / %.1f 斤 · 还能装 %.1f 斤" % [Inv.weight(bag), Explore.carry(Game.run), left], 19, UI.GOLD))
	body.add_child(UI.para("取物不消耗时间。未拿走的物资会留在此处，本次返家后无法带回；可将背囊物资放回这里，腾出位置。", 15))
	var contents := UI.vbox(6)
	contents.add_child(UI.heading("此处物资", 20, UI.GOLD))
	if loot.is_empty():
		contents.add_child(UI.label("这里已经空了。", 16, UI.INK_SOFT))
	for raw_id in loot.keys():
		var id := str(raw_id)
		var item: Dictionary = Data.item(id)
		var row := UI.hbox(8)
		row.add_child(UI.label("%s ×%d · 每件 %.1f 斤" % [item.name, Inv.count(loot, id), float(item.get("weight", 0))], 17))
		row.add_child(UI.spacer())
		row.add_child(UI.button("取 1", func(): _take_loot(idx, id, 1)))
		row.add_child(UI.button("尽量取", func(): _take_loot(idx, id, Inv.count(loot, id))))
		contents.add_child(row)
	contents.add_child(UI.sep())
	contents.add_child(UI.heading("背囊 · 放回此处", 20, UI.GOLD))
	if bag.is_empty():
		contents.add_child(UI.label("背囊是空的。", 16, UI.INK_SOFT))
	for raw_id in bag.keys():
		var id := str(raw_id)
		var item: Dictionary = Data.item(id)
		var row := UI.hbox(8)
		row.add_child(UI.label("%s ×%d · 每件 %.1f 斤" % [item.name, Inv.count(bag, id), float(item.get("weight", 0))], 17))
		row.add_child(UI.spacer())
		row.add_child(UI.button("放回 1", func(): _put_back(idx, id, 1)))
		row.add_child(UI.button("全部放回", func(): _put_back(idx, id, Inv.count(bag, id))))
		contents.add_child(row)
	body.add_child(UI.scroll(contents, mini(400, maxi(180, int(get_viewport().get_visible_rect().size.y) - 320))))


func _take_loot(idx: int, id: String, amount: int) -> void:
	var n := int(Game.act(func(): return Explore.take(Game.run, idx, id, amount)))
	Game.toast.emit("取走 %s ×%d" % [Data.item(id).name, n] if n > 0 else "背囊空间不足，或此处已没有这件物资。")


func _put_back(idx: int, id: String, amount: int) -> void:
	var n := int(Game.act(func(): return Explore.put_back(Game.run, idx, id, amount)))
	Game.toast.emit("放回 %s ×%d" % [Data.item(id).name, n] if n > 0 else "此时无法放回物资。")


func finish() -> void:
	if Game.run.explore.is_empty():
		return
	if Post.is_busy(Game.run):
		Game.toast.emit("先完成眼前的工作；尚未完工的调查不能带回证据。")
		return
	Sfx.play("door_close", -3.0)
	Game.act(func(): return Post.finish_explore(Game.run))


# ---------- HUD ----------

func build_hud() -> void:
	var run: Dictionary = Game.run
	var ex: Dictionary = run.explore
	if ex.is_empty():
		return
	var p: Dictionary = Data.table("map_points")[ex.point]
	var v := UI.vbox(4)
	v.add_child(UI.heading(p.name, 26))
	v.add_child(UI.wrap_line(p.desc, 15, UI.INK_SOFT, 300))
	if not ex.get("only_investigate", false):
		var journey_profile: Dictionary = SiteJourney.profile(str(ex.point))
		var grades := {"easy": "简单", "medium": "中等", "hard": "困难"}
		var done: Dictionary = SiteJourney.state(run).get("completed", {})
		v.add_child(UI.label("%s路线 · 完整现场约%s（游戏时间）" % [grades.get(str(journey_profile.get("grade", "")), "探索"), str(journey_profile.get("estimated", ""))], 15, UI.GOLD))
		v.add_child(UI.label("含走动、机关与翻找；不含返程", 14, UI.INK_SOFT))
		v.add_child(UI.label("耗时为参考，随选择与走动变化", 14, UI.INK_SOFT))
		v.add_child(UI.label("现场行动 %d / %d 处" % [done.size(), journey_profile.get("stages", []).size()], 15, UI.INK_SOFT))
	_budget_label = UI.label("距 21:00 还有 %d 分钟 · 返程 %d 分钟" % [maxi(0, Post.CURFEW_AT - Post.day_minute(run)), int(Post.ACTIONS.travel[1])], 15, UI.INK_SOFT)
	v.add_child(_budget_label)
	var profile: Dictionary = Expedition.profile(str(ex.point))
	var progress: Dictionary = Expedition.state(run)
	var found: Array = progress.get("clues", [])
	var clue_count := 0
	for known in found:
		if bool(known): clue_count += 1
	v.add_child(UI.wrap_line("探索 · %s：线索 %d/%d · %s" % [str(profile.get("title", "现场")), clue_count, profile.get("clues", []).size(), "通路已开" if progress.get("unlocked", false) else "通路待解"], 15, UI.GOLD, 300))
	var journal := UI.button("查看已发现线索", func(): _open_expedition("journal"))
	journal.set_meta("expedition_journal", true)
	v.add_child(journal)
	v.add_child(UI.stat_row("气血", State.attr(run, "hp"), State.attr_max(run, "hp"), UI.CINNABAR, 44))
	v.add_child(UI.stat_row("精力", State.attr(run, "energy"), 100, UI.INK_SOFT, 44))
	v.add_child(UI.label("背囊 %.1f / %d 斤" % [Inv.weight(ex.bag), int(Explore.carry(run))], 16))
	var ordinary := 0
	var searched := 0
	var site_target := ""
	for i in ex.spots.size():
		var spot: Dictionary = ex.spots[i]
		if spot.has("mainline") or spot.has("neighbor"): continue
		ordinary += 1
		if spot.done: searched += 1
		elif Explore.site_options(run, i).size() > 1: site_target = str(spot.name)
	if ex.get("only_investigate", false):
		v.add_child(UI.wrap_line("专程查访 · 这里暂时翻不出物资，要查的地方照样能查。", 15, UI.GOLD, 300))
		v.add_child(UI.label("返程需 %d 分钟" % int(Post.ACTIONS.travel[1]), 15, UI.INK_SOFT))
	else:
		v.add_child(UI.label("搜寻 %d / %d 处 · 返程需 %d 分钟" % [searched, ordinary, int(Post.ACTIONS.travel[1])], 15, UI.INK_SOFT))
	if site_target != "": v.add_child(UI.label("特色行动：" + site_target, 15, UI.GOLD))
	v.add_child(UI.wrap_line("带着：" + (Data.describe_items(ex.bag) if not ex.bag.is_empty() else "空手"), 15, UI.INK_SOFT, 300))
	v.add_child(UI.wrap_line(Neighbor.summary(run), 16, UI.INK_SOFT, 300))
	if Neighbor.state(run).stage in ["fetch", "carrying"]:
		v.add_child(UI.label("送药截止：第 4 日 18:00（含返程）", 15, UI.GOLD))
	if Neighbor.state(run).medicine:
		v.add_child(UI.label("贴身药包 ×1 · 不占背囊", 16, UI.GOLD))
	var objective := Mainline.objective(run, str(ex.point))
	v.add_child(UI.wrap_line(Mainline.summary(run), 15, UI.GOLD, 300))
	if not objective.is_empty():
		v.add_child(UI.wrap_line("要查的：" + str(objective.name), 15, UI.GOLD, 300))
	_work_label = UI.label("", 15, UI.GOLD)
	v.add_child(_work_label)
	corner_panel(v, Control.PRESET_TOP_LEFT)

	var e := UI.vbox(4)
	var row := UI.hbox(10)
	row.add_child(UI.label("阳气外泄", 20, UI.CINNABAR))
	row.add_child(UI.bar(int(ex.exposure), Explore.EXPOSURE_MAX, UI.CINNABAR, 360, 20))
	row.add_child(UI.label("%d / %d" % [ex.exposure, Explore.EXPOSURE_MAX], 18))
	e.add_child(row)
	var risk := Explore.exposure_range(run, str(ex.point))
	var tip := "被尸群嗅到了！快逃！" if ex.caught else "翻找基础外泄 +%d～%d；具体行动耗时与风险见现场选择。21:00 后返程需 %d 分钟。" % [risk.x, risk.y, int(Post.ACTIONS.travel[1])]
	e.add_child(UI.label(tip, 15, UI.CINNABAR if ex.caught else UI.INK_SOFT))
	corner_panel(e, Control.PRESET_CENTER_TOP, 14, 0.9)

	var top := UI.hbox(6)
	_clock = Hud.text("%s  %s" % [Post.shichen(run), Post.clock_text(run)], 22, Hud.CYAN, true)
	top.add_child(_clock)
	_return_button = UI.seal_button("逃回家" if ex.caught else "回家", finish)
	_return_button.set_meta("mainline_return", true)
	_return_button.disabled = Post.is_busy(run)
	top.add_child(_return_button)
	top.add_child(UI.button("劫余录", Dialogs.journal))
	corner_panel(top, Control.PRESET_TOP_RIGHT)
	corner_panel(UI.log_lines(ex.notes, 4, 15, 560), Control.PRESET_BOTTOM_LEFT, 14, 0.8)
	var help := UI.label("WASD 走动 · %s 翻找 / 查看 / 回家 · 右键拖动转视角" % InputCfg.first_key_name("interact"), 15, Color(UI.PAPER_LIGHT, 0.95))
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	help.add_theme_constant_override("outline_size", 4)
	hud.add_child(help)
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN


## 废墟里也可能碰上早上的事件。
func after_build() -> void:
	if Game.run.phase == "post" and Game.run.pending_event != "" and not UI.has_modal("event"):
		Dialogs.event()
