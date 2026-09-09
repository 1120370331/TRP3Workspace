-- Three independent subjects exercise embedded pixel materials and original UVs.
local L={}
function L.new(ctx,scene,art)
    local M=ctx.scene3d.math
    local self={active=false,selected=1,rotation=0,spinning=false,message="点阵经 UV 映射到模型表面；不加载 PNG。"}
    local registered=false;local angle=0;local motionTime=0;local trails={};local trailTime=0
    self.motion=0;self.effectsEnabled=false
    local subjects={{id="material_cube",name="海潮符文匣",texture=1,rotation=0},{id="material_obelisk",name="潮汐方碑",texture=3,rotation=0},{id="material_pyramid",name="仪式晶石",texture=5,rotation=0}}
    local positions={M.vec(-2.1,0,0),M.vec(0,0,0),M.vec(2.1,0,0)}
    local function box()
        local mesh=ctx.scene3d.boxMesh(1,{1,1,1,1})
        for _,f in ipairs(mesh.faces)do
            local a,b,c=mesh.vertices[f[1]],mesh.vertices[f[2]],mesh.vertices[f[3]]
            local normal=M.unit(M.cross(M.sub(b,a),M.sub(c,a)));local right,up
            if math.abs(normal.y)>.5 then right=M.vec(1,0,0);up=M.vec(0,0,-normal.y)
            else right=M.cross(M.vec(0,1,0),normal);up=M.vec(0,1,0)end
            f.uv={};for _,index in ipairs(f)do local v=mesh.vertices[index];f.uv[#f.uv+1]={u=.5+M.dot(v,right),v=.5-M.dot(v,up)}end
        end
        return mesh
    end
    local function pyramid()
        return {vertices={M.vec(-.6,-.7,-.6),M.vec(.6,-.7,-.6),M.vec(.6,-.7,.6),M.vec(-.6,-.7,.6),M.vec(0,.9,0)},
            faces={{4,3,5},{3,2,5},{2,1,5},{1,4,5},{1,2,3,4}}}
    end
    local function bind(index)
        local subject=subjects[index];local bindings={}
        local mesh=scene.get(subject.id).mesh
        for i=1,#mesh.faces do
            local texture=subject.sixFaces and ((i-1)%6+1) or subject.texture
            bindings[i]={texture=art.faces[texture].id,rotation=subject.rotation}
        end
        local ok,why=scene.setPixelMaterials(subject.id,bindings)
        self.message=ok and (subject.name.."：点阵材质已绑定。") or ("材质未应用："..tostring(why))
        return ok
    end
    function self.enter()
        if not registered then
            for _,face in ipairs(art.faces)do
                if not scene.pixelTextures[face.id]then
                assert(scene.definePixelTexture(face.id,{width=art.width,height=art.height,codec=art.codec,palette=art.palette,data=face.data}))
                end
            end
            registered=true
        end
        scene.clear();self.active=true;self.spinning=false;self.motion=0;self.effectsEnabled=false;motionTime=0;angle=.3
        scene.create("material_group",{})
        for i,subject in ipairs(subjects)do
            scene.create(subject.id,{parent="material_group",mesh=i==3 and pyramid() or box(),position=positions[i],
                scale=i==1 and M.vec(1.4,1.4,1.4) or i==2 and M.vec(1.05,2.1,1.05) or M.vec(1.2,1.2,1.2),rotation=M.vec(0,.3,0),tag=subject.name})
            subject.sixFaces=i==1;subject.rotation=0
            assert(bind(i),"pixel material scene exceeds its face budget")
        end
        scene.orbit(.27,.24,5.8,M.vec())
        self.message="三个主体已绑定内嵌点阵；可换图、旋转 UV 或转动模型。"
    end
    function self.leave()self.active=false;self.spinning=false;self.motion=0;scene.particles.clear();trails={};scene.clear()end
    function self.select(index)if subjects[index]then self.selected=index;angle=scene.get(subjects[index].id).rotation.y;self.message="已选择："..subjects[index].name end end
    function self.pick(hit)for i,s in ipairs(subjects)do if s.id==hit.id then self.select(i);return true end end;return false end
    function self.texture(index)
        local subject=subjects[self.selected];local old,six=subject.texture,subject.sixFaces
        subject.texture=index;subject.sixFaces=false;local ok=bind(self.selected)
        if not ok then subject.texture=old;subject.sixFaces=six end;return ok
    end
    function self.sixFaces()
        local subject=subjects[self.selected];local old=subject.sixFaces;subject.sixFaces=true
        local ok=bind(self.selected);if not ok then subject.sixFaces=old end;return ok
    end
    function self.rotateUV()
        local subject=subjects[self.selected];local old=subject.rotation;subject.rotation=(old+1)%4
        local ok=bind(self.selected);if not ok then subject.rotation=old end;return ok
    end
    function self.removeMaterial()
        local subject=subjects[self.selected];scene.setPixelMaterials(subject.id,nil);subject.sixFaces=false
        self.message="已解除像素绑定；模型几何仍然保留。"
    end
    function self.toggleSpin()self.spinning=not self.spinning;angle=scene.get(subjects[self.selected].id).rotation.y end
    function self.rotateGroup()
        local rotation=scene.get("material_group").rotation
        scene.setTransform("material_group",{rotation=M.vec(0,rotation.y+math.pi/4,0)})
        self.message="整组转动45°；各主体的点阵绑定保持不变。"
    end
    local function startTrails()
        for _,id in ipairs(trails)do scene.particles.stop(id,true)end;trails={};trailTime=0
        for i,s in ipairs(subjects)do
            local id=scene.particles.start("rocket_trail",{nodeId=s.id,duration=60,countScale=.55,seed=i*7919})
            if id then trails[#trails+1]=id end
        end
    end
    function self.toggleMotion()
        self.motion=(self.motion+1)%3;motionTime=0
        scene.setTransform("material_group",{position=M.vec()});scene.orbit(.27,.24,5.8,M.vec())
        if self.motion>0 then startTrails();self.message=self.motion==1 and "模型穿越视口；世界空间拖尾保留原轨迹。" or "镜头平移与推进；屏幕外模型自动跳过像素计算。"
        else for _,id in ipairs(trails)do scene.particles.stop(id,true)end;trails={};self.message="空间运动已停止。"end
    end
    function self.toggleEffects()
        self.effectsEnabled=not self.effectsEnabled
        for i,s in ipairs(subjects)do
            scene.effects.set(s.id,self.effectsEnabled and {color={.15,.75,1},rim=.55,power=2,pulse=.22,speed=.7,phase=i,emissive=.04} or nil)
        end
        scene.effects.setFog(self.effectsEnabled and {near=5,far=18,color={.055,.061,.078}} or nil)
        self.message=self.effectsEnabled and "已启用奥术脉冲、轮廓光与距离雾。" or "已恢复原始材质光照。"
    end
    function self.update(dt)
        if self.active and self.motion>0 then
            motionTime=motionTime+dt;trailTime=trailTime+dt
            if self.motion==1 then scene.setTransform("material_group",{position=M.vec(math.sin(motionTime*.6)*8,math.sin(motionTime*.7)*.35,math.sin(motionTime*.3)*2)})
            else scene.orbit(.27,.24,5.8+math.sin(motionTime*.5)*2,M.vec(math.sin(motionTime*.35)*5,0,0))end
            if trailTime>=59 then startTrails()end
        end
        if self.active and self.spinning then
            angle=angle+dt*.55
            scene.setTransform(subjects[self.selected].id,{rotation=M.vec(math.sin(angle*.5)*.2,angle,0)})
        end
    end
    function self.snapshot()
        local subject=subjects[self.selected];local encoded,rects=#art.palette*6,0
        for _,face in ipairs(art.faces)do encoded=encoded+#face.data end
        for _,texture in pairs(scene.pixelTextures)do rects=rects+#texture.rectangles end
        local labels={}
        if self.active then for i,s in ipairs(subjects)do
            local left,right,bottom=math.huge,-math.huge,-math.huge
            for _,p in ipairs(scene.get(s.id).mesh.vertices)do
                local x,y=scene.project(scene.worldPoint(s.id,p))
                if x then left=math.min(left,x);right=math.max(right,x);bottom=math.max(bottom,y)end
            end
            if left~=math.huge and scene.get(s.id).renderVisible then labels[#labels+1]={name=s.name,x=(left+right)/2,y=bottom,selected=i==self.selected}end
        end end
        return {selected=self.selected,name=subject.name,texture=subject.texture,sixFaces=subject.sixFaces,uvRotation=subject.rotation,
            bound=self.active and scene.get(subject.id).pixelBindings~=nil,spinning=self.spinning,motion=self.motion,effectsEnabled=self.effectsEnabled,
            message=self.message,faces=art.faces,subjects=subjects,labels=labels,rectangles=rects,encodedBytes=encoded,stats=scene.stats()}
    end
    return self
end
return L
