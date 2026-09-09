# ItemGame 0.4.2 引擎

0.4.2 为像素皮肤补充矩形UV子区域快速裁剪；共享一幅图案即可分配给多个实际方块。面片可用 `surfaceGroup` 标记同一表面的底板、边框和点阵覆盖层，按统一表面深度及源面顺序绘制，避免底板遮住局部图案。魔方现默认直接使用海潮皮肤。

0.4.1 新增可选 `pixel-materials` 包：将调色板/RLE点阵解码、合并成同色色块，并按模型UV映射为彩色面片。PNG只作制作预览；客户端无需外部贴图文件。支持逐面绑定、四向UV旋转、三角面裁剪和运行时解除绑定，保留原始模型供碰撞/拾取使用。用法见[3D指南](../../docs/ITEM-GAME-3D.md)及[奥术魔方材质试验](../../items/arcane-cube/art/README.md)。

0.4.0 新增[本地包管理与发行构建](../../docs/ITEM-GAME-PACKAGES.md)：项目通过 `packages` 选择能力，构建器自动解析依赖，支持 Lua 发布精简、源码映射、依赖锁和体积预算。Runtime 按选包创建 World/音频/二维特效，Scene3D 可不带三维粒子。未配置项目仍全量打包；release 默认按需持久化日志。魔方、两种塔防已采用各自选包配置，API/saveVersion 保持兼容。

0.3.1 加入独立三维粒子系统 `scene.particles`：球面/环形/锥形发射、三轴速度和重力、阻力、世界空间跟随、粒子及发射器预算、优先级淘汰、暂停和回收。粒子与几何共享镜头及面排序，不占用场景节点。新增节点级变换/投影缓存、视锥内快速路径和按稳定面ID复用原生绘图对象，减少高阶魔方的重复运算与属性设置。魔方复原会播放五式烟花，可在“烟花试验”运行24秒对照并导出日志。

0.3.0 新增可选 `ctx.scene3d`：独立三维场景图、父子变换、透视摄像机、六面视锥裁剪、射线拾取、AABB 查询/扫掠和运动学推进。WoW 适配器将三维凸面投影为原生 Texture 顶点，按深度绘制并复用对象池。现有 World/Surface 的二维语义保持兼容。它是有界的几何后端，不提供 GPU 深度缓冲或完整刚体物理；详见 [3D 开发指南](../../docs/ITEM-GAME-3D.md)。[奥术魔方](../../items/arcane-cube/README.md) 是使用同一套接口的 2–7 阶游戏与验证项目。

0.2.3 增加音效总音量、混音总线音量、可配置声部预算和单音效并发上限；减少密集请求的重复声部查询。高优先级声音成功起播后才停止被抢占的旧声部。音量通过原生SoundKit参数控制，不修改全局CVar。

0.2.2 增加原生双切面棱晶粒子和初速度朝向；用于寒冰命中的尖锐爆裂效果。每颗棱晶两张纹理，沿用全局粒子预算和池复用。

0.2.1 修正粒子实机锚点、跨发射器/爆发的统一预算、默认结束尺寸二次缩放；空闲栈与粒子表复用减少分配，缓存绘制属性避免重复调用。新增延迟、淡入、长宽比、原生遮罩及可见/峰值/淘汰统计。生物大战天灾使用独立的 `vfx.lua` 配方组合豌豆命中、寒冰命中和爆炸，伤害仍由游戏规则结算。

已实现的 Lua 5.1 引擎和 TRP3 装配工具。0.1.1 已在 WoW 12.1.0 / TRP3E 1061 跑完自动基准；当前 0.2.0 新增有界纹理粒子系统，并保留共享模型、启动、音频和 Esc/关闭修复，客户端仍需复测。完整路径见[性能测试项目](../../items/performance-lab/README.md)。

文档入口：[游戏开发](../../docs/ITEM-GAME-DEVELOPER-GUIDE.md) · [引擎维护](../../docs/ITEM-GAME-MAINTENANCE.md) · [常见问题](../../docs/ITEM-GAME-FAQ.md) · [架构设计](../../docs/ITEM-GAME-ENGINE-DESIGN.md)。

