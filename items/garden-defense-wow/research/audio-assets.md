# 昼夜 BGM 与命中音效映射

本轮音频全部使用魔兽客户端原生 FileDataID，不把《植物大战僵尸》原作音乐或音效打包进道具。ID 与路径来自公开的 [wowdev/wow-listfile](https://github.com/wowdev/wow-listfile) `parts/sound.csv`；清单能证明文件映射，不能替代目标客户端试听。

## 背景音乐

| 场景 / 界面曲名 | FileDataID | 客户端路径 | 选择理由 |
| --- | ---: | --- | --- |
| 白天战斗 / 汇帆市场·白天 | 1781897 | `sound/music/battleforazeroth/mus_80_kultiran_highseas_a.mp3` | 汇帆市场白天曲库中的 Kul Tiran High Seas A |
| 夜晚战斗 / 汇帆市场·夜晚 | 2146621 | `sound/music/battleforazeroth/mus_80_kultiran_parley_b.mp3` | 用户通过 N1 指令试听后选定 Kul Tiran Parley B |

版本39按用户试听结果，将夜晚替换为 **N1 · Kul Tiran Parley B**，白天保持不变。100%音量直接播放 FileDataID 2146621；1–99%改走 **SoundKit 93661** 保留独立音量，用户已接受随机曲目限制。该 SoundKit 有三条记录：243125 → High Seas A（1781897）、337271 → Parley B（2146621）、339441 → Freehold Combat A（2146593），同构建 SoundKitChild 无子曲库。0%仍静音。配乐卡在低于100%且非静音时显示“Parley B 等 · 曲库随机”，不将随机结果标称为固定 N1。此次未再试听或运行测试。

选曲依据以用户试听为准：A/B 是曲目分段，收录于夜间播放列表不等于具有独立的“夜晚版”；版本37对 High Seas B 的选用已被此次 N1 替换。

版本37改用伯拉勒斯·汇帆市场的昼夜配乐。WoW 12.1.0.69587 的 [AreaTable](https://wago.tools/db2/AreaTable/csv?build=12.1.0.69587) 记录8718（Tradewinds Market，伯拉勒斯港下的汇帆市场，非围攻伯拉勒斯副本）使用 [ZoneMusic](https://wago.tools/db2/ZoneMusic/csv?build=12.1.0.69587) 2070（`ZONE_80_TiragardeSound_Boralus`），昼夜分别指向 SoundKit 116005 / 116006。[SoundKitEntry](https://wago.tools/db2/SoundKitEntry/csv?build=12.1.0.69587) 中的记录339000（116005 → 1781897）和339002（116006 → 2146242）对应选定的 High Seas A / B；文件路径由 wow-listfile 对应。区域曲库含多首，本游戏从各自昼夜曲库固定选一首，不随机换曲。未试听或运行测试。

版本35按用户要求将昼夜曲目均替换为炽蓝仙野（Ardenweald / AW）配乐。文件名和 FileDataID 来自 wow-listfile；WoW 12.1.0.69587 [SoundKitEntry](https://wago.tools/db2/SoundKitEntry/csv?build=12.1.0.69587) 中的记录570303（SoundKit 170713 → 3853246）与555251（SoundKit 173965 → 3853322）提供客户端曲目映射。游戏直接播放对应文件，不通过随机 SoundKit 选曲，保证白天和夜晚各固定一首。曲名后缀 H 对应所选文件段；界面中文标题为游戏内简称。未试听或运行测试。

版本34将夜晚曲目替换为暮色森林的 `Haunted UU02`，白天曲目与播放控件不变。区域归属依据 WoW 12.1.0.69587 的 [AreaTable](https://wago.tools/db2/AreaTable/csv?build=12.1.0.69587)（暮色森林下的 The Yorgen Farmstead 245、Addle's Stead 536 使用 ZoneMusic 768）、[ZoneMusic](https://wago.tools/db2/ZoneMusic/csv?build=12.1.0.69587)（768 / `Zone-DuskwoodHaunted` 指向 SoundKit 22757）及 [SoundKitEntry](https://wago.tools/db2/SoundKitEntry/csv?build=12.1.0.69587)（记录41233：22757 → 441672）；文件名由 wow-listfile 对应。未试听或运行客户端验收。

两首曲目走引擎默认的 `SFX` 通道，遵守魔兽总声音、音效开关与音量；游戏设置另有独立 BGM 开关，游戏内音效开关及音效/命中音量不影响 BGM。进入白天/夜晚关卡时选择对应曲目并循环，暂停时停止、恢复时重播，返回地图或结算时停止。

版本38新增独立 BGM 音量（0–100%，每次10%，默认100%，存档字段 `musicVolume`）。100%保持直接文件播放；低于100%时使用 `C_Sound.PlaySoundWithOptions.volumeOverride`：白天对应单曲 SoundKit **120160**（SoundKitEntry 354974 → 1781897），夜晚对应 **120161**（354975 → 2146242），两者的 `baseVolume` 均为1，保持文件播放的归一化基准。已读取同构建 [SoundKitChild](https://wago.tools/db2/SoundKitChild/csv?build=12.1.0.69587)，两者均无子 SoundKit，因此不会随机换为区域曲库内其他歌曲。不改魔兽音量 CVar，也不影响本游戏音效增益。

WoW 原生接口只提供开始播放时的音量覆盖，不支持音频暂停、seek 或运行中的增益变更。正在试听时调音量会重新播放该曲；0%立即静音，调高后可重播。处于暂停状态的战局不会因调音量而恢复。用户提出的“从记录点续播”尚无法用当前原生后端实现，本版未将“暂停期间继续播放”冒充断点恢复，也未擅自切换这一行为。能力依据 [Sound API](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SoundDocumentation.lua) 的本地参考副本；按要求未运行测试或实机验收。

版本33修复“BGM 开启但试听失败”：本机保存的 `WTF/Config.wtf` 中 `Sound_EnableMusic=0`，旧版显式使用 `Music` 通道，宿主会返回 `channel_disabled`。改用 `SFX` 后无需开启区域背景音乐，不改动任何客户端 CVar。错误提示现在区分总声音关闭、总音量为零、音效通道关闭、音效音量为零、原生接口失败和资源未能启动；恢复游戏时可重试此前不可用的曲目。此诊断来自只读配置与源码，未在运行客户端试听验证。

界面曲名是便于识别的游戏内简称，并非官方译名。保留上述两首原生配乐，不另外下载或打包音乐文件。

### 配乐控件

- 游戏设置页直接提供音效、命中、音乐三行音量调节；音乐音量与试听页复用相同控件逻辑、引擎接口及存档值，设置即时保存，无需为调音量进入试听页。
- 底部“音乐”或暂停 → 游戏设置 → “昼夜配乐 / 试听”打开配乐页；进入时冻结战局。
- 两张曲目卡分别显示昼夜、曲名、文件简称和本关标记。可试听任一曲目、从头试听或停止试听，不改变关卡的自动配乐映射。
- 试听是暂停状态下的显式操作，循环播放且只持有一个音乐句柄；切换曲目先停止上一首。返回、Esc、收起窗口或恢复游戏均结束试听；战局恢复后使用本关曲目。
- BGM 开关即时保存；关闭时停止音乐并禁用试听。非战斗界面不会因打开 BGM 开关而播放保留战局的歌曲。
- 配乐页通过“BGM 音量 − / +”独立调节并保存；旧客户端无音量接口时禁用控件。仍受魔兽总声音与 SFX 通道的开关/音量上限约束，不修改全局音量；游戏内音效和命中音量不影响 BGM。控件旁明确提示调音量会重播以及不支持断点续播。

本轮按用户要求只修改并生成导入包，未试听、未运行测试或客户端验收；听感与循环行为留给用户确认。

## 分类命中

| 游戏事件 | 逻辑声音 | FileDataID | 客户端路径 |
| --- | --- | ---: | --- |
| 翡翠/深红鞭笞者自然弹 | `hit_nature` | 569707 | `Sound/SPELLS/SPELL_HU_CobraShot_Impact_01.ogg` |
| 寒霜精灵寒霜弹 | `hit_frost` | 568542 | `Sound/SPELLS/BlizzardImpact1a.ogg` |
| 赞加喷射孢子 | `hit_spore` | 978341 | `Sound/SPELLS/SPELL_Podling_Poison_Impact_01.OGG` |
| 邪恶南瓜吞噬 | `hit_devour` | 1970170 | `sound/spells/spell_npc_bite_eat_plant_01.ogg` |
| 炸弹宝宝/黑索地雷 | `explode` | 568528 | `Sound/SPELLS/SmallExplosions_Generic_01.ogg` |
| 巫妖暗影弹 | `hit_shadow` | 568936 | `Sound/SPELLS/SPELL_PR_ShadowOrb_Impact_02.ogg` |
| 食尸鬼近战啃咬 | `enemy_bite_a/b` | 564214 / 564220 | `Sound/CREATURE/Wolf/BiteMediumA/B.ogg`，逐次交替 |
| 紧急机械防线碾压 | `mower_hit` | 568580 | `Sound/SPELLS/FX_Crunch_Armor_Impact_03.ogg` |

自然、寒霜、孢子、暗影和啃咬沿用 `combat` 密度预算，密集战斗不会为每次伤害叠加声音；吞噬、爆炸和碾压是较低频的重要反馈，保留独立播放。呕吐持续伤害沿用已有的 `567302`，不会按每个伤害 tick 重复触发。

## 实机验收边界

- 分别在白天与夜晚关卡确认曲目听感、SFX 通道音量、暂停/恢复、返回地图和循环重播；魔兽区域音乐关闭时仍可播放本游戏配乐。
- 逐类触发一次命中，确认文件可播放、音量层级合理、没有过长尾音；再用密集双发与多路啃咬确认预算仍有效。
- FileDataID 在公开清单中的存在不保证目标客户端分支一定可播；失败时音频层返回失败但不影响伤害结算。
