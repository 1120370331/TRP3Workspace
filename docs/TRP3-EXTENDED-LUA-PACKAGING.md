# Lua 源码到 TRP3 Extended 导入字符串：构建与发布技术规格

## 1. 文档目的与当前状态

本文规定如何把仓库中的 Lua 源文件装配为 Total RP 3: Extended（下称 TRP3E）根物品，生成以 `!` 开头的短导入字符串，并在后续发布中保持同一作者、同一对象身份和可比较的递增版本。

已提供游戏专用 `tools/build-item-game.mjs` 和 `tools/lib/trp3-codec.mjs`，可生成完整性能测试道具；包含数字/字符串键保留、Lua 5.1 语法检查、已用效果的安全扫描、回读和发行版本比较。当前命令见[性能项目说明](../items/performance-lab/README.md)与[维护指南](ITEM-GAME-MAINTENANCE.md)。下文通用 `build-trp3-item.mjs` 和对应 schema 仍为规划，不能照抄其拟定命令。

ItemGame 0.1.1 已在 WoW 12.1.0 / TRP3E 1061 跑通启动和自动基准。这个样本没有验收全部升级、重登存档和双客户端交易；0.1.4 启动误退出、BGM 和 Esc/关闭修复仍需复测。

| 能力 | 当前状态 |
| --- | --- |
| 独立维护可粘贴到 TRP3E 的 Lua 脚本 | 已支持 |
| 解码 TRP3E 短导入字符串并输出可读 JSON | 已实现，见 `tools/decode-trp3-export.mjs` |
| 根据 Lua 和清单构造 TRP3E 根物品 | 游戏专用 builder 已实现；通用 build-trp3-item.mjs 未实现 |
| AceSerializer 编码、压缩和可打印编码 | codec 已实现，支持类型保留回读；原生 AceSerializer 参考检查通过 |
| 固定根 ID、固定创建者、递增对象版本 | 游戏 builder 校验清单；--previous 检查发行身份、版本递增和有效变化 |
| 游戏内导入后使用、启动与自动负载 | 已有上述首轮实机样本，不能外推其他客户端 |
| 完整升级、重登存档和双客户端交易 | 待相应真实路径验收 |
| 自动联网检查和推送新版本 | 不属于 TRP3E 原生短导入机制 |

第 2 节起保留通用目标契约；其中拟定文件/命令不代表已实现。游戏道具按[开发指南](ITEM-GAME-DEVELOPER-GUIDE.md)使用现有 builder，工作流见[装配设计](ITEM-GAME-ENGINE-TRP3-PACKAGE.md)，宏长度和延时见[FAQ](ITEM-GAME-FAQ.md)。

## 2. 目标与非目标

### 2.1 目标

一次构建必须能够：

1. 把一个或多个 UTF-8 Lua 源文件作为文本嵌入 TRP3E 的 `script` 效果，不在构建机上执行道具代码。
2. 由版本化清单提供物品名称、固定根 ID、创建者、对象版本和目标 TRP3E 格式版本。
3. 构造合法的根物品、工作流、入口和内部对象。
4. 生成与 TRP3E“短导出”兼容的 `!` 开头字符串。
5. 回读刚生成的字符串，并验证身份、版本、入口、引用和 Lua 字节内容没有变化。
6. 对相同输入产生确定性输出；时间字段只能来自显式输入或构建参数。

### 2.2 非目标

- 不把任意 `.lua` 文件直接当成 TRP3E 导入字符串。Lua 必须先成为完整 TRP3E 对象中的工作流效果。
- 不依赖游戏运行时读取仓库文件。WoW 插件沙盒不会从本仓库执行 `require()`。
- 不把 `MD.CB` 当作数字签名或可信身份认证。
- 不替代游戏内验收。离线回读只能证明包格式和结构，不能证明 WoW API、UI、声音、交易或存档行为正确。
- 不承诺自动更新。发行者仍需分发新字符串，用户仍需重新导入。

## 3. 制品和目录契约

普通 Lua 道具建议使用以下目录：