## 构建与调用

```powershell
npm ci
npm run build
```

构建器将模块、游戏工厂和注册代码打入根物品 `wf_bootstrap`，将配置拆入内部文档，生成六个工作流和可导入字符串。源码不会在 Node 构建过程中执行。

打包前会将入口、游戏模块和引擎源码的 CRLF/CR 换行统一为 LF，再计算哈希和编译。TRP3 的外层工作流只转义 LF，原样嵌入 CR 会导致 `unfinished string` 并将长段源码打印到聊天框。导入回读的字节一致性指规范化后的打包源码。

作者提交 `item.json`、`content.json`、`game.lua`。完整的现有输入见 `items/performance-lab/`。发布清单包含稳定 rootId、精确 publisher、创建/保存时间、对象版本、引擎 API 版本和目标 TRP3E 版本；仅填写游戏名不足以出包。

游戏也可声明共享引擎目录和自己的 Lua 模块：`"engine": "../../framework/item-game"`、`"modules": {"ui": "src/ui.lua", "sprites": "src/sprites.lua"}`。构建器在编译时读取这些源码，一起装入道具；游戏入口可返回 `function(ctx, modules)` 使用模块的返回值。模块不在构建机执行，也不在 WoW 中通过路径加载。游戏目录只维护本游戏的界面、规则和素材；通用能力继续维护在引擎目录。完整项目见 [garden-defense](../../items/garden-defense/README.md)。省略 engine/modules 的现有单文件游戏保持兼容。

```lua
return function(ctx)
    local hero
    return {
        onStart = function()
            ctx.level.load("arena_01")
            hero = ctx.world.spawn("hero", {x=100, y=20})
        end,
        onFixedUpdate = function(dt, input)
            ctx.motion.setIntent(hero, {moveX=input.moveX, jumpPressed=input.jumpPressed})
            if input.attackPressed then ctx.combat.requestAction(hero, "slash") end
        end,
        onSave = function() return {checkpoint="arena_01"} end,
    }
end
```

角色、动作和关卡 ID 需在该游戏的 content.json 中存在。引擎自动调用工厂和回调，不由游戏脚本创建第二个 OnUpdate。

## 文件和职责

`surface-actors.lua` 提供可选共享模型场景、Actor 资源预热与复用，以及由战局时钟采样的动作播放；通过 `content.surfaceModelScene=true` 启用。`audio.lua` 支持按声音组的动态密度限流、并发上限和短暂让声。具体字段见游戏开发指南。

共享模型使用稳定待机边界测量体型，支持独立的 `anchorX/anchorY` 脚底坐标、`modelAnchor` 局部锚点、`scale` 和 `fitFill`。按原生投影拟合目标像素尺寸；单模型投影失败单独隐藏并重试，UI缩放变化在暂停期间也会重新校准。用法见[模型位置与尺寸](../../docs/ITEM-GAME-DEVELOPER-GUIDE.md)。

| 文件 | 实际能力 |
| --- | --- |
| core.lua | 有界 JSON 编解码、资源作用域、阶段事件分发 |
| runtime.lua | 注册游戏、ctx 门面、固定步长、回调、暂停/退出、存档与操作记录 |
| host.lua | TRP3 实例定位、物品变量、原生事件、库存/交易、WoW 音频接口 |
| input.lua | 有限键集读取、键盘接管、短按边沿缓存、输入释放 |
| surface.lua | 画布 rect/text/button/texture/model 节点、平铺/UV/混合、模型镜头/动画及回退、稳定 ID 与对象池；左上角坐标 |
| view.lua | 窗口、按钮、日志/文本输入面板、纹理/模型池、PlayerModel 与共享 ModelScene、血条/碰撞框 |
| world.lua | 实体、移动/跳跃/地形、AABB/swept AABB、Grid/Naive 查询、动作、基础追击 AI、伤害与死亡 |
| audio.lua | Sound 句柄与限频、默认 SFX 通道的 Native BGM、可选 Musician 独立本机曲目 |
| effects.lua | 有界 Texture 粒子与发射器、固定步长推进、逐帧插值、世界/屏幕坐标、对象池与降级统计 |
| telemetry.lua | 预热/采样、直方图分位数、阶段汇总、NDJSON、有界日志保留 |

