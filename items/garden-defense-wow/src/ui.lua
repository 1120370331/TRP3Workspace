-- Native edition: all scenery, cards, tools and units use WoW texture/model assets.
-- This module owns presentation; rules, progression and saves stay in game.lua.
return function(ctx, read, actions, drawProgress)
    local C, floor, min, max = ctx.content, math.floor, math.min, math.max
    local ui, render = ctx.ui.surface()
    local V=C.visuals
    local plants={};for _,p in ipairs(C.plants)do plants[p.id]=p end
    local book,slot,run,screen,selected,message,saveStatus,sunEffects,help,confirm
    local pauseMenu,settings,achievementNotice
    local cellKey,cellX,rowY,rowActive=actions.cellKey,actions.cellX,actions.rowY,actions.rowActive
    local cream={1,.94,.77,1};local gold={1,.78,.33,1};local muted={.67,.72,.63,1}
    local dark={.04,.06,.045,.82};local white={1,1,1,1}
    local paper={.80,.72,.55,1};local ink={.20,.15,.10,1};local softInk={.34,.28,.18,1}
    local function R(id,x,y,w,h,color,z)
        ui.draw(id,{x=x,y=y,w=w,h=h,color=color,layer=z or 0})
    end
    local function X(id,asset,x,y,w,h,color,z,uv,tile,blend)
        ui.draw(id,{kind="texture",asset=asset,x=x,y=y,w=w,h=h,color=color or white,layer=z or 0,texCoord=uv,tile=tile,blend=blend})
    end
    local function T(id,text,x,y,w,h,size,color,z,align)
        ui.draw(id,{kind="text",text=text,x=x,y=y,w=w,h=h,size=size or 14,color=color or cream,layer=z or 3,align=align})
    end
    local function M(id,asset,x,y,w,h,z,animation,distance,paused)
        ui.draw(id,{kind="model",asset=asset,x=x,y=y,w=w,h=h,layer=z or 4,animation=animation,distance=distance,paused=paused})
    end
    local function unit(id,asset,x,feet,animation,paused,growth,timeline)
        local def=C.assets.models[asset]
        local size=def.render or {width=104,height=108}
        local scale=(growth or 1)*(def.scale or 1)
        local w,h=min(84*1.3,size.width*scale),min(68*1.3,size.height*scale)
        local anchorX,anchorY=x+(size.offsetX or 0),feet+(size.offsetY or 0)
        -- Apply the asset multiplier before the game's footprint cap. The
        -- engine receives the final dimensions and an independent foot anchor.
        ui.draw(id,{kind="model",asset=asset,x=anchorX-w/2,y=anchorY-h*.9,w=w,h=h,scale=1,
            anchorX=anchorX,anchorY=anchorY,layer=4,depth=feet,animation=animation,paused=paused,
            animationTime=timeline and timeline.time,animationRate=timeline and timeline.rate,animationEnd=timeline and timeline.limit})
    end
    local function B(id,text,x,y,w,h,fn,z,enabled,icon,tint,transparent)
        z=z or 8
        local nativeButton=z>=24 and not transparent
        ui.draw(id,{kind="button",text=icon and "" or text,x=x,y=y,w=w,h=h,
            nativeButton=nativeButton,asset=not transparent and not nativeButton and "ground_elwynn_wood" or nil,texCoord={0,1,0,1},
            onClick=function(mouse)
                fn(mouse)
                if ctx.session.isStopped()then return end
                -- Play after the action: pause stops existing voices, including pre-click sounds.
                if book.sound and id~="shield" and id~="collectAll" and not id:match("^cell") and not id:match("^sun%d") then
                    ctx.sound.play(id:match("^seed") and "ui_select" or "ui_click")
                end
                render()
            end,color=(transparent or nativeButton)and {0,0,0,0} or tint or {.65,.65,.58,1},
            layer=z,enabled=enabled,size=15})
        if icon then
            X("buttonIcon/"..id,icon,x+5,y+4,h-8,h-8,enabled==false and {.45,.45,.45,1} or white,z+1,{.07,.93,.07,.93})
            T("buttonLabel/"..id,text,x+h,y+2,w-h-3,h-4,14,enabled==false and muted or cream,z+1)
        end
    end
    local function panel(id,x,y,w,h,z)
        -- Keep full opaque coverage, then overlay native paper grain. SetAtlas owns
        -- the UV bounds; do not sample the transparent padding of the complete file.
        R(id.."fill",x,y,w,h,paper,z)
        X(id.."/paperTexture","ui_parchment_grain",x,y,w,h,{1,1,1,.85},z+1)
    end
    local function backdrop(night,level)
        X("ground",V.materials.dirt.texture,0,0,960,600,night and {.32,.39,.52,1} or {.70,.66,.49,1},0,{0,4,0,3},true)
        X("path",V.materials.road.texture,78,152,48,359,night and {.40,.49,.62,1} or {.86,.84,.69,1},1,{0,1,0,4},true)
        X("road",V.materials.road.texture,889,152,71,359,night and {.28,.34,.44,1} or {.59,.61,.52,1},1,{0,1,0,4},true)
        -- Draw exactly one ground texture per cell. Same-layer overlays can be reordered
        -- when WoW reuses textures, so an unopened row must never draw grass underneath.
        for row=1,5 do for col=1,9 do
            local cultivated=not level or rowActive(level,row)
            local color
            if cultivated then
                color=night and ((row+col)%2==0 and {.35,.52,.65,1} or {.39,.58,.71,1}) or
                    ((row+col)%2==0 and {.49,.65,.42,1} or {.55,.71,.47,1})
            else color=night and {.32,.34,.36,1}or {.55,.49,.36,1}end
            X("lawn"..row.."_"..col,cultivated and V.materials.grass.texture or V.materials.dirt.texture,130+(col-1)*84,rowY(row),84,68,color,1,
                {(col-1)*.5,col*.5,(row-1)*.5,row*.5},true)
        end end
        X("upperCurb",V.materials.road.texture,125,149,765,14,{.59,.58,.50,1},2,{0,7,0,.35},true)
        X("lowerCurb",V.materials.road.texture,125,504,765,12,{.59,.58,.50,1},2,{0,7,.4,.7},true)
        X("porch",V.materials.wood.texture,0,199,75,303,night and {.36,.42,.51,1} or {.71,.66,.48,1},1,{0,1,0,3},true)
        X("porchFrame","ui_stone_frame",-14,240,105,204,{.78,.71,.53,1},2)
        T("house","庭\n院\n入\n口",16,280,43,126,20,gold,3)
        X("topbar",V.materials.wood.texture,0,0,960,60,{.53,.51,.39,1},12,{0,6,0,1},true)
        X("toolbar",V.materials.wood.texture,0,550,960,50,{.46,.46,.37,1},12,{0,6,0,1},true)
        R("messageShade",0,517,960,31,dark,12)
        if night then X("moon","icon_sun_alt",899,161,45,45,{.46,.71,1,.8},3,nil,nil,"ADD")end
    end
    local function footer()
        T("saveStatus",saveStatus,12,565,138,22,12,muted,13,"LEFT")
        B("musicShortcut","音乐",155,559,85,34,actions.showMusicSettings,15,true,"icon_sound",book.music and {.65,.65,.58,1}or {.38,.40,.37,1})
        T("message",achievementNotice or message,14,520,932,24,14,achievementNotice and gold or cream,13,"LEFT")
    end
    local function drawProfiles()
        -- Warm the complete small catalog while the player chooses a save.
        for asset in pairs(C.assets.models)do ui.preloadModel(asset)end
        backdrop(false)
        T("heading","生物VS天灾",24,8,912,40,28,gold,13,"CENTER")
        M("greeterPlant",V.plants.pea.model,37,284,193,208,4,0,1.1)
        M("greeterZombie","zombie",746,257,208,238,4,0,1.2)
        local panelX,panelY,panelW,panelH=232,112,496,384
        local rowX,rowW=panelX+20,panelW-40
        local contentX,contentW=rowX+12,rowW-24
        local buttonGap,deleteW=12,104
        local loadW=contentW-buttonGap-deleteW
        panel("profilesPanel",panelX,panelY,panelW,panelH,10)
        T("profilesTitle","你的花园手册",rowX,panelY+12,rowW,32,24,ink,12,"CENTER")
        for i=1,3 do
            local value=book.slots[tostring(i)];local y=panelY+62+(i-1)*102
            T("slotText"..i,value and value.name or "花园 "..i,contentX,y+8,160,24,17,ink,12,"LEFT")
            T("slotStats"..i,value and value.cleared.." / 10 关 · "..value.coins.." 金币"or "空存档",contentX+168,y+8,contentW-168,24,14,softInk,12,"RIGHT")
            if value then
                B("load"..i,value.run and (value.run.mode=="endless"and "读档 · 无尽第 "..value.run.round.." 轮"or "读档 · 第 "..value.run.level.." 关") or "读档 · 庭院地图",contentX,y+42,loadW,36,function()actions.loadSlot(i)end,13,true)
                B("delete"..i,"删档",contentX+loadW+buttonGap,y+42,deleteW,36,function()actions.requestDelete(i)end,13,true,nil,{.65,.30,.24,1})
            else B("create"..i,"建立新存档",contentX,y+42,contentW,36,function()actions.createSlot(i)end,13,true)end
        end
        T("profilesNote","三份独立花园 · 十种植物 · 十关守卫",272,565,646,22,15,cream,13)
    end
    local function drawMap()
        backdrop(false)
        T("heading",slot.name.." / 庭院手册",22,11,452,35,25,gold,13,"LEFT")
        X("coinsIcon","icon_coin",629,15,26,26,nil,13)
        T("coins",slot.coins.." 金币 · "..slot.cleared.." / 10 关",664,13,275,31,17,cream,13)
        -- The level map sits directly on the native lawn drawn by backdrop(false).
        for i=1,10 do
            local x=164+((i-1)%5)*138;local y=183+floor((i-1)/5)*151
            local unlocked=i<=min(10,slot.cleared+1)
            if unlocked then ui.preloadModel(V.plants[C.plants[i].id].model)end
            X("mapRoad"..i,"ground_elwynn_road",x+16,y+29,132,15,unlocked and {.8,.72,.48,1} or {.25,.3,.27,1},11,{0,1,0,.5})
            X("levelIcon"..i,V.plants[C.plants[i].id].texture,x+29,y,65,65,unlocked and white or {.3,.3,.3,1},12,{.05,.95,.05,.95})
            X("levelRing"..i,"action_border",x+19,y-10,85,85,unlocked and gold or muted,12)
            T("levelIndex"..i,tostring(i)..(i<=slot.cleared and "  ✓" or ""),x+53,y+41,39,25,18,gold,13)
            B("level"..i,"",x+19,y-10,85,85,function()actions.chooseLevel(i)end,14,unlocked,nil,nil,true)
            T("levelName"..i,C.campaign[i].title,x,y+70,126,25,15,unlocked and cream or muted,12)
            T("unlock"..i,C.plants[i].name,x,y+99,126,22,13,unlocked and gold or muted,12)
        end
        local endlessUnlocked=slot.cleared>=10
        local progress=slot.progress and slot.progress.stats or {}
        T("endlessRules",endlessUnlocked and "积分：食尸鬼10 / 旗手20 / 披甲25 / 巨尸45 / 恶鬼35 / 侍僧40 / 亡灵师80 / 憎恶150"or
            "通关第 10 关后解锁无尽挑战；首轮中间3路，第2轮起五路。",149,458,711,18,11,endlessUnlocked and cream or muted,13)
        B("endless",endlessUnlocked and ("无尽挑战 · 最高第 "..(progress.endlessBestRound or 0).." 轮 · "..(progress.endlessBestScore or 0).." 分")or
            "无尽挑战 · 尚未解锁",149,480,711,34,actions.chooseEndless,14,endlessUnlocked,nil,endlessUnlocked and {.54,.38,.24,1}or nil)
        B("progress","统计 / 成就",514,559,153,34,actions.showProgress,15,true,"icon_help")
        B("profiles","存档管理",675,559,133,34,actions.openProfiles,15,true,"icon_profiles")
        B("continue",run and (run.mode=="endless"and "继续无尽"or "继续战局") or "开始挑战",817,559,132,34,actions.continueBattle,15,true,"icon_farm_seed")
    end
    local function drawBattle()
        local def=C.campaign[run.level];backdrop(def.theme=="night",run.level)
        T("heading",run.mode=="endless"and "∞  无尽挑战"or string.format("%02d",run.level).."  "..def.title,18,10,343,35,24,gold,13,"LEFT")
        X("sunCounter",V.tools.sun.texture,370,13,31,31,white,13)
        T("sunTotal",tostring(run.sun),412,8,116,37,27,gold,13,"LEFT")
        B("speed",book.speed==2 and "2× 加速" or "1× 速度",540,15,75,29,actions.toggleSpeed,15,true,nil,book.speed==2 and {.88,.65,.30,1} or nil)
        local wave
        if run.mode=="endless"then
            local spawned=min(run.roundTotal,run.spawnIndex-1)
            wave="第 "..run.round.." 轮 · "..run.score.." 分 · "..spawned.." / "..run.roundTotal.." · 场上 "..#run.zombies
            if run.time<run.nextWave then wave="第 "..run.round.." 轮 · 准备 "..math.ceil(run.nextWave-run.time).." 秒 · "..run.score.." 分"end
        else wave=run.wave==0 and ("准备 "..math.ceil(max(0,run.nextWave-run.time)).." 秒") or ("波次 "..run.wave.." / "..#def.waves.."  ·  场上 "..#run.zombies)end
        T("wave",wave,616,13,325,30,17,cream,13)
        for i,p in ipairs(C.plants)do
            local x=9+(i-1)*95;local unlocked=i<=actions.unlockCount();local cooldown=run.cooldowns[p.id] or 0
            local affordable=run.sun>=p.cost
            if unlocked then ui.preloadModel(V.plants[p.id].model)end
            X("card"..i,"ui_leather_background",x,68,90,75,unlocked and {.54,.57,.40,1} or {.25,.27,.24,1},12)
            X("cardIcon"..i,unlocked and V.plants[p.id].texture or "icon_seed_bag",x+4,72,38,38,unlocked and (affordable and white or {.45,.45,.45,1}) or {.4,.4,.4,1},13,{.07,.93,.07,.93})
            X("cardRim"..i,"action_border",x-2,65,52,52,selected==p.id and gold or {.75,.72,.54,1},13)
            T("cardCost"..i,unlocked and tostring(p.cost) or (i.."关"),x+43,75,44,24,18,unlocked and (affordable and gold or {1,.25,.18,1}) or muted,14)
            T("cardName"..i,p.name,x+1,115,88,22,13,unlocked and cream or muted,14)
            if unlocked and not affordable then T("cardNoSun"..i,"×",x+2,66,42,46,36,{1,.08,.05,.96},14)end
            if unlocked and cooldown>0 then
                ui.draw("cardSwipe"..i,{kind="cooldown",x=x+4,y=72,w=38,h=38,layer=13,duration=p.reload,remaining=cooldown})
                T("cardCooldown"..i,math.ceil(cooldown).."s",x+44,98,42,18,12,cream,14)
            end
            if selected==p.id then R("cardSelect"..i,x+2,139,86,3,gold,14)end
            B("seed"..i,"",x,68,90,75,function()actions.selectPlant(p.id)end,15,true,nil,nil,true)
        end
        for row=1,5 do
            if rowActive(run.level,row) then
                local mower=run.mowers[row]
                if mower>=0 then unit("mower"..row,V.tools.mower.model,mower==0 and 99 or mower,rowY(row)+57,mower==0 and 0 or 4)end
                for col=1,9 do
                    local key=cellKey(row,col);local p=run.plants[key];local x=cellX(col)
                    B("cell"..key,"",x-42,rowY(row),84,68,function(mouse)actions.plantAt(row,col,mouse)end,3,true,nil,nil,true)
                    if p then
                        local visual=V.plants[p.kind];local sleeping=(p.kind=="puff" or p.kind=="sunshroom") and def.theme~="night"
                        local attack=plants[p.kind].damage and p.timer>(plants[p.kind].interval or 1)-.25
                        R("plantShadow"..key,x-20,rowY(row)+53,40,4,{.025,.04,.02,.35},3)
                        unit("plant"..key,visual.model,x,rowY(row)+57,attack and 16 or 0,sleeping,p.kind=="sunshroom" and p.age<90 and .72 or 1)
                        if p.hp<plants[p.kind].hp then
                            R("plantHPBase"..key,x-26,rowY(row)+62,52,3,{.1,.1,.07,.9},5)
                            R("plantHP"..key,x-26,rowY(row)+62,52*p.hp/plants[p.kind].hp,3,{.56,.83,.28,1},6)
                        end
                        local status=sleeping and "休眠" or (p.kind=="mine" and p.age<12 and (math.ceil(12-p.age).."s")) or
                            (p.kind=="chomper" and p.timer>0 and ("咀嚼 "..math.ceil(p.timer))) or nil
                        if status then T("plantState"..key,status,x-35,rowY(row)+4,70,19,12,gold,6)end
                    end
                end
            else
                T("closedRow"..row,"待开垦的土地",142,rowY(row)+24,730,21,16,muted,1)
            end
        end
        for _,z in ipairs(run.zombies)do
            local i=z.viewSlot
            local visual=V.enemies[z.kind];local animation=4
            local d=C.enemies[z.kind]
            local timeline
            if z.attackTime~=nil then
                animation=d.melee.animation
                local rate=d.melee.motionDuration/d.melee.period
                timeline={time=z.attackTime*rate,rate=rate,limit=d.melee.motionDuration}
            end
            if z.phase=="vomit" then animation=53 elseif z.phase=="stunned"then animation=0
            elseif not timeline and d.ability=="necromancer" and (z.shotCooldown or 0)>d.shotInterval-.4 then animation=51 end
            unit("enemy"..i,visual.model,z.x,rowY(z.row)+57,animation,nil,nil,timeline)
            if z.phase=="vomit" then
                for cloud=1,3 do X("vomit"..i.."_"..cloud,"orb",z.x-cloud*52-15,rowY(z.row)+18,83,35,{.4,.85,.05,.50},7,nil,nil,"ADD")end
                T("eliteState"..i,"呕吐 "..math.ceil(z.phaseTime or 0).."s",z.x-36,rowY(z.row)-1,72,15,10,{.7,1,.2,1},7)
            elseif z.phase=="stunned"then T("eliteState"..i,"僵直 "..math.ceil(z.phaseTime or 0).."s",z.x-36,rowY(z.row)-1,72,15,10,gold,7)end
            T("enemyName"..i,C.enemies[z.kind].name,z.x-29,rowY(z.row)+53,58,14,11,z.slow>0 and {.56,.85,1,1} or cream,6)
            if z.hp<C.enemies[z.kind].hp then R("enemyHP"..i,z.x-26,rowY(z.row)+66,52*z.hp/C.enemies[z.kind].hp,3,{.88,.30,.19,1},6)end
            if z.slow>0 then X("ice"..i,"icon_snow",z.x-24,rowY(z.row)+9,28,28,{.6,.8,1,.5},6,nil,nil,"ADD")end
        end
        for i,b in ipairs(run.bullets)do
            X("bulletGlow"..i,"orb",b.x-9,rowY(b.row)+20,22,22,b.ice and {.35,.8,1,1} or b.spore and {.65,.35,1,.85} or {.38,1,.15,1},7,nil,nil,"ADD")
        end
        for i,b in ipairs(run.enemyBolts or {})do
            X("shadowBolt"..i,"orb",b.x-10,rowY(b.row)+23,23,19,{.67,.19,1,1},7,nil,nil,"ADD")
            X("shadowTrail"..i,"orb",b.x+6,rowY(b.row)+26,25,13,{.37,.09,.68,.6},7,nil,nil,"ADD")
        end
        for i,s in ipairs(run.suns)do
            local alpha=min(1,max(0,s.ttl/3));local pulse=.88+.12*math.sin((16-s.ttl)*3)
            X("sunGlow"..i,"orb",s.x-19,s.y-19,38,38,{1,.73,.21,alpha*pulse},9,nil,nil,"ADD")
            X("sunIcon"..i,V.tools.sun.texture,s.x-11,s.y-11,23,23,{1,1,1,alpha},9,{.08,.92,.08,.92})
            T("sunValue"..i,tostring(s.value),s.x-17,s.y+13,34,16,12,{1,.78,.33,alpha},10)
            B("sun"..i,"",s.x-20,s.y-19,41,48,function()actions.collect(i)end,11,true,nil,nil,true)
        end
        for i,effect in ipairs(sunEffects or {})do
            local alpha=max(0,effect.ttl/.45);local y=effect.y-(1-alpha)*22
            X("sunCollectGlow"..i,"orb",effect.x-21,y-21,42,42,{1,.84,.3,alpha},9,nil,nil,"ADD")
            X("sunCollectIcon"..i,V.tools.sun.texture,effect.x-11,y-11,23,23,{1,1,1,alpha},9,{.08,.92,.08,.92})
            T("sunCollectValue"..i,"+"..effect.value,effect.x-22,y+10,44,19,14,{1,.87,.4,alpha},10)
        end
        B("shovel",selected=="shovel" and "铲除 ✓" or "铲除",249,559,83,34,actions.toggleShovel,15,true,"icon_shovel",selected=="shovel" and {.9,.72,.35,1} or nil)
        B("collectAll","收阳",338,559,78,34,actions.collectAll,15,true,V.tools.sun.texture)
        B("pause","暂停",422,559,78,34,actions.pause,15,true,"icon_pause")
        B("map","地图",506,559,78,34,actions.leaveBattle,15,true,"icon_map")
        B("sound",book.sound and "音效开" or "音效关",590,559,90,34,actions.toggleSound,15,true,"icon_sound")
        B("help","玩法",686,559,78,34,actions.showHelp,15,true,"icon_help")
        B("save","保存",770,559,78,34,function()actions.persist("manual")end,15,true,"icon_save")
        B("profiles","存档",854,559,95,34,actions.openProfiles,15,true,"icon_profiles")
    end
    local function modal(title,tall)
        B("shield","",0,0,960,600,function()end,20,true,nil,dark,true)
        R("modalShade",0,0,960,600,{.015,.025,.035,.78},20)
        local y=tall and 134 or 179
        local h=tall and 365 or 250
        panel("modal",225,y,510,h,21)
        T("modalTitle",title,245,y+12,470,45,27,ink,23)
    end
    local function volumeRow(id,label,value,y,onChange,available)
        T(id,label.."  "..floor(value*100+.5).."%",278,y,280,30,17,ink,24,"LEFT")
        B(id.."Down","−",579,y,50,30,function()onChange(-.1)end,24,available and value>0)
        B(id.."Up","+",640,y,50,30,function()onChange(.1)end,24,available and value<1)
    end
    local function musicSourceLabel()
        return book.musicSource=="native"and "配乐：魔兽原生"or "配乐：自动（Musician 优先）"
    end
    local function musicFallbackNote(reason)
        if reason=="musician_unavailable"then return "未启用 Musician，已回退魔兽原生配乐。"end
        if reason=="musician_busy"then return "Musician 正在演奏其他曲目，暂用原生配乐。"end
        if reason=="musician_muted"or reason=="musician_no_channel"then return "Musician 已静音或未启用通道，暂用原生配乐。"end
        if reason then return "MIDI 无法播放，已回退原生；切换配乐方式可重试。"end
    end
    local function musicVolumeRow(y)
        local caps=ctx.music.capabilities()
        if caps.selectedBackend=="musician"then
            T("musicVolume",book.musicVolume==0 and "MIDI 已静音"or "MIDI 无单曲音量调节",278,y,280,30,16,ink,24,"LEFT")
            B("musicVolumeDown","−",579,y,50,30,function()end,24,false)
            B("musicVolumeUp",book.musicVolume==0 and "开"or "+",640,y,50,30,actions.unmuteMusic,24,book.musicVolume==0)
            return false
        end
        volumeRow("musicVolume","音乐音量",book.musicVolume,y,actions.adjustMusicVolume,caps.independentVolume)
        return caps.independentVolume
    end
    local function drawMusicSettings(music)
        modal("庭院配乐",true)
        B("musicSource",musicSourceLabel(),249,193,462,28,actions.toggleMusicSource,24,true)
        for i,id in ipairs({"battle_day","battle_night","menu"})do
            local track=C.music[id];local x=249+(i-1)*158
            local isMidi=ctx.music.capabilities(id).selectedBackend=="musician"
            local accent=i==2 and {.55,.75,1,1}or gold
            R("musicCard"..i,x,228,146,112,i==2 and {.09,.15,.23,.9}or {.20,.19,.09,.9},23)
            R("musicAccent"..i,x,228,146,3,accent,24)
            T("musicTheme"..i,({"白天","夜晚","选关"})[i]..(music.track==id and " · 当前"or ""),x+10,234,126,20,13,accent,24,"LEFT")
            T("musicTitle"..i,isMidi and track.musicianTitle or track.title,x+10,256,126,24,15,cream,24,"LEFT")
            local subtitle=isMidi and "社区 MIDI · 支持续播"or
                (book.musicVolume>0 and book.musicVolume<1 and track.volumeSubtitle or track.subtitle)
            T("musicFile"..i,subtitle,x+10,283,126,18,11,muted,24,"LEFT")
            B("musicPreview"..i,music.preview==id and "从头试听"or "试听",x+10,305,126,30,function()actions.previewMusic(id)end,24,book.music)
        end
        B("musicEnabled",book.music and "背景音乐：开"or "背景音乐：关",267,346,207,30,actions.toggleMusic,24,true,"icon_sound")
        B("musicStopPreview","停止试听",486,346,207,30,actions.stopMusicPreview,24,music.preview~=nil)
        local volumeAvailable=musicVolumeRow(382)
        local status
        local id=music.preview or music.track
        local track=id and C.music[id]
        local title=track and (ctx.music.capabilities(id).selectedBackend=="musician"and track.musicianTitle or track.title)
        if not book.music then status="背景音乐已关闭，开启后可试听。"
        elseif music.error then status=music.error
        elseif book.musicVolume==0 then status="音乐已静音，点击音量右侧按钮可恢复。"
        elseif music.state=="loading"then status="正在加载 MIDI；战局保持暂停。"
        elseif music.fallback then status=musicFallbackNote(music.fallback)
        elseif music.preview then status="正在试听："..title
        elseif music.backend=="musician"and music.state=="paused"then status="已暂停，继续游戏后从原位置续播。"
        elseif title then status="恢复后播放："..title
        else status="选择曲目试听；进入关卡后自动切换。"end
        T("musicStatus",status,250,414,460,22,13,ink,24)
        local note=ctx.music.capabilities().selectedBackend=="musician"and
            "MIDI 按谱续播；独立音量仅用于原生配乐。"or
            (volumeAvailable and "原生曲目调音量会重播；夜曲低音量可能随机选曲。"or "当前客户端不支持独立音量。")
        T("musicVolumeNote",note,247,437,466,20,12,softInk,24)
        B("musicBack","返回游戏设置",320,465,320,25,actions.showSettings,24,true)
    end
    render=function()
        local state=read()
        book,slot,run,screen,selected=state.book,state.slot,state.run,state.screen,state.selected
        message,saveStatus,help,confirm=state.message,state.saveStatus,state.help,state.confirm
        sunEffects=state.sunEffects
        achievementNotice=state.achievementNotice
        pauseMenu,settings=state.pauseMenu,state.settings
        ui.begin()
        if screen=="profiles" then drawProfiles()elseif screen=="map" then drawMap()else drawBattle()end
        footer()
        -- One overlay per frame. Keep the parent menu state for Cancel, but do not
        -- draw its buttons/text under a confirmation that shares the modal nodes.
        if confirm then
            modal(confirm.kind=="delete" and "删除这份花园存档？" or confirm.kind=="restart" and (confirm.mode=="endless"and "重新开始无尽挑战？"or "重新开始本关？") or confirm.kind=="replace_endless"and "开始无尽挑战？"or "重新开始一个关卡？")
            T("confirmNote",confirm.kind=="delete" and "该槽的关卡、金币、战局及统计成就将被删除。\n其他花园和像素版存档均保留。" or confirm.kind=="restart" and "当前战局的植物、敌人、阳光、进度和计时将重置。\n通关进度、统计成就、金币及设置保留。" or confirm.kind=="replace_endless"and "当前战局将被替换为无尽挑战。\n通关进度、统计成就、金币及设置保留。"or "当前战局将被替换，通关进度、统计成就和金币保留。",249,252,462,63,17,ink,23)
            B("confirmYes","确认",270,360,196,43,actions.acceptConfirm,25,true,nil,{.68,.28,.20,1})
            B("confirmNo","取消",494,360,196,43,actions.cancelConfirm,25,true)
        elseif state.progress then
            drawProgress(ui,state.progress,{onTab=actions.progressTab,onBack=actions.closeProgress,
                clickSound=function()if book.sound then ctx.sound.play("ui_click")end end,redraw=render})
        elseif pauseMenu and ctx.session.isPaused()then
            if state.music.open then
                drawMusicSettings(state.music)
            elseif settings then
                modal("游戏设置",true)
                B("settingSpeed",book.speed==2 and "游戏速度：2 倍速" or "游戏速度：正常 1 倍速",267,194,426,30,actions.toggleSpeed,24,true)
                B("settingSound",book.sound and "游戏音效：开" or "游戏音效：关",267,231,207,30,actions.toggleSound,24,true,"icon_sound")
                B("settingMusic",book.music and "背景音乐：开" or "背景音乐：关",486,231,207,30,actions.toggleMusic,24,true,"icon_sound")
                B("settingMusicSource",musicSourceLabel(),267,268,426,30,actions.toggleMusicSource,24,true)
                local volumeAvailable=ctx.sound.capabilities().volume
                volumeRow("soundVolume","音效音量",book.soundVolume,304,function(delta)actions.adjustVolume("all",delta)end,volumeAvailable)
                volumeRow("hitVolume","命中音量",book.hitVolume,340,function(delta)actions.adjustVolume("impact",delta)end,volumeAvailable)
                local musicAvailable=musicVolumeRow(376)
                local note=state.music.error or musicFallbackNote(state.music.fallback)or
                    (ctx.music.capabilities().selectedBackend=="musician"and "MIDI 支持续播；独立音量仅用于原生配乐。"or
                    (volumeAvailable and musicAvailable and "音效对新声音生效；音乐音量恢复后生效"or "当前客户端存在不支持的音量调节项"))
                T("volumeNote",note,250,410,460,20,12,softInk,24)
                B("musicLibrary","曲目 / 试听",267,436,426,25,actions.showMusicSettings,24,true,"icon_sound")
                B("settingsBack","返回暂停菜单",320,469,320,23,actions.backToPause,24,true)
            else
                modal("游戏已暂停",true)
                T("pausedNote",saveStatus.." · 阳光、敌人和冷却已冻结",247,195,466,25,15,ink,23)
                B("resume","继续游戏",267,235,426,40,actions.resume,24,true,"icon_farm_seed")
                B("settings","游戏设置",267,282,207,40,actions.showSettings,24,true)
                if slot and screen~="profiles" then B("pauseProgress","统计 / 成就",486,282,207,40,actions.showProgress,24,true)end
                if run and screen=="battle"then
                    B("pauseRestart","重新开始本关",267,329,207,40,actions.requestRestart,24,true,nil,{.65,.36,.25,1})
                    B("pauseSave","保存游戏",486,329,207,40,function()actions.persist("pause_menu_save")end,24,true,"icon_save")
                else
                    B("pauseSave","保存游戏",267,329,426,40,function()actions.persist("pause_menu_save")end,24,true,"icon_save")
                end
                B("saveExit","保存并关闭游戏",267,376,426,40,actions.saveAndExit,24,true,nil,{.65,.36,.25,1})
                if run and screen=="battle"then
                    B("exitRun","退出本局",267,437,207,35,actions.exitCurrentRun,24,true,nil,{.72,.28,.20,1})
                    B("pauseMap","返回地图（保留）",486,437,207,35,actions.leaveBattle,24,true,"icon_map")
                else
                    B("pauseMap",slot and "返回庭院地图" or "返回存档选择",320,437,320,35,actions.leaveBattle,24,true,"icon_map")
                end
            end
        elseif screen=="battle" and run.status~="playing" then
            local endless=run.mode=="endless"
            modal(endless and "无尽挑战结束"or run.status=="won" and (run.level==10 and "天灾终结者" or "防线守住了！") or "天灾突破了防线")
            local result=endless and ("到达第 "..run.round.." 轮 · 获得 "..run.score.." 分")or run.status=="won" and
                (run.level<10 and ("下一关解锁："..C.plants[run.level+1].name) or "十种植物集齐 · 无尽挑战已解锁") or "重新布置防线，再守一次。"
            T("result",result,249,251,462,36,18,ink,23)
            T("resultKills","击退 "..run.kills.." 个敌人 · 用时 "..floor(run.time).." 秒",249,297,462,27,16,softInk,23)
            B("resultMap","返回地图",270,360,196,43,actions.leaveBattle,24,true,"icon_map")
            B("resultNext",endless and "再战无尽"or run.status=="won"and run.level==10 and "进入无尽"or run.status=="won" and run.level<10 and "下一关" or "重玩本关",494,360,196,43,
                function()if endless or(run.status=="won"and run.level==10)then actions.startEndless()else actions.startLevel(run.status=="won"and min(10,run.level+1)or run.level)end end,24,true,"icon_farm_seed")
        elseif help then
            modal("防线作战指南",true)
            T("helpBody","选种子 → 点草坪部署；点击阳光收集。\n每路机械防线仅出动一次，铲除不退款。\n疾行恶鬼跃过前排，狂暴侍僧受伤后加速。\n缝合怪喷吐前方毒雾，持续3.2秒。\n呕吐后僵直4秒，把握反击窗口！\n亡灵师边行进边施法，前排可挡暗影弹。\n夜间没有天降阳光，孢子守卫白天休眠。\nEsc打开暂停菜单，可保存并退出。",249,213,462,197,16,ink,23)
            B("helpBack","明白，继续守卫",320,437,320,35,actions.hideHelp,24,true)
        end
        ui.finish()
    end
    return render
end