```text
items/<item-slug>/
├── item.json              # 发布清单，纳入版本控制
├── main.lua               # 入口脚本
├── src/                   # 可选的开发时模块
├── content.json           # 可选的内部对象/数据
├── README.md              # 安装、权限、使用和升级说明
└── dist/                  # 构建产物，不手工编辑
    ├── item.t3e.txt       # TRP3E 短导入字符串
    ├── item.decoded.json  # 回读后的诊断结构
    └── build-report.json  # 版本、哈希、大小和校验结果
```

游戏引擎类项目可以继续使用 `item.json + content.json + game.lua`；构建器应允许清单声明入口文件，而不是把文件名写死。

`dist/` 是否提交由具体发布流程决定。若提交，必须保证它来自同一提交上的清单和源码，并在报告中记录源码哈希。

## 4. 发布清单

建议的最小 `item.json` 如下：

```json
{
  "$schema": "../../schemas/trp3-item.schema.json",
  "slug": "example-item",
  "rootId": "0123456789AbCdE",
  "name": "示例道具",
  "description": "由源码构建的 TRP3 Extended 道具。",
  "icon": "inv_inscription_scroll",
  "publisher": "角色名-服务器名",
  "createdAt": "05/09/26 12:00:00",
  "objectVersion": 1,
  "releaseVersion": "1.0.0",
  "locale": "zhCN",
  "entry": {
    "source": "main.lua",
    "workflow": "onUse",
    "actionText": "使用"
  },
  "target": {
    "extendedBuild": 1061,
    "extendedDisplayVersion": "目标客户端显示版本"
  }
}
```

字段约束：

| 字段 | 约束 |
| --- | --- |
| `slug` | 仓库内稳定、唯一，只用于构建和文件名 |
| `rootId` | 首次发布后永久冻结；不能为空、不能包含 TRP3E 内部 ID 分隔符 |
| `publisher` | 必须是精确的 TRP3 玩家 ID，通常为`角色名-规范化服务器名` |
| `createdAt` | 首次发布后冻结，格式与 TRP3E 元数据一致 |
| `objectVersion` | 正整数；每次对外发布必须严格递增 |
| `releaseVersion` | 面向人的语义版本；TRP3E 不用它判断对象新旧 |
| `entry.source` | 相对物品目录的 UTF-8 Lua 源文件，不能越出该目录 |
| `target.extendedBuild` | TRP3E 格式/构建版本，不是作品版本 |
| `target.extendedDisplayVersion` | 对应目标 TRP3E 客户端显示版本，不是作品版本 |

`publisher` 不应接受任意品牌文案。TRP3 的 `player_id` 由未修饰角色名和去除空格、连字符、点号后的服务器名组成。构建前应提供一个“打印当前玩家 ID”的游戏内确认步骤，避免作者字符串和实际角色 ID 不一致。

## 5. 身份、作者与版本模型

### 5.1 对象身份

TRP3E 用导出元组的第二项，也就是根 ID，识别一个对象。升级必须保持：

```text
exportTuple[2] == manifest.rootId
```

更换根 ID 会创建另一个对象，不是原对象的升级。首次发布时应生成并登记唯一根 ID；后续构建禁止自动重新生成。

### 5.2 作者字段

根对象的 `MD` 元数据应按以下规则产生：

| TRP3E 字段 | 含义 | 发布规则 |
| --- | --- | --- |
| `MD.CB` | Created By，最初创建者 | 固定为 `publisher`，首次发布后不得变化 |
| `MD.CD` | Created Date，创建时间 | 固定为 `createdAt` |
| `MD.SB` | Saved By，最后保存者 | 默认固定为发布者；若记录实际构建角色，允许变化 |
| `MD.SD` | Saved Date，最后保存时间 | 每次构建显式写入 |

粘贴导入时，TRP3E 会比较 `MD.CB` 和本机 `Globals.player_id`：相同则写入“我的数据库”，不同则写入交换数据库。导入器还会把作者字符串登记为发送者。

这不是可信发布者机制。短导入字符串没有签名，第三方能够复制根 ID并伪造 `MD.CB`。因此文档和 UI 中只能称它为“显示作者”或“发布元数据”，不能宣称已验证作者身份。若将来需要防伪，应在 TRP3E 包外提供签名清单、发布站点校验或哈希，而不是修改原生字段语义。

