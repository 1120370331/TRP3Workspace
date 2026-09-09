# ItemGame 引擎维护指南

本文面向改引擎、构建器和发布包的人。玩法接入看[开发指南](ITEM-GAME-DEVELOPER-GUIDE.md)，排错看[FAQ](ITEM-GAME-FAQ.md)。[引擎 README](../framework/item-game/README.md)是已实现 API 入口；[模块设计](ITEM-GAME-ENGINE-MODULES.md)中的拟建接口不等于现有接口。

## 1. 改动归属

| 文件 | 负责的变化 | 直接联动 |
| --- | --- | --- |
| `framework/item-game/core.lua` | JSON、资源作用域、事件队列 | Runtime、遥测、配置和存档 |
| `runtime.lua` | ctx、回调、固定步长、暂停/退出、存档和库存操作记录 | 所有模块及 game.lua |
| `host.lua` | WoW/TRP3 能力、实例、变量、事件、库存/交易和原生音频 | Runtime、Input、Audio |
| `input.lua` | 读取、接管、短按缓存、归还输入 | Runtime、窗口、controls |
| `surface.lua` | 有界的 rect/text/button 节点、稳定 ID、层级、按需属性更新和池复用 | view.surface → ctx.ui.surface；坐标从画布左上开始 |
| `world.lua` | 实体、地形、移动、碰撞、动作、AI、伤害 | prefab/action 配置、View、事件 |
| `view.lua` | 窗口、纹理/模型池、投影、血条、碰撞框和文本面板 | World、Input、资产记录 |
| `audio.lua` | 音效句柄、限频；BGM 后端和 Musician 异步生命周期 | Host、Runtime、音频配置 |
| `effects.lua` | 粒子发射、固定步长状态、Texture 对象池、插值渲染和容量降级 | Runtime、View 画布、effects/texture 配置、遥测 |
| `telemetry.lua` | 阶段采样、直方图、有界日志和汇总 | Runtime、测试台、分析器 |
| `tools/lib/item-game-bootstrap.mjs` | 短宏、延时、单次注入、启动提示 | 原生执行器、构建器、启动检查 |
| `tools/build-item-game.mjs` | 校验、Lua 打包、SC/LI/IN、身份、版本、安全元数据 | 编解码器、导入产物、构建测试 |
| `tools/analyze-perf-log.mjs` | 日志解析、对比、Markdown/CSV/JSON 报告 | 遥测字段；不能把 mock 当实机 |
| `items/<game>/` | 游戏身份、配置、规则和测试负载 | 通过 ctx 接入，不复制修改后的引擎 |

现在是上述平铺 Lua 文件。设计里的 ItemBinding、Environment、Assets、ItemStore 职责分别落在生成工作流、Host、Runtime 和 View，没有同名独立文件或通用 `ItemBinding.open` API。

改公开能力时一起核对门面、配置校验、直接调用者、相关检查和文档。发布文件从源构建；不要只修 dist 或编辑器中的节点。

## 2. 启动桥接的固定约束

```text
US.SC / LI.OU → onUse
  1. secure_macro：准备本根物品的单次注入
  2. 原生 delay：0.1 秒
  3. script：检查实例与注入，调用 wf_bootstrap
     → 装载引擎/注册游戏 → wf_open → Host → Runtime → onStart
```

**宏上限是 255 字节，计入 `/run ` 和空格。** 上游 [Effects.lua](../references/total-rp-3-extended/totalRP3_Extended_Tools/Script/Effects/Effects.lua) 的 `MAX_CHARACTERS_IN_MACRO = 255` 由 `strlen` 校验。旧版错误地使用 1023 门槛，生成约 731 字节宏，游戏内直接提示过长。当前性能台 rootId 对应 253 ASCII 字节；换长 rootId 也可能超限。

**宏和限定 Lua 之间必须保留原生 0.1 秒延时。** 宏经过安全执行路径，不能把相邻效果当作宏已先执行完；立即进入 Lua 会读不到注入。延时是工作流第二个节点，不能用 Lua 忙等替代。

