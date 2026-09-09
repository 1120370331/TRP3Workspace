# 模型不显示与自动暂停修复依据

对象版本9；没有操作魔兽客户端。以下是接口来源及离线回归范围，不是客户端视觉验收记录。

- [暴雪 ModelSceneActorMixin.lua](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_SharedXML/ModelSceneActorMixin.lua) 的 `CalculateNormalizedScale` 使用 `bottomX, bottomY, bottomZ, topX, topY, topZ = self:GetActiveBoundingBox()`，并说明不可见模型可能没有边界。
- [生成的 Actor API 定义](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameAPIModelSceneFrameActorBaseDocumentation.lua) 将边界声明为两个 vector3。引擎现在兼容两种返回形式，不能仅把前两个返回值当成两个向量。
- [ModelSceneMixin.xml](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_SharedXML/ModelSceneMixin.xml) 的商店模型场景启用 `allowOverlappedModels`；[ModelSceneMixin.lua](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_SharedXML/ModelSceneMixin.lua) 对应调用 `SetAllowOverlappedModels(true)`。共享战场同样显式启用。

原错误路径：已加载 Actor → 六个边界数值被截为前两个 → 向量读取失败 → fitReady 始终为 false → 8秒后暂停。修复同时覆盖共享场景、旧独立场景和世界模型诊断。

镜头改用0.55弧度视角，小坐标单位与按相同脚底深度合并的区间。取消模型后端控制暂停；未就绪资源继续异步尝试，场景创建失败每秒重试，模型请求失败最多每0.25秒重试一次。

离线检查覆盖六数值/双向量归一化、生成导入包的六数值路径、98模型的镜头坐标与投影脚底、模型缺失及边界延迟不暂停、恢复资源后继续显示，以及 Esc 正常暂停。实际客户端皮肤、帧渲染和加载耗时仍由用户观察。

## 对象版本10：平移随模型缩放导致错位

[ModelSceneMixin.lua 的 AddOrUpdateDropShadow](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_SharedXML/ModelSceneMixin.lua) 先读取 `actor:GetPosition()`，再乘 `actor:GetScale()` 后投影，表明原生 Actor 的平移也会被缩放。

对象版本9将已计算出的世界坐标直接传给 `SetPosition`，导致平移又乘了一次缩放；不同尺寸、不同排的偏移量不同。版本10将世界坐标先除以 Actor 缩放，再添加局部模型锚点。

此前投影检查也误把平移参数当成世界坐标。现在检查使用原生变换 `(局部平移 + 旋转后的模型点) × 模型缩放`，修改前可复现错误，修改后覆盖满场98单位、放大/缩小模型、偏心模型边界、体型变化和前排消失后的脚底稳定性。

## 对象版本11：以客户端投影为准

用户确认截图中右侧植物实际种在左侧第一列，割草机从开局就没有显示。这否定了仅检查上一版理论矩阵的充分性；它没有覆盖客户端的左右投影方向、视角宽高比和物理像素比例。

引擎改为读取 `Project3DPointTo2D` 在三个共面基准点的输出，通过 `GetEffectiveScale` 对齐逻辑像素，再反算目标脚底位置。`SetCameraOrientationByYawPitchRoll` 与暴雪 OrbitCameraMixin 保持相同调用方式。投影像素与有效缩放的处理参考 ModelSceneMixin 的 `AddOrUpdateDropShadow`，不再硬编码世界 Y 的左右符号。

`screenFacing` 定义朝屏幕左或右；资源的 `forwardYaw` 定义局部前向轴。体型根据真实投影比例计算，再检查模型边界八角，约束在游戏设置的1.3格以内。等待 `IsGeoReady`（若可用）并跨一帧读取最大边界，避免用尚未稳定的边界缩放角色。

离线检查显式变化左右投影符号、水平/垂直 FOV 约定、UI有效缩放，检查第一列植物、左侧割草机、朝向和最终投影尺寸。客户端运行中的实际视觉结果仍未由代理操作验收，不把宿主模拟器作为GPU证据。

## 对象版本12：固定站立体型，独立控制脚底

复核上述暴雪 Actor 和投影接口后，保留原生投影校准及缩放前平移。修正共享后端忽略 `scale` 的缺陷，新增独立屏幕脚底与可选局部脚底。几何完成一帧身份变换后，读取冻结待机姿态的活动边界；仅在活动边界持续不可用时退回最大边界，避免其他动画范围参与站立体型计算。实际皮肤的边界仍需客户端验证。

新增回归将待机网格与最大动画包围盒分开，检查真实待机脚底投影，而非只用引擎自己选定的包围盒验证自身。旧渲染器在大动画边界、显式脚底、角点投影失效三个场景均失败，修复后通过；另覆盖倍率、局部脚底、像素偏移、1.3格上限、暂停中的重试与单Actor失效隔离。拟合同时校验最终屏幕宽高，不再只在超出时缩小，`fitFill=1` 的目标不额外留18%空白。

验证运行真实 Lua 引擎、游戏与生成包的模拟启动链路；没有操作魔兽客户端，不将这些结果记为GPU或皮肤观感验收。

## 对象版本14：客户端证据与真正的加载门槛

2026-09-06 在 WoW 12.1.0 / build 69587 / interface 120100、TRP3E 1061 的运行中战局读取原生结果。旧对象版本12的日志一直记录 `surface.model_unavailable`，没有进入 `surface.model_ready`。资源解析正常，例如鞭笞者 species 1932 → display 72085，暗月坦克 species 338 → display 15381。

坦克 Actor 的 `IsLoaded()` 为true、`GetModelFileID()` 为126069，活动和最大边界均返回六个有效数值；但 `IsGeoReady()` 持续为false。旧渲染器在读取边界之前被这项额外检查提前返回，Actor停留在探测用的0.01透明度，因此所有单位不可见。暴雪 `ModelSceneActorMixin:CalculateNormalizedScale` 使用 `IsLoaded()` 与有效活动边界，并不等待这项额外条件。

移除该门槛后，在客户端直接装载仓库的 `surface-actors.lua`，重建当前战局的Surface并保持其存档与单位状态，未伪造或覆盖原生API的返回值。实际看到植物、割草机、食尸鬼、巨尸和亡灵师。另将敌方 `forwardYaw` 校准为0，观察它们朝屏幕左侧；通过游戏原生按钮完成暂停→继续→暂停，模型保持可见且移动/动画恢复。

这次修复的回归宿主显式提供持续返回false的 `IsGeoReady()`，同时保留真实加载延迟和有效边界。旧代码复现失败，修复后通过。此客户端证据属于渲染器在当前战局的实测，不宣称所有皮肤、十关战役或并行新增的粒子功能均已视觉验收。

## 对象版本15：逐种校准植物朝向

在同一 WoW 12.1.0 客户端创建临时独立 Surface，对十种植物逐种并排显示原始和修正配置。实测向日葵 `facing=0` 显示花盘背面，`facing=math.pi` 显示正脸；豌豆、双发、坚果、寒冰、大嘴花、炸弹与地雷的 `forwardYaw=math.pi` 将面部或前端朝左，改为0后朝右。两种孢子近似径向对称，统一采用相同前向轴。

本轮仅更改上述植物资产的朝向字段。敌方及割草机配置、引擎源码、脚底位置、显示尺寸和战斗规则均保留。临时预览使用独立资源池，不更改原战局植物或存档，观察后已清理；实际游戏继续使用相同的原生投影与模型姿态路径。
