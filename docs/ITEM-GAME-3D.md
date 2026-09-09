# ItemGame 0.3.0：三维场景

0.3.1 在下述接口上新增三维粒子与渲染缓存，详见本文最后两节。

`ctx.scene3d` 为每场游戏提供一个按需创建的三维场景。纯几何/空间逻辑位于 `math3d.lua`、`scene3d.lua`；WoW 显示和鼠标适配位于 `view3d.lua`。游戏不创建第二个 OnUpdate。现有二维 World、Surface、模型显示及存档接口不改变。

## 最小示例

```lua
return function(ctx)
    local scene
    local M=ctx.scene3d.math
    return {
        onStart=function()
            scene=ctx.scene3d.create({viewport={x=20,y=100,w=640,h=400}})
            scene.create("box", {
                mesh=ctx.scene3d.boxMesh(1,{.2,.7,.5,1}),
                position=M.vec(0,0,0), collider=true,
            })
            scene.orbit(.6,.4,7,M.vec())
            scene.onPointer(function(event)
                if event.phase=="up" then
                    local hit=scene.pick(event.x,event.y)
                    if hit then ctx.ui.notify("选中："..hit.id)end
                end
            end)
        end,
        onFixedUpdate=function(dt)
            scene.setTransform("box",{rotation=M.vec(0,ctx.clock.now(),0)})
        end,
    }
end
```

`math.vec()` 生成 `{x,y,z}`。采用右手坐标：X 向右、Y 向上、Z 向观察者；空间单位独立于像素。角度使用弧度，局部变换顺序是缩放、绕 X/Y/Z 旋转、平移，即 `T * Rz * Ry * Rx * S`。摄像机 target 决定观察方向。viewport 与 Surface 相同，使用左上角、向右/向下的逻辑像素；适配器处理 UI 缩放。

## 接口

| 接口 | 契约 |
| --- | --- |
| `ctx.scene3d.create({viewport})` | 懒创建；每场仅一个场景，重复调用返回原实例。会话结束后返回 nil/reason |
| `scene.create(id,spec)` | 稳定且唯一的字符串 ID；创建并返回节点 |
| `scene.get(id)` | 返回运行时节点；不直接写入存档 |
| `scene.setTransform(id,{position,rotation,scale})` | 部分更新局部变换；正缩放；渲染和拾取共同更新 |
| `scene.setParent(id,parentId)` | 保留局部变换；nil 脱离父节点；拒绝环，层级上限32 |
| `scene.worldPoint(id,localPoint)` | 经父子变换得到世界坐标 |
| `scene.setVisible(id,bool)` | 子节点继承父节点可见性 |
| `scene.setTint(id,{r,g,b,a})` | 乘性染色，分量0–1 |
| `scene.remove(id)` / `clear()` | 删除子树 / 清空本场节点；原生绘图对象留在有界池中复用 |
| `scene.setCamera({position,target,up,fov,near,far})` | 部分更新透视相机；fov 为垂直弧度视角 |
| `scene.orbit(yaw,pitch,distance,target)` | 环绕镜头；pitch 限制到 ±1.5 防止上向量退化 |
| `scene.getCamera()` / `getViewport()` | 返回副本 |
| `scene.project(worldPoint)` | 返回逻辑屏幕 x/y 和相机深度；近远裁剪范围外为 nil |
| `scene.screenRay(x,y)` | 返回射线原点及单位方向 |
| `scene.pick(x,y)` | 查询视口内最近可见、可拾取网格；在近远裁剪平面内判定 |
| `scene.raycast(origin,direction,maxDistance)` | 任意三维网格射线；返回 id/tag/face/faceTag/point/normal/distance |
| `scene.queryAABB({min,max})` | 查询带 `collider=true` 的节点世界轴对齐包围盒，返回 ID 列表 |
| `scene.sweepAABB(box,displacement,ignoreId)` | 扫掠盒体，返回最先命中的 id/time/normal；time 在0–1之间 |
| `scene.onPointer(callback)` | 接收 down/move/up/wheel/cancel；x/y 与 viewport 同坐标，move 含 dx/dy |
| `scene.stats()` | 节点/几何面/可见面/原生绘制数/池容量/丢弃数 |

节点 spec 可包含 `parent / position / rotation / scale / visible / pickable / mesh / collider / velocity / tag`。父子关系不强制树形创建顺序之外的自动装配，父节点必须先存在。设置非零 velocity 后，引擎每个固定步长按局部坐标推进；碰撞响应由游戏控制器负责，不自动停止、滑动或施加重力。`queryAABB` 对旋转体使用世界包围盒，是保守判定，不等于精确网格碰撞。

