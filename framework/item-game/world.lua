return function(E, G)
    local abs, min, max = math.abs, math.min, math.max
    function E.overlap(a, b) return a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y end
    function E.sweep(a, dx, dy, b)
        if E.overlap(a, b) then return 0 end
        local entry, exit = 0, 1
        local function axis(p, size, delta, low, extent)
            if delta == 0 then return p + size >= low and p <= low + extent end
            local first, last = (low - p - size) / delta, (low + extent - p) / delta
            if first > last then first, last = last, first end
            entry = max(entry, first); exit = min(exit, last)
            return entry <= exit
        end
        if axis(a.x, a.w, dx, b.x, b.w) and axis(a.y, a.h, dy, b.y, b.h) and entry >= 0 and entry <= 1 then return entry end
        return nil
    end
    function E.newWorld(session)
        local self = { list = {}, byId = {}, nextId = 0, attackId = 0, terrain = {}, mode = "grid", gridDirty = true, grid = {}, usedCells = {}, queryStamp = 0, queryBuffer = {}, candidateCount = 0, contacts = 0 }
        local data, events, perf = session.content, session.events, session.perf
        local function updateBox(e) e.box.x = e.x - e.w / 2; e.box.y = e.y; e.box.w = e.w; e.box.h = e.h end
        function self.spawn(prefabId, position, overrides)
            local def = data.prefabs[prefabId]
            if not def then G.error("Unknown prefab: " .. tostring(prefabId)) end
            if #self.list >= (data.limits.maxEntities or 1200) then G.error("entity budget exceeded") end
            position = position or {x=0,y=0}
            if not E.util.finite(position.x) or not E.util.finite(position.y) or abs(position.x) > 100000 or abs(position.y) > 100000 then G.error("invalid entity position") end
            self.nextId = self.nextId + 1
            local e = { id = self.nextId, prefabId = prefabId, x = position.x, y = position.y, previousX = position.x, previousY = position.y,
                w = def.width or 16, h = def.height or 16, vx = def.vx or 0, vy = def.vy or 0,
                hp = def.health or 100, maxHP = def.health or 100, role = def.role, faction = def.faction or "neutral",
                motion = def.motion or "static", visual = def.visual or {}, speed = def.speed or 180,
                jumpSpeed = def.jumpSpeed or 330, gravity = def.gravity or 850, facing = 1, intent = {}, box = {},
                ai = def.ai, ttl = def.ttl, spawnedAt = session.time, projectile = def.projectile == true,
                damage = def.damage or 1, allowedActions = def.actions, invulnerability = def.invulnerability or .06,
                animation = def.animation, wrap = def.wrap, removed = false, beforeBox = {}, sweepBox = {} }
            for _, k in ipairs({"vx", "vy", "faction", "damage", "sourceId", "ttl"}) do if overrides and overrides[k] ~= nil then e[k] = overrides[k] end end
            updateBox(e); self.list[#self.list + 1] = e; self.byId[e.id] = e; self.gridDirty=true
            local handle, reason = session.view.attach(e)
            if not handle then perf.increment("renderAttachmentFailures"); perf.note("capability", { feature = "render", prefab = prefabId, reason = reason }) end
            return e.id
        end
        function self.despawn(id)
            local e = self.byId[id]; if not e or e.removed then return false end
            e.removed = true; self.byId[id] = nil; self.gridDirty=true; session.view.detach(e); return true
        end
        function self.cleanup()
            local n = 1
            for i = 1, #self.list do local e = self.list[i]; if not e.removed then self.list[n] = e; n = n + 1 end end
            for i = #self.list, n, -1 do self.list[i] = nil end
        end
        function self.clear()
            for i = 1, #self.list do self.despawn(self.list[i].id) end
            self.list = {}; self.byId = {}; self.terrain = {}; self.grid = {}; self.usedCells = {}; self.queryBuffer = {}; self.gridDirty=true
            session.view.setTerrain({})
        end
        function self.loadLevel(id)
            local level = data.levels[id]; if not level then G.error("Unknown level: " .. tostring(id)) end
            self.clear(); self.levelId = id; self.terrain = E.util.copy(level.terrain or {})
            session.view.setTerrain(self.terrain)
            for _, spawn in ipairs(level.spawns or {}) do self.spawn(spawn.prefab, spawn) end
            return true
        end
        function self.setIntent(id, intent)
            local e = self.byId[id]; if not e or e.hp <= 0 then return false, "entity_unavailable" end
            if intent.moveX ~= nil then e.intent.moveX = E.util.clamp(tonumber(intent.moveX) or 0, -1, 1) end
            if intent.jumpPressed then e.intent.jumpPressed = true end
            return true
        end
        function self.requestAction(id, actionId)
            local e, def = self.byId[id], data.actions[actionId]
            if not e or e.hp <= 0 or e.removed then return false, "entity_unavailable" end
            if not def then return false, "unknown_action" end
            if e.allowedActions then
                local allowed = false; for _, a in ipairs(e.allowedActions) do if a == actionId then allowed = true end end
                if not allowed then return false, "action_not_allowed" end
            end
            if e.action then return false, "busy" end
            self.attackId = self.attackId + 1
            e.action = { id = self.attackId, def = def, start = session.time, last = session.time, hits = {}, active = false, box = {} }
            events.emit("combat.action", { sourceId = id, action = actionId, attackId = self.attackId, tick = session.tick })
            return true
        end
        function self.updateAI()
            local player
            for i = 1, #self.list do local e = self.list[i]; if e.role == "player" and e.hp > 0 then player = e; break end end
            if not player then return end
            for i = 1, #self.list do
                local e = self.list[i]
                if e.ai and e.hp > 0 and session.time >= (e.nextDecision or 0) then
                    e.nextDecision = session.time + (e.ai.interval or .2)
                    local dx = player.x - e.x; e.facing = dx >= 0 and 1 or -1
                    self.setIntent(e.id, { moveX = abs(dx) > (e.ai.range or 48) and e.facing or 0 })
                    if abs(dx) <= (e.ai.range or 48) and abs(player.y - e.y) < 70 then self.requestAction(e.id, e.ai.action or "slash") end
                    perf.increment("aiDecisions")
                end
            end
        end
        function self.updateActions(dt)
            local count = #self.list
            for i = 1, count do
                local e, a = self.list[i], self.list[i].action
                if a then
                    local age = session.time - a.start; local d = a.def
                    local activeFrom, activeTo = d.windup or 0, (d.windup or 0) + (d.active or .1)
                    a.active = age >= activeFrom and a.last - a.start < activeTo
                    if a.active and d.projectile and not a.fired then
                        a.fired = true
                        self.spawn(d.projectile, { x = e.x + e.facing * (e.w / 2 + 12), y = e.y + e.h * .5 },
                            { vx = e.facing * (d.projectileSpeed or 600), faction = e.faction, sourceId = e.id, damage = d.damage or 5 })
                    end
                    a.finished = age >= activeTo + (d.recovery or .15)
                    a.last = session.time
                end
            end
        end
        function self.move(dt)
            for i = 1, #self.list do
                local e = self.list[i]
                e.previousX, e.previousY = e.x, e.y
                if e.ttl and session.time - e.spawnedAt >= e.ttl then self.despawn(e.id)
                elseif not e.removed then
                    if e.motion == "dynamic" and e.hp > 0 then
                        local movement = e.intent.moveX or 0
                        if movement ~= 0 then e.facing = movement > 0 and 1 or -1 end
                        e.vx = movement * e.speed + (e.knockbackX or 0)
                        e.knockbackX = (e.knockbackX or 0) * max(0, 1 - dt * 10)
                        if e.intent.jumpPressed and e.grounded then e.vy = e.jumpSpeed; e.grounded = false end
                        e.intent.jumpPressed = false; e.vy = e.vy - e.gravity * dt
                    end
                    if e.motion ~= "static" then
                        local dx, dy = e.vx * dt, e.vy * dt
                        if e.motion == "dynamic" then
                            for _, r in ipairs(self.terrain) do
                                if e.y + e.h > r.y and e.y < r.y + r.h then
                                    if dx > 0 and e.x + e.w / 2 <= r.x and e.x + e.w / 2 + dx >= r.x then dx = min(dx, r.x - e.x - e.w / 2) end
                                    if dx < 0 and e.x - e.w / 2 >= r.x + r.w and e.x - e.w / 2 + dx <= r.x + r.w then dx = max(dx, r.x + r.w - e.x + e.w / 2) end
                                end
                            end
                            e.x = e.x + dx; e.grounded = false
                            for _, r in ipairs(self.terrain) do
                                if e.x + e.w / 2 > r.x and e.x - e.w / 2 < r.x + r.w then
                                    if dy <= 0 and e.y >= r.y + r.h - .001 and e.y + dy <= r.y + r.h then dy = max(dy, r.y + r.h - e.y); e.vy = 0; e.grounded = true end
                                    if dy > 0 and e.y + e.h <= r.y and e.y + e.h + dy >= r.y then dy = min(dy, r.y - e.y - e.h); e.vy = 0 end
                                end
                            end
                            e.y = e.y + dy
                        else e.x = e.x + dx; e.y = e.y + dy end
                        if e.wrap then
                            local width, height = data.viewport.width, data.viewport.height
                            if e.x < 0 or e.x > width then e.x = e.x % width; e.previousX = e.x end
                            if e.y < 25 or e.y > height - e.h then e.y = 25 + (e.y - 25) % (height - e.h - 25); e.previousY = e.y end
                        elseif e.x < -300 or e.x > data.viewport.width + 300 or e.y < -300 then self.despawn(e.id) end
                    end
                    if e.x~=e.previousX or e.y~=e.previousY then self.gridDirty=true end
                    updateBox(e)
                end
            end
        end
        function self.rebuildGrid()
            if not self.gridDirty then return end
            self.gridDirty=false
            for _, bucket in ipairs(self.usedCells) do bucket.n = 0 end
            self.usedCells = {}
            if self.mode == "naive" then return end
            for _, e in ipairs(self.list) do
                if not e.removed and not e.projectile and e.hp > 0 then
                    local b = e.box
                    for x = math.floor(b.x / 96), math.floor((b.x + b.w) / 96) do
                        for y = math.floor(b.y / 96), math.floor((b.y + b.h) / 96) do
                            local key = x .. ":" .. y
                            local bucket = self.grid[key]
                            if not bucket then bucket = { n = 0, values = {} }; self.grid[key] = bucket end
                            if bucket.n == 0 then self.usedCells[#self.usedCells + 1] = bucket end
                            bucket.n = bucket.n + 1; bucket.values[bucket.n] = e
                        end
                    end
                end
            end
        end
        local function candidates(box)
            self.queryStamp = self.queryStamp + 1
            local out, n = self.queryBuffer, 0
            local function add(e)
                if not e.removed and not e.projectile and e.hp > 0 and e.queryStamp ~= self.queryStamp then
                    e.queryStamp = self.queryStamp; n = n + 1; out[n] = e
                end
            end
            if self.mode == "naive" then for _, e in ipairs(self.list) do add(e) end
            else
                for x = math.floor(box.x / 96), math.floor((box.x + box.w) / 96) do
                    for y = math.floor(box.y / 96), math.floor((box.y + box.h) / 96) do
                        local bucket = self.grid[x .. ":" .. y]
                        if bucket then for i = 1, bucket.n do add(bucket.values[i]) end end
                    end
                end
            end
            for i = #out, n + 1, -1 do out[i] = nil end
            self.candidateCount = self.candidateCount + n; return out
        end
        function self.query(box, faction)
            self.rebuildGrid(); local out = {}; local before=self.candidateCount
            for _, e in ipairs(candidates(box)) do if (not faction or e.faction == faction) and E.overlap(box, e.box) then out[#out + 1] = e.id end end
            perf.increment("queryCandidates",self.candidateCount-before)
            return out
        end
        local function hit(source, target, damage, attackId)
            if target.hp <= 0 or session.time < (target.invUntil or 0) then return false end
            target.hp = max(0, target.hp - damage); target.invUntil = session.time + target.invulnerability
            target.knockbackX = ((target.x >= source.x) and 1 or -1) * 50
            self.contacts = self.contacts + 1; perf.increment("hits")
            events.emit("combat.hit", { sourceId = source.sourceId or source.id, targetId = target.id, attackId = attackId, damage = damage, tick = session.tick })
            if target.hp == 0 then
                target.vx, target.vy, target.action = 0, 0, nil
                events.emit("entity.died", { sourceId = source.sourceId or source.id, targetId = target.id, attackId = attackId, tick = session.tick })
            end
            return true
        end
        function self.collide()
            self.candidateCount = 0; self.rebuildGrid()
            for _, e in ipairs(self.list) do
                if not e.removed then
                    if e.projectile then
                        local dx, dy = e.x - e.previousX, e.y - e.previousY
                        local before=e.beforeBox;before.x=e.previousX-e.w/2;before.y=e.previousY;before.w=e.w;before.h=e.h
                        local swept=e.sweepBox;swept.x=min(before.x,e.box.x);swept.y=min(before.y,e.box.y);swept.w=e.w+abs(dx);swept.h=e.h+abs(dy)
                        local first, earliest
                        for _, wall in ipairs(self.terrain) do local at=E.sweep(before,dx,dy,wall);if at and (not earliest or at<earliest) then earliest=at;first=nil end end
                        for _, target in ipairs(candidates(swept)) do
                            if target.faction ~= e.faction and target.faction ~= "neutral" and target.id ~= e.sourceId then
                                local at = E.sweep(before, dx, dy, target.box)
                                if at and (not earliest or at < earliest) then first, earliest = target, at end
                            end
                        end
                        if earliest then if first then hit(e, first, e.damage, e.id) end; self.despawn(e.id) end
                    elseif e.action then
                        local a, d = e.action, e.action.def
                        if a.active and not d.projectile then
                            local box = a.box; box.w = d.width or 50; box.h = d.height or 36
                            box.x = e.x + (e.facing > 0 and e.w / 2 or -e.w / 2 - box.w); box.y = e.y + (d.offsetY or 0)
                            for _, target in ipairs(candidates(box)) do
                                if target.id ~= e.id and target.faction ~= e.faction and target.faction ~= "neutral" and not a.hits[target.id] and E.overlap(box, target.box) then
                                    if hit(e, target, d.damage or 10, a.id) then a.hits[target.id] = true end
                                end
                            end
                        end
                        if a.finished then e.action = nil end
                    end
                end
            end
            perf.increment("collisionCandidates", self.candidateCount)
        end
        return self
    end
end
