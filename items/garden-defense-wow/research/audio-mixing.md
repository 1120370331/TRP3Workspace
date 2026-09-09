# 音效并发与音量（IG 0.2.3）

旧版多个命中、施法、啃咬共用combat组，仅一路并发；组间隔0.55秒加最多0.7秒密度惩罚，且呕吐停止combat并封锁1.6秒。0.38–0.6秒的maxDuration也会直接截短尚未播完的片段。

新版将自然/寒冰/孢子各分配2路、暗影1路、啃咬2路、施法1路、精英1路、特殊效果3路；全场16路封顶，界面反馈按优先级抢占低优先级声音。单类保留冷却，持续请求不排队补播；呕吐取消duckGroups。普通命中maxDuration改为2秒的清理兜底，原生已结束时提前回收。高优先级声音起播成功才淘汰旧声部，失败按音源独立退避250ms。

声部存活扫描最多每20ms一次，组活动数与单音效活动数增量维护。普通暂停与关闭仍停止本场声部；BGM由Music模块独立持有。

## 音量路径

[Blizzard Sound API](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SoundDocumentation.lua)提供 `C_Sound.PlaySoundWithOptions` / `volumeOverride`，没有通用单文件音量参数。通过[SoundKitEntry](https://wago.tools/db2/SoundKitEntry/csv?build=12.1.0.69587)核对当前选用文件的同音色SoundKit，以原生单声部音量实现控制；不修改SFX/Master/Music等全局CVar。

| 声音 | 原文件ID | 音量用SoundKit |
| --- | ---: | ---: |
| 自然 | 569707 | 22889 |
| 寒冰 | 568542 | 7 |
| 孢子 | 978341 | 41206 |
| 吞噬 | 1970170 | 103506 |
| 暗影 | 568936 | 23249 |
| 碾压 | 568580 | 18085 |
| 爆炸 | 568528 | 16418 |
| 啃咬A/B | 564214 / 564220 | 3176 |
| 呕吐 | 567302 | 22028 |

SoundKit会在同音色文件中随机取变体，包括啃咬A/B/C；游戏仍交替提交A/B请求，但不保证原生实际播放A/B的逐次顺序。无音量需求的既有裸文件播放仍保持原路径；未映射文件请求降音量会明确返回不支持。

命中总线默认0.5；暂停→游戏设置中，音效总音量和命中音量均按10%调整并保存。总音量×命中总线×单音效音量×本次播放音量形成目标，传入原生接口前再乘baseVolume。直接文件原本基准为1；既有SoundKit的baseVolume依据[SoundKit表](https://wago.tools/db2/SoundKit/csv?build=12.1.0.69587)的VolumeFloat，保留界面提示音原基准。音量调整对新声部生效，0立即停止对应已有声部，不倒回或重播声音。

按用户指示，最终改动仅生成导入包，不执行最终测试或客户端试听验收；尚无本版实机叠加、音量或性能结论。
