# 第二轮命中音效试听

试听结果已落实：自然 N11、孢子 S5、吞噬 D8。下列内容保留为选择记录。

本轮只试听尚未选定的自然弹、孢子和吞噬。每段宏复制一次，会以两秒间隔播放8个不同声音家族，并在聊天框打印候选编号。使用 `Master` 只为方便试听，最终游戏音频仍按既定通道和预算播放。

## 自然弹 N5–N12

```lua
/run local a={569708,1687889,978341,568483,567954,568290,569707,1602214};for i=1,#a do local j=i;C_Timer.After((i-1)*2,function()print("N"..j+4);PlaySoundFile(a[j],"Master")end)end
```

- N5 `NatureImpact`
- N6 `Nature_Impact_Medium01`
- N7 `Podling_Poison_Impact_01`
- N8 `ChimeraShotImpact2`
- N9 `WaterBolt_Impact_02`
- N10 `BubbleBlast_Impact_04`
- N11 `CobraShot_Impact_01`
- N12 `ForceOfNature_impactV2_01`

## 孢子 S5–S12

```lua
/run local a={978341,983489,568323,569386,568526,568092,1936962,569517};for i=1,#a do local j=i;C_Timer.After((i-1)*2,function()print("S"..j+4);PlaySoundFile(a[j],"Master")end)end
```

- S5 `Podling_Poison_Impact_01`
- S6 `Poison_Impact01`
- S7 `FoulJuice_Impact_01`
- S8 `PufferBreath_Impact_01`
- S9 `FetidBreath_Impact_01`
- S10 `RottenStench_Impact_08`
- S11 `Sewer_Slime_Impact_01`
- S12 `BubbleBlast_Impact_01`

## 吞噬 D5–D12

```lua
/run local a={3055167,1449454,1970165,1970170,668959,1278546,545096,4633594};for i=1,#a do local j=i;C_Timer.After((i-1)*2,function()print("D"..j+4);PlaySoundFile(a[j],"Master")end)end
```

- D5 `FerociousBite_Impact`
- D6 `GoremawsBite_01`
- D7 `Bite_Eat_Flesh_01`
- D8 `Bite_Eat_Plant_01`
- D9 `GIBS_ChunkSquish01`
- D10 `DemonBite_Cast_01`
- D11 `Lanathel_Bite02`
- D12 `Dragon_ChompBite_01`

回复格式：`N编号、S编号、D编号`，例如 `N7、S12、D5`。完全无声的编号请标注“不可用”。
