# Steam 首发录入单

以下字段对应《劫余录》Windows 单人离线版，候选源码为 `c5a7deb`。商店字段、当前售价与审核状态以实际 Steamworks 应用为准。

## 商店页

| 后台字段 | 内容 |
|---|---|
| 产品名 | 简体中文用「劫余录」，英文用「The Survivor's Ledger」。 |
| 游戏描述、抢先体验六问 | [简体中文字段](store-zh-CN.md) · [English store fields](store-en.md)。每个标题下面是该字段的正文，录入时仅复制正文。当前尚无确定的正式版日期或调价方案。 |
| 类型与标签 | 建议选择独立、模拟、策略。标签围绕生存、资源管理、时间管理、单人、多结局、中国民俗题材，按后台提供的实际标签选择。 |
| 平台与功能 | Windows x64，单人，本地存档，键盘和鼠标。当前交付范围仅含离线版。平台成就、云存档、联网合作、手柄完整支持和 Steam Deck 验证均未列入首发功能。 |
| 游戏语言 | 界面、对话和日志均使用简体中文。语言表选择简体中文界面。音乐、音效随包提供，完整配音未交付。英文商店文案已说明游戏文字仅为简体中文。 |
| 系统要求 | Godot 4.7.2，64 位 Windows，默认 Vulkan / Forward+。安装内容大小以本次上传清单计，可为安装文件预留 1 GB。CPU、内存、显卡与操作系统最低版本需按实际目标机结果填写。历史实测环境的 RTX 4060 Ti 仅可作为参考。[Windows 验证记录](../50-windows-release.md) |
| 开发商、发行商、定价、对外支持渠道 | 使用权利人确定的商号和发行主体信息、Steamworks 已配置的支持联系方式与定价。仓库所有者名、代码提交人和第三方素材作者不能代替这些字段。 |

后台的商店文字语言和游戏内语言分别配置。商店页使用与候选包一致的实机截图和玩法视频。开发工程可以启用的动态世情服务不属于玩家购买的功能。[Steam 商店文字](https://partner.steamgames.com/doc/store/page/description) · [商店与游戏语言](https://partner.steamgames.com/doc/store/localization) · [抢先体验](https://partner.steamgames.com/doc/store/earlyaccess)

## 内容调查与审核员说明

**已确认的玩家可见内容**包括尸群入侵、刀具迎敌、死亡、饥荒、瘟疫和文字中的伤口、收殓、血迹及溃兵劫掠。可粘贴的成熟内容说明已列在两份商店文案末尾。审核员可在灾后从院门附近经历夜袭，查看死亡复盘，或在药铺废墟的地点说明中查看血迹描写。夜袭属于有尸潮的夜晚。具体表现程度按最终上传的画面和完整包选择。[地图说明](../../data/map_points.json) · [世情文本](../../data/events.json) · [夜战说明](../06-night-defense-v0.6.md)

**生成式 AI** 选择包含开发期间生成的玩家可见内容。55 件物品使用四张预生成插画图集，邻居求药支线有 AI 辅助策划、人工筛选并固化入包的记录。Windows release 模式在运行时跳过在线导演。公开说明已列在商店文案的最后一项。内容调查涵盖提交的全部内容，提交方需确认完整素材清单，按真实情况答复年龄分级、其他敏感内容及权利声明。[物品插画记录](../47-inventory-art.md) · [支线开发记录](../12-neighbor-ai-review.md) · [导出模式判定](../../scripts/autoload/story_director.gd) · [Valve 内容调查](https://partner.steamgames.com/doc/gettingstarted/contentsurvey)

审核员说明可填写：

> 标题页「新开一卷」可使用默认身份直接进城。「自选开局」可查看其他身份与难度。备劫三日后进入宅院，按 J 查看目标，I 打开存货，T 查看差事。夜袭前先选择守夜方针，在有尸潮的夜晚可看到三轮攻防。游戏文字为简体中文，Windows 版本可离线完成剧情。测试存档会保存在本机 Windows 用户目录，设置内可导出试玩报告。

> The game text is in Simplified Chinese. On the title screen, choose 新开一卷 to enter town with the default character, or 自选开局 to pick an identity and difficulty. After the three preparation days, J opens the journal, I opens the inventory, and T shows the day's errands. On siege nights, choose a watch order and defend the courtyard through three waves. The Windows build uses local events and saves progress on the machine. A playtest report can be exported from Settings.

## Windows 单 depot 上传

候选生成在本机 `build/steam-ea-20261120/windows/`。相邻的 `steam-upload/` 内，`The-Survivors-Ledger_windows_x64_c5a7deb.zip` 是该目录的无外层文件夹压缩包，`upload-receipt.json` 记录来源与指纹。客户端根目录包含 `劫余录.exe`、`劫余录.pck`、`字体许可.txt`、`读我.txt`、`构建来源.txt` 和 `package-provenance.json`。Godot 及所含开源组件的许可地址在读我内。QA 输出和商店草稿留在 depot 外。[字体许可](../../assets/fonts/LICENSES.txt)

在目标应用配置 Windows x64 depot，并核对该 depot 属于预期的基础包。启动项使用 Windows 可执行文件 `劫余录.exe`，安装位置相对于 depot 根目录，默认参数留空。后台若提供完整 depot 的 Web Uploads，可选择该 zip 并核对清单。首次完整构建不选择向既有基线合并少数文件的模式。[Steam 上传说明](https://partner.steamgames.com/doc/sdk/uploading) · [局部更新模式](https://partner.steamgames.com/doc/sdk/updating/partial_depot)

使用 SteamPipe SDK 时，把[单 depot 模板](windows-app-build.vdf.in)复制为上传目录内的 `app-build.vdf`。用后台显示的实际应用 AppID、Windows DepotID 和验证过的源码 SHA 替换三个占位符。Playtest 使用自己的 AppID 和 depot。相对路径以 `app-build.vdf` 所在目录为基准。模板仅上传构建；后台会另行指定分支。

```text
steam-ea-20261120/
  steam-upload/app-build.vdf
  windows/
    劫余录.exe
    劫余录.pck
    字体许可.txt
    读我.txt
    构建来源.txt
    package-provenance.json
```

在已有上传权限的 SteamCMD 会话中执行 `run_app_build "<app-build.vdf 的绝对路径>"`。上传后记录 BuildID，指定测试分支，由 Steam 客户端实际安装、启动和读写存档；审核用分支、提交审核及公开发行状态均在 Steamworks 确认。[SteamPipe](https://partner.steamgames.com/doc/sdk/uploading) · [Steam 审核流程](https://partner.steamgames.com/doc/store/review_process)
