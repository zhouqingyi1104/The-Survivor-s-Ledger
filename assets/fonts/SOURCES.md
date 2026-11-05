# Bundled font sources

Acquired on 2026-11-05 from the official repositories below. Font binaries are original upstream bytes: no subsetting, conversion, font installation, or dependency installation. The Noto upstream `Subset/` directory is the upstream Simplified Chinese family release, not a modification made by this project.

All fonts use SIL Open Font License 1.1. `LICENSES.txt` contains both complete upstream license documents, including their original notices, plus each binary's original name-table copyright notice. The Windows build also copies `LICENSES.txt` beside the executable as `字体许可.txt`.

Integrity verification: each expected Git blob ID below was read with `git ls-tree <commit> -- <path>` after a filtered, depth-one fetch from its official repository; the local downloaded bytes were then hashed as `SHA1("blob " + decimal_length + NUL + file_bytes)` and matched exactly. SHA256 is provided independently for local/artifact verification. No API credentials were used.

## LXGWWenKai-Regular.ttf

- Repository: https://github.com/lxgw/LxgwWenKai
- Pin: `v1.530`, commit `4becfb4d5cf0c92cfdb60a6e9b504bda43315325`
- Original upstream path: `fonts/TTF/LXGWWenKai-Regular.ttf`
- Download: https://raw.githubusercontent.com/lxgw/LxgwWenKai/4becfb4d5cf0c92cfdb60a6e9b504bda43315325/fonts/TTF/LXGWWenKai-Regular.ttf
- Internal version: `Version 1.530; October 18, 2026`
- Size: `25,928,940` bytes (24.728 MiB)
- SHA256: `2d73eea94ad808999d90c0000c239a84a33b09d4bc6ab6c5b8bbf1eda8a7fc8b`
- Git blob SHA1: `7f8f031dc5c6c5ba1913d93c36d4667c1e311cea` (verified)
- Complete original license: https://raw.githubusercontent.com/lxgw/LxgwWenKai/4becfb4d5cf0c92cfdb60a6e9b504bda43315325/OFL.txt
- License Git blob SHA1: `bb1634cb03ee7202d5c66bf2754705493bd73e1e` (verified)
- License SHA256: `1a25e35da1031c6c3436fde545bb9cb5aca954e9873afe510c834b8b79bd21a0`


## NotoSansSC-VF.ttf

- Repository: https://github.com/notofonts/noto-cjk
- Pin: `commit pin`, commit `f8d157532fbfaeda587e826d4cd5b21a49186f7c`
- Original upstream path: `Sans/Variable/TTF/Subset/NotoSansSC-VF.ttf`
- Download: https://raw.githubusercontent.com/notofonts/noto-cjk/f8d157532fbfaeda587e826d4cd5b21a49186f7c/Sans/Variable/TTF/Subset/NotoSansSC-VF.ttf
- Internal version: `Version 2.004;hotconv 1.0.118;makeotfexe 2.5.65603`
- Size: `17,773,132` bytes (16.950 MiB)
- SHA256: `d68bafcb48a2707749396aa12bbbd833cb70401f3a9a689fd2902c7e0d295964`
- Git blob SHA1: `5371a543be5fc670c7cdee9760c03554ee3e9b8e` (verified)
- Complete original license: https://raw.githubusercontent.com/notofonts/noto-cjk/f8d157532fbfaeda587e826d4cd5b21a49186f7c/Sans/LICENSE
- License Git blob SHA1: `d952d62c065f3f35fb83a173496e90b21525aef3` (verified)
- License SHA256: `6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2`

## Coverage and use

- Existing `fontTools` 4.65.0 was used read-only; no new package was installed.
- A source-character superset from all `.gd`, `.json`, `.tscn`, and `.tres` files under `scripts/` and `data/` contains 1,941 unique visible characters (comments included). Each of the two bundled fonts independently covers every character in this current set, including the U+2161 ROMAN NUMERAL TWO (`Ⅱ`) pause label. This is a full cmap comparison against the scanned set, with no system font needed for those characters.
- The Noto Sans SC variable font has a `wght` axis from 100 to 900 and a default of 100. The resource entry point selects 400 explicitly for body text and 700 for bold text using the numeric OpenType tag `0x77676874` (decimal `2003265652`). A local Godot 4.7.2 TextServer probe confirmed actual variation coordinates `{ 2003265652: 400 }` and `{ 2003265652: 700 }`; the string alias did not set those coordinates in this runtime. The ignored local probe evidence is `build/fonts-qa/font-metrics-stdout.log`.
- Both FontFile resources disable system fallback and have no fallback-font list. Typeface selection and weight variations use the bundled resources only; all font binary bytes remain unchanged.
- The binary cmap comparison and local axis probe do not establish real-window acceptance or rendering consistency on another machine. Arbitrary player-entered rare characters and emoji are not guaranteed; a machine/VM without system CJK fonts and cross-platform appearance remain separate acceptance work.

Total uncompressed font bytes: `43,702,072` (41.678 MiB).
