"""cs-studio 中式铺面：FBX → GLB。Unity 材质丢了，按材质名里的编号接上贴图 LowpolyChineseBuilding_Texture_0N.png。
用法：blender -b --factory-startup --python bl_fbx2glb.py -- <贴图目录> <输出目录> <fbx...>"""
import bpy, sys, os, re
args = sys.argv[sys.argv.index("--") + 1:]
tex_dir, out_dir, fbxs = args[0], args[1], args[2:]
for spec in fbxs:
    # "路径|贴图编号|输出名"
    path, tex_num, out_name = spec.split("|")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=path)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for m in bpy.data.materials:
        if not m.users:
            continue
        img_path = os.path.join(tex_dir, "LowpolyChineseBuilding_Texture_%02d.png" % int(tex_num))
        if not os.path.exists(img_path):
            print("no texture for", m.name)
            continue
        m.use_nodes = True
        nt = m.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(img_path)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.85
    for o in meshes:
        print(os.path.basename(path), o.name, "dims", [round(d, 2) for d in o.dimensions], "scale", [round(x, 4) for x in o.scale])
    out = os.path.join(out_dir, out_name + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_animations=False)
