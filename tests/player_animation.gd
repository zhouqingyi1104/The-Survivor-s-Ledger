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
		# Production setup for the default model, explicit preview override for the other rigs.
		player.setup("scholar")
		if body != player.figure._look.body:
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
		var skel: Skeleton3D = figure._skel
		var idle_rotations := {}
		if body in ["moon", "maid"]:
			figure._process(1.0 / 60.0)
			ap.advance(0.4)
			idle_rotations = sample_idle_joints(ap, skel)
		var left := skel.find_bone("mixamorig_LeftFoot" if body in ["moon", "maid"] else "foot_l")
		var right := skel.find_bone("mixamorig_RightFoot" if body in ["moon", "maid"] else "foot_r")
		check(left >= 0 and right >= 0, "%s has no left/right foot bones" % body)
		for held in [[KEY_W], [KEY_W, KEY_A], [KEY_W, KEY_D], [KEY_S, KEY_A], [KEY_S, KEY_D], []]:
			player.position = Vector3(0, 0.02, 0)
			keys(held)
			# 单帧按键仍处于起步或收步；取匀速段验证实际步态和骨骼循环。
			for frame in 32:
				player._physics_process(1.0 / 60.0)
				figure._process(1.0 / 60.0)
				ap.advance(1.0 / 60.0)
			var clip_name: String = ap.current_animation
			var clip := ap.get_animation(clip_name)
			check(figure.moving == not held.is_empty(), "%s input state %s" % [body, held])
			check(clip.loop_mode == Animation.LOOP_LINEAR, "%s %s is not looping" % [body, clip_name])
			var samples := []
			var poses := {}
			var feet: Array[float] = []
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
					if left >= 0 and right >= 0:
						var separation := skel.get_bone_global_pose(left).origin - skel.get_bone_global_pose(right).origin
						feet.append((skel.global_basis * separation).dot(figure.global_basis.z.normalized()))
			check(ap.is_playing(), "%s %s stopped for %s" % [body, clip_name, held])
			check(samples.max() - samples.min() > 0.05, "%s animation clock frozen for %s" % [body, held])
			check(poses.size() > 1, "%s skeleton pose frozen for %s" % [body, held])
			if not held.is_empty():
				check(player.position.length() > 1.0, "%s did not move for %s" % [body, held])
				if not feet.is_empty():
					check(feet.min() < -0.12 and feet.max() > 0.12, "%s %s did not alternate the lead foot" % [body, held])
			print("Animation input: ", body, " ", held, " clip=", ap.current_animation, " playing=", ap.is_playing())
		if body in ["moon", "maid"]:
			check_shoe_contact(figure, body)
			var after_stop := sample_idle_joints(ap, skel)
			for joint: String in idle_rotations:
				var a: Quaternion = idle_rotations[joint]
				check(a.angle_to(after_stop[joint]) < deg_to_rad(1.0), "%s kept its running %s pose after stopping" % [body, joint])
		player.queue_free()
		await get_tree().process_frame
	keys([])
	print("Player animation: 18 cases, %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)


## Compare the same idle frame on either side of running. Native idle omits these tracks.
func sample_idle_joints(ap: AnimationPlayer, skel: Skeleton3D) -> Dictionary:
	ap.seek(0.23, true)
	var sample := {}
	for joint in ["mixamorig_Spine1", "mixamorig_LeftToeBase", "mixamorig_RightToeBase"]:
		var index := skel.find_bone(joint)
		check(index >= 0, "Missing idle joint " + joint)
		if index >= 0: sample[joint] = skel.get_bone_pose_rotation(index)
	return sample


## At cruising speed a planted shoe should stay near its patch of ground.
## Lowest 15% of each toe's height trace approximates stance, avoiding heel lift.
func check_shoe_contact(figure: Node3D, body: String) -> void:
	var dt := 1.0 / 120.0
	var ap: AnimationPlayer = figure._ap
	var skel: Skeleton3D = figure._skel
	var forward := figure.global_basis.z.normalized()
	var bones := [skel.find_bone("mixamorig_LeftToeBase"), skel.find_bone("mixamorig_RightToeBase")]
	if -1 in bones:
		check(false, body + " has no toe markers for the stance check")
		return
	figure.moving = true
	figure.move_speed = Player.SPEED
	var feet := [[], []]
	for frame in 480:
		figure._process(dt)
		ap.advance(dt)
		if frame >= 120:
			for side in 2:
				feet[side].append(skel.to_global(skel.get_bone_global_pose(bones[side]).origin))
	for side in 2:
		var marks: Array = feet[side]
		var heights: Array[float] = []
		for p: Vector3 in marks:
			heights.append(p.y)
		heights.sort()
		var low := heights[int(heights.size() * 0.15)]
		var drift: Array[float] = []
		for i in range(1, marks.size()):
			var prev: Vector3 = marks[i - 1]
			var next: Vector3 = marks[i]
			if maxf(prev.y, next.y) <= low:
				# The fixture holds the body in place as the skeleton plays.
				# Add the body's actual forward speed to get toe drift against the floor.
				drift.append(absf((next - prev).dot(forward) / dt + Player.SPEED))
		check(drift.size() >= 12, body + " has too few contact samples")
		if drift.is_empty(): continue
		drift.sort()
		var median := drift[drift.size() / 2]
		print("%s toe %d at %.1f m/s, median contact drift %.3f m/s" % [body, side, Player.SPEED, median])
		check(median < Player.SPEED * 0.1, "%s toe %d slides %.3f m/s during stance" % [body, side, median])
	figure.move_speed = 0.0
	figure.moving = false
	var height_range := Vector2(INF, -INF)
	for frame in 720:
		figure._process(dt)
		ap.advance(dt)
		if frame < 120: continue
		var toe := figure.to_local(skel.to_global(skel.get_bone_global_pose(bones[0]).origin))
		height_range.x = minf(height_range.x, toe.y)
		height_range.y = maxf(height_range.y, toe.y)
	check(height_range.y < 0.06 and height_range.y - height_range.x < 0.025, "%s idle shoe leaves the ground (%s)" % [body, height_range])
