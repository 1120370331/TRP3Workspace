# 可选社区 MIDI 配乐

## 场景与来源

| 场景 ID | 曲目 | 页面署名 | 原 MIDI 字节 | 内置曲目码字符 | 来源 |
| --- | --- | --- | ---: | ---: | --- |
| battle_day | Grasswalk | Community arrangement (BitMidi) | 3291 | 2416 | [来源](https://bitmidi.com/plants-vs-zombies-grasswalk-mid) / [MIDI](https://bitmidi.com/uploads/85345.mid) |
| battle_night | Moongrains | 用户提供，编曲者未核实 | 7728 | 4420 | 用户上传 Moongrains_Normal.mid；未启用 Musician 时回退原生 N1 |
| menu | Plants Selection | Paul Soh | 8340 | 5296 | [来源](https://www.vgmusic.com/music/computer/microsoft/windows/) / [MIDI](https://www.vgmusic.com/music/computer/microsoft/windows/Plants_vs_Zombies_-_Plants_Selection.mid) |

Grasswalk 页面没有提供可确认的编曲者署名；BitMidi 是发布来源，不代表编曲者。版本57移除错误分配给夜间的 Zen Garden（禅境花园），版本58用用户提供的 Moongrains_Normal.mid 补齐夜晚/无尽配乐。该文件为格式1、8轨 MIDI，经本机转换器生成3314字节曲目数据及4420字符 Base64 码；未试听确认演奏效果。Plants Selection 用于存档选择与选关页；无 Musician 时菜单回退到已有 High Seas A。

MIDI 均经本机 Musician 附带转换器（CONVERTER_VERSION=8.10）转换，useFullPitchBendRange=false，只把曲目码写入 content.music，不重复存入原 MIDI，也不打包乐器采样。

源文件 SHA-256：

- Grasswalk: `f868dd4bb96374835a3b843049b625158117ea35277bdeb956cd5cfbb541de35`
- Moongrains_Normal.mid: `421f7a68ce2606b04a11f66b09fbbb7e95c1a93e566719269883f33f10154335`
- Plants Selection: `5d9fe7e045db59261cb1399eb1078112d66e73e2c09d22757776ac660a573dfc`

## 自动选择与设置

- 新旧存档缺少 musicSource 时采用 auto：有可用 Musician 优先 MIDI；无插件/忙碌/静音、格式不兼容、加载失败或30秒超时回退原生曲目。
- 游戏设置和曲目试听页均可切换“自动（Musician 优先）/ 魔兽原生”，保存到 book.musicSource；BGM 总开关仍生效。
- MIDI 模式按同一个 Song 游标暂停/恢复；不触发对外广播，不把进入设置当作重播。手动换曲、试听、切换后端或关闭后重新打开不承诺恢复旧曲游标。
- 当前 Musician 没有单曲独立音量接口。保留 book.musicVolume 供原生模式使用，MIDI 模式禁用百分比调整并说明原因；已有0音量仍静音，可点“开”恢复。原生模式保留 N1 低音量随机曲库的既有约定。
- 宿主调用 Song 时临时关闭自动音频参数调整并立即恢复，不自动保存/改写 Musician 的全局音量设置。采样器自身设置和复音上限仍需用户确认。
- 三首可分别试听，首次异步加载和回退状态会刷新；暂停、收起、取消导入后，晚到回调不能重新开始播放。

## 使用边界

社区 MIDI 是改编乐谱，不是原版录音；音色由 Musician 乐器库决定。已保留来源与页面署名，未确认商业使用或公开再分发许可，公开分享含谱包前需确认原作者及相关权利方要求。

按用户要求完成代码接入与导入包生成，未运行测试、未实机试听或验收；以上是接口、数据来源和实现边界，不是客户端听感/性能结论。