### 5.3 四种容易混淆的版本

| 位置 | 含义 | 谁负责递增 |
| --- | --- | --- |
| `MD.V` | TRP3E 对象版本，原生导入器用它比较新旧 | 本项目每次发布递增 |
| 清单 `releaseVersion` | 面向用户的作品版本，例如 `1.4.0` | 项目发布流程 |
| 导出元组 `[1]` 与 `MD.tV` | 目标 TRP3E 构建/格式版本 | 随目标宿主版本更新 |
| 导出元组 `[4]` 与 `MD.dV` | 目标 TRP3E 显示版本 | 随目标宿主版本更新 |

禁止把作品的 `1.4.0` 写进 `MD.dV`。`MD.dV` 描述创建/保存对象时使用的 TRP3E 版本。作品语义版本应保存在清单、构建报告和可见说明中。

当前导入器仅在“本地已有对象的 `MD.V` 大于导入对象”时提示降级。它不会联网检查版本，也不会验证版本是否连续。因此构建器必须自行阻止以下发布：

- 同一 `rootId` 的 `objectVersion` 小于或等于已登记的上次发行版本；
- `objectVersion` 增加但源码、清单有效内容和构建目标完全没有变化；
- 有实际定义变更却复用旧 `objectVersion`；
- `rootId` 已发布后被替换。

## 6. TRP3E 根物品装配

Lua 源文件是 `script` 效果的第一个参数。一个只在使用时执行 Lua 的最小概念结构如下；这是说明结构，不是可以直接导入的 Lua 文件：

```json
{
  "TY": "IT",
  "MD": {
    "MO": "EX",
    "V": 1,
    "CB": "角色名-服务器名",
    "CD": "05/09/26 12:00:00",
    "SB": "角色名-服务器名",
    "SD": "05/09/26 12:00:00",
    "tV": 1061,
    "dV": "目标客户端显示版本",
    "LO": "zhCN"
  },
  "BA": {
    "NA": "示例道具",
    "DE": "由源码构建的 TRP3 Extended 道具。",
    "IC": "inv_inscription_scroll",
    "US": true
  },
  "US": {
    "SC": "onUse",
    "AC": "使用"
  },
  "LI": {
    "OU": "onUse"
  },
  "SC": {
    "onUse": {
      "ST": {
        "1": {
          "t": "list",
          "e": [
            {
              "id": "script",
              "args": ["<main.lua 的完整 UTF-8 文本>"]
            }
          ]
        }
      }
    }
  },
  "IN": {},
  "HA": {}
}
```

实现时必须保留 Lua 表键类型。上例中的工作流节点 `"1"` 只是 JSON 展示；TRP3E 的实际 Lua/AceSerializer 表可能需要数字键。现有解码器为了输出 JSON，会把对象键统一显示为字符串，因此解码后的 JSON不能在没有类型恢复规则的情况下直接重新编码。推荐在构建器内部用数组表示连续数字键、用对象表示字符串键，并由结构模板决定两者的转换。

装配规则：

1. `TY` 为 `IT`，需要脚本效果时 `MD.MO` 为专家模式 `EX`。
2. `BA.US` 为真，`US.SC` 指向存在的使用工作流。
3. 专家模式下若存在 `LI.OU`，宿主会优先使用它；它也必须指向同一合法工作流。
4. 每个 `SC.<workflow>.ST` 必须有入口节点 `1`，所有 `n`、分支和延迟引用必须指向存在的节点。
5. Lua 作为不透明字符串放入 `{ id = "script", args = { source } }`，构建器不得 `eval`、`loadstring` 或调用源码。
6. 开发时多个 Lua 文件需要由构建器按明确顺序拼接或包装；运行时不能依赖本地模块路径。
7. `IN` 中的内部对象随根对象一起导出；内部 ID 和引用在版本升级中也应保持稳定。

TRP3E 的脚本效果运行在受限环境中。默认可用能力包括 `string`、`table`、`math`、`pairs`、`ipairs`、`next`、`select`、`unpack`、`type`、`tonumber`、`tostring`、`date`、`effect`、`op`、`getVar` 和 `setVar`。`args._G` 不是标准能力；依赖全局 API 注入的脚本必须按[架构说明](ARCHITECTURE.md)中的受信内容边界单独处理。

