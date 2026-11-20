extends RefCounted
## 本地 +Z 朝向院子。所有顶点沿墙边依次排列，供地台、屋檐和室内判断共用。

static func footprint(kind: String, w: float, d: float) -> PackedVector2Array:
	var outline: PackedVector2Array
	match kind:
		"hall":
			# 东书斋三面挑出，中厅让进，西卧房成一条向院伸出的翼。
			outline = PackedVector2Array([
				Vector2(-0.50, -0.50), Vector2(0.50, -0.50), Vector2(0.50, 0.42),
				Vector2(0.425, 0.62), Vector2(0.27, 0.62), Vector2(0.19, 0.42),
				Vector2(0.19, 0.25), Vector2(-0.20, 0.25), Vector2(-0.20, 0.80), Vector2(-0.50, 0.80)])
		"kitchen":
			outline = PackedVector2Array([
				Vector2(-0.50, -0.50), Vector2(0.50, -0.50), Vector2(0.50, 0.60),
				Vector2(0.10, 0.60), Vector2(0.10, 0.35), Vector2(-0.50, 0.35)])
		"workshop":
			outline = PackedVector2Array([
				Vector2(-0.50, -0.50), Vector2(0.50, -0.50), Vector2(0.50, 0.35),
				Vector2(0.32, 0.60), Vector2(-0.28, 0.60), Vector2(-0.50, 0.24)])
	for i in outline.size():
		outline[i] *= Vector2(w, d)
	return outline
