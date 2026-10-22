extends RefCounted
## 院门前的短打：不开新场景，就在自家院子门口。
##
## 门是这一套的核心：关着，僵尸只能撞门（扣耐久）；开着，它们会走进院子砸东西。
## 玩家可以随时开门（出去打）或关门（缩回来挨撞），开关门本身就是风险——
## 门开着的那段时间，院子里的菜畦、米袋、家具都在挨啃。
##
## 这里只有判定，不画东西：位置用世界坐标的 x / z，3D 那边照着摆人。

const SPEED := 3.4
const Z_SPEED := 1.05
const Z_REACH := 1.25
const Z_TICK := 1.25        # 咬人 / 砸门 / 啃东西的间隔
const HIT_DMG := 5          # 咬一口掉多少气血
const BASH_DMG := 2         # 撞一下门掉多少耐久
const REACH := 2.2
const SWING_CD := 0.5
const MAX_LIVE := 5         # 门外同时最多站这么多只
const MAX_SECONDS := 45.0   # 打这么久还没清完，它们自己散了
const GATE := Vector2(0.0, 7.2)
const STREET_Z := 12.6
const INSIDE_Z := 6.4

## 院子里会被啃的地方：[名字, x, z, 类型]
const TARGETS := [
	["菜畦", 3.5, 1.4, "crop"],
	["米袋", -9.0, 1.5, "grain"],
	["柴垛", -8.6, 2.6, "fuel"],
	["灶台", -8.0, -1.6, "furniture"],
	["工作台", 8.2, -1.2, "furniture"],
]


## 开一场。count 是这一轮院门本该来几只；armored 时铜甲要两刀。
static func begin(count: int, armored: bool) -> Dictionary:
	var n := mini(maxi(1, count), MAX_LIVE)
	var foes := []
	for i in n:
		foes.append({
			"x": -6.0 + float(i) * 3.0 + float(i % 2) * 0.7,
			"z": STREET_Z + float(i % 3) * 1.2,
			"hp": 2 if armored else 1,
			"cd": 0.0,
			"dead": false,
			"inside": false,
			"target": -1,
			"chew": 0.0,
		})
	return {
		"t": 0.0, "foes": foes, "total": n, "armored": armored,
		"kills": 0, "hp_loss": 0, "contacts": 0, "bashes": 0,
		"wrecked": [], "done": false, "swing": 0.0,
	}


## 走一步。door_open：门是不是开着。返回这一帧发生的事（给界面弹提示）。
static func step(s: Dictionary, dt: float, px: float, pz: float, door_open: bool) -> Array:
	var events := []
	if bool(s.done):
		return events
	s.t = float(s.t) + dt
	if float(s.t) >= MAX_SECONDS:
		s.done = true
		return events
	s.swing = maxf(0.0, float(s.swing) - dt)
	for f in s.foes:
		if bool(f.dead):
			continue
		f.cd = maxf(0.0, float(f.cd) - dt)
		var tx: float = GATE.x
		var tz: float = GATE.y
		if bool(f.inside):
			var t: Array = TARGETS[int(f.target)]
			tx = float(t[1])
			tz = float(t[2])
		elif door_open:
			# 门开着：从门口穿进来
			if float(f.z) > INSIDE_Z:
				tz = INSIDE_Z
		var dx: float = tx - float(f.x)
		var dz: float = tz - float(f.z)
		var d := sqrt(dx * dx + dz * dz)
		var reached := d <= 0.9
		if bool(f.inside):
			reached = d <= 1.1
		if not reached:
			var k: float = Z_SPEED * dt / maxf(d, 0.001)
			f.x = float(f.x) + dx * k
			f.z = float(f.z) + dz * k
			continue
		# 到了：门开着就进屋，门关着就砸门
		if not bool(f.inside):
			if door_open:
				f.inside = true
				f.target = int(s.foes.find(f)) % TARGETS.size()
				f.z = INSIDE_Z
				events.append(["enter", f])
				continue
			if float(f.cd) <= 0.0:
				f.cd = Z_TICK
				s.bashes = int(s.bashes) + 1
				events.append(["bash", f])
			continue
		# 在院子里啃东西
		if float(f.cd) <= 0.0:
			f.cd = Z_TICK
			s.wrecked.append(int(f.target))
			events.append(["wreck", f])
	# 贴到人身上就咬（不管它是不是在院里）
	for f in s.foes:
		if bool(f.dead):
			continue
		var dx2: float = px - float(f.x)
		var dz2: float = pz - float(f.z)
		if sqrt(dx2 * dx2 + dz2 * dz2) <= Z_REACH and float(f.cd) <= 0.0:
			f.cd = Z_TICK
			s.hp_loss = int(s.hp_loss) + HIT_DMG
			s.contacts = int(s.contacts) + 1
			events.append(["bite", f])
	# 互相挤开
	for i in s.foes.size():
		var a: Dictionary = s.foes[i]
		if bool(a.dead):
			continue
		for j in range(i + 1, s.foes.size()):
			var b: Dictionary = s.foes[j]
			if bool(b.dead):
				continue
			var ex: float = float(a.x) - float(b.x)
			var ez: float = float(a.z) - float(b.z)
			var ed := sqrt(ex * ex + ez * ez)
			if ed > 0.001 and ed < 0.9:
				var push: float = (0.9 - ed) * 0.5
				a.x = float(a.x) + ex / ed * push
				a.z = float(a.z) + ez / ed * push
				b.x = float(b.x) - ex / ed * push
				b.z = float(b.z) - ez / ed * push
	if alive(s) == 0:
		s.done = true
	return events


static func strike(s: Dictionary, px: float, pz: float) -> Dictionary:
	if bool(s.done) or float(s.swing) > 0.0:
		return {}
	s.swing = SWING_CD
	var best_i := -1
	var best_d := REACH
	for i in s.foes.size():
		var f: Dictionary = s.foes[i]
		if bool(f.dead):
			continue
		var dx: float = px - float(f.x)
		var dz: float = pz - float(f.z)
		var d := sqrt(dx * dx + dz * dz)
		if d < best_d:
			best_d = d
			best_i = i
	if best_i < 0:
		return {"hit": false}
	var best: Dictionary = s.foes[best_i]
	best.hp = int(best.hp) - 1
	if int(best.hp) <= 0:
		best.dead = true
		s.kills = int(s.kills) + 1
		return {"hit": true, "kill": true, "i": best_i, "x": float(best.x), "z": float(best.z)}
	return {"hit": true, "kill": false, "i": best_i}


static func alive(s: Dictionary) -> int:
	var n := 0
	for f in s.foes:
		if not bool(f.dead):
			n += 1
	return n


static func inside_count(s: Dictionary) -> int:
	var n := 0
	for f in s.foes:
		if not bool(f.dead) and bool(f.inside):
			n += 1
	return n


## 收场：尸毒按被咬次数算，返回要写回 run 的东西。
static func finish(s: Dictionary) -> Dictionary:
	s.done = true
	var plague := false
	var chance: float = minf(0.5, 0.04 + 0.03 * int(s.contacts))
	if int(s.contacts) > 0:
		var h := int(s.contacts) * 7919 + int(s.kills) * 104729 + int(float(s.t) * 10.0)
		plague = float(h % 1000) / 1000.0 < chance
	return {
		"kills": int(s.kills), "hp_loss": int(s.hp_loss), "contacts": int(s.contacts),
		"bashes": int(s.bashes), "wrecked": s.wrecked.duplicate(), "plague": plague,
		"left": alive(s), "inside": inside_count(s),
	}
