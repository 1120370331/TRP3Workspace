-- WoW adapter for the independent scene3d core. Colored convex faces are projected
-- into native Texture quads; the CPU owns projection and ordering, WoW draws them.
return function(E,G)
    function E.newWoWScene3D(session,parent,options,cache)
        options=options or {};cache=cache or {pool={}}
        local width,height=session.content.viewport.width,session.content.viewport.height
        local limits=session.content.limits or {}
        local scene=E.newScene3D({width=width,height=height,maxNodes=limits.maxScene3DNodes or 512,maxFaces=limits.maxScene3DFaces or 4096})
        if E.newParticles3D then scene.particles=E.newParticles3D(scene,session.content.particles3d,limits) end
        if options.viewport then scene.setViewport(options.viewport)end
        local root=cache.root
        if not root then root=G.CreateFrame("Frame",nil,parent);cache.root=root end
        root:ClearAllPoints();root:SetPoint("TOPLEFT",parent,"TOPLEFT",0,0);root:SetSize(width,height)
        root:SetFrameLevel(parent:GetFrameLevel()+100);root:EnableMouse(false);root:Show()
        local input=cache.input
        if not input then input=G.CreateFrame("Frame",nil,root);cache.input=input end
        input:EnableMouse(true)
        if input.EnableMouseWheel then input:EnableMouseWheel(true)end
        input:SetFrameLevel(root:GetFrameLevel()+4097)
        local callback,drag,lastRevision,lastScale,lastParticleRevision=nil,nil,-1,nil,-1
        local lastShadingRevision=-1
        local drawn,dropped,batchCount=0,0,0
        local selfViewportX,selfViewportY,selfViewportW,selfViewportH
        local byKey,free,commands={},{},{}
        cache.frames=cache.frames or {}
        local batches,freeFrames={},{}
        for _,h in ipairs(cache.pool)do h.texture:Hide();h.visible=false;free[#free+1]=h end
        for _,b in ipairs(cache.frames)do b.frame:Hide();b.visible=false;freeFrames[#freeFrames+1]=b end
        local defaultUV={0,1,0,1}
        local function point()
            if not G.GetCursorPosition or not root.GetLeft or not root.GetTop then return nil end
            local left,top=root:GetLeft(),root:GetTop();if not left or not top then return nil end
            local x,y=G.GetCursorPosition();local scale=root:GetEffectiveScale()
            return x/scale-left,top-y/scale
        end
        local function send(event)
            if callback and not session.stopping and not session.paused and not scene.closed then session.safe("scene3d.pointer",callback,event)end
        end
        local function release(x,y,cancelled)
            if not drag then return end
            local old=drag;drag=nil
            send({phase=cancelled and "cancel" or "up",x=x or old.x,y=y or old.y,button=old.button})
        end
        input:SetScript("OnMouseDown",function(_,button)
            if session.paused or session.stopping then return end
            local x,y=point();if not x then return end
            drag={button=button,x=x,y=y};send({phase="down",x=x,y=y,button=button})
        end)
        input:SetScript("OnMouseUp",function(_,button)
            if drag and drag.button==button then local x,y=point();release(x,y)end
        end)
        input:SetScript("OnMouseWheel",function(_,delta)
            local x,y=point();if x then send({phase="wheel",x=x,y=y,delta=delta})end
        end)
        input:SetScript("OnHide",function()release(nil,nil,true)end)
        scene.inputFrame=input;scene.cache=cache
        function scene.onPointer(fn)assert(fn==nil or type(fn)=="function","invalid 3D input callback");callback=fn end
        function scene.cancelPointer()drag=nil end
        local function batch(key,level)
            local b=batches[key]
            if not b then
                b=table.remove(freeFrames)
                if not b then
                    assert(#cache.frames<4096,"3D batch frame budget exceeded")
                    local frame=G.CreateFrame("Frame",nil,root);frame:EnableMouse(false)
                    frame:SetPoint("TOPLEFT",root,"TOPLEFT",0,0)
                    b={frame=frame};cache.frames[#cache.frames+1]=b
                end
                batches[key]=b
            end
            b.key=key
            if b.w~=width or b.h~=height then b.frame:SetSize(width,height);b.w,b.h=width,height end
            if b.level~=level then b.frame:SetFrameLevel(level);b.level=level end
            if not b.visible then b.frame:Show();b.visible=true end;return b
        end
        local function acquire(key,b)
            local h=byKey[key]
            if not h then
                h=table.remove(free)
                if not h then
                    local texture=root:CreateTexture(nil,"ARTWORK")
                    assert(texture.SetVertexOffset and texture.SetParent,"3D rendering requires movable Texture regions")
                    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false);texture:SetTexelSnappingBias(0)end
                    texture:Hide();h={texture=texture,visible=false};cache.pool[#cache.pool+1]=h
                end
                byKey[key]=h
            end
            if h.frame~=b.frame then
                h.texture:SetParent(b.frame);h.frame=b.frame;h.anchored=false;h.geometryFace=nil
            end
            h.batchKey=b.key;h.drawKey=key;h.level=b.level
            return h
        end
        local function paintColor(h,color,revision)
            local old=h.color
            if not old or old[1]~=color[1] or old[2]~=color[2] or old[3]~=color[3] or old[4]~=color[4]then
                h.texture:SetVertexColor(unpack(color));h.color=h.color or {}
                for i=1,4 do h.color[i]=color[i]end
            end
            h.colorRevision=revision
        end
        local function polygon(points,color,material,key,face,b)
            if drawn>=4096 then dropped=dropped+1;return end
            drawn=drawn+1;local h=acquire(key,b)
            if not material and h.geometryFace==face then
                if h.colorRevision~=face.colorRevision then paintColor(h,color,face.colorRevision)end
                if not h.visible then h.texture:Show();h.visible=true end;return
            end
            h.geometryFace=not material and face or nil
            local a,b,c,d=points[1],points[2],points[3],points[4] or points[3]
            -- Quad winding: perimeter a,b,c,d -> native TL, TR, BR, BL.
            -- A triangle duplicates c at BR/BL, giving one degenerate triangle.
            local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
            for _,p in ipairs(points)do minX=math.min(minX,p.x);minY=math.min(minY,p.y);maxX=math.max(maxX,p.x);maxY=math.max(maxY,p.y)end
            local w,ht=math.max(.01,maxX-minX),math.max(.01,maxY-minY)
            local t=h.texture
            if not h.anchored or h.x~=minX or h.y~=minY then
                t:ClearAllPoints();t:SetPoint("TOPLEFT",h.frame,"TOPLEFT",minX,-minY);h.x,h.y=minX,minY;h.anchored=true
            end
            if h.w~=w or h.h~=ht then t:SetSize(w,ht);h.w,h.h=w,ht end
            local texture=material and material.texture or "Interface\\Buttons\\WHITE8X8"
            local blend=material and material.blend or "BLEND"
            if h.source~=texture then t:SetTexture(texture);h.source=texture;h.uv=nil end
            if h.blend~=blend then t:SetBlendMode(blend);h.blend=blend end
            local uv=material and material.texCoord or defaultUV
            local old=h.uv
            if not old or old[1]~=uv[1] or old[2]~=uv[2] or old[3]~=uv[3] or old[4]~=uv[4]then
                t:SetTexCoord(unpack(uv));h.uv={unpack(uv)}
            end
            local coordinates={a.x-minX,-(a.y-minY),d.x-minX,ht-(d.y-minY),b.x-minX-w,-(b.y-minY),c.x-minX-w,ht-(c.y-minY)}
            local vertices=h.vertices
            for i=1,4 do
                local j=i*2-1
                if not vertices or vertices[j]~=coordinates[j] or vertices[j+1]~=coordinates[j+1]then t:SetVertexOffset(i,coordinates[j],coordinates[j+1])end
            end
            h.vertices=coordinates
            paintColor(h,color,face.colorRevision)
            if not h.visible then t:Show();h.visible=true end
        end
        function scene.render(alpha)
            if scene.closed or session.stopping then return end
            local scale=math.max(.1,math.min(parent:GetWidth()/width,parent:GetHeight()/height))
            if lastScale~=scale then root:SetScale(scale)end
            local v=scene.getViewport()
            if selfViewportX~=v.x or selfViewportY~=v.y or selfViewportW~=v.w or selfViewportH~=v.h then
                input:ClearAllPoints();input:SetPoint("TOPLEFT",root,"TOPLEFT",v.x,-v.y);input:SetSize(v.w,v.h)
                selfViewportX,selfViewportY,selfViewportW,selfViewportH=v.x,v.y,v.w,v.h
            end
            input:Show()
            if session.paused then drag=nil
            elseif drag then
                local x,y=point()
                if x then
                    if G.IsMouseButtonDown and not G.IsMouseButtonDown(drag.button)then release(x,y)
                    elseif x~=drag.x or y~=drag.y then
                        local event={phase="move",x=x,y=y,dx=x-drag.x,dy=y-drag.y,button=drag.button}
                        drag.x,drag.y=x,y;send(event)
                    end
                end
            end
            if session.stopping then return end
            local fx=scene.particles
            local particleRevision=fx and fx.revision or 0
            if lastRevision==scene.revision and lastScale==scale and lastParticleRevision==particleRevision and (not fx or #fx.particles==0 or session.paused)then
                if lastShadingRevision~=scene.shadingRevision then
                    scene.renderList()
                    for _,h in pairs(byKey)do local face=h.geometryFace
                        if face and h.colorRevision~=face.colorRevision then paintColor(h,face.color,face.colorRevision)end
                    end
                    lastShadingRevision=scene.shadingRevision
                end
                return
            end
            drawn,dropped=0,0
            local geometry=scene.renderList();local geometryDraws=0
            for _,face in ipairs(geometry)do geometryDraws=geometryDraws+(#face.points<=4 and 1 or #face.points-2)end
            local started=session.host.profileMS()
            local particles=fx and fx.renderList(session.paused and 1 or alpha or 1,math.max(0,4096-geometryDraws)) or {}
            session.perf.record("particles3DProjectMs",session.host.profileMS()-started)
            -- Merge already-sorted lists so particles do not invalidate static mesh projection.
            -- Geometry owns its draw budget; excess billboards cannot hide the cube.
            local gi,pi=1,1;local particleDrawMS=0;local desired={};local count=0
            local function command(face,points,key,isParticle)
                if count>=4096 then dropped=dropped+1;return end
                count=count+1;local c=commands[count] or {};commands[count]=c
                c.face,c.points,c.key,c.particle=face,points,key,isParticle;desired[key]=true
            end
            while gi<=#geometry or pi<=#particles do
                local isParticle=particles[pi] and (not geometry[gi] or particles[pi].depth>geometry[gi].depth)
                local face=isParticle and particles[pi] or geometry[gi]
                if #face.points<=4 then command(face,face.points,face.key,isParticle)
                else for i=2,#face.points-1 do command(face,{face.points[1],face.points[i],face.points[i+1]},face.key..":"..i,false)end end
                if isParticle then pi=pi+1 else gi=gi+1 end
            end
            for key,h in pairs(byKey)do
                if not desired[key]then h.texture:Hide();h.visible=false;byKey[key]=nil;free[#free+1]=h end
            end
            -- Adjacent patches of one original face have no interior overlap.
            -- They share a Frame (and texture/blend state) instead of one Frame
            -- per pixel rectangle. Geometry boundaries still split additive runs.
            local wanted,segments,ordered={}, {}, {};local previous,activeBatch
            batchCount=0
            for i=1,count do
                local c=commands[i]
                local base=c.particle and (c.face.blend=="ADD" and "additive" or c.key) or ("surface:"..c.face.id..":"..c.face.sourceFace)
                if base~=previous then
                    segments[base]=(segments[base] or 0)+1;activeBatch=base..":"..segments[base]
                    batchCount=batchCount+1;wanted[activeBatch]=true;ordered[batchCount]=activeBatch;previous=base
                end
                c.batchKey=activeBatch
            end
            for key,b in pairs(batches)do if not wanted[key]then b.frame:Hide();b.visible=false;batches[key]=nil;freeFrames[#freeFrames+1]=b end end
            local baseLevel=root:GetFrameLevel()
            for i,key in ipairs(ordered)do batch(key,baseLevel+i)end
            local measure=session.perf.phase and session.perf.phase.measuring
            for i=1,count do
                local c=commands[i];local before=c.particle and measure and session.host.profileMS()
                polygon(c.points,c.face.color,c.particle and c.face or nil,c.key,c.face,batches[c.batchKey])
                if before then particleDrawMS=particleDrawMS+session.host.profileMS()-before end
            end
            for i=#commands,count+1,-1 do commands[i]=nil end
            session.perf.record("particles3DDrawMs",particleDrawMS)
            lastRevision,lastScale,lastParticleRevision=scene.revision,scale,particleRevision
            lastShadingRevision=scene.shadingRevision
        end
        local coreStats,coreDispose=scene.stats,scene.dispose
        function scene.stats()
            local out=coreStats();out.scene3DDraws=drawn;out.scene3DPooledQuads=#cache.pool;out.scene3DDropped=dropped;out.scene3DNativeFrames=batchCount;out.scene3DPooledFrames=#cache.frames
            if scene.particles then for key,value in pairs(scene.particles.stats())do out[key]=value end end;return out
        end
        function scene.dispose()
            if scene.particles then scene.particles.dispose() end
            callback=nil;drag=nil
            for _,event in ipairs({"OnMouseDown","OnMouseUp","OnMouseWheel","OnHide"})do input:SetScript(event,nil)end
            input:EnableMouse(false);input:Hide();root:Hide()
            for _,h in ipairs(cache.pool)do h.texture:Hide();h.visible=false end
            for _,b in ipairs(cache.frames)do b.frame:Hide();b.visible=false end
            drawn=0;batchCount=0;coreDispose()
        end
        return scene
    end
end
