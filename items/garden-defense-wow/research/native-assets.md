# Garden Defense WoW：原生材质与图标候选

`native-candidates.json` 是可直接传给 `Texture:SetTexture(FileDataID)` 的受控清单：15 项 `.blp` FileDataID，另有两个新增 M2 文件映射。它也引用上一轮 `items/garden-defense/research/assets-candidates.json` 的 Lasher、Lasher Orchid 和 Zombie M2。所有数字都是 FileDataID，不是 CreatureDisplayID。

## 可立即接入的资源

最终采用的地形在 [parts/misc.csv](https://github.com/wowdev/wow-listfile/blob/master/parts/misc.csv) 全文件检索中核对：草地 **187126**（`TILESET/ELWYNN/ElwynnGrassBase.blp`）、泥土 **187113**（`TILESET/ELWYNN/ELWYNNDIRTBASE.BLP`）、石路 **187099**（`TILESET/ELWYNN/ElwynnCobbleStoneBase.blp`）。木栏和门廊使用 `parts/world.csv` 中的艾尔文铁匠铺木材 **189607**。

草、泥、石路均使用实际 Tileset 漫反射 BLP，不使用草叶 billboard、模型蒙皮、镜面 `_s` 贴图或 `.meta` 文件作为地面基底。相邻 UV 和重复平铺在本版 `src/ui.lua` 中定义。

早期的 detail 草片 `189756` 和 doodad 泥土 `189683` 已排除，不进入最终地图配置。

UI 使用木框 `130672`、石框 `457323` 和制皮背景 `4619890`；木、石框图作为边框叠加，不当作无缝底图。工具/卡片资源包括铲子 `134435`、工程炮塔回退图标 `133013`、草药包 `133668`、农场种子 `656440`、太阳 `134909` / `135828`、松子 `134057` 和石块 `135227`。紧急防线默认使用下述收割傀儡模型。

## 证据边界

实际查阅公开的 [wowdev/wow-listfile](https://github.com/wowdev/wow-listfile) 的 `parts/misc.csv`、`parts/world.csv`、`parts/interface.csv` 与 `parts/creature.csv`。它们给出精确 FileDataID 和客户端路径。映射证据不等于客户端加载、模型皮肤、镜头比例、纹理接缝或听感验证。

没有使用裸模型皮肤 `132022` 作为“皮革 UI 背景”：它虽是 BLP，但路径属于角色选择模型材质，不是 UI 背景。这是 `notSelected` 中的显式反例。没有输出 CreatureDisplayID，因为未取得可信的 `CreatureDisplayInfo` 表来源；不能由 M2 FileDataID 推导 DisplayID。

补入两个确切 M2 FileDataID：Ancient Protector `122899`（`Creature/AncientProtector/AncientProtector.M2`）作为坚果防线的树人替代，Golem Harvest `124235`（`Creature/GOLEMHARVEST/GolemHarvest.M2`）作为紧急机械防线/割草机替代。二者来自同一公开清单的 `parts/creature.csv`；它们是模型文件映射，尚未验证在目标 `PlayerModel` 的比例、姿态或裁剪。

## 实现约束

- 本版直接使用原生贴图与模型，不加载像素版图形模块；模型失败或超时显示对应魔兽图标。
- 地面贴图可能带 alpha、透视、光照或不可平铺边缘；使用前需要在目标 UI 尺寸检查裁剪和接缝。
- `Texture:SetTexture` 可接受 FileDataID 的事实不等于该资源适合图块；所有 `direct_but_frame_not_fill` 项必须当边框使用。
- 本任务按要求未操作 WoW 客户端或运行实测。
