-- Game-owned firework choreography and repeatable performance trials.
-- Physics, pooling, emission and projection live in the shared 3D particle system.
local F={}
F.kinds={{id="peony",name="星辉礼花"},{id="ring",name="奥术星环"},{id="willow",name="鎏金垂柳"},{id="fountain",name="翡翠喷泉"},{id="crackle",name="连环爆裂"}}
function F.new(ctx,scene,getOrder,getSkin)
    local M,fx=ctx.scene3d.math,scene.particles
    local self={selected="peony",intensity=2,testing=false,message="选择烟花，或运行四阶段性能对照。",rewards=0}
    local queue,time,serial,stage,nextLaunch={},0,0,0,0
    local intensity={.55,1,3};local phaseLabels={"空场基线","低密度","标准密度","高密度"}
    local settings=ctx.content.fireworksLab or {};local duration=settings.duration or 5;local warmup=settings.warmup or 1
    self.adaptive=true
    local function quality()
        -- Repeatable benchmark phases use the full fixed workload. Normal play
        -- can shed draw work without changing seeds, simulation or rewards.
        fx.setRenderPolicy(self.adaptive and not self.testing and {adaptive=true,minPixels=.5,maxScreenArea=4} or nil)
    end
    quality()
    function self.toggleQuality()if not self.testing then self.adaptive=not self.adaptive;quality()end end
    local function schedule(delay,fn)
        if #queue>=96 then return false end
        queue[#queue+1]={at=time+delay,fn=fn};return true
    end
    local function launch(kind,level,side)
        serial=serial+1;local seed=serial*7919;local factor=intensity[level]
        -- Place the launch pads beside the current view of the cube, then keep
        -- their trajectories in world space even if the player orbits the camera.
        local camera=scene.getCamera();local toward=M.unit(M.sub(camera.position,camera.target))
        local right=M.unit(M.cross(M.vec(0,1,0),toward))
        local start=M.add(camera.target,M.add(M.mul(right,(side or (serial%2==0 and -2.15 or 2.15))*1.25),M.mul(toward,serial%3==0 and -.5 or 1.6)))
        start.y=-1.35
        if kind=="fountain" then
            fx.start("fountain",{position=start,countScale=factor,seed=seed});return
        end
        local flight=.65;local rise=M.vec(0,3.5,0);local acceleration=M.vec(0,-2,0)
        fx.start("rocket_trail",{position=start,emitterVelocity=rise,emitterAcceleration=acceleration,duration=flight,countScale=factor,seed=seed})
        local center=M.add(start,M.add(M.mul(rise,flight),M.mul(acceleration,.5*flight*flight)))
        schedule(flight,function()
            fx.burst(kind,{position=center,countScale=factor,seed=seed+1})
            fx.burst("flash",{position=center,seed=seed+2})
            if kind=="crackle" then
                for i=1,7 do
                    local theta=i*2*math.pi/7
                    local p=M.add(center,M.vec(math.cos(theta)*.65,math.sin(theta)*.65,(i%3-1)*.5))
                    schedule(.16+i*.065,function()fx.burst("crackle",{position=p,countScale=factor*.6,seed=seed+i*17})end)
                end
            end
        end)
    end
    function self.stop(reason)
        if self.ownsPhase and ctx.perf.isRunning()then ctx.perf.finish(reason or "cancelled")end
        self.ownsPhase=false
        self.testing=false;stage=0;queue={};fx.clear();quality()
        self.message=reason=="complete" and "对照完成，可导出每阶段的帧耗时与粒子统计。" or "已停止烟花。"
    end
    function self.select(id)
        for _,kind in ipairs(F.kinds)do if kind.id==id then self.selected=id;return true end end;return false
    end
    function self.setIntensity(level)if level>=1 and level<=3 then self.intensity=level end end
    function self.preview()
        if self.testing or ctx.session.isPaused()then return false end
        queue={};fx.clear();fx.resetStats()
        ctx.perf.begin("fireworks.preview",{kind="particles3d",pattern=self.selected,intensity=self.intensity,order=getOrder()},{warmup=.2,duration=5});self.ownsPhase=true
        launch(self.selected,self.intensity)
        self.message="正在燃放，可旋转视角观察空间轨迹和遮挡。";return true
    end
    function self.show(reason)
        if self.testing or ctx.session.isPaused()then return false end
        queue={};fx.clear();fx.resetStats()
        ctx.perf.begin(reason and "fireworks.reward" or "fireworks.mixed",{kind="particles3d",pattern="five_types",intensity=self.intensity,order=getOrder(),reason=reason},{warmup=.2,duration=6});self.ownsPhase=true
        for i,kind in ipairs(F.kinds)do schedule((i-1)*.55,function()launch(kind.id,self.intensity,i%2==0 and -2.15 or 2.15)end)end
        self.message="五式烟花依次燃放。";return true
    end
    function self.celebrate(reason)
        if self.testing then return end
        self.rewards=self.rewards+1;self.show(reason)
        ctx.perf.note("fireworks.reward",{reason=reason,sequence=self.rewards,order=getOrder()})
    end
    local function phase()
        queue={};fx.clear();fx.resetStats();serial=0;nextLaunch=time
        ctx.perf.begin("fireworks."..({"baseline","low","normal","high"})[stage],
            {kind="particles3d",order=getOrder(),skin=getSkin and getSkin() or "classic",pattern="five_types",intensity=stage-1,
                camera=scene.getCamera(),seed=7919,countersScope="phase_including_warmup",cubeMotion="static",particlePolicy=fx.getRenderPolicy()},
            {warmup=warmup,duration=duration})
        self.ownsPhase=true
        self.message=phaseLabels[stage].."：固定镜头与魔方，正在采样。"
    end
    function self.benchmark()
        if self.testing or ctx.session.isPaused()then return false end
        self.testing=true;quality();stage=1;phase();return true
    end
    function self.update(dt)
        time=time+dt
        -- Remove ready tasks before invoking them: crackles can schedule child bursts.
        local ready={}
        for i=#queue,1,-1 do if queue[i].at<=time then ready[#ready+1]=table.remove(queue,i)end end
        for i=#ready,1,-1 do ready[i].fn()end
        if self.testing then
            if not ctx.perf.isRunning()then
                stage=stage+1
                if stage>4 then self.stop("complete");return else phase()end
            end
            if stage>1 and time>=nextLaunch then
                nextLaunch=time+(stage==4 and .18 or .55)
                local kind=F.kinds[serial%#F.kinds+1];launch(kind.id,stage-1)
            end
        end
    end
    function self.onPause()
        if self.testing then self.testing=false;quality();stage=0;queue={};self.message="测试已中断；已完成的阶段仍可导出。"end
    end
    function self.snapshot()
        local perf=ctx.perf.snapshot();local last=perf.last
        return {selected=self.selected,intensity=self.intensity,testing=self.testing,adaptive=self.adaptive,message=self.message,
            phase=stage>0 and phaseLabels[stage] or "",stats=fx.stats(),perf=perf,
            metrics=perf.metrics or (last and last.metrics) or {},rewards=self.rewards,
            totalSeconds=4*(duration+warmup)}
    end
    return self
end
return F
