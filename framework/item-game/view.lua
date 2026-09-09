return function(E, G)
    local pcall = G.pcall
    local function label(parent, size, layer)
        local f = parent:CreateFontString(nil, layer or "OVERLAY", size or "GameFontNormalSmall")
        f:SetJustifyH("LEFT"); return f
    end
    local function background(parent, r, g, b, a)
        local t = parent:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints(parent); t:SetColorTexture(r, g, b, a); return t
    end
    function E.newWoWView(session)
        local host, config = session.host, session.content
        local cache = E.viewCache
        if not cache then
            cache = { rects = {}, models = {}, actors = {}, terrain = {}, buttons = {}, bounds = {}, health = {}, created = 0 }
            E.viewCache = cache
            local f = G.CreateFrame("Frame", nil, G.UIParent)
            cache.frame = f; f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
            f:SetMovable(true); f:EnableMouse(true)
            background(f, .035, .045, .065, .98)
            cache.title = label(f, "GameFontNormalLarge"); cache.title:SetPoint("TOPLEFT", 14, -13)
            cache.info = label(f); cache.info:SetPoint("TOPLEFT", 14, -39); cache.info:SetSize(860, 18)
            cache.message = label(f); cache.message:SetPoint("BOTTOMLEFT", 14, 12); cache.message:SetSize(860, 22)
            cache.status = label(f); cache.status:SetPoint("BOTTOMLEFT", 14, 39); cache.status:SetSize(860, 20)
            cache.drag = G.CreateFrame("Frame", nil, f); cache.drag:SetPoint("TOPLEFT"); cache.drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -46, 0); cache.drag:SetHeight(33)
            cache.drag:EnableMouse(true); cache.drag:RegisterForDrag("LeftButton")
            cache.drag:SetScript("OnDragStart", function() f:StartMoving() end)
            cache.drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
            cache.close = G.CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            cache.close:SetSize(30, 24); cache.close:SetPoint("TOPRIGHT", -8, -8); cache.close:SetText("X")
            cache.canvas = G.CreateFrame("Frame", nil, f)
            cache.canvas:SetPoint("TOPLEFT", 12, -170); cache.canvas:SetPoint("BOTTOMRIGHT", -12, 68)
            if cache.canvas.SetClipsChildren then cache.canvas:SetClipsChildren(true) end
            background(cache.canvas, .06, .08, .105, 1)
            cache.overlay=G.CreateFrame("Frame",nil,cache.canvas);cache.overlay:SetAllPoints(cache.canvas);cache.overlay:SetFrameLevel(cache.canvas:GetFrameLevel()+10)
            cache.logFrame = G.CreateFrame("Frame", nil, f)
            cache.logFrame:SetAllPoints(f); cache.logFrame:SetFrameLevel(f:GetFrameLevel() + 9500); cache.logFrame:EnableMouse(true)
            cache.close:SetFrameLevel(cache.logFrame:GetFrameLevel() + 10)
            background(cache.logFrame, .025, .03, .04, 1)
            local help = label(cache.logFrame); help:SetPoint("TOPLEFT", 14, -15); help:SetWidth(690); cache.logHeader = help
            local close = G.CreateFrame("Button", nil, cache.logFrame, "UIPanelButtonTemplate")
            close:SetSize(90, 24); close:SetPoint("TOPRIGHT", -52, -10); close:SetText("返回")
            local function dismissPanel()
                cache.logEdit:ClearFocus(); cache.logFrame:Hide()
                cache.apply:Hide(); cache.apply:SetScript("OnClick", nil)
            end
            close:SetScript("OnClick", dismissPanel)
            cache.apply = G.CreateFrame("Button", nil, cache.logFrame, "UIPanelButtonTemplate")
            cache.apply:SetSize(90,24); cache.apply:SetPoint("TOPRIGHT",-148,-10); cache.apply:SetText("确定"); cache.apply:Hide()
            local scroll = G.CreateFrame("ScrollFrame", nil, cache.logFrame, "UIPanelScrollFrameTemplate")
            scroll:SetPoint("TOPLEFT", 14, -45); scroll:SetPoint("BOTTOMRIGHT", -36, 14)
            local edit = G.CreateFrame("EditBox", nil, scroll)
            edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject("ChatFontNormal")
            edit:SetWidth(830); edit:SetHeight(430); edit:SetMaxLetters(0)
            edit:SetScript("OnEscapePressed", dismissPanel)
            scroll:SetScrollChild(edit); cache.logEdit = edit; cache.logFrame:Hide()
        end
        local self = { cache = cache, frame = cache.frame, canvas = cache.canvas, buttons = 0, camera = { x = 0, y = 0, zoom = 1 }, showBounds = false, drawn = 0, modelLoaded = 0, modelFailed = 0 }
        local f = cache.frame
        local width = math.min(980, math.max(600, G.UIParent:GetWidth() - 40))
        local height = math.min(690, math.max(480, G.UIParent:GetHeight() - 40))
        f:SetSize(width, height); f:ClearAllPoints(); f:SetPoint("CENTER")
        local gameUI = config.presentation == "game"
        cache.title:SetText(session.manifest.name .. (gameUI and "" or "  /  Engine " .. E.VERSION))
        cache.canvas:ClearAllPoints()
        cache.canvas:SetPoint("TOPLEFT", 12, gameUI and -44 or -170)
        cache.canvas:SetPoint("BOTTOMRIGHT", -12, gameUI and 34 or 68)
        if gameUI then cache.info:Hide();cache.status:Hide() else cache.info:Show();cache.status:Show() end
        cache.logEdit:SetWidth(width - 58)
        cache.logHeader:SetWidth(width - 265)
        cache.title:SetWidth(width - 70); cache.info:SetWidth(width - 28); cache.message:SetWidth(width - 28); cache.status:SetWidth(width - 28)
        cache.message:SetText(gameUI and "" or "选择测试。性能数据必须在当前客户端运行后导出。")
        if config.hideHostFooter then cache.message:Hide()else cache.message:Show()end
        cache.logFrame:Hide(); cache.logEdit:ClearFocus()
        cache.close:SetScript("OnClick", function() session.requestClose("window_closed") end)
        f:SetScript("OnHide", function()
            if not session.stopping and not self.hiding then
                self.hiding=true;if cache.escapeProxy then cache.escapeProxy:Hide()end;self.hiding=false
                session.requestClose("window_hidden")
            end
        end)
        f:Show()
        local function acquire(pool, make)
            for i = 1, #pool do if not pool[i].active then pool[i].active = true; return pool[i] end end
            if #pool >= 1600 then return nil, "view_pool_limit" end
            local h = { object = make(), active = true }; pool[#pool + 1] = h; cache.created = cache.created + 1; return h
        end
        function self.attach(entity)
            local visual = entity.visual or {}; local handle, kind
            if visual.kind == "scene_model" then
                local def=(config.assets.models or {})[visual.asset]
                if not def then return nil,"missing_model_asset" end
                local modelKind,modelID=E.resolveModel(def)
                if not modelKind then return nil,"model_display_unavailable" end
                local ok, result=pcall(function()
                    if not cache.scene then
                        cache.scene=G.CreateFrame("ModelScene",nil,cache.canvas)
                        cache.scene:SetPoint("BOTTOMLEFT",cache.canvas,"BOTTOMLEFT",0,0)
                        cache.scene:SetCameraFieldOfView(.9)
                        cache.scene:SetCameraPosition(-config.viewport.height/(24*math.tan(.45)),0,config.viewport.height/24)
                        if cache.scene.SetCameraFarClip then cache.scene:SetCameraFarClip(1000) end
                    end
                    local free=false;for _,h in ipairs(cache.actors)do if not h.active then free=true;break end end
                    if not free and #cache.actors>=40 then G.error("actor_pool_limit")end
                    return acquire(cache.actors,function()return cache.scene:CreateActor("IGActor"..(#cache.actors+1))end)
                end)
                if not ok or not result then self.modelFailed=self.modelFailed+1;return nil,"ModelScene_unavailable" end
                handle=result;kind="scene_model";handle.loaded=false;handle.owner=session
                local actor=handle.object
                local called, accepted
                if modelKind=="creatureDisplayID" then called,accepted=pcall(actor.SetModelByCreatureDisplayID,actor,modelID)
                else called,accepted=pcall(actor.SetModelByFileID,actor,modelID)end
                if not called or accepted==false then actor:Hide();handle.active=false;self.modelFailed=self.modelFailed+1;return nil,"actor_load_call_failed"end
                if actor.SetScale then actor:SetScale(def.sceneScale or 1)end
                if actor.SetYaw then actor:SetYaw(def.facing or 0)end
                if actor.SetPaused then actor:SetPaused(false)end
                cache.scene:Show()
            elseif visual.kind == "model" then
                if #cache.models >= 40 then
                    local free = false; for _, h in ipairs(cache.models) do if not h.active then free = true; break end end
                    if not free then return nil, "model_pool_limit" end
                end
                local ok, result = pcall(acquire, cache.models, function() return G.CreateFrame("PlayerModel", nil, cache.canvas) end)
                if not ok or not result then self.modelFailed = self.modelFailed + 1; return nil, "PlayerModel_unavailable" end
                handle = result; kind = "model"
                local def = (config.assets.models or {})[visual.asset]
                if not def then handle.active = false; return nil, "missing_model_asset" end
                local modelKind,modelID=E.resolveModel(def)
                if not modelKind then handle.active=false;return nil,"model_display_unavailable" end
                local model = handle.object
                if model.ClearModel then model:ClearModel() end
                model:SetSize(visual.width or 64, visual.height or 64)
                handle.loaded = false; handle.owner = session
                model:SetScript("OnModelLoaded", function()
                    if handle.active and handle.owner == session and not session.stopping and not handle.loaded then handle.loaded = true; self.modelLoaded = self.modelLoaded + 1 end
                end)
                local success
                if modelKind == "creatureDisplayID" and model.SetDisplayInfo then success = pcall(model.SetDisplayInfo, model, modelID)
                elseif modelKind == "fileID" and model.SetModel then success = pcall(model.SetModel, model, modelID) end
                if not success then model:Hide(); handle.active = false; self.modelFailed = self.modelFailed + 1; return nil, "model_load_call_failed" end
                if model.SetModelScale then pcall(model.SetModelScale, model, def.scale or 1) end
                if model.SetFacing then pcall(model.SetFacing, model, def.facing or 0) end
            else
                handle = acquire(cache.rects, function() return cache.canvas:CreateTexture(nil, "ARTWORK") end); kind = "rect"
                if not handle then return nil, "texture_pool_limit" end
                local color = visual.color or { .3, .75, .95, 1 }
                handle.object:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
            end
            handle.kind = kind;handle.animation=nil; handle.object:Show(); entity.view = handle
            if entity.role=="player" or entity.ai then
                entity.healthView=acquire(cache.health,function()return cache.overlay:CreateTexture(nil,"OVERLAY")end)
                if entity.healthView then entity.healthView.object:SetColorTexture(.2,.95,.35,1);entity.healthView.object:Show()end
            end
            return handle
        end
        function self.detach(entity)
            local h = entity.view
            if h then
                h.active = false; h.owner = nil; h.object:Hide()
                if h.kind == "model" then h.object:SetScript("OnModelLoaded", nil); if h.object.ClearModel then h.object:ClearModel() end end
                if h.kind=="scene_model" and h.object.SetPaused then h.object:SetPaused(true)end
                entity.view = nil
            end
            if entity.boundsView then entity.boundsView.object:Hide(); entity.boundsView.active = false; entity.boundsView = nil end
            if entity.healthView then entity.healthView.object:Hide();entity.healthView.active=false;entity.healthView=nil end
        end
        function self.setTerrain(rectangles)
            for _, h in ipairs(cache.terrain) do h.active = false; h.object:Hide() end
            self.terrain = rectangles or {}
            for _, rect in ipairs(self.terrain) do
                local h = acquire(cache.terrain, function() return cache.canvas:CreateTexture(nil, "BACKGROUND") end)
                if h then h.rect = rect; h.object:SetColorTexture(.19, .24, .29, 1); h.object:Show() end
            end
        end
        function self.render(world, alpha)
            local logicalWidth = config.viewport.width or 960
            local logicalHeight = config.viewport.height or 400
            local scale = math.min(cache.canvas:GetWidth() / logicalWidth, cache.canvas:GetHeight() / logicalHeight) * self.camera.zoom
            if scale <= 0 then return end
            local function place(object, x, y, w, h)
                object:SetPoint("BOTTOMLEFT", cache.canvas, "BOTTOMLEFT", (x - self.camera.x) * scale, (y - self.camera.y) * scale)
                object:SetSize(w * scale, h * scale)
            end
            self.drawn = 0
            local sceneActors=0
            if cache.scene then cache.scene:SetSize(logicalWidth*scale,logicalHeight*scale)end
            for _, h in ipairs(cache.terrain) do if h.active then local r = h.rect; place(h.object, r.x, r.y, r.w, r.h) end end
            for i = 1, #world.list do
                local e = world.list[i]; local h = e.view
                if h and not e.removed then
                    local x = e.previousX + (e.x - e.previousX) * alpha
                    local y = e.previousY + (e.y - e.previousY) * alpha
                    local isModel=h.kind=="model" or h.kind=="scene_model"
                    local w = isModel and (e.visual.width or 64) or e.w
                    local height = isModel and (e.visual.height or 64) or e.h
                    if x + w >= self.camera.x and x - w <= self.camera.x + logicalWidth and y + height >= self.camera.y and y <= self.camera.y + logicalHeight then
                        h.object:Show()
                        if h.kind=="scene_model" then
                            sceneActors=sceneActors+1;h.object:SetPosition(0,(logicalWidth/2-x+self.camera.x)/12,(y-self.camera.y)/12)
                        else place(h.object, x - w / 2, y, w, height)end
                        self.drawn = self.drawn + 1
                        if isModel then
                            if not h.loaded and h.object.GetModelFileID then
                                local ok, id = pcall(h.object.GetModelFileID, h.object)
                                if ok and type(id) == "number" and id > 0 then h.loaded = true; self.modelLoaded = self.modelLoaded + 1 end
                            end
                            if e.animation ~= h.animation and e.animation and h.object.SetAnimation then pcall(h.object.SetAnimation, h.object, e.animation); h.animation = e.animation end
                        end
                    else h.object:Hide() end
                    if e.healthView then
                        e.healthView.object:Show();place(e.healthView.object,x-e.w/2,y+height+3,math.max(.01,e.w*e.hp/e.maxHP),3)
                    end
                    if self.showBounds then
                        if not e.boundsView then e.boundsView = acquire(cache.bounds, function() return cache.overlay:CreateTexture(nil, "OVERLAY") end) end
                        if e.boundsView then e.boundsView.object:SetColorTexture(1, .25, .2, .22); e.boundsView.object:Show(); place(e.boundsView.object, e.x - e.w / 2, e.y, e.w, e.h) end
                    elseif e.boundsView then e.boundsView.object:Hide() end
                end
            end
            if cache.scene then if sceneActors>0 then cache.scene:Show()else cache.scene:Hide()end end
        end
        function self.button(text, fn)
            self.buttons = self.buttons + 1; local n = self.buttons
            if n > 24 then G.error("UI button budget exceeded") end
            local b = cache.buttons[n]
            if not b then b = G.CreateFrame("Button", nil, f, "UIPanelButtonTemplate"); cache.buttons[n] = b end
            local columns, buttonWidth = 8, (width - 32) / 8 - 4
            b:ClearAllPoints(); b:SetSize(buttonWidth, 25)
            b:SetPoint("TOPLEFT", 14 + ((n - 1) % columns) * (buttonWidth + 4), -67 - math.floor((n - 1) / columns) * 31)
            b:SetText(text); b:Show(); b:SetScript("OnClick", function() session.safe("ui", fn) end)
            return b
        end
        function self.notify(text) cache.message:SetText(tostring(text):sub(1, 600)) end
        function self.info(text) cache.info:SetText(text) end
        function self.status(text) cache.status:SetText(text) end
        function self.surface()
            if not self.gameSurface then
                self.gameSurface = E.newSurface(session, cache.canvas, cache.surface)
                cache.surface = self.gameSurface.cache
            end
            return self.gameSurface
        end
        function self.scene3d(options)
            if not self.gameScene3D then
                self.gameScene3D=E.newWoWScene3D(session,cache.canvas,options,cache.scene3D)
                cache.scene3D=self.gameScene3D.cache
            end
            return self.gameScene3D
        end
        function self.update()if self.gameSurface then self.gameSurface.update()end end
        function self.showLog(text)
            session.pause("log_viewer")
            cache.logHeader:SetText("日志：Ctrl+A / Ctrl+C 复制为 .ndjson；当前游戏暂停。")
            cache.apply:Hide(); cache.apply:SetScript("OnClick",nil)
            cache.logEdit:SetText(text or "暂无日志"); cache.logFrame:Show(); cache.logEdit:SetFocus(); cache.logEdit:HighlightText()
        end
        function self.prompt(title, initial, callback)
            session.pause("text_prompt"); cache.logHeader:SetText(title)
            cache.logEdit:SetText(initial or ""); cache.logFrame:Show(); cache.logEdit:SetFocus()
            cache.apply:Show(); cache.apply:SetScript("OnClick",function()
                local text=cache.logEdit:GetText(); cache.logEdit:ClearFocus(); cache.logFrame:Hide()
                cache.apply:Hide(); cache.apply:SetScript("OnClick",nil); session.safe("prompt",callback,text)
            end)
        end
        function self.stats()
            local rects, models, loaded, actors = 0, 0, 0, 0
            for _, h in ipairs(cache.rects) do if h.active then rects = rects + 1 end end
            for _, h in ipairs(cache.models) do if h.active then models = models + 1; if h.loaded then loaded = loaded + 1 end end end
            for _, h in ipairs(cache.actors)do if h.active then actors=actors+1;if h.loaded then loaded=loaded+1 end end end
            local result = { visible = self.drawn, activeTextures = rects, activeModels = models+actors, activePlayerModels=models, activeActors=actors, loadedModels = loaded,
                failedModels = self.modelFailed, pooledTextures = #cache.rects, pooledModels = #cache.models,
                pooledTerrain = #cache.terrain, pooledBounds = #cache.bounds, pooledActors=#cache.actors, pooledHealthBars=#cache.health, createdRenderObjects = cache.created }
            if self.gameSurface then for key,value in pairs(self.gameSurface.stats())do result[key]=value end end
            if self.gameScene3D then for key,value in pairs(self.gameScene3D.stats())do result[key]=value end end
            return result
        end
        function self.hide()
            self.hiding=true
            if cache.escapeProxy then cache.escapeProxy:Hide()end
            f:SetScript("OnUpdate", nil); f:StopMovingOrSizing(); f:Hide();self.hiding=false
        end
        function self.suspend()
            self.hiding=true;f:StopMovingOrSizing();cache.logEdit:ClearFocus();cache.logFrame:Hide()
            f:Hide();if cache.escapeProxy then cache.escapeProxy:Hide()end;self.hiding=false
        end
        function self.show()
            f:Show();if cache.escapeProxy then cache.escapeProxy:Show()end
        end
        function self.dispose()
            if cache.escapeProxy then cache.escapeProxy:SetScript("OnHide",nil);cache.escapeProxy:Hide()end
            if self.gameSurface then self.gameSurface.dispose() end
            if self.gameScene3D then self.gameScene3D.dispose() end
            f:SetScript("OnUpdate", nil); f:SetScript("OnHide", nil)
            f:SetScript("OnKeyDown", nil); f:SetScript("OnKeyUp", nil)
            cache.close:SetScript("OnClick", nil)
            cache.apply:SetScript("OnClick",nil); cache.apply:Hide()
            for _, b in ipairs(cache.buttons) do b:Hide(); b:SetScript("OnClick", nil) end
            cache.logEdit:ClearFocus(); cache.logEdit:SetText(""); cache.logFrame:Hide(); f:Hide()
            if cache.scene then cache.scene:Hide()end
            self.setTerrain({})
        end
        -- WoW's Escape handler resolves UISpecialFrames entries through _G.
        -- A proxy lets a game handle Escape without WoW first hiding the game window.
        local escapeName = "TRP3_ItemGameWindow"
        if type(G.UISpecialFrames) == "table" then
            if not cache.escapeProxy then
                cache.escapeProxy=G.CreateFrame("Frame",nil,G.UIParent)
                cache.escapeProxy:SetSize(1,1);cache.escapeProxy:EnableMouse(false)
            end
            cache.escapeProxy:SetScript("OnHide",function()
                if session.stopping or self.hiding then return end
                session.requestClose("escape")
                if not session.stopping and f:IsShown()then cache.escapeProxy:Show()end
            end)
            cache.escapeProxy:Show();G[escapeName] = cache.escapeProxy
            local registered = false
            for _, name in ipairs(G.UISpecialFrames) do if name == escapeName then registered = true; break end end
            if not registered then G.UISpecialFrames[#G.UISpecialFrames + 1] = escapeName end
        end
        return self
    end
end
