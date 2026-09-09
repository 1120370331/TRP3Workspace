-- Bounded 2D texture particles. Simulation follows session time; rendering is
-- interpolated on the existing runtime frame and never installs another OnUpdate.
return function(E, G)
    local floor, max, min = math.floor, math.max, math.min
    local cos, sin, pi = math.cos, math.sin, math.pi
    local pcall = G.pcall
    local DEG = pi / 180
    local UL,LL,UR,LR=G.UPPER_LEFT_VERTEX or 1,G.LOWER_LEFT_VERTEX or 2,G.UPPER_RIGHT_VERTEX or 3,G.LOWER_RIGHT_VERTEX or 4
    local LAYER_STRIDE, PARTICLE_OFFSET = 288, 160

    local function range(value, random, fallback)
        if value == nil then return fallback end
        if type(value) == "table" then
            local a, b = value[1], value[2] or value[1]
            return a + (b - a) * random()
        end
        return value
    end

    local function color(value, fallback, out)
        value = value or fallback
        out = out or {}
        out[1],out[2],out[3],out[4]=value[1],value[2],value[3],value[4] == nil and 1 or value[4]
        return out
    end

    local function seedValue(value)
        local text = tostring(value or 1)
        local seed = 1
        for i = 1, #text do seed = (seed * 131 + text:byte(i)) % 2147483647 end
        return max(1, seed)
    end

    local function newRandom(seed)
        local state = seedValue(seed)
        return function()
            state = (state * 48271) % 2147483647
            return state / 2147483647
        end
    end

    function E.newEffects(session, view)
        local content = session.content
        local definitions = content.effects or {}
        local limits = content.limits or {}
        local capacity = limits.maxParticles or 128
        local emitterCapacity = limits.maxEmitters or 24
        local spawnStepCapacity = limits.maxParticleSpawnsPerStep or 32
        local width, height = content.viewport.width, content.viewport.height
        local assets = (content.assets or {}).textures or {}
        local cache = E.effectsViewCache
        if not cache then
            local root = G.CreateFrame("Frame", nil, view.canvas)
            cache = { root = root, layers = {}, pool = {}, created = 0 }
            E.effectsViewCache = cache
        end
        local root = cache.root
        root:SetParent(view.canvas); root:ClearAllPoints(); root:SetPoint("TOPLEFT", view.canvas, "TOPLEFT", 0, 0)
        root:SetSize(width, height); root:EnableMouse(false); root:Show()
        if root.SetClipsChildren then root:SetClipsChildren(false) end

        local particles, emitters, counts, free = {}, {}, {}, {}
        for i=#cache.pool,1,-1 do free[#free+1]=cache.pool[i] end
        local sequence, nextEmitter = 0, 0
        local spawned, dropped, evicted, peak, visibleCount = 0, 0, 0, 0, 0
        local budgetTick, budgetFrame, stepSpawns, frameSpawns = -1, -1, 0, 0
        local lastScale
        local unavailable = {}
        local self = { particles = particles, emitters = emitters }

        local function optional(object, method, ...)
            if object and object[method] then return pcall(object[method], object, ...) end
            return false
        end

        local function layer(z)
            local frame = cache.layers[z]
            if not frame then
                frame = G.CreateFrame("Frame", nil, root)
                frame:SetAllPoints(root); frame:EnableMouse(false)
                cache.layers[z] = frame
            end
            local level=root:GetFrameLevel() + z * LAYER_STRIDE + PARTICLE_OFFSET
            if frame:GetFrameLevel()~=level then frame:SetFrameLevel(level)end
            if not frame:IsShown()then frame:Show()end
            return frame
        end

        local function acquire(z)
            local handle=free[#free];free[#free]=nil
            if not handle then
                -- The retained pool is bounded by the highest configured capacity
                -- used in this engine session; Lua cannot destroy UI regions.
                if #cache.pool >= 512 then return nil end
                local frame = G.CreateFrame("Frame", nil, layer(z))
                frame:EnableMouse(false)
                local texture = frame:CreateTexture(nil, "ARTWORK")
                texture:SetAllPoints(frame)
                handle = { frame = frame, texture = texture, particle = {}, rotate = texture.SetRotation }
                cache.pool[#cache.pool + 1] = handle; cache.created = cache.created + 1
                optional(texture, "SetSnapToPixelGrid", false)
                optional(texture, "SetTexelSnappingBias", 0)
            end
            local parent = layer(z)
            handle.active = true; handle.visible = false; handle.parent=parent;handle.frame:SetParent(parent)
            handle.frame:SetFrameLevel(parent:GetFrameLevel() + 1)
            handle.frame:ClearAllPoints();handle.frame:Hide(); handle.texture:Show()
            handle.x,handle.y,handle.size,handle.rotation,handle.alpha=nil,nil,nil,nil,nil
            return handle
        end

        local function configure(handle, effect)
            local asset = assets[effect.texture]
            if not asset then return false end
            local signature = effect.texture .. ":" .. tostring(effect.blend or "BLEND")..":"..(effect.shape or "sprite")
            if handle.signature == signature then return true end
            local ok, result
            if asset.kind == "atlas" and handle.texture.SetAtlas then
                ok, result = pcall(handle.texture.SetAtlas, handle.texture, asset.atlas, false)
            else
                ok, result = pcall(handle.texture.SetTexture, handle.texture, asset.id or asset.path, "CLAMP", "CLAMP")
            end
            if not ok or result == false then
                if not unavailable[effect.texture] then
                    unavailable[effect.texture] = true
                    session.perf.note("particle.asset_unavailable", { asset = effect.texture })
                end
                pcall(handle.texture.SetTexture, handle.texture, asset.fallbackPath or "Interface\\Cooldown\\star4", "CLAMP", "CLAMP")
            end
            handle.texture:SetBlendMode(effect.blend or "BLEND")
            if handle.facet then handle.facet:Hide()end
            if handle.crystal and handle.texture.SetVertexOffset then
                for _,vertex in ipairs({UL,LL,UR,LR})do handle.texture:SetVertexOffset(vertex,0,0)end
            end
            handle.crystal=effect.shape=="crystal" and handle.texture.SetVertexOffset~=nil
            if handle.crystal then
                if not handle.facet then handle.facet=handle.frame:CreateTexture(nil,"ARTWORK");handle.facet:SetAllPoints(handle.frame)end
                handle.facet:SetTexture(asset.id or asset.path,"CLAMP","CLAMP")
                handle.facet:SetBlendMode(effect.blend or "BLEND");handle.facet:Show()
                if handle.rotate then handle.rotate(handle.texture,0)end
            end
            if handle.maskApplied then handle.texture:RemoveMaskTexture(handle.mask);handle.maskApplied=false end
            if asset.maskPath and handle.frame.CreateMaskTexture then
                if not handle.mask then handle.mask=handle.frame:CreateMaskTexture(nil,"ARTWORK");handle.mask:SetAllPoints(handle.texture)end
                handle.mask:SetTexture(asset.maskPath,"CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
                handle.texture:AddMaskTexture(handle.mask);handle.maskApplied=true
            end
            if asset.kind ~= "atlas" then handle.texture:SetTexCoord(0, 1, 0, 1) end
            handle.signature = signature; handle.cell = nil; handle.atlas = asset.kind == "atlas"
            return true
        end

        local function releaseAt(index)
            local particle = particles[index]
            if not particle then return end
            counts[particle.effectId] = max(0, (counts[particle.effectId] or 1) - 1)
            if particle.handle then
                particle.handle.frame:Hide(); particle.handle.texture:Hide()
                particle.handle.active = false; particle.handle.visible = false
                free[#free+1]=particle.handle;particle.handle = nil
            end
            particles[index] = particles[#particles]; particles[#particles] = nil
        end

        local function noteDropped(amount)
            amount = amount or 1; dropped = dropped + amount
            session.perf.increment("particlesDropped", amount)
        end

        local function makeRoom(priority)
            if #particles < capacity then return true end
            local candidate, candidatePriority, candidateBirth
            for i = 1, #particles do
                local particle = particles[i]
                if not candidatePriority or particle.priority < candidatePriority or
                    (particle.priority == candidatePriority and particle.birth < candidateBirth) then
                    candidate, candidatePriority, candidateBirth = i, particle.priority, particle.birth
                end
            end
            if candidate and priority > candidatePriority then
                releaseAt(candidate);evicted=evicted+1;session.perf.increment("particlesEvicted");return true
            end
            noteDropped(); return false
        end

        local function resolveOrigin(params, fallbackSpace)
            params = params or {}
            local space = params.space or fallbackSpace or "screen"
            local x, y = params.x or 0, params.y or 0
            if params.entityId then
                local entity = session.world and session.world.byId[params.entityId]
                if not entity or entity.removed then return nil, nil, nil, "entity_unavailable" end
                x = entity.x + (params.x or 0); y = entity.y + (params.y or 0); space = "world"
            end
            if not E.util.finite(x) or not E.util.finite(y) or (space ~= "screen" and space ~= "world") then
                return nil, nil, nil, "invalid_origin"
            end
            return x, y, space
        end

        local function validateParams(params)
            if type(params)~="table"then return false,"invalid_params"end
            for _,key in ipairs({"x","y"})do if params[key]~=nil and (not E.util.finite(params[key])or math.abs(params[key])>100000)then return false,"invalid_origin"end end
            if params.layer ~= nil and (not E.util.finite(params.layer) or params.layer < 0 or params.layer > 30 or params.layer ~= floor(params.layer)) then return false, "invalid_layer" end
            if params.scale ~= nil and (not E.util.finite(params.scale) or params.scale <= 0 or params.scale > 20) then return false, "invalid_scale" end
            if params.facing ~= nil and params.facing ~= 1 and params.facing ~= -1 then return false, "invalid_facing" end
            if params.color ~= nil then
                if type(params.color) ~= "table" then return false, "invalid_color" end
                for i = 1, 4 do if not E.util.finite(params.color[i]) or params.color[i] < 0 or params.color[i] > 1 then return false, "invalid_color" end end
            end
            return true
        end

        local function spawnOne(effectId, effect, params, random, emitterId, originX, originY, space)
            if budgetTick~=session.tick then budgetTick=session.tick;stepSpawns=0 end
            if budgetFrame~=session.frameSerial then budgetFrame=session.frameSerial;frameSpawns=0 end
            if stepSpawns>=spawnStepCapacity or frameSpawns>=spawnStepCapacity*2 then noteDropped();return false end
            local priority = effect.priority or 0
            if effect.maxAlive and (counts[effectId] or 0) >= effect.maxAlive then noteDropped(); return false end
            if not makeRoom(priority) then return false end
            local z = params.layer or effect.layer or 0
            local handle = acquire(z)
            if not handle then noteDropped(); return false end
            if not configure(handle, effect) then handle.active = false;handle.frame:Hide();free[#free+1]=handle;noteDropped(); return false end

            local direction = range(effect.directionDeg, random, 0)
            local spread = range(effect.spreadDeg, random, 0)
            direction = (direction + (random() - .5) * spread) * DEG
            local speed = range(effect.speed, random, 0)
            local facing = params.facing == -1 and -1 or 1
            local vx = cos(direction) * speed * facing
            local vy = sin(direction) * speed
            if space == "screen" then vy = -vy end
            local gravity = range(effect.gravity, random, 0)
            local rawSize=range(effect.startSize, random, 8)
            local startSize = rawSize * (params.scale or 1)
            local endSize = range(effect.endSize, random, rawSize) * (params.scale or 1)
            local particle=handle.particle
            local startColor = color(params.color or effect.startColor, {1, 1, 1, 1},particle.startColor)
            local endColor = color(params.color or effect.endColor, startColor,particle.endColor)
            local startAlpha = range(effect.startAlpha, random, 1)
            local endAlpha = range(effect.endAlpha, random, 0)
            local x = originX + range(effect.offsetX, random, 0) * facing
            local y = originY + range(effect.offsetY, random, 0)
            sequence = sequence + 1
            particle.effectId,particle.effect,particle.emitterId,particle.handle=effectId,effect,emitterId,handle
            particle.x,particle.y,particle.previousX,particle.previousY,particle.vx,particle.vy=x,y,x,y,vx,vy
            particle.gravity,particle.wind,particle.drag=gravity,range(effect.wind,random,0),range(effect.drag,random,0)
            particle.age=-range(effect.delay,random,0);particle.previousAge=particle.age;particle.life=range(effect.lifetime,random,.5)
            particle.startSize,particle.endSize,particle.startColor,particle.endColor=startSize,endSize,startColor,endColor
            particle.startAlpha,particle.endAlpha=startAlpha,endAlpha
            particle.rotation,particle.spin=range(effect.startRotationDeg,random,0)*DEG,range(effect.spinDeg,random,0)*DEG
            if effect.alignToVelocity then particle.rotation=particle.rotation+(facing==-1 and pi-direction or direction)-pi/2 end
            particle.space,particle.layer,particle.layerFrame,particle.priority,particle.birth=space,z,handle.parent,priority,sequence
            particle.aspect=effect.aspectRatio or 1;particle.fadeIn=effect.fadeIn or 0
            particle.previousRotation = particle.rotation
            particles[#particles + 1] = particle
            counts[effectId] = (counts[effectId] or 0) + 1
            stepSpawns=stepSpawns+1;frameSpawns=frameSpawns+1;peak=max(peak,#particles)
            spawned = spawned + 1; session.perf.increment("particlesSpawned")
            return true
        end

        local function spawnMany(effectId, effect, params, count, random, emitterId, x, y, space)
            local made = 0
            for _ = 1, count do if spawnOne(effectId, effect, params, random, emitterId, x, y, space) then made = made + 1 end end
            return made
        end

        function self.burst(effectId, params)
            if session.stopping then return nil, "stopped" end
            local effect = definitions[effectId]
            if not effect then return nil, "unknown_effect" end
            params = params or {}
            local valid, invalid = validateParams(params); if not valid then return nil, invalid end
            local x, y, space, why = resolveOrigin(params, effect.space)
            if not x then return nil, why end
            local count = params.count or effect.count or effect.initialBurst or 1
            if not E.util.finite(count) or count < 1 or count > 128 or count ~= floor(count) then return nil, "invalid_count" end
            local before = dropped
            local random = newRandom(params.seed or (session.tick .. ":" .. effectId .. ":" .. (sequence + 1)))
            local made = spawnMany(effectId, effect, params, count, random, nil, x, y, space)
            return made, dropped - before
        end

        local function removeEmitterAt(index)
            emitters[index] = emitters[#emitters]; emitters[#emitters] = nil
        end

        function self.start(effectId, params)
            if session.stopping then return nil, "stopped" end
            local effect = definitions[effectId]
            if not effect then return nil, "unknown_effect" end
            if effect.mode ~= "continuous" then return nil, "effect_not_continuous" end
            if #emitters >= emitterCapacity then return nil, "emitter_budget_exceeded" end
            params = params or {}
            local valid, invalid = validateParams(params); if not valid then return nil, invalid end
            local x, y, space, why = resolveOrigin(params, effect.space)
            if not x then return nil, why end
            local rate = params.rate or effect.rate
            local duration = params.duration
            if duration == nil then duration = effect.duration end
            if not E.util.finite(rate) or rate <= 0 or rate > 512 then return nil, "invalid_rate" end
            if duration ~= nil and (not E.util.finite(duration) or duration <= 0 or duration > 3600) then return nil, "invalid_duration" end
            nextEmitter = nextEmitter + 1
            local emitter = { id = nextEmitter, effectId = effectId, effect = effect, params = params,
                rate = rate, duration = duration, age = 0, accumulator = 0,
                random = newRandom(params.seed or (session.tick .. ":emitter:" .. nextEmitter)), x = x, y = y, space = space }
            emitters[#emitters + 1] = emitter
            local initial = params.initialBurst
            if initial == nil then initial = effect.initialBurst or 0 end
            if E.util.finite(initial) and initial > 0 and initial <= 128 and initial == floor(initial) then
                spawnMany(effectId, effect, params, initial, emitter.random, emitter.id, x, y, space)
            end
            return emitter.id
        end

        function self.stop(emitterId, immediate)
            local found = false
            for i = #emitters, 1, -1 do
                if emitters[i].id == emitterId then removeEmitterAt(i); found = true; break end
            end
            if immediate then
                for i = #particles, 1, -1 do if particles[i].emitterId == emitterId then releaseAt(i) end end
            end
            return found
        end

        function self.clear()
            for i = #particles, 1, -1 do releaseAt(i) end
            for i = #emitters, 1, -1 do emitters[i] = nil end
            visibleCount=0
        end

        function self.update(dt)
            if session.stopping then return end
            for i = #particles, 1, -1 do
                local particle = particles[i]
                particle.previousX, particle.previousY = particle.x, particle.y
                particle.previousAge, particle.previousRotation = particle.age, particle.rotation
                particle.age = particle.age + dt
                if particle.age >= particle.life then
                    releaseAt(i)
                elseif particle.age>0 then
                    local activeDt=min(dt,particle.age)
                    local damping = max(0, 1 - particle.drag * activeDt)
                    particle.vx = (particle.vx + particle.wind * activeDt) * damping
                    local gravity = particle.space == "screen" and particle.gravity or -particle.gravity
                    particle.vy = (particle.vy + gravity * activeDt) * damping
                    particle.x = particle.x + particle.vx * activeDt
                    particle.y = particle.y + particle.vy * activeDt
                    particle.rotation = particle.rotation + particle.spin * activeDt
                end
            end
            -- Reclaim expired slots before continuous emitters allocate this
            -- step, avoiding artificial drops when a steady-state pool is full.
            for i = #emitters, 1, -1 do
                local emitter = emitters[i]
                local emitDt=emitter.duration and min(dt,max(0,emitter.duration-emitter.age))or dt
                emitter.age = emitter.age + dt
                local x, y, space = resolveOrigin(emitter.params, emitter.effect.space)
                if not x then
                    removeEmitterAt(i)
                else
                    emitter.x, emitter.y, emitter.space = x, y, space
                    emitter.accumulator = emitter.accumulator + emitter.rate * emitDt
                    local count = floor(emitter.accumulator)
                    if count > 0 then
                        emitter.accumulator = emitter.accumulator - count
                        if count > spawnStepCapacity then noteDropped(count - spawnStepCapacity); count = spawnStepCapacity end
                        spawnMany(emitter.effectId, emitter.effect, emitter.params, count, emitter.random, emitter.id, x, y, space)
                    end
                    if emitter.duration and emitter.age>=emitter.duration then removeEmitterAt(i)end
                end
            end
        end

        local function mix(a, b, t) return a + (b - a) * t end
        -- Two native, degenerate quads form a diamond with a lit facet.
        -- Coordinates are UI units, positive Y up. No round mask/glow texture.
        local function crystal(handle,w,h,rotation)
            local c,s=cos(rotation),sin(rotation)
            local tx,ty=-s*h*.5,c*h*.5
            local lx,ly=-c*w*.5,-s*w*.5
            local rx,ry=-lx,-ly
            local bx,by=-tx,-ty
            local left,right=handle.texture,handle.facet
            left:SetVertexOffset(UL,tx+w*.5,ty-h*.5)
            left:SetVertexOffset(LL,lx+w*.5,ly+h*.5)
            left:SetVertexOffset(UR,tx-w*.5,ty-h*.5)
            left:SetVertexOffset(LR,bx-w*.5,by+h*.5)
            right:SetVertexOffset(UL,tx+w*.5,ty-h*.5)
            right:SetVertexOffset(LL,bx+w*.5,by+h*.5)
            right:SetVertexOffset(UR,rx-w*.5,ry-h*.5)
            right:SetVertexOffset(LR,bx-w*.5,by+h*.5)
        end
        function self.render(alpha)
            if session.stopping then return end
            visibleCount=0
            if #particles==0 then return end
            local canvasHeight=view.canvas:GetHeight()
            local scale = max(.1, min(view.canvas:GetWidth() / width, canvasHeight / height))
            local displayHeight=canvasHeight/scale
            if lastScale ~= scale then root:SetScale(scale); lastScale = scale end
            local camera = view.camera or { x = 0, y = 0, zoom = 1 }
            for i = 1, #particles do
                local particle = particles[i]
                local age = mix(particle.previousAge, particle.age, alpha)
                local progress = E.util.clamp(age / particle.life, 0, 1)
                local x = mix(particle.previousX, particle.x, alpha)
                local y = mix(particle.previousY, particle.y, alpha)
                local size = mix(particle.startSize, particle.endSize, progress)
                if particle.space == "world" then
                    x = (x - camera.x) * camera.zoom
                    y = displayHeight - (y - camera.y) * camera.zoom
                    size = size * camera.zoom
                end
                local handle = particle.handle
                local radius=size*max(1,particle.aspect)
                local visible = age>=0 and x + radius >= 0 and x - radius <= width and y + radius >= 0 and y - radius <= displayHeight
                if visible then
                    visibleCount=visibleCount+1
                    if handle.x~=x or handle.y~=y then handle.frame:SetPoint("CENTER", particle.layerFrame, "TOPLEFT", x, -y);handle.x,handle.y=x,y end
                    if handle.size~=size then handle.frame:SetSize(max(.01,size*particle.aspect),max(.01,size));handle.size=size end
                    local c0, c1 = particle.startColor, particle.endColor
                    local a = mix(particle.startAlpha, particle.endAlpha, progress) * mix(c0[4], c1[4], progress)
                    if particle.fadeIn>0 then a=a*min(1,age/particle.fadeIn)end
                    local r,g,b=mix(c0[1],c1[1],progress),mix(c0[2],c1[2],progress),mix(c0[3],c1[3],progress)
                    handle.texture:SetVertexColor(r,g,b,a)
                    local rotation=mix(particle.previousRotation,particle.rotation,alpha)
                    if handle.crystal then
                        crystal(handle,size*particle.aspect,size,rotation)
                        handle.facet:SetVertexColor(min(1,r*.45+.55),min(1,g*.45+.55),min(1,b*.45+.55),a)
                    elseif handle.rotate and handle.rotation~=rotation then handle.rotate(handle.texture,rotation);handle.rotation=rotation end
                    local flipbook = particle.effect.flipbook
                    if flipbook then
                        local frame = floor(age * flipbook.fps) % flipbook.frames
                        if handle.cell ~= frame then
                            local column, row = frame % flipbook.columns, floor(frame / flipbook.columns)
                            handle.texture:SetTexCoord(column / flipbook.columns, (column + 1) / flipbook.columns,
                                row / flipbook.rows, (row + 1) / flipbook.rows)
                            handle.cell = frame
                        end
                    elseif handle.cell ~= nil and not handle.atlas then handle.texture:SetTexCoord(0, 1, 0, 1); handle.cell = nil end
                    if not handle.visible then handle.frame:Show(); handle.texture:Show(); handle.visible = true end
                else
                    if handle.visible then handle.frame:Hide(); handle.visible = false end
                end
            end
        end

        function self.stats()
            return { activeParticles = #particles, activeEmitters = #emitters,
                pooledParticles = #cache.pool, particleCapacity = capacity,
                spawnedParticles = spawned, droppedParticles = dropped, evictedParticles=evicted,
                peakParticles=peak, visibleParticles=visibleCount }
        end

        function self.dispose()
            self.clear(); root:Hide()
            for _, frame in pairs(cache.layers) do frame:Hide() end
        end
        return self
    end
end
