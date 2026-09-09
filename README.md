# TRP3 Item Workshop

面向 Total RP 3（TRP3）物品脚本的源码仓库。仓库保存可复用框架、完整应用实例，以及按物品打包的实现。

## 目录

```text
framework/
  octopus/       Octopus 通用 Lua 框架
  ovo/           Ovo 文档像素渲染框架
  item-game/     单道具游戏引擎及 ctx API
apps/
  rprecorder/    RP 记录员，完整可部署的应用实例
items/           独立 TRP3 道具与性能测试项目
docs/             API、架构与研究文档
references/      Total RP 3 与 Extended 上游源码子模块
```

## 当前内容

- `framework/octopus/Octopus.lua`：提供表操作、菜单构建、数据存储、音效、监听器、资源和脚本调度能力。
- `framework/ovo/ovo.lua`：从 TRP3 文档读取 RGB 数据并渲染为像素图。
- [framework/item-game/](framework/item-game/README.md)：Lua 5.1 游戏引擎，含输入、渲染、碰撞、AI、存档、Sound/Music 和性能日志。
- [items/performance-lab/](items/performance-lab/README.md)：21 阶段性能测试台及可导入的完整 TRP3 道具测试候选。
- [items/arcane-cube/](items/arcane-cube/README.md)：基于新增 [Scene3D](docs/ITEM-GAME-3D.md) 的 2–7 阶奥术魔方，支持自由视角、内层转动、计时、撤销、回放复原与存档。
- ItemGame 文档：[游戏开发指南](docs/ITEM-GAME-DEVELOPER-GUIDE.md) · [引擎维护指南](docs/ITEM-GAME-MAINTENANCE.md) · [常见问题 FAQ](docs/ITEM-GAME-FAQ.md) · [架构概览](docs/ITEM-GAME-ENGINE-DESIGN.md)。
- `tools/build-item-game.mjs` / `tools/analyze-perf-log.mjs`：完整道具构建、结构回读、安全元数据，以及 NDJSON 日志转 Markdown/CSV/JSON 报告。
- [包管理与发行构建](docs/ITEM-GAME-PACKAGES.md)：各项目按需选包、Lua 发布精简、依赖锁、体积预算及错误源码回查；`npm run build:all` 构建全部项目。
- `apps/rprecorder/RPRecorder.lua`：记录和回放游戏内聊天信息的完整示例，含菜单、事件监听、持久化和播放逻辑。
- `docs/API.docx`：现有 Octopus API 文档。
- `docs/TRP3-EXTENDED-LUA-PACKAGING.md`：Lua 源码构建为 TRP3 Extended 短导入字符串时的身份、版本、编码、发布与验收规格。
- `references/total-rp-3` 与 `references/total-rp-3-extended`：上游插件源码的固定 Git 子模块，用于追踪宿主实现而不复制其历史。
- `references/decoded/abyss-aquarium/`：从 TRP3 Extended 短导出反解析的只读参考项目；保留原始导出和可读 JSON。
- `docs/research/rpbox/`：来自 RPBox 提交 `8485f74be09f038218b54717101c6ab9beb81004` 的研究快照。

`RPRecorder.lua` 是可直接放入 TRP3 的独立脚本，内部包含一份 Octopus 实现（版本 1.2.0）；它并不从 `framework/octopus/Octopus.lua` 导入。后者目前保留为独立框架版本（1.1.5）。在未专门完成版本统一前，请不要将两者视为可自动替换的依赖关系。

## 新道具约定

每个新道具放在 `items/<item-slug>/`。目录应包含可粘贴到 TRP3 的 Lua 脚本，并在需要时附加简短的 `README.md`，写明用途、TRP3 工作流/变量依赖和安装方式。框架 API 发生改变时，同步更新 `docs/`。

## 参考源码与研究

克隆仓库后，用以下命令取得与当前提交一致的上游参考源码：

```bash
git submodule update --init --recursive
```

`docs/research/rpbox/README.md` 说明了导入范围及一个重要但安全敏感的研究结论：`/run` 包装 `TRP3_API.script.runLuaScriptEffect` 后向 `args._G` 注入 WoW 全局 API。它会影响后续 Lua 道具的执行边界，只能用于本人完全信任的内容，并应优先采用研究中 `TRP3ItemGuard.lua` 的受控方案。

## 运行与验证

脚本运行在 TRP3 的 Lua 沙盒中，依赖宿主提供的 `args`、`getVar`、`setVar` 和 `effect` 等接口；`ovo` 还依赖 TRP3 的界面对象。因此最终验证应在游戏内对应物品或工作流中完成。本仓库暂未设置开源许可证，公开可见不等于授予再分发许可。

ItemGame 开发与验证：

```powershell
npm ci
powershell -NoProfile -File tools/setup-tests.ps1
npm run build
npm test
node tools/analyze-perf-log.mjs run.ndjson
```

ItemGame 0.1.1 已在 WoW 12.1.0 / TRP3E 1061 完成首轮自动基准；当前 0.2.0 新增有界纹理粒子并保留共享模型、启动、BGM 和 Esc/关闭修复，客户端待复测，交易/重登/退出等另行验收。模拟宿主不产生 WoW 性能结论。启动固定为“短宏 → 原生延时 0.1 秒 → Lua”：当前宏 253 字节，TRP3 上限 255 字节；注入用完或两秒后恢复，不长期开放执行器。
