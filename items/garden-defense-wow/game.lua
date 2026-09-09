-- All game state is plain data. The engine owns time, UI, audio and item storage.
return function(ctx, modules)
    local vfx=modules.vfx(ctx)
    local C, floor, min, max, abs = ctx.content, math.floor, math.min, math.max, math.abs
    local plants, plantIndex = {}, {}
    for i, p in ipairs(C.plants) do plants[p.id] = p; plantIndex[p.id] = i end
    local function copy(v)
        if type(v) ~= "table" then return v end
        local out = {}; for k, value in pairs(v) do out[k] = copy(value) end; return out
    end
    local function number(v, lo, hi, integer)
        return type(v)=="number" and v==v and v>=lo and v<=hi and (not integer or v==floor(v))
    end
    local function check(ok) if not ok then error("庭院存档格式无效，原存档已保留。") end end
    local function array(t, limit)
        check(type(t)=="table" and #t<=limit)
        local n=0;for k in pairs(t)do check(number(k,1,#t,true));n=n+1 end;check(n==#t)
    end
    local function rowActive(level, row)
        for _, r in ipairs(C.campaign[level].rows) do if r == row then return true end end
        return false
    end
    local function cellKey(row, col) return tostring((row-1)*9+col) end
    local function cellX(col) return 130+(col-.5)*84 end
    local function rowY(row) return 164+(row-1)*68 end
    local CELL_WIDTH, BITE_CONTACT = 84, 38 -- plant half-width 20 + zombie half-width 18
    local ENDLESS, MAX_SCORE = C.endless, 1000000000
    local function endlessPlan(round)
        local r=min(round,100000)
        local plan
        if r==1 then plan={{"basic",3},{"cone",1}}
        else
            local growth=r-2
            plan={
                {"basic",8+growth*2},
                {"flag",1+floor(growth/5)},
                {"cone",2+floor(growth/2)},
                {"bucket",1+floor(growth/2)},
                {"pole",floor(growth/3)},
                {"paper",floor(growth/4)},
                {"necromancer",floor(growth/4)},
                {"abomination",floor(growth/5)},
            }
        end
        local total=0;for _,entry in ipairs(plan)do total=total+entry[2]end
        return plan,total
    end
    local function endlessRows(round)return round<ENDLESS.allRowsFromRound and ENDLESS.openingRows or C.campaign[ENDLESS.level].rows end
    local function gcd(a,b)while b~=0 do a,b=b,a%b end;return a end
    local function endlessKind(plan,total,round,index)
        local step=5;while gcd(step,total)~=1 do step=step+2 end
        local position=((index-1)*step+round*7)%total+1
        for _,entry in ipairs(plan)do
            if position<=entry[2]then return entry[1]end
            position=position-entry[2]
        end
        return "basic"
    end
    local elite=modules.enemies(C.enemies,cellX)
    local function freeEnemySlot(zombies)
        local used={};for _,z in ipairs(zombies)do if z.viewSlot then used[z.viewSlot]=true end end
        for i=1,48 do if not used[i]then return i end end
    end
    local function validateRun(r, cleared)
        check(type(r)=="table" and number(r.level,1,min(10,cleared+1),true))
        local endless=r.mode=="endless"
        local endlessTotal
        check(r.mode==nil or r.mode=="campaign" or endless)
        if endless then
            check(cleared==10 and r.level==ENDLESS.level and number(r.round,1,1000000,true) and number(r.score,0,MAX_SCORE,true))
            local _,total=endlessPlan(r.round);endlessTotal=total;check(number(r.roundTotal,1,1000000,true))
        end
        check(r.status=="playing" or r.status=="won" or r.status=="lost")
        for _, key in ipairs({"time","nextSky","waveTime","nextWave","spawnClock"}) do check(number(r[key],0,1e7)) end
        check(number(r.sun,0,9990,true) and number(r.wave,0,endless and 1 or #C.campaign[r.level].waves,true))
        check(number(r.spawnIndex,1,endless and 1000000 or 100,true) and number(r.rng,1,2147483646,true) and number(r.kills,0,MAX_SCORE,true))
        if endless then r.roundTotal=endlessTotal;r.spawnIndex=min(r.spawnIndex,endlessTotal+1)end
        check(type(r.plants)=="table" and type(r.cooldowns)=="table")
        for k,p in pairs(r.plants)do
            check(type(p)=="table" and plants[p.kind] and plantIndex[p.kind]<=min(10,cleared+1))
            check(number(p.row,1,5,true) and rowActive(r.level,p.row) and number(p.col,1,9,true) and k==cellKey(p.row,p.col))
            check(number(p.hp,.001,plants[p.kind].hp) and number(p.age,0,1e7) and number(p.timer,0,100))
        end
        for id, v in pairs(r.cooldowns) do check(plants[id] and number(v,0,100)) end
        array(r.zombies,48);array(r.bullets,160);array(r.suns,60);array(r.mowers,5);check(#r.mowers==5)
        if r.enemyBolts==nil then r.enemyBolts={}end -- additive upgrade of existing battle saves
        array(r.enemyBolts,80)
        local viewSlots={}
        for _, z in ipairs(r.zombies) do
            check(type(z)=="table" and C.enemies[z.kind] and number(z.hp,.001,C.enemies[z.kind].hp))
            check(number(z.row,1,5,true) and rowActive(r.level,z.row) and number(z.x,0,1000) and number(z.slow,0,6) and type(z.jumped)=="boolean")
            if z.phase~=nil then check(z.phase=="advance" or z.phase=="vomit" or z.phase=="stunned")end
            for _,key in ipairs({"phaseTime","abilityCooldown","shotCooldown","biteSoundCooldown"})do if z[key]~=nil then check(number(z[key],0,120))end end
            z.biteSoundCooldown=nil -- superseded by impact-triggered, wall-time audio admission
            if z.viewSlot then check(number(z.viewSlot,1,48,true) and not viewSlots[z.viewSlot]);viewSlots[z.viewSlot]=true end
            if z.attackTime~=nil then
                check(number(z.attackTime,0,C.enemies[z.kind].melee.period) and type(z.attackHit)=="boolean" and number(z.attackCol,1,9,true))
            end
        end
        for _,z in ipairs(r.zombies)do if not z.viewSlot then z.viewSlot=freeEnemySlot(r.zombies)end end
        for _, b in ipairs(r.bullets) do
            check(type(b)=="table" and number(b.row,1,5,true) and number(b.x,0,1100) and number(b.remaining,0,1100))
            check(number(b.damage,1,100) and type(b.ice)=="boolean" and type(b.spore)=="boolean")
        end
        for _,b in ipairs(r.enemyBolts)do
            check(type(b)=="table" and number(b.row,1,5,true) and number(b.x,0,1100) and number(b.remaining,0,600))
            check(number(b.damage,0,300) and number(b.speed,1,1000))
        end
        for _, s in ipairs(r.suns) do
            check(type(s)=="table" and number(s.x,100,940) and number(s.y,140,520) and number(s.ttl,0,20))
            check(s.value==15 or s.value==25)
        end
        for _, m in ipairs(r.mowers) do check(number(m,-1,1000)) end
    end
    local book = copy(ctx.save.data)
    if next(book)==nil then book={format=1,slots={},active=0,sound=true,music=true} end
    if book.speed==nil then book.speed=1 end
    if book.music==nil then book.music=true end
    if book.musicVolume==nil then book.musicVolume=1 end
    if book.musicSource==nil then book.musicSource="auto"end
    check(book.musicSource=="auto"or book.musicSource=="native")
    if book.hitVolume==nil then book.hitVolume=.5 end
    if book.soundVolume==nil then book.soundVolume=1 end
    check(number(book.hitVolume,0,1)and number(book.soundVolume,0,1)and number(book.musicVolume,0,1))
    check(book.speed==1 or book.speed==2)
    check(book.format==1 and type(book.slots)=="table" and number(book.active,0,3,true) and type(book.sound)=="boolean" and type(book.music)=="boolean")
    local trackers={}
    for key,slot in pairs(book.slots)do
        check(key=="1" or key=="2" or key=="3")
        check(type(slot)=="table" and type(slot.name)=="string" and #slot.name<=60)
        check(number(slot.cleared,0,10,true) and number(slot.coins,0,1000000,true))
        if slot.run then validateRun(slot.run,slot.cleared) end
        trackers[key]=modules.progress.new(slot.progress,{cleared=slot.cleared})
        slot.progress=trackers[key].data
    end
    local screen, selected, message, saveStatus = "profiles", "pea", "", "存档保存在本道具"
    local slot, run, render, confirm, help, dirty, saveTimer, drawTimer
    local pauseMenu,settings,lastPauseSaved=false,false,true
    local musicSettings,musicPreview,musicError=false,nil,nil
    local tracker,progressTab,progressWasPaused,achievementNotice
    local achievementTTL=0
    saveTimer, drawTimer = 0, 0
    local sunEffects = {}
    local function say(text) message=text end
    local function sound(id) if book.sound then ctx.sound.play(id) end end
    local function musicFailure(reason)
        local messages={
            all_sound_disabled="魔兽总声音已关闭，请在系统 → 音频开启声音。",
            master_volume_zero="魔兽总音量为零，请调高总音量后重试。",
            channel_disabled="魔兽音效通道已关闭，请在系统 → 音频开启音效。",
            channel_volume_zero="魔兽音效音量为零，请调高音效音量后重试。",
            sound_not_started="客户端未能启动此曲目，请重试或保留 IG 日志。",
            sound_api_error="原生声音接口调用失败，请保留 IG 日志。",
            sound_unavailable="当前客户端缺少原生声音接口或曲目资源。",
            music_volume_unsupported="当前曲目或客户端不支持独立 BGM 音量。",
            sound_volume_unsupported="当前曲目或客户端不支持独立 BGM 音量。",
        }
        return messages[reason]or "音乐播放失败（"..tostring(reason).."）。"
    end
    local function sceneMusicId()
        if screen=="profiles"or screen=="map"then return "menu"end
        if screen=="battle"and run and run.status=="playing"then
            return (run.mode=="endless"or C.campaign[run.level].theme=="night")and "battle_night"or "battle_day"
        end
    end
    local function playSceneMusic()
        local id=sceneMusicId()
        if not book.music or not id then ctx.music.stop("not_in_music_scene");return end
        ctx.music.setEnabled(true)
        local ok,reason=ctx.music.play(id,{loop=true})
        if ok then musicError=nil else musicError=musicFailure(reason)end
    end
    local function closeMusicSettings()
        if not musicSettings then return end
        local wasPreview=musicPreview~=nil or ctx.music.playWhilePaused
        musicSettings=false;musicPreview=nil;musicError=nil
        if wasPreview then ctx.music.stop("preview_closed")end
        playSceneMusic()
    end
    local function persist(reason)
        local ok, why = ctx.save.flush(reason)
        if ok then dirty=false;saveTimer=0;saveStatus="已自动保存"
        else dirty=true;saveTimer=0;saveStatus="保存失败，请勿关闭道具";ctx.ui.notify("存档未写入："..tostring(why)) end
        return ok
    end
    local function changed() dirty=true end
    local function record(event,payload)
        if not tracker then return end
        local gained=tracker.record(event,payload)
        if event~="time" then changed()end
        if #gained>0 then
            local titles={};for _,a in ipairs(gained)do titles[#titles+1]=a.title end
            achievementNotice="成就达成："..table.concat(titles," · ");achievementTTL=5
            sound("ui_select")
        end
    end
    local function openPauseMenu(reason)
        closeMusicSettings()
        pauseMenu=true;settings=false;help=false;confirm=nil;progressTab=nil
        if ctx.session.isPaused()then lastPauseSaved=persist(reason or "pause_menu")
        else ctx.session.pause(reason or "pause_menu")end
        if render then render()end
        return lastPauseSaved
    end
    local function resumeGame()
        closeMusicSettings()
        pauseMenu=false;settings=false;help=false;progressTab=nil;ctx.session.resume()
    end
    local function random(n)
        run.rng=(run.rng*16807)%2147483647
        return (run.rng%n)+1
    end
    local function unlockCount() return slot and min(10,slot.cleared+1) or 1 end
    local function addSun(x,y,value)
        if #run.suns>=60 then return end
        run.suns[#run.suns+1]={x=x,y=y,value=value,ttl=16}
    end
    local function collect(index)
        if screen~="battle" or not run or run.status~="playing" or ctx.session.isPaused() then return end
        local s=run.suns[index];if not s then return end
        if #sunEffects<60 then sunEffects[#sunEffects+1]={x=s.x,y=s.y,value=s.value,ttl=.45}end
        ctx.fx.burst("sun_collect",{x=s.x,y=s.y,seed=run.rng})
        local amount=min(s.value,9990-run.sun)
        run.sun=run.sun+amount;table.remove(run.suns,index);sound("sun");record("sun",{amount=amount});changed()
    end
    local function collectAll()
        if not run then return end
        for i=#run.suns,1,-1 do collect(i) end
    end
    local function createSlot(index)
        local key=tostring(index);if book.slots[key] then return end
        local previous=book.active
        local value={name="花园 "..index,cleared=0,coins=0}
        local progress=modules.progress.new()
        value.progress=progress.data
        book.slots[key]=value;book.active=index
        if not persist("create_profile") then book.slots[key]=nil;book.active=previous;return end
        trackers[key]=progress;tracker=progress
        slot=value;run=nil;screen="map";progressTab=nil;achievementNotice=nil;message="第一关已开放。点击地图上的 1 开始。"
        playSceneMusic()
    end
    local function loadSlot(index)
        local value=book.slots[tostring(index)];if not value then return end
        if dirty and not persist("before_load") then return end
        slot=value;run=slot.run;book.active=index;screen=run and "battle" or "map";selected="pea";sunEffects={};ctx.fx.clear()
        tracker=trackers[tostring(index)];progressTab=nil;achievementNotice=nil
        ctx.level.load(run and C.campaign[run.level].theme=="night" and "lawn_night" or "lawn_day");playSceneMusic()
        changed();persist("load_profile");message=run and "战局已恢复。阳光、冷却和波次均保留。" or "选择已开放的关卡。"
        if run and run.status=="playing" then ctx.session.pause("loaded_game") end
    end
    local function deleteSlot(index)
        local key=tostring(index);local previous=book.slots[key];local active=book.active
        book.slots[key]=nil;if active==index then book.active=0 end
        if not persist("delete_profile") then book.slots[key]=previous;book.active=active;return end
        trackers[key]=nil
        if active==index then slot=nil;run=nil;tracker=nil;progressTab=nil;achievementNotice=nil end
        confirm=nil;say("存档已删除，可以在这个位置重新建档。")
    end
    local function startLevel(level)
        if not slot or level>min(10,slot.cleared+1) then return end
        local def=C.campaign[level]
        run={mode="campaign",level=level,status="playing",time=0,sun=def.sun,nextSky=def.sky>0 and def.sky or 0,
            nextWave=def.prepare,wave=0,waveTime=0,spawnIndex=1,spawnClock=0,plants={},zombies={},bullets={},enemyBolts={},suns={},
            mowers={0,0,0,0,0},cooldowns={},kills=0,rng=1977+level*7919}
        slot.run=run;selected="pea";screen="battle";sunEffects={};ctx.fx.clear();ctx.level.load(def.theme=="night" and "lawn_night" or "lawn_day")
        progressTab=nil;achievementNotice=nil;record("run_started",{level=level})
        say("新植物："..C.plants[level].name.."。"..C.plants[level].tip)
        changed();persist("level_start");ctx.session.resume();playSceneMusic()
    end
    local function startEndless()
        if not slot or slot.cleared<10 then return end
        local level,def=ENDLESS.level,C.campaign[ENDLESS.level]
        local _,total=endlessPlan(1)
        run={mode="endless",level=level,status="playing",time=0,sun=def.sun,nextSky=0,
            nextWave=ENDLESS.prepare,wave=0,waveTime=0,spawnIndex=1,spawnClock=0,round=1,roundTotal=total,score=0,
            plants={},zombies={},bullets={},enemyBolts={},suns={},mowers={0,0,0,0,0},cooldowns={},kills=0,rng=1977+79190}
        slot.run=run;selected="pea";screen="battle";sunEffects={};ctx.fx.clear();ctx.level.load("lawn_night")
        progressTab=nil;achievementNotice=nil;record("run_started",{level=level,mode="endless"})
        record("endless_progress",{round=1,score=0})
        say("无尽挑战开始：第 1 轮将在 "..ENDLESS.prepare.." 秒后抵达。")
        changed();persist("endless_start");ctx.session.resume();playSceneMusic()
    end
    local function leaveBattle()
        if not persist("return_to_map") then return end
        screen=slot and "map" or "profiles";ctx.fx.clear();ctx.music.stop("return_to_map");resumeGame()
        playSceneMusic()
        say(slot and "当前战局已保留，点击“继续战局”返回。" or "选择存档或建立新的防线。")
    end
    local function plantAt(row,col,mouse)
        if screen~="battle" or ctx.session.isPaused() or not run or run.status~="playing" or not rowActive(run.level,row) then return end
        if mouse=="RightButton" then selected=nil;say("已取消选择。");return end
        local key=cellKey(row,col)
        if selected=="shovel" then
            if run.plants[key] then run.plants[key]=nil;changed();sound("plant");say("已铲除，不返还阳光。") end
            return
        end
        local p=plants[selected];if not p then say("先点击一张种子卡。");return end
        if run.plants[key] then say("这里已有植物。用铲子移除后再种植。");return end
        if plantIndex[selected]>unlockCount() then return end
        if run.sun<p.cost then say("阳光不足：需要 "..p.cost.." 阳光。");return end
        if (run.cooldowns[selected] or 0)>0 then say("种子还在冷却。");return end
        local value={kind=selected,row=row,col=col,hp=p.hp,age=0,timer=(selected=="sunflower" or selected=="sunshroom") and 6 or 0}
        run.plants[key]=value;run.sun=run.sun-p.cost;run.cooldowns[selected]=p.reload;sound("plant");changed()
        record("plant",{kind=selected,cost=p.cost})
        say(p.name.."已种下。"..(selected=="mine" and "12秒后武装。" or p.tip))
    end
    local function nearest(row,x,range)
        local target
        for _, z in ipairs(run.zombies) do
            if z.hp>0 and z.row==row and z.x>=x-18 and z.x-x<=range and (not target or z.x<target.x) then target=z end
        end
        return target
    end
    local function blast(row,x,radius,rows,lethal)
        for _, z in ipairs(run.zombies) do
            if abs(z.row-row)<=rows and abs(z.x-x)<=radius then z.hp=lethal and 0 or z.hp-1800 end
        end
        vfx.explosion(x,rowY(row)+32,radius)
        sound("explode")
    end
    local function fire(p,offset)
        if #run.bullets>=160 then return end
        run.bullets[#run.bullets+1]={row=p.row,x=cellX(p.col)+24-(offset or 0),remaining=p.kind=="puff" and 252 or 920,
            damage=plants[p.kind].damage,ice=p.kind=="snow",spore=p.kind=="puff"}
    end
    local schedules={}
    for level, def in ipairs(C.campaign)do
        schedules[level]={}
        for w,wave in ipairs(def.waves)do
            local list={};for _,group in ipairs(wave.types)do for _=1,group[2]do list[#list+1]=group[1]end end
            schedules[level][w]=list
        end
    end
    local function removeDefeated()
        for i=#run.zombies,1,-1 do
            if run.zombies[i].hp<=0 then
                local kind=run.zombies[i].kind
                record("kill",{kind=kind})
                if run.mode=="endless"then
                    run.score=min(MAX_SCORE,run.score+(ENDLESS.score[kind]or 0))
                    record("endless_progress",{round=run.round,score=run.score})
                end
                table.remove(run.zombies,i);run.kills=run.kills+1
            end
        end
    end
    local function finish(status)
        if run.status~="playing" then return end
        run.status=status;run.enemyBolts={};ctx.music.stop("battle_finished")
        removeDefeated()
        if run.mode=="endless"then
            record("endless_progress",{round=run.round,score=run.score})
            say("无尽挑战结束：到达第 "..run.round.." 轮，获得 "..run.score.." 分。")
            sound("lose");changed();persist("endless_"..status);return
        end
        local noMowersUsed=true;for _,mower in ipairs(run.mowers)do if mower~=0 then noMowersUsed=false end end
        record(status=="won" and "win" or "loss",{level=run.level,duration=run.time,noMowersUsed=noMowersUsed})
        if status=="won" then
            local first=run.level>slot.cleared
            if first then slot.cleared=run.level;slot.coins=slot.coins+100+run.level*25 end
            say(first and run.level==10 and "十关通关！无尽挑战已解锁。" or first and ("首次通关！获得 "..(100+run.level*25).." 金币。") or "再次守住了庭院。")
            sound("win")
        else say("僵尸进入了家门。重试本关，调整你的防线。");sound("lose") end
        changed();persist(status)
    end
    local function simulate(dt)
        if screen~="battle" or not run or run.status~="playing" then return end
        local def=C.campaign[run.level];run.time=run.time+dt
        record("time",{seconds=dt/book.speed})
        for id,value in pairs(run.cooldowns)do run.cooldowns[id]=max(0,value-dt)end
        if def.sky>0 and run.time>=run.nextSky then
            addSun(150+random(700),168+random(315),25);run.nextSky=run.time+def.sky
        end
        for i=#run.suns,1,-1 do local s=run.suns[i];s.ttl=s.ttl-dt;if s.ttl<=0 then table.remove(run.suns,i)end end
        if run.mode=="endless"then
            if run.time>=run.nextWave then
                local plan,total=endlessPlan(run.round)
                run.spawnClock=max(0,run.spawnClock-dt)
                if run.spawnIndex<=total and run.spawnClock<=0 and #run.zombies<48 then
                    local kind=endlessKind(plan,total,run.round,run.spawnIndex);local d=C.enemies[kind]
                    local rows=endlessRows(run.round);local row=rows[random(#rows)];local viewSlot=freeEnemySlot(run.zombies)
                    run.zombies[#run.zombies+1]={kind=kind,row=row,x=925,hp=d.hp,slow=0,jumped=false,viewSlot=viewSlot}
                    run.spawnIndex=run.spawnIndex+1
                    run.spawnClock=max(ENDLESS.spawnIntervalMin,ENDLESS.spawnIntervalBase-run.round*ENDLESS.spawnIntervalStep)
                end
                if run.spawnIndex>total and #run.zombies==0 then
                    local completed=run.round
                    local reward=min(ENDLESS.roundSunMax,ENDLESS.roundSunBase+completed*ENDLESS.roundSunStep)
                    run.sun=min(9990,run.sun+reward);run.round=completed+1;run.spawnIndex=1;run.spawnClock=0
                    local _,nextTotal=endlessPlan(run.round);run.roundTotal=nextTotal;run.nextWave=run.time+ENDLESS.roundGap
                    record("endless_progress",{round=run.round,score=run.score})
                    sound("wave");say("第 "..completed.." 轮完成，获得 "..reward.." 阳光；下一轮敌军增至 "..nextTotal.." 名。")
                    changed()
                end
            end
        else
            -- Campaign waves are explicit content; only lane selection uses the saved PRNG.
            if run.wave==0 then
                if run.time>=run.nextWave then run.wave=1;run.waveTime=run.time;run.spawnClock=0;sound("wave");changed() end
            end
            if run.wave>0 then
                local sequence=schedules[run.level][run.wave];local wave=def.waves[run.wave]
                run.spawnClock=max(0,run.spawnClock-dt)
                if run.spawnIndex<=#sequence and run.spawnClock<=0 and #run.zombies<48 then
                    local kind=sequence[run.spawnIndex];local d=C.enemies[kind]
                    local row=def.rows[random(#def.rows)]
                    local viewSlot=freeEnemySlot(run.zombies)
                    run.zombies[#run.zombies+1]={kind=kind,row=row,x=925,hp=d.hp,slow=0,jumped=false,viewSlot=viewSlot}
                    run.spawnIndex=run.spawnIndex+1;run.spawnClock=wave.interval
                end
                if run.spawnIndex>#sequence and #run.zombies==0 then
                    if run.wave==#def.waves then finish("won");return end
                    if run.nextWave<=run.waveTime then run.nextWave=run.time+wave.gap;changed() end
                    if run.time>=run.nextWave then
                        run.wave=run.wave+1;run.waveTime=run.time;run.spawnIndex=1;run.spawnClock=0
                        sound("wave");say(run.wave==#def.waves and "最后一波！守住家门！" or "第 "..run.wave.." 波来袭。");changed()
                    end
                end
            end
        end
        for key,p in pairs(run.plants)do
            p.age=p.age+dt;p.timer=max(0,p.timer-dt)
            local sleeping=(p.kind=="puff" or p.kind=="sunshroom") and def.theme~="night"
            if not sleeping then
                if p.kind=="cherry" and p.age>=1.2 then blast(p.row,cellX(p.col),126,1);run.plants[key]=nil
                elseif p.kind=="mine" and p.age>=12 and nearest(p.row,cellX(p.col),BITE_CONTACT) then blast(p.row,cellX(p.col),48,0,true);run.plants[key]=nil
                elseif p.kind=="chomper" then
                    -- Include an enemy touching the plant in the next cell, not just its centre.
                    local z=nearest(p.row,cellX(p.col),CELL_WIDTH+BITE_CONTACT)
                    if p.timer<=0 and z then z.hp=0;p.timer=20;sound("hit_devour") end
                elseif p.kind=="sunflower" or p.kind=="sunshroom" then
                    if p.timer<=0 then addSun(cellX(p.col)+8,rowY(p.row)+20,p.kind=="sunshroom" and p.age<90 and 15 or 25);p.timer=plants[p.kind].interval end
                elseif plants[p.kind].damage and p.timer<=0 and nearest(p.row,cellX(p.col),p.kind=="puff" and 252 or 1000) then
                    fire(p);if p.kind=="repeater" then fire(p,24)end;p.timer=plants[p.kind].interval
                end
            end
        end
        for i=#run.bullets,1,-1 do
            local b=run.bullets[i];local old=b.x;local dx=min(320*dt,b.remaining);b.x=b.x+dx;b.remaining=b.remaining-dx
            local target
            for _,z in ipairs(run.zombies)do
                if z.hp>0 and z.row==b.row and z.x+18>=old and z.x-18<=b.x and (not target or z.x<target.x)then target=z end
            end
            if target then
                target.hp=target.hp-b.damage;if b.ice then target.slow=5 end
                vfx.impact(b.ice,b.spore,max(old,min(b.x,target.x-18)),rowY(b.row)+31)
                sound(b.ice and "hit_frost" or b.spore and "hit_spore" or "hit_nature")
            end
            if target or b.x>950 or b.remaining<=0 then table.remove(run.bullets,i)end
        end
        elite.projectiles(run,dt,sound)
        for _,z in ipairs(run.zombies)do
            if z.hp>0 then
                local d=C.enemies[z.kind];z.slow=max(0,z.slow-dt)
                local speed=d.speed*(z.slow>0 and .5 or 1)
                if z.kind=="pole" and z.jumped then speed=speed*.58 end
                if z.kind=="paper" and z.hp<=180 then speed=speed*2.2 end
                local obstacle
                for _,p in pairs(run.plants)do
                    local x=cellX(p.col)
                    if p.row==z.row and z.x>=x-18 and z.x<=x+BITE_CONTACT and (not obstacle or p.col>obstacle.col)then obstacle=p end
                end
                local blocked=elite.step(z,run,dt,sound)
                if not blocked and obstacle then
                    if z.kind=="pole" and not z.jumped then z.jumped=true;z.x=cellX(obstacle.col)-52;elite.cancelMelee(z)
                    else
                        if elite.melee(z,obstacle,run,dt,sound)then drawTimer=.1 end
                    end
                else
                    if elite.cancelMelee(z)then drawTimer=.1 end
                    if not blocked then z.x=z.x-speed*dt end
                end
                if z.x<=108 then
                    if run.mowers[z.row]==0 then run.mowers[z.row]=108;sound("wave");record("mower",{row=z.row})
                    elseif run.mowers[z.row]<0 and z.x<80 then finish("lost");return end
                end
            end
        end
        for row,x in ipairs(run.mowers)do
            if x>0 then
                local nextX=x+460*dt
                local crushed=false
                for _,z in ipairs(run.zombies)do if z.hp>0 and z.row==row and z.x>=x-35 and z.x<=nextX+35 then z.hp=0;crushed=true end end
                if crushed then sound("mower_hit")end
                run.mowers[row]=nextX>965 and -1 or nextX
            end
        end
        removeDefeated()
        for i=#sunEffects,1,-1 do sunEffects[i].ttl=sunEffects[i].ttl-dt;if sunEffects[i].ttl<=0 then table.remove(sunEffects,i)end end
    end

    local function exitCurrentRun()
        if screen~="battle"or not run then return end
        if run.mode=="endless"then
            finish("lost")
            pauseMenu=false;settings=false;help=false;confirm=nil
            if ctx.session.isPaused()then ctx.session.resume()end
            return
        end
        local previous=run;slot.run=nil;run=nil
        if not persist("campaign_abandoned")then slot.run=previous;run=previous;return end
        screen="map";selected="pea";sunEffects={};ctx.fx.clear();ctx.music.stop("campaign_abandoned")
        pauseMenu=false;settings=false;help=false;confirm=nil;say("已退出本关；通关进度、统计成就、金币及设置均已保留。")
        if ctx.session.isPaused()then ctx.session.resume()end
        playSceneMusic()
    end

    local function selectPlant(id)
        if plantIndex[id]>unlockCount() then say("通关前一关后，在第 "..plantIndex[id].." 关解锁。");return end
        selected=id;say(plants[id].name.."："..plants[id].tip)
    end
    local actions={
        cellKey=cellKey,cellX=cellX,rowY=rowY,rowActive=rowActive,unlockCount=unlockCount,
        createSlot=createSlot,loadSlot=loadSlot,startLevel=startLevel,startEndless=startEndless,leaveBattle=leaveBattle,exitCurrentRun=exitCurrentRun,
        plantAt=plantAt,collect=collect,collectAll=collectAll,persist=persist,selectPlant=selectPlant,
        pause=function()openPauseMenu("user")end,
        resume=resumeGame,
        showSettings=function()closeMusicSettings();settings=true;pauseMenu=true end,
        backToPause=function()closeMusicSettings();settings=false;pauseMenu=true end,
        showMusicSettings=function()
            openPauseMenu("music_settings");musicSettings=true;settings=false
        end,
        previewMusic=function(id)
            if not musicSettings or not book.music or (id~="battle_day"and id~="battle_night"and id~="menu")then return end
            ctx.music.stop("preview_switch");musicPreview=id;musicError=nil
            local ok,reason=ctx.music.play(id,{loop=true,playWhilePaused=true,retry=true})
            if not ok then musicPreview=nil;musicError=musicFailure(reason)end
        end,
        stopMusicPreview=function()
            if not musicSettings then return end
            musicPreview=nil;musicError=nil;ctx.music.stop("preview_stopped")
        end,
        showProgress=function()
            if not tracker or screen=="profiles" then return end
            progressWasPaused=ctx.session.isPaused();progressTab="stats";help=false;settings=false;confirm=nil
            ctx.session.pause("progress")
        end,
        progressTab=function(tab)progressTab=tab=="achievements" and "achievements" or "stats" end,
        closeProgress=function()
            progressTab=nil
            if progressWasPaused then pauseMenu=true;settings=false else resumeGame()end
        end,
        saveAndExit=function()if persist("save_and_exit")then ctx.session.stop("user_exit",{save=false})end end,
        requestDelete=function(index)confirm={kind="delete",index=index}end,
        requestRestart=function()if run and screen=="battle"then confirm={kind="restart",level=run.level,mode=run.mode}end end,
        chooseEndless=function()
            if not slot or slot.cleared<10 then return end
            if run and run.status=="playing"then confirm={kind="replace_endless"}else startEndless()end
        end,
        chooseLevel=function(level)
            if run and run.status=="playing" then confirm={kind="replace",level=level} else startLevel(level)end
        end,
        openProfiles=function()if persist("profiles")then screen="profiles";progressTab=nil;ctx.fx.clear();ctx.music.stop("profiles");ctx.session.resume();playSceneMusic()end end,
        continueBattle=function()
            if run then screen="battle";ctx.level.load(C.campaign[run.level].theme=="night" and "lawn_night" or "lawn_day");playSceneMusic() else startLevel(1)end
        end,
        toggleShovel=function()selected=selected=="shovel" and nil or "shovel";say("点击植物铲除；不返还阳光。")end,
        toggleSound=function()book.sound=not book.sound;ctx.sound.setEnabled(book.sound);changed();persist("sound_setting")end,
        adjustVolume=function(bus,delta)
            local key=bus=="impact"and "hitVolume"or "soundVolume"
            book[key]=max(0,min(1,floor((book[key]+delta)*100+.5)/100))
            if bus=="impact"then ctx.sound.setBusVolume(bus,book[key])else ctx.sound.setVolume(book[key])end
            changed();persist("sound_volume")
        end,
        toggleMusic=function()
            musicPreview=nil;musicError=nil
            book.music=not book.music;ctx.music.setEnabled(book.music)
            if book.music and not musicSettings then playSceneMusic()end
            changed();persist("music_setting")
        end,
        toggleMusicSource=function()
            local preview=musicPreview
            book.musicSource=book.musicSource=="auto"and "native"or "auto"
            musicPreview=nil;musicError=nil;ctx.music.setBackend(book.musicSource)
            if book.music then
                if musicSettings and preview then
                    musicPreview=preview
                    local ok,reason=ctx.music.play(preview,{loop=true,playWhilePaused=true,retry=true})
                    if not ok then musicPreview=nil;musicError=musicFailure(reason)end
                else playSceneMusic()end
            end
            changed();persist("music_source")
        end,
        unmuteMusic=function()
            ctx.music.setVolume(1);book.musicVolume=ctx.music.getVolume();musicError=nil
            changed();persist("music_volume")
        end,
        adjustMusicVolume=function(delta)
            local volume=max(0,min(1,floor((book.musicVolume+delta)*100+.5)/100))
            local ok,reason=ctx.music.setVolume(volume)
            book.musicVolume=ctx.music.getVolume()
            if ok then musicError=nil else musicError=musicFailure(reason)end
            changed();persist("music_volume")
        end,
        toggleSpeed=function()
            book.speed=book.speed==1 and 2 or 1;ctx.session.setSpeed(book.speed)
            changed();persist("speed_setting");say(book.speed==2 and "2倍速：整场战局和冷却同步加速。" or "已恢复正常速度。")
        end,
        showHelp=function()help=true;pauseMenu=false;settings=false;ctx.session.pause("help")end,
        hideHelp=resumeGame,
        acceptConfirm=function()
            local c=confirm;confirm=nil;if not c then return end
            if c.kind=="delete"then deleteSlot(c.index)
            elseif c.kind=="replace_endless"or(c.kind=="restart"and c.mode=="endless")then startEndless()
            else startLevel(c.level)end
        end,
        cancelConfirm=function()confirm=nil end,
    }
    local function presentationState()
        return {book=book,slot=slot,run=run,screen=screen,selected=selected,message=message,
            saveStatus=saveStatus,sunEffects=sunEffects,help=help,confirm=confirm,pauseMenu=pauseMenu,settings=settings,
            music={open=musicSettings,preview=musicPreview,error=musicError or (ctx.music.lastError and musicFailure(ctx.music.lastError)),state=ctx.music.state,
                track=sceneMusicId(),source=book.musicSource,backend=ctx.music.backend,
                musicianAvailable=ctx.music.capabilities().musician,fallback=ctx.music.fallbackReason},
            achievementNotice=achievementNotice,progress=progressTab and tracker and {
                tab=progressTab,summary=tracker.summary(),achievements=tracker.achievements()} or nil}
    end
    return {
        onStart=function()
            ctx.level.load("lawn_day");ctx.input.release();ctx.sound.setEnabled(book.sound);ctx.music.setEnabled(book.music);ctx.session.setSpeed(book.speed)
            ctx.music.setBackend(book.musicSource)
            ctx.sound.setVolume(book.soundVolume);ctx.sound.setBusVolume("impact",book.hitVolume)
            local volumeOK,volumeReason=ctx.music.setVolume(book.musicVolume)
            if not volumeOK then musicError=musicFailure(volumeReason)end
            render=modules.ui(ctx,presentationState,actions,modules.progress_ui);say("选择一份存档，或在空槽建立新的花园。");render();sound("ui_open")
            playSceneMusic()
        end,
        onFixedUpdate=function(dt)
            if achievementNotice then achievementTTL=achievementTTL-dt/book.speed;if achievementTTL<=0 then achievementNotice=nil end end
            simulate(dt);saveTimer=saveTimer+dt;drawTimer=drawTimer+dt
            if (dirty and saveTimer>=.65) or (screen=="battle" and run.status=="playing" and saveTimer>=5) then persist("autosave")end
            if drawTimer>=.1 then drawTimer=0;render()end
        end,
        onPause=function(reason)
            if reason~="help"then pauseMenu=true end
            lastPauseSaved=persist("pause");render()
        end,
        onResume=function()
            closeMusicSettings();pauseMenu=false;settings=false;progressTab=nil
            playSceneMusic()
            render()
        end,
        onMusicChanged=function()if render then render()end end,
        onCloseRequested=function(reason)
            local saved=openPauseMenu(reason)
            if saved and reason=="window_closed"then ctx.session.suspend()end
            if reason=="window_hidden"then ctx.ui.notify("战局已暂停，重新使用道具可返回。")end
        end,
        onSave=function()return copy(book)end,
    }
end
