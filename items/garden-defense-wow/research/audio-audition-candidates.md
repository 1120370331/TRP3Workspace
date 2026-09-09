# 命中音效试听候选

第一轮结果已落实：爆炸 E4、暗影 H4、啃咬 B3/B4 交替、机械 M1。自然、孢子和吞噬请改用[第二轮扩展试听池](audio-audition-expanded.md)。下表保留为选择记录。

下面每条都是可单独复制到 WoW 聊天栏执行的本机试听宏。全部使用 `Master` 通道，便于试听时避开 SFX 开关；最终接入游戏后仍会按现有配置走 SFX 或 Master，并接受战斗密度限制。候选 ID 与路径来自 `wowdev/wow-listfile` 的 `parts/sound.csv`。

寒霜命中已按要求改为冰风暴命中 `568542 / BlizzardImpact1a`，不参与本轮选择。其余类别请回复候选编号，例如：`自然 N2，孢子 S1，吞噬 D4，爆炸 E2，暗影 H3，啃咬 B3，碾压 M2`。

## 自然弹命中

- N1（当前）：`/run PlaySoundFile(568563,"Master")` — `Druid_Wrath_Impact01`
- N2：`/run PlaySoundFile(569134,"Master")` — `Druid_Wrath_Impact02`
- N3：`/run PlaySoundFile(569488,"Master")` — `Druid_Wrath_Impact03`
- N4：`/run PlaySoundFile(568895,"Master")` — `Druid_Wrath_Impact04`

## 孢子命中

- S1（当前）：`/run PlaySoundFile(568437,"Master")` — `FX_FungleSpores_Poison_Impact_03`
- S2：`/run PlaySoundFile(569259,"Master")` — `FX_FungleSpores_Poison_Impact_01`
- S3：`/run PlaySoundFile(569135,"Master")` — `FX_FungleSpores_Poison_Impact_02`
- S4：`/run PlaySoundFile(568865,"Master")` — `FX_FungleSpores_Poison_Impact_04`

## 吞噬命中

- D1（当前）：`/run PlaySoundFile(595451,"Master")` — `AzjolLighting_ShortSquish01`
- D2：`/run PlaySoundFile(596762,"Master")` — `AzjolLighting_ShortSquish02`
- D3：`/run PlaySoundFile(596555,"Master")` — `AzjolLighting_ShortSquish03`
- D4（偏干脆）：`/run PlaySoundFile(568358,"Master")` — `FX_Crunch_Armor_Impact_01`

## 爆炸命中

- E1（当前）：`/run PlaySoundFile(568639,"Master")` — `Bomb_ExplosionPumpkin1`
- E2：`/run PlaySoundFile(569567,"Master")` — `Bomb_ExplosionPumpkin2`
- E3：`/run PlaySoundFile(569083,"Master")` — `Bomb_ExplosionPumpkin3`
- E4（通用轻爆炸）：`/run PlaySoundFile(568528,"Master")` — `SmallExplosions_Generic_01`

## 暗影弹命中

- H1（当前）：`/run PlaySoundFile(568417,"Master")` — `SPELL_SpectreBlast_Impact_02`
- H2：`/run PlaySoundFile(569519,"Master")` — `SPELL_SpectreBlast_Impact_01`
- H3：`/run PlaySoundFile(568025,"Master")` — `SPELL_SpectreBlast_Impact_03`
- H4（更像暗影球）：`/run PlaySoundFile(568936,"Master")` — `SPELL_PR_ShadowOrb_Impact_02`

## 食尸鬼啃咬

- B1（当前）：`/run PlaySoundFile(568914,"Master")` — `WolfEatFlesh1`
- B2：`/run PlaySoundFile(569233,"Master")` — `WolfEatFlesh2`
- B3（较短）：`/run PlaySoundFile(564214,"Master")` — `BiteMediumA`
- B4（较短变体）：`/run PlaySoundFile(564220,"Master")` — `BiteMediumB`

## 机械防线碾压

- M1（当前）：`/run PlaySoundFile(568580,"Master")` — `FX_Crunch_Armor_Impact_03`
- M2：`/run PlaySoundFile(568358,"Master")` — `FX_Crunch_Armor_Impact_01`
- M3：`/run PlaySoundFile(569536,"Master")` — `FX_Crunch_Armor_Impact_02`
- M4：`/run PlaySoundFile(568452,"Master")` — `FX_Crunch_Armor_Impact_04`

若执行宏完全无声，先确认魔兽“启用声音”和主音量已开启；某个 FileDataID 在当前客户端分支失效时，直接把该编号标为不可用即可。
