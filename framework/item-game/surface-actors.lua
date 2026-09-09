-- One camera per surface layer, with real actors sharing the depth buffer.
-- UI coordinates and footprint limits belong to the caller, never to grid cells.
return function(E,G)
    local pcall,error=G.pcall,G.error
    local function call(object,method,...)
        if object and object[method] then return pcall(object[method],object,...)end
        return false
    end
    local function resourceKey(def)return def.kind..":"..def.id..":"..(def.displayIndex or 1)end
    function E.newSurfaceActors(session,root,cache,layer)
        cache.actorScenes=cache.actorScenes or {}
        cache.actorResources=cache.actorResources or {}
        local groups,resources=cache.actorScenes,cache.actorResources
        local generation,queue,queued=0,{},{}
        local width,height=session.content.viewport.width,session.content.viewport.height
        -- Keep native model coordinates near the origin with a normal UI lens.
        local unitsPerPixel,fov=.01,.55
        local cameraDistance=height*unitsPerPixel/(2*math.tan(fov/2))
        local limit=(session.content.limits or {}).maxSurfaceModels or 104
        local self={}
        local function group(z)
            if session.host.now()<(self.nextSceneAttempt or 0)then return nil end
            if not groups[z] then
                local ok,f=pcall(G.CreateFrame,"ModelScene",nil,layer(z))
                if not ok then
                    self.nextSceneAttempt=session.host.now()+1
                    if not self.unavailable then session.perf.note("surface.scene_unavailable",{reason=tostring(f)})end
                    self.unavailable=true
                    return nil
                end
                self.unavailable=false
                f:SetAllPoints(root);f:EnableMouse(false)
                call(f,"SetFixedFrameLevel",true);f:SetFrameLevel(layer(z):GetFrameLevel()+1)
                -- Use the same camera setup as Blizzard's OrbitCameraMixin.
                f:SetCameraOrientationByYawPitchRoll(0,0,0)
                f:SetCameraFieldOfView(fov)
                f:SetCameraPosition(-cameraDistance,0,0)
                call(f,"SetCameraNearClip",.01);call(f,"SetCameraFarClip",1000)
                call(f,"ClearFog");call(f,"SetAllowOverlappedModels",true)
                call(f,"SetLightVisible",true);call(f,"SetLightAmbientColor",.75,.75,.75)
                call(f,"SetLightDiffuseColor",.25,.25,.25);call(f,"SetLightDirection",-1,-1,-1)
                groups[z]={frame=f,actors={},z=z}
            end
            local g=groups[z];g.frame:Show();call(g.frame,"SetPaused",false,false)
            return g
        end
        local function resource(def)
            local key=resourceKey(def)
            local r=resources[key]
            if not r then r={key=key};resources[key]=r end
            if not r.id and session.host.now()>=(r.nextResolve or 0)then
                r.kind,r.id=E.resolveModel(def);r.nextResolve=session.host.now()+.1
            end
            return r
        end
        local function release(a,clear)
            if a.owner then a.owner.actorLease=nil;a.owner.model=nil;a.owner.loaded=false;a.owner.fitReady=false end
            a.owner=nil;a.actor:Hide();a.visible=false
            if clear then
                call(a.actor,"ClearModel");a.key=nil;a.requested=false;a.ready=false;a.notified=nil
                a.nextLoadAttempt=nil
                a.measureAfter=nil
                a.anim=nil;a.animOffset=nil;a.animSpeed=nil
            end
        end
        local function take(g,node,key)
            if not node then
                for _,a in ipairs(g.actors)do if a.key==key and a.ready then return a end end
            end
            if node and node.actorLease and node.actorLease.key==key then return node.actorLease end
            if node and node.actorLease then release(node.actorLease,false)end
            local chosen
            for _,a in ipairs(g.actors)do
                if not a.owner and a.key==key then chosen=a;break end
            end
            if not chosen then
                for _,a in ipairs(g.actors)do if not a.owner and not a.key then chosen=a;break end end
            end
            if not chosen and (cache.modelCount or 0)<limit then
                cache.modelCount=(cache.modelCount or 0)+1
                chosen={actor=g.frame:CreateActor("IGSharedActor"..cache.modelCount)}
                call(chosen.actor,"SetUseCenterForOrigin",false,false,false)
                g.actors[#g.actors+1]=chosen
            end
            if not chosen then
                for _,a in ipairs(g.actors)do
                    if not a.owner and (not chosen or (a.usedAt or 0)<(chosen.usedAt or 0))then chosen=a end
                end
            end
            if not chosen then return nil end
            if chosen.key~=key then release(chosen,true);chosen.key=key;chosen.started=session.host.now()end
            chosen.owner=node;chosen.usedAt=session.host.now()
            if node then node.actorLease=chosen;node.model=chosen.actor;node.scene=g.frame;node.sharedScene=true end
            return chosen
        end
        local function load(a,r)
            if a.ready then return true end
            local actor=a.actor
            -- Keep identity-size geometry updating while its bounds initialize.
            -- A sub-pixel probe may never produce active geometry on the client.
            actor:Show();call(actor,"SetAlpha",.01);call(actor,"SetScale",1)
            call(actor,"SetPosition",0,0,0)
            if r.id and not a.requested and session.host.now()>=(a.nextLoadAttempt or 0)then
                a.requested=true;a.nextLoadAttempt=session.host.now()+.25
                local ok,accepted=call(actor,r.kind=="creatureDisplayID" and "SetModelByCreatureDisplayID" or "SetModelByFileID",r.id)
                if not ok or accepted==false then a.requested=false end
            end
            if not a.requested then return false end
            local ok,loaded=call(actor,"IsLoaded")
            if not ok then local valid,id=call(actor,"GetModelFileID");loaded=valid and type(id)=="number" and id>0 end
            if not loaded then return false end
            -- Retail can report IsGeoReady()==false while IsLoaded() and both
            -- native bounding boxes are valid. Gating on it strands every actor
            -- at probe alpha and prevents the first visible render. Blizzard's
            -- ModelSceneActorMixin uses IsLoaded() + usable bounds instead.
            if not r.bounds then
                if not a.measureAfter then
                    call(actor,"SetScale",1);call(actor,"SetYaw",0);call(actor,"SetPosition",0,0,0)
                    call(actor,"SetPitch",0);call(actor,"SetRoll",0)
                    call(actor,"SetUseCenterForOrigin",false,false,false);call(actor,"SetAnimation",0,0,0,0)
                    a.measureAfter=session.host.now()
                    return false -- let the native geometry commit the identity transform
                end
                if session.host.now()<=a.measureAfter then return false end
                -- Measure a frozen idle pose. The maximum box can include death,
                -- spell and other animation extents far outside the standing body.
                local bottom,top=E.readModelBounds(actor,"GetActiveBoundingBox")
                local fit=E.fitModelBounds(bottom,top,1,0,.82)
                local source="idle"
                if not fit and session.host.now()-a.measureAfter>=.5 then
                    bottom,top=E.readModelBounds(actor,"GetMaxBoundingBox")
                    fit=E.fitModelBounds(bottom,top,1,0,.82);source="maximum"
                end
                if fit then r.bounds={fit.bottom,fit.top};r.boundsSource=source end
            end
            a.ready=r.bounds~=nil
            if a.ready then
                session.perf.note("surface.model_ready",{resource=r.key,seconds=session.host.now()-(a.started or session.host.now())})
            end
            return a.ready
        end
        local function animate(a)
            local spec,def=a.spec,a.def
            local animation=spec.animation or def.animation or 0
            if spec.animationTime~=nil then
                local offset=spec.animationTime
                if not session.paused and not spec.paused then offset=offset+math.max(0,session.time-a.sampleAt)*(spec.animationRate or 1)end
                offset=math.min(spec.animationEnd or 100000,offset)
                if a.anim~=animation or a.animOffset~=offset then
                    call(a.actor,"SetAnimation",animation,0,0,offset);a.anim=animation;a.animOffset=offset
                end
            else
                local speed=(session.paused or spec.paused)and 0 or session.speed
                if a.anim~=animation or a.animSpeed~=speed or a.animOffset then
                    call(a.actor,"SetAnimation",animation,0,speed,0);a.anim=animation;a.animSpeed=speed;a.animOffset=nil
                end
            end
        end
        local function projectionPlane(g,x)
            -- Calibrate against the native projection. Do not assume its Y sign,
            -- FOV aspect convention, or physical-pixel/UI-scale relationship.
            local ok,u,v=call(g.frame,"Project3DPointTo2D",x,0,0)
            local yOK,yu,yv=call(g.frame,"Project3DPointTo2D",x,1,0)
            local zOK,zu,zv=call(g.frame,"Project3DPointTo2D",x,0,1)
            local scaleOK,uiScale=call(g.frame,"GetEffectiveScale")
            if not(ok and yOK and zOK and scaleOK)then return nil end
            for _,value in ipairs({u,v,yu,yv,zu,zv,uiScale})do if not E.util.finite(value)then return nil end end
            if not u or not v or not yu or not yv or not zu or not zv or not uiScale or uiScale<=0 then return nil end
            local a,b,c,d=yu-u,zu-u,yv-v,zv-v
            local determinant=a*d-b*c
            if math.abs(determinant)<.000001 then return nil end
            return {x=x,u=u,v=v,a=a,b=b,c=c,d=d,det=determinant,uiScale=uiScale,
                pixelWidth=uiScale/math.sqrt(a*a+c*c),pixelHeight=uiScale/math.sqrt(b*b+d*d)}
        end
        local function pointOnPlane(p,x,y)
            local du,dv=x*p.uiScale-p.u,(height-y)*p.uiScale-p.v
            return (du*p.d-dv*p.b)/p.det,(p.a*dv-p.c*du)/p.det
        end
        local function actorSize(a,p)
            local s,fit=a.spec,a.fit
            return math.min((s.w or 1)*p.pixelWidth/fit.width,(s.h or 1)*p.pixelHeight/fit.height)*a.fill*a.sizeScale
        end
        local function projectedSize(a,g,x,y,z,scale)
            local b,t=a.resource.bounds[1],a.resource.bounds[2]
            local pivot=a.pivot
            local c,s=math.cos(a.yaw),math.sin(a.yaw)
            local left,right,bottom,top
            for _,px in ipairs({b.x,t.x})do for _,py in ipairs({b.y,t.y})do for _,pz in ipairs({b.z,t.z})do
                local dx,dy=px-pivot.x,py-pivot.y
                local ok,u,v=call(g.frame,"Project3DPointTo2D",x+(dx*c-dy*s)*scale,
                    y+(dx*s+dy*c)*scale,z+(pz-pivot.z)*scale)
                if not ok or not E.util.finite(u) or not E.util.finite(v)then return nil end
                left=left and math.min(left,u)or u;right=right and math.max(right,u)or u
                bottom=bottom and math.min(bottom,v)or v;top=top and math.max(top,v)or v
            end end end
            return right-left,top-bottom
        end
        local function facing(a,p)
            local direction=a.spec.screenFacing or a.def.screenFacing
            if direction then
                local side=direction=="right" and 1 or -1
                return side*(p.a>0 and 1 or -1)*math.pi/2-(a.def.forwardYaw or 0)
            end
            return a.spec.facing or a.def.facing or 0
        end
        local function pendingProjection(g,visible)
            for _,a in ipairs(visible)do a.actor:Hide();a.visible=false;a.owner.fitReady=false end
            g.dirty=true
            if not g.projectionNotice then
                session.perf.note("surface.projection_pending",{layer=g.z});g.projectionNotice=true
            end
        end
        local function layout(g)
            local visible={}
            for _,a in ipairs(g.actors)do
                if a.owner and a.generation==generation and a.ready then visible[#visible+1]=a end
            end
            -- Frontmost feet first. Actors with the same foot depth share a band;
            -- packing 98 separate bands needlessly inflates coordinates/scales.
            table.sort(visible,function(a,b)
                if a.owner.depth==b.owner.depth then return a.owner.order>b.owner.order end
                return a.owner.depth>b.owner.depth
            end)
            if #visible==0 then g.dirty=false;return end
            local headingPlane=projectionPlane(g,0)
            if not headingPlane then pendingProjection(g,visible);return end
            local cursor,index,retry=0,1,false
            while index<=#visible do
                local last=index
                while last<=#visible and visible[last].owner.depth==visible[index].owner.depth do
                    local a=visible[last];local s,def=a.spec,a.def
                    a.yaw=facing(a,headingPlane)
                    a.fit=E.fitModelBounds(a.resource.bounds[1],a.resource.bounds[2],(s.w or 1)/(s.h or 1),a.yaw,def.fitFill or .82)
                    local b,t=a.resource.bounds[1],a.resource.bounds[2]
                    a.pivot=s.modelAnchor or def.modelAnchor or {x=(b.x+t.x)/2,y=(b.y+t.y)/2,z=b.z}
                    a.sizeScale=s.scale or def.scale or 1;a.fill=s.fitFill or def.fitFill or .82
                    if not E.util.finite(a.sizeScale) or a.sizeScale<=0 or
                        not E.util.finite(a.fill) or a.fill<=0 or a.fill>1 then error("invalid surface model size")end
                    for _,key in ipairs({"x","y","z"})do
                        if not E.util.finite(a.pivot[key])then error("invalid surface model anchor")end
                    end
                    local c,sine=math.cos(a.yaw),math.sin(a.yaw)
                    local centerOffset=((b.x+t.x)/2-a.pivot.x)*c-((b.y+t.y)/2-a.pivot.y)*sine
                    a.depthExtent=a.fit and a.fit.depth+2*math.abs(centerOffset)or 0
                    last=last+1
                end
                -- Solve the band extent in native scene units. A few bounded
                -- iterations account for perspective as the band moves away.
                local center,plane,depth=cursor,nil,0
                for _=1,5 do
                    plane=projectionPlane(g,center)
                    if not plane then
                        pendingProjection(g,visible)
                        return
                    end
                    depth=0
                    for i=index,last-1 do
                        local a=visible[i]
                        if a.fit then depth=math.max(depth,a.depthExtent*actorSize(a,plane))end
                    end
                    local nextCenter=cursor+depth/2
                    if math.abs(nextCenter-center)<.00001 then break end
                    center=nextCenter
                end
                -- The final plane is authoritative for both placement and size.
                center=plane.x
                cursor=center+depth/2+.02
                for i=index,last-1 do
                    local a=visible[i];local n,s,def,fit=a.owner,a.spec,a.def,a.fit
                    if fit then
                        local scale=actorSize(a,plane)
                        local anchorX=s.anchorX or (s.x or 0)+(s.w or 1)/2
                        local anchorY=s.anchorY or (s.y or 0)+(s.h or 1)*.9
                        if not E.util.finite(anchorX) or not E.util.finite(anchorY)then error("invalid surface screen anchor")end
                        local worldY,worldZ=pointOnPlane(plane,anchorX,anchorY)
                        -- Enforce the final screen footprint, including the
                        -- perspective of the near corners of deep/long models.
                        local projectionReady=false
                        for _=1,6 do
                            local projectedW,projectedH=projectedSize(a,g,center,worldY,worldZ,scale)
                            if not projectedW or not projectedH or projectedW<=0 or projectedH<=0 then break end
                            local ratio=math.min((s.w or 1)*plane.uiScale*a.fill*a.sizeScale/projectedW,
                                (s.h or 1)*plane.uiScale*a.fill*a.sizeScale/projectedH)
                            if ratio>=1 and ratio<=1.005 then projectionReady=true;break end
                            scale=scale*ratio*.998
                        end
                        if projectionReady then
                            local c,sine=math.cos(a.yaw),math.sin(a.yaw)
                            local pivot=a.pivot
                            local scaleOK=call(a.actor,"SetScale",scale)
                            local yawOK=call(a.actor,"SetYaw",a.yaw)
                            -- Actor positions are in pre-scale model space.
                            local positionOK=call(a.actor,"SetPosition",center/scale-(pivot.x*c-pivot.y*sine),
                                worldY/scale-(pivot.x*sine+pivot.y*c),worldZ/scale-pivot.z)
                            projectionReady=scaleOK and yawOK and positionOK
                        end
                        if projectionReady then
                            call(a.actor,"SetAlpha",1);a.actor:Show();a.visible=true
                            n.loaded=true;n.fitReady=true;n.bounds=a.resource.bounds;n.framing=fit
                            n.sceneDepth={near=center-depth/2,far=center+depth/2}
                            n.projectedAnchor={x=anchorX,y=anchorY};n.modelAnchor=pivot
                            n.boundsSource=a.resource.boundsSource
                            animate(a)
                        else
                            -- A clipped/unready actor must not hide the rest of the lawn.
                            pendingProjection(g,{a});retry=true
                        end
                    end
                end
                index=last
            end
            call(g.frame,"SetCameraFarClip",cameraDistance+cursor+10)
            g.dirty=retry
        end
        function self.begin()generation=generation+1 end
        function self.draw(node,spec,def)
            if not def then error("unknown surface model: "..tostring(spec.asset))end
            for _,key in ipairs({"w","h"})do
                if not E.util.finite(spec[key] or 1) or (spec[key] or 1)<=0 then error("invalid surface model dimensions")end
            end
            node.sharedScene=true
            node.fallback:Hide()
            local g=group(node.z);if not g then return end
            local r=resource(def);local a=take(g,node,r.key)
            if not a then return end
            a.spec=spec;a.def=def;a.resource=r;a.generation=generation;a.sampleAt=session.time
            g.dirty=true
            node.asset=spec.asset;node.loaded=a.ready or false
            load(a,r)
        end
        function self.preload(asset,z)
            local def=(session.content.assets.models or {})[asset]
            if not def or queued[resourceKey(def)] or #queue>=32 then return false end
            queued[resourceKey(def)]=true;queue[#queue+1]={asset=asset,def=def,z=z or 4};return true
        end
        function self.finish()
            for _,g in pairs(groups)do
                for _,a in ipairs(g.actors)do if a.owner and a.generation~=generation then release(a,false)end end
                layout(g)
            end
        end
        function self.update()
            local now=session.host.now()
            for _,g in pairs(groups)do
                -- Native UI scale/size can change without a game redraw, e.g.
                -- while paused. Invalidate the calibrated layout in that case.
                local _,effectiveScale=call(g.frame,"GetEffectiveScale")
                local signature=tostring(effectiveScale)..":"..g.frame:GetWidth()..":"..g.frame:GetHeight()
                if g.viewportSignature~=signature then g.viewportSignature=signature;g.dirty=true end
                for _,a in ipairs(g.actors)do
                    if a.owner then
                        if not a.ready then
                            local wasReady=a.ready
                            load(a,resource(a.def))
                            if a.ready~=wasReady then g.dirty=true end
                            if not a.ready and now-(a.started or now)>8 and not a.notified then
                                a.notified=true;session.perf.note("surface.model_unavailable",{resource=a.key})
                            end
                        end
                        if a.ready then animate(a)end
                    elseif a.key and now-(a.usedAt or 0)>120 then release(a,true)end
                end
                if g.dirty then layout(g)end
                local level=layer(g.z):GetFrameLevel()+1
                if g.frame:GetFrameLevel()~=level then g.frame:SetFrameLevel(level)end
            end
            -- Independent resources load in parallel; no three-second queue barrier.
            local count=0
            for i=#queue,1,-1 do
                if count>=4 then break end
                local request=queue[i];local r=resource(request.def);local g=group(request.z)
                if not g then break end
                local a=take(g,nil,r.key)
                if a then
                    count=count+1
                    if load(a,r) or now-(a.started or now)>8 then
                        if not a.owner then a.actor:Hide()end
                        table.remove(queue,i)
                    end
                end
            end
        end
        function self.dispose()
            for _,g in pairs(groups)do
                for _,a in ipairs(g.actors)do release(a,true);a.notified=nil end
                g.frame:Hide();call(g.frame,"SetPaused",true,false)
            end
        end
        return self
    end
end
