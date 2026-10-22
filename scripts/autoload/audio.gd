extends Node
## 声音（自动加载为 Sfx）：音效、环境声、配乐，各走一条总线，音量存在 meta.settings 里。
##   play(名字)         —— 界面 / 动作音效，同名多份随机挑一份，音高略变
##   play_at(名字, 位置) —— 3D 场景里的定位音效（尸潮演出的砸门、低吼）
##   strikes(名字列表)   —— 一串间隔敲下去（打更：先一声更鼓，再按更数敲梆子）
##   ambience(名字, 音量) / music(名字) —— 循环的环境声 / 配乐，切换时淡入淡出
## 素材来源和许可证见 docs/03-art-assets.md；中式的梆子、更鼓、赶尸铃、铜锣、风雪是 tools/pipeline/synth_sfx.py 合成的。
## 文件由 tools/pipeline/build_audio.py 生成，同名多份按 _1 _2 … 编号，份数记在 VARIANTS。

const SFX := "res://assets/audio/sfx/%s.ogg"
const AMB := "res://assets/audio/amb/%s.ogg"
const MUSIC := "res://assets/audio/music/%s.ogg"
const VARIANTS := {
	"ui_click": 2, "ui_open": 1, "ui_close": 1, "ui_error": 1, "ui_confirm": 1, "ui_tick": 1,
	"coins": 2, "book": 3, "book_place": 3, "door_open": 2, "door_close": 4, "creak": 3, "pot": 3, "knife": 2,
	"chop": 1, "cloth": 4, "leather": 3, "latch": 1, "step_snow": 5, "step_stone": 5, "step_wood": 5,
	"hit_door": 5, "hammer": 5, "hit_plank": 5, "hit_soft": 5, "dig": 5, "punch": 5, "bell": 5,
	"zombie": 24, "gust": 3, "bangzi": 1, "genggu": 1, "ling": 1, "luo": 1, "water_draw": 1, "sip": 1,
}
const BUSES := {"music": "Music", "sfx": "Sfx", "amb": "Ambience"}
const DEFAULT_VOLUME := {"music": 0.7, "sfx": 0.85, "amb": 0.8}
const POOL := 12

var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _streams := {}
var _music: Array[AudioStreamPlayer] = []
var _music_name := ""
var _music_db := 0.0
var _amb := {}
var _tweens := {}
var _last_click := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key in BUSES:
		if AudioServer.get_bus_index(BUSES[key]) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, BUSES[key])
			AudioServer.set_bus_send(i, "Master")
	for k in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Sfx"
		add_child(p)
		_pool.append(p)
	for k in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		add_child(m)
		_music.append(m)
	apply_volumes()
	# 所有按钮按下都"嗒"一声
	get_tree().node_added.connect(_on_node_added)
	Game.screen_changed.connect(_on_screen)
	_on_screen.call_deferred(Game.screen)


## 换界面时的配乐和环境声。宅院（post）的昼夜由 post_screen 自己管。
func _on_screen(screen: String) -> void:
	match screen:
		"title", "roles", "talents", "ending":
			music("lotus_pond", -4.0)
			ambience_off()
		"pre":
			music("lotus_pond", -11.0)
			ambience("wind_loop", -17.0)
			ambience("fire_loop", null)
		"explore":
			music("")
			ambience("wind_loop", -9.0)
			ambience("fire_loop", null)
		"dead":
			music("")
			ambience_off()
			strikes(["genggu", "genggu", "luo"], 0.9, -3.0)


## 吃喝用的声音：喝的咕嘟，吃的窸窣。
func use_item(id: String) -> void:
	play("sip" if id == "water" or id.ends_with("tea") or id.ends_with("soup") else "leather", -4.0)


# ---------- 音量 ----------

func volume(key: String) -> float:
	return float(Game.meta.get("settings", {}).get(key, DEFAULT_VOLUME[key]))