## 当前 ctx 接口

| 接口 | 说明 |
| --- | --- |
| session.pause / resume / stop / isPaused | 操作本场生命周期 |
| world.spawn / despawn / clear / get / count | spawn 解析 prefab 并装配显示/碰撞；get 用于本场逻辑和诊断，不把返回表写入存档 |
| level.load / checkpoint | 场景装配与检查点保存请求 |
| motion.setIntent / combat.requestAction | 提交移动、跳跃和攻击意图 |
| collision.query / sweep / setBroadphase | AABB 查询、扫掠、grid/naive 对照 |
| input.acquire / release / readKey / emitAction | 接管/释放及小游戏动作；不发送系统按键 |
| events.on / emit | 本场事件；订阅随退出销毁 |
| clock.now / wall / after | 游戏时间、实际时间、可取消的游戏时间任务 |
| save.data / request / flush / probe | 读档、合并保存、同步保存并核对变量、往返测试；flush 不代表磁盘刷盘 |
| inventory.count / grant / consume | 本游戏材料/装备；写操作要求 operationId，结果须检查 |
| trade.open | 打开当前目标或指定目标的原生交易窗口，确认和拖入物品由原生 UI 完成 |
| sound.play / stop / stopOwner / setEnabled / setVolume / getVolume / setBusVolume / getBusVolume / capabilities | 本机音效、独立音量及限频 |
| music.play / playCode / pause / resume / stop / setEnabled / setBackend / getBackend / setVolume / getVolume / capabilities | Native 或 Musician；音量与暂停能力依当前后端而定 |
| fx.burst / start / stop / clear / stats | 爆发或持续纹理特效；自动服从暂停、倍速、容量和整场清理 |
| ui.button / notify / status / prompt / showLog / toggleBounds | 有限数量的游戏/测试 UI |
| ui.surface | 懒创建本场 2D Surface，提供 begin/draw/finish；退出由 View 回收 |
| assets.recordModels | 记录文件 ID、加载状态、逻辑碰撞框及可取得的 Actor 包围盒 |
| perf.begin / finish / isRunning / note / measure / stats / saveLog | 性能阶段和结构化记录 |
| data.encode / decode | 有界 JSON，禁止执行数据中的 Lua |

回调：`onStart` 必需；`onFixedUpdate`、`onFrame`、`onPause`、`onResume`、`onSave`、`onStop` 可选。`onFrame` 每个未暂停的显示帧调用一次，用于测试阶段控制等实际时间逻辑；物理仍只由固定步长驱动。

Surface 先 begin，再用稳定 ID 逐个 draw，最后 finish 隐藏本轮未绘制节点；支持 rect/text/button/texture/model/cooldown/panel、0–30 层，每场最多 3600 个不同 ID，同 ID 不可改变 kind/layer。其坐标为左上角、向右/向下；World 为实体脚底中心、向右/向上。示例见[开发指南](../../docs/ITEM-GAME-DEVELOPER-GUIDE.md)。

IG 0.2.5 新增原生面板：`ui.draw("panel", {kind="panel", layout="Dialog", asset="paper", x=20,y=20,w=400,h=240,layer=10,color={1,1,1,1}})`。`NineSliceUtil.ApplyLayoutByName` 使用客户端定义的四角/四边及实际图集尺寸，在当前逻辑层的普通 Frame 上组合，避免套用固定500帧层级的模板；面板不接收鼠标。`asset` 可为 `QuestBG-Parchment` 等 atlas，保留客户端裁切坐标；缺少原生边框 API 时记录 `surface.panel` 并保留底图。退出时随 Surface 隐藏及回收。

`kind="button", nativeButton=true` 使用 `UIPanelButtonTemplate` 的边框、按下、高亮与禁用样式。原生按钮与普通按钮分池，同一按钮 ID 的模板不可在运行中改变。场景文本、音效回调和点击权限仍由 Surface 管理，透明战场命中区无需使用模板。

