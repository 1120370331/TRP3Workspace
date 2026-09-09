-- Generated wrapper provides E, content, recipe and sourceHash. Native APIs only.
if IGFXProbe then IGFXProbe.close()end
local live=TRP3_ItemGame.current
if live and not live.paused then live.pause("particle_probe")end
local window=CreateFrame("Frame",nil,UIParent)
window:SetSize(940,500);window:SetPoint("CENTER");window:SetFrameStrata("FULLSCREEN_DIALOG");window:EnableMouse(true)
local bg=window:CreateTexture(nil,"BACKGROUND");bg:SetAllPoints();bg:SetColorTexture(.035,.045,.04,1)
local function label(text,x,y,w)
    local f=window:CreateFontString(nil,"OVERLAY","GameFontNormal");f:SetPoint("TOPLEFT",x,-y);f:SetSize(w or 900,24);f:SetJustifyH("LEFT");f:SetText(text);return f
end
label("IG · 豌豆 / 寒冰 / 孢子 / 爆炸 · 原生粒子试验",20,12)
local canvas=CreateFrame("Frame",nil,window);canvas:SetPoint("TOPLEFT",20,-66);canvas:SetSize(900,330);canvas:SetClipsChildren(true);canvas:EnableMouse(false)
local grass=canvas:CreateTexture(nil,"BACKGROUND");grass:SetAllPoints();grass:SetTexture(187126,"REPEAT","REPEAT");grass:SetTexCoord(0,4,0,2);grass:SetVertexColor(.55,.65,.42)
label("豌豆 · 8 粒子",45,40,210);label("寒冰 · 16 棱晶",270,40,210)
label("孢子 · 10 粒子",495,40,210);label("爆炸 · 37 粒子",720,40,210)
local host={kind="wow",now=GetTime,profileMS=debugprofilestop,date=function()return date("%Y-%m-%dT%H:%M:%S")end,
    memoryKB=gcinfo,fps=GetFramerate,profileClock="debugprofilestop/ms"}
local perf=E.newTelemetry(host,{sourceHash=sourceHash,gameId="particle_native_probe",clientVersion=GetBuildInfo(),scope="isolated_native_fx_canvas_no_game_save"})
local s={content=content,tick=0,frameSerial=0,time=0,perf=perf,world={byId={}}}
local fx=E.newEffects(s,{canvas=canvas,camera={x=0,y=0,zoom=1}})
local vfx=recipe({fx=fx})
local accumulator,cycle,nextEmission,speed,paused,mode=0,0,0,1,false,"demo"
local status=label("",20,408)
local results=label("",20,468)
local function stats()return fx.stats()end
local function close()
    if s.stopping then return end
    perf.finish("stopped",stats());s.stopping=true;fx.dispose();window:SetScript("OnUpdate",nil);window:Hide()
    IGFXProbeLog=perf.export()
end
IGFXProbe={close=close,fx=fx,session=s,window=window,hash=sourceHash}
local function button(text,x,fn)
    local b=CreateFrame("Button",nil,window,"UIPanelButtonTemplate");b:SetPoint("TOPLEFT",x,-436);b:SetSize(120,26);b:SetText(text);b:SetScript("OnClick",fn);return b
end
local function setMode(value)
    perf.finish("interrupted",stats());fx.clear();mode=value;paused=false;nextEmission=s.time;speed=value=="demo"and .35 or 1
    if value=="load"then fx.start("load",{x=450,y=165,seed=44})end
    if value~="demo"then perf.begin("fx_"..value,{kind="native_particles",mode=value,capacity=256},{warmup=2,duration=10})end
end
button("慢放演示",20,function()setMode("demo")end)
button("基线",150,function()setMode("baseline")end)
button("10 命中/秒",280,function()setMode("normal")end)
button("40 命中/秒",410,function()setMode("dense")end)
button("256 粒子",540,function()setMode("load")end)
button("暂停 / 继续",670,function()paused=not paused;accumulator=0 end)
button("关闭",800,close)
local function step(dt)
    s.tick=s.tick+1;s.time=s.time+dt
    local emitted=0
    while s.time>=nextEmission and mode~="baseline"and mode~="load"and emitted<4 do
        local interval=mode=="dense"and .025 or mode=="normal"and .1 or 1.8
        nextEmission=nextEmission+interval;cycle=cycle+1;emitted=emitted+1
        if mode=="demo"then
            vfx.impact(false,false,112,175);vfx.impact(true,false,337,175)
            vfx.impact(false,true,562,175);vfx.explosion(787,175,100)
        else
            perf.increment("fxImpactEvents")
            local x=80+(cycle*97)%740;local y=60+(cycle*31)%210
            vfx.impact(cycle%3==1,cycle%3==2,x,y)
            if cycle%10==0 then vfx.explosion(750,165,100)end
        end
    end
    fx.update(dt)
end
local updateAt=0
window:SetScript("OnUpdate",function(_,elapsed)
    local started=debugprofilestop();s.frameSerial=s.frameSerial+1;perf.beforeFrame()
    if not paused then
        accumulator=accumulator+math.min(.25,elapsed)*speed
        local n=0
        while accumulator>=1/30 and n<5 do
            accumulator=accumulator-1/30;n=n+1;local t=debugprofilestop();step(1/30);perf.record("effectsMs",debugprofilestop()-t)
        end
        accumulator=accumulator%(1/30)
        local t=debugprofilestop();fx.render(accumulator*30);perf.record("effectsRenderMs",debugprofilestop()-t)
    end
    local cost=debugprofilestop()-started
    perf.afterFrame(elapsed,cost,stats)
    if GetTime()>=updateAt then
        updateAt=GetTime()+.25;local st=stats()
        status:SetText(string.format("%s | 活动 %d / 256 · 可见 %d · 池 %d · 丢弃 %d · 淘汰 %d | 本帧 %.3f ms",mode,st.activeParticles,st.visibleParticles,st.pooledParticles,st.droppedParticles,st.evictedParticles,cost))
    end
    if perf.completed~=(IGFXProbe.completed or 0)then
        IGFXProbe.completed=perf.completed;IGFXProbeLog=perf.export()
        for i=#perf.records,1,-1 do local r=perf.records[i]
            if r.type=="phase.end"then local m=r.data.metrics.luaFrameMs;local f=r.data.metrics.frameMs
                if m then results:SetText(string.format("%s: Lua P95 %.2f ms / P99 %.2f ms · 帧 P95 %.1f ms · %d帧",r.data.name,m.p95,m.p99,f.p95,r.data.frames))end
                break
            end
        end
        if mode~="demo"and not perf.phase then paused=true end
    end
end)
