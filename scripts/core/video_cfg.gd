extends RefCounted
## 画面选项：全屏 / 分辨率 / 垂直同步。存 user://video.cfg，启动时套一次。
## 分辨率只改窗口大小——内容走项目既有的 canvas_items + expand 拉伸，不另做缩放逻辑。

## 同 input_cfg：测试指向临时文件，不碰玩家真配置。
static var cfg_path := "user://video.cfg"
const SECTION := "video"

## 分辨率选项（索引即存的值）。1280×720 是项目基准分辨率。
const SIZES := [[1280, 720], [1600, 900], [1920, 1080]]

## 默认值。缺 cfg / 脏值都落回这里。
static func defaults() -> Dictionary:
	return {"fullscreen": false, "resolution": 0, "vsync": true}


## 读 cfg。逐项校验类型，坏值丢默认。
## 同 input_cfg：不叫 load()，避开 GDScript 内建函数。
static func read() -> Dictionary:
	var out := defaults()
	if FileAccess.file_exists(cfg_path):
		var cfg := ConfigFile.new()
		if cfg.load(cfg_path) == OK:
			for key in out:
				if cfg.has_section_key(SECTION, key):
					var value = cfg.get_value(SECTION, key, out[key])
					if typeof(value) == typeof(out[key]):
						out[key] = value
	out["resolution"] = clampi(int(out["resolution"]), 0, SIZES.size() - 1)
	return out


## 存 cfg（整份写，三项一起）。
static func save(opts: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for key in defaults():
		cfg.set_value(SECTION, key, opts.get(key, defaults()[key]))
	cfg.save(cfg_path)


## 套到窗口上。headless 下 DisplayServer 是哑实现，调用安全（测试直接跑）。
static func apply(opts: Dictionary) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if bool(opts.get("fullscreen", false)) else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if bool(opts.get("vsync", true)) else DisplayServer.VSYNC_DISABLED)
	var size: Array = SIZES[clampi(int(opts.get("resolution", 0)), 0, SIZES.size() - 1)]
	DisplayServer.window_set_size(Vector2i(int(size[0]), int(size[1])))
