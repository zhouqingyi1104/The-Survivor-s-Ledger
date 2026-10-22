import bpy, sys
args = sys.argv[sys.argv.index("--") + 1:]
for path in args:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    print("=====", path.split("/")[-1])
    for ob in bpy.context.scene.objects:
        info = ob.type
        if ob.type == "MESH":
            info += " verts=%d mats=%s groups=%d" % (len(ob.data.vertices), [m.name for m in ob.data.materials], len(ob.vertex_groups))
        if ob.type == "ARMATURE":
            info += " bones=%d" % len(ob.data.bones)
            print("   bones:", len(ob.data.bones), [b.name for b in ob.data.bones][:8])
        print(" ", ob.name, info, "dims=" + str(tuple(round(d, 2) for d in ob.dimensions)))
    acts = [a.name for a in bpy.data.actions]
    print("  actions(%d):" % len(acts), acts)
