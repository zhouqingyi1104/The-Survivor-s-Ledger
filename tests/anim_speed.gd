extends SceneTree
## 开发用：量走 / 跑动作原本的步速（米/秒）。脚踩在地上那段时间，脚相对身体往后滑的速度就是步速。
## 运行：godot --headless --path . --script res://tests/anim_speed.gd

const BODY := "res://assets/models/characters/male_short.glb"
const LIB := "res://assets/third_party/quaternius/ual/UAL1_Standard.glb"


func _init() -> void:
	var body: Node3D = load(BODY).instantiate()
	root.add_child(body)
	var skel: Skeleton3D = body.find_child("Skeleton3D", true, false)
	var ual: Node = load(LIB).instantiate()
	var lib: AnimationLibrary = (ual.find_child("AnimationPlayer", true, false) as AnimationPlayer).get_animation_library("")
	var ap: AnimationPlayer = ual.find_child("AnimationPlayer", true, false)
	for anim_name in ["Walk", "Walk_Formal", "Jog_Fwd", "Sprint", "Crouch_Fwd"]:
		if not lib.has_animation(anim_name):
			continue
		var anim := lib.get_animation(anim_name)
		var length := anim.length
		var steps := 120
		var samples := []
		for i in steps + 1:
			_apply(anim, skel, length * i / steps)
			var fl := _global(skel, skel.find_bone("foot_l")).origin
			var fr := _global(skel, skel.find_bone("foot_r")).origin
			samples.append([fl, fr])
		var speeds := []
		for side in 2:
			var miny := 1e9
			for s in samples:
				miny = minf(miny, s[side].y)
			for i in steps:
				var a: Vector3 = samples[i][side]
				var b: Vector3 = samples[i + 1][side]
				if a.y < miny + 0.03 and b.y < miny + 0.03:
					speeds.append(-(b.z - a.z) / (length / steps))
		speeds.sort()
		var med: float = speeds[speeds.size() / 2] if speeds.size() > 0 else 0.0
		var zmin := 1e9
		var zmax := -1e9
		for smp in samples:
			zmin = minf(zmin, smp[0].z)
			zmax = maxf(zmax, smp[0].z)
		# 另一种估法：一个周期身体前进一个跨步 ≈ 脚前后摆幅的两倍（左右各一步）
		print("%-12s 长 %.2f 秒  着地估 %.2f 米/秒（%d 样本）  摆幅 %.2f 米 → 摆幅估 %.2f 米/秒" % [anim_name, length, med, speeds.size(), zmax - zmin, 2.0 * (zmax - zmin) / length])
	quit()


## 不靠 AnimationPlayer，直接按轨道把这一刻的姿势摆到骨骼上。
func _apply(anim: Animation, skel: Skeleton3D, t: float) -> void:
	for tr in anim.get_track_count():
		var bone := skel.find_bone(String(anim.track_get_path(tr).get_concatenated_subnames()))
		if bone < 0:
			continue
		match anim.track_get_type(tr):
			Animation.TYPE_POSITION_3D:
				skel.set_bone_pose_position(bone, anim.position_track_interpolate(tr, t))
			Animation.TYPE_ROTATION_3D:
				skel.set_bone_pose_rotation(bone, anim.rotation_track_interpolate(tr, t))
			Animation.TYPE_SCALE_3D:
				skel.set_bone_pose_scale(bone, anim.scale_track_interpolate(tr, t))


## 骨骼不在运行中的树里，自己沿父链乘出全局姿势。
func _global(skel: Skeleton3D, bone: int) -> Transform3D:
	var t := skel.get_bone_pose(bone)
	var p := skel.get_bone_parent(bone)
	while p >= 0:
		t = skel.get_bone_pose(p) * t
		p = skel.get_bone_parent(p)
	return t