注入只匹配本根物品，消费一次后恢复；未消费则两秒超时恢复。限定脚本不提升权限；恢复时只有入口仍是本包装器才写回，避免覆盖其他插件后续的包装器。不要改成长期开启执行器或要求先运行另一件道具。

本地检查覆盖原生工作流生成器和真实 delayed 函数的模拟调度、长度、作用根、单次恢复和超时。这些检查不等于当前客户端的 GUI、键盘和音频验收。

## 3. 道具、存档和版本

0.1.3 的关闭入口：View 用稳定全局别名 TRP3_ItemGameWindow 注册 UISpecialFrames，别名指向当前窗口，重复打开不重复登记；接管时 Esc 直接请求 stop。文本框 Esc 先取消面板。X 位于模态面板之上，拖动区与它不重叠。stop 先隐藏/释放，再逐项保护保存、声音、世界、事件、日志和 View 清理，异常记为 cleanup.*，不把停止中的残留场次重新显示。

| 标识/数据 | 管理规则 |
| --- | --- |
| rootId | 同产品升级不变；新游戏另取短 ID |
| publisher / createdAt | 首次发布身份，后续保留 |
| objectVersion / releaseVersion / savedAt | 每次发行递增对象版本，更新作品版本和时间 |
| engineApiVersion | 当前为 1；改公开兼容契约时安排明确升级 |
| saveVersion | 游戏进度格式；不匹配时保留旧值并拒绝启动，需专门迁移实现 |
| sourceHash / objectHash / exportHash | 构建报告生成，分别辨认源码、结构和导出串 |

原生编辑器保存会递增 MD.V，却不会修改包内编译清单。0.1.4 起 Host.definitionVersion 捕获启动时的 MD.V，definitionChanged 比较该快照与当前定义，并继续检查清单指纹。不要将运行期变化检测直接与 manifest.objectVersion 比较，否则编辑后每次启动都会立即退出。日志 objectVersion 是构建版本，objectRevision 是本机修订；同一时点启动的新场次允许它们不同，运行中的更新仍需停止旧场次。

性能台作者为 **斯提芬丶九二-金色平原**，根 ID 为 `0905170116PLab1`。具体候选版本以 [item.json](../items/performance-lab/item.json) 和 [build-report.json](../items/performance-lab/dist/build-report.json) 为准。

`SC/IN` 是共享定义，`args.object` 是一份背包实例，session 是一次运行。主道具变量只写当前实例：`IG_SAVE_V1`、`IG_SAVE_BACKUP_V1`、`IG_PERF_LOG_V1`、`IG_BOOT_STATUS_V1`。`IG_CONTROL_V1` 传低频暂停/停止/销毁请求；`IG_STORAGE_PROBE_V1` 是往返测试键；装备属性写装备自身的 `IG_EQUIP_V1`。

库存写操作前后核对所有权和数量；主道具交易中或离开背包时停止写入。不确定操作保留记录，不自动补发。主道具和带属性装备禁止堆叠：上游拆堆不复制变量，合堆也不按变量区分实例。改内部物品 ID 会影响已发出去的材料/装备，需按兼容变更处理。

`ctx.save.request` 合并延后保存，`ctx.save.flush(reason)` 同步执行 onSave 和变量核对并返回结果，成功后清除待保存请求。后者可用于显式保存按钮，但不会触发 WoW 磁盘刷盘；停止/重入时返回 session_busy。变更保存流程时同时核对两条入口。

## 4. 本地修改与发布

0.4.0 的选包、发行精简、项目依赖锁、预算和源码回查见[包管理指南](ITEM-GAME-PACKAGES.md)。发行前运行 `npm run build:all -- --frozen-lockfile`，审阅依赖变化后使用 `--update-lock` 更新锁。开发模式可用 `--out` 生成独立诊断候选；不要覆盖发布包后仍沿用旧报告。

