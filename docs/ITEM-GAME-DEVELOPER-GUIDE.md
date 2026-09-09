# ItemGame 游戏开发指南

0.4.0 项目可通过 `item.json.packages` 选择引擎能力，并使用 release 构建减小道具体积。包列表、依赖、`ctx.hasPackage` / `ctx.requirePackage` 与发行命令见[包管理与发行构建](ITEM-GAME-PACKAGES.md)。省略选包配置仍包含全部能力。

**做一款游戏：复制项目，改配置，写玩法，构建成一个 TRP3 道具。** 玩家只需已有的 TRP3 和 Extended，不需要安装引擎插件，也不需要激活剧本。

本文按当前实现写。完整接口见[引擎 README](../framework/item-game/README.md)，维护和排错分别见[维护指南](ITEM-GAME-MAINTENANCE.md)、[FAQ](ITEM-GAME-FAQ.md)。[模块设计](ITEM-GAME-ENGINE-MODULES.md)仍包含后续规划，不能直接当作 API 文档。

## 1. 从哪里开始

目前没有空白模板生成命令。复制 `items/performance-lab/` 的三个源文件作为起点，再替换测试玩法：

```text
items/training-arena/
  item.json       游戏的身份、版本、入口
  content.json    角色、动作、地形、模型、音频、按键、物品
  game.lua        开场、操作、胜负和进度
  dist/           构建产物，不手改

framework/item-game/*.lua     通用引擎，通常不需要修改
tools/build-item-game.mjs     完整道具构建器
```

新游戏修改 `item.json` 的 `gameId`、`slug`、`name`、`description`、`rootId` 和时间字段，确认 `publisher` 是实际作者的“角色名-服务器名”。保留入口 `game.lua`、配置 `content.json`、当前 API 版本 `1` 和明确的 `target`。

- **新游戏使用新 rootId；同一游戏升级保留 rootId。** 不要继续使用性能台的 `0905170116PLab1`，否则导入会更新性能台定义。
- rootId 只用字母和数字，并保持短小；它进入启动宏，构建器会检查完整宏不超过 255 字节。
- 升级递增 `objectVersion`，更新 `releaseVersion` 和 `savedAt`，保留 `publisher`、`createdAt`。`saveVersion` 只在存档格式确实改变时调整，当前没有自动迁移器。
- 源文件用 UTF-8 无 BOM，入口位于本游戏目录内，游戏代码不能依赖运行时 `require`。

## 2. 配置改哪里

先保留性能台配置，用下一节的短脚本验证接入，再删掉不用的测试素材。以下都是现有字段：

| 区域 | 实际字段 / 示例 | 负责什么 |
| --- | --- | --- |
| `simulationHz`、`viewport`、`limits` | 60 或 30；width/height；maxEntities | 模拟频率、逻辑画布和实体预算 |
| `controls` | left/right/jump/attack/fire → 键名数组 | A/D、方向键、Space、J、K 映射 |
| `prefabs` | width/height、motion、health、faction、actions、visual | 碰撞矩形、移动方式、生命、阵营、可用动作和显示 |
| prefab 的移动与 AI | speed、jumpSpeed、gravity；ai.action/range/interval | 移动参数及基础追击 AI |
| `actions` | windup/active/recovery、width/height、damage；projectile | 攻击时间轴、攻击框、伤害或弹体 |
| `levels` | terrain 的 x/y/w/h；可选 spawns | 地形与自动出生列表 |
| `assets.models` | kind 为 creatureDisplayID 或 fileID；id | WoW 原生模型，由 visual.asset 引用 |
| `sounds`、`feedback` | soundKitID/fileID；combat.hit → combat_hit | 音效资源和事件反馈映射 |
| `music` | nativeFileId、channel；可选 musicianCode、volumeSoundKitID、baseVolume | 内置曲目或 Musician 数据，原生独立音量见[引擎说明](../framework/item-game/README.md) |
| `items` | innerId、name；材料 stack；装备 attributes | 内部物品定义；声明本身不会发放物品 |

