-- Retained, bounded 2D UI. Coordinates are logical pixels from the top left.
-- Call begin/draw/finish; untouched nodes are hidden and reused next frame.
return function(E, G)
    local pcall = G.pcall
    -- Stay below WoW's 10,000 frame-level ceiling, including the topmost modal.
    -- 288 still leaves room for 128 depth-sorted models (two levels apiece).
    local LAYER_STRIDE=288
    -- Retail branches expose either two Vector3 objects or six scalar returns.
    -- Preserve every return before normalizing; taking only two drops Z/top.
    function E.readModelBounds(actor,method)
        if not actor or not actor[method] then return nil end
        local ok,a,b,c,d,e,f=pcall(actor[method],actor)
        if not ok then return nil end
        if type(a)~="number" then
            local function xyz(v)if v.GetXYZ then return v:GetXYZ()end;return v.x,v.y,v.z end
            ok,a,b,c,d,e,f=pcall(function()
                local x,y,z=xyz(a);local xx,yy,zz=xyz(b)
                return x,y,z,xx,yy,zz
            end)
            if not ok then return nil end
        end
        if not(E.util.finite(a) and E.util.finite(b) and E.util.finite(c) and
            E.util.finite(d) and E.util.finite(e) and E.util.finite(f))then return nil end
        return {x=a,y=b,z=c},{x=d,y=e,z=f}
    end
    -- Fit the measured, untransformed actor box into a transparent camera viewport.
    -- Camera looks along +X; -Y is screen-right and +Z is screen-up.
    function E.fitModelBounds(bottom,top,aspect,yaw,fill)
        local function xyz(v)if v.GetXYZ then return v:GetXYZ()end;return v.x,v.y,v.z end
        local ok,x0,y0,z0,x1,y1,z1=pcall(function()
            local a,b,c=xyz(bottom);local d,e,f=xyz(top);return a,b,c,d,e,f
        end)
        if not ok then return nil end
        local values={x0,y0,z0,x1,y1,z1,aspect,yaw,fill}
        for i=1,9 do if not E.util.finite(values[i])then return nil end end
        if not x1 or x1<=x0 or y1<=y0 or z1<=z0 or aspect<=0 then return nil end
        local c,s=math.cos(yaw),math.sin(yaw)
        local dx,dy,h=x1-x0,y1-y0,z1-z0
        local depth=math.abs(c)*dx+math.abs(s)*dy
        local width=math.abs(s)*dx+math.abs(c)*dy
        local tangent=math.tan(.55/2)
        fill=E.util.clamp(fill,.35,.9)
        local nearest=math.max(h/(2*tangent*fill),width/(2*tangent*aspect*fill),.01)
        local cx,cy,cz=(x0+x1)/2,(y0+y1)/2,(z0+z1)/2
        return {distance=depth/2+nearest, cameraZ=-h/2+.8*nearest*tangent,
            actorX=-(cx*c-cy*s),actorY=-(cx*s+cy*c),actorZ=-cz,
            width=width,height=h,depth=depth,nearest=nearest,fov=.55,
            bottom={x=x0,y=y0,z=z0},top={x=x1,y=y1,z=z1}}
    end
    -- Pet species carry skins. CreatureID and M2 FileDataID are not display IDs.
    function E.resolveModel(def)
        if def.kind~="petSpeciesID" then return def.kind,def.id end
        local journal=G.C_PetJournal
        if not journal then return nil,nil,"pet_journal_unavailable" end
        local display
        if journal.GetDisplayIDByIndex then
            local ok,value=pcall(journal.GetDisplayIDByIndex,def.id,def.displayIndex or 1)
            if ok and type(value)=="number" and value>0 then display=value end
        end
        if not display and journal.GetPetInfoTableBySpeciesID then
            local ok,info=pcall(journal.GetPetInfoTableBySpeciesID,def.id)
            if ok and type(info)=="table" and type(info.displayID)=="number" and info.displayID>0 then display=info.displayID end
        end
        if display then return "creatureDisplayID",display end
        return nil,nil,"pet_display_unavailable"
    end
    function E.newSurface(session, parent, cache)
        cache = cache or { pools = {}, layers = {} }
        if not cache.root then cache.root = G.CreateFrame("Frame", nil, parent) end
        local root, nodes, generation, count = cache.root, {}, 0, 0
        local width, height = session.content.viewport.width, session.content.viewport.height
        root:ClearAllPoints(); root:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        root:SetSize(width, height);root:EnableMouse(false);root:Show()
        local self = {}
        local actorSurface
        local measuredBounds, preloadQueue, preloadSeen = {}, {}, {}
        local preloader
        local function modelKey(def)return def.kind..":"..tostring(def.id)..":"..tostring(def.displayIndex or 1)end
        local assets = session.content.assets or {}
        local modelLimit = (session.content.limits or {}).maxSurfaceModels or 104
        cache.modelCount = cache.modelCount or 0
        cache.compatModelCount=cache.compatModelCount or 0
        local function optional(object, method, ...)
            if object and object[method] then return pcall(object[method], object, ...) end
            return false
        end
        optional(root,"SetClipsChildren",false)
        local function modelLevel(node,level)
            optional(node.object,"SetFixedFrameLevel",true)
            if node.object:GetFrameLevel()~=level then node.object:SetFrameLevel(level)end
            local child=node.scene or node.model
            if child then
                optional(child,"SetFixedFrameLevel",true)
                if child:GetFrameLevel()~=level+1 then child:SetFrameLevel(level+1)end
            end
            if node.compatModel then
                optional(node.compatModel,"SetFixedFrameLevel",true)
                if node.compatModel:GetFrameLevel()~=level+1 then node.compatModel:SetFrameLevel(level+1)end
            end
            node.drawLevel=level
        end
        local function texture(object, key, coords, color, repeatTexture, blend)
            local def = (assets.textures or {})[key]
            if not def then G.error("unknown surface texture: " .. tostring(key)) end
            local wrap = repeatTexture and "REPEAT" or "CLAMP"
            local ok, result, atlasApplied
            if def.kind=="atlas" and object.SetAtlas then ok,result=pcall(object.SetAtlas,object,def.atlas,false)
                atlasApplied=ok and result~=false
            elseif def.kind=="atlas"then ok=false
            else ok,result=pcall(object.SetTexture, object, def.id or def.path, wrap, wrap)end
            if not ok or result == false then
                pcall(object.SetTexture, object, def.fallbackPath or "Interface\\Icons\\INV_Misc_QuestionMark")
            end
            if coords or not atlasApplied then object:SetTexCoord(unpack(coords or {0,1,0,1}))end
            object:SetVertexColor(unpack(color or {1,1,1,1}))
            object:SetBlendMode(blend or "BLEND")
        end
        local function clearModel(node)
            if node.model then
                if not node.scene then optional(node.model,"SetScript","OnModelLoaded",nil)end
                if node.scene then optional(node.scene,"SetPaused",true,false);node.scene:Hide()end
                optional(node.model,"SetPaused",true);optional(node.model,"ClearModel")
                node.model:Hide()
            end
            if node.compatModel then
                node.compatModel:SetScript("OnModelLoaded",nil);optional(node.compatModel,"ClearModel");node.compatModel:Hide()
            end
            node.asset=nil;node.loaded=false;node.pose=nil;node.modelRequested=false;node.resolvedID=nil
            node.bounds=nil;node.fitReady=false;node.framing=nil
            node.compatActive=false;node.compatLoaded=false;node.compatRequested=false;node.failureNotice=false
            node.hiddenAt=nil
        end
        local function legacyPose(model,spec,def,compat)
            optional(model,"SetPortraitZoom",def.portraitZoom or 0)
            optional(model,"SetCamDistanceScale",compat and (def.fallbackDistance or .65) or spec.distance or def.distance or 1)
            optional(model,"SetModelScale",spec.scale or def.scale or 1)
            optional(model,"SetFacing",spec.facing or def.facing or 0)
            optional(model,"SetPosition",unpack(def.offset or {0,0,0}))
            optional(model,"SetAnimation",spec.animation or def.animation or 0)
            optional(model,"SetPaused",session.paused or spec.paused==true)
        end
        local function pose(node)
            local model, spec, def = node.model, node.pose, node.modelDef
            if not model or not spec or not def then return end
            if node.scene then
                if not node.loaded then return end
                if not node.bounds then node.bounds=measuredBounds[modelKey(def)]end
                if not node.bounds then
                    if session.host.now()-(node.requestedAt or 0)>3 then return end
                    optional(model,"SetScale",1);optional(model,"SetYaw",0);optional(model,"SetPosition",0,0,0)
                    optional(model,"SetUseCenterForOrigin",false,false,false)
                    local bottom,top=E.readModelBounds(model,"GetActiveBoundingBox")
                    local fit=E.fitModelBounds(bottom,top,(spec.w or 1)/(spec.h or 1),spec.facing or def.facing or 0,def.fitFill or .82)
                    if not fit then
                        bottom,top=E.readModelBounds(model,"GetMaxBoundingBox")
                        fit=E.fitModelBounds(bottom,top,(spec.w or 1)/(spec.h or 1),spec.facing or def.facing or 0,def.fitFill or .82)
                    end
                    if not fit then return end
                    node.bounds={fit.bottom,fit.top}
                    measuredBounds[modelKey(def)]=node.bounds
                end
                local fit=E.fitModelBounds(node.bounds[1],node.bounds[2],(spec.w or 1)/(spec.h or 1),spec.facing or def.facing or 0,def.fitFill or .82)
                if not fit then return end
                node.framing=fit;node.fitReady=true
                optional(model,"SetScale",1);optional(model,"SetYaw",spec.facing or def.facing or 0)
                optional(model,"SetPosition",fit.actorX,fit.actorY,fit.actorZ)
                node.scene:SetCameraFieldOfView(fit.fov)
                node.scene:SetCameraPosition(-fit.distance,0,fit.cameraZ)
                optional(node.scene,"SetCameraNearClip",math.max(.001,fit.nearest*.01))
                optional(node.scene,"SetCameraFarClip",fit.distance+fit.depth+fit.height+20)
                optional(model,"SetAnimation",spec.animation or def.animation or 0)
                optional(node.scene,"SetPaused",session.paused or spec.paused==true,false)
                return
            end
            legacyPose(model,spec,def)
        end
        local function compatibilityModel(node,spec,def)
            if not node.compatModel and cache.compatModelCount<modelLimit then
                local ok,model=pcall(G.CreateFrame,"PlayerModel",nil,node.object)
                if ok and model then
                    node.compatModel=model;cache.compatModelCount=cache.compatModelCount+1
                    model:SetAllPoints(node.object);model:EnableMouse(false)
                    model:SetFrameLevel(node.object:GetFrameLevel()+1)
                end
            end
            local model=node.compatModel
            if not model then return false end
            if not node.compatActive then
                node.compatActive=true
                if node.scene then node.scene:Hide();optional(node.scene,"SetPaused",true,false)end
                if node.model then node.model:Hide();optional(node.model,"ClearModel")end
            end
            if not node.compatRequested and session.host.now()>=(node.compatNextAt or 0) then
                node.compatNextAt=session.host.now()+.5
                local kind,id=E.resolveModel(def)
                if kind then
                    node.compatRequested=true
                    model:SetScript("OnModelLoaded",function()
                        if node.claimed and not session.stopping and node.asset==spec.asset then
                            node.compatLoaded=true;legacyPose(model,node.pose or spec,def,true);model:Show()
                        end
                    end)
                    local ok,accepted=optional(model,kind=="creatureDisplayID" and "SetDisplayInfo" or "SetModel",id)
                    if not ok or accepted==false then node.compatRequested=false end
                end
            end
            if model.GetModelFileID then
                local ok,id=pcall(model.GetModelFileID,model)
                node.compatLoaded=ok and type(id)=="number" and id>0
            end
            local signature=table.concat({spec.animation or def.animation or 0,(session.paused or spec.paused) and 1 or 0,spec.w or 1,spec.h or 1},":")
            node.pose=spec
            if node.compatLoaded then
                if node.compatPose~=signature then legacyPose(model,spec,def,true);node.compatPose=signature end
                model:Show()
            else model:Hide()end
            return node.compatLoaded
        end
        local function reportUnavailable(node,spec)
            if node.preloading or node.failureNotice then return end
            node.failureNotice=true
            session.perf.note("model.unavailable",{asset=spec.asset,reason=node.loadReason or "model_or_bounds_unavailable"})
        end
        local function drawModel(node, spec)
            local def=(assets.models or {})[spec.asset]
            if not def then G.error("unknown surface model: " .. tostring(spec.asset)) end
            local modelOnly=def.fallbackMode=="model"
            local fallback=not modelOnly and (spec.fallback or def.fallback)
            if fallback and node.fallbackAsset~=fallback then
                texture(node.fallback,fallback,nil,{1,1,1,1});node.fallbackAsset=fallback
            end
            if not node.model and not node.unavailable and cache.modelCount<modelLimit then
                if def.fitToBounds then
                    local ok,model=pcall(function()
                        node.scene=node.scene or G.CreateFrame("ModelScene",nil,node.object)
                        node.scene:SetAllPoints(node.object);node.scene:EnableMouse(false)
                        node.scene:SetAlpha(0)
                        node.scene:SetCameraOrientationByAxisVectors(1,0,0,0,-1,0,0,0,1)
                        optional(node.scene,"SetLightVisible",true)
                        optional(node.scene,"SetLightAmbientColor",.72,.72,.72)
                        optional(node.scene,"SetLightDiffuseColor",.28,.28,.28)
                        optional(node.scene,"SetLightDirection",-1,-1,-1)
                        return node.scene:CreateActor("IGSurfaceModel"..tostring(cache.modelCount+1))
                    end)
                    if ok and model then node.model=model;cache.modelCount=cache.modelCount+1
                    else node.unavailable=true;if node.scene then node.scene:Hide()end end
                else
                    local ok,model=pcall(G.CreateFrame,"PlayerModel",nil,node.object)
                    if ok and model then
                        node.model=model;cache.modelCount=cache.modelCount+1
                        model:SetAllPoints(node.object);model:EnableMouse(false)
                        optional(model,"SetClipsChildren",false)
                    else node.unavailable=true end
                end
            end
            local model=node.model
            if node.asset~=spec.asset then
                clearModel(node);node.asset=spec.asset;node.modelDef=def;node.pose=spec
                node.requestedAt=session.host.now();node.failed=false;node.resolveNextAt=0
                node.compatNextAt=0;node.compatPose=nil
                node.lastPose=nil
            end
            if node.compatActive then
                local ready=compatibilityModel(node,spec,def);node.fallback:Hide()
                if not ready and session.host.now()-node.requestedAt>=3 then reportUnavailable(node,spec)end
                return
            end
            if model and not node.modelRequested and node.asset and session.host.now()>=(node.resolveNextAt or 0) and session.host.now()-node.requestedAt<=3 then
                local kind,id,reason=E.resolveModel(def)
                node.resolveNextAt=session.host.now()+.5
                node.failed=not kind;node.loadReason=reason
                if kind then
                    node.modelRequested=true;node.resolvedID=id
                    -- Geometry needs an updating scene while loading, even when gameplay is paused.
                    -- pose() restores the requested pause after bounds have been measured.
                    if node.scene then optional(node.scene,"SetPaused",false,false)end
                    if not node.scene then
                        model:SetScript("OnModelLoaded",function()
                            if node.claimed and not session.stopping and node.asset==spec.asset then
                                node.loaded=true;node.failed=false;pose(node);node.fallback:Hide()
                            end
                        end)
                    end
                    local ok, accepted
                    if node.scene then
                        ok,accepted=optional(model,kind=="creatureDisplayID" and "SetModelByCreatureDisplayID" or "SetModelByFileID",id)
                    elseif kind=="creatureDisplayID" then ok,accepted=optional(model,"SetDisplayInfo",id)
                    else ok,accepted=optional(model,"SetModel",id)end
                    if not ok or accepted==false then node.failed=true end
                end
            end
            if model and not node.failed then
                if not node.loaded and model.GetModelFileID then
                    local ok,id=pcall(model.GetModelFileID,model)
                    node.loaded=ok and type(id)=="number" and id>0
                    if node.loaded then node.lastPose=nil end
                end
                local signature=table.concat({spec.scale or def.scale or 1,spec.distance or def.distance or 1,
                    spec.facing or def.facing or 0,spec.animation or def.animation or 0,
                    (session.paused or spec.paused) and 1 or 0,spec.w or 1,spec.h or 1},":")
                node.pose=spec
                if node.lastPose~=signature or (node.scene and node.loaded and not node.fitReady)then pose(node);node.lastPose=signature end
                if node.scene then
                    if node.loaded and node.fitReady then model:Show();node.scene:SetAlpha(1);node.scene:Show()
                    elseif session.host.now()-(node.requestedAt or 0)<3 then model:Show();node.scene:SetAlpha(0);node.scene:Show()
                    else node.scene:Hide()end
                elseif node.loaded or session.host.now()-(node.requestedAt or 0)<3 then model:Show()else model:Hide()end
            elseif model then model:Hide() end
            local ready=node.loaded and not node.failed and (not node.scene or node.fitReady)
            if modelOnly then
                node.fallback:Hide()
                if not ready and (node.unavailable or node.failed or session.host.now()-node.requestedAt>=3)then
                    ready=compatibilityModel(node,spec,def)
                    if not ready and session.host.now()-node.requestedAt>=3 then reportUnavailable(node,spec)end
                end
            elseif ready then node.fallback:Hide()else node.fallback:Show()end
        end
        local function layer(n)
            if not cache.layers[n] then
                local f = G.CreateFrame("Frame", nil, root)
                f:SetAllPoints(root); f:SetFrameLevel(root:GetFrameLevel() + n * LAYER_STRIDE)
                optional(f,"SetClipsChildren",false)
                f:EnableMouse(false) -- only explicit buttons participate in hit testing
                cache.layers[n] = f
            end
            return cache.layers[n]
        end
        local function acquire(kind, z, nativeButton)
            local key = kind .. ":" .. z .. (nativeButton and ":native" or "")
            local pool = cache.pools[key] or {}; cache.pools[key] = pool
            for _, node in ipairs(pool) do if not node.claimed then node.claimed = true; return node end end
            local parentLayer, object = layer(z)
            if kind == "text" then object = parentLayer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            elseif kind=="cooldown" then
                object=G.CreateFrame("Cooldown",nil,parentLayer,"CooldownFrameTemplate")
                object:EnableMouse(false);object:SetHideCountdownNumbers(true)
                object:SetDrawSwipe(true);object:SetDrawEdge(true);object:SetDrawBling(false)
                object:SetSwipeColor(.015,.03,.02,.78)
            elseif kind == "button" or kind == "model" or kind=="panel" then
                object = G.CreateFrame(kind=="button" and "Button" or "Frame", nil, parentLayer,
                    nativeButton and "UIPanelButtonTemplate" or nil)
                object:EnableMouse(false)
            else object = parentLayer:CreateTexture(nil, "ARTWORK") end
            local node = { object = object, claimed = true, kind = kind, nativeButton=nativeButton==true }
            if kind=="panel"then
                node.bg=object:CreateTexture(nil,"BACKGROUND");node.bg:SetAllPoints(object)
            end
            if kind == "model" then
                node.fallback=object:CreateTexture(nil,"BACKGROUND");node.fallback:SetAllPoints(object)
                if object.SetClipsChildren then object:SetClipsChildren(false)end
            end
            if kind == "button" then
                node.bg = object:CreateTexture(nil, "BACKGROUND"); node.bg:SetAllPoints(object)
                node.label = object:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                node.label:SetAllPoints(object)
                object:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                object:SetScript("OnClick", function(_, button)
                    if node.enabled and node.fn then session.safe("surface.click", node.fn, button) end
                end)
                object:SetScript("OnEnter", function() if node.enabled and not node.nativeButton then object:SetAlpha(.82) end end)
                object:SetScript("OnLeave", function() object:SetAlpha(1) end)
            end
            pool[#pool + 1] = node; return node
        end
        function self.begin()
            generation = generation + 1
            if actorSurface then actorSurface.begin()end
            root:SetScale(math.max(.1, math.min(parent:GetWidth() / width, parent:GetHeight() / height)))
        end
        function self.draw(id, spec)
            local kind, z = spec.kind or "rect", spec.layer or 0
            if kind ~= "rect" and kind ~= "text" and kind ~= "button" and kind ~= "texture" and kind ~= "model" and kind~="cooldown" and kind~="panel" then G.error("unsupported surface node") end
            if z < 0 or z > 30 or z ~= math.floor(z) then G.error("invalid surface layer") end
            local node = nodes[id]
            if not node then
                count = count + 1; if count > 3600 then G.error("surface node budget exceeded") end
                node = acquire(kind, z, kind=="button"and spec.nativeButton==true); node.z = z;node.order=count;nodes[id] = node
            end
            if node.kind ~= kind or node.z ~= z then G.error("surface node type/layer changed: " .. id) end
            if kind=="button"and (node.nativeButton==true)~=(spec.nativeButton==true)then G.error("surface button template changed: "..id)end
            node.generation = generation
            node.lastSpec=spec
            if node.hiddenAt then node.hiddenAt=nil;node.lastPose=nil;node.compatPose=nil end
            local object = node.object
            local x, y, w, h = spec.x or 0, spec.y or 0, spec.w or 1, spec.h or 1
            node.depth=spec.depth or (kind=="model" and spec.anchorY) or (y+h)
            if not E.util.finite(node.depth)then G.error("invalid surface depth")end
            if node.x ~= x or node.y ~= y then object:ClearAllPoints(); object:SetPoint("TOPLEFT", layer(z), "TOPLEFT", x, -y); node.x=x;node.y=y end
            if node.w ~= w or node.h ~= h then object:SetSize(math.max(.01,w),math.max(.01,h));node.w=w;node.h=h end
            if kind=="panel"then
                local layout=spec.layout or "Dialog"
                if node.panelLayout~=layout then
                    local ns=G.NineSliceUtil
                    if node.panelLayout and ns and ns.HideLayout then pcall(ns.HideLayout,object)end
                    local ok=false
                    if ns and ns.GetLayout and ns.ApplyLayoutByName and ns.GetLayout(layout)then
                        ok=pcall(ns.ApplyLayoutByName,object,layout)
                    end
                    node.panelLayout=layout;node.panelBorderReady=ok
                    if not ok then
                        if ns and ns.HideLayout then pcall(ns.HideLayout,object)end
                        session.perf.note("surface.panel",{layout=layout,status="native_border_unavailable"})
                    end
                end
            end
            local color = spec.color or ((kind == "text" or kind=="texture") and {1,1,1,1} or {.2,.3,.2,1})
            local signature = table.concat(color, ":")
            if kind=="texture" or ((kind=="button"or kind=="panel") and spec.asset) then
                local texSignature=tostring(spec.asset)..":"..signature..":"..table.concat(spec.texCoord or {0,1,0,1},":")..":"..tostring(spec.tile)..":"..(spec.blend or "BLEND")
                if node.textureSignature~=texSignature then
                    texture(node.bg or object,spec.asset,spec.texCoord,color,spec.tile,spec.blend);node.textureSignature=texSignature
                end
            elseif kind=="model" then
                if session.content.surfaceModelScene then
                    if not E.newSurfaceActors then G.error("package_not_included: surface-models") end
                    if not actorSurface then actorSurface=E.newSurfaceActors(session,root,cache,layer);actorSurface.begin()end
                    actorSurface.draw(node,spec,(assets.models or {})[spec.asset])
                else drawModel(node,spec)end
            elseif kind=="cooldown" then
                local duration,remaining=spec.duration,spec.remaining
                if not E.util.finite(duration) or duration<=0 or not E.util.finite(remaining) then G.error("invalid surface cooldown")end
                remaining=math.max(0,math.min(duration,remaining))
                duration=duration/(session.speed or 1);remaining=remaining/(session.speed or 1)
                local now=session.host.now();local paused=session.paused or spec.paused==true
                if node.cdDuration~=duration or node.cdPaused~=paused or not node.cdEnd or math.abs(node.cdEnd-now-remaining)>.12 then
                    object:SetCooldown(now-duration+remaining,duration)
                    object:SetPaused(paused);node.cdEnd=now+remaining;node.cdDuration=duration;node.cdPaused=paused
                end
            else
                if node.textureSignature then node.color=nil;node.textureSignature=nil end
                if node.color ~= signature then
                    if kind == "text" then object:SetTextColor(unpack(color))
                    else (node.bg or object):SetColorTexture(unpack(color)) end
                    node.color = signature
                end
            end
            if kind == "text" or kind == "button" then
                local font = node.label or object
                if node.text ~= spec.text then font:SetText(spec.text or ""); node.text = spec.text end
                local size = spec.size or 14
                if node.size ~= size then font:SetFont(G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",size,"");node.size=size end
                local align = spec.align or "CENTER"
                if node.align ~= align then font:SetJustifyH(align);node.align=align end
                if kind == "button" then
                    node.fn = spec.onClick; node.enabled = spec.enabled ~= false
                    object:EnableMouse(node.enabled)
                    if node.nativeButton then optional(object,"SetEnabled",node.enabled)end
                    -- A hit target does not need a transparent render region over models.
                    if node.nativeButton or (not spec.asset and color[4]==0)then node.bg:Hide()else node.bg:Show()end
                    font:SetTextColor(1,.96,.84,node.enabled and 1 or .45)
                end
            end
            object:Show(); return node
        end
        function self.finish()
            local groups={}
            for _, node in pairs(nodes) do
                if node.generation ~= generation then
                    node.object:Hide();node.fn=nil
                    if node.kind=="model" and node.asset and not node.sharedScene then
                        node.hiddenAt=node.hiddenAt or session.host.now()
                        if node.scene then optional(node.scene,"SetPaused",true,false);node.scene:Hide()end
                        if node.compatModel then optional(node.compatModel,"SetPaused",true);node.compatModel:Hide()end
                        if not node.scene and node.model then optional(node.model,"SetPaused",true);node.model:Hide()end
                        if session.host.now()-node.hiddenAt>=15 then clearModel(node)end
                    end
                    if node.kind=="cooldown" then node.object:Clear();node.cdEnd=nil end
                elseif node.kind=="model" and not node.sharedScene then
                    groups[node.z]=groups[node.z] or {};groups[node.z][#groups[node.z]+1]=node
                end
            end
            for z,group in pairs(groups)do
                table.sort(group,function(a,b)if a.depth==b.depth then return a.order<b.order end;return a.depth<b.depth end)
                for rank,node in ipairs(group)do
                    local level=layer(z):GetFrameLevel()+rank*2
                    modelLevel(node,level)
                end
            end
            if actorSurface then actorSurface.finish()end
        end
        function self.preloadModel(asset)
            if session.content.surfaceModelScene then
                if not E.newSurfaceActors then G.error("package_not_included: surface-models") end
                if not actorSurface then actorSurface=E.newSurfaceActors(session,root,cache,layer);actorSurface.begin()end
                return actorSurface.preload(asset,4)
            end
            local def=(assets.models or {})[asset]
            if not def or preloadSeen[asset] or measuredBounds[modelKey(def)] or #preloadQueue>=32 then return false end
            preloadSeen[asset]=true;preloadQueue[#preloadQueue+1]=asset;return true
        end
        function self.update()
            if session.stopping then return end
            if actorSurface then actorSurface.update()end
            for _,node in pairs(nodes)do
                if node.kind=="model" and not node.sharedScene and node.generation==generation and node.lastSpec then
                    local ready=(node.compatActive and node.compatLoaded) or (node.loaded and not node.failed and (not node.scene or node.fitReady))
                    if not ready then drawModel(node,node.lastSpec)end
                    if node.drawLevel then modelLevel(node,node.drawLevel)end
                elseif node.kind=="model" and node.hiddenAt and session.host.now()-node.hiddenAt>=15 then clearModel(node)end
            end
            if #preloadQueue>0 then
                if not preloader then
                    preloader=acquire("model",0);preloader.preloading=true
                    preloader.object:SetPoint("TOPLEFT",root,"TOPLEFT",0,0);preloader.object:SetSize(96,96)
                    preloader.object:SetAlpha(0);preloader.object:Show()
                end
                local asset=preloadQueue[1]
                drawModel(preloader,{asset=asset,w=96,h=96,animation=0})
                if preloader.fitReady or preloader.compatLoaded or (preloader.requestedAt and session.host.now()-preloader.requestedAt>=3.1)then
                    clearModel(preloader);table.remove(preloadQueue,1)
                end
            end
        end
        function self.dispose()
            if actorSurface then actorSurface.dispose()end
            if preloader then
                clearModel(preloader);preloader.object:Hide();preloader.object:SetAlpha(1)
                preloader.claimed=false;preloader.preloading=false;preloader.unavailable=nil
            end
            root:Hide()
            for _, node in pairs(nodes) do
                node.object:Hide();node.fn=nil;node.enabled=false;node.claimed=false;node.object:SetAlpha(1)
                -- Click handlers capture this session and must be rebound on reuse.
                if node.kind == "button" then node.object:SetScript("OnClick",nil);node.object:SetScript("OnEnter",nil);node.object:SetScript("OnLeave",nil) end
                if node.kind == "model" then
                    if node.sharedScene then node.scene=nil;node.sharedScene=nil else clearModel(node)end
                    node.fallbackAsset=nil;node.unavailable=nil
                end
                if node.kind=="cooldown" then node.object:Clear();node.object:SetPaused(false);node.cdEnd=nil end
                node.textureSignature=nil;node.color=nil
            end
        end
        -- Rebind pooled buttons to this session rather than retaining the old closure.
        for _, pool in pairs(cache.pools) do
            for _, node in ipairs(pool) do
                if node.kind == "button" then
                    node.object:SetScript("OnClick",function(_,button) if node.enabled and node.fn then session.safe("surface.click",node.fn,button)end end)
                    node.object:SetScript("OnEnter",function()if node.enabled and not node.nativeButton then node.object:SetAlpha(.82)end end)
                    node.object:SetScript("OnLeave",function()node.object:SetAlpha(1)end)
                end
            end
        end
        self.cache = cache
        function self.stats()
            local active, loaded, fallback = 0,0,0
            for _,node in pairs(nodes)do
                if node.kind=="model" and node.claimed and node.generation==generation then
                    active=active+1
                    if (node.compatActive and node.compatLoaded) or (not node.compatActive and node.loaded and not node.failed and (not node.scene or node.fitReady))then loaded=loaded+1 else fallback=fallback+1 end
                end
            end
            return {surfaceModels=active,surfaceModelsLoaded=loaded,surfaceModelFallbacks=fallback,pooledSurfaceModels=cache.modelCount+cache.compatModelCount,surfaceNodes=count}
        end
        return self
    end
end