首次准备（需要 Node.js/npm、Python 和上游参考源码）：

```powershell
git submodule update --init --recursive
npm ci
powershell -NoProfile -File tools/setup-tests.ps1
```

setup 将 Lua 5.1 测试运行时放在仓库 `.local-tools/`，下载并校验固定 SHA-256 的 AceSerializer 参考。哈希失败先核对上游变化，不删校验。

对稳定候选执行相关最终检查：

```powershell
npm run build
npm test
node tools/build-item-game.mjs items/performance-lab/item.json --verify-only
```

`npm test` 执行 Node 构建测试和 Python 驱动的 Lua 5.1 模拟宿主检查。开发中先跑受影响检查，不必每改一行就重建或跑全套。`--verify-only` 重算候选并确认现有导入串没有过期。

正式更新时保留上一发行版报告，再构建：

```powershell
node tools/build-item-game.mjs items/performance-lab/item.json --previous releases/previous/build-report.json
```

previous 路径替换为真实留存文件；该选项检查发布身份、对象版本递增和有效内容变化。dist 产出导入串、可读结构、报告、生成 Lua、短宏、启动 Lua。保留它们和原始日志，才能复现候选。

## 5. 实机验收和日志

更新定义后执行一次 `/reload`，从 TRP3 背包使用主道具，不只预览 Lua 节点。按改动范围验证：

| 改动 | 最小实机路径 |
| --- | --- |
| 桥接/构建/运行期 | 导入 → 添加到背包 → 三段提示 → 窗口 → 关闭 → 再开 |
| 输入/退出 | 接管操作 → 文本焦点 → 暂停/继续 → WoW 战斗/副本关闭后控制权归还 |
| 模型/碰撞 | 两种后端画面、模型记录、逻辑框和命中位置，不只看 loaded=true |
| 音频 | 可听性、通道设置、切曲、暂停/继续、退出停止；Musician 另测 |
| 存档/库存 | 保存 → reload/重登 → 恢复；材料/装备发放与双客户端交易核对 |
| 性能 | 固定环境跑受影响阶段，确认实际负载和失败计数后比较 |

首轮实机：WoW **12.1.0 / build 69587**、TRP3E **1061**、住宅 `interior`，对象版本 2 / 作品 0.1.1-test。21 个自动阶段到达结束，20 个 complete、1 个 music_not_started；无记录到的运行错误。它证明该候选能启动和运行，不能证明新版、关闭清理、重登存档或交易全部通过。该样本 `Sound_EnableMusic=0`，音效由玩家确认正常。

日志按钮只开文本框，Ctrl+A/C 后在游戏外保存 UTF-8 文件，再运行：

```powershell
node tools/analyze-perf-log.mjs run.ndjson
```

输出 `run.analysis/report.md`、`phases.csv`、`summary.json`。文件名虽可为 `.json`，内容仍是逐行 JSON，不要改成数组。模拟宿主数据默认不能作为性能证据。

区分 `frameMs`（OnUpdate 间隔）与 `luaFrameMs`（引擎 Lua 用时）；P95/P99 是直方图近似上界，`memoryKB` 是共享客户端 Lua 堆。排除阶段失败、负载不足和日志裁剪，再比较同机器、地点、画质、帧率设置、插件组合与候选 sourceHash。

## 6. 文档随代码更新

- 改 ctx/内容字段：更新[开发指南](ITEM-GAME-DEVELOPER-GUIDE.md)和[引擎 README](../framework/item-game/README.md)。
- 改启动、版本、日志、交付：更新本文、[FAQ](ITEM-GAME-FAQ.md)和[测试台 README](../items/performance-lab/README.md)。
- 改工作流/内部对象：更新[装配设计](ITEM-GAME-ENGINE-TRP3-PACKAGE.md)，注明实际生成行为。
- 规划功能落地前保留“拟建/未实现”；API 成功、模型 loaded、mock 通过，均不能写成实机体验已验收。