完整例子见[content.json](../items/performance-lab/content.json)。构建器检查主要引用和类型，但不能证明资源在当前客户端有画面或声音。当前没有通用资产搜索器或已全部验收的模型目录。

逻辑坐标以实体脚底中心为 `(x, y)`，向右/向上为正；`width/height` 是逻辑碰撞尺寸，`visual.width/height` 是显示尺寸。换模型不会自动改变判定。`level.load` 会清空现有实体；同一角色不要同时配置在 `spawns` 又在代码中生成。

## 3. 游戏怎样调用引擎

**引擎调用你的回调，你通过 `ctx` 调用引擎。** `ctx` 已绑定本次游戏、配置和正确的背包实例；用点号调用，例如 `ctx.world.spawn(...)`。

以下 `game.lua` 使用性能台现有配置，成为单敌人训练场：

```lua
return function(ctx)
    local player, enemy
    local cleared = ctx.save.data.cleared == true
    return {
        onStart = function()
            ctx.level.load("arena_01")
            player = ctx.world.spawn("hero_play", {x = 100, y = 20})
            enemy = ctx.world.spawn("enemy_play", {x = 600, y = 20})
            ctx.ui.button("接管按键", function()
                local ok, reason = ctx.input.acquire()
                if not ok then ctx.ui.notify(reason) end
            end)
            ctx.ui.button("继续", function() ctx.session.resume() end)
            ctx.ui.button("复制日志", function() ctx.ui.showLog() end)
            ctx.events.on("entity.died", function(event)
                if event.targetId == enemy then
                    cleared = true
                    ctx.ui.notify("训练完成")
                    ctx.save.request("victory")
                end
            end)
        end,
        onFixedUpdate = function(dt, input)
            ctx.motion.setIntent(player, {
                moveX = input.moveX,
                jumpPressed = input.jumpPressed,
            })
            if input.attackPressed then ctx.combat.requestAction(player, "slash") end
            if input.firePressed then ctx.combat.requestAction(player, "shoot") end
        end,
        onSave = function() return {cleared = cleared} end,
    }
end
```

接管后 A/D 移动、Space 跳跃、J 近战、K 发射；Esc 关闭游戏。默认读取/透传，未接管时这些键也可能影响 WoW。本例保存是否完成过训练，重开仍是一场新训练。需要暂停时由按钮调用 ctx.session.pause；文本框有焦点时第一次 Esc 返回主界面，第二次关闭。

`world.spawn` 返回本场实体 ID，并装配显示与碰撞。`requestAction` 返回是否接受请求；动作进行中返回 `false, "busy"`，死亡实体返回不可用状态。普通命中音效由 `feedback` 映射播放，不需要再在事件里重复播放。

### 自定义 2D 界面

固定工具按钮用 `ctx.ui.button`；自定布局用 `ctx.ui.surface()`。将以下内容放在游戏工厂里，在 onStart 和需要重绘的 onFrame 中调用 `drawHUD()`：

```lua
local surface = ctx.ui.surface()
local function drawHUD()
    surface.begin()
    surface.draw("title", {
        kind = "text", x = 20, y = 10, w = 240, h = 24,
        text = "训练场", size = 18, align = "LEFT", layer = 1,
    })
    surface.draw("save", {
        kind = "button", x = 20, y = 40, w = 120, h = 28,
        text = "保存进度", layer = 1,
        onClick = function()
            local ok, reason = ctx.save.flush("manual")
            ctx.ui.notify(ok and "已写入道具变量" or reason)
        end,
    })
    surface.finish()
end
```

Surface 坐标从画布**左上角**开始，向右/向下为正，与 World 的脚底中心、向上为正不同。支持 rect/text/button/texture/model/cooldown，按 viewport 尺寸缩放，层为 0–30。每次绘制按 begin → draw → finish；本轮没画的旧节点隐藏。ID 要稳定，同一 ID 不能换 kind/layer；每场最多 3600 个不同 ID，不能每帧生成新 ID。退出清理由 View 执行。

