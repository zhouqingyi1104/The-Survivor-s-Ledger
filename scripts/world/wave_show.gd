extends Node3D
## 入夜演出。结果已经由 Post.night 算好（报告在 run.report），这里只负责把它演出来：
## 僵尸从街两头蹦过来，该斩的在守具前闪光倒下，剩下的扑到门窗上砸，门破了就蹦进院子。

signal finished

const K = preload("res://scripts/world/kit.gd")
const Figure = preload("res://scripts/world/character.gd")

const GATE := Vector3(0, 0, 7.9)
const WINDOW := Vector3(5.6, 0, 7.9)
const KILL_RADIUS := 4.2

var _world: Node3D
var _rig: Node3D
var _t := 0.0
var _dur := 3.0
var _actors := []
var _effects := []
var _breach_at := -1.0
var _breached := false
var _done := false
var _player_pos := Vector3.ZERO
var _groan_in := 0.8
var _bell_rung := false
var banner := ""


## report：本夜战报；before：入夜前的局面（演出期间宅院按它画，演完再画结果）。
func play(world: Node3D, rig: Node3D, report: Dictionary, player_pos: Vector3) -> void:
	_world = world
	_rig = rig
	_player_pos = player_pos
	var wave: Dictionary = report.get("wave", {})
	var blood: bool = wave.get("name", "").contains("血月")
	world.set_preset("blood" if blood else "night", 900)
	if wave.is_empty():
		_dur = 3.2
		banner = "一夜无事" if not report.has("raid") else "溃兵砸了半夜的门"
		rig.goto(Vector3(9, 8, 16), Vector3(0, 1.5, 0))
		return
	banner = "尸潮%s · 来 %d 只" % [("（" + wave.name + "）") if wave.name != "" else "", wave.count]
	rig.goto(Vector3(0, 13.5, 15.2), Vector3(0, 0.5, 8.0))
	var visual := clampi(int(wave.count), 4, 30)
	var killed := int(round(visual * float(wave.killed) / maxf(1.0, float(wave.count))))
	var win_share := 0.65 if wave.name.contains("夹击") else 0.35
	var rng := RandomNumberGenerator.new()
	rng.seed = int(wave.count) * 31 + int(wave.killed)
	for k in visual:
		var side := -1.0 if k % 2 == 0 else 1.0
		var start := Vector3(side * rng.randf_range(13, 19), 0, rng.randf_range(9.6, 12.8))
		var target := WINDOW if rng.randf() < win_share else GATE
		target += Vector3(rng.randf_range(-0.9, 0.9), 0, rng.randf_range(0.0, 0.6))
		var fig: Node3D = Figure.new()
		add_child(fig)
		fig.setup("jiangshi")
		fig.position = start
		fig.hopping = false
		fig.speed_scale = rng.randf_range(0.9, 1.2)
		_actors.append({
			"fig": fig, "target": target, "spawn": rng.randf_range(0.0, 5.0), "speed": rng.randf_range(1.9, 2.6),
			"die": k < killed, "die_d": rng.randf_range(1.2, KILL_RADIUS), "state": "wait", "timer": 0.0,
		})
	_breached = bool(wave.get("breached", false)) or int(wave.get("hp_loss", 0)) > 0
	_dur = 13.0
	if _breached:
		_breach_at = 9.5


func skip() -> void:
	_finish()


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	for a in _actors:
		_step(a, delta)
	_sounds(delta)
	for e in _effects.duplicate():
		e.t += delta
		var l: OmniLight3D = e.light
		l.light_energy = maxf(0.0, 6.0 * (1.0 - e.t / 0.5))
		(e.orb as Node3D).scale = Vector3.ONE * (1.0 + e.t * 3.0)
		if e.t > 0.5:
			(e.node as Node3D).queue_free()
			_effects.erase(e)
	if _breach_at > 0.0 and _t >= _breach_at:
		_breach_at = -1.0
		_break_in()
	if _t >= _dur:
		_finish()


func _step(a: Dictionary, delta: float) -> void:
	var fig: Node3D = a.fig
	match a.state:
		"wait":
			fig.visible = _t >= a.spawn
			if _t >= a.spawn:
				a.state = "hop"
				fig.hopping = true
		"hop":
			var to: Vector3 = a.target - fig.position
			to.y = 0
			var d := to.length()
			if a.die and d <= a.die_d:
				_kill(a)
				return
			if d < 0.3:
				a.state = "pound"
				fig.hopping = false
				return
			fig.position += to.normalized() * minf(d, a.speed * delta)
			fig.face(to, 1.0)
		"pound":
			a.timer += delta
			fig.position.z = a.target.z + sin(a.timer * 9.0) * 0.12
			if fmod(a.timer, 1.1) < delta:
				_rig.shake = maxf(_rig.shake, 0.35)
				Sfx.play_at("hit_door", fig.position + Vector3(0, 1.2, 0), self, 2.0)
		"inside":
			var to: Vector3 = _player_pos - fig.position
			to.y = 0
			if to.length() > 1.1:
				fig.position += to.normalized() * a.speed * delta
				fig.face(to, 1.0)
		"dead":
			a.timer += delta
			if a.timer > 1.4:
				fig.position.y -= delta * 0.8
			if a.timer > 2.6:
				fig.visible = false


func _kill(a: Dictionary) -> void:
	var fig: Node3D = a.fig
	a.state = "dead"
	a.timer = 0.0
	fig.fall()
	Sfx.play_at("hit_soft", fig.position, self, 0.0)
	Sfx.play_at("ling", fig.position + Vector3(0, 1.0, 0), self, -10.0, 0.15)
	var n := K.node(self, fig.position + Vector3(0, 1.0, 0))
	var orb := K.sphere(n, 0.35, K.mat(Color("#ffd36b"), 0.5, 4.0, 0.6), Vector3.ZERO)
	var l := K.light(n, Color("#ffd36b"), 6.0, 6.0, Vector3.ZERO)
	_effects.append({"node": n, "orb": orb, "light": l, "t": 0.0})


## 门窗破了：几只蹦进院子，镜头一震。
func _break_in() -> void:
	_rig.shake = 1.0
	Sfx.play("hit_plank", 2.0)
	Sfx.play("creak", 0.0)
	Sfx.play("punch", 0.0)
	_rig.goto(Vector3(0, 10, 14), Vector3(0, 0.5, 3))
	var n := 0
	for a in _actors:
		if a.state == "pound" and n < 3:
			a.state = "inside"
			a.fig.position = Vector3(randf_range(-0.8, 0.8), 0, 6.2)
			a.fig.hopping = true
			n += 1


## 蹦过来的路上一阵阵低吼；头一只露面时远处一声赶尸铃。
func _sounds(delta: float) -> void:
	var alive := []
	for a in _actors:
		if a.state in ["hop", "pound", "inside"]:
			alive.append(a)
	if alive.is_empty():
		return
	if not _bell_rung:
		_bell_rung = true
		Sfx.play("ling", -6.0, 0.0)
	_groan_in -= delta
	if _groan_in <= 0.0:
		_groan_in = randf_range(0.35, 0.9) * (6.0 / (alive.size() + 4.0))
		var a: Dictionary = alive[randi() % alive.size()]
		Sfx.play_at("zombie", (a.fig as Node3D).position + Vector3(0, 1.6, 0), self, -2.0, 0.12)


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit()