粒子特效声明在 `content.effects`，纹理引用 `assets.textures`。`ctx.fx.burst(id,params)` 产生一次爆发；`ctx.fx.start(id,params)` 启动 `mode:"continuous"` 发射器并返回句柄。粒子不进入 World/Collision，也不占用 Surface 稳定 ID；逻辑由固定步长推进，显示在既有帧中插值。`space:"screen"` 使用左上角坐标，`space:"world"` 使用 World 坐标和 View 相机。`params.entityId` 让持续发射器跟随实体，新粒子出生后独立运动。容量由 `maxParticles/maxEmitters/maxParticleSpawnsPerStep` 控制；满池丢弃低优先级新粒子，高优先级可替换最旧的低优先级粒子，并记录 `particlesDropped`。配置与示例见开发指南。

`texture` 的 `asset` 引用 `content.assets.textures`（`fileID/id` 或 `texturePath/path`），支持 `texCoord={left,right,top,bottom}`、`tile=true`、`color` 和 `blend`；button 也可设置 asset 作为原生背景。`model` 的 asset 引用 `content.assets.models`，使用 PlayerModel，支持 `scale/distance/facing/animation/paused`；模型定义的 `fallback` 指向纹理目录。失败或加载超时显示图标，finish 隐藏时清除模型，dispose 解除回调。可通过 `limits.maxSurfaceModels` 设置1–128的对象预算，默认104；实例数量与加载/回退状态计入 `surface.stats()` 和引擎统计。具体游戏示例见[魔兽材质模型版](../../items/garden-defense-wow/README.md)。

模型目录也支持 `kind:"petSpeciesID"`、`id` 和可选 `displayIndex`。Surface、PlayerModel prefab 与 ModelScene 共用 `E.resolveModel`：查询 Pet Journal 的显示 ID，并用完整的 `SetDisplayInfo` / `SetModelByCreatureDisplayID` 加载皮肤；绝不将该 API 的 NPC `creatureID` 当显示 ID。Surface 会在3秒内重试暂时缺失的元数据，失败回退图标。此查询不召唤宠物、不更改收藏过滤器，也不要求拥有该宠物。

音效定义可指定 `channel`、`priority`（默认0）、`maxConcurrent`。总预算 `limits.maxSoundVoices` 默认12、范围1–32，生物大战天灾设为16；高优先级声音成功起播后才抢占最低优先级的旧声部。组间并发独立，同组仍受预算和冷却限制。Master 通道的界面反馈遵守总声音开关及主音量，不跟随 SFX 子通道开关；引擎不改 CVar。

`ctx.session.setSpeed(speed)` / `getSpeed()` 控制固定步长推进相对于实际时间的倍率，默认1，范围0.25–4；暂停不推进，也不在恢复时补算暂停时间。Surface 新增 `kind:"cooldown"`，传入逻辑时间的 `duration/remaining`，自动转换倍率并通过原生 Cooldown 控件绘制转盘，随暂停/恢复冻结和继续。原生数字隐藏，游戏可自行保留文字倒计时；节点隐藏和退出时清理。

游戏可返回可选回调 `onCloseRequested(reason)` 自行处理 `escape`、`window_closed`、`window_hidden`；未声明时保持关闭并清理的默认行为。`ctx.session.suspend()` 暂停并收起窗口但保留场次，重新使用同一道具会重新显示；`isStopped()` 可避免退出按钮执行后继续播放音效或绘图。Esc 通过无可见内容的 UISpecialFrames 代理转发，避免宿主先隐藏游戏窗口。需要“保存失败不退出”的游戏应先 `save.flush` 核对成功，再 `session.stop(reason,{save=false})`；这些游戏业务策略仍由各项目拥有。

模型可设置 `fitToBounds:true`，以 ModelScene Actor 的实际边界取景，使用 `fitFill`（0.35–0.9，默认0.82）控制留白；未开启时保持 PlayerModel 后端。`E.fitModelBounds` 在模型的本地坐标中读取边界、处理朝向、计算投影并对齐脚下。有效边界缓存到模型切换为止，避免动画造成镜头抖动。

