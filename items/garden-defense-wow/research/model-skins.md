# 魔兽材质模型版：皮肤模型数据依据

最终使用 ATT 仓库保存的 **BattlePetSpecies 12.1.0.69587 CSV**，而非根据网页名称猜测数字。源表的 ID 是物种 ID；CreatureID 是 NPC ID，两者都不是显示 ID。配置通过客户端 Pet Journal 查询完整皮肤。

[BattlePetSpecies 源表](https://github.com/ATTWoWAddon/AllTheThings/blob/master/.contrib/.wago/12%20-%20Midnight/BattlePetSpecies.12.1.0.69587.csv) · [官方 API 定义](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/PetJournalInfoDocumentation.lua)

| 游戏模型键 | PetSpeciesID | NPC CreatureID（不用于加载） | 源表图标 FileDataID |
| --- | --- | --- | --- |
| pea | 1932 | 112798 | 959797 |
| sunflower | 291 | 51090 | 133939 |
| cherry | 85 | 9656 | 133712 |
| wall | 460 | 62020 | 132129 |
| mine | 1322 | 73352 | 897633 |
| snow | 253 | 40198 | 135851 |
| chomper | 162 | 23909 | 134015 |
| repeater | 318 | 53661 | 133941 |
| puff | 1539 | 86718 | 463281 |
| sunshroom | 1540 | 86719 | 132851 |
| zombie | 1967 | 115150 | 1100170 |
| mower | 338 | 55356 | 133015 |
| bucket_zombie | 2962 | 172151 | 3622122 |
| paper_zombie | 249 | 36979 | 254094 |
| pole_zombie | 3046 | 174181 | 336781 |

机器可读的 model-skins.json 同时保留源表 Description 与 SourceText，便于核对。比如物种291的来源是 Hillsbrad Foothills 的 Lawn of the Dead 任务，描述为会唱歌的花；不是先前未经证实的536（企鹅）。

运行时先调用 C_PetJournal.GetDisplayIDByIndex(speciesID, 1)，无值时取 GetPetInfoTableBySpeciesID(speciesID).displayID，随后通过 ModelScene Actor 或 PlayerModel 加载完整皮肤。短时不可用会重试；主通道失败转用相同皮肤的备用模型，两条通道都失败会暂停，不用图标代替单位。查询不召唤宠物、不更改收藏过滤器，也不要求拥有该宠物。

本文不声称已在客户端检查模型皮肤、镜头或音效；用户要求不做实机测试。
