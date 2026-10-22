import json, os, sys, urllib.request, posixpath
UA = {"User-Agent": "JieYuLu-prototype/0.4 (asset fetch for a Godot game)"}
OUT = sys.argv[1]
MODELS = ["chinese_cabinet", "chinese_sofa", "chinese_tea_table", "chinese_screen_panels", "chinese_stool",
          "chinese_armchair", "chinese_console_table", "chinese_commode", "chinese_chandelier",
          "ceramic_vase_01", "ceramic_vase_02", "ceramic_vase_03", "ceramic_pot", "folding_wooden_stool", "dead_tree_trunk"]
TEXTURES = ["grey_roof_tiles", "roof_09", "white_stucco", "beige_wall_001", "cobblestone_floor_08",
            "square_cobblestone", "snow_02", "brown_planks_09"]

def get_json(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return json.load(r)

def fetch(url, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r, open(dest, "wb") as f:
        f.write(r.read())
    return os.path.getsize(dest)

def safe_join(base, rel):
    rel = posixpath.normpath(rel)
    if rel.startswith("..") or rel.startswith("/") or ":" in rel:
        raise ValueError("unsafe path: " + rel)
    return os.path.join(base, *rel.split("/"))

total = 0
for mid in MODELS:
    files = get_json(f"https://api.polyhaven.com/files/{mid}")
    g = files["gltf"]["1k"]["gltf"]
    d = os.path.join(OUT, "models", mid)
    total += fetch(g["url"], os.path.join(d, f"{mid}.gltf"))
    for rel, info in g.get("include", {}).items():
        total += fetch(info["url"], safe_join(d, rel))
    print("model", mid, "ok")
for tid in TEXTURES:
    files = get_json(f"https://api.polyhaven.com/files/{tid}")
    d = os.path.join(OUT, "textures", tid)
    for key, short in [("Diffuse", "diff"), ("nor_gl", "nor"), ("arm", "arm")]:
        total += fetch(files[key]["1k"]["jpg"]["url"], os.path.join(d, f"{tid}_{short}.jpg"))
    print("texture", tid, "ok")
print("total bytes", total)
