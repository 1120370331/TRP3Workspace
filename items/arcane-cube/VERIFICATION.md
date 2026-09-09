# 奥术魔方 0.1.0-test 验证记录

日期：2026-09-08。环境：Windows、Lua 5.1（Lupa）、仓库 mock-wow 宿主、TRP3 Extended 上游脚本执行器，以及本地浏览器绘图预览。

## 最终候选

- 引擎：ItemGame 0.3.0，API 1。
- rootId：`0908ArcCube001`；objectVersion：1。
- sourceHash：`9f32c71edcb0302872c6814b09bbd689c55962166da77f41d36b3751aa437aaa`。
- exportHash：`1ac03d6796ccb570b553e446ff5914fd614bbaf7e53c056f2de55cc2259052d2`。
- 导入字符串：94447字符，文件含末尾换行为94448字节；启动宏252字节，小于255字节上限。
- 文件：[dist/item.t3e.txt](dist/item.t3e.txt)；完整构建元数据：[dist/build-report.json](dist/build-report.json)。

## 已通过的检查

| 检查 | 结果 |
| --- | --- |
| `npm run build` / `npm run build:cube` | PASS：Lua 5.1语法、结构校验、导入回读、源码字节一致性与安全元数据 |
| `node --test tests/build.test.mjs` | PASS：15项 |
| `python tools/test-engine.py` | PASS：45项 |
| `python items/garden-defense/tests/test_game.py` | PASS：8项 |
| `python tests/test_scene3d.py` | PASS：5项 |
| `python items/arcane-cube/tests/test_cube.py` | PASS：12项 |

合计85项测试。最终游戏文案修复后重跑魔方12项；其他有效检查按未受影响的代码范围复用。期间修正了两处已有测试夹具：物品介绍与当前manifest不一致、Musician替身缺少当前音频适配器要求的Resume/IsPlaying。没有为通过测试修改原有音频或庭院玩法。

魔方导入包通过原生AceSerializer回读，并经仓库固定的TRP3 ScriptGeneration/安全宏收集器启动：宏 → 原生延时 → 沙盒Lua → 创建3D场景 → J转层 → 关闭。执行器注入在启动完成后恢复。发现并修复了TRP3沙盒缺少assert的打包绑定问题；assert/error仅绑定为生成脚本内的局部变量。

## 浏览器实际操作

以最终源码启动独立预览，在可见画面中点击：3阶 → 7阶 → X轴 → 第4层 → +90°。显示一条贯穿表面的新色带，计步为1。点击“模拟关闭并重开”后，阶数、选层、色带和计步保留。点击“回放复原”后恢复同色六面并显示完成提示。预览使用实际Lua游戏和引擎，画面来自view3d生成的原生Texture顶点，不是重写的JavaScript魔方。

三阶默认视角159个可见面；七阶219节点、2190提交面、默认视角1095个可见/绘制面，未触发绘制丢弃。这里只记录几何数量，不把模拟宿主耗时解释为WoW性能。

## 尚待客户端验证

WoW 12.1.0 / TRP3E 1061中的实际导入、Texture顶点视觉、不同UI缩放、拖出视口后的鼠标释放、进入战斗时清理、重载后的存档，以及7阶转动帧率。当前包的 `inGameVerified` 保持false。

渲染使用CPU投影和按面深度排序，不提供GPU深度缓冲。相交网格、复杂透明、跨ModelScene遮挡和完整刚体物理均不在当前能力范围。魔方的2–7阶范围和2000步记录上限是明确的产品预算。

## 复现

```powershell
npm run build
npm run build:cube
npm test
python tools/preview-cube.py
```

默认预览：[http://127.0.0.1:8766](http://127.0.0.1:8766)。`--port 8767` 可启动隔离实例。浏览器预览存档仅保留在本次Python进程的模拟宿主中；实际道具存档写入TRP3物品变量。