`get` 暴露诊断与运动学数据；修改位置、父子关系、可见性与染色应使用对应方法，避免绕过缓存失效。网格在 create 时校验，之后视为不可变。

## 网格与实际渲染边界

网格格式为 `vertices={{x,y,z},...}` 与 `faces={{1,2,3,4,color={r,g,b,a},tag="face"},...}`。每个面必须是共面凸三角形或四边形，顶点从外面看逆时针排列。可指定 `doubleSided=true` 或 `unlit=true`。`boxMesh(size,color)` 提供基础盒体。颜色没有纹理导入依赖，光照为世界空间固定方向的漫反射加环境光。

流程：父子变换 → 相机坐标 → 近/远/左/右/上/下裁剪 → 透视除法 → 面深度排序 → Texture:SetVertexOffset。四边形使用四个原生顶点；裁剪后多边形拆为三角形。每个绘制面使用池中的 Frame 与 Texture，空闲节点隐藏，退出解除输入回调。暂停不推进运动，仍可校准 UI 缩放。

当前是 **CPU 几何投影 + WoW 原生纹理绘制**，并非通用 GPU 网格渲染器。按面平均深度排序适用于魔方这样的分离凸几何；相交网格、循环遮挡、复杂透明物体不保证像 GPU 深度缓冲一样正确。此场景与既有 ModelScene 不共享深度，不承诺两类对象互相正确遮挡。不提供任意材质/Shader、原生地形、网格资产导入或完整刚体物理。

预算：`limits.maxScene3DNodes` 默认512，范围1–1024；`maxScene3DFaces` 默认4096，范围1–4096，按提交的面计算。裁剪可能增加绘制数，原生绘制面硬上限4096，超出记入 `scene3DDropped`。这是引擎预算，不是 WoW 官方性能上限。重复打开复用原生池，池容量保持本机本次会话的峰值。

3D 输入位于 Surface 第15层以下；覆盖菜单、按钮、血条应使用 Surface **20层或更高**，3D 背景使用0层。整个三维世界使用单一透视镜头；暂停/弹窗由更高层 UI 接收鼠标。一个窗口内的多个独立三维视口暂不提供。

## 验证与复现

```powershell
npm run build
npm run build:cube
npm test
python tools/preview-cube.py
```

预览默认在 `http://127.0.0.1:8766`。它运行实际 Lua 引擎与游戏源码，把 WoW 适配器输出的 Texture 顶点转交浏览器显示，按钮与指针调用同一份 Lua 处理器。它不是另一份 JavaScript 魔方，也不能证明 WoW GPU、鼠标捕获、客户端帧率或磁盘持久化。

永久测试覆盖：仿射逆变换、投影/射线一致性、父子关系与最近命中、六面裁剪、AABB 扫掠及离开接触面的行为、预算和销毁；魔方测试覆盖2–7阶排列不变量、连续四转、长序列逆操作、朝向一致性、内层旋转、暂停、存档、胜利与实际 TRP3 脚本沙盒启动。

## 0.3.1：三维粒子

独立的 `particles3d.lua` 管理世界空间粒子，不把每一粒装配为 Scene3D 节点。WoW 适配器使用原生 `Interface\Cooldown\star4` 纹理的加色混合面向摄像机绘制，透视尺寸随距离变化，与几何按深度合并。粒子不参与拾取或实体碰撞，不提供软粒子深度采样或透明排序的GPU精度。

在 `content.particles3d` 声明配方，例如：

```json
{"celebrate":{"mode":"burst","shape":"sphere","count":96,
 "speed":[1.2,2.1],"lifetime":[1.1,1.8],"size":[0.05,0.1],"endSize":0.01,
 "gravity":{"x":0,"y":-0.8,"z":0},"drag":0.4,
 "startColor":[1,0.8,0.3,1],"endColor":[1,0.2,0.05,0]}}
```

```lua
local scene=ctx.scene3d.create()
local made,dropped=scene.particles.burst("celebrate",{position={x=2,y=1,z=0},seed=42})
```

