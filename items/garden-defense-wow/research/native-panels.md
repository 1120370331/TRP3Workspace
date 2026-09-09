# 魔兽原生面板组合

版本48仅将关卡选择区改为直接使用背景中的艾尔文草地，不再绘制该页的羊皮纸面板；存档与弹窗仍沿用版本47的纸张底板。关卡文字采用浅色/金色，布局与功能不变。

版本47在不透明羊皮纸底色之上叠加 `QuestBG-Parchment` 图集，使用85%不透明度显示原生纸张纹理；不额外传入 UV，交由 `SetAtlas` 使用客户端裁切信息。保留深色文字、简洁布局及完整底色，不恢复九宫格或标题/按钮区装饰。缺少图集时退回白色纹理叠层以保持可读性。未运行测试或实机校验。

版本46按用户要求不再使用下述面板装饰组合，改用一块 `SetColorTexture(0.80, 0.72, 0.55, 1)` 直接覆盖面板矩形，文字使用深棕色；不加载背景图集、九宫格边框或装饰分区。原生按钮继续保留，IG 0.2.5 的可复用能力未删除。下文仅记录版本45的实现来源。

版本45不再把一张木纹放大成整个面板。共同的地图、存档和弹窗底板采用：

- `QuestBG-Parchment` 图集：由客户端 `SetAtlas` 使用正确裁切区域，来源于 Blizzard [QuestFrameTemplates.xml](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/QuestFrameTemplates.xml)。不直接把带透明留白的整张 QuestBG 文件设成背景。缺少图集时退回原生 `UI-Background-Marble` 材质。
- `Dialog` 原生九宫格：四个 `UI-Frame-DiamondMetal-Corner*` 金属角和四条相应边线，使用客户端 [NineSliceLayouts.lua](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_SharedXML/Mainline/NineSliceLayouts.lua) 配置与 [NineSliceUtil](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_SharedXML/NineSlice.lua) 布局，四角不随面板拉伸。
- 有标题的面板增加内嵌标题带与细分隔线；弹窗底部单独承托按钮，正文和操作区不再混在整块木头上。
- 弹窗与设置页按钮使用 `UIPanelButtonTemplate`，沿用原生高亮、按下与禁用状态；庭院工具栏和战场按钮不变。

共享引擎 IG 0.2.5 提供 `panel` Surface 节点和 `nativeButton`，游戏只负责位置、内容及配色。原生装饰 Frame 禁用鼠标，保持在所属逻辑层，不使用带固定500层级的 NineSlicePanelTemplate，因此不会遮住上层确认按钮。

保留未开垦行只绘制泥土、现有存档、音乐/音量和玩法。按用户要求，仅生成导入包，未运行测试或客户端视觉校验；这里记录的是原生接口与资产来源，不是实测结论。
