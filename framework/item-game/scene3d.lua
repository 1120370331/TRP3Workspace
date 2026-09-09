-- Retained 3D scene: hierarchical transforms, convex meshes, perspective camera,
-- six-plane clipping, ray picking and bounded spatial queries. Host-independent.
return function(E,G)
    local M=E.math3d
    local axes={"x","y","z"}
    local function copy(v) return M.vec(v.x,v.y,v.z) end
    local function same(a,b)return a.x==b.x and a.y==b.y and a.z==b.z end
    local function bounds(vertices)
        local lo,hi=M.vec(math.huge,math.huge,math.huge),M.vec(-math.huge,-math.huge,-math.huge)
        for _,v in ipairs(vertices)do for _,a in ipairs(axes)do lo[a]=math.min(lo[a],v[a]);hi[a]=math.max(hi[a],v[a])end end
        return {min=lo,max=hi}
    end
    function E.boxMesh(size,color)
        local s=(size or 1)/2
        return {vertices={M.vec(-s,-s,-s),M.vec(s,-s,-s),M.vec(s,s,-s),M.vec(-s,s,-s),
            M.vec(-s,-s,s),M.vec(s,-s,s),M.vec(s,s,s),M.vec(-s,s,s)},faces={
            {1,4,3,2,color=color},{5,6,7,8,color=color},{1,5,8,4,color=color},
            {2,3,7,6,color=color},{4,8,7,3,color=color},{1,2,6,5,color=color}}}
    end
    local function validateMesh(mesh)
        if not mesh then return 0 end
        assert(type(mesh.vertices)=="table" and #mesh.vertices>=3 and #mesh.vertices<=8192,"invalid 3D mesh vertices")
        assert(type(mesh.faces)=="table" and #mesh.faces>=1 and #mesh.faces<=4096,"invalid 3D mesh faces")
        for _,v in ipairs(mesh.vertices)do assert(M.finite(v) and M.length(v)<100000,"invalid 3D vertex")end
        for _,f in ipairs(mesh.faces)do
            assert(#f>=3 and #f<=4,"3D faces must be convex triangles or quads")
            for _,i in ipairs(f)do assert(type(i)=="number" and i%1==0 and mesh.vertices[i],"invalid 3D face index")end
            assert(f.surfaceGroup==nil or (type(f.surfaceGroup)=="string" and #f.surfaceGroup<=80),"invalid 3D surface group")
            local c=f.color or {1,1,1,1}
            for i=1,4 do assert(E.util.finite(c[i]) and c[i]>=0 and c[i]<=1,"invalid 3D face color")end
        end
        return #mesh.faces
    end
    function E.newScene3D(options)
        options=options or {}
        local self={nodes={},order={},revision=0,shadingRevision=0,faceCount=0,closed=false,pixelTextures={}}
        local maxNodes,maxFaces=options.maxNodes or 512,options.maxFaces or 4096
        assert(maxNodes%1==0 and maxNodes>=1 and maxNodes<=1024 and maxFaces%1==0 and maxFaces>=1 and maxFaces<=4096,"invalid 3D budget")
        local camera={position=M.vec(6,4,8),target=M.vec(),up=M.vec(0,1,0),fov=math.pi/4,near=.1,far=100}
        local viewport={x=0,y=0,w=options.width or 640,h=options.height or 600}
        local synced=-1;local drawCache,drawRevision={},-1
        local cameraVersion,worldVersion,nextOrder=0,0,0
        local transformedNodes,projectedNodes,culledNodes,paintedVertices,projectedVertices=0,0,0,0,0
        local cameraCache
        function self.invalidate() self.revision=self.revision+1 end
        function self.invalidateShading()self.shadingRevision=self.shadingRevision+1 end
        function self.get(id)return self.nodes[id]end
        function self.definePixelTexture(id,definition)
            if self.closed then return false,"scene_closed" end
            assert(E.pixelMaterials,"pixel-materials package is required")
            assert(type(id)=="string" and #id>0 and #id<=80,"invalid pixel texture ID")
            if self.pixelTextures[id]then return false,"pixel_texture_exists" end
            local count=0;for _ in pairs(self.pixelTextures)do count=count+1 end
            if count>=32 then return false,"pixel_texture_budget" end
            self.pixelTextures[id]=E.pixelMaterials.decode(definition);return true
        end
        function self.setPixelMaterials(id,bindings)
            if self.closed then return false,"scene_closed" end
            assert(E.pixelMaterials,"pixel-materials package is required")
            local n=assert(self.nodes[id],"unknown 3D node");assert(n.mesh,"pixel material needs a mesh")
            if bindings==nil then
                self.faceCount=self.faceCount-n.faceCount+#n.mesh.faces;n.faceCount=#n.mesh.faces
                n.paintMesh=nil;n.paintVertices=nil;n.pixelBindings=nil
            else
                local painted,why=E.pixelMaterials.bake(n.mesh,bindings,self.pixelTextures,maxFaces-self.faceCount+n.faceCount)
                if not painted then return false,why end
                self.faceCount=self.faceCount-n.faceCount+#painted.faces;n.faceCount=#painted.faces
                n.paintMesh=painted;n.pixelBindings=E.util.copy(bindings)
            end
            n.poseVersion=n.poseVersion+1;self.invalidate();return true
        end
        function self.create(id,spec)
            if self.closed then return nil,"scene_closed" end
            assert(type(id)=="string" and #id>0 and #id<=100 and not self.nodes[id],"invalid or duplicate 3D node id")
            assert(#self.order<maxNodes,"3D node budget exceeded")
            spec=spec or {};local nfaces=validateMesh(spec.mesh)
            assert(self.faceCount+nfaces<=maxFaces,"3D mesh face budget exceeded")
            assert(not spec.parent or self.nodes[spec.parent],"missing 3D parent")
            local n={id=id,parent=spec.parent,mesh=spec.mesh,position=copy(spec.position or M.vec()),rotation=copy(spec.rotation or M.vec()),
                scale=copy(spec.scale or M.vec(1,1,1)),visible=spec.visible~=false,pickable=spec.pickable~=false,tag=spec.tag,faceCount=nfaces,
                velocity=spec.velocity and copy(spec.velocity),collider=spec.collider==true,tint={1,1,1,1},poseVersion=1,tintVersion=1}
            nextOrder=nextOrder+1;n.ordinal=nextOrder
            M.transform(n.position,n.rotation,n.scale)
            assert(not n.velocity or M.finite(n.velocity),"invalid 3D velocity")
            self.nodes[id]=n;self.order[#self.order+1]=n;self.faceCount=self.faceCount+nfaces;self.invalidate();return n
        end
        function self.setTransform(id,spec)
            if self.closed then return false end
            local n=assert(self.nodes[id],"unknown 3D node")
            local p,r,s=spec.position or n.position,spec.rotation or n.rotation,spec.scale or n.scale
            assert(M.finite(p) and M.finite(r) and M.finite(s) and s.x>0 and s.y>0 and s.z>0,"invalid 3D transform")
            if same(p,n.position) and same(r,n.rotation) and same(s,n.scale)then return true end
            n.position,n.rotation,n.scale=copy(p),copy(r),copy(s)
            n.poseVersion=n.poseVersion+1
            self.invalidate();return true
        end
        function self.setParent(id,parent)
            if self.closed then return false end
            local n=assert(self.nodes[id],"unknown 3D node")
            local p=parent and assert(self.nodes[parent],"missing 3D parent")
            local depth=0
            while p do assert(p~=n,"3D parent cycle");depth=depth+1;assert(depth<32,"3D hierarchy too deep");p=p.parent and self.nodes[p.parent]end
            if n.parent==parent then return true end
            n.parent=parent;n.poseVersion=n.poseVersion+1;self.invalidate();return true -- local transform is preserved
        end
        function self.setVisible(id,visible)
            if self.closed then return false end
            local n=assert(self.nodes[id],"unknown 3D node")
            if n.visible==(visible==true)then return true end
            n.visible=visible==true;n.poseVersion=n.poseVersion+1;self.invalidate();return true
        end
        function self.setTint(id,color)
            if self.closed then return false end
            for i=1,4 do assert(E.util.finite(color[i]) and color[i]>=0 and color[i]<=1,"invalid 3D tint")end
            local n=self.nodes[id];local old=n.tint
            if old[1]==color[1] and old[2]==color[2] and old[3]==color[3] and old[4]==color[4]then return true end
            n.tint={unpack(color)};n.tintVersion=n.tintVersion+1;self.invalidateShading();return true
        end
        function self.remove(id)
            if self.closed or not self.nodes[id]then return false end
            local removed={[id]=true};local changed=true
            while changed do changed=false;for _,n in ipairs(self.order)do if n.parent and removed[n.parent] and not removed[n.id]then removed[n.id]=true;changed=true end end end
            local keep={}
            for _,n in ipairs(self.order)do if removed[n.id]then
                if self.effects then self.effects.set(n.id,nil)end
                self.nodes[n.id]=nil;self.faceCount=self.faceCount-n.faceCount else keep[#keep+1]=n end end
            self.order=keep;self.invalidate();return true
        end
        function self.clear()
            if self.effects then self.effects.clear()end
            self.nodes={};self.order={};self.faceCount=0;self.invalidate()
        end
        function self.setCamera(spec)
            if self.closed then return false end
            local c={position=copy(spec.position or camera.position),target=copy(spec.target or camera.target),up=copy(spec.up or camera.up),
                fov=spec.fov or camera.fov,near=spec.near or camera.near,far=spec.far or camera.far}
            assert(M.finite(c.position) and M.finite(c.target) and M.finite(c.up),"invalid 3D camera")
            assert(E.util.finite(c.fov) and c.fov>.05 and c.fov<3 and E.util.finite(c.near) and E.util.finite(c.far) and c.near>0 and c.far>c.near,"invalid 3D camera lens")
            assert(M.length(M.cross(M.sub(c.target,c.position),c.up))>1e-8,"degenerate 3D camera")
            if same(c.position,camera.position) and same(c.target,camera.target) and same(c.up,camera.up) and
                c.fov==camera.fov and c.near==camera.near and c.far==camera.far then return true end
            camera=c;cameraVersion=cameraVersion+1;self.invalidate();return true
        end
        function self.getCamera()return E.util.copy(camera)end
        local function viewState()
            if cameraCache and cameraCache.version==cameraVersion then return cameraCache end
            local f=M.unit(M.sub(camera.target,camera.position));local r=M.unit(M.cross(f,camera.up));local u=M.cross(r,f)
            local p=camera.position;local tan=math.tan(camera.fov/2);local aspect=viewport.w/viewport.h;local focal=viewport.h/(2*tan)
            local near,far=camera.near,camera.far
            local cx,cy=viewport.x+viewport.w/2,viewport.y+viewport.h/2
            local planes={}
            local function plane(x,y,z,offset)planes[#planes+1]={x,y,z,-x*p.x-y*p.y-z*p.z+(offset or 0)}end
            plane(f.x,f.y,f.z,-near);plane(-f.x,-f.y,-f.z,far)
            plane(f.x*tan*aspect+r.x,f.y*tan*aspect+r.y,f.z*tan*aspect+r.z)
            plane(f.x*tan*aspect-r.x,f.y*tan*aspect-r.y,f.z*tan*aspect-r.z)
            plane(f.x*tan+u.x,f.y*tan+u.y,f.z*tan+u.z);plane(f.x*tan-u.x,f.y*tan-u.y,f.z*tan-u.z)
            local project=function(x,y,z)
                x,y,z=x-p.x,y-p.y,z-p.z;local depth=x*f.x+y*f.y+z*f.z
                if depth<near or depth>far then return nil end
                return cx+(x*r.x+y*r.y+z*r.z)*focal/depth,cy-(x*u.x+y*u.y+z*u.z)*focal/depth,depth,focal
            end
            cameraCache={version=cameraVersion,r=r,u=u,f=f,tan=tan,aspect=aspect,focal=focal,cx=cx,cy=cy,planes=planes,project=project,
                clip={function(q)return q.z-near end,function(q)return far-q.z end,
                    function(q)return q.z*tan*aspect+q.x end,function(q)return q.z*tan*aspect-q.x end,
                    function(q)return q.z*tan+q.y end,function(q)return q.z*tan-q.y end}}
            return cameraCache
        end
        -- Shared projection closure until camera/viewport changes, including particle batches.
        function self.projector()return viewState().project,viewport end
        function self.setViewport(v)
            assert(E.util.finite(v.x) and E.util.finite(v.y) and E.util.finite(v.w) and E.util.finite(v.h) and v.w>0 and v.h>0,"invalid 3D viewport")
            if v.x==viewport.x and v.y==viewport.y and v.w==viewport.w and v.h==viewport.h then return end
            viewport={x=v.x,y=v.y,w=v.w,h=v.h};cameraVersion=cameraVersion+1;self.invalidate()
        end
        function self.getViewport()return E.util.copy(viewport)end
        function self.orbit(yaw,pitch,distance,target)
            assert(E.util.finite(yaw) and E.util.finite(pitch) and E.util.finite(distance) and distance>0,"invalid camera orbit")
            target=target or camera.target;pitch=E.util.clamp(pitch,-1.5,1.5)
            self.setCamera({target=target,position=M.add(target,M.vec(math.sin(yaw)*math.cos(pitch)*distance,math.sin(pitch)*distance,math.cos(yaw)*math.cos(pitch)*distance))})
        end
        local function basis()
            local v=viewState();return v.r,v.u,v.f
        end
        function self.project(point)
            local x,y,z=viewState().project(point.x,point.y,point.z);return x,y,z
        end
        function self.screenRay(x,y)
            assert(E.util.finite(x) and E.util.finite(y),"invalid 3D pointer")
            local r,u,f=basis();local focal=viewport.h/(2*math.tan(camera.fov/2))
            return copy(camera.position),M.unit(M.add(f,M.add(M.mul(r,(x-viewport.x-viewport.w/2)/focal),M.mul(u,-(y-viewport.y-viewport.h/2)/focal))))
        end
        local function sync()
            if synced==self.revision then return end
            transformedNodes=0
            local visiting={}
            local function update(n,depth)
                if n.synced==self.revision then return end
                assert(depth<=32 and not visiting[n.id],"invalid 3D hierarchy")
                visiting[n.id]=true
                local p=n.parent and assert(self.nodes[n.parent],"missing 3D parent")
                if p then update(p,depth+1)end
                local parentVersion=p and p.worldVersion or 0
                if n.cachedPose~=n.poseVersion or n.cachedParent~=parentVersion then
                    local localMatrix=M.transform(n.position,n.rotation,n.scale)
                    n.matrix=p and M.compose(p.matrix,localMatrix) or localMatrix;n.worldVisible=n.visible and (not p or p.worldVisible)
                    n.vertices=n.vertices or {};local m=n.matrix
                    if n.mesh then
                        for i,v in ipairs(n.mesh.vertices)do
                            local w=n.vertices[i] or {};n.vertices[i]=w
                            w.x=m[1]*v.x+m[2]*v.y+m[3]*v.z+m[4];w.y=m[5]*v.x+m[6]*v.y+m[7]*v.z+m[8];w.z=m[9]*v.x+m[10]*v.y+m[11]*v.z+m[12]
                        end
                        n.bounds=bounds(n.vertices);n.normals=n.normals or {}
                        for i,face in ipairs(n.mesh.faces)do
                            local a,b,c=n.vertices[face[1]],n.vertices[face[2]],n.vertices[face[3]]
                            n.normals[i]=M.unit(M.cross(M.sub(b,a),M.sub(c,a)))
                        end
                    end
                    worldVersion=worldVersion+1;n.worldVersion=worldVersion;n.cachedPose=n.poseVersion;n.cachedParent=parentVersion
                    transformedNodes=transformedNodes+1
                end
                n.synced=self.revision;visiting[n.id]=nil
            end
            for _,n in ipairs(self.order)do update(n,1)end;synced=self.revision
        end
        function self.worldPoint(id,point)sync();return M.point(assert(self.nodes[id],"unknown 3D node").matrix,point)end
        function self.raycast(origin,direction,limit)
            assert(M.finite(origin) and M.finite(direction) and M.length(direction)>1e-9,"invalid 3D ray")
            sync();direction=M.unit(direction);local hit,best=nil,limit or math.huge
            for _,n in ipairs(self.order)do
                if n.worldVisible and n.pickable and n.mesh and M.rayBox(origin,direction,n.bounds,best)then
                    for fi,f in ipairs(n.mesh.faces)do
                        local a,b,c=n.vertices[f[1]],n.vertices[f[2]],n.vertices[f[3]]
                        local normal=M.unit(M.cross(M.sub(b,a),M.sub(c,a)))
                        if f.doubleSided or M.dot(normal,direction)<0 then
                            for i=2,#f-1 do
                                local t=M.rayTriangle(origin,direction,a,n.vertices[f[i]],n.vertices[f[i+1]])
                                if t and t<best then best=t;hit={id=n.id,tag=n.tag,face=fi,faceTag=f.tag,distance=t,normal=normal,point=M.add(origin,M.mul(direction,t))}end
                            end
                        end
                    end
                end
            end
            return hit
        end
        function self.pick(x,y)
            if x<viewport.x or x>viewport.x+viewport.w or y<viewport.y or y>viewport.y+viewport.h then return nil end
            local o,d=self.screenRay(x,y);local _,_,f=basis();local k=M.dot(d,f)
            local start=M.add(o,M.mul(d,camera.near/k))
            local h=self.raycast(start,d,(camera.far-camera.near)/k)
            if h then h.distance=h.distance+camera.near/k end;return h
        end
        function self.queryAABB(box)
            assert(M.finite(box.min) and M.finite(box.max),"invalid 3D bounds")
            sync();local out={};for _,n in ipairs(self.order)do if n.collider and n.bounds and M.overlap(box,n.bounds)then out[#out+1]=n.id end end;return out
        end
        function self.sweepAABB(box,delta,ignoreId)
            assert(M.finite(box.min) and M.finite(box.max) and M.finite(delta),"invalid 3D sweep")
            sync();local best,hit=1,nil
            for _,n in ipairs(self.order)do if n.id~=ignoreId and n.collider and n.bounds then
                local t,normal=M.sweepBox(box,delta,n.bounds)
                if t and t<=best then best=t;hit={id=n.id,time=t,normal=normal}end
            end end;return hit
        end
        -- Kinematic integration. Collision response is a game/controller decision.
        function self.step(dt)
            if self.closed then return end
            assert(E.util.finite(dt) and dt>=0 and dt<=.25,"invalid 3D timestep")
            local changed=false
            for _,n in ipairs(self.order)do local v=n.velocity
                if dt>0 and v and (v.x~=0 or v.y~=0 or v.z~=0)then
                    local p=n.position;p.x,p.y,p.z=p.x+v.x*dt,p.y+v.y*dt,p.z+v.z*dt;n.poseVersion=n.poseVersion+1;changed=true
                end
            end
            if self.effects then self.effects.update(dt)end
            if changed then self.invalidate()end
        end
        function self.setVelocity(id,velocity)
            local n=assert(self.nodes[id],"unknown 3D node")
            assert(velocity==nil or M.finite(velocity),"invalid 3D velocity");n.velocity=velocity and copy(velocity)
        end
        local function clip(poly,plane)
            local out={};if #poly==0 then return out end
            local a=poly[#poly];local da=plane(a)
            for _,b in ipairs(poly)do
                local db=plane(b)
                if (da>=0)~=(db>=0)then out[#out+1]=M.add(a,M.mul(M.sub(b,a),da/(da-db)))end
                if db>=0 then out[#out+1]=b end
                a,da=b,db
            end
            return out
        end
        local function inFrustum(box,planes)
            -- Conservative AABB/plane test. Use the positive vertex so objects
            -- crossing the near plane or viewport edge still take exact clipping.
            for _,p in ipairs(planes)do
                local x=p[1]>=0 and box.max.x or box.min.x
                local y=p[2]>=0 and box.max.y or box.min.y
                local z=p[3]>=0 and box.max.z or box.min.z
                if p[1]*x+p[2]*y+p[3]*z+p[4]<-1e-8 then return false end
            end
            return true
        end
        local light=M.unit(M.vec(-.4,.8,1));local shadeRevision=-1
        local function recolor()
            local fogRevision=self.effects and self.effects.fogRevision or 0
            for _,n in ipairs(self.order)do if n.renderVisible and (n.drawColorsDirty or n.colorTint~=n.tintVersion or
                n.colorEffect~=n.effectRevision or n.colorFog~=fogRevision)then
                local coefficients={}
                for _,f in ipairs(n.drawFaces)do
                    local index=f.sourceFace;local c=coefficients[index]
                    if not c then
                        local source=n.mesh.faces[index];local normal=n.normals[index]
                        local diffuse=source.unlit and 1 or (.48+.52*math.max(0,M.dot(normal,light)))
                        c=self.effects and self.effects.coefficients(n,index,normal,camera.position,f.depth) or {0,0,0,0,0,0,0}
                        c.diffuse=diffuse;coefficients[index]=c
                    end
                    for j=1,3 do
                        local value=E.util.clamp((f.baseColor[j]*c.diffuse+c[j])*n.tint[j],0,1)
                        f.color[j]=value+(c[j+4]-value)*c[4]
                    end
                    f.color[4]=f.baseColor[4]*n.tint[4];f.colorRevision=self.shadingRevision
                end
                n.drawColorsDirty=false;n.colorTint=n.tintVersion;n.colorEffect=n.effectRevision;n.colorFog=fogRevision
            end end
            shadeRevision=self.shadingRevision
        end
        function self.renderList()
            if self.closed then return {} end
            projectedNodes,paintedVertices,projectedVertices=0,0,0
            if drawRevision==self.revision then if shadeRevision~=self.shadingRevision then recolor()end;return drawCache end
            sync();local view=viewState();local r,u,forward=view.r,view.u,view.f;local tan,aspect=view.tan,view.aspect
            local focal=view.focal;local out={};culledNodes=0
            local cx,cy=view.cx,view.cy;local planes=view.clip
            for _,n in ipairs(self.order)do
                n.renderVisible=n.worldVisible and n.mesh and inFrustum(n.bounds,view.planes)
                if n.worldVisible and n.mesh and not n.renderVisible then culledNodes=culledNodes+1 end
                if n.renderVisible then
                local displayMesh=n.paintMesh or n.mesh
                if n.paintMesh and n.paintWorld~=n.worldVersion then
                    local m=n.matrix;n.paintVertices=n.paintVertices or {}
                    for i,v in ipairs(n.paintMesh.vertices)do
                        local w=n.paintVertices[i] or {};n.paintVertices[i]=w
                        w.x=m[1]*v.x+m[2]*v.y+m[3]*v.z+m[4];w.y=m[5]*v.x+m[6]*v.y+m[7]*v.z+m[8];w.z=m[9]*v.x+m[10]*v.y+m[11]*v.z+m[12]
                    end
                    for i=#n.paintVertices,#n.paintMesh.vertices+1,-1 do n.paintVertices[i]=nil end
                    n.paintWorld=n.worldVersion;paintedVertices=paintedVertices+#n.paintMesh.vertices
                end
                local displayVertices=n.paintMesh and n.paintVertices or n.vertices
                if n.drawWorld~=n.worldVersion or n.drawCamera~=cameraVersion then
                    projectedNodes=projectedNodes+1;n.projected=n.projected or {};local faces={}
                    projectedVertices=projectedVertices+#displayVertices
                    local cv=n.projected;local cp=camera.position
                    for i,v in ipairs(displayVertices)do
                        local x,y,z=v.x-cp.x,v.y-cp.y,v.z-cp.z;local q=cv[i] or {};cv[i]=q
                        q.x=x*r.x+y*r.y+z*r.z;q.y=x*u.x+y*u.y+z*u.z;q.z=x*forward.x+y*forward.y+z*forward.z
                        q.inside=q.z>=camera.near and q.z<=camera.far and math.abs(q.x)<=q.z*tan*aspect and math.abs(q.y)<=q.z*tan
                        if q.inside then q.screen=q.screen or {};q.screen.x=cx+q.x*focal/q.z;q.screen.y=cy-q.y*focal/q.z end
                    end
                    local surfaceDepths={}
                    -- Coplanar body/rim/pixel layers share one surface depth. Their
                    -- source order then keeps the entire image above its backing.
                    for sourceIndex,source in ipairs(n.mesh.faces)do
                        local group=source.surfaceGroup or (n.paintMesh and ("pixel:"..sourceIndex))
                        if group and not surfaceDepths[group]then
                        local depth=0
                        for _,i in ipairs(source)do local v=n.vertices[i];depth=depth+(v.x-cp.x)*forward.x+(v.y-cp.y)*forward.y+(v.z-cp.z)*forward.z end
                        surfaceDepths[group]=depth/#source
                    end end
                    for fi,face in ipairs(displayMesh.faces)do
                        local source=n.mesh.faces[face.sourceFace or fi]
                        local surfaceGroup=source.surfaceGroup or (n.paintMesh and ("pixel:"..(face.sourceFace or fi)))
                        local a=displayVertices[face[1]];local normal=n.normals[face.sourceFace or fi]
                        if source.doubleSided or normal.x*(cp.x-a.x)+normal.y*(cp.y-a.y)+normal.z*(cp.z-a.z)>1e-9 then
                            local inside=true;for _,i in ipairs(face)do if not cv[i].inside then inside=false;break end end
                            local points,depth={},0
                            if inside then
                                -- The common path allocates no clip polygons and reuses projected vertices.
                                for _,i in ipairs(face)do points[#points+1]=cv[i].screen;depth=depth+cv[i].z end
                            else
                                local poly={};for _,i in ipairs(face)do poly[#poly+1]=cv[i]end
                                for _,plane in ipairs(planes)do poly=clip(poly,plane);if #poly<3 then break end end
                                if #poly>=3 then for _,v in ipairs(poly)do points[#points+1]={x=cx+v.x*focal/v.z,y=cy-v.y*focal/v.z};depth=depth+v.z end end
                            end
                            if #points>=3 then
                                faces[#faces+1]={points=points,depth=surfaceGroup and surfaceDepths[surfaceGroup] or depth/#points,
                                    surfaceGroup=surfaceGroup,sourceFace=face.sourceFace or fi,order=n.ordinal*4096+fi,id=n.id,face=fi,key="g:"..n.id..":"..fi,
                                    baseColor=face.color or {1,1,1,1},color={}}
                            end
                        end
                    end
                    n.drawFaces=faces;n.drawWorld=n.worldVersion;n.drawCamera=cameraVersion;n.drawColorsDirty=true
                end
                for _,f in ipairs(n.drawFaces)do out[#out+1]=f end
            end end
            table.sort(out,function(a,b)if math.abs(a.depth-b.depth)<1e-8 then return a.order<b.order end;return a.depth>b.depth end)
            drawCache,drawRevision=out,self.revision;recolor();return out
        end
        function self.stats()return {scene3DNodes=#self.order,scene3DFaces=self.faceCount,scene3DVisibleFaces=#drawCache,scene3DTransformedNodes=transformedNodes,
            scene3DProjectedNodes=projectedNodes,scene3DCulledNodes=culledNodes,scene3DPaintedVertices=paintedVertices,scene3DProjectedVertices=projectedVertices}end
        function self.dispose()self.clear();self.closed=true;drawCache={}end
        if E.newSurfaceEffects3D then self.effects=E.newSurfaceEffects3D(self)end
        return self
    end
end