### 纹理粒子特效

粒子不使用 Surface ID，也不是 World 实体。先在 `content.json` 声明有界预算和特效：

```json
{
  "limits": {"maxParticles":128,"maxEmitters":16,"maxParticleSpawnsPerStep":32},
  "assets":{"textures":{"spark":{"kind":"texturePath","path":"Interface\\Cooldown\\star4"}}},
  "effects":{"hit_spark":{"texture":"spark","mode":"burst","count":18,"space":"world","layer":7,"blend":"ADD","lifetime":[0.2,0.5],"speed":[80,220],"directionDeg":[0,360],"gravity":260,"startSize":[6,14],"endSize":1,"startAlpha":1,"endAlpha":0,"startColor":[1,0.7,0.2,1],"endColor":[1,0.15,0.02,0.2],"spinDeg":[-720,720]}}
}
```

游戏代码调用：

```lua
ctx.fx.burst("hit_spark",{x=target.x,y=target.y+target.h/2,seed=attackId})
local smoke=ctx.fx.start("smoke",{entityId=enemyId,seed=enemyId}) -- 仅 continuous
ctx.fx.stop(smoke,false) -- 停止发射，已有粒子自然结束；true 立即清除该发射器的粒子
```

`screen` 坐标与 Surface 相同；`world` 坐标向上为正并应用 View 相机。方向角规定0°向右、90°向上，`gravity` 正值始终表示向下。支持颜色/透明度/尺寸/旋转插值、速度、风、阻力、散射、偏移、ADD/BLEND/MOD/ALPHAKEY及规则纹理表的 `flipbook`。暂停冻结，倍速随战局时钟，退出统一回收。`fx.stats()` 返回活动粒子、发射器、池容量及丢弃数；特效满载只能降级视觉，不应参与伤害或碰撞判定。

0.2.1 新增 `delay`（秒或范围）、`fadeIn`（秒）、`aspectRatio`（宽/高，0.1–8），可组合闪光、碎晶及稍后出现的烟雾。粒子纹理资产可给 `maskPath` 使用原生透明遮罩，素材换池时解除旧遮罩；普通 Surface 暂不消费此字段。不要将带黑色背景的发光素材直接用 BLEND 绘制。

0.2.2 新增 `shape:"crystal"`：用两张白色Texture的原生顶点构成菱形双切面，支持长宽比、旋转、颜色与尺寸动画；每颗棱晶使用两张纹理。只能配无mask、非atlas、非flipbook的普通纹理。`alignToVelocity:true` 将棱晶长轴朝向初始发射方向，`startRotationDeg`作为偏角、`spinDeg`继续驱动旋转。改回普通粒子时清除顶点形变、隐藏附加切面。

`maxParticleSpawnsPerStep` 现在是整场同一逻辑 tick 的出生上限，覆盖 burst、initialBurst 和全部发射器；同一显示帧最多出生两倍该数量，避免追帧导致瞬时分配尖峰。没有延迟补发。高优先级抢占另计 `evictedParticles/particlesEvicted`；`visibleParticles`、`peakParticles` 帮助排查低负载或裁剪。对象池使用空闲栈并复用粒子状态表。世界坐标按 View 画布底边定位，避免宽高比留白造成垂直偏移。

同一层的模型可用 `depth` 指定脚底的纵坐标，值越大显示越靠前。容器和子模型的实际层级都会校正；模型无需放进单格父容器。透明点击按钮不绘制背景，图形与模型节点不接管鼠标。游戏自行限定显示尺寸；共享引擎不认识关卡或格子。

`surface.preloadModel(asset)` 可提前排队加载模型，单个不可见预加载器顺序处理，队列上限32；`fitToBounds` 的实测边界按模型资源缓存。引擎逐帧处理资源就绪，包括游戏暂停期间。隐藏模型保留15秒以供复用，之后清除，结束会释放回调。模型帧预算包括预加载器，需在 `limits.maxSurfaceModels` 中预留一个位置。

