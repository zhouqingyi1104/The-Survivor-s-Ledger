# 美术与声音素材清单

> **现状（2026-10-24）**：第一、六、七节的素材都已下载并接入游戏；第二节（Sketchfab，要登录）一件都没下；第八节的主角女身是 2026-10-23 另行接入的。
> 第一到第五节保留的是 2026-10-22 的调研记录，"推荐下载"等字样是当时的说法。

> 原则：只用**允许商用**的公开资源。首选 CC0（公有领域，不用署名），其次 CC-BY（要署名）。
> 不用 NonCommercial（禁止商用）、不用引用他人 IP 的同人模型、**不提取原版《生存日志》的任何美术资产**。
> 调研日期：2026-10-22。下载前请再确认一次各页面上的许可证。

## 一、推荐下载（可以直接用 curl 下载）

### 1. Poly Haven（CC0，写实 PBR）—— 室内家具、贴图

来源：<https://polyhaven.com>，许可证 CC0，可商用、不用署名。格式选 glTF + 1K 贴图。

| 资源 id | 用在哪 | 大小（1K） |
|---|---|---|
| `chinese_cabinet` 中式柜 | 储物柜 | 2.3 MB |
| `chinese_sofa` 中式榻 | 正屋的罗汉床 / 床榻 | 1.6 MB |
| `chinese_tea_table` 中式茶几 | 书案旁、正屋 | 1.6 MB |
| `chinese_screen_panels` 中式屏风 | 正屋神龛后 | 1.7 MB |
| `chinese_stool` 中式凳 | 书案、灶房 | 约 1.5 MB（未核实） |
| `chinese_armchair` 中式扶手椅 | 正屋 | 约 1.5 MB（未核实） |
| `chinese_console_table` 中式条案 | 神龛供桌 | 约 1.5 MB（未核实） |
| `chinese_commode` 中式矮柜 | 卧处 | 约 1.5 MB（未核实） |
| `chinese_chandelier` 中式吊灯 | 正屋檐下宫灯 | 约 1.5 MB（未核实） |
| `ceramic_vase_01`～`03`、`ceramic_pot` 陶瓷瓶罐 | 陈设、米缸、水缸 | 每个约 1.5 MB（未核实） |
| `folding_wooden_stool` 木折凳 | 院中 | 约 1.5 MB（未核实） |
| `dead_tree_trunk` 枯树干 | 柴垛、院外 | 约 3 MB（未核实） |

贴图（JPG 1K：颜色 + 法线 + ARM，每套约 1.3 MB）：

| 资源 id | 用在哪 |
|---|---|
| `grey_roof_tiles`、`roof_09`（弧形陶瓦） | 黛瓦屋顶 |
| `white_stucco`、`beige_wall_001` | 粉墙 |
| `cobblestone_floor_08`、`square_cobblestone` | 院内青石板、街道 |
| `snow_02` | 雪地 |
| `brown_planks_09` | 木作、门板 |

小计：约 30 MB（模型）+ 约 12 MB（贴图）。

### 2. cs-studio「Low Poly Chinese Style Building Set 1 [FREE]」—— 临川城的铺子

来源：<https://cs-studio.itch.io/cs-building-set1>，免费（自定一价，可填 0）。
**许可证不是 CC0**：可用于免费和商业项目、可修改、不用署名，**但不得再分发或转卖素材本身**（打包进游戏可以，素材原文件不能公开传播，比如不能放进公开的 Git 仓库）。

| 文件 | 内容 | 大小 |
|---|---|---|
| `AncientChina_set_1.unitypackage` | 书肆、肉铺、布庄、凉亭、马房 5 栋（带材质贴图） | 3.4 MB |

本质是 tar.gz，用 Python 解包得到 FBX，再用 Blender 转 glTF。

### 3. Quaternius（CC0）—— 带骨骼的人物和动画

来源：<https://quaternius.com>，许可证 CC0。免费档是 itch.io 上"自定一价"的 Standard 版。

| 文件 | 内容 | 大小 |
|---|---|---|
| `Universal Animation Library[Standard].zip` | 45 个人形动画（走、跑、坐、死亡……），FBX / GLB | 15 MB |
| `Universal Base Characters[Standard].zip` | 2 个基础体型 + 5 种发型，人形骨骼可重定向 | 122 MB |
| `Modular Character Outfits - Fantasy[Standard].zip`（可选） | 免费的有"农夫""游侠"两套服装，glTF | 280 MB |