## 7. 安全元数据

保存对象时，TRP3E 会遍历根对象及内部对象的工作流，根据效果 ID计算 `securityLevel` 和 `details`。`script` 效果属于低安全级别，并被登记到 `SEC_REASON_SCRIPT`。

离线构建器必须复现目标 TRP3E 版本的安全扫描，不能为了减少导入提示而直接写入 `securityLevel = 3`。最低要求是：

1. 从目标版本维护效果到安全组/等级的映射。
2. 遍历根对象和所有 `IN`、`QE`、`ST` 子对象。
3. 收集每个效果所在对象 ID，生成与宿主一致的 `details`。
4. 对未知效果采用最低安全等级并让构建失败，除非发布清单显式选择兼容策略。
5. 回读产物后重新计算一次，确认元数据没有漏掉脚本或宏。

用户仍需在游戏内审阅并决定是否接受低安全效果。固定作者字段不能绕过安全确认。

## 8. 短导入字符串编码

TRP3E 当前短导出的逻辑等价于：

```text
tuple = {
  targetExtendedBuild,
  rootId,
  rootObject,
  targetExtendedDisplayVersion
}

serialized = AceSerializer-3.0.Serialize(tuple)
escaped    = serialized 中的 | 替换为 ||
compressed = raw-DEFLATE(escaped)
printable  = LibDeflate.EncodeForPrint(compressed)
output     = "!" + printable
```

导入执行相反步骤：

```text
移除 !
→ LibDeflate.DecodeForPrint
→ raw-DEFLATE 解压
→ || 还原为 |
→ AceSerializer-3.0 安全反序列化
→ 取得 {宿主版本, 根 ID, 根对象, 宿主显示版本}
```

必须精确兼容以下细节：

- AceSerializer 协议修订为 `^1`，并支持字符串、有限数字、浮点表示、布尔值、nil 和嵌套表。
- 字符串必须遵循 AceSerializer 控制字符转义，不能只做 JSON 转义。
- 压缩层是 raw DEFLATE，不带 zlib 或 gzip 头。
- 可打印编码使用 LibDeflate 的 64 字符字母表和位排列，不能替换成标准 Base64。
- `|` 转义发生在压缩之前；顺序不能颠倒。
- 短导出 UI 假定粘贴文本小于约 500,000 字符；超过该值应构建失败或改走经游戏验证的完整文件导出流程。
- 为实现确定性构建，字符串键应按 UTF-8 字节顺序排序，数字键按数值排序；导入器不要求顺序，但发布制品需要可复现。

现有 `tools/decode-trp3-export.mjs` 已验证上述解码路径，但它是静态分析工具，不执行导入包中的 Lua。

## 9. 拟定构建器接口

建议新增：

```text
schemas/trp3-item.schema.json
tools/build-trp3-item.mjs
tools/lib/ace-serializer.mjs
tools/lib/libdeflate-print.mjs
tools/lib/trp3-object.mjs
tools/lib/trp3-security.mjs
```

拟定命令：

```powershell
node tools/build-trp3-item.mjs items/example-item/item.json
```

建议选项：

```text
--out <dir>                 覆盖默认 dist 目录
--saved-at <timestamp>      显式、可复现的 MD.SD
--verify-only               不写新包，只验证现有产物
--previous <report.json>    校验根 ID、作者和版本递增
--target-profile <name>     选择仓库登记的 TRP3E 兼容配置
```

成功输出：

- `item.t3e.txt`：用户粘贴的唯一短导入字符串；
- `item.decoded.json`：由正式解码器回读的诊断结构；
- `build-report.json`：包含根 ID、作者、对象版本、作品版本、目标宿主版本、源码 SHA-256、对象 SHA-256、导入字符串 SHA-256、字符数和所有校验结果。

任一结构或版本校验失败时不得留下看似成功的新 `item.t3e.txt`。

## 10. 发布与升级流程

### 10.1 首次发布

