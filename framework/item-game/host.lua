return function(E, G)
    local pcall, error = G.pcall, G.error
    function E.newWoWHost(args, manifest)
        local API = G.TRP3_API
        if not API or not API.inventory or not G.CreateFrame then error("WoW/TRP3 host unavailable") end
        local item = args.object
        if type(item) ~= "table" or item.id ~= manifest.rootId then error("A main-item instance is required") end
        local host = { kind = "wow", G = G, item = item, rootId = manifest.rootId, objectVersion = manifest.objectVersion }
        local initialClass=API.extended.getClass(host.rootId)
        -- Saving in the native editor increments MD.V without rewriting the bundled manifest.
        -- Detect changes since this launch, rather than treating every editor save as a stale runtime.
        host.definitionVersion = initialClass and initialClass.MD and initialClass.MD.V
        local function fingerprint(class)
            return class and class.IN and class.IN.ig_manifest and class.IN.ig_manifest.PA and class.IN.ig_manifest.PA[1] and class.IN.ig_manifest.PA[1].TX
        end
        host.definitionFingerprint=fingerprint(initialClass)
        host.bootstrapStartedMS=args._igLaunchMS
        host.now = function() return G.GetTime() end
        host.profileMS = G.debugprofilestop or function() return G.GetTime() * 1000 end
        host.profileClock = G.debugprofilestop and "debugprofilestop/ms" or "GetTime/ms-coarse"
        host.date = function() return G.date("%Y-%m-%dT%H:%M:%S") end
        host.fps = function() return G.GetFramerate and G.GetFramerate() or nil end
        host.memoryKB = function()
            if G.gcinfo then local ok, n = pcall(G.gcinfo); if ok and type(n) == "number" then return n end end
            return nil
        end
        function host.inventoryRoot() return API.inventory.getInventory and API.inventory.getInventory() end
        function host.findItem(predicate)
            local seen, visited = {}, 0
            local function find(container, depth)
                if type(container) ~= "table" or seen[container] or depth > 32 then return end
                seen[container] = true
                for slot, object in pairs(container.content or {}) do
                    visited = visited + 1; if visited > 20000 then return end
                    if predicate(object, container, slot) then return object, container, slot end
                    local a, b, c = find(object, depth + 1); if a then return a, b, c end
                end
            end
            return find(host.inventoryRoot(), 0)
        end
        function host.owned()
            if item.id ~= manifest.rootId then return false, "item_missing" end
            local found, parent = host.findItem(function(o) return o == item end)
            if not found then return false, "item_missing" end
            if API.inventory.isInTransaction and API.inventory.isInTransaction(item) then return false, "item_in_trade" end
            return true, parent
        end
        function host.read(key) return item.vars and item.vars[key] end
        function host.write(key, value)
            local allowed, reason = host.owned(); if not allowed then return false, reason end
            if type(value) == "string" and #value > 220000 then return false, "store_size_limit" end
            if not API.script or not API.script.setVar then return false, "store_unavailable" end
            local written,why=pcall(API.script.setVar,{ object = item }, "o", "=", key, value)
            if not written then return false,tostring(why)end
            if host.read(key)==value then return true end
            return false,"write_verification_failed"
        end
        function host.environment()
            if not G.IsInInstance or not G.InCombatLockdown then return { allowed = false, reason = "environment_unavailable" } end
            local inside, kind = G.IsInInstance()
            local combat = G.InCombatLockdown() == true
            local blocked = { party = true, raid = true, scenario = true, pvp = true, arena = true }
            local known = not inside or kind == "none" or kind == "neighborhood" or kind == "interior" or blocked[kind]
            return { inInstance = inside, instanceType = kind, inCombat = combat,
                allowed = known and not combat and not blocked[kind],
                reason = combat and "wow_combat" or (blocked[kind] and "wow_instance" or (not known and "unknown_instance" or nil)) }
        end
        function host.definitionChanged()
            local c = API.extended.getClass(host.rootId)
            return not c or not c.MD or c.MD.V ~= host.definitionVersion or fingerprint(c)~=host.definitionFingerprint
        end
        function host.metadata()
            local version, build, date, toc = G.GetBuildInfo()
            local result = { clientVersion = version, clientBuild = build, interface = toc, clientDate = date,
                objectRevision = host.definitionVersion,
                extendedBuild = API.globals and API.globals.extended_version, locale = G.GetLocale and G.GetLocale(),
                memoryScope = "shared_client_lua_heap_not_gpu_or_engine_attribution", environment = host.environment() }
            if G.GetCVar then
                result.graphics = {}
                for _, k in ipairs({"gxWindow", "gxResolution", "gxVSync", "maxFPS", "graphicsQuality", "Sound_EnableAllSound", "Sound_EnableSFX", "Sound_EnableMusic", "Sound_MasterVolume", "Sound_SFXVolume", "Sound_MusicVolume", "Sound_NumChannels"}) do
                    local ok, v = pcall(G.GetCVar, k); if ok then result.graphics[k] = v end
                end
            end
            return result
        end
        function host.watch(scope, callback)
            E.eventFrame = E.eventFrame or G.CreateFrame("Frame")
            local f = E.eventFrame
            f:SetScript("OnEvent", function(_, name) callback(name) end)
            for _, name in ipairs({"PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_LOGOUT", "PLAYER_REGEN_DISABLED", "ZONE_CHANGED_NEW_AREA"}) do pcall(f.RegisterEvent, f, name) end
            scope.add(function() f:UnregisterAllEvents(); f:SetScript("OnEvent", nil) end)
            if G.TRP3_Extended and API.RegisterCallback then
                for _, name in ipairs({"REFRESH_BAG", "ON_OBJECT_UPDATED", "SECURITY_CHANGED"}) do
                    if G.TRP3_Extended.Events[name] then
                        local ok, registration = pcall(API.RegisterCallback, G.TRP3_Extended, name, function() callback(name) end)
                        if ok and registration then scope.add(function() registration:Unregister() end) end
                    end
                end
            end
        end
        function host.allowedEffects()
            if not API.security or not API.security.resolveEffectSecurity then return false end
            return API.security.resolveEffectSecurity(host.rootId, "script") and API.security.resolveEffectSecurity(host.rootId, "secure_macro")
        end
        function host.keyDown(key)
            if not G.IsKeyDown then return nil end
            local ok, value = pcall(G.IsKeyDown, key)
            if ok then return value end
            return nil
        end
        function host.textFocused()
            if G.GetCurrentKeyBoardFocus then
                local ok, f = pcall(G.GetCurrentKeyBoardFocus); if ok and f then return true end
            end
            if G.GetCurrentKeyboardFocus then
                local ok, f = pcall(G.GetCurrentKeyboardFocus); if ok and f then return true end
            end
            if G.ChatFrameUtil and G.ChatFrameUtil.GetActiveWindow then return G.ChatFrameUtil.GetActiveWindow() ~= nil end
            return false
        end
        function host.audioStatus(channel)
            local result = { channel = channel or "SFX", cvars = {} }
            local channels = {
                SFX = { "Sound_EnableSFX", "Sound_SFXVolume" },
                Music = { "Sound_EnableMusic", "Sound_MusicVolume" },
                Ambience = { "Sound_EnableAmbience", "Sound_AmbienceVolume" },
                Dialog = { "Sound_EnableDialog", "Sound_DialogVolume" },
                Master = {},
            }
            local keys = channels[result.channel]
            if not keys then result.reason = "invalid_sound_channel"; return result end
            local function read(key)
                if not key or not G.GetCVar then return nil end
                local ok, value = pcall(G.GetCVar, key)
                if ok and (type(value) == "string" or type(value) == "number") then result.cvars[key] = value; return value end
            end
            local all, volume, enabled, channelVolume = read("Sound_EnableAllSound"), read("Sound_MasterVolume"), read(keys[1]), read(keys[2])
            if tonumber(all) == 0 then result.reason = "all_sound_disabled"
            elseif tonumber(volume) == 0 then result.reason = "master_volume_zero"
            elseif tonumber(enabled) == 0 then result.reason = "channel_disabled"
            elseif tonumber(channelVolume) == 0 then result.reason = "channel_volume_zero" end
            return result
        end
        function host.soundVolumeSupported(def)
            return G.C_Sound~=nil and type(G.C_Sound.PlaySoundWithOptions)=="function" and
                (def==nil or def.kind=="soundKitID" or def.volumeSoundKitID~=nil)
        end
        function host.playSound(def,volume)
            local status = host.audioStatus(def.channel)
            if status.reason then return nil, status.reason, status end
            if volume~=nil and (not E.util.finite(volume)or volume<0 or volume>1)then return nil,"invalid_sound_volume",status end
            if volume==0 then return nil,"volume_zero",status end
            local volumePath=volume~=nil and (volume~=1 or def.baseVolume~=nil or def.volumeSoundKitID~=nil)
            if volumePath then
                if not host.soundVolumeSupported(def)then return nil,"sound_volume_unsupported",status end
                status.volume=volume;status.volumeOverride=volume*(def.baseVolume or 1)
                status.soundKitID=def.volumeSoundKitID or def.id
                local ok,playing,handle=pcall(G.C_Sound.PlaySoundWithOptions,{soundKitID=status.soundKitID,
                    uiSoundSubType=status.channel,forceNoDuplicates=false,volumeOverride=status.volumeOverride})
                if not ok then return nil,"sound_api_error",status end
                if not playing or not handle then return nil,"sound_not_started",status end
                return handle,nil,status
            end
            local fn = def.kind == "soundKitID" and G.PlaySound or G.PlaySoundFile
            if not fn or type(def.id) ~= "number" then return nil, "sound_unavailable", status end
            local ok, playing, handle = pcall(fn, def.id, status.channel)
            if not ok then return nil, "sound_api_error", status end
            if not playing or not handle then return nil, "sound_not_started", status end
            return handle, nil, status
        end
        function host.stopSound(handle, fadeMs) if handle and G.StopSound then pcall(G.StopSound, handle, fadeMs or 0) end end
        function host.soundPlaying(handle)
            if G.C_Sound and G.C_Sound.IsPlaying then
                local ok, active = pcall(G.C_Sound.IsPlaying, handle); if ok then return active end
            end
            return nil
        end
        function host.itemCount(classID)
            return API.inventory.getItemCount and API.inventory.getItemCount(classID) or nil
        end
        function host.mutateInventory(operation, classID, amount, attributes)
            local owned, reason = host.owned(); if not owned then return { status = "failed", applied = 0, reason = reason } end
            local found = host.findItem(function(o) return o.id == classID and API.inventory.isInTransaction and API.inventory.isInTransaction(o) end)
            if found then return { status = "failed", applied = 0, reason = "item_in_trade" } end
            local before = host.itemCount(classID)
            if before == nil then return { status = "failed", applied = 0, reason = "inventory_unavailable" } end
            if operation == "consume" and before < amount then return { status = "failed", applied = 0, reason = "insufficient_items" } end
            local ok, err
            if operation == "grant" then
                local data={count=amount}
                if attributes then data.vars={IG_EQUIP_V1=E.JSON.encode(attributes)}end
                ok, err = pcall(API.inventory.addItem, nil, classID, data, false)
            else ok, err = pcall(API.inventory.removeItem, classID, amount) end
            local after = host.itemCount(classID)
            if not ok or after == nil then return { status = "unknown", reason = tostring(err), requested = amount } end
            local delta = operation == "grant" and after - before or before - after
            if delta < 0 or delta > amount then return { status = "unknown", reason = "unexpected_inventory_delta", requested = amount } end
            return { status = delta == amount and "complete" or (delta == 0 and "failed" or "partial"), requested = amount, applied = delta }
        end
        function host.openTrade(target)
            if not target or target == "" or not API.inventory.startEmptyExchangeWithUnit then return false, "select_a_player_target" end
            if G.TRP3_ExchangeFrame and G.TRP3_ExchangeFrame:IsShown() then return false, "trade_already_open" end
            local ok, err = pcall(API.inventory.startEmptyExchangeWithUnit, target); return ok, err
        end
        function host.targetPlayer()
            if G.UnitIsPlayer and not G.UnitIsPlayer("target") then return nil end
            if API.utils and API.utils.str and API.utils.str.getUnitID then return API.utils.str.getUnitID("target") end
            return nil
        end
        return host
    end
end
