"""itch.io 免费（自定一价，可填 0）资源的标准下载流程：
purchase 页取 csrf → POST download_url 拿到下载页 → 下载页列出文件 → POST file/<id> 拿到带签名的地址 → 下载。
用法：python -I itch_dl.py <页面地址> <输出目录> [只下载文件名包含的关键词...]"""
import http.cookiejar, json, os, re, sys, urllib.parse, urllib.request

page, out = sys.argv[1].rstrip("/"), sys.argv[2]
wanted = sys.argv[3:]
jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"

def req(url, data=None, xhr=False):
    headers = {"User-Agent": UA}
    if xhr:
        headers["X-Requested-With"] = "XMLHttpRequest"
    body = urllib.parse.urlencode(data).encode() if data is not None else None
    with opener.open(urllib.request.Request(url, data=body, headers=headers), timeout=120) as r:
        return r.read()

html = req(page + "/purchase").decode("utf-8", "replace")
csrf = re.search(r'<meta name="csrf_token" value="([^"]+)"', html).group(1)
dl_page = json.loads(req(page + "/download_url", {"csrf_token": csrf}, xhr=True))["url"]
html = req(dl_page).decode("utf-8", "replace")
csrf = re.search(r'<meta name="csrf_token" value="([^"]+)"', html).group(1)
key = urllib.parse.unquote(dl_page.rstrip("/").split("/")[-1])
uploads = []
for block in html.split('<div class="upload">')[1:]:
    uid = re.search(r'data-upload_id="(\d+)"', block)
    name = re.search(r'<strong[^>]*title="([^"]+)"', block)
    if uid and name:
        uploads.append((uid.group(1), name.group(1)))
os.makedirs(out, exist_ok=True)
for uid, name in uploads:
    if wanted and not any(w in name for w in wanted):
        print("skip", name)
        continue
    info = json.loads(req(f"{page}/file/{uid}?" + urllib.parse.urlencode({"source": "game_download"}), {"csrf_token": csrf}, xhr=True))
    if "url" not in info:
        print("failed", name, info)
        continue
    safe = os.path.basename(name).replace("..", "_")
    dest = os.path.join(out, safe)
    with opener.open(urllib.request.Request(info["url"], headers={"User-Agent": UA}), timeout=600) as r, open(dest, "wb") as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    print("got", safe, os.path.getsize(dest))