1. 在游戏中确认发布角色的精确 `player_id`。
2. 生成一次根 ID并写入 `item.json`；提交后冻结。
3. 设置 `objectVersion = 1`、`releaseVersion` 和固定 `createdAt`。
4. 构建、回读并审阅安全报告。
5. 在仅安装目标版本 TRP3/TRP3E 的客户端中导入。
6. 从完整数据库确认根 ID、作者和版本；把物品添加到背包后主动使用。
7. 保存构建报告和游戏内验收记录，再发布字符串。

导入字符串只登记物品定义，不等于已经把实例放入玩家背包。发布说明必须包含“导入后从数据库添加到背包”的步骤。

### 10.2 后续升级

1. 保持 `rootId`、`publisher` 和 `createdAt` 不变。
2. 修改 Lua、内容或元数据。
3. 更新面向用户的 `releaseVersion`。
4. 将 `objectVersion` 至少增加 1；推荐严格连续递增。
5. 若目标 TRP3E 版本变化，同步更新目标构建和显示版本，并重新核对效果、安全映射与对象结构。
6. 使用上一版 `build-report.json` 执行身份和版本防回退校验。
7. 回读新字符串并做游戏内升级验证。
8. 发布新字符串及变更说明。用户重新导入后，同一根 ID的定义被替换。

对象定义升级和玩家背包实例存档是两个层面。修改变量名、内部 ID、存档 schema 或材料定义时，脚本需要提供迁移逻辑；仅提高 `MD.V` 不会自动迁移业务数据。

### 10.3 回滚

不要用较小 `MD.V` 作为正式回滚版本，因为宿主会提示用户正在降级。正确做法是基于旧代码产生一个新的、更高对象版本，并在变更说明中标明内容回滚。

## 11. 构建验证门禁

### 11.1 静态门禁

- 清单符合 JSON Schema；路径不能越出物品目录。
- `rootId`、`publisher`、`createdAt` 相对上一发行版不变。
- `objectVersion` 严格大于上一发行版。
- 所有入口、工作流后继、内部对象和效果引用存在。
- Lua 文件为 UTF-8、没有意外 BOM，拼装前后字节一致。
- 不存在运行时 `require()` 或对本仓库绝对路径的依赖。
- 安全扫描覆盖全部对象，未知效果阻断构建。
- 最终导入字符串以 `!` 开头且未超过短导出限制。

对 Lua 的静态语法检查只能作为辅助。标准桌面 Lua 版本和 WoW 使用的 Lua 方言/API 不完全相同，不能以本机解释器通过代替游戏内验证。

### 11.2 回读门禁

构建后必须调用解码器读取刚生成的字符串，并至少断言：

```text
tuple[1]       == target.extendedBuild
tuple[2]       == rootId
tuple[3].TY    == "IT"
tuple[3].MD.CB == publisher
tuple[3].MD.V  == objectVersion
tuple[4]       == target.extendedDisplayVersion
```

此外应比较完整规范化对象哈希，并逐字节比较嵌入的 Lua 源码。重新编码后的字符串哈希一致，才能宣称构建可复现。

### 11.3 游戏内最小真实路径

每个发布候选至少完成一次：

1. 在干净或隔离的 SavedVariables 环境导入字符串；
2. 确认导入对话框显示正确名称、作者和 `MD.V`；
3. 从完整数据库添加到背包；
4. 审阅并设置脚本效果安全权限；
5. 点击使用，验证入口脚本；
6. `/reload` 后再次使用；
7. 在已安装旧版定义的环境重新导入新版，确认仍为同一根 ID并执行新版行为；
8. 尝试导入旧版，确认出现降级警告。

若道具涉及存档、交易、内部物品、界面或全局 API，还要执行对应专项路径，不能把最小导入测试当成完整产品验收。

## 12. 兼容性与发布风险

