-- Game-owned interface. Surface IDs and layers are stable across every screen.
local U={}
function U.new(ctx,art)
    local surface=ctx.ui.surface();local self={};local layer=20
    local colors={ink={.055,.061,.078,1},panel={.10,.115,.145,1},gold={.72,.55,.28,1},muted={.59,.64,.70,1},white={.93,.92,.86,1}}
    local function rect(id,x,y,w,h,color,z)surface.draw(id,{kind="rect",x=x,y=y,w=w,h=h,color=color,layer=z or layer})end
    local function text(id,value,x,y,w,h,size,color,align,z)
        surface.draw(id,{kind="text",text=value,x=x,y=y,w=w,h=h,size=size or 14,color=color or colors.white,align=align or "LEFT",layer=z or layer})
    end
    local function button(id,value,x,y,w,h,fn,enabled,selected,z)
        surface.draw(id,{kind="button",text=value,x=x,y=y,w=w,h=h,size=14,
            color=selected and {.34,.27,.13,1} or colors.panel,onClick=fn,enabled=enabled,layer=z or layer})
    end
    local function time(value)return string.format("%02d:%02d",math.floor(value/60),math.floor(value%60))end
    function self.draw(s,actions)
        surface.begin()
        rect("background",0,0,960,610,colors.ink,0)
        rect("top-rule",25,66,910,1,colors.gold)
        text("brand","斯托颂 · 奥术工坊",28,10,320,20,12,colors.gold)
        text("title","奥术魔方",26,28,340,36,27)
        text("time-label","用时",365,15,65,20,12,colors.muted)
        text("time",time(s.elapsed),365,34,90,27,22)
        text("moves-label","转动",475,15,65,20,12,colors.muted)
        text("moves",tostring(s.moves),475,34,90,27,22)
        button("materials",s.materialsOpen and "返回魔方" or "材质试验",580,22,110,32,actions.materials,not s.busy,s.materialsOpen)
        button("pause",s.paused and "继续" or "暂停",818,22,110,32,actions.pause,true,s.paused)
        button("fireworks",s.fireworksOpen and "魔方控制" or "烟花试验",699,22,110,32,actions.fireworks,true,s.fireworksOpen)
        text("order-label","阶数",29,83,48,26,13,colors.muted)
        for n=2,7 do button("order"..n,n.." 阶",84+(n-2)*75,80,66,32,function()actions.order(n)end,not s.busy and not s.benchmark and not s.materialsOpen,n==s.n)end
        button("skin",s.skin=="tidal" and "皮肤：海潮" or "皮肤：经典",552,80,120,32,actions.skin,not s.busy and not s.materialsOpen and not s.paused,s.skin=="tidal")
        if not s.fireworksOpen then text("mode",s.challenge and (s.assisted and "辅助练习" or "计时挑战") or "自由练习",552,118,120,20,12,colors.gold,"RIGHT")end
        rect("side-rule",681,125,1,415,{.28,.25,.20,1})
        if s.materialsOpen then
            local m=s.materials
            text("mat-title","海潮像素材质",704,126,225,28,20)
            for i,subject in ipairs(m.subjects)do
                button("mat-subject"..i,subject.name,705,168+(i-1)*35,223,29,function()actions.materialSelect(i)end,true,m.selected==i)
            end
            text("mat-choose","切换当前主体的点阵",705,277,225,20,12,colors.gold)
            for i,face in ipairs(m.faces)do
                button("mat-texture"..i,face.name,705+(i-1)%3*76,303+math.floor((i-1)/3)*35,68,29,function()actions.materialTexture(i)end,true,m.bound and not m.sixFaces and m.texture==i)
            end
            button("mat-six","六面组合",705,386,107,30,actions.materialSix,true,m.bound and m.sixFaces)
            button("mat-uv","UV "..(m.uvRotation*90).."°",821,386,107,30,actions.materialUV,true)
            button("mat-spin",m.spinning and "停止自转" or "主体自转",705,427,107,30,actions.materialSpin,true,m.spinning)
            button("mat-group","整组转45°",821,427,107,30,actions.materialGroup,true)
            button("mat-motion",({"空间运动：关闭","空间运动：模型","空间运动：镜头"})[m.motion+1],705,466,223,27,actions.materialMotion,true,m.motion>0)
            button("mat-effects",m.effectsEnabled and "光效：开启" or "光效：关闭",705,501,107,27,actions.materialEffects,true,m.effectsEnabled)
            button("mat-clear","解除材质",821,501,107,27,actions.materialClear,true)
            text("mat-bytes",string.format("24×24 · 12色 · 内嵌 %.2f KB",m.encodedBytes/1024),30,118,625,20,12,colors.gold)
            text("mat-count","面片 "..m.stats.scene3DDraws.."    原生Frame "..(m.stats.scene3DNativeFrames or 0).."    视锥剔除 "..(m.stats.scene3DCulledNodes or 0),30,510,625,22,12,colors.muted)
            for i,label in ipairs(m.labels)do
                text("mat-label"..i,label.name,label.x-70,label.y+8,140,23,12,label.selected and colors.gold or colors.muted,"CENTER")
            end
        elseif s.fireworksOpen then
            local f=s.fireworks;local stats=f.stats;local enabled=not f.testing and not s.paused
            text("fx-title","三维烟花试验台",704,126,225,28,20)
            local kinds={{"peony","星辉礼花"},{"ring","奥术星环"},{"willow","鎏金垂柳"},{"fountain","翡翠喷泉"},{"crackle","连环爆裂"}}
            for i,k in ipairs(kinds)do button("fx-kind-"..k[1],k[2],705+(i-1)%2*116,168+math.floor((i-1)/2)*36,107,30,function()actions.fireworkKind(k[1])end,enabled,f.selected==k[1])end
            for i,name in ipairs({"低密度","标准","高密度"})do button("fx-level"..i,name,705+(i-1)*76,283,68,30,function()actions.fireworkIntensity(i)end,enabled,f.intensity==i)end
            button("fx-preview","单式燃放",705,328,107,34,actions.fireworkPreview,enabled)
            button("fx-show","五式齐放",821,328,107,34,actions.fireworkShow,enabled)
            button("fx-benchmark","四阶段对照 · "..f.totalSeconds.."秒",705,375,223,36,actions.fireworkBenchmark,enabled and not s.busy,true)
            button("fx-stop","停止 / 清场",705,422,107,30,actions.fireworkStop,not s.paused)
            button("fx-log","导出日志",821,422,107,30,actions.fireworkLog,true)
            text("fx-count","粒子 "..stats.particles3D.." / "..stats.particles3DCapacity.."    峰值 "..stats.particles3DPeak,705,464,225,22,12,colors.gold)
            text("fx-budget","发射器 "..stats.emitters3D.."    丢弃 "..(stats.particles3DDropped+stats.particles3DRenderDropped),705,488,225,22,12,colors.muted)
            text("fx-batches","原生Frame "..(s.nativeFrames or 0),705,511,225,20,12,colors.muted)
            local frame=f.metrics.frameMs;local update=f.metrics.particles3DStepMs;local project=f.metrics.particles3DProjectMs;local draw=f.metrics.particles3DDrawMs
            local function ms(m,key)return m and m[key] and string.format("%.2f",m[key]) or "—"end
            text("fx-timing","宿主 FPS "..tostring(math.floor(f.perf.hostFPS or 0)).."    帧 P95 "..ms(frame,"p95").." ms",30,481,625,20,12,colors.gold)
            text("fx-timing-detail","粒子均值 ms  更新 "..ms(update,"mean").." / 投影 "..ms(project,"mean").." / 绘制 "..ms(draw,"mean"),30,504,625,22,11,colors.muted)
            text("fx-environment",f.perf.hostKind=="mock" and "模拟宿主 · 不代表 WoW 性能" or "WoW 客户端 · 帧耗时含宿主负载",30,118,625,20,12,colors.muted)
            button("fx-quality",f.testing and "对照：固定画质" or (f.adaptive and "自动控量：开" or "自动控量：关"),537,117,135,22,actions.fireworkQuality,enabled,f.adaptive and not f.testing)
            text("fx-quality-stats",string.format("绘制额度 %.0f%% · 覆盖 %.2f 屏",(stats.particles3DQualityScale or 1)*100,stats.particles3DScreenArea or 0),30,525,625,12,10,colors.muted)
        else
        text("control-title","转动一层",704,126,220,28,20)
        text("control-note","点选方块，再选择轴与层。",705,160,230,24,12,colors.muted)
        for i,axis in ipairs({"x","y","z"})do
            button("axis"..axis,string.upper(axis).." 轴",705+(i-1)*76,195,68,32,function()actions.axis(axis)end,not s.busy and not s.paused,s.axis==axis)
        end
        text("layer-label","第 "..s.layer.." 层  /  "..s.n.." 层",705,240,225,22,13,colors.gold)
        for i=1,s.n do button("slice"..i,tostring(i),705+(i-1)*32,270,28,30,function()actions.layer(i)end,not s.busy and not s.paused,s.layer==i)end
        button("turn-minus","−90°  反向",705,318,107,38,function()actions.turn(-1)end,not s.busy and not s.paused)
        button("turn-plus","+90°  正向",821,318,107,38,function()actions.turn(1)end,not s.busy and not s.paused)
        text("axis-note","方向以所选正轴为准",705,362,222,19,11,colors.muted)
        button("scramble","打乱 · 开始新局",705,397,223,38,actions.scramble,not s.busy and not s.paused,true)
        button("undo","撤销一步",705,447,107,32,actions.undo,s.canUndo and not s.busy and not s.paused)
        button("replay",s.replaying and "停止演示" or "回放复原",821,447,107,32,actions.replay,not s.paused and (s.replaying or not s.busy and s.hasHistory))
        button("camera-reset","重置视角",705,491,107,30,actions.camera,not s.benchmark)
        button("reset","还原为初始",821,491,107,30,actions.reset,not s.busy)
        end
        text("status",s.materialsOpen and s.materials.message or s.fireworksOpen and s.fireworks.message or s.message,30,540,900,26,14,s.won and {.45,.9,.65,1} or colors.white)
        text("hint","右键拖动观察 · 滚轮缩放 · 左键点选 / 拖动转层",30,572,650,20,12,colors.muted)
        text("keyboard","J / K 转层  ·  Z 撤销",695,572,235,20,11,colors.muted,"RIGHT")
        if not s.fireworksOpen and not s.materialsOpen then
        for i,face in ipairs({"U","D","R","L","F","B"})do
            rect("gem"..face,34+(i-1)*104,510,9,9,art.colors[face])
            text("gem-name"..face,art.names[face],48+(i-1)*104,504,86,22,10,colors.muted)
        end
        local best=s.bests[tostring(s.n)]
        text("best",best and ("本阶最佳  "..time(best.time).." / "..best.moves.." 次") or "六面各归一色，即为复原。",30,118,625,20,12,colors.muted)
        end
        if s.paused or s.confirm then
            rect("modal-shade",0,0,960,610,{.025,.03,.04,.93},25)
            rect("modal-edge",236,191,488,218,colors.gold,25)
            rect("modal-body",238,193,484,214,colors.ink,25)
            text("modal-title",s.confirm and "开始新的魔方？" or "时间已暂停",266,219,425,34,24,colors.white,"CENTER",25)
            text("modal-note",s.confirm and "当前局面将被替换；已取得的最佳成绩保留。" or "继续后再转动。关闭窗口会保存完整局面。",267,267,426,42,14,colors.muted,"CENTER",25)
            if s.confirm then
                button("confirm-no","保留当前",287,334,169,38,actions.cancel,true,false,25)
                button("confirm-yes","开始新局",479,334,169,38,actions.confirm,true,true,25)
            else button("resume","继续解谜",365,334,230,38,actions.pause,true,true,25)end
        end
        surface.finish()
    end
    return self
end
return U
