# ItemGame 包管理与发行构建

ItemGame 0.4.0 支持本地声明式包管理：项目选择能力，构建器解析依赖，只读取和打包选中的 Lua 模块。接收者仍只需导入一个完整道具，不用另装引擎插件。没有远程包仓库或运行时下载。

## 项目配置

在 `item.json` 中增加：

```json
{
  "engine": "../../framework/item-game",
  "packages": ["surface", "particles3d"],
  "build": {
    "profile": "release",
    "budgets": {"sourceBytes": 200000, "exportCharacters": 85000},
    "logs": {"persist": "manual", "maxBytes": 32768}
  }
}
```

这是魔方的配置形式。`runtime` 总会加入；`particles3d` 会带入 `scene3d`。省略 `packages` 时保持旧行为，包含全部包；`packages: []` 只包含基础运行时。未知名字、重复选择、依赖循环和重复模块归属在构建时失败。游戏自己的 `modules` 映射仍由项目选择，保持原有 `function(ctx, modules)` 约定。

| 包 | 能力 | 自动依赖 |
| --- | --- | --- |
| runtime | 窗口、生命周期、输入、定时、存档、库存/交易、诊断 | 总是包含 |
| surface | 2D 画布、文字、按钮、纹理、PlayerModel | runtime |
| surface-models | Surface 共享 ModelScene 生物模型 | surface |
| world | 2D 实体、地形、移动、碰撞、战斗、AI | surface |
| audio | 音效、原生 BGM、可选 Musician | runtime |
| effects | 2D Texture 粒子 | runtime |
| scene3d | 数学、几何、摄像机、拾取、WoW 投影 | runtime |
| particles3d | 3D 粒子、发射器和 billboard | scene3d |
| pixel-materials | 调色板/RLE像素材质与UV绑定 | scene3d |
| surface-effects3d | 轮廓光、自发光脉冲、距离雾（原生颜色近似） | scene3d |

World 复用 Surface 的模型资源解析，所以目前依赖 surface。Scene3D 不需要二维 World，Surface 生物模型也不需要独立 Scene3D。没选 world/audio/effects 时，Runtime 不创建或更新这些系统。Scene3D 没选 particles3d 时，`scene.particles` 为 nil。

非空 `prefabs/actions/levels` 要求 world；`sounds/music/feedback` 要求 audio；二维/三维粒子定义分别要求 effects/particles3d；`surfaceModelScene: true` 要求 surface-models。构建器不会静默删除这些内容。动态 Lua 的全部访问无法静态证明；游戏可调用：

```lua
ctx.requirePackage("surface")
if ctx.hasPackage("audio") then ctx.sound.play("click") end
```

缺失能力时报 `package_not_included` 并走正常错误清理。不要通过 `if ctx.sound then` 判断能力，未选包的 API 门面用于给出明确错误。`ctx.level.checkpoint` 保持可用，`ctx.level.load` 需要 world。

## 开发、发布和预算

```powershell
npm run packages
node tools/build-item-game.mjs items/arcane-cube/item.json
node tools/build-item-game.mjs items/arcane-cube/item.json --profile development --out .test-output/cube-debug
npm run build:all
```

`development` 是未配置项目的兼容默认值：保留可读 Lua，自动保存最多约 190000 字节的性能日志。`release` 去掉代码注释和多余空白，保留字符串、标识符和代码行边界，比较精简前后的 token 和语法树。最终仍是适配 WoW 的 Lua 源码，完整道具继续使用 AceSerializer → Deflate level 9 → LibDeflate 可打印编码。不交付平台相关字节码，不增加二次解压执行器。

`build.budgets` 只约束 release。`sourceBytes` 是嵌入 `wf_bootstrap` 的 UTF-8 字节数；`exportCharacters` 是最终导入码字符数。两种模式仍受原有 500000 字符硬上限、255 字节宏上限及结构校验约束。预算失败发生在替换已有产物之前。

release 默认 `logs.persist: "manual"`、`maxBytes: 32768`，阶段完成和退出不再自动改写 `IG_PERF_LOG_V1`。`ctx.perf.saveLog()` 仍可明确保存日志；内存诊断、`ctx.ui.showLog()`、错误提示和游戏存档继续工作。可以覆盖为 `auto`；`maxBytes` 范围为 4096–190000。已有实例中的旧日志不自动删除，下次明确保存才替换。此策略不修改存档格式或移除备份。

