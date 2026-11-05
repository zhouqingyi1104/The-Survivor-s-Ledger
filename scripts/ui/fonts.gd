extends RefCounted
## 随包字体：纸面文楷、HUD 黑体，不向系统取字。

const BOOK = preload("res://assets/fonts/LXGWWenKai-Regular.ttf")
const BODY = preload("res://assets/fonts/NotoSansSC-VF.ttf")
## 数值 OpenType tag：Godot 4.7 会忽略字符串别名 wght。
const WEIGHT_AXIS := 0x77676874

static var _configured := false
static var _body: FontVariation
static var _bold: FontVariation


static func _configure() -> void:
	if _configured:
		return
	for font in [BOOK, BODY]:
		font.allow_system_fallback = false
		font.fallbacks = []
	_configured = true


static func book() -> Font:
	_configure()
	return BOOK


static func body() -> Font:
	_configure()
	if _body == null:
		_body = FontVariation.new()
		_body.base_font = BODY
		_body.variation_opentype = {WEIGHT_AXIS: 400}
	return _body


static func bold() -> Font:
	_configure()
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = BODY
		_bold.variation_opentype = {WEIGHT_AXIS: 700}
	return _bold
