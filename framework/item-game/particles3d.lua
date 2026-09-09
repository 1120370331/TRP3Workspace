-- Bounded, deterministic 3D particles. Independent of mesh nodes and WoW APIs.
-- Particles live in world space; rendering produces camera-facing spark quads.
return function(E,G)
    local M,assert=E.math3d,G.assert
    local function number(v,lo,hi)return E.util.finite(v) and v>=lo and v<=hi end
    local function vector(v,default)
        v=v or default;assert(M.finite(v) and M.length(v)<=100000,"invalid 3D particle vector")
        return M.vec(v.x,v.y,v.z)
    end
    local function range(v,default,lo,hi)
        v=v or default;local a,b
        if type(v)=="table"then a,b=v[1],v[2]else a,b=v,v end
        assert(number(a,lo,hi) and number(b,lo,hi) and b>=a,"invalid 3D particle range")
        return {a,b}
    end
    local function color(v,default)
        v=v or default;for i=1,4 do assert(number(v[i],0,1),"invalid 3D particle color")end
        return {unpack(v)}
    end
    function E.newParticles3D(scene,definitions,limits)
        limits=limits or {};local capacity=limits.maxParticles3D or 512
        local emitterCapacity,spawnCapacity=limits.maxEmitters3D or 16,limits.maxParticleSpawns3DPerStep or 256
        assert(number(capacity,1,2048) and capacity%1==0 and number(emitterCapacity,1,64) and emitterCapacity%1==0 and
            number(spawnCapacity,1,1024) and spawnCapacity%1==0,"invalid 3D particle budget")
        local catalog={}
        for id,def in pairs(definitions or {})do
            assert(type(id)=="string" and type(def)=="table","invalid 3D particle definition")
            local d={mode=def.mode or "burst",shape=def.shape or "sphere",count=def.count or 48,rate=def.rate or 30,duration=def.duration or 1,
                spread=def.spread or .35,radius=def.radius or 0,drag=def.drag or 0,priority=def.priority or 0,
                direction=vector(def.direction,M.vec(0,1,0)),gravity=vector(def.gravity,M.vec(0,-1,0)),
                speed=range(def.speed,1,0,100),lifetime=range(def.lifetime,1,.02,15),size=range(def.size,.08,.002,2),
                endSize=def.endSize or .01,startColor=color(def.startColor,{1,.8,.3,1}),endColor=color(def.endColor,{1,.2,.05,0})}
            assert((d.mode=="burst" or d.mode=="continuous") and (d.shape=="sphere" or d.shape=="ring" or d.shape=="cone"),"invalid 3D emitter mode/shape")
            assert(number(d.count,1,2048) and d.count%1==0 and number(d.rate,0,2048) and number(d.duration,.02,60) and
                number(d.spread,0,math.pi) and number(d.radius,0,20) and number(d.drag,0,20) and number(d.endSize,0,2) and number(d.priority,-10,10),"invalid 3D emitter settings")
            d.direction=M.unit(d.direction);assert(M.length(d.direction)>.9,"3D emitter direction must be nonzero")
            d.right=M.unit(M.cross(d.direction,math.abs(d.direction.y)<.9 and M.vec(0,1,0) or M.vec(1,0,0)))
            d.up=M.cross(d.right,d.direction);catalog[id]=d
        end
        local self={revision=0,closed=false,particles={},emitters={},free={}}
        local used,serial,nextEmitter,peak,spawned,dropped,evicted,pooled=0,0,0,0,0,0,0,0
        local visible,renderDropped,qualityDropped,screenArea,evictionScans=0,0,0,0,0
        local renderPool,output,candidates,candidatePool={},{},{},{}
        local priorityCounts,lowestPriority={}
        local policy={minPixels=.1,maxDistance=100000,maxScreenArea=0,maxVisible=capacity,adaptive=false,targetMs=1000/60}
        local qualityScale,sampleTime,sampleFrames,sampleMS,recovery=1,0,0,0,0
        local function priorityChange(priority,delta)
            priorityCounts[priority]=(priorityCounts[priority] or 0)+delta
            if priorityCounts[priority]==0 then
                priorityCounts[priority]=nil
                if priority==lowestPriority then lowestPriority=nil;for p in pairs(priorityCounts)do if not lowestPriority or p<lowestPriority then lowestPriority=p end end end
            elseif not lowestPriority or priority<lowestPriority then lowestPriority=priority end
        end
        function self.setRenderPolicy(spec)
            if self.closed then return false,"particles_closed" end
            spec=spec or {}
            local p={minPixels=spec.minPixels or .1,maxDistance=spec.maxDistance or 100000,maxScreenArea=spec.maxScreenArea or 0,
                maxVisible=spec.maxVisible or capacity,adaptive=spec.adaptive==true,targetMs=spec.targetMs or 1000/60}
            assert(number(p.minPixels,.1,32) and number(p.maxDistance,.1,100000) and number(p.maxScreenArea,0,64) and
                number(p.maxVisible,1,capacity) and p.maxVisible%1==0 and number(p.targetMs,8,100),"invalid particle render policy")
            policy=p;qualityScale=1;sampleTime,sampleFrames,sampleMS,recovery=0,0,0,0;self.revision=self.revision+1;return true
        end
        function self.getRenderPolicy()return E.util.copy(policy)end
        function self.observeFrame(milliseconds)
            if not policy.adaptive or self.closed then return end
            if #self.particles==0 or not number(milliseconds,.01,250)then sampleTime,sampleFrames,sampleMS,recovery=0,0,0,0;return end
            sampleTime=sampleTime+milliseconds/1000;sampleMS=sampleMS+milliseconds;sampleFrames=sampleFrames+1
            if sampleTime<1 then return end
            local mean=sampleMS/sampleFrames;local nextScale=qualityScale
            if mean>policy.targetMs*1.25 then nextScale=math.max(.25,qualityScale-.25);recovery=0
            elseif mean<=policy.targetMs*1.05 then recovery=recovery+sampleTime
                if recovery>=3 then nextScale=math.min(1,qualityScale+.25);recovery=0 end
            else recovery=0 end
            sampleTime,sampleFrames,sampleMS=0,0,0
            if nextScale~=qualityScale then qualityScale=nextScale;self.revision=self.revision+1 end
        end
        local function rng(seed)
            assert(seed==nil or number(seed,-1e12,1e12),"invalid particle seed")
            local value=math.floor(math.abs(seed or (serial+1)*911))%2147483646+1
            return function()value=value*16807%2147483647;return (value-1)/2147483646 end
        end
        local function sample(r,random)return r[1]+(r[2]-r[1])*random()end
        local function origin(params)
            local p=vector(params.position,M.vec())
            if params.nodeId then
                if not scene.get(params.nodeId)then return nil,"particle_owner_missing" end
                p=scene.worldPoint(params.nodeId,p)
            end
            return p
        end
        local function parameters(params)
            params=params or {};local p,why=origin(params);if not p then return nil,why end
            local scale=params.scale or 1;assert(number(scale,.1,4),"invalid particle scale")
            local multiplier=params.countScale or 1;assert(number(multiplier,.1,8),"invalid particle count scale")
            return {position=p,offset=vector(params.position,M.vec()),nodeId=params.nodeId,scale=scale,countScale=multiplier,
                velocity=vector(params.velocity,M.vec()),emitterVelocity=vector(params.emitterVelocity,M.vec()),
                emitterAcceleration=vector(params.emitterAcceleration,M.vec()),random=rng(params.seed)}
        end
        local function remove(i)
            local list=self.particles;priorityChange(list[i].priority,-1);self.free[#self.free+1]=list[i];list[i]=list[#list];list[#list]=nil
        end
        local function spawn(d,p,owner,index,total)
            if used>=spawnCapacity then dropped=dropped+1;return false end
            used=used+1
            local slot
            if #self.particles>=capacity then
                -- The common saturated case rejects in O(1), without scanning
                -- the whole live pool for each same-priority spawn attempt.
                if d.priority<=lowestPriority then dropped=dropped+1;return false end
                local candidate
                evictionScans=evictionScans+1
                for i,old in ipairs(self.particles)do if old.priority==lowestPriority and
                    (not candidate or old.serial<self.particles[candidate].serial)then candidate=i end end
                if not candidate then dropped=dropped+1;return false end
                slot=self.particles[candidate];self.particles[candidate]=self.particles[#self.particles];self.particles[#self.particles]=nil
                priorityChange(slot.priority,-1)
                evicted=evicted+1
            else slot=table.remove(self.free)end
            if not slot then pooled=pooled+1;slot={poolId=pooled,renderKey="p:"..pooled} end
            local random=p.random;local theta=random()*2*math.pi;local direction
            if d.shape=="sphere" then
                local y=random()*2-1;local rad=math.sqrt(math.max(0,1-y*y));direction=M.vec(math.cos(theta)*rad,y,math.sin(theta)*rad)
            elseif d.shape=="ring" then
                theta=((index-1)/math.max(1,total)+random()*.008)*2*math.pi
                direction=M.add(M.mul(d.right,math.cos(theta)),M.mul(d.up,math.sin(theta)))
            else
                local cos=1-random()*(1-math.cos(d.spread));local sin=math.sqrt(math.max(0,1-cos*cos))
                direction=M.add(M.mul(d.direction,cos),M.add(M.mul(d.right,math.cos(theta)*sin),M.mul(d.up,math.sin(theta)*sin)))
            end
            local speed=sample(d.speed,random)*p.scale
            local position=M.add(p.position,M.mul(direction,d.radius*p.scale))
            slot.x,slot.y,slot.z=position.x,position.y,position.z;slot.px,slot.py,slot.pz=position.x,position.y,position.z
            slot.vx,slot.vy,slot.vz=direction.x*speed+p.velocity.x,direction.y*speed+p.velocity.y,direction.z*speed+p.velocity.z
            slot.age,slot.previousAge,slot.life=0,0,sample(d.lifetime,random)
            slot.size,slot.endSize=sample(d.size,random)*p.scale,d.endSize*p.scale
            slot.def,slot.owner,slot.priority=d,owner,d.priority;serial=serial+1;slot.serial=serial
            priorityChange(slot.priority,1)
            self.particles[#self.particles+1]=slot;spawned=spawned+1;peak=math.max(peak,#self.particles);return true
        end
        local function spawnMany(d,p,count,owner)
            local made=0
            -- Stop work once the shared step budget is exhausted; count every omission.
            local accepted=math.min(count,math.max(0,spawnCapacity-used));dropped=dropped+count-accepted
            for i=1,accepted do if spawn(d,p,owner,i,count)then made=made+1 end end
            if made>0 then self.revision=self.revision+1 end;return made,count-made
        end
        function self.burst(id,params)
            if self.closed then return nil,"particles_closed" end
            local d=catalog[id];if not d or d.mode~="burst"then return nil,"unknown_particle_burst" end
            local p,why=parameters(params);if not p then return nil,why end
            local count=params and params.count or math.floor(d.count*p.countScale)
            assert(number(count,1,2048) and count%1==0,"invalid 3D burst count")
            return spawnMany(d,p,count,nil)
        end
        function self.start(id,params)
            if self.closed then return nil,"particles_closed" end
            local d=catalog[id];if not d or d.mode~="continuous"then return nil,"unknown_particle_emitter" end
            if #self.emitters>=emitterCapacity then return nil,"3D_emitter_budget" end
            local p,why=parameters(params);if not p then return nil,why end
            local duration=params and params.duration or d.duration
            assert(number(duration,.02,60),"invalid 3D emitter duration")
            nextEmitter=nextEmitter+1
            self.emitters[#self.emitters+1]={id=nextEmitter,def=d,params=p,age=0,accumulator=0,duration=duration,base=M.vec(p.position.x,p.position.y,p.position.z)}
            return nextEmitter
        end
        function self.stop(id,kill)
            local found=false
            for i=#self.emitters,1,-1 do if self.emitters[i].id==id then table.remove(self.emitters,i);found=true end end
            if kill then for i=#self.particles,1,-1 do if self.particles[i].owner==id then remove(i);found=true end end end
            if found then self.revision=self.revision+1 end;return found
        end
        function self.clear()
            for i=#self.particles,1,-1 do remove(i)end
            self.emitters={};visible=0;renderDropped=0;qualityDropped=0;screenArea=0;self.revision=self.revision+1
        end
        function self.update(dt)
            if self.closed then return end
            assert(number(dt,0,.25),"invalid 3D particle timestep")
            local changed=#self.particles>0
            for i=#self.particles,1,-1 do
                local p=self.particles[i];p.px,p.py,p.pz,p.previousAge=p.x,p.y,p.z,p.age;p.age=p.age+dt
                if p.age>=p.life then remove(i)
                else
                    local d=p.def
                    if d.dampingDT~=dt then d.damping=math.exp(-d.drag*dt);d.dampingDT=dt end
                    local damping=d.damping
                    p.vx=(p.vx+d.gravity.x*dt)*damping;p.vy=(p.vy+d.gravity.y*dt)*damping;p.vz=(p.vz+d.gravity.z*dt)*damping
                    p.x=p.x+p.vx*dt;p.y=p.y+p.vy*dt;p.z=p.z+p.vz*dt
                end
            end
            for i=#self.emitters,1,-1 do
                local e=self.emitters[i];local p=e.params;local active=math.min(dt,e.duration-e.age);e.age=e.age+active
                local base=e.base
                if p.nodeId then if scene.get(p.nodeId)then base=scene.worldPoint(p.nodeId,p.offset)else base=nil end end
                if base then
                    local age=e.age;local half=.5*age*age;local v,a=p.emitterVelocity,p.emitterAcceleration
                    p.position.x,p.position.y,p.position.z=base.x+v.x*age+a.x*half,base.y+v.y*age+a.y*half,base.z+v.z*age+a.z*half
                    e.accumulator=e.accumulator+e.def.rate*p.countScale*active
                    local count=math.floor(e.accumulator+1e-9);e.accumulator=e.accumulator-count
                    if count>0 then spawnMany(e.def,p,count,e.id)end
                end
                if not base or e.age>=e.duration-1e-9 then table.remove(self.emitters,i)end
            end
            if changed then self.revision=self.revision+1 end
            used=0
        end
        function self.renderList(alpha,budget)
            alpha=E.util.clamp(alpha or 1,0,1);budget=math.max(0,math.min(capacity,budget or capacity))
            local project,v=scene.projector();local n,eligible=0,0;visible=0;renderDropped=0;qualityDropped=0;screenArea=0
            local limit=math.min(budget,math.max(1,math.floor(policy.maxVisible*qualityScale)))
            local areaLimit=policy.maxScreenArea>0 and policy.maxScreenArea*v.w*v.h*qualityScale or math.huge
            for _,p in ipairs(self.particles)do
                local x,y,z,focal=project(p.px+(p.x-p.px)*alpha,p.py+(p.y-p.py)*alpha,p.pz+(p.z-p.pz)*alpha)
                if x then
                    local age=p.previousAge+(p.age-p.previousAge)*alpha;local t=age/p.life
                    local half=(p.size+(p.endSize-p.size)*t)*focal/z/2
                    local l,r,top,bottom=math.max(v.x,x-half),math.min(v.x+v.w,x+half),math.max(v.y,y-half),math.min(v.y+v.h,y+half)
                    if half>.05 and r>l and bottom>top then
                        visible=visible+1
                        if half*2>=policy.minPixels and z<=policy.maxDistance then
                            eligible=eligible+1;local c=candidatePool[p.poolId] or {};candidatePool[p.poolId]=c;candidates[eligible]=c
                            c.p,c.x,c.y,c.z,c.half,c.l,c.r,c.top,c.bottom,c.t=p,x,y,z,half,l,r,top,bottom,t
                        else qualityDropped=qualityDropped+1 end
                    end
                end
            end
            for i=#candidates,eligible+1,-1 do candidates[i]=nil end
            if eligible>limit or areaLimit<math.huge then
                table.sort(candidates,function(a,b)if a.p.priority==b.p.priority then return a.p.serial<b.p.serial end;return a.p.priority>b.p.priority end)
            end
            for _,c in ipairs(candidates)do
                local area=(c.r-c.l)*(c.bottom-c.top)
                if n<limit and screenArea+area<=areaLimit then
                    local p,x,y,z,half,l,r,top,bottom,t=c.p,c.x,c.y,c.z,c.half,c.l,c.r,c.top,c.bottom,c.t
                    n=n+1;screenArea=screenArea+area;local f=renderPool[p.poolId]
                    if not f then f={points={{},{},{},{}},color={},texCoord={},blend="ADD",texture="Interface\\Cooldown\\star4"};renderPool[p.poolId]=f end
                    local points=f.points;points[1].x,points[1].y=l,top;points[2].x,points[2].y=r,top
                    points[3].x,points[3].y=r,bottom;points[4].x,points[4].y=l,bottom
                    f.texCoord[1],f.texCoord[2],f.texCoord[3],f.texCoord[4]=(l-x+half)/(2*half),(r-x+half)/(2*half),(top-y+half)/(2*half),(bottom-y+half)/(2*half)
                    for j=1,4 do f.color[j]=p.def.startColor[j]+(p.def.endColor[j]-p.def.startColor[j])*t end
                    f.depth=z;f.order=p.serial;f.key=p.renderKey;output[n]=f
                elseif n<budget then qualityDropped=qualityDropped+1 end
            end
            renderDropped=visible-n;screenArea=screenArea/(v.w*v.h)
            for i=#output,n+1,-1 do output[i]=nil end
            table.sort(output,function(a,b)if a.depth==b.depth then return a.order<b.order end;return a.depth>b.depth end)
            return output
        end
        function self.stats()
            return {particles3D=#self.particles,emitters3D=#self.emitters,particles3DPeak=peak,particles3DPooled=pooled,
                particles3DSpawned=spawned,particles3DDropped=dropped,particles3DEvicted=evicted,particles3DVisible=visible,particles3DRenderDropped=renderDropped,particles3DCapacity=capacity,
                particles3DQualityDropped=qualityDropped,particles3DQualityScale=qualityScale,particles3DScreenArea=screenArea,particles3DEvictionScans=evictionScans}
        end
        function self.resetStats()
            peak=#self.particles;spawned=0;dropped=0;evicted=0;renderDropped=0;qualityDropped=0;evictionScans=0
        end
        function self.dispose()self.clear();self.closed=true end
        return self
    end
end
