extends SceneTree
## Rebuild the shared 413 Games locomotion library from the bundled CC0 Quaternius UAL.
## godot --headless --path . --script res://tools/pipeline/hero_locomotion.gd

const SOURCE := preload("res://assets/third_party/quaternius/ual/UAL1_Standard.glb")
const TARGET := preload("res://assets/third_party/413games/moon-motion-v7.glb")
const OUTPUT := "res://assets/models/folk/hero_locomotion.res"
const LIMBS := {"clavicle": "Shoulder", "upperarm": "Arm", "lowerarm": "ForeArm", "hand": "Hand",
	"thigh": "UpLeg", "calf": "Leg", "foot": "Foot", "ball": "ToeBase"}
const HERO_SCALE := 0.92
## [metres per second, seconds per full left/right stride] at normal playback speed.
const STRIDES := {"Walk": Vector2(1.25, 1.10), "Jog_Fwd": Vector2(3.4, 0.76), "Sprint": Vector2(4.8, 0.68)}


func _initialize() -> void:
	_bake.call_deferred()


func _bake() -> void:
	var source := SOURCE.instantiate()
	var target := TARGET.instantiate()
	root.add_child(source)
	root.add_child(target)
	var from: Skeleton3D = source.find_child("Skeleton3D", true, false)
	var to: Skeleton3D = target.find_child("Skeleton3D", true, false)
	var player: AnimationPlayer = source.find_child("AnimationPlayer", true, false)
	var target_player: AnimationPlayer = target.find_child("AnimationPlayer", true, false)
	var from_path := player.get_node(player.root_node).get_path_to(from)
	var to_path := target_player.get_node(target_player.root_node).get_path_to(to)
	var mapping := {"pelvis": "Hips", "spine_01": "Spine", "spine_02": "Spine1",
		"spine_03": "Spine2", "neck_01": "Neck", "Head": "Head"}
	for side in ["l", "r"]:
		var prefix := "Left" if side == "l" else "Right"
		for limb: String in LIMBS:
			mapping[limb + "_" + side] = prefix + LIMBS[limb]
		for finger: String in ["thumb", "index", "middle", "ring", "pinky"]:
			for joint in range(1, 4):
				mapping["%s_%02d_%s" % [finger, joint, side]] = prefix + "Hand" + finger.capitalize() + str(joint)
	var stature := _leg_length(to, "mixamorig_LeftUpLeg", "mixamorig_LeftFoot") / _leg_length(from, "thigh_l", "foot_l")
	var library := AnimationLibrary.new()
	for name in ["Walk", "Jog_Fwd", "Sprint"]:
		var clip := player.get_animation(name)
		var output := Animation.new()
		output.length = clip.length
		output.loop_mode = Animation.LOOP_LINEAR
		for bone: String in mapping:
			var target_bone := "mixamorig_" + str(mapping[bone])
			var src := from.find_bone(bone)
			var dst := to.find_bone(target_bone)
			assert(src >= 0 and dst >= 0, "Missing bone: " + bone + "/" + target_bone)
			var input_track := clip.find_track(NodePath("%s:%s" % [from_path, bone]), Animation.TYPE_ROTATION_3D)
			var out_track := output.add_track(Animation.TYPE_ROTATION_3D)
			output.track_set_path(out_track, NodePath("%s:%s" % [to_path, target_bone]))
			var src_rest := from.get_bone_rest(src).basis.get_rotation_quaternion()
			var dst_rest := to.get_bone_rest(dst).basis.get_rotation_quaternion()
			# A rotation relative to rest must first be expressed in the receiving bone's axes.
			# The target Armature rotates X by 90 degrees and stores distances in centimetres.
			var space := (_world_rest(to, dst).basis.orthonormalized().inverse() * _world_rest(from, src).basis.orthonormalized()).get_rotation_quaternion()
			if input_track < 0:
				output.rotation_track_insert_key(out_track, 0.0, dst_rest)
			else:
				for key in clip.track_get_key_count(input_track):
					var delta: Quaternion = src_rest.inverse() * clip.track_get_key_value(input_track, key)
					var rotation := (dst_rest * space * delta * space.inverse()).normalized()
					output.rotation_track_insert_key(out_track, clip.track_get_key_time(input_track, key), rotation)
		_bake_hips(clip, output, from_path, to_path, from, to, stature)
		library.add_animation(name, _fit_stride(output, name, target_player, to))
	var result := ResourceSaver.save(library, OUTPUT, ResourceSaver.FLAG_COMPRESS)
	source.free()
	target.free()
	quit(0 if result == OK else 1)