| 接口/字段 | 说明 |
| --- | --- |
| `particles.burst(id,params)` | 一次爆发，返回生成数/丢弃数；未知配方或已关闭返回nil/reason |
| `particles.start(id,params)` | 持续发射器，返回本场句柄；mode必须为continuous |
| `particles.stop(handle,killParticles)` | 停止发射，可同时清理该发射器已产生的粒子 |
| `particles.clear()` | 清空粒子和发射器；不会重置当前固定步的生成预算 |
| `particles.stats()` / `resetStats()` | 读取/重置计数；对象池保留复用，预算不变 |
| `shape` | sphere：均匀球面方向；ring：direction法向的圆环；cone：direction轴周围的锥形方向 |
| `speed/lifetime/size` | 数字或有序双元素范围；支持endSize、startColor/endColor随寿命线性变化 |
| `direction/spread/radius` | 发射方向、锥形半角（弧度）、出生半径 |
| `gravity/drag/priority` | 三轴重力、指数阻力、满池淘汰优先级 |
| `rate/duration` | 持续发射器每秒数量、逻辑时间寿命 |
| params `position/nodeId` | 世界位置；带nodeId时为节点局部偏移，持续发射器每步重新定位。节点删除后停止发射 |
| params `velocity` | 为新粒子附加世界初速度 |
| params `emitterVelocity/emitterAcceleration` | 发射器出生点随时间运动，例如火箭尾焰；已产生粒子独立运动 |
| params `count/countScale/scale/seed` | 爆发数量、密度倍率、尺寸/速度/半径倍率、可复现随机种子 |

引擎固定步自动更新粒子，并按前后位置插值绘制；暂停冻结运动，退出释放粒子和输入。配方生命周期最长15秒，发射器最长60秒。`limits.maxParticles3D` 默认512、上限2048；`maxEmitters3D` 默认16、上限64；`maxParticleSpawns3DPerStep` 默认256、上限1024。生成预算在发射器与所有爆发间共享。满池拒绝同/低优先级粒子，高优先级可淘汰旧的低优先级粒子，并分别计数。

原生绘制仍遵守4096面总预算，优先保留几何面，其余配额用于粒子。统计区分 `particles3DDropped`（生成拒绝）、`particles3DEvicted`（替换）、`particles3DRenderDropped`（绘制额度）。粒子死亡后表和绘图对象会复用，不把累计粒子ID变成永久原生对象。

`ctx.perf.snapshot()` 提供当前采样阶段、均值/分位数、宿主种类/FPS和最近结束的阶段。现有NDJSON增加粒子资源计数及 `particles3DStepMs / particles3DProjectMs / particles3DDrawMs`。绘制耗时是Lua提交原生属性的耗时，不是GPU计时。

## 0.3.1：渲染算法优化

节点维护局部变换版本和父节点世界版本，只重算变化的子树；镜头变化不重复构造世界顶点。各节点缓存相机投影和面列表，转动魔方一层不会重新投影其他层。完全处于视锥内的面直接投影，跳过六次多边形裁剪；跨越裁剪面时仍使用完整裁剪。变换后的法线、顶点和相机坐标会复用。

WoW绘图对象按稳定几何面ID/粒子池槽复用；深度顺序改变时更新FrameLevel，静止面的坐标、颜色和纹理属性保持缓存。可见面替换前先回收不再使用的对象，因此缓存不会随历史ID无限增长。粒子更新不使几何投影缓存失效。

```powershell
python tools/benchmark-scene3d.py > render-cpu.json
```

该命令固定采样3/4/5/7阶的同一转层轨迹，报告投影、原生属性提交、调用计数及源码哈希。它使用标注为mock的宿主，只用于算法对比。实际客户端仍应使用魔方内的烟花对照与日志导出。

## 0.4.1：内嵌像素材质

在物品 `packages` 中加入 `pixel-materials`，依赖解析会补齐Scene3D和runtime。该包将小尺寸点阵变成沿UV排列的彩色面片，完全不读取PNG、SVG或外部图片路径。

```lua
local scene=ctx.scene3d.create()
scene.definePixelTexture("red_blue",{
    width=2,height=2,codec="rle4",palette={"FF0000","0000FF"},data="15",
}) -- 上排两格红，下排两格蓝
scene.create("box",{mesh=ctx.scene3d.boxMesh(1)})
scene.setPixelMaterials("box",{default={texture="red_blue",rotation=0}})
-- 单独指定第2个原始面：
scene.setPixelMaterials("box",{[2]={texture="red_blue",rotation=1}})
scene.setPixelMaterials("box",nil) -- 解除绑定，恢复原始网格颜色
```

`definePixelTexture` 每场最多定义32个ID，重复ID返回false/reason。尺寸为1–32的整数；色值为六位RGB十六进制。RLE4最多16色，每字符按字母表 `0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_` 解出6位值：颜色索引为 `floor(value/4)`，长度为 `value%4+1`。像素按从上到下、从左到右排列，解码总数必须恰好等于宽×高。不指定codec时保留两字符RLE：第一个字符为颜色索引，第二个为长度减一，最多32色。

