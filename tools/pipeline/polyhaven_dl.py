import json, os, sys, urllib.request, posixpath
from pathlib import Path
UA = {"User-Agent": "JieYuLu-prototype/0.4 (asset fetch for a Godot game)"}
OUT = sys.argv[1]
MODELS = ["chinese_cabinet", "chinese_sofa", "chinese_tea_table", "chinese_screen_panels", "chinese_stool",
          "chinese_armchair", "chinese_console_table", "chinese_commode", "chinese_chandelier",
          "ceramic_vase_01", "ceramic_vase_02", "ceramic_vase_03", "ceramic_pot", "folding_wooden_stool", "dead_tree_trunk"]
TEXTURES = ["grey_roof_tiles", "roof_09", "white_stucco", "beige_wall_001", "cobblestone_floor_08",
            "square_cobblestone", "snow_02", "brown_planks_09", "rock_face_03", "brown_mud_dry",
            "rock_01", "brick_wall_09"]

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

def bind_packed_occlusion(path):
    """Poly Haven ARM maps store occlusion in red. A plain roughness map does not."""
    path = Path(path)
    model = json.loads(path.read_text(encoding="utf-8"))
    changed = False
    for material in model.get("materials", []):
        packed = material.get("pbrMetallicRoughness", {}).get("metallicRoughnessTexture")
        if not packed or "occlusionTexture" in material:
            continue
        tex = model["textures"][packed["index"]]
        uri = model["images"][tex["source"]].get("uri", "")
        if "_arm_" in posixpath.basename(uri).lower():
            material["occlusionTexture"] = dict(packed, strength=0.8)
            changed = True
    if changed:
        path.write_text(json.dumps(model, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")

total = 0
for mid in MODELS:
    files = get_json(f"https://api.polyhaven.com/files/{mid}")
    g = files["gltf"]["1k"]["gltf"]
    d = os.path.join(OUT, "models", mid)
    model_path = os.path.join(d, f"{mid}.gltf")
    total += fetch(g["url"], model_path)
    bind_packed_occlusion(model_path)
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
