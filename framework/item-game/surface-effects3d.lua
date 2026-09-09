-- Shader-like surface lighting using native vertex colors, not GPU programs.
-- Compute uniforms per node and view-dependent coefficients per source face.
return function(E,G)
    local clamp=E.util.clamp
    local function number(v,lo,hi)return E.util.finite(v) and v>=lo and v<=hi end
    local function color(v)
        v=v or {0,1,1}
        assert(type(v)=="table","invalid surface effect color")
        for i=1,3 do assert(number(v[i],0,1),"invalid surface effect color")end
        return {v[1],v[2],v[3]}
    end
    function E.newSurfaceEffects3D(scene)
        local self={fogRevision=0};local effects,animated={},{};local fog;local time,tick=0,0
        local function changed(id)
            local n=scene.get(id);if n then n.effectRevision=(n.effectRevision or 0)+1 end
            scene.invalidateShading()
        end
        function self.set(id,spec)
            if scene.closed then return false,"scene_closed" end
            assert(scene.get(id),"unknown 3D node")
            local d
            if spec then
                assert(type(spec)=="table","invalid surface effect")
                d={color=color(spec.color),emissive=spec.emissive or 0,rim=spec.rim or 0,power=spec.power or 2,
                    pulse=spec.pulse or 0,speed=spec.speed or 1,phase=spec.phase or 0}
                assert(number(d.emissive,0,1) and number(d.rim,0,1) and number(d.power,1,8) and number(d.pulse,0,1) and
                    number(d.speed,0,20) and number(d.phase,-10000,10000),"invalid surface effect settings")
                d.energy=d.emissive+d.pulse*(.5+.5*math.sin(time*d.speed*2*math.pi+d.phase))
            end
            effects[id]=d;animated[id]=d and d.pulse>0 and d.speed>0 and d or nil
            changed(id);return true
        end
        function self.setFog(spec)
            if scene.closed then return false,"scene_closed" end
            local d
            if spec then
                d={near=spec.near,far=spec.far,color=color(spec.color)}
                assert(number(d.near,0,100000) and number(d.far,0,100000) and d.far>d.near,"invalid distance fog")
            end
            fog=d;self.fogRevision=self.fogRevision+1;scene.invalidateShading();return true
        end
        function self.update(dt)
            time=time+dt;local nextTick=math.floor(time*30+1e-8)
            if tick==nextTick then return end;tick=nextTick
            -- Uniform animation is capped at 30 Hz, independently of mesh movement.
            for id,d in pairs(animated)do
                d.energy=d.emissive+d.pulse*(.5+.5*math.sin(time*d.speed*2*math.pi+d.phase));changed(id)
            end
        end
        function self.coefficients(n,index,normal,camera,depth)
            local c={0,0,0,0,0,0,0};local d=effects[n.id]
            if d then
                local amount=d.energy
                if d.rim>0 then
                    local x,y,z=0,0,0;local face=n.mesh.faces[index]
                    for _,i in ipairs(face)do local v=n.vertices[i];x=x+v.x;y=y+v.y;z=z+v.z end
                    x,y,z=camera.x-x/#face,camera.y-y/#face,camera.z-z/#face
                    local length=math.sqrt(x*x+y*y+z*z)
                    local facing=length>1e-8 and math.abs((normal.x*x+normal.y*y+normal.z*z)/length) or 1
                    amount=amount+d.rim*(1-clamp(facing,0,1))^d.power
                end
                for j=1,3 do c[j]=d.color[j]*amount end
            end
            if fog then
                c[4]=clamp((depth-fog.near)/(fog.far-fog.near),0,1)
                for j=1,3 do c[j+4]=fog.color[j]end
            end
            return c
        end
        function self.clear()
            for id in pairs(effects)do changed(id)end
            effects={};animated={};fog=nil;self.fogRevision=self.fogRevision+1;scene.invalidateShading()
        end
        function self.capabilities()return {backend="vertex-color",customGPUShader=false,rim=true,emissive=true,pulse=true,distanceFog=true}end
        return self
    end
end