func set_volume(key: String, linear: float) -> void:
	if not Game.meta.has("settings"):
		Game.meta.settings = {}
	Game.meta.settings[key] = clampf(linear, 0.0, 1.0)
	apply_volumes()


func apply_volumes() -> void:
	for key in BUSES:
		var i := AudioServer.get_bus_index(BUSES[key])
		var v := volume(key)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)


# ---------- 音效 ----------

func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	return _streams[path]


func _variant(sound: String) -> AudioStream:
	var n: int = VARIANTS.get(sound, 1)
	var file := sound if n <= 1 else "%s_%d" % [sound, randi_range(1, n)]
	return _stream(SFX % file)


func play(sound: String, volume_db := 0.0, pitch_var := 0.06) -> AudioStreamPlayer:
	var s := _variant(sound)
	if s == null:
		return null
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()
	return p


## 3D 定位音效：挂在 parent 下，播完自己删掉。
func play_at(sound: String, pos: Vector3, parent: Node, volume_db := 0.0, pitch_var := 0.08, unit_size := 6.0) -> void:
	var s := _variant(sound)
	if s == null or parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "Sfx"
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.max_distance = 60.0
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


## 一串敲击：sounds 依次敲，间隔 gap 秒。
func strikes(sounds: Array, gap := 0.6, volume_db := 0.0) -> void:
	for k in sounds.size():
		if k > 0:
			await get_tree().create_timer(gap, false).timeout
		play(sounds[k], volume_db, 0.02)


func _on_node_added(n: Node) -> void:
	if n is BaseButton:
		(n as BaseButton).pressed.connect(_click)


func _click() -> void:
	# 同一帧好几个按钮（重画界面时）不叠在一起响
	var now := Time.get_ticks_msec()
	if now - _last_click < 40:
		return
	_last_click = now
	play("ui_click", -8.0, 0.04)


# ---------- 环境声 ----------

## 循环环境声：volume_db 为 null 时淡出停掉。
func ambience(sound: String, volume_db = 0.0, fade := 1.5) -> void:
	var p: AudioStreamPlayer = _amb.get(sound)
	if volume_db == null:
		if p != null and p.playing:
			_fade(p, -60.0, fade, true)
		return
	if p == null:
		var s := _stream(AMB % sound)
		if s == null:
			return
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		p = AudioStreamPlayer.new()
		p.stream = s
		p.bus = "Ambience"
		add_child(p)
		_amb[sound] = p
	if not p.playing:
		p.volume_db = -60.0
		p.play(randf() * p.stream.get_length())
	_fade(p, float(volume_db), fade)


func ambience_off() -> void:
	for sound in _amb:
		ambience(sound, null)


# ---------- 配乐 ----------

## 换曲（两轨交叉淡化）。name 为空串就淡出。同一首只改音量。
func music(track: String, volume_db := 0.0, fade := 2.5) -> void:
	if track == _music_name:
		if track != "" and absf(volume_db - _music_db) > 0.1:
			_music_db = volume_db
			_fade(_music[0], volume_db, fade)
		return
	_music_name = track
	_music_db = volume_db
	var old := _music[0]
	if old.playing:
		_fade(old, -60.0, fade, true)
	_music.reverse()
	if track == "":
		return
	var s := _stream(MUSIC % track)
	if s == null:
		return
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	var p := _music[0]
	p.stream = s
	p.volume_db = -60.0
	p.play()
	_fade(p, volume_db, fade)


func music_name() -> String:
	return _music_name


## 同一个播放器只留一个渐变，新的顶掉旧的。
func _fade(p: AudioStreamPlayer, db: float, sec: float, stop_after := false) -> void:
	var old: Tween = _tweens.get(p)
	if old != null and old.is_valid():
		old.kill()
	var tw := create_tween()
	tw.tween_property(p, "volume_db", db, sec)
	if stop_after:
		tw.tween_callback(p.stop)
	_tweens[p] = tw
