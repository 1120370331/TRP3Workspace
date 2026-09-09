return function(E, G)
    local pcall, error = G.pcall, G.error
    E.games, E.lastLogs = {}, {}
    function E.registerGame(id, definition)
        if type(id) ~= "string" or type(definition.create) ~= "function" or definition.apiVersion ~= E.API_VERSION then error("incompatible game definition") end
        E.games[id] = definition
    end
    function E.start(host, manifest, content, viewFactory)
        local initialEnvironment=host.environment()
        if not initialEnvironment.allowed then return nil,initialEnvironment.reason end
        if E.current and not E.current.stopping and not E.current.host.definitionChanged() and E.current.host.item == host.item and E.current.manifest.objectVersion == manifest.objectVersion then
            if E.current.view.show then E.current.view.show()else E.current.view.frame:Show()end
            return E.current
        end
        if E.current then E.current.stop("switch_game") end
        local env = host.environment()
        if not env.allowed then return nil, env.reason end
        local owned, reason = host.owned(); if not owned then return nil, reason end
        local definition = E.games[manifest.gameId]
        if not definition then return nil, "game_not_registered" end
        local s = { host = host, manifest = manifest, content = content, scope = E.newScope(), time = 0, tick = 0,
            accumulator = 0, speed = 1, fixed = 1 / (content.simulationHz or 60), tasks = {}, nextTask = 0, paused = false, stopping = false,
            savePending = nil, revision = 0, operations = {}, callbacks = {}, previousLog = host.read("IG_PERF_LOG_V1") or E.lastLogs[manifest.rootId],
            id = manifest.gameId .. ":" .. tostring(host.now()), nextWatch = 0, nextHUD = 0 }
        local metadata = host.metadata()
        metadata.engineVersion = E.VERSION; metadata.gameId = manifest.gameId; metadata.rootId = manifest.rootId
        metadata.objectVersion = manifest.objectVersion; metadata.sourceHash = manifest.sourceHash
        metadata.releaseVersion = manifest.releaseVersion; metadata.simulationHz = content.simulationHz or 60
        local logPolicy = manifest.logPolicy or {persist="auto",maxBytes=190000}
        s.perf = E.newTelemetry(host, metadata, logPolicy)
        function s.stats()
            local out = s.view and s.view.stats() or {}
            out.entities = s.world and #s.world.list or 0; out.scheduledTasks = #s.tasks
            if s.effects then for key,value in pairs(s.effects.stats())do out[key]=value end end
            out.soundVoices = s.sound and s.sound.count or 0; out.musicBackend = s.music and s.music.backend or "silent"
            if s.sound then for key,value in pairs(s.sound.stats())do out[key]=value end end
            out.musicState = s.music and s.music.state or "stopped"
            out.musicChannel = s.music and s.music.channel; out.musicError = s.music and s.music.lastError
            out.inputMode = s.input and s.input.mode or "none"; return out
        end
        function s.saveLog()
            local text = s.perf.export(); E.lastLogs[manifest.rootId] = text
            local start = host.profileMS(); local ok, why = host.write("IG_PERF_LOG_V1", text)
            s.perf.note("log.persist", { ok = ok, reason = why, bytes = #text, milliseconds = host.profileMS() - start })
            return ok, why
        end
        function s.autoSaveLog()
            if logPolicy.persist ~= "manual" then return s.saveLog() end
        end
        function s.fail(stage, message)
            if s.stopping then return end
            s.perf.note("error", { stage = stage, message = tostring(message):sub(1, 3000) })
            s.perf.finish("failed", s.stats()); s.stop("script_error", { save = false })
            if G.print then G.print("TRP3 游戏停止：" .. tostring(message)) end
        end
        function s.safe(stage, fn, ...)
            if s.stopping then return false end
            if not fn then return true end
            local ok, a, b = pcall(fn, ...)
            if not ok then s.fail(stage, a) end
            return ok, a, b
        end
        local gameState = {}
        local function decodeSave(raw)
            if raw == nil or raw == "" or raw == "nil" then return nil end
            local ok, saved = pcall(E.JSON.decode, raw, 220000)
            if not ok or type(saved) ~= "table" then return nil,"invalid_save" end
            if saved.gameId~=manifest.gameId then return nil,"save_game_mismatch"end
            if saved.schemaVersion~=1 then return nil,"save_format_version_mismatch"end
            if saved.gameSaveVersion ~= definition.saveVersion then return nil, "save_version_mismatch" end
            if type(saved.game) ~= "table" or type(saved.operations or {}) ~= "table" then return nil, "invalid_save" end
            return saved
        end
        local raw = host.read("IG_SAVE_V1")
        local saved, saveError = decodeSave(raw)
        if saveError then
            if saveError~="invalid_save" then return nil,saveError..": save preserved; migration required"end
            local backup = host.read("IG_SAVE_BACKUP_V1"); local recovered = decodeSave(backup)
            if not recovered then return nil, saveError .. ": keep item data and inspect the backup" end
            saved, raw = recovered, backup; s.perf.note("save.recovered", { reason = saveError })
        end
        if saved then gameState = saved.game; s.operations = saved.operations or {}; s.revision = saved.revision or 0; s.lastGoodRaw = raw end
        function s.save(reason)
            if s.saving then return false, "save_reentrant" end
            local allowed, why = host.owned(); if not allowed then return false, why end
            s.saving = true; local start = host.profileMS()
            local ok, state = true, gameState
            if s.callbacks.onSave then ok, state = pcall(s.callbacks.onSave) end
            if not ok or type(state) ~= "table" then s.saving = false; return false, "game_save_failed: " .. tostring(state) end
            local success, text = pcall(E.JSON.encode, { schemaVersion = 1, gameSaveVersion = definition.saveVersion,
                gameId = manifest.gameId, revision = s.revision + 1, game = state, operations = s.operations })
            if not success or #text > 200000 then s.saving = false; return false, "save_encode_or_size_failed" end
            if s.lastGoodRaw then
                local backed, backupError = host.write("IG_SAVE_BACKUP_V1", s.lastGoodRaw)
                if not backed then s.saving = false; return false, backupError end
            end
            local written, writeError = host.write("IG_SAVE_V1", text)
            if written then s.lastGoodRaw = text; s.revision = s.revision + 1; gameState = E.util.copy(state) end
            s.saving = false
            s.perf.note("save.write", { reason = reason, ok = written, error = writeError, bytes = #text, milliseconds = host.profileMS() - start, revision = s.revision })
            return written, writeError
        end
        function s.stop(reason, options)
            if s.stopping then return end
            s.stopping = true; s.stopReason = reason; options = options or {}
            local failures = {}; s.cleanupErrors = failures
            local function clean(stage, fn, ...)
                if not fn then return true end
                local ok, a, b = pcall(fn, ...)
                if not ok then
                    local message = tostring(a):sub(1, 1000)
                    failures[#failures + 1] = {stage = stage, message = message}
                    pcall(s.perf.note, "error", {stage = "cleanup." .. stage, message = message})
                end
                return ok, a, b
            end
            -- Release the visible/input path before any optional statistics or persistence.
            if s.input then clean("input", s.input.release) end
            if s.view then clean("hide", s.view.hide) end
            clean("phase", function() s.perf.finish("stopped", s.stats()) end)
            if s.effects then clean("effects",s.effects.dispose)end
            if s.sound then clean("sound", s.sound.stopOwner) end
            if s.music then clean("music", s.music.stop, reason) end
            if options.save ~= false and s.started then
                local called, ok, why = clean("save", s.save, reason)
                if called and not ok then clean("save_status", s.perf.note, "save.skipped", { reason = why }) end
            end
            clean("onStop", s.callbacks.onStop, reason)
            s.tasks = {}; if s.events then clean("events", s.events.close) end
            if s.world then clean("world", s.world.clear) end
            clean("scope", s.scope.dispose); if s.view then clean("view", s.view.dispose) end
            if E.current == s then E.current = nil end
            clean("stats", function() s.perf.note("cleanup", s.stats()) end)
            clean("log_close", s.perf.close, reason)
            clean("log_save", s.autoSaveLog)
            clean("log_export", function() E.lastLogs[manifest.rootId] = s.perf.export() end)
            s.closed = true
            if reason == "definition_changed" then
                local message = "[IG STOP] 道具定义在运行中发生变化，已关闭；请重新使用道具。"
                if G.print then pcall(G.print, message) end
                pcall(host.write, "IG_BOOT_STATUS_V1", message)
            end
            if #failures > 0 and G.print then pcall(G.print, "[IG CLOSE] 界面已关闭；清理异常 " .. #failures .. " 项，请保留日志。") end
        end
        function s.pause(reason)
            if s.stopping or s.paused then return end
            s.captureBeforePause = s.input and s.input.mode == "capture"
            s.paused = true; s.accumulator = 0
            s.perf.finish("paused", s.stats())
            if s.input then s.input.release() end
            if s.scene3d then s.scene3d.cancelPointer() end
            if s.sound then s.sound.stopOwner() end
            if s.music then pcall(s.music.pause) end
            s.perf.note("runtime.pause", { reason = reason })
            s.safe("onPause", s.callbacks.onPause, reason)
        end
        function s.requestClose(reason)
            if s.stopping then return false end
            if s.callbacks.onCloseRequested then return s.safe("onCloseRequested",s.callbacks.onCloseRequested,reason) end
            s.stop(reason);return true
        end
        function s.resume()
            if s.stopping then return false, "stopped" end
            local state = host.environment(); local present, why = host.owned()
            if not state.allowed or not present then s.stop(state.reason or why, {save=present}); return false end
            if not s.paused then return true end
            s.paused = false; s.accumulator = 0
            if s.music then pcall(s.music.resume) end
            if s.captureBeforePause then s.input.acquire() end
            s.safe("onResume", s.callbacks.onResume); return true
        end
        E.current = s
        s.events = E.newEvents(function(err) s.fail("event", err) end)
        local constructed, view = pcall(viewFactory or E.newWoWView, s)
        if not constructed then s.fail("view_init", view); return nil, tostring(view) end
        s.view = view; s.input = E.newInput(s)
        if E.newWorld then s.world = E.newWorld(s) end
        if E.newSound then s.sound = E.newSound(s); s.music = E.newMusic(s) end
        if E.newEffects then s.effects = E.newEffects(s,view) end
        local packages = E.packages or {runtime=true,surface=E.newSurface~=nil,["surface-models"]=E.newSurfaceActors~=nil,
            world=E.newWorld~=nil,audio=E.newSound~=nil,effects=E.newEffects~=nil,scene3d=E.newWoWScene3D~=nil,particles3d=E.newParticles3D~=nil,surfaceEffects3D=E.newSurfaceEffects3D~=nil}
        local function requirePackage(name)
            if not packages[name] then error("package_not_included: " .. tostring(name) .. "; add it to item.json packages") end
            return true
        end
        local function unavailable(name)
            return G.setmetatable({}, {__index=function()requirePackage(name)end})
        end
        local ctx = { session = { id = s.id, pause = s.pause, resume = s.resume, stop = s.stop, isPaused=function()return s.paused end },
            content = content, events = s.events, world = unavailable("world"), motion = unavailable("world"), combat = unavailable("world"), collision = unavailable("world"), level = unavailable("world"),
            sound = s.sound or unavailable("audio"), music = s.music or unavailable("audio"), input = s.input, fx = unavailable("effects"), clock = {}, save = {}, inventory = {}, trade = {}, ui = {}, perf = {}, assets = {}, data = E.JSON }
        ctx.hasPackage=function(name)return packages[name]==true end
        ctx.requirePackage=requirePackage
        s.ctx = ctx
        ctx.scene3d=unavailable("scene3d")
        if E.newWoWScene3D then ctx.scene3d={math=E.math3d,boxMesh=E.boxMesh,create=function(options)
            if s.stopping then return nil,"session_stopped" end
            if s.scene3d then return s.scene3d end
            s.scene3d=view.scene3d(options);return s.scene3d
        end} end
        ctx.session.isStopped=function()return s.stopping end
        ctx.session.suspend=function()
            if s.stopping then return false end
            s.pause("suspend");if not s.stopping then view.suspend();return true end
            return false
        end
        ctx.session.getSpeed=function()return s.speed end
        ctx.session.setSpeed=function(speed)
            if s.stopping or not E.util.finite(speed) or speed<.25 or speed>4 then return false,"invalid_simulation_speed" end
            s.speed=speed;return true
        end
        if s.world then
        ctx.world.spawn = s.world.spawn; ctx.world.despawn = s.world.despawn; ctx.world.clear = s.world.clear
        ctx.world.get = function(id) return s.world.byId[id] end
        ctx.world.count = function() return #s.world.list end
        ctx.motion.setIntent = s.world.setIntent; ctx.combat.requestAction = s.world.requestAction
        ctx.collision.query = s.world.query; ctx.collision.sweep = E.sweep
        ctx.collision.setBroadphase = function(mode) if mode ~= "grid" and mode ~= "naive" then return false end; s.world.mode = mode;s.world.gridDirty=true; return true end
        ctx.level.load = s.world.loadLevel
        end
        if s.effects then
            ctx.fx.burst=s.effects.burst;ctx.fx.start=s.effects.start;ctx.fx.stop=s.effects.stop;ctx.fx.clear=s.effects.clear;ctx.fx.stats=s.effects.stats
        end
        ctx.level.checkpoint = function(id) s.perf.note("checkpoint", { id = id }); s.savePending = "checkpoint" end
        ctx.clock.now = function() return s.time end; ctx.clock.wall = host.now
        ctx.clock.after = function(delay, fn)
            if s.stopping or not E.util.finite(delay) or delay < 0 or #s.tasks >= 256 then return nil, "task_budget_or_delay" end
            s.nextTask = s.nextTask + 1
            local task = { id = s.nextTask, at = s.time + delay, fn = fn }
            s.tasks[#s.tasks + 1] = task; return function() task.cancelled = true end
        end
        ctx.save.data = E.util.copy(gameState)
        ctx.save.request = function(reason) if not s.stopping and not s.saving then s.savePending = reason or "requested"; return true end; return false end
        ctx.save.flush = function(reason)
            if s.stopping or s.saving then return false, "session_busy" end
            local ok, why = s.save(reason or "explicit")
            if ok then s.savePending = nil end
            return ok, why
        end
        ctx.save.probe = function()
            local key, old = "IG_STORAGE_PROBE_V1", host.read("IG_STORAGE_PROBE_V1")
            local text = E.JSON.encode({ test = "变量往返", nonce = s.id, position = { 1.25, -4 }, enabled = true })
            local start = host.profileMS(); local ok, why = host.write(key, text)
            local readOK = ok and host.read(key) == text
            local restored, restoreWhy = host.write(key, old)
            local result = { ok = readOK and restored, writeReason = why, restoreReason = restoreWhy, milliseconds = host.profileMS() - start, bytes = #text }
            s.perf.note("check.storage", result); return result
        end
        local function itemDefinition(id)
            local d = content.items[id]; if not d then return nil end
            return manifest.rootId .. " " .. d.innerId, d
        end
        ctx.inventory.count = function(id) local class = itemDefinition(id); if not class then return nil, "unknown_item" end; return host.itemCount(class) end
        local function mutate(operation, id, n, operationId)
            if s.saving or s.stopping then return {status="failed",reason="session_busy"} end
            local class, d = itemDefinition(id)
            if not class or not E.util.finite(n) or n < 1 or n > 100 or n ~= math.floor(n) or type(operationId) ~= "string" or #operationId > 100 then return {status="failed",reason="invalid_request"} end
            if s.operations[operationId] then
                local op = s.operations[operationId]
                if op.item ~= id or op.requested ~= n or op.operation ~= operation then return {status="failed",reason="operation_id_conflict"} end
                return op.result or {status="unknown",reason="pending_operation_not_retried"}
            end
            if operation == "consume" and not d.stack then return {status="failed",reason="use_exact_instance_ui_for_equipment"} end
            if E.util.count(s.operations) >= 128 then return {status="failed",reason="operation_journal_full"} end
            local record = { item = id, requested = n, operation = operation }
            s.operations[operationId] = record
            local persisted, why = s.save("inventory_pending")
            if not persisted then s.operations[operationId] = nil; return {status="failed",reason=why} end
            local result = host.mutateInventory(operation, class, n, d.attributes); record.result = result
            local written = s.save("inventory_result")
            if not written then record.result = nil; result = {status="unknown",reason="inventory_changed_but_receipt_not_saved",applied=result.applied} end
            s.perf.note("inventory.operation", { operationId = operationId, item = id, operation = operation, result = result })
            s.events.emit("inventory.changed", { item = id, result = result }); return result
        end
        ctx.inventory.grant = function(id,n,op) return mutate("grant",id,n,op) end
        ctx.inventory.consume = function(id,n,op) return mutate("consume",id,n,op) end
        ctx.trade.open = function(target) s.pause("trade"); return host.openTrade(target or host.targetPlayer()) end
        ctx.ui.button = view.button; ctx.ui.notify = view.notify; ctx.ui.status = view.status; ctx.ui.prompt = view.prompt
        ctx.ui.surface = function()requirePackage("surface");return view.surface()end
        ctx.ui.showLog = function(previous)
            view.showLog(previous and (s.previousLog or "暂无上次日志") or s.perf.export())
        end
        ctx.ui.toggleBounds = function() view.showBounds = not view.showBounds; return view.showBounds end
        ctx.perf.begin = function(name, metadata, options) s.resume(); s.perf.begin(name, metadata, options) end
        ctx.perf.finish = function(status) s.perf.finish(status or "manual", s.stats()) end
        ctx.perf.isRunning = function() return s.perf.phase ~= nil end
        ctx.perf.note = s.perf.note; ctx.perf.stats = s.stats; ctx.perf.saveLog = s.saveLog
        ctx.perf.snapshot = s.perf.snapshot
        ctx.perf.measure = function(name, fn)
            local start = host.profileMS(); local ok, result = s.safe(name, fn)
            s.perf.record(name, host.profileMS() - start); return ok, result
        end
        ctx.assets.recordModels = function()
            local result = {}
            for _, e in ipairs(s.world and s.world.list or {}) do
                if e.view and (e.view.kind == "model" or e.view.kind=="scene_model") then
                    local ok, id = E.util.call(e.view.object.GetModelFileID, e.view.object)
                    local bounds
                    if e.view.kind=="scene_model" and e.view.loaded then
                        local bottom,top=E.readModelBounds(e.view.object,"GetActiveBoundingBox")
                        if bottom and top then bounds={bottom=bottom,top=top}end
                    end
                    result[#result + 1] = { entity = e.id, asset = e.visual.asset, fileID = ok and id or nil,
                        backend=e.view.kind,loaded = e.view.loaded == true, collider = E.util.copy(e.box), nativeBounds = bounds or "unavailable_for_this_backend_or_load_state" }
                end
            end
            s.perf.note("check.models", { models = result, count = #result }); return result
        end
        if s.sound then
            for name, sound in pairs(content.feedback or {}) do s.events.on(name, function() if not s.paused then s.sound.play(sound) end end) end
        end
        local function changed(event)
            if s.stopping then return end
            if event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_LOGOUT" then s.stop(event); return end
            local state = host.environment(); local present, why = host.owned()
            if not state.allowed or not present then s.stop(state.reason or why, {save=present}); return end
            if host.definitionChanged() then s.stop("definition_changed"); return end
            local command=host.read("IG_CONTROL_V1")
            if command then
                host.write("IG_CONTROL_V1",nil)
                if command=="stop" or command=="destroy" then s.stop(command,{save=command~="destroy"});return end
                if command=="pause" then s.pause("item_workflow") end
            end
            if event == "SECURITY_CHANGED" and not host.allowedEffects() then s.stop("security_changed", {save=false}) end
        end
        host.watch(s.scope, changed)
        local ok, callbacks = s.safe("createGame", definition.create, ctx)
        if not ok or type(callbacks) ~= "table" or type(callbacks.onStart) ~= "function" then if not s.stopping then s.fail("createGame", "onStart callback required") end; return nil, "invalid_game" end
        s.callbacks = callbacks
        local startOK = s.safe("onStart", callbacks.onStart)
        if not startOK then return nil, "onStart_failed" end
        s.started = true
        s.perf.note("runtime.started", s.stats())
        if host.bootstrapStartedMS then s.perf.note("startup",{bootstrapLuaToOnStartMs=host.profileMS()-host.bootstrapStartedMS,excludes="macro, intentional 0.1s delay, import, permission UI"})end
        local function stage(name, fn, ...)
            local start = host.profileMS(); fn(...); s.perf.record(name, host.profileMS() - start)
        end
        local function fixedStep()
            s.time = s.time + s.fixed; s.tick = s.tick + 1
            local input = s.input.snapshot()
            stage("gameMs", function() s.safe("onFixedUpdate", s.callbacks.onFixedUpdate, s.fixed, input) end)
            if s.stopping or s.paused then return end
            if s.world then
            stage("aiMs", s.world.updateAI)
            stage("actionsMs", s.world.updateActions, s.fixed)
            stage("motionMs", s.world.move, s.fixed)
            end
            if s.scene3d then stage("scene3DStepMs",s.scene3d.step,s.fixed)end
            if s.scene3d and s.scene3d.particles then stage("particles3DStepMs",s.scene3d.particles.update,s.fixed)end
            if s.world then stage("collisionMs", s.world.collide) end
            stage("eventsMs", s.events.flush)
            if s.effects then stage("effectsMs",s.effects.update,s.fixed) end
            if s.stopping then return end
            if #s.tasks > 0 then
                local current = s.tasks; s.tasks = {}
                for _, task in ipairs(current) do
                    if not task.cancelled then
                        if task.at <= s.time then s.safe("scheduled", task.fn) else s.tasks[#s.tasks + 1] = task end
                    end
                    if s.stopping then break end
                end
            end
            if s.world then s.world.cleanup() end
            if s.savePending and not s.stopping then
                local why = s.savePending; s.savePending = nil
                local ok,err=s.save(why)
                if not ok then s.perf.note("save.failed",{reason=why,error=tostring(err)});view.notify("存档失败："..tostring(err))end
            end
        end
        function s.frame(elapsed)
            if s.stopping then return end
            s.frameSerial=(s.frameSerial or 0)+1
            local frameStart = host.profileMS(); local now = host.now()
            if now >= s.nextWatch then s.nextWatch = now + .25; changed("poll"); if s.stopping then return end end
            if view.update then s.safe("asset_update",view.update)end
            if not s.paused then s.safe("onFrame", s.callbacks.onFrame, elapsed) end
            if s.stopping then return end
            s.perf.beforeFrame(); stage("inputMs", s.input.poll)
            if not s.paused then
                s.accumulator = s.accumulator + math.min(elapsed, .25) * s.speed
                if elapsed > .25 then s.perf.increment("clampedSimulationMs", (elapsed - .25) * 1000) end
                local steps = 0
                while s.accumulator >= s.fixed and steps < 5 and not s.stopping and not s.paused do
                    s.accumulator = s.accumulator - s.fixed; steps = steps + 1; fixedStep()
                end
                if s.stopping then return end
                if s.accumulator >= s.fixed then
                    local dropped = math.floor(s.accumulator / s.fixed) * s.fixed
                    s.accumulator = s.accumulator - dropped; s.perf.increment("droppedSimulationMs", dropped * 1000)
                end
                if s.world then stage("renderMs", view.render, s.world, E.util.clamp(s.accumulator / s.fixed, 0, 1)) end
                if s.effects then stage("effectsRenderMs",s.effects.render,E.util.clamp(s.accumulator / s.fixed,0,1)) end
            end
            if s.scene3d then
                if not s.paused and s.scene3d.particles then s.scene3d.particles.observeFrame(elapsed*1000)end
                stage("scene3DRenderMs",s.scene3d.render,s.paused and 1 or E.util.clamp(s.accumulator/s.fixed,0,1))
            end
            if s.sound then s.sound.update() end
            if s.music then
            local audioOK, audioError = pcall(s.music.update)
            if not audioOK then s.perf.note("music.error", {reason=tostring(audioError)}); pcall(s.music.stop, "backend_error") end
            end
            if now >= s.nextHUD then
                s.nextHUD = now + .3
                local p = s.perf.phase
                local mode = s.input.mode == "capture" and "键盘接管" or "按键只读/透传"
                view.info((s.paused and "已暂停" or "运行中") .. " | " .. mode .. " | 实体 " .. (s.world and #s.world.list or 0) .. " | Music " .. (s.music and s.music.backend or "silent"))
                if content.presentation ~= "game" then view.status(p and (p.name .. (p.measuring and " 采样 " or " 预热 ") .. string.format("%.1fs", now - (p.measureStart or p.start))) or "空闲：选择一项测试；自动基准包含预热，导出日志会暂停。") end
            end
            s.perf.afterFrame(elapsed, host.profileMS() - frameStart, s.stats)
            if s.perf.completed ~= s.lastLoggedCompletion then
                s.lastLoggedCompletion = s.perf.completed
                if s.perf.completed > 0 then s.autoSaveLog() end
            end
        end
        view.frame:SetScript("OnUpdate", function(_, elapsed) s.safe("frame", s.frame, elapsed) end)
        return s
    end
end
