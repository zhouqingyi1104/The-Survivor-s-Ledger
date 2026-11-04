extends RefCounted
## 三问只属于这次打开的表单；不进入存档，也不跨局保留。

const UI = preload("res://scripts/ui/ui_kit.gd")
const Report = preload("res://scripts/core/playtest_report.gd")
const MODAL_KEY := "playtest_feedback"


class Draft extends RefCounted:
	var answers := {}
	var submitting := false
	var submitted := false
	var submit_ref: WeakRef


static func open() -> void:
	if UI.has_modal(MODAL_KEY):
		return
	var draft := Draft.new()
	UI.open_modal(MODAL_KEY, "试玩反馈", _build.bind(draft), true, 740)


static func _build(body: VBoxContainer, draft: Draft) -> void:
	body.add_child(UI.para("这三问都可以留空。回答写入本机报告，附件来源会在结果中说明；请先查看内容，再自行分享。", 16))
	var content := UI.vbox(8)
	var error := UI.para(Report.feedback_error(draft.answers), 15, UI.CINNABAR)
	error.set_meta("feedback_error", true)
	error.custom_minimum_size.y = 20
	for i in range(Report.QUESTIONS.size()):
		var key: String = Report.FEEDBACK_KEYS[i]
		content.add_child(UI.para(Report.QUESTIONS[i], 16, UI.INK))
		var editor := TextEdit.new()
		editor.set_meta("feedback_key", key)
		editor.text = str(draft.answers.get(key, ""))
		editor.placeholder_text = "选填，可写多行"
		editor.custom_minimum_size.y = 100
		editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		editor.add_theme_font_size_override("font_size", 17)
		editor.add_theme_color_override("font_color", UI.INK)
		editor.add_theme_color_override("font_placeholder_color", UI.INK_FAINT)
		editor.add_theme_color_override("caret_color", UI.CINNABAR)
		editor.add_theme_stylebox_override("normal", UI._box(UI.PAPER_LIGHT, UI.BORDER, 1, 2, 10, 8))
		editor.add_theme_stylebox_override("focus", UI._box(UI.PAPER_LIGHT, UI.CINNABAR, 1, 2, 10, 8))
		content.add_child(editor)
		var count := UI.label("%d / %d 字" % [editor.text.length(), Report.MAX_FEEDBACK_CHARS], 14, UI.INK_FAINT)
		if editor.text.length() > Report.MAX_FEEDBACK_CHARS:
			count.add_theme_color_override("font_color", UI.CINNABAR)
		content.add_child(count)
		editor.text_changed.connect(_edited.bind(editor, key, draft, count, error, UI.INK_FAINT, UI.CINNABAR))
		if i < Report.QUESTIONS.size() - 1:
			content.add_child(UI.sep())
	var height := mini(380, maxi(150, int(body.get_viewport().get_visible_rect().size.y) - 300))
	body.add_child(UI.scroll(content, height))
	body.add_child(error)
	var row := UI.hbox(10)
	row.add_child(UI.spacer())
	var cancel := UI.button("取消", _cancel.bind(draft))
	cancel.set_meta("feedback_cancel", true)
	row.add_child(cancel)
	var submit := UI.seal_button("导出到本机", _submit.bind(draft))
	submit.set_meta("feedback_submit", true)
	draft.submit_ref = weakref(submit)
	row.add_child(submit)
	body.add_child(row)


static func _edited(editor: TextEdit, key: String, draft: Draft, count: Label, error: Label, normal_color: Color, error_color: Color) -> void:
	draft.answers[key] = editor.text
	var length := editor.text.length()
	count.text = "%d / %d 字" % [length, Report.MAX_FEEDBACK_CHARS]
	count.add_theme_color_override("font_color", error_color if length > Report.MAX_FEEDBACK_CHARS else normal_color)
	error.text = Report.feedback_error(draft.answers)


static func _live(draft: Draft) -> bool:
	if draft.submit_ref == null or not UI.has_modal(MODAL_KEY):
		return false
	var submit = draft.submit_ref.get_ref()
	return is_instance_valid(submit) and submit.is_inside_tree() and not submit.is_queued_for_deletion()


static func _cancel(draft: Draft) -> void:
	if _live(draft) and not draft.submitting:
		UI.close_modal(MODAL_KEY)


static func _submit(draft: Draft) -> void:
	if not _live(draft) or draft.submitting or draft.submitted or UI.has_modal("playtest_report"):
		return
	draft.submitting = true
	var result: Dictionary = Game.export_playtest(draft.answers)
	draft.submitting = false
	if bool(result.get("ok", false)):
		draft.submitted = true
		UI.close_modal(MODAL_KEY)
	# 失败时原表单仍在下层；合上结果后可直接改写或重试。
	Dialogs.playtest_exported(result)