多单位相互遮挡的游戏可设置 `content.surfaceModelScene=true`，启用 `surface-actors.lua`：同层所有 model 节点共享一个完整画布 ModelScene，`x/y/w/h` 表示目标脚底位置和体型，不创建每单位矩形视口。按 `depth` 为角色分配前后深度区间，自动补偿透视。默认模式及其他游戏不受影响。

共享模型的位置和尺寸可独立指定：

```lua
surface.draw("guard", {
    kind="model", asset="pea", layer=4,
    anchorX=172, anchorY=357, -- 画布左上起算的脚底位置
    w=90, h=80, scale=1, fitFill=1,
    depth=357,
})
```

`w/h × scale × fitFill` 是静止姿态包围盒的目标屏幕尺寸，保持模型比例，宽或高至少一项贴合目标（误差不超过0.5%）。`scale`、`fitFill` 优先取节点配置，其次取模型资产；共享模式支持 `fitFill=1`。`anchorX/anchorY` 省略时兼容旧节点的 `x+w/2`、`y+h*0.9`；显式脚底不会随体型改变，未提供 `depth` 时取 `anchorY`。`x/y/w/h` 仍可用于装饰容器，不能用容器位置判断共享 Actor 的实际位置。

引擎在几何就绪后的下一帧测量冻结的待机姿态，缓存 `GetActiveBoundingBox`；连续0.5秒仍不可用才退回最大边界。最大边界可能包含其他动画的额外范围，不应优先用它计算站立体型。默认模型锚点为待机边界底面中心；原点特殊的资源可在资产或节点设置 `modelAnchor={x=0,y=0,z=0}`（模型局部单位），将原生脚底精确绑定到屏幕锚点。`node.modelAnchor / boundsSource / projectedAnchor` 可用于诊断。尺寸只约束测量姿态，攻击中伸出的武器和特效仍可越出该范围，不因每帧重测而缩放抖动。

共享模式将相同 `depth` 合并为一个深度区间，采用0.55弧度视角和0.01模型单位/逻辑像素的坐标。启用 `SetAllowOverlappedModels(true)` 并清除雾，避免依赖超远镜头。读取边界统一用 `E.readModelBounds(actor, method)`，兼容六数值与两个向量两种客户端返回形式；世界模型诊断和独立视口也使用这个归一化入口。加载失败不应改变游戏暂停状态：模型后端仅记录失败并重试，暂停由游戏或用户操作决定。

原生 Actor 的平移属于缩放前的坐标，世界原点位置为 `actor:GetPosition() * actor:GetScale()`。共享渲染器将目标世界位置除以模型缩放，再叠加局部锚点偏移。离线投影检查必须应用这一原生变换，不能直接把 `SetPosition` 参数当作世界坐标，否则会漏检不同体型的错位。

原生加载流程为：解析显示ID → `Actor:SetModelByCreatureDisplayID` → 等待 `IsLoaded()` → 身份变换完成一帧后读取有效边界 → 拟合/定位 → `SetAlpha(1)` 与 `Show()`。不要把 `IsGeoReady()` 当作前置门槛：WoW 12.1.0 实测它在模型和边界均可用时仍持续为false，会使所有 Actor 卡在半透明探测阶段。客户端证据见模型版项目的 `research/model-rendering.md`。

共享渲染现在直接采样 `ModelScene:Project3DPointTo2D` 在各深度平面的投影基底，并用 `GetEffectiveScale` 将画布逻辑像素转换为原生投影像素；通过2×2逆变换求出目标脚底位置。体型按采样得到的单位像素比例计算，额外检查模型边界八角的投影大小。不要在调用方假设世界 Y 对应屏幕左或右、或固定假设 FOV 使用哪个宽高比约定。