| 风险 | 处理方式 |
| --- | --- |
| 目标 TRP3E 改变序列化或压缩实现 | 用固定参考样本做双向兼容测试，并在升级子模块时复核 |
| JSON 丢失 Lua 数字键类型 | 使用结构模板和数组建模，不直接重编码诊断 JSON |
| 发布者字符串拼写错误 | 首次发布前从游戏内复制精确 `player_id`，构建器冻结 |
| 第三方伪造作者或根 ID | 明示原生格式无签名；发布站点额外提供哈希/签名 |
| `script` 被错误标记为高安全 | 构建器复现安全扫描，未知效果从严处理 |
| 导入成功但无法使用 | 游戏内验证工作流入口、背包实例和安全设置 |
| 更新覆盖定义但破坏旧存档 | 保持 ID并提供显式存档 schema 迁移 |
| 包体过大，输入框无法粘贴 | 构建时检查字符数；压缩数据或采用经验证的完整文件导出 |
| 依赖 `args._G` 的脚本扩大权限 | 默认拒绝；只对受信内容使用受控桥接并单独验收 |

## 13. 实施顺序与完成标准

建议按以下顺序实现，避免先构建高层模板却没有可验证的底层编解码器：

1. 从现有解码器提取可测试的 LibDeflate 可打印解码和 AceSerializer 解码模块。
2. 实现可打印编码、AceSerializer 编码和 raw DEFLATE，使用已知导出做解码—编码—解码等价测试。
3. 定义 `item.json` Schema、目标 TRP3E 版本配置和稳定 ID/版本规则。
4. 实现最小根物品与单个 `onUse` 脚本效果装配。
5. 实现结构校验和安全元数据扫描。
6. 生成短导入字符串、诊断 JSON和构建报告。
7. 用最小道具完成游戏内导入、添加背包、权限、使用、重载和升级验证。
8. 再扩展到多个工作流、内部对象、游戏引擎和内容打包。

构建技术达到可用状态必须同时满足：

- 一条命令从受版本控制的清单和 Lua 源码产生短导入字符串；
- 构建不执行道具 Lua；
- 同输入和同时间参数产生完全一致的输出；
- 回读结构与输入身份、版本和源码一致；
- 同根 ID从 `MD.V = N` 升级到 `N + 1` 的游戏内真实路径通过；
- 导入界面正确显示作者，但文档不把它描述成已认证身份；
- 脚本效果触发正常的 TRP3E 安全审阅。

## 14. 已核对的上游依据

| 结论 | 源码位置 |
| --- | --- |
| 短导出元组、`|` 转义、压缩和 `EncodeForPrint` | [`List/List.lua`](../references/total-rp-3-extended/totalRP3_Extended_Tools/List/List.lua)，导出动作 |
| 短导入的反向处理和版本比较 | [`List/List.lua`](../references/total-rp-3-extended/totalRP3_Extended_Tools/List/List.lua)，`importFunction` 与导入按钮 |
| 保存时 `MD.V` 自增并更新 `SB/SD/tV/dV` | [`Tools/Main.lua`](../references/total-rp-3-extended/totalRP3_Extended_Tools/Main.lua)，`doSave` |
| 新物品的 `CB/CD/SB/SD/V` 初始值 | [`Items/Items.lua`](../references/total-rp-3-extended/totalRP3_Extended_Tools/Items/Items.lua)，`getBlankItemData` |
| `player_id` 的角色名和服务器名组成规则 | [`Core/Globals.lua`](../references/total-rp-3/totalRP3/Core/Globals.lua)，`globals.build` |
| `script` 效果取得 `args[1]` 并调用 Lua 沙盒 | [`ScriptEffects.lua`](../references/total-rp-3-extended/totalRP3_Extended/Script/ScriptEffects.lua) 与 [`ScriptGeneration.lua`](../references/total-rp-3-extended/totalRP3_Extended/Script/ScriptGeneration.lua) |
| 专家模式 `LI.OU` 优先于 `US.SC` | [`Inventory.lua`](../references/total-rp-3-extended/totalRP3_Extended/Inventory/Inventory.lua)，`doUseSlot` |
| 脚本效果的安全分组和对象安全扫描 | [`Security.lua`](../references/total-rp-3-extended/totalRP3_Extended/Security.lua)，`transposition` 与 `computeSecurity` |
| 已验证导出样本的元数据和尺寸 | [`abyss-aquarium-technical.md`](research/abyss-aquarium-technical.md) |
