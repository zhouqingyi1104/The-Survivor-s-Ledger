"""给 Quaternius 基础人物"穿衣"：从身体网格派生贴身衣裤（保留蒙皮权重，跟着动画动），
长袍版再加一圈蒙皮下摆；挂上发型；导出 GLB（不带动画，动画在 Godot 里共用动画库）。
用法：blender -b --factory-startup --python bl_dress.py -- <身体.gltf> <发型.gltf> <输出.glb> <short|long>"""
import bpy, bmesh, sys, math
from mathutils import Vector

body_path, hair_path, out_path, variant = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


def import_gltf(path):
    before = set(scene.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in scene.objects if o not in before]


def delete(objs):
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)


objs = import_gltf(body_path)
arm = [o for o in objs if o.type == "ARMATURE"][0]
delete([o for o in objs if o.type == "MESH" and o.name.startswith("Icosphere")])
body = max([o for o in scene.objects if o.type == "MESH"], key=lambda o: len(o.data.vertices))
body.name = "Body"

# 发型：换到主骨架上
new = import_gltf(hair_path)
for o in new:
    if o.type == "MESH" and not o.name.startswith("Icosphere"):
        o.parent = arm
        for m in o.modifiers:
            if m.type == "ARMATURE":
                m.object = arm
        o.name = "Hair"
delete([o for o in new if o.type == "ARMATURE" or o.name.startswith("Icosphere")])

EXPOSED = ("Head", "neck_01", "hand_", "index_", "middle_", "pinky_", "ring_", "thumb_", "foot_", "ball_")
LEGS = ("thigh_", "calf_")
FEET = ("foot_", "ball_")


def group_sets(ob, prefixes):
    return {vg.index for vg in ob.vertex_groups if vg.name.startswith(prefixes)}


def weight_of(v, idx):
    return sum(g.weight for g in v.groups if g.group in idx)


# 衣服层：复制身体
clothes = body.copy()
clothes.data = body.data.copy()
clothes.name = "Clothes"
scene.collection.objects.link(clothes)
exposed = group_sets(clothes, EXPOSED)
legs = group_sets(clothes, LEGS)
feet = group_sets(body, FEET)
body_exposed = group_sets(body, EXPOSED)

me = clothes.data
drop = [v.index for v in me.vertices if weight_of(v, exposed) > 0.45]
leg_w = {v.index: weight_of(v, legs) for v in me.vertices}
bm = bmesh.new()
bm.from_mesh(me)
bm.verts.ensure_lookup_table()
# 先在完整网格上抹平肌肉线条、往外撑开一层（法线连续，不会起刺），最后再切掉头手脚
for _ in range(6):
    bmesh.ops.smooth_vert(bm, verts=bm.verts, factor=0.4, use_axis_x=True, use_axis_y=True, use_axis_z=True)
bm.normal_update()
for v in bm.verts:
    v.co += v.normal * 0.014
bm.verts.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[bm.verts[i] for i in drop], context="VERTS")
bm.to_mesh(me)
bm.free()

robe_mat = bpy.data.materials.new("Robe")
robe_mat.diffuse_color = (0.35, 0.42, 0.5, 1)
pants_mat = bpy.data.materials.new("Pants")
pants_mat.diffuse_color = (0.18, 0.16, 0.15, 1)
shoes_mat = bpy.data.materials.new("Shoes")
shoes_mat.diffuse_color = (0.08, 0.07, 0.07, 1)
me.materials.clear()
me.materials.append(robe_mat)
me.materials.append(pants_mat)
for poly in me.polygons:
    vs = [me.vertices[i] for i in poly.vertices]
    lw = sum(weight_of(v, legs) for v in vs) / len(vs)
    poly.material_index = 1 if lw > 0.5 else 0