`fallbackMode:"model"` 禁用模型的图标兜底，主通道失败时用相同完整显示 ID 的 PlayerModel 备用通道，镜头由 `fallbackDistance` 控制。模型边界初始化前会解除本场景暂停，取得边界后恢复游戏暂停状态。两条通道均失败则请求暂停并记录 `model.unavailable`。备用池仅在需要时创建，和主池分别受 `maxSurfaceModels` 限制；同时只显示一条通道，统计中的 pooledSurfaceModels 为两池对象之和。未指定 fallbackMode 的旧游戏保持图标兜底。

`surface.draw` 的模型节点支持 `depth`，默认取显示框底部；同层模型按该值递增显示，数值更大者在前。逻辑层之间留出模型排序区，工具/菜单仍可放在更高逻辑层。模型容器不裁切邻格，是否允许跨格由游戏的显示尺寸决定；Surface 不修改 World 碰撞框。日志面板与关闭按钮保持在所有 Surface 层上方。

Surface 逻辑层间距为288，保留128个模型的排序空间，同时避免结算、设置等高逻辑层超过 WoW 的10000帧层级上限而被压到同层。根画布和所有装饰层显式禁用鼠标，仅实际按钮响应点击。日志面板保留在9500附近。相关回归通过有效层级和坐标选择实际命中按钮，避免只调用按钮回调而遗漏遮罩拦截问题。

## Native BGM 配置与诊断

音频通用能力位于共享 `audio.lua`，由 `runtime.lua` 为每个游戏场次创建 `ctx.sound` / `ctx.music`，经 `host.lua` 对接客户端接口：

- 音效：总声部预算、按声音/分组的并发上限、限频、优先级抢占、失败退避、声音结束回收，以及整体/总线音量。声音可在预算内叠加；满额或限频时按策略丢弃/抢占，不承诺无限并发。
- 音乐：曲目切换、循环、开关、独立增益、句柄生命周期及后端能力查询。音乐与音效的音量及声音句柄分别管理。
- 游戏层负责内容目录、预算参数、UI 和存档字段。植物大战僵尸的16声部、`impact` 默认50%、昼夜选曲与 `musicVolume` 保存均为调用这些通用接口的游戏配置；引擎不依赖任何植物、关卡或音乐页面。

```json
{ "music": { "arena": { "nativeFileId": 1061171, "channel": "SFX" } } }
```

`nativeFileId` 是正整数 FileDataID；`channel` 可省略，默认 `SFX`，仅允许 `SFX` 或 `Music`。SFX 不受 WoW 区域音乐开关影响，但仍遵守总声音/SFX 开关和音量；显式 Music 跟随音乐设置。引擎不修改全局 CVar。

IG 0.2.4 新增 `ctx.music.setVolume(0..1)` / `getVolume()`，默认1，与音效音量独立。需要低于100%播放的原生曲目应配置 `volumeSoundKitID`（正整数）及可选 `baseVolume`（0..1，直接文件建议1），利用宿主 `C_Sound.PlaySoundWithOptions.volumeOverride`。必须确认 SoundKit 包含选定曲目；需要固定歌曲时应选择无子 SoundKit 的单文件 SoundKit。100%仍直接播放原文件，保留旧客户端兼容性。无映射或旧客户端不支持非100%增益时明确返回失败，不改全局音量。

`ctx.music.capabilities(trackId).independentVolume` 按当前/待播放后端决定是否启用控件。原生音量0立即停止本场曲目并进入 `muted`；运行中调整原生音量会从头重播，暂停时只保存音量。`nativePauseMode` 固定为 `restart`，不承诺原生音频断点续播。Musician 不支持单曲增益：非零音量仅为原生回退保留，MIDI 不按百分比降低音量；0仍静音，调回非零从曲目游标恢复。界面必须说明限制，不应把保留的原生音量显示为 MIDI 的实际音量。游戏如需持久化音量，应保存 `getVolume()`。

IG 0.2.6 的可选 MIDI 后端：在同一曲目中同时提供 `musicianCode` 与 `nativeFileId`，默认 `auto` 优先 Musician；缺少插件、插件被静音/占用、导入失败或超过30秒时回退原生。`setBackend("native")` 强制原生，`setBackend("auto")` 恢复自动；改变偏好清理本场旧曲目，调用方再 `play` 对应场景曲目。导入错误在本会话内记忆，`play(id,{retry=true})` 或切换后端可重试，不反复自动重载坏曲目。

