extends "res://scripts/ui/screens/screen_base.gd"
## 定难度。对应原版 DifficultySelect：四档预设，参数全在 data/difficulty.json 里。
## 点卡选中，底部一个确认；选中项记在 _picked，界面重画也不会丢。带记忆重开时沿用上一局的难度。

const Pre = preload("res://scripts/core/pre.gd")

## 参数的中文名，给卡片上的小表用
const PARAM_LABELS := {
	"silver_mul": "开局银两", "hp_mul": "气血上限", "food_mul": "食量",
	"water_mul": "水量", "cold_add": "寒冷", "wave_mul": "尸潮",
}

## 当前选中的难度 id（默认寻常年景）
var _picked := "normal"


func build() -> void:
	var role_id: String = Game.pending_role
	var v := page(28)
	var head := UI.hbox()
	head.add_child(UI.heading("这一劫，有多难？", 34))
	head.add_child(UI.spacer())
	head.add_child(UI.button("返回", func(): Game.go("roles")))
	v.add_child(head)
	if role_id != "":
		var r: Dictionary = Data.table("roles")[role_id]
		v.add_child(UI.para("身份：%s —— %s" % [r.name, r.trait_desc], 17))
	v.add_child(UI.sep())
	var row := UI.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	for d in Data.table("difficulty"):
		row.add_child(_card(d))
	v.add_child(UI.sep())
	var foot := UI.hbox()
	foot.add_child(UI.spacer())
	foot.add_child(UI.seal_button("就这个 · %s" % State.diff_name({"difficulty": _picked}), _start))
	v.add_child(foot)


## 一张难度卡：名字、说明，再把偏离"寻常年景"的参数列出来（不列等于没变）。
## 整张卡就是一个按钮，点它选中。
func _card(d: Dictionary) -> Control:
	var id := str(d.id)
	var v := UI.vbox(8)
	var title := UI.heading(str(d.name), 28)
	if id == _picked:
		title.modulate = UI.CINNABAR
	v.add_child(title)
	v.add_child(UI.para(str(d.desc), 17))
	v.add_child(UI.sep())
	var rows := UI.grid(3, 10, 4)
	for k in PARAM_LABELS:
		var val: float = float(d.get("params", {}).get(k, _default_of(k)))
		if is_equal_approx(val, _default_of(k)):
			continue
		rows.add_child(UI.label(PARAM_LABELS[k], 15, UI.INK_SOFT))
		rows.add_child(UI.label(_fmt(k, val), 15, _color_of(val)))
	v.add_child(rows)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(gap)
	if id == _picked:
		v.add_child(UI.tag("已选中", UI.CINNABAR))
	var p := UI.panel(v, Color("#f2e3c2") if id == _picked else UI.PANEL)
	# 卡片占满整行，并让选中项始终比其他选项更宽；不能依赖文字的最小宽度。
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 1.4 if id == _picked else 1.0
	# 整张卡收点击：内容一律不吃鼠标（Label 默认就 IGNORE，但 gap、各种容器默认
	# STOP，会把点击吃掉），卡片自己接 gui_input。以前这段写在屏幕根的 _gui_input
	# 里按坐标找卡：卡嵌套在 Margin→VBox→HBox 里，根的 get_children() 只有一个
	# MarginContainer，且事件先被卡里的控件吃掉、根本到不了根——四张卡全都点不动。
	UI.ignore_mouse(v)
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.gui_input.connect(_on_card_input.bind(id))
	p.set_meta("difficulty_pick", id)
	return p


func _on_card_input(event: InputEvent, id: String) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_pick(id)


func _pick(id: String) -> void:
	_picked = id
	_redraw()


## 选中后重画。必须先 clear：build() 只往 self 追加，不清就会每点一次叠一层
## （和 challenge_screen 的 _redraw 一个套路）。
func _redraw() -> void:
	UI.clear(self)
	build()


func _start() -> void:
	if Game.pending_role == "":
		Game.go("roles")
		return
	# 难度定了，接着去挑了愿（挑战自选的第一步）
	Game.pending_difficulty = _picked
	Game.go("challenge")


func _default_of(k: String) -> float:
	match k:
		"cold_add":
			return 0.0
		_:
			return 1.0


## 乘数直接写百分比；cold_add 是加减，写正负号
func _fmt(k: String, val: float) -> String:
	if k == "cold_add":
		return "%+d 度" % int(val)
	return "%d%%" % int(round(val * 100.0))


## 越难越红，越简单越青
func _color_of(val: float) -> Color:
	if val > 1.0:
		return UI.CINNABAR
	if val < 1.0:
		return Color("#3f7d5a")
	return UI.INK_SOFT