# 身体：被衣服盖住的地方删掉（免得动作大时穿模），脚换成鞋的材质
bm = bmesh.new()
bm.from_mesh(body.data)
bm.verts.ensure_lookup_table()
deform = bm.verts.layers.deform.active
covered = [v for v in bm.verts if sum(w for g, w in v[deform].items() if g in body_exposed) < 0.3]
bmesh.ops.delete(bm, geom=covered, context="VERTS")
bm.to_mesh(body.data)
bm.free()
body.data.materials.append(shoes_mat)
shoe_index = len(body.data.materials) - 1
for poly in body.data.polygons:
    vs = [body.data.vertices[i] for i in poly.vertices]
    if sum(weight_of(v, feet) for v in vs) / len(vs) > 0.5:
        poly.material_index = shoe_index

# 长袍下摆：从骨盆垂到小腿的一圈，上沿跟骨盆，越往下越跟大腿
if variant == "long":
    bones = arm.data.bones
    mw = arm.matrix_world
    pelvis = mw @ bones["pelvis"].head_local
    thigh_l = mw @ bones["thigh_l"].head_local
    calf_l = mw @ bones["calf_l"].head_local
    foot_l = mw @ bones["foot_l"].head_local
    top = pelvis.z + 0.02
    bottom = foot_l.z + 0.16
    cx, cy = pelvis.x, pelvis.y
    left_sign = 1.0 if thigh_l.x > cx else -1.0
    seg, rings = 28, 10
    bm = bmesh.new()
    grid = []
    for r in range(rings + 1):
        t = r / rings
        z = top + (bottom - top) * t
        rx = 0.2 + 0.13 * t
        ry = 0.16 + 0.12 * t
        ring = []
        for s in range(seg):
            a = 2 * math.pi * s / seg
            ring.append(bm.verts.new((cx + math.cos(a) * rx, cy + math.sin(a) * ry, z)))
        grid.append(ring)
    for r in range(rings):
        for s in range(seg):
            a, b = grid[r][s], grid[r][(s + 1) % seg]
            c, d = grid[r + 1][(s + 1) % seg], grid[r + 1][s]
            bm.faces.new((a, b, c, d))
    skirt_me = bpy.data.meshes.new("Skirt")
    bm.to_mesh(skirt_me)
    bm.free()
    skirt = bpy.data.objects.new("Skirt", skirt_me)
    scene.collection.objects.link(skirt)
    skirt_me.materials.append(robe_mat)
    for p in skirt_me.polygons:
        p.use_smooth = True
    vg_p = skirt.vertex_groups.new(name="pelvis")
    vg_l = skirt.vertex_groups.new(name="thigh_l")
    vg_r = skirt.vertex_groups.new(name="thigh_r")
    vg_cl = skirt.vertex_groups.new(name="calf_l")
    vg_cr = skirt.vertex_groups.new(name="calf_r")
    knee_t = (top - calf_l.z) / (top - bottom)
    for v in skirt_me.vertices:
        t = (top - v.co.z) / (top - bottom)
        side = max(-1.0, min(1.0, (v.co.x - cx) / 0.2 * left_sign))
        follow = min(0.85, t * 1.1)
        wl = follow * (0.5 + 0.5 * side)
        wr = follow * (0.5 - 0.5 * side)
        vg_p.add([v.index], 1.0 - follow, "REPLACE")
        if t > knee_t:
            k = min(1.0, (t - knee_t) / max(0.01, 1.0 - knee_t)) * 0.5
            vg_l.add([v.index], wl * (1 - k), "REPLACE")
            vg_cl.add([v.index], wl * k, "REPLACE")
            vg_r.add([v.index], wr * (1 - k), "REPLACE")
            vg_cr.add([v.index], wr * k, "REPLACE")
        else:
            vg_l.add([v.index], wl, "REPLACE")
            vg_r.add([v.index], wr, "REPLACE")
    skirt.parent = arm
    mod = skirt.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    solid = skirt.modifiers.new("Solidify", "SOLIDIFY")
    solid.thickness = 0.012

bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", export_animations=False, export_apply=True)
print("exported", out_path)
