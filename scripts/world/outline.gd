extends RefCounted
## 悬停描边：给物件的每个网格挂一层外扩的单色背面（material_overlay），不影响共用材质。

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_opaque;
uniform vec4 outline_color : source_color = vec4(1.0, 0.83, 0.38, 1.0);
uniform float grow = 0.035;
void vertex() {
	VERTEX += NORMAL * grow;
}
void fragment() {
	ALBEDO = outline_color.rgb;
}
"""

static var _mat: ShaderMaterial


static func material() -> ShaderMaterial:
	if _mat == null:
		var sh := Shader.new()
		sh.code = SHADER
		_mat = ShaderMaterial.new()
		_mat.shader = sh
	return _mat


static func set_outline(node: Node, on: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is GeometryInstance3D and not (node is Label3D):
		(node as GeometryInstance3D).material_overlay = material() if on else null
	for c in node.get_children():
		set_outline(c, on)
