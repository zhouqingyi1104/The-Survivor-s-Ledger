#!/usr/bin/env python3
"""IL2CPP global-metadata.dat 解析：把类型名 / 方法名 / 字段名抽出来，用来列功能清单。

只读元数据，不碰 GameAssembly.dll 的原生代码。IL2CPP 元数据格式随版本变化，
这里按 v31 的布局硬编码偏移；解析不出来就明说，不猜。
"""
import struct
import sys
import json
from collections import Counter, defaultdict

PATH = sys.argv[1] if len(sys.argv) > 1 else (
    "D:/program files (x86)/steam/steamapps/common/Survival Log/"
    "SurvivalLog_Data/il2cpp_data/Metadata/global-metadata.dat")

data = open(PATH, "rb").read()
print("文件大小 %.1f MB" % (len(data) / 1048576.0))

# ---- 头部 ----
magic, version = struct.unpack_from("<II", data, 0)
print("magic=0x%08x version=%d" % (magic, version))
if magic != 0xFAB11BAF:
    print("不是 IL2CPP 元数据（magic 不对）")
    sys.exit(1)

# v31 头部布局（Il2CppGlobalMetadataHeader）
# 0:magic 4:version 之后是一串 size/offset 对
HDR = [
    "stringLiteral", "stringLiteralData", "string", "events", "properties",
    "methods", "parameterDefaultValues", "fieldDefaultValues", "fieldAndParameterDefaultValueData",
    "parameterInfos", "genericInstances", "genericContainers", "nestedTypes", "interfaces",
    "vtable", "interfaceOffsets", "typeDefinitions", "images", "assemblies",
    "fieldRefs", "referencedAssemblies", "attributeData", "attributeDataRange",
    "unresolvedIndirectCallParameterTypes", "unresolvedIndirectCallParameterRanges",
    "windowsRuntimeTypeNames", "windowsRuntimeStrings", "exportedTypeDefinitions",
    ("fieldOffsets", 2),  # v29+ 是两个字段
]
off = 8
fields = {}
for name in HDR:
    if isinstance(name, tuple):
        for n in name:
            fields[n] = struct.unpack_from("<II", data, off)
            off += 8
    else:
        fields[name] = struct.unpack_from("<II", data, off)
        off += 8

for k in ("typeDefinitions", "string", "methods", "images", "assemblies"):
    print("  %-16s size=%-10d offset=%d" % (k, fields[k][0], fields[k][1]))


def idx_list(offset, size, stride):
    return [struct.unpack_from("<I", data, offset + i * stride)[0] for i in range(size)]


def cstr(off_in_data):
    end = data.index(b"\0", off_in_data)
    return data[off_in_data:end].decode("utf-8", "replace")


# ---- 字符串表：string 区每项 8 字节 {length, dataIndex} ----
str_size, str_off = fields["string"]
strs = []
for i in range(str_size):
    length, di = struct.unpack_from("<II", data, str_off + i * 8)
    strs.append(cstr(str_off + di))

# ---- 图片（程序集）表：每项 40 字节，nameIndex 在偏移 0 ----
img_size, img_off = fields["images"]
images = []
for i in range(img_size):
    name_idx = struct.unpack_from("<i", data, img_off + i * 40)[0]
    images.append(strs[name_idx] if 0 <= name_idx < len(strs) else "?")

# ---- 类型定义表：每项 116 字节（v31）----
# nameIndex(0) namespaceIndex(4) ...
td_size, td_off = fields["typeDefinitions"]
STRIDE = 116
types = []
for i in range(td_size):
    b = td_off + i * STRIDE
    name_idx, ns_idx = struct.unpack_from("<ii", data, b)
    name = strs[name_idx] if 0 <= name_idx < len(strs) else "?"
    ns = strs[ns_idx] if 0 <= ns_idx < len(strs) else ""
    types.append((ns, name))

print("\n类型总数：%d" % len(types))

# ---- 方法表：每项 48 字节（v31），nameIndex 在偏移 0 ----
m_size, m_off = fields["methods"]
MSTRIDE = 48
methods = []
for i in range(m_size):
    name_idx = struct.unpack_from("<i", data, m_off + i * MSTRIDE)[0]
    methods.append(strs[name_idx] if 0 <= name_idx < len(strs) else "?")

print("方法总数：%d" % len(methods))

# ---- 汇总 ----
ns_counter = Counter(ns for ns, _ in types if ns)
print("\n命名空间 Top 40（按类型数）：")
for ns, n in ns_counter.most_common(40):
    print("  %-52s %d" % (ns, n))

# 只看业务命名空间（排除系统/第三方）
SKIP_PREFIX = ("System", "Unity", "UnityEngine", "Mono", "Microsoft", "Internal",
               "JetBrains", "Newtonsoft", "Unity.Collections", "Unity.Entities",
               "Unity.Mathematics", "Unity.Burst", "Unity.Jobs", "Unity.Profiling",
               "Unity.Logging", "Unity.Baselib", "TMPro", "Unity.TextMeshPro",
               "UnityEditor", "Facebook", "Firebase", "Google", "Sentry",
               "Steamworks", "FMOD", "AstarPathfindingProject", "Cinemachine",
               "DOTween", "YooAsset", "MemoryPack", "MessagePack", "Vuplex",
               "Newtonsoft.Json", "Unity.AI.Navigation", "Unity.RenderPipelines")
biz = [(ns, n) for ns, n in types
       if ns and not ns.startswith(SKIP_PREFIX) and not ns.startswith("mscorlib")]
biz_ns = Counter(ns for ns, _ in biz)
print("\n业务命名空间 %d 个，业务类型 %d 个：" % (len(biz_ns), len(biz)))
for ns, n in biz_ns.most_common(60):
    print("  %-52s %d" % (ns, n))

out = {
    "counts": {"types": len(types), "methods": len(methods), "images": len(images)},
    "images": images,
    "namespaces": dict(ns_counter),
    "business_namespaces": dict(biz_ns),
    "business_types": ["%s.%s" % (ns, n) for ns, n in biz],
}
with open("D:/meta_types.json", "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
print("\n已写 D:/meta_types.json")