模型资产可设置 `screenFacing="left"|"right"` 和 `forwardYaw`（模型局部前向轴，弧度），由引擎按原生投影选取方向；不设置时仍使用原来的 `facing` 弧度。投影暂不可用时保留重试，禁止用未经校准的位置显示角色；恢复不改变用户暂停状态。

共享模式的预热并行推进4个资源，与可见角色共用 `maxSurfaceModels` 预算；空闲 Actor 按模型资源复用，120秒后清除，池满优先回收空闲对象。资源ID和测量边界缓存跨本引擎会话的打开/关闭保留，活模型在结束时清理。游戏应使用稳定节点ID，避免数组删除引发余下所有模型重载。

共享模型可传 `animationTime`（当前动作原始秒数）、`animationRate`（每游戏秒推进量）及 `animationEnd`（终点）。引擎按战局时钟逐帧采样 `Actor:SetAnimation(animation, 0, 0, offsetSeconds)`；游戏在命中和换周期时刷新节点。暂停不前进，2倍速自动同步；不要用现实时间另写一套扣血时钟。

音效可声明 `soundGroups`，字段包括 `interval/window/densityStep/maxExtra/maxConcurrent`；声音通过 `group` 加入预算。事件密度指数衰减，下一次允许播放间隔为 `interval + min(maxExtra, density × densityStep)`，合并的请求直接丢弃。可配置 `fadeMs`、`duckGroups`、`duckDuration`，让特殊反馈暂时抑制普通音效；限流始终使用宿主实时时钟，不随游戏速度加倍。

0.2.3 音量：JSON配置 `"soundBuses":{"impact":0.5}` 声明混音总线，音效以 `bus:"impact"` 加入；`ctx.sound.setVolume(0..1)` 控制本场音效，`setBusVolume("impact",0..1)` 控制指定总线。播放音量为总音量×总线音量×定义volume×options.volume；各项默认1。0立即停止对应已有声部，其他值对下一次播放生效，不重播已有声音。BGM仍走独立Music模块。

宿主使用 `C_Sound.PlaySoundWithOptions.volumeOverride`。soundKitID直接调用；fileID需声明经客户端表确认的 `volumeSoundKitID`。SoundKit可能随机选择同音色文件，不能承诺单文件/A-B顺序。`baseVolume`是100%时的归一化基准：直接文件填1，原生SoundKit按SoundKit表VolumeFloat保留基准。无映射文件的非100%播放返回 `sound_volume_unsupported`，不会假装已调整音量。`capabilities().volume`可用于禁用旧客户端控制。

声部存活查询最多每20ms一次，分组活动数增量维护；失败音源独立退避250ms，高优先级起播失败不会截断旧声部。统计含 `soundVoiceLimit/peakSoundVoices/soundGroups/soundVolume/soundBusVolumes`；计数区分声音冷却、组间隔、组并发、总预算、duck和超时。

已有完整自定义保存状态的游戏，可在 content 中设置 `hideHostFooter=true` 隐藏额外宿主页脚；默认仍显示。它只影响呈现，不影响存档写入、错误日志或暂停行为。

## 4. 常用联动

| 需求 | 游戏调用 | 引擎接手的工作 |
| --- | --- | --- |
| 延时刷怪 | `ctx.clock.after(2, function() ... end)` | 游戏时间；暂停冻结、退出取消；返回提前取消函数 |
| 生成/移除 | `ctx.world.spawn(id, position)` / `despawn(entityId)` | 状态登记、显示对象分配与回收 |
| 音效/音乐 | `ctx.sound.play("combat_hit")` / `ctx.music.play("arena")` | 解析、播放、本场清理；检查返回值，可选音频失败不阻止开场 |
| 按钮转动作 | `ctx.input.emitAction("attack", "pressed")` | 提交小游戏动作边沿，不模拟系统按键 |
| 保存进度 | `ctx.save.request("checkpoint")` | 合并请求、调用 onSave、写本物品变量 |
| 立即确认保存 | `ctx.save.flush("manual")` | 同步调用 onSave 并核对变量，返回 ok/reason；不代表磁盘已刷盘 |
| 查看材料 | `ctx.inventory.count("token")` | 读取实际 TRP3 库存 |
| 发放/消耗 | `ctx.inventory.grant("token", 1, operationId)` / `consume(...)` | 记录操作、修改库存、核对数量，返回结果表 |
| 交换物品 | `ctx.trade.open()` | 暂停、归还输入、打开当前目标的原生交易 UI，玩家拖入并确认 |
| 性能阶段 | `ctx.perf.begin("my_scene", {}, {warmup=2, duration=10})` | 预热、采样、汇总；按[测试台说明](../items/performance-lab/README.md)复制日志 |