绑定表可使用 `default` 或原始mesh的1基面索引；值为纹理ID字符串，或 `{texture=id,rotation=0..3}`。rotation为顺时针90度步进。`mesh.faces[i].uv` 可按顶点顺序提供 `{u,v}`，范围0–1且不可退化。未提供时，四边形默认UV为 `(0,1),(1,1),(1,0),(0,0)`，三角形为 `(0,1),(1,1),(.5,0)`。

绑定仅修改显示面片，`node.mesh`、基础碰撞盒与raycast面索引保持原始几何语义。矩形像素块在绑定时生成，变换期间复用；普通未绑定模型继续走原来的投影缓存。显示预算仍使用 `maxScene3DFaces`，预算不足返回false/`pixel_face_budget`并保留旧材质。调用方应检查返回结果。

该方法适合低分辨率像素图案与小型模型；提高点阵分辨率或使用高频噪点会增加面片，不能视为任意高分辨率图片的GPU纹理替代。魔方示例使用24×24、12色和同色色块合并，完整制作文件见 `items/arcane-cube/art/`。

0.4.2 的矩形UV可指定0–1内的子区域，例如一幅整面图案中的某个魔方格。轴对齐矩形UV与平行四边形网格走快速裁剪，只为相交色块生成面片。2–7阶海潮皮肤分别使用1215、1489、1773、2571、2667、3956个显示面，均在4096预算内；没有为每个格子重复整幅24×24图案。

`mesh.faces[i].surfaceGroup` 可将同一物理表面上近乎共面的底板、边框与像素层分组。组内按原始源面顺序从底到顶绘制，组深度取第一个源面的中心深度，防止整块底板按平均深度排序时盖住像素片段。只应分组同一表面的覆盖层，不应把不同朝向或相交物体放入一组。拾取和碰撞仍使用原始几何。

## 0.4.3：WoW原生Frame批处理

原先每个彩色色块或粒子各使用一个Frame和一个Texture。现在同一节点、同一源面连续提交的色块共用一个Frame，Texture直接锚定在该Frame的视口坐标内；层级按批次更新。没有显式surfaceGroup的像素材质也以源面中心深度排序，保证同一面的像素连续。同一面内部的色块没有面积重叠；不同源面仍保持独立层级，不能随意合批。

连续ADD粒子允许共用Frame，遇到几何面立即拆分批次；普通透明混合粒子保留各自层级。Texture和Frame分别回收，复用时通过Texture:SetParent改挂批次并使锚点缓存失效。隐藏对象逐Texture处理，不能用共享Frame是否显示来判断某个色块是否活跃。Frame和Texture池均受4096上限约束，关闭场景隐藏两个池。

`scene.stats()` 新增 `scene3DNativeFrames`（当前显示批次）与 `scene3DPooledFrames`（累计池容量）。`scene3DDraws` 仍为提交的Texture面片数，不是Frame数或GPU draw call数。默认静态视角的三阶、四阶、五阶、七阶海潮魔方，Frame数分别由730/873/1264/1961降为132/264/444/948；Texture数与24×24美术细节不变。

可以只替换旧适配器，保持游戏和几何完全相同来复测：

```powershell
python tools/benchmark-scene3d.py --adapter-bundle items/arcane-cube/candidates/tidal-pixels/engine.generated.lua
python tools/benchmark-scene3d.py
```

报告列出每个原生方法的调用次数（36帧总计），计时排除前6帧预热。该对照证明Frame资源和原生API提交减少，mock并未显示稳定的Lua耗时下降；它不能计量WoW的布局、GPU批次或实际FPS。像素仍由多个Texture色块模拟，复杂场景仍有成本；同面深度分组继续属于画家算法近似。

## 0.5.0：空间移动、粒子控量与表面光效

场景先用原始网格的世界AABB测试六个视锥平面，完全不可见的节点不再变换或投影像素顶点。基础世界几何继续更新，所以速度、碰撞查询和射线查询不会被渲染剔除暂停。与平面相交的模型仍走逐面精确裁剪；旋转、父子变换和非均匀缩放均使用变换后的包围盒。首次进入视口时补算皮肤，之后按世界版本复用。原始mesh覆盖全部绘制面片是此优化的前提，内嵌像素UV烘焙满足该前提。

相同的setTransform/setCamera/setViewport不再使缓存失效；零速度节点不进入运动更新。镜头基向量、视锥平面与粒子投影闭包按镜头版本复用。`scene.setVelocity(id,{x=1,y=0,z=0})` 设置运动速度，传nil停止积分；碰撞响应仍由游戏控制器决定。`scene3DCulledNodes`计当前被整物体剔除的节点，`scene3DPaintedVertices/scene3DProjectedVertices`计最近一次renderList实际计算的顶点，不是场景容量或GPU统计。