用法：在 Blender 里把动画套到人物上、换上服装、改配色，导出 GLB 给 Godot。
主角、街上的百姓都用它；僵尸用同一副骨骼，套上官帽、黄符，配僵直的蹦跳动作。

## 二、可选（要登录 Sketchfab 才能下载，需要你自己下）

Sketchfab 的下载需要登录账号，我不能代为注册或登录。以下都是 **CC-BY**，用的话要在游戏里署名：

| 模型 | 作者 | 面数 | GLB 大小 | 用途 |
|---|---|---|---|---|
| [Chinese ancient building](https://sketchfab.com/3d-models/dea5596f50ce4235a67b11aa2678fce4) | LSDWaterPipe | 1.3 万 | 27 MB | 城里的楼阁 |
| [Low poly Chinese city](https://sketchfab.com/3d-models/faf480ecd57d4c8e9a2836f5c02c4d00) | smooth998 | 35 万 | 31 MB | 临川城远景 |
| [Old Chinese Rice Wine Brewery](https://sketchfab.com/3d-models/d531e13126e5420e84ec499aa57209de) | SeppeHauspie | 28 万 | 16 MB | 外出地点（酒坊） |
| [chinese umbrella](https://sketchfab.com/3d-models/ad8e821e552d4b25a3684f6a8673afd3) | local.yany | 20 万 | 12 MB | 陈设 |
| [Chibi Ancient Chinese Zombie (jiangshi)](https://sketchfab.com/3d-models/546f763f00654b428d13ad0e5c37f274) | xiamilisite | 14 万 | — | 僵尸（Q 版，风格可能不搭） |

## 三、排除的

- `Chinese Hall`（Sketchfab）：CC BY-NC-SA，禁止商用。
- "Heavenly Palace" dome：CC BY-NC，禁止商用。
- `Agnes Jiangshi` 等：动漫角色的同人模型，有 IP 风险。
- cs-studio 的其他中式建筑包、各商店的中式四合院：付费。
- 汉服模型（Sketchfab）：静态高模、不带骨骼，做不了动画。

## 四、Blender（已安装 5.2.1 LTS）能做的

1. FBX → glTF 统一转换（cs-studio 的铺面）。
2. 人物合成：基础体型 + 服装 + 发型，套上动画库，导出带动画的 GLB。
3. 用 Blender 脚本建模公开资源里缺的中式构件：带弧度、起翘的屋顶，马头墙，门楼，漏窗。
4. Godot 可以直接导入 `.blend` 文件（编辑器设置里填 Blender 路径）。

## 五、署名

CC-BY 的资源用上以后，在游戏的"制作名单"里写明：模型名、作者、许可证、链接。CC0 的不强制，但会一并列出致谢。

## 六、接入情况（v0.4，2026-10-22）

第一部分（Poly Haven、cs-studio、Quaternius 两个 Standard 包）已下载并接入；Quaternius 服装包和 Sketchfab 的资源都没下。

| 素材 | 用在哪 | 代码 |
|---|---|---|
| Poly Haven 家具 | 正屋：条案作神龛供桌、屏风、两把圈椅、宫灯；罗汉榻作床（睡觉、小憩时人躺上去）；书案用茶几 + 方凳；储物柜；院里折凳、枯树干，各处瓷瓶瓷罐 | `home_world.gd` 的 `_furniture()` / `_decor()`，经 `assets.gd` 的 `prop()` 加载并按包围盒加碰撞 |
| Poly Haven 贴图 | 粉墙 `white_stucco`、雪地 `snow_02`、青石板 `cobblestone_floor_08` / `square_cobblestone`、木作 `brown_planks_09`、屋顶 `grey_roof_tiles` | `kit.gd` 的 `PBR` 表 → `assets.gd` 的 `pbr()`（世界坐标三面投影，不用 UV） |
| cs-studio 铺面 | 书肆、菜市、当铺、杂货铺、营造坊、青云观（同一批模型换配色、转朝向），南岸河边的凉亭 | `city_world.gd` 的 `MODEL_SHOPS`；缺文件时退回代码拼的厅堂 |
| Quaternius 人物 | 街上百姓（男女）、僵尸；v0.4 时也用作主角（2026-10-23 起主角改用第八节的女身）。同一副骨骼，四个体型（男 / 女 × 短褂 / 长袍） | `character.gd`（换色、冠帽黄符灯笼挂骨骼、动作状态机、僵尸平举双臂的骨骼修改器） |
| Quaternius 动画库 | 走、正式步、待机、提灯、干活（蹲、跪修、捡拾、施法）、坐、倒地 | 所有人物共用一份 `AnimationLibrary`，不做重定向 |

下载了没用上的：`chinese_commode`（4.5 米宽，宅子里放不下）、`roof_09`、`beige_wall_001`。

### 怎么重新生成（脚本在 `tools/pipeline/`）

```bash
# 1. Poly Haven：15 个模型 + 8 套贴图（1K），写到 assets/third_party/polyhaven/
python -I tools/pipeline/polyhaven_dl.py assets/third_party/polyhaven

# 2. cs-studio：itch.io 领取（免费）→ 解包 → FBX 转 GLB（"FBX|贴图编号|输出名"）
python -I tools/pipeline/itch_dl.py https://cs-studio.itch.io/cs-building-set1 assets/third_party/cs_studio
python -I tools/pipeline/unitypackage_extract.py assets/third_party/cs_studio/AncientChina_set_1.unitypackage assets/third_party/cs_studio/raw
blender -b --factory-startup --python tools/pipeline/bl_fbx2glb.py -- <Textures 目录> assets/models/buildings \
  "<Models>/SM_Bookstore_01.fbx|4|bookstore" "<Models>/SM_Bookstore_01.fbx|5|bookstore_green" \
  "<Models>/SM_Butcher_01.fbx|3|butcher" "<Models>/SM_Clothing_Store_01.fbx|4|clothing_store" \
  "<Models>/SM_Clothing_Store_01.fbx|3|clothing_store_brown" "<Models>/SM_Gazeebo_01.fbx|5|gazebo" \
  "<Models>/SM_Horse_Room_01.fbx|3|horse_room"

# 3. Quaternius：itch.io 领取两个 Standard 包，解压到 assets/third_party/quaternius/raw/，
#    动画库 UAL1_Standard.glb 复制到 assets/third_party/quaternius/ual/；人物换装（体型 + 发型 → 输出，short|long）
blender -b --factory-startup --python tools/pipeline/bl_dress.py -- \
  "<Base Characters>/Godot - UE/Superhero_Male_FullBody.gltf" "<Hairstyles>/Rigged to Head Bone/glTF (Godot -Unreal)/Hair_Buzzed.gltf" \
  assets/models/characters/male_short.glb short
#    male_long 用同样的身体和发型、最后一个参数 long；female_short / female_long 用 Superhero_Female_FullBody + Hair_Buns。
```

`.gitignore` 排除了 cs-studio 的原始包和 `assets/models/buildings/`（许可证不许再分发素材本身），以及 Quaternius 的压缩包和解包目录。

### 还能做的

- 百姓和僵尸用的 Quaternius 人物是"超级英雄"体型，袍服从身体网格派生，近看偏紧身；以后可以换 Quaternius 服装包（280 MB，要另行同意下载）或在 Blender 里做宽袖长袍。
- 米行、铁匠铺、药铺、家宅还是代码拼的；cs-studio 其他中式建筑包是付费的。
- 写实家具（Poly Haven）和低多边形铺面（cs-studio）风格不完全一致，可以统一调色或加一层描边 / 色调后处理拉近。

## 七、声音（v0.4，2026-10-22）

全部是 CC0（可商用、不用署名，制作名单里一并致谢），原始包在 `assets/third_party/audio/`（`.gdignore`，引擎不导入），
挑出来转好的 OGG 在 `assets/audio/`（约 4.3 MB）。

| 来源 | 内容 | 用在哪 |
|---|---|---|
| [BiteMe Games · Chinese Game Music](https://bitemegames.itch.io/chinese-game-music)（itch.io，自定一价） | 古筝、笛、鼓两首，各约 1 分钟可循环：Lotus Pond（平静）、Dragon Dance（激战） | 标题、城里、宅院白天；尸潮演出 |
| [Kenney · RPG Audio](https://kenney.nl/assets/rpg-audio) | 钱币、翻书、门、吱呀、锅、刀、布料、皮具 | 买卖、读书、出门、做饭、翻找、睡觉 |
| [Kenney · Impact Sounds](https://kenney.nl/assets/impact-sounds) | 雪地 / 石板 / 木地板脚步，木头、木板、软物、拳、钟的撞击 | 脚步（按踩的地面换）、砸门、营造敲打、倒地、晨钟 |
| [Kenney · Interface Sounds](https://kenney.nl/assets/interface-sounds) | 点击、开合、出错、确认 | 按钮、弹窗、做不了的事 |
| [OpenGameArt · Zombies Sound Pack](https://opengameart.org/content/zombies-sound-pack)（artisticdude） | 24 声僵尸低吼 | 尸潮演出、废墟里被嗅到 |
| [OpenGameArt · Wind](https://opengameart.org/content/wind)（IgnasD） | 三阵风 | 夜里偶尔一阵风 |
| [OpenGameArt · Fireplace Sound Loop](https://opengameart.org/content/fireplace-sound-loop)（PagDev） | 柴火噼啪（循环） | 生火做饭、夜里烧炭 |
| 程序合成（`tools/pipeline/synth_sfx.py`） | 梆子、更鼓、赶尸铃、铜锣、风雪（可无缝循环）、打水、喝水 | 打更、尸潮开锣、夜里远处的铃声、环境风雪、打水 |

重新生成：

```bash
python -I tools/pipeline/synth_sfx.py <合成输出目录>
python -I tools/pipeline/build_audio.py assets/third_party/audio/raw <合成输出目录> assets/audio
```

（需要 ffmpeg。下载用的是 kenney.nl / opengameart.org 的直链和 `tools/pipeline/itch_dl.py`，解压后放进 `assets/third_party/audio/raw/<来源>/`。）

游戏里怎么响（`scripts/autoload/audio.gd`，自动加载为 `Sfx`）：
- 三条总线：配乐、音效、风声环境，音量在"设置"里调，存在 meta 里。
- 脚步按动作的步点响，屋里木地板、院里石板、城里雪地各一种声音；跑起来步点自然变密。
- 宅院白天低低一点古筝、入夜只剩风雪；戌时一更起，每更先一声更鼓再按更数敲梆子；夜里偶尔一阵风、远处一声赶尸铃。
- 尸潮来时开锣、换激战曲，僵尸低吼和砸门声在 3D 里定位。

## 八、主角女身（413 Games，CC0，2026-10-23 接入）

| 项 | 内容 |
|---|---|
| 来源 | [Anime Maid Character by 413 Games](https://413games.itch.io/maid-character)，CC0 1.0；许可证原文和获取记录在 `assets/third_party/413games/SOURCE-LICENSE.txt`、`NOTICE.txt` |
| 文件 | `assets/third_party/413games/`：`base-motion-v7.glb`（女仆装）和 moon 一套（戴尖帽、换配色） |
| 改动 | 只重绑贴图、转 GLB，几何体保持原样。moon 的配色和尖帽是本项目自己做的，**尖帽不属于第三方素材，也不以 CC0 再发布** |
| 用在哪 | 主角（`character.gd` 里 `hero = true`）一律用女身 moon 那套，再加本项目的"仙气"装束：披帛、腰绦、步摇、灵光，配色月白 / 青灰。想换回女仆装只改 `character.gd` 里一个值 |
| 动画 | 这套是 Mixamo 骨架，用模型自带的 `Camp_*` 动作；Quaternius 那套照旧用 UAL 动画库（`character.gd` 的 `RIGS` 表分开处理） |
| 注意 | `NOTICE.txt` 写明：开发机上另下的 MMD 角色包**不是**这套素材，没有清过商用授权，不在仓库里也不能放进游戏 |
| 检查工具 | `tests/hero_shot.tscn` 从几个角度拍主角，`tests/check_hero.tscn` 逐项报挂件在不在、挂在哪 |

标题页"制作名单"（`data/credits.json`）已列 413 Games，并写明尖帽和仙气装束是本作自己做的。

## 九、图标（代码绘制，没有第三方素材）

57 件物品和 18 件家具的图标全部由 `scripts/ui/icon_art.gd` 用 CanvasItem 现画（墨线 + 淡彩），不用任何图片；`icon_view.gd` 负责显示。背包、灶房、添置家具三处在用。要换成手绘图，把 `icon_art.gd` 换成贴图查表即可。
