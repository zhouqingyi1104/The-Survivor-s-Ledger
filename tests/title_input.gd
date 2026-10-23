extends Node
## Exercise viewport mouse routing rather than emitting Button.pressed directly.

func _ready() -> void:
	Game.no_save = true
	Game.save_path = "user://title_input_missing_save.json"
	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.2).timeout
	var button: Button
	for node in main.find_children("*", "Button", true, false):
		if node.text == "新开一卷":
			button = node
			break
	assert(button != null)
	var point := button.get_global_rect().get_center()
	print("Button rect: ", button.get_global_rect(), " viewport: ", get_viewport().get_visible_rect())
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion)
	await get_tree().process_frame
	print("Title hover: ", get_viewport().gui_get_hovered_control())
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event)
		await get_tree().process_frame
	var passed: bool = Game.screen == "roles"
	print("Title mouse click: ", "PASS" if passed else "FAIL")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if passed else 1)