## Sample the feet on the actual target skeleton. During stance the grounded shoe moves
## backwards at travelling speed. The swing takes the remaining time in the selected cadence.
func _fit_stride(raw: Animation, clip_name: String, player: AnimationPlayer, rig: Skeleton3D) -> Animation:
	const STEPS := 120
	var specification: Vector2 = STRIDES[clip_name]
	var preview := AnimationLibrary.new()
	preview.add_animation("raw", raw)
	player.add_animation_library("preview", preview)
	rig.reset_bone_poses()
	player.play("preview/raw", 0)
	var feet := [rig.find_bone("mixamorig_LeftToeBase"), rig.find_bone("mixamorig_RightToeBase")]
	var poses := PackedVector3Array()
	var ground := INF
	for i in STEPS + 1:
		player.seek(raw.length * i / STEPS, true)
		for foot: int in feet:
			var point := rig.to_global(rig.get_bone_global_pose(foot).origin) * HERO_SCALE
			poses.append(point)
			ground = minf(ground, point.y)
	player.stop()
	player.remove_animation_library("preview")
	var fixed := PackedFloat64Array()
	var free := PackedFloat64Array()
	var stance_time := 0.0
	var swing_weight := 0.0
	for i in STEPS:
		var j := i * 2
		if poses[j + 1].y < poses[j].y: j += 1
		var back := maxf(0, poses[j].z - poses[j + 2].z)
		var weight := (1.0 - smoothstep(0.022, 0.08, poses[j].y - ground)) * smoothstep(0.0, 0.007, back)
		var stance := weight * back / specification.x
		fixed.append(stance)
		free.append(1.0 - weight)
		stance_time += stance
		swing_weight += 1.0 - weight
	assert(stance_time < specification.y and swing_weight > 0.0)
	var clock := PackedFloat64Array([0.0])
	for i in STEPS:
		clock.append(clock[i] + fixed[i] + free[i] * (specification.y - stance_time) / swing_weight)

	var reference_height := _world_rest(rig, feet[0]).origin.y * HERO_SCALE
	var lift := rig.global_transform.basis.inverse() * Vector3.UP * ((reference_height - ground) / HERO_SCALE)
	var fitted := Animation.new()
	fitted.length = specification.y
	fitted.loop_mode = Animation.LOOP_LINEAR
	for tr in raw.get_track_count():
		var type := raw.track_get_type(tr)
		var out := fitted.add_track(type)
		fitted.track_set_path(out, raw.track_get_path(tr))
		if raw.track_get_key_count(tr) == 1 and type == Animation.TYPE_ROTATION_3D:
			fitted.rotation_track_insert_key(out, 0.0, raw.track_get_key_value(tr, 0))
			continue
		for i in STEPS + 1:
			var source_time := raw.length * i / STEPS
			if type == Animation.TYPE_ROTATION_3D:
				fitted.rotation_track_insert_key(out, clock[i], raw.rotation_track_interpolate(tr, source_time))
			else:
				fitted.position_track_insert_key(out, clock[i], raw.position_track_interpolate(tr, source_time) + lift)
	return fitted


func _world_rest(skeleton: Skeleton3D, bone: int) -> Transform3D:
	return skeleton.global_transform * skeleton.get_bone_global_rest(bone)


func _leg_length(skeleton: Skeleton3D, hip: String, ankle: String) -> float:
	return _world_rest(skeleton, skeleton.find_bone(hip)).origin.distance_to(_world_rest(skeleton, skeleton.find_bone(ankle)).origin)


func _bake_hips(clip: Animation, output: Animation, from_path: NodePath, to_path: NodePath,
		from: Skeleton3D, to: Skeleton3D, stature: float) -> void:
	var src := from.find_bone("pelvis")
	var dst := to.find_bone("mixamorig_Hips")
	var track := clip.find_track(NodePath("%s:pelvis" % from_path), Animation.TYPE_POSITION_3D)
	var out_track := output.add_track(Animation.TYPE_POSITION_3D)
	output.track_set_path(out_track, NodePath("%s:mixamorig_Hips" % to_path))
	var parent_space := to.global_transform.basis.inverse() * _world_rest(from, from.get_bone_parent(src)).basis
	for key in clip.track_get_key_count(track):
		var delta: Vector3 = clip.track_get_key_value(track, key) - from.get_bone_rest(src).origin
		output.position_track_insert_key(out_track, clip.track_get_key_time(track, key),
			to.get_bone_rest(dst).origin + parent_space * delta * stature)
