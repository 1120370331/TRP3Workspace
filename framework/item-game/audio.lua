return function(E, G)
    local pcall = G.pcall
    function E.newSound(session)
        local host, perf = session.host, session.perf
        local self = { enabled = true, playing = {}, last = {}, nextId = 0, count = 0,
            limit=(session.content.limits or {}).maxSoundVoices or 12,peak=0,volume=1 }
        local buses=E.util.copy(session.content.soundBuses or {})
        local groups,bySound,retryAt={},{},{}
        local nextSweep=0
        local function state(id,now)
            local group=groups[id]
            if not group then group={density=0,updated=now,nextAt=0,blockedUntil=0,active=0};groups[id]=group end
            return group
        end
        local function admit(def,now)
            local policy=def.group and (session.content.soundGroups or {})[def.group]
            if not policy then return true end
            local group=state(def.group,now)
            -- Exponentially decayed event density; dropped sounds never queue.
            group.density=group.density*math.exp(-(now-group.updated)/(policy.window or 1))+1;group.updated=now
            if now<group.blockedUntil then return false,nil,nil,"ducked" end
            if now<group.nextAt then return false,nil,nil,"interval" end
            if group.active>=(policy.maxConcurrent or 1)then return false,nil,nil,"concurrency" end
            return true,group,policy
        end
        function self.play(id, options)
            options = options or {}; local def = session.content.sounds[id]
            if session.stopping then return nil,"stopped" end
            if not self.enabled then return nil, "disabled" end
            if not def then return nil, "unknown_sound" end
            local requested=options.volume or 1
            if not E.util.finite(requested)or requested<0 or requested>1 then return nil,"invalid_volume"end
            local volume=self.volume*(def.volume or 1)*(def.bus and buses[def.bus] or 1)*requested
            if volume==0 then perf.increment("soundVolumeMuted");return nil,"volume_zero"end
            perf.increment("soundAttempts")
            local now = host.now()
            self.update(now)
            if now<(retryAt[id] or 0)then perf.increment("soundRetryBackoff");return nil,"retry_backoff"end
            if now - (self.last[id] or -100) < (def.cooldown or .08) then perf.increment("soundThrottled"); return nil, "throttled" end
            local allowed,group,policy,detail=admit(def,now)
            if not allowed then
                perf.increment("soundGroupMerged");perf.increment("soundGroup_"..detail);return nil,"group_merged",detail
            end
            if (bySound[id] or 0)>=(def.maxConcurrent or self.limit)then perf.increment("soundTypeBudgetDrops");return nil,"sound_budget"end
            local victim, priority
            if self.count >= self.limit then
                for token,p in pairs(self.playing)do
                    local voicePriority=p.priority or 0
                    if not priority or voicePriority<priority or (voicePriority==priority and token<victim)then victim=token;priority=voicePriority end
                end
                if not victim or (def.priority or 0)<=priority then perf.increment("soundBudgetDrops"); return nil, "voice_budget" end
            end
            perf.increment("soundRequests")
            local handle, reason = host.playSound(def,volume)
            if not handle then
                retryAt[id]=now+.25;perf.increment("soundFailures")
                perf.note("sound.failure",{sound=id,reason=reason,group=def.group});return nil, reason
            end
            -- Do not cut an audible voice until its replacement actually starts.
            if victim then self.stop(victim,60);perf.increment("soundPreemptions")end
            self.last[id]=now;retryAt[id]=nil;perf.increment("soundStarted")
            if group then group.nextAt=now+(policy.interval or .5)+math.min(policy.maxExtra or .6,group.density*(policy.densityStep or .025))end
            for _,id in ipairs(def.duckGroups or {})do
                local ducked=state(id,now)
                ducked.blockedUntil=math.max(ducked.blockedUntil,now+(def.duckDuration or .8))
                for token,voice in pairs(self.playing)do if voice.group==id then self.stop(token,80);perf.increment("soundDuckStops")end end
            end
            self.nextId = self.nextId + 1
            self.playing[self.nextId] = { handle = handle, soundId=id, bus=def.bus, volume=volume, owner = options.owner, group=def.group,fadeMs=def.fadeMs or 0,
                priority=def.priority or 0, expires = now + (def.maxDuration or 5) }
            self.count = self.count + 1;self.peak=math.max(self.peak,self.count)
            bySound[id]=(bySound[id] or 0)+1
            if group then group.active=group.active+1 end
            return self.nextId
        end
        function self.stop(token,fadeMs)
            local p = self.playing[token]; if not p then return end
            host.stopSound(p.handle,fadeMs or 0); self.playing[token] = nil; self.count = self.count - 1
            bySound[p.soundId]=bySound[p.soundId]-1
            if p.group and groups[p.group]then groups[p.group].active=groups[p.group].active-1 end
        end
        function self.stopOwner(owner)
            for token, p in pairs(self.playing) do if owner == nil or p.owner == owner then self.stop(token) end end
        end
        function self.update(now)
            now=now or host.now()
            if now<nextSweep then return end
            nextSweep=now+.02
            if self.count==0 then return end
            perf.increment("soundSweeps")
            for token, p in pairs(self.playing) do
                if now >= p.expires then self.stop(token,p.fadeMs);perf.increment("soundTimeoutStops")
                elseif host.soundPlaying(p.handle) == false then self.stop(token);perf.increment("soundFinished")end
            end
        end
        function self.stats()
            local active={};for id,g in pairs(groups)do if g.active>0 then active[id]=g.active end end
            return {soundVoices=self.count,soundVoiceLimit=self.limit,peakSoundVoices=self.peak,soundGroups=active,soundVolume=self.volume,soundBusVolumes=E.util.copy(buses)}
        end
        function self.capabilities()return {volume=host.soundVolumeSupported and host.soundVolumeSupported()or false,volumeAppliesTo="new_voices"}end
        function self.setVolume(volume)
            if not E.util.finite(volume)or volume<0 or volume>1 then return false,"invalid_volume"end
            self.volume=volume;if volume==0 then self.stopOwner()end;return true
        end
        function self.getVolume()return self.volume end
        function self.setBusVolume(bus,volume)
            if not buses[bus]then return false,"unknown_bus"end
            if not E.util.finite(volume)or volume<0 or volume>1 then return false,"invalid_volume"end
            buses[bus]=volume
            if volume==0 then for token,p in pairs(self.playing)do if p.bus==bus then self.stop(token)end end end
            return true
        end
        function self.getBusVolume(bus)return buses[bus]end
        function self.setEnabled(enabled) self.enabled = enabled == true; if not self.enabled then self.stopOwner() end end
        return self
    end
    function E.newMusic(session)
        local host, perf = session.host, session.perf
        local self = {enabled=true,backend="silent",state="stopped",generation=0,loop=false,
            volume=1,preference="auto",paused=false,playWhilePaused=false}
        local failedImports={}
        local function changed()
            local fn=session.callbacks and session.callbacks.onMusicChanged
            if not session.stopping and type(fn)=="function"then
                if session.safe then session.safe("onMusicChanged",fn)else pcall(fn)end
            end
        end
        local function state(backend,value)
            local different=self.backend~=backend or self.state~=value
            self.backend=backend;self.state=value
            if different then changed()end
        end
        local function musicianAvailable()
            local m=G.Musician
            return m~=nil and m.Song~=nil and type(m.Song.create)=="function"
        end
        local function preferred(def)
            return self.preference~="native"and def and def.musicianCode and musicianAvailable()and "musician"or "native"
        end
        local function nativeSource(def)
            if not def or not def.nativeFileId then return nil end
            return {kind="fileID",id=def.nativeFileId,channel=def.channel or "SFX",
                volumeSoundKitID=def.volumeSoundKitID,baseVolume=def.baseVolume}
        end
        function self.capabilities(id)
            local def=id and session.content.music[id]or self.definition
            local selected=preferred(def)
            if not def and self.preference=="auto"and musicianAvailable()then selected="musician"end
            if def==self.definition and self.state~="stopped"and self.backend~="silent"then selected=self.backend end
            local source=nativeSource(def)
            local volumeSupported=selected=="native"and (id==nil or def~=nil)and
                host.soundVolumeSupported~=nil and host.soundVolumeSupported(source)or false
            return {native=G.PlaySoundFile~=nil,musician=musicianAvailable(),selectedBackend=selected,
                preferredBackend=preferred(def),localOnly=true,independentVolume=volumeSupported,
                nativeDefaultChannel="SFX",nativePauseMode="restart",
                pauseMode=selected=="musician"and "resume"or "restart",
                volumeChangeMode=selected=="musician"and "mute_only"or "restart",
                seek=self.song~=nil and type(self.song.Seek)=="function"}
        end
        -- Song:Resume otherwise lets Musician normalize SFX/Dialog volume and cache CVars.
        -- Suppress only that synchronous auto-adjust call; restore the user's setting even on error.
        local function songCall(fn,song,...)
            if type(fn)~="function"then return false,"unsupported_song_method"end
            local settings=G.Musician_Settings
            local previous=type(settings)=="table"and settings.autoAdjustAudioSettings
            if type(settings)=="table"then settings.autoAdjustAudioSettings=false end
            local ok,result=pcall(fn,song,...)
            if type(settings)=="table"then settings.autoAdjustAudioSettings=previous end
            return ok and result~=false,result
        end
        local function clearSong()
            local song=self.song
            self.song=nil;self.importDeadline=nil;self.needsFirstPlay=false
            if song then
                if song.CancelImport then songCall(song.CancelImport,song)end
                if song.Stop then songCall(song.Stop,song)end
            end
        end
        function self.stop(reason)
            self.generation=self.generation+1
            if self.handle then host.stopSound(self.handle);self.handle=nil end
            clearSong();self.paused=false;self.playWhilePaused=false
            self.channel=nil;self.lastError=nil;self.fallbackReason=nil
            state("silent","stopped")
        end
        function self.getBackend()return self.preference end
        function self.setBackend(preference)
            if preference~="auto"and preference~="native"then return false,"invalid_music_backend"end
            if self.preference~=preference then
                self.stop("backend_changed");self.preference=preference;failedImports={};changed()
            end
            return true
        end
        local function native(def)
            self.channel=def and def.channel or "SFX"
            local source=nativeSource(def)
            local handle,reason,status
            if not source then reason="no_fallback_track"
            elseif self.channel~="SFX"and self.channel~="Music"then reason="invalid_music_channel"
            elseif self.paused then self.lastError=nil;state("native","paused");return true
            elseif self.volume==0 then self.lastError=nil;state("native","muted");return true
            else
                if self.volume==1 then source.volumeSoundKitID=nil;source.baseVolume=nil end
                handle,reason,status=host.playSound(source,self.volume)
            end
            self.lastError=reason
            perf.note("music.playback",{trackId=self.trackId,fileID=def and def.nativeFileId,
                channel=self.channel,ok=handle~=nil,reason=reason,audio=status,volume=self.volume,
                fallbackReason=self.fallbackReason})
            if not handle then
                state("silent","unavailable");perf.increment("musicFailures");return false,reason
            end
            self.handle=handle;self.started=host.now();state("native","playing");return true
        end
        local function fallback(reason,remember)
            if remember then failedImports[self.trackId]=reason end
            clearSong();self.fallbackReason=reason
            perf.note("music.fallback",{trackId=self.trackId,reason=reason})
            local ok,why=native(self.definition);changed();return ok,why
        end
        local function startSong()
            if self.paused then state("musician","paused");return true end
            if self.volume==0 then state("musician","muted");return true end
            local song=self.song
            if not song then return fallback("musician_song_missing",true)end
            local fn=self.needsFirstPlay and song.Play or song.Resume
            local ok,why=songCall(fn,song)
            if not ok then
                perf.note("music.error",{reason=tostring(why)})
                return fallback("musician_play_failed",true)
            end
            self.needsFirstPlay=false;self.lastError=nil;self.channel=nil
            state("musician","playing");return true
        end
        function self.getVolume()return self.volume end
        function self.setVolume(volume)
            if not E.util.finite(volume)or volume<0 or volume>1 then return false,"invalid_music_volume"end
            if volume==self.volume then return true end
            if self.backend~="musician"and self.definition and volume~=0 and volume~=1 and
                not self.capabilities().independentVolume then return false,"music_volume_unsupported"end
            self.volume=volume
            if self.backend=="musician"then
                -- Non-zero gain is kept for Native playback; Musician has no per-song fader.
                -- Zero is still an explicit mute, and unmuting resumes the owned song cursor.
                if volume==0 and self.state=="playing"then
                    if self.song then songCall(self.song.Stop,self.song)end
                    state("musician","muted")
                elseif volume>0 and self.state=="muted"then startSong()end
                changed();return true
            end
            if self.backend=="native"and (self.state=="playing"or self.state=="muted")then
                if self.handle then host.stopSound(self.handle);self.handle=nil end
                local ok,why=native(self.definition);changed();return ok,why
            end
            changed();return true
        end
        function self.play(id,options)
            options=options or {}
            local def=session.content.music[id]
            if not def then return false,"unknown_track"end
            if session.stopping then return false,"stopped"end
            if not self.enabled then return false,"disabled"end
            if options.retry then failedImports[id]=nil end
            if self.trackId==id and not options.retry and
                (self.state=="playing"or self.state=="loading"or self.state=="paused"or self.state=="muted")then return true end
            self.stop("switch");self.trackId=id;self.definition=def;self.loop=options.loop==true
            self.playWhilePaused=options.playWhilePaused==true
            self.paused=session.paused==true and not self.playWhilePaused
            if preferred(def)~="musician"then
                if self.preference=="auto"and def.musicianCode then self.fallbackReason="musician_unavailable"end
                return native(def)
            end
            if failedImports[id]then return fallback(failedImports[id],false)end
            local m=G.Musician
            if m.Song.GetPlayingSongCount then
                local ok,count=pcall(m.Song.GetPlayingSongCount)
                if not ok or (type(count)=="number"and count>0)then return fallback("musician_busy",false)end
            end
            if m.Live and m.Live.IsPlaying then
                local ok,playing=pcall(m.Live.IsPlaying)
                if not ok or playing then return fallback("musician_busy",false)end
            end
            if m.Sampler and m.Sampler.GetMuted then
                local ok,muted=pcall(m.Sampler.GetMuted)
                if not ok or muted then return fallback("musician_muted",false)end
            end
            local settings=G.Musician_Settings
            local channels=settings and settings.audioChannels
            if type(channels)=="table"and not channels.Master and not channels.SFX and not channels.Dialog then
                return fallback("musician_no_channel",false)
            end
            local ok,song=pcall(m.Song.create)
            if not ok or not song or type(song.ImportFromBase64)~="function"or type(song.Play)~="function"or
                type(song.Resume)~="function"or type(song.Stop)~="function"or type(song.IsPlaying)~="function"then
                return fallback("musician_api_unavailable",true)
            end
            self.song=song;self.importDeadline=host.now()+30
            local generation=self.generation;local started=host.profileMS()
            state("musician","loading")
            local imported,why=pcall(song.ImportFromBase64,song,def.musicianCode,false,function(success)
                if generation~=self.generation or session.stopping or self.song~=song then return end
                self.importDeadline=nil
                perf.note("music.import",{trackId=id,success=success,milliseconds=host.profileMS()-started,bytes=#def.musicianCode})
                if success then self.needsFirstPlay=true;startSong()
                else fallback("musician_import_failed",true)end
            end)
            if not imported and self.song==song then
                perf.note("music.error",{reason=tostring(why)});return fallback("musician_import_failed",true)
            end
            if self.state=="unavailable"then return false,self.lastError end
            return true
        end
        function self.playCode(code)
            if type(code)~="string"or #code==0 or #code>150000 then return false,"music_code_size_limit"end
            session.content.music.__imported={musicianCode=code}
            self.stop("manual_import");return self.play("__imported",{loop=false,retry=true})
        end
        function self.pause()
            self.paused=true
            if self.state=="playing"or self.state=="muted"then
                if self.song then songCall(self.song.Stop,self.song)
                elseif self.handle then host.stopSound(self.handle);self.handle=nil end
                state(self.backend,"paused")
            end
        end
        function self.resume()
            self.paused=false
            if self.state~="paused"or not self.enabled then return end
            if self.song then return startSong()else return native(self.definition)end
        end
        function self.update()
            if self.importDeadline and host.now()>=self.importDeadline then fallback("musician_import_timeout",true)end
            if self.state~="playing"then return end
            local ended=self.handle and host.soundPlaying(self.handle)==false
            if self.song then
                local ok,playing=pcall(self.song.IsPlaying,self.song)
                if not ok then fallback("musician_play_failed",true);return end
                ended=not playing
            end
            if ended then
                if self.loop then
                    if self.song then self.needsFirstPlay=true;startSong()
                    else self.handle=nil;native(self.definition)end
                else self.stop("finished")end
            end
        end
        function self.setEnabled(enabled)
            self.enabled=enabled==true
            if not self.enabled then self.stop("disabled")end
            changed()
        end
        return self
    end
end
