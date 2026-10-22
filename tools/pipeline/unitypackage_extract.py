"""解开 .unitypackage（本质是 tar.gz：每个资源一个目录，里面 pathname 记路径、asset 是文件本体）。
用法：python -I unitypackage_extract.py <包.unitypackage> <输出目录>"""
import os, sys, tarfile

pkg, out = sys.argv[1], os.path.abspath(sys.argv[2])
with tarfile.open(pkg, "r:gz") as tar:
    members = {m.name: m for m in tar.getmembers()}
    for name, m in members.items():
        if not name.endswith("/pathname"):
            continue
        rel = tar.extractfile(m).read().decode("utf-8").splitlines()[0].strip()
        asset = members.get(name[: -len("pathname")] + "asset")
        if asset is None or not asset.isfile():
            continue
        dest = os.path.abspath(os.path.join(out, rel))
        if not dest.startswith(out + os.sep):
            print("跳过可疑路径：", rel)
            continue
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as f:
            f.write(tar.extractfile(asset).read())
        print(rel)
