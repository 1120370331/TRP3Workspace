-- All game state is plain data. The engine owns time, UI, audio and item storage.
return function(ctx, modules)
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
    local function validateRun(r, cleared)
        check(type(r)=="table" and number(r.level,1,min(10,cleared+1),true))
        check(r.status=="playing" or r.status=="won" or r.status=="lost")
        for _, key in ipairs({"time","nextSky","waveTime","nextWave","spawnClock"}) do check(number(r[key],0,1e7)) end
        check(number(r.sun,0,9990,true) and number(r.wave,0,#C.campaign[r.level].waves,true))
        check(number(r.spawnIndex,1,100,true) and number(r.rng,1,2147483646,true) and number(r.kills,0,10000,true))
        check(type(r.plants)=="table" and type(r.cooldowns)=="table")
        for k,p in pairs(r.plants)do
            check(type(p)=="table" and plants[p.kind] and plantIndex[p.kind]<=min(10,cleared+1))
            check(number(p.row,1,5,true) and rowActive(r.level,p.row) and number(p.col,1,9,true) and k==cellKey(p.row,p.col))
            check(number(p.hp,.001,plants[p.kind].hp) and number(p.age,0,1e7) and number(p.timer,0,100))
        end
        for id, v in pairs(r.cooldowns) do check(plants[id] and number(v,0,100)) end
        array(r.zombies,48);array(r.bullets,160);array(r.suns,60);array(r.mowers,5);check(#r.mowers==5)
        for _, z in ipairs(r.zombies) do
            check(type(z)=="table" and C.enemies[z.kind] and number(z.hp,.001,C.enemies[z.kind].hp))
            check(number(z.row,1,5,true) and rowActive(r.level,z.row) and number(z.x,0,1000) and number(z.slow,0,6) and type(z.jumped)=="boolean")
        end
        for _, b in ipairs(r.bullets) do
            check(type(b)=="table" and number(b.row,1,5,true) and number(b.x,0,1100) and number(b.remaining,0,1100))
            check(number(b.damage,1,100) and type(b.ice)=="boolean" and type(b.spore)=="boolean")
        end
        for _, s in ipairs(r.suns) do
            check(type(s)=="table" and number(s.x,100,940) and number(s.y,140,520) and number(s.ttl,0,20))
            check(s.value==15 or s.value==25)
        end
        for _, m in ipairs(r.mowers) do check(number(m,-1,1000)) end
    end
    local book = copy(ctx.save.data)
    if next(book)==nil then book={format=1,slots={},active=0,sound=true} end
    check(book.format==1 and type(book.slots)=="table" and number(book.active,0,3,true) and type(book.sound)=="boolean")
    for key,slot in pairs(book.slots)do
        check(key=="1" or key=="2" or key=="3")
        check(type(slot)=="table" and type(slot.name)=="string" and #slot.name<=60)
        check(number(slot.cleared,0,10,true) and number(slot.coins,0,1000000,true))
        if slot.run then validateRun(slot.run,slot.cleared) end
    end
    local screen, selected, message, saveStatus = "profiles", "pea", "", "存档保存在本道具"
    local slot, run, render, confirm, help, dirty, saveTimer, drawTimer
    saveTimer, drawTimer = 0, 0
    local flashes = {}
    local function say(text) message=text end
    local function sound(id) if book.sound then ctx.sound.play(id) end end
    local function persist(reason)
        local ok, why = ctx.save.flush(reason)
        if ok then dirty=false;saveTimer=0;saveStatus="已自动保存"
        else dirty=true;saveTimer=0;saveStatus="保存失败，请勿关闭道具";ctx.ui.notify("存档未写入："..tostring(why)) end
        return ok
    end
    local function changed() dirty=true end
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
        run.sun=min(9990,run.sun+s.value);table.remove(run.suns,index);sound("sun");changed()
    end
    local function collectAll()
        if not run then return end
        for i=#run.suns,1,-1 do collect(i) end
    end
    local function createSlot(index)
        local key=tostring(index);if book.slots[key] then return end
        local previous=book.active
        local value={name="花园 "..index,cleared=0,coins=0}
        book.slots[key]=value;book.active=index
        if not persist("create_profile") then book.slots[key]=nil;book.active=previous;return end
        slot=value;run=nil;screen="map";message="第一关已开放。点击地图上的 1 开始。"
    end
    local function loadSlot(index)
        local value=book.slots[tostring(index)];if not value then return end
        if dirty and not persist("before_load") then return end
        slot=value;run=slot.run;book.active=index;screen=run and "battle" or "map";selected="pea"
        ctx.level.load(run and C.campaign[run.level].theme=="night" and "lawn_night" or "lawn_day")
        changed();persist("load_profile");message=run and "战局已恢复。阳光、冷却和波次均保留。" or "选择已开放的关卡。"
        if run and run.status=="playing" then ctx.session.pause("loaded_game") end
    end
    local function deleteSlot(index)
        local key=tostring(index);local previous=book.slots[key];local active=book.active
        book.slots[key]=nil;if active==index then book.active=0 end
        if not persist("delete_profile") then book.slots[key]=previous;book.active=active;return end
        if active==index then slot=nil;run=nil end
        confirm=nil;say("存档已删除，可以在这个位置重新建档。")
    end
    local function startLevel(level)
        if not slot or level>min(10,slot.cleared+1) then return end
        local def=C.campaign[level]
        run={level=level,status="playing",time=0,sun=def.sun,nextSky=def.sky>0 and def.sky or 0,
            nextWave=def.prepare,wave=0,waveTime=0,spawnIndex=1,spawnClock=0,plants={},zombies={},bullets={},suns={},
            mowers={0,0,0,0,0},cooldowns={},kills=0,rng=1977+level*7919}
        slot.run=run;selected="pea";screen="battle";flashes={};ctx.level.load(def.theme=="night" and "lawn_night" or "lawn_day")
        say("新植物："..C.plants[level].name.."。"..C.plants[level].tip)
        changed();persist("level_start");ctx.session.resume()
    end
    local function leaveBattle()
        if not persist("return_to_map") then return end
        screen="map";help=false;ctx.session.resume();say("当前战局已保留，点击“继续战局”返回。")
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
        say(p.name.."已种下。"..(selected=="mine" and "12秒后武装。" or p.tip))
    end
    local function nearest(row,x,range)
        local target
        for _, z in ipairs(run.zombies) do
            if z.hp>0 and z.row==row and z.x>=x-18 and z.x-x<=range and (not target or z.x<target.x) then target=z end
        end
        return target
    end
    local function blast(row,x,radius,rows)
        for _, z in ipairs(run.zombies) do if abs(z.row-row)<=rows and abs(z.x-x)<=radius then z.hp=z.hp-1800 end end
        flashes[#flashes+1]={row=row,x=x,radius=radius,rows=rows,ttl=.45};sound("explode")
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
    local function finish(status)
        run.status=status
        for i=#run.zombies,1,-1 do if run.zombies[i].hp<=0 then table.remove(run.zombies,i);run.kills=run.kills+1 end end
        if status=="won" then
            local first=run.level>slot.cleared
            if first then slot.cleared=run.level;slot.coins=slot.coins+100+run.level*25 end
            say(first and ("首次通关！获得 "..(100+run.level*25).." 金币。") or "再次守住了庭院。")
            sound("win")
        else say("僵尸进入了家门。重试本关，调整你的防线。");sound("lose") end
        changed();persist(status)
    end
    local function simulate(dt)
        if screen~="battle" or not run or run.status~="playing" then return end
        local def=C.campaign[run.level];run.time=run.time+dt
        for id,value in pairs(run.cooldowns)do run.cooldowns[id]=max(0,value-dt)end
        if def.sky>0 and run.time>=run.nextSky then
            addSun(150+random(700),168+random(315),25);run.nextSky=run.time+def.sky
        end
        for i=#run.suns,1,-1 do local s=run.suns[i];s.ttl=s.ttl-dt;if s.ttl<=0 then table.remove(run.suns,i)end end
        -- Each wave is explicit content; only lane selection uses a saved PRNG.
        if run.wave==0 then
            if run.time>=run.nextWave then run.wave=1;run.waveTime=run.time;run.spawnClock=0;sound("wave");changed() end
        end
        if run.wave>0 then
            local sequence=schedules[run.level][run.wave];local wave=def.waves[run.wave]
            run.spawnClock=max(0,run.spawnClock-dt)
            if run.spawnIndex<=#sequence and run.spawnClock<=0 and #run.zombies<48 then
                local kind=sequence[run.spawnIndex];local d=C.enemies[kind]
                local row=def.rows[random(#def.rows)]
                run.zombies[#run.zombies+1]={kind=kind,row=row,x=925,hp=d.hp,slow=0,jumped=false}
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
        for key,p in pairs(run.plants)do
            p.age=p.age+dt;p.timer=max(0,p.timer-dt)
            local sleeping=(p.kind=="puff" or p.kind=="sunshroom") and def.theme~="night"
            if not sleeping then
                if p.kind=="cherry" and p.age>=1.2 then blast(p.row,cellX(p.col),126,1);run.plants[key]=nil
                elseif p.kind=="mine" and p.age>=12 and nearest(p.row,cellX(p.col),32) then blast(p.row,cellX(p.col),48,0);run.plants[key]=nil
                elseif p.kind=="chomper" then
                    local z=nearest(p.row,cellX(p.col),90)
                    if p.timer<=0 and z then z.hp=0;p.timer=20;sound("hit") end
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
            if target then target.hp=target.hp-b.damage;if b.ice then target.slow=5 end;sound("hit") end
            if target or b.x>950 or b.remaining<=0 then table.remove(run.bullets,i)end
        end
        for _,z in ipairs(run.zombies)do
            if z.hp>0 then
                local d=C.enemies[z.kind];z.slow=max(0,z.slow-dt)
                local speed=d.speed*(z.slow>0 and .5 or 1)
                if z.kind=="pole" and z.jumped then speed=speed*.58 end
                if z.kind=="paper" and z.hp<=180 then speed=speed*2.2 end
                local obstacle
                for _,p in pairs(run.plants)do
                    local x=cellX(p.col)
                    if p.row==z.row and z.x>=x-18 and z.x<=x+38 and (not obstacle or p.col>obstacle.col)then obstacle=p end
                end
                if obstacle then
                    if z.kind=="pole" and not z.jumped then z.jumped=true;z.x=cellX(obstacle.col)-52
                    else obstacle.hp=obstacle.hp-d.bite*dt;if obstacle.hp<=0 then run.plants[cellKey(obstacle.row,obstacle.col)]=nil end end
                else z.x=z.x-speed*dt end
                if z.x<=108 then
                    if run.mowers[z.row]==0 then run.mowers[z.row]=108;sound("wave")
                    elseif run.mowers[z.row]<0 and z.x<80 then finish("lost");return end
                end
            end
        end
        for row,x in ipairs(run.mowers)do
            if x>0 then
                local nextX=x+460*dt
                for _,z in ipairs(run.zombies)do if z.row==row and z.x>=x-35 and z.x<=nextX+35 then z.hp=0 end end
                run.mowers[row]=nextX>965 and -1 or nextX
            end
        end
        for i=#run.zombies,1,-1 do if run.zombies[i].hp<=0 then table.remove(run.zombies,i);run.kills=run.kills+1 end end
        for i=#flashes,1,-1 do flashes[i].ttl=flashes[i].ttl-dt;if flashes[i].ttl<=0 then table.remove(flashes,i)end end
    end

    local function selectPlant(id)
        if plantIndex[id]>unlockCount() then say("通关前一关后，在第 "..plantIndex[id].." 关解锁。");return end
        selected=id;say(plants[id].name.."："..plants[id].tip)
    end
    local actions={
        cellKey=cellKey,cellX=cellX,rowY=rowY,rowActive=rowActive,unlockCount=unlockCount,
        createSlot=createSlot,loadSlot=loadSlot,startLevel=startLevel,leaveBattle=leaveBattle,
        plantAt=plantAt,collect=collect,collectAll=collectAll,persist=persist,selectPlant=selectPlant,
        requestDelete=function(index)confirm={kind="delete",index=index}end,
        chooseLevel=function(level)
            if run and run.status=="playing" then confirm={kind="replace",level=level} else startLevel(level)end
        end,
        openProfiles=function()if persist("profiles")then screen="profiles";ctx.session.resume()end end,
        continueBattle=function()
            if run then screen="battle";ctx.level.load(C.campaign[run.level].theme=="night" and "lawn_night" or "lawn_day") else startLevel(1)end
        end,
        toggleShovel=function()selected=selected=="shovel" and nil or "shovel";say("点击植物铲除；不返还阳光。")end,
        toggleSound=function()book.sound=not book.sound;ctx.sound.setEnabled(book.sound);changed();persist("sound_setting")end,
        showHelp=function()help=true;ctx.session.pause("help")end,
        hideHelp=function()help=false;ctx.session.resume()end,
        acceptConfirm=function()
            local c=confirm;confirm=nil;if not c then return end
            if c.kind=="delete"then deleteSlot(c.index)else startLevel(c.level)end
        end,
        cancelConfirm=function()confirm=nil end,
    }
    local function presentationState()
        return {book=book,slot=slot,run=run,screen=screen,selected=selected,message=message,
            saveStatus=saveStatus,flashes=flashes,help=help,confirm=confirm}
    end
    return {
        onStart=function()
            ctx.level.load("lawn_day");ctx.input.release();ctx.sound.setEnabled(book.sound)
            render=modules.ui(ctx,presentationState,actions,modules.sprites);say("选择一份存档，或在空槽建立新的花园。");render()
        end,
        onFixedUpdate=function(dt)
            simulate(dt);saveTimer=saveTimer+dt;drawTimer=drawTimer+dt
            if (dirty and saveTimer>=.65) or (screen=="battle" and run.status=="playing" and saveTimer>=5) then persist("autosave")end
            if drawTimer>=.1 then drawTimer=0;render()end
        end,
        onPause=function()persist("pause");render()end,
        onResume=function()render()end,
        onSave=function()return copy(book)end,
    }
end