正常暂停保留同一个 Musician Song 和游标，以 `Stop` / `Resume` 续播；相同曲目的重复 `play` 不销毁暂停态。显式 `stop`、换曲、切换后端或退出会销毁旧对象，因此不承诺跨换曲或重新载入道具恢复位置。`play(id,{playWhilePaused=true})` 只用于用户主动试听，支持异步导入后在战局暂停中播放；普通导入完成时仍遵守暂停状态。晚到回调按会话代数和对象身份丢弃，停止后不会复活播放。只使用 Song 本地播放，不调用广播/演奏接口。

Musician 播放调用期间临时抑制其 `autoAdjustAudioSettings`，同步调用结束立即恢复原值，避免自动改写 SFX/Dialog 音量和声音缓存 CVar；不修改已保存的 Musician 选项。Musician 自身采样通道、静音等设置仍生效。可选游戏回调 `onMusicChanged()` 会在异步状态变化时安全通知界面，暂停期间也可刷新“加载/回退”提示；停止清理期间不再通知。

`ctx.music.play("arena", {loop=true})` 返回是否接受/开始播放和原因。Native 成功不代表已经耳听验收；Musician 的 true 还可能只是接受了异步导入。`ctx.music.capabilities().nativeDefaultChannel` 为 SFX；`ctx.music.state / channel / lastError` 可诊断当前状态，stop 会清除通道和错误。`ctx.perf.stats()` 也提供 `musicState / musicChannel / musicError`。

`music.playback` 记录 trackId、fileID、channel、ok、reason 和可取得的 audio.cvars 快照。频道/音量关闭与资源/API 失败分开报告，详见[FAQ](../../docs/ITEM-GAME-FAQ.md)。Native 暂停后从曲首恢复，循环依赖宿主可报告播放结束；不承诺无缝衔接。

## 当前边界

原生编辑器每次保存递增 MD.V，不会自动改写包内 objectVersion。Host 记录启动时的定义修订号，只在运行中修订号或清单变化时关闭。run.start 中 objectVersion 表示构建版本，objectRevision 表示本机道具修订；启动提示同时显示两者。

Esc 在普通、接管、暂停状态关闭主界面，文本框有焦点时先返回；X 始终退出。退出先隐藏窗口/释放输入，再分步保存和清理；异常写 cleanup.*，不阻止其余步骤。暂停应使用 ctx.session.pause 的游戏按钮。

- 支持矩形和扫掠矩形；复杂物理、圆形/多边形判定、行为树与联网战斗尚未加入。
- 不做任意存档自动迁移。较新或不匹配的版本会保留原值并拒绝覆盖；格式损坏才尝试有效备份。
- 独立装备可发放并保存/显示 `IG_EQUIP_V1` 属性；角色如何使用装备词条由游戏规则定义。
- Musician 为可选增强；没有自建通用 MIDI 合成器。其自身音频设置可能影响 WoW BGM，需单独验证。
- 函数返回和模型 loaded 只表示接口/加载状态，不代表模型视觉、音乐可听性或音频时延通过验收。
- `wf_stop` 用物品变量发送停止请求；手动销毁后主要由原生背包通知立即清理，低频所有权检查兜底。
- 启动按“253 字节短宏 → 原生延时 0.1 秒 → 限定 Lua”编排；253 字节对应当前性能台根 ID，实际硬上限为 255 字节。短宏仅准备本根物品的单次注入，用完或两秒后恢复，限定脚本不提升权限。此链已在首轮客户端跑通，改桥接后仍需重测。

## 验证

```powershell
powershell -NoProfile -File tools/setup-tests.ps1
npm run build
npm test
```

setup 只在仓库 `.local-tools/` 安装 Lua 测试运行时，并下载校验哈希固定的 AceSerializer 测试参考。Node 测试覆盖编解码、原有导出样本、发布身份与坏输入；Lua 5.1 测试覆盖真实代码的生命周期、物理、输入、存档、音频回调和生成道具的沙盒启动。模拟宿主不提供 WoW 性能证据。
