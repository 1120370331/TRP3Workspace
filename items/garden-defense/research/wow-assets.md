# Garden Defense：WoW 原生资源候选

此清单是**可选增强**的受控候选集，不是已经在目标 WoW 客户端验收过的资产。游戏必须继续具备图标、矢量或纯色 UI 的完整兜底；不要让模型或声音加载失败阻断玩法。

## 引擎接口核对

已阅读 `framework/item-game/README.md`、`audio.lua` 和 `view.lua`。模型在 `content.assets.models` 内使用 `kind: "fileID"` / `id: FileDataID`，由 `PlayerModel:SetModel`（或场景模型路径）尝试加载；也可用 `creatureDisplayID`，但本次没有把 FileDataID 误写成 DisplayID。`loaded` 或 `SetModel` 调用成功只表示接口状态，README 明确要求在客户端确认实际视觉。

音效用 `content.sounds` 的 `{kind:"soundKitID", id, channel:"SFX"}`；背景乐用 `content.music` 的 `nativeFileId`，引擎默认通过 SFX 通道播放，也可显式配置 `channel:"Music"`。音效请求会受每音效 cooldown、12 声部预算和客户端播放结果限制。

## 证据与类型

`assets-candidates.json` 是机器可读的唯一候选表。模型和 BGM 的 `fileID` 均来自公开的 [wowdev/wow-listfile](https://github.com/wowdev/wow-listfile) `community-listfile.csv` 中的 `FileDataID;路径` 映射；该项目 README 说明 community 名称存在稳定性限制，故记录原路径，不把它当作客户端可播放证明。

音效的 `soundKitID` 均来自公开的 [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_SharedXML/Mainline/SoundKitConstants.lua) `SOUNDKIT` 常量。该来源能证明常量名与 ID 的对应，不能证明其听感适合 PvZ；表中因此分开标记。公开来源在本次检索中提供的是 FileDataID 映射，不是 `CreatureDisplayInfo` 数据表，故没有臆造 DisplayID。

## 推荐使用方式

植物模型只有有限的 WoW 近似：Lasher（124753）覆盖豌豆/寒冰/双发/大嘴花，Lasher Orchid（124765）覆盖向日葵，Sporeling（126055）和橙色赞加蘑菇（193920）覆盖两种蘑菇；坚果墙不选低相似模型，继续使用矢量轮廓。樱桃炸弹与土豆地雷分别用 Alliance Bomb（234505）和 Landmine（126022）表达战术角色。

普通僵尸使用 `creature/zombie/zombie.m2`（126570）。路障、铁桶、撑杆和读报是同一基础模型上的 UI 覆盖物候选，而不是捏造不存在的变体 Model ID。冰豌豆弹体和普通弹体可试 Frostbolt（166214）与 Missile Wave Nature（166575）；爆炸可试 Bomb Explosion A（165744）。

音效里播种、收阳光、命中、爆炸、警报、胜利、失败均有语义相近的 SoundKit 常量候选；射击没有受控的精确命名候选，保持静音或在实际试听后复用低风险 UI 音效，不能在未试听前称为“射击音”。背景声只保留一条植物主题的 Netherstorm 片段（53634），以免引入不受控大批音乐。

## 客户端验收清单

1. 逐个将候选接入临时 `content.assets.models`，生成实体后调用 `ctx.assets.recordModels()`；确认 `fileID`、`loaded`、比例、朝向、裁剪和是否遮挡棋盘。静态 doodad 与 spell M2 尤其可能不适合 `PlayerModel`。
2. 逐个触发候选 `sound.play`，记录 returned token/错误；在 SFX 音量正常、连续射击和 12 声部预算下实际试听。不要仅以 `PlaySound` 返回成功判定通过。
3. 用 `music.play(...,{loop=true})` 试听 53634，确认 Music 通道、循环边界、音量和停止行为；失败即回落无 BGM。
4. 检查每个模型在本客户端版本可用后才写入正式 content；记录客户端 build、所用 backend（`model`/`scene_model`）、scale/facing 及屏幕截图或 `check.models` 日志。

## 已知风险

- community listfile 的文件名可随社区校正变化；ID/路径映射应在目标客户端复核。
- FileDataID 不等于 CreatureDisplayID，二者不得互换。
- BGM、特效 M2 和静态世界物件可能加载却不合适，或在不同客户端分支缺失。
- `SoundKitConstants.lua` 是 UI 常量表；它不是完整法术/生物 SFX 目录。因此射击音没有用猜测补齐。
