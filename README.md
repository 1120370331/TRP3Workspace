# TRP3 Item Workshop

面向 Total RP 3（TRP3）物品脚本的源码仓库。仓库保存可复用框架、完整应用实例，以及今后按物品拆分的实现。

## 目录

```text
framework/
  octopus/       Octopus 通用 Lua 框架
  ovo/           Ovo 文档像素渲染框架
apps/
  rprecorder/    RP 记录员，完整可部署的应用实例
items/           今后的独立 TRP3 道具
docs/             API、架构与研究文档
references/      Total RP 3 与 Extended 上游源码子模块
```

## 当前内容

- `framework/octopus/Octopus.lua`：提供表操作、菜单构建、数据存储、音效、监听器、资源和脚本调度能力。
- `framework/ovo/ovo.lua`：从 TRP3 文档读取 RGB 数据并渲染为像素图。
- `apps/rprecorder/RPRecorder.lua`：记录和回放游戏内聊天信息的完整示例，含菜单、事件监听、持久化和播放逻辑。
- `docs/API.docx`：现有 Octopus API 文档。
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