库存结果检查 `status`：只有 `complete` 代表要求已完成；`partial / failed / unknown` 不能当作完整发奖。`operationId` 来自稳定结算记录，同一奖励重试仍用原 ID；未知结果先核对，不换随机 ID 再发一次。当前操作记录上限 128 条，长期经济系统需另行设计归档。

## 5. 引擎何时调用游戏

| 回调 | 时机与约束 |
| --- | --- |
| 工厂 `function(ctx)` | 读档后创建本场局部状态，返回回调表 |
| `onStart()` | 新场次一次，必需；装配关卡和规则 |
| `onFixedUpdate(dt, input)` | 固定逻辑步，AI/动作/移动/碰撞之前，提交本步意图 |
| `onFrame(elapsed)` | 未暂停的显示帧，适合测试控制；不能再更新一套物理 |
| `onPause(reason)` / `onResume()` | 暂停/恢复；引擎已处理输入和音频 |
| `onSave()` | 返回纯数据；不发奖、不递归保存、不保存实体/Frame/函数 |
| `onStop(reason)` | 最后一次玩法清理；回调失败也继续释放引擎资源 |

`ctx.save.data` 是启动读入的进度快照；运行状态放局部变量，通过 `onSave` 返回。实体 ID 只在本场有效，不能跨重开引用。引擎只恢复有效备份，不自动迁移不匹配的 `saveVersion`。

一般保存用 request 合并到安全保存点；明确的“保存”按钮可用 flush 取得即时结果，暂停时也可保存。flush 在正在保存或停止时返回 session_busy；不要在 onSave 里调用它。

不要另建 `OnUpdate`、永久 ticker 或直接操作 TRP3 变量。副本、WoW 战斗、过图、道具移出和定义变化由宿主监听，统一停止。当前同时只有一个活动游戏场次。

## 6. 构建和交付

在仓库根目录运行：

```powershell
npm ci
node tools/build-item-game.mjs items/training-arena/item.json
node tools/build-item-game.mjs items/training-arena/item.json --verify-only
```

`npm run build` 固定构建性能台；新游戏使用上面的明确路径。

| 输入 | 道具中的位置 |
| --- | --- |
| item.json | 根定义元数据、`IN.ig_manifest` |
| content.json | `ig_game / ig_assets / ig_levels / ig_music` 文档及材料/装备定义 |
| game.lua + 引擎 | `SC.wf_bootstrap` 中的一份 Lua，构建器自动注册游戏 |
| 构建器模板 | 六个工作流、使用/销毁绑定、帮助文档、启动诊断 |

启动固定为 **短宏 → 原生延时 0.1 秒 → 限定 Lua → wf_bootstrap → wf_open → 创建 ctx → onStart**。不要把长引擎代码塞入宏，也不要删延时，原因见[FAQ](ITEM-GAME-FAQ.md)。

交付 `dist/item.t3e.txt`。作者导入后添加到 TRP3 背包并使用；玩家通过原生交易收到实例后使用。每版保留 `build-report.json`，按版本和 sourceHash 关联日志。最低实测：启动、操作、保存重开、退出归还输入，以及本游戏用到的音频/模型/交易。发布流程见[维护指南](ITEM-GAME-MAINTENANCE.md)。
