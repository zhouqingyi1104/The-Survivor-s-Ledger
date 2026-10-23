extends Node3D
## Input reaches the real movement controller; animation advances deterministically.
const Player = preload("res://scripts/world/player.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func keys(held: Array) -> void:
	for key in [KEY_W, KEY_A, KEY_S, KEY_D]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.pressed = key in held
		Input.parse_input_event(event)
	Input.flush_buffered_events()

func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	collider.shape = box
	collider.position.y = -0.5
	floor_body.add_child(collider)
	add_child(floor_body)
	await get_tree().physics_frame
	for body in ["moon", "maid", "female_long"]:
		var player = Player.new()
		add_child(player)
		player.set_physics_process(false)
		# Select each supported hero rig before setup creates the model.
		# setup() creates the figure, so build a matching test figure first.
		player.setup("scholar")
		player.figure.free()
		player.figure = Player.Figure.new()
		player.figure.hero = true
		player.figure.force_body = body
		player.add_child(player.figure)
		player.figure.setup("scholar")
		var figure = player.figure
		figure.set_process(false)
		var ap: AnimationPlayer = figure._ap
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for held in [[KEY_W], [KEY_W, KEY_A], [KEY_W, KEY_D], [KEY_S, KEY_A], [KEY_S, KEY_D], []]:
			player.position = Vector3(0, 0.02, 0)
			keys(held)
			player._physics_process(1.0 / 60.0)
			figure._process(1.0 / 60.0)
			var clip_name: String = ap.current_animation
			var clip := ap.get_animation(clip_name)
			check(figure.moving == not held.is_empty(), "%s input state %s" % [body, held])
			check(clip.loop_mode == Animation.LOOP_LINEAR, "%s %s is not looping" % [body, clip_name])
			var samples := []
			var poses := {}
			for frame in range(int(clip.length * 180.0) + 12):
				player._physics_process(1.0 / 60.0)
				figure._process(1.0 / 60.0)
				ap.advance(1.0 / 60.0)
				if frame > int(clip.length * 120.0):
					samples.append(ap.current_animation_position)
					var rotations := []
					for bone in figure._skel.get_bone_count():
						rotations.append(figure._skel.get_bone_pose_rotation(bone))
					poses[hash(rotations)] = true
			check(ap.is_playing(), "%s %s stopped for %s" % [body, clip_name, held])
			check(samples.max() - samples.min() > 0.05, "%s animation clock frozen for %s" % [body, held])
			check(poses.size() > 1, "%s skeleton pose frozen for %s" % [body, held])
			if not held.is_empty():
				check(player.position.length() > 1.0, "%s did not move for %s" % [body, held])
			print("Animation input: ", body, " ", held, " clip=", ap.current_animation, " playing=", ap.is_playing())
		player.queue_free()
		await get_tree().process_frame
	keys([])
	print("Player animation: 18 cases, %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
