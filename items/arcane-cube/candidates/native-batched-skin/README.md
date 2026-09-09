# WoW原生贴图批处理候选

游戏 **0.4.2-test / objectVersion 6**，共享引擎 **0.4.3**。导入 [item.t3e.txt](item.t3e.txt) 的完整内容；沿用rootId `0908ArcCube001`、原存档格式和默认海潮皮肤。无需安装外部图片。

同一源面连续提交的点阵色块共用一个Frame。相邻ADD粒子也可共用Frame，遇到几何边界拆分；Texture和Frame分别缓存、隐藏及回收。海潮24×24、12色图案和全部Texture面片保留。

## 固定视角资源对照

| 场景 | 旧Frame | 新Frame | 可见Texture（未减少） |
| --- | ---: | ---: | ---: |
| 三阶海潮魔方 | 730 | 132 | 730 |
| 四阶海潮魔方 | 873 | 264 | 873 |
| 五阶海潮魔方 | 1264 | 444 | 1264 |
| 七阶海潮魔方 | 1961 | 948 | 1961 |
| 三主体材质试验 | 1080 | 7 | 1080 |

同一转层轨迹36帧，三阶所有受监测原生方法调用合计159397→98351，七阶345500→197777。三阶SetFrameLevel为10914→1747，Show为38748→141；七阶SetFrameLevel为52088→22672。调用数包含预热6帧，耗时统计排除预热。

对照只替换从旧候选提取的view3d模块，游戏、几何和材质均使用本次源码。原始数据见 [旧适配器](native-api-before.json) 与 [新适配器](native-api-after.json)，包含实际加载的适配器哈希。复测：

```powershell
python tools/benchmark-scene3d.py --adapter-bundle items/arcane-cube/candidates/tidal-pixels/engine.generated.lua
python tools/benchmark-scene3d.py
```

这是Lua mock宿主中的对象/API计数，**不是WoW FPS或GPU draw call数**。mock中Lua绘制均值没有稳定改善：三阶约2.87→2.87ms，七阶约7.83→9.03ms。目标是减少真实客户端中的Frame管理和原生API开销，其实际收益待客户端确认。面片数量仍随皮肤复杂度上升，画家算法的同面深度近似仍存在。

## 候选与验证

源码包哈希：`d4f51898b7142da22ad840737140429051a5b88449897f6214c4a89639aeb83d`。

导入文件SHA-256（含文件尾换行）：`34e209b72df755ff554d25ea7f1bb2c3e6f23b79ffc7a13a6412b5f30f0598af`。

构建记录见 [build-report.json](build-report.json)，固定源码见 [engine.generated.lua](engine.generated.lua)，物品元信息见 [item.manifest.json](item.manifest.json)。开发构建238647字节，导出串93783字符。

`npm test` 全部119项通过：21构建/包、45引擎、8花园、5空间、6粒子、7像素材质、22魔方、5包运行时。额外加强的粒子/几何层级边界断言已单独运行通过。测试覆盖原生Texture顶点、皮肤切换、转层和存档、批次遮挡顺序、关闭与复用时的残留清理、TRP3实际脚本沙盒启动。浏览器预览已检查真实Lua输出的转层、三主体材质、切回魔方和烟花试验交互；浏览器不模拟真实WoW渲染成本。

客户端复测：在同一场景、UI缩放和视角下比较三阶/四阶/七阶海潮与经典皮肤的转层；进入“烟花试验”运行四阶段对照并导出日志。面板新增原生Frame数。还需确认WoW Texture:SetParent、不同UI缩放、混合烟花遮挡及实际帧率。