## 依赖锁与复现

```powershell
# 首次建立锁，或审阅引擎依赖变化后更新锁。
npm run build:all -- --update-lock

# 发布/CI：输入与锁不匹配则失败。
npm run build:all -- --frozen-lockfile
npm run build:all -- --frozen-lockfile --verify-only
```

单项目构建接受同样的选项。项目 `item-game.lock.json` 保存目录版本/哈希、请求与解析后的包列表、选中模块的 SHA-256，以及构建器/编译器/编码器/npm 锁文件指纹。未选择的 Lua 文件变化不令该项目锁失效。锁不冻结游戏源码，也不取代 `sourceHash` 或道具发行版本。普通开发构建不强制校验锁；发布流程应显式使用 frozen 模式。

每次成功构建在 dist 写出实际使用的 `package-lock.json`；只有 `--update-lock` 才更新项目源目录的锁。frozen/verify 不更新锁。目录版本或构建工具变化需要重新审阅锁。报告记录 Node、zlib、luaparse 版本；跨机器复现应使用相同工具链并先 `npm ci`。

`--previous <report>` 继续检查 rootId/publisher/createdAt 不变、objectVersion 增长和有效变化。构建模式、包选择、选中源码和工具变化都进入包指纹，不复用不匹配的旧运行时。

## 产物与错误回查

| 文件 | 用途 | 是否进入道具 |
| --- | --- | --- |
| item.t3e.txt | 唯一需要导入的完整道具码 | 是 |
| engine.generated.lua | 与 wf_bootstrap 逐字一致的最终源码 | 已在导入码内 |
| engine.debug.lua | 同一候选的可读组装源码 | 否 |
| engine.source-map.json | 最终代码映射到可读源码与原文件 | 否 |
| package-lock.json | 此次构建实际使用的依赖快照 | 否 |
| build-report.json | 包列表、自动依赖、分文件体积、预算、哈希与工具链 | 否 |

源码映射的偏移是 JavaScript UTF-16 code unit，行号从 1 开始。保留代码行边界，使 WoW 的行号错误可回查，而不是将引擎压成一行。

```powershell
# engine.generated.lua 中的行号。
node tools/trace-item-game.mjs items/arcane-cube/dist 123

# 确定来自 wf_bootstrap Lua 效果的 Generated code:124 错误。
# 固定上游执行器增加一行 return function(args)，该选项自动扣除。
node tools/trace-item-game.mjs items/arcane-cube/dist 124 --trp3
```

工具核对最终/可读源码哈希，返回原文件、原行号与文本。其他工作流也叫 Generated code，不能把 wf_open 或外层工作流的行号套进 bootstrap 映射。

## 引擎维护与验证

`framework/item-game/packages.json` 定义包描述、依赖和拥有的模块；`moduleOrder` 是明确的安装顺序。模块先安装 API 定义，跨包对象在全部安装完成后创建。扩展时给模块唯一归属，补齐依赖并维护安装顺序。旧式 engine 目录没有目录文件时可沿用内置模块目录；按需构建还要求该引擎具备 0.4.0 的可选系统装配能力。

```powershell
npm run build:all -- --frozen-lockfile
npm test
npm run test:native
```

新增回归覆盖依赖解析、锁漂移、预算失败保留旧产物、Lua 词法边界、源码映射、最小包、无粒子 Scene3D 和日志策略。最小包经过真实 Lua 5.1、上游 AceSerializer、TRP3 工作流编译器、延时和单次注入执行；图形/音频 API 由明确标记的 WoW mock 提供。魔方和塔防另有生成道具启动/交互检查。这不构成 WoW 客户端的视觉、声音、性能或双客户端交易验收。

精简器参考 [luamin](https://github.com/mathiasbynens/luamin) 的 token 边界处理思路，未引入其代码或变量改名流程。仅使用现有 luaparse 依赖；原生 Lua 回归补足 JavaScript 解析器与宿主词法差异。