粒子满池的同/低优先级拒绝改为常数时间，只有确实能替换低优先级粒子时才扫描淘汰目标。阻力指数按配方和dt缓存；发射器位置、候选投影与billboard对象复用。世界空间粒子不会随其发射模型一起搬动。

```lua
scene.particles.setRenderPolicy({
    minPixels=.5,        -- 小于此投影直径的粒子不绘制，单位为视口逻辑像素
    maxDistance=100,     -- 相机空间深度；原镜头near/far仍然生效
    maxScreenArea=4,     -- 可见billboard裁剪矩形面积总和 / 视口面积；0表示不限制
    maxVisible=512,      -- 不超过当前粒子容量；几何仍优先占用4096绘制总预算
    adaptive=true,
    targetMs=1000/60,
})
scene.particles.setRenderPolicy(nil) -- 恢复固定全量策略
```

控量只影响绘制，不改变随机种子、粒子物理、发射数量或游戏胜负。存在额度竞争时先保留高优先级，同优先级按出生序号稳定选择，再按深度排序。覆盖面积是过度叠加的保守近似，不是实际GPU像素计数。较大的单粒子若超过面积预算也可能被省略。

运行时自动把未暂停的宿主帧间隔交给observeFrame；独立使用粒子组件时可直接调用`observeFrame(frameMilliseconds)`。自适应默认关闭。开启后每1秒判断一次：平均帧耗时超过目标125%时降低25%绘制额度，最低25%；连续至少3秒不超过目标105%才恢复一级。单次超过250ms的卡顿不参与调节，无粒子时不调节。它缓解绘制负载，不替代降低CPU模拟开销，也不能把其他插件或游戏场景导致的掉帧归因于本引擎。

魔方普通烟花默认开启自动控量，可以在面板关闭；四阶段对照临时使用固定全量策略并把策略写入阶段元数据，结束或中断后恢复用户的开关选择。统计增加`particles3DQualityScale`、`particles3DQualityDropped`、`particles3DScreenArea`与`particles3DEvictionScans`；质量省略数是总`particles3DRenderDropped`的子集，不能重复相加。

### Shader相关效果的可用边界

WoW插件Texture接口提供颜色、混合、UV和顶点偏移等能力，本引擎没有自定义GLSL/HLSL着色程序入口。`surface-effects3d`是可选包，利用原生SetVertexColor实现逐源面的轮廓光近似、自发光脉冲和线性距离雾；不新增模型面片，不提供逐像素法线、屏幕采样、真实Bloom或GPU深度雾。

```lua
-- item.json packages加入surface-effects3d，自动依赖scene3d。
local scene=ctx.scene3d.create()
scene.create("crystal",{mesh=ctx.scene3d.boxMesh(1)})
scene.effects.set("crystal",{
    color={.15,.75,1},emissive=.04,
    rim=.55,power=2,     -- 视线与面法线夹角决定轮廓光
    pulse=.22,speed=.7,phase=0, -- speed单位Hz，phase单位弧度
})
scene.effects.setFog({near=5,far=18,color={.055,.061,.078}})
scene.effects.set("crystal",nil)
scene.effects.setFog(nil)
local supported=scene.effects.capabilities() -- customGPUShader=false
```

颜色、emissive/rim/pulse均在0–1内，power为1–8，speed为0–20Hz。脉冲参数每节点最多30Hz更新，按原始源面计算视角系数后应用到各像素片段。颜色版本独立于几何版本：静止模型的脉冲不重新计算投影、深度排序或原生顶点；与粒子混合时也复用几何。移除节点、清场与关闭都会清理光效；暂停不推进光效时钟。未选择此包时`scene.effects`为nil。

魔方“材质试验”中的空间运动按钮依次切换关闭、模型平移、镜头平移/推进；三个模型附带世界空间拖尾。“光效”开关可查看原图与轮廓光/脉冲/雾的区别。退出试验会清理拖尾与光效并恢复原魔方及视角。

可复测：`python tools/benchmark-spatial-effects.py`。它用上一固定候选的场景/粒子模块作为基线，在同一轨迹上验证量化到7位小数的顶点、颜色输出一致，并比较移动场景与满池发射耗时。参考了[three.js Frustum的包围盒平面判定](https://github.com/mrdoob/three.js/blob/dev/src/math/Frustum.js)；WoW接口边界核对自[Blizzard生成的Texture API文档镜像](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SimpleTextureBaseAPIDocumentation.lua)。这些参考不构成WoW实机验收证据。
