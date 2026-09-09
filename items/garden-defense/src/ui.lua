-- Project-owned screens, map, seed bank, battle HUD and dialogs.
return function(ctx, read, actions, art)
    local C, floor, min, max = ctx.content, math.floor, math.min, math.max
    local ui, render = ctx.ui.surface()
    local palette, sprites = art.palette, art.sprites
    local plants={};for _,p in ipairs(C.plants)do plants[p.id]=p end
    local book,slot,run,screen,selected,message,saveStatus,flashes,help,confirm
    local cellKey,cellX,rowY,rowActive=actions.cellKey,actions.cellX,actions.rowY,actions.rowActive
    local unlockCount,createSlot,loadSlot=actions.unlockCount,actions.createSlot,actions.loadSlot
    local startLevel,leaveBattle,plantAt=actions.startLevel,actions.leaveBattle,actions.plantAt
    local collect,collectAll,persist=actions.collect,actions.collectAll,actions.persist
    local selectPlant=actions.selectPlant
    local colors={wood={.26,.16,.09,1},woodLight={.42,.27,.14,1},cream={.96,.88,.64,1},ink={.15,.20,.12,1},
        leaf={.22,.40,.16,1},button={.26,.43,.18,1},gold={.89,.63,.19,1},muted={.57,.65,.47,1},red={.62,.24,.19,1}}
    local function R(id,x,y,w,h,color,z)ui.draw(id,{x=x,y=y,w=w,h=h,color=color,layer=z or 0})end
    local function T(id,text,x,y,w,h,size,color,z,align)
        ui.draw(id,{kind="text",text=text,x=x,y=y,w=w,h=h,size=size or 14,color=color or colors.cream,layer=z or 3,align=align})
    end
    local function B(id,text,x,y,w,h,fn,color,z,enabled,size)
        ui.draw(id,{kind="button",text=text,x=x,y=y,w=w,h=h,onClick=function(mouse)fn(mouse);if render then render()end end,
            color=color or colors.button,layer=z or 8,enabled=enabled,size=size or 15})
    end
    local function sprite(id,kind,x,y,scale,z)
        for i,p in ipairs(sprites[kind] or sprites.pea)do R(id.."/"..i,x+p.x*scale,y+p.y*scale,p.w*scale,scale,p.color,z or 4)end
    end
    local function gardenBackdrop(night)
        R("background",0,0,960,600,night and {.08,.13,.19,1} or {.15,.25,.12,1})
        R("topwood",0,0,960,60,colors.wood)
        R("toptrim",0,57,960,3,colors.gold)
        R("bottomwood",0,552,960,48,colors.wood)
        -- A paved path, a porch, and fence posts make the map readable as a yard.
        R("path",78,155,48,360,night and {.28,.30,.33,1} or {.50,.48,.37,1})
        R("road",890,155,70,360,night and {.21,.23,.27,1} or {.39,.40,.34,1})
        for row=1,5 do
            R("paver"..row,82,rowY(row)+8,38,58,night and {.33,.35,.38,1} or {.60,.56,.43,1})
            for col=1,9 do
                local c=night and ((row+col)%2==0 and {.17,.29,.29,1} or {.19,.32,.29,1}) or ((row+col)%2==0 and {.35,.52,.19,1} or {.40,.57,.22,1})
                R("tile"..row.."_"..col,130+(col-1)*84,rowY(row),82,66,c)
            end
        end
        for n=1,22 do R("fence"..n,125+n*34,147,7,15,night and {.36,.35,.30,1} or {.77,.70,.48,1})end
        R("fencebar",130,151,756,4,colors.woodLight)
        R("porch",0,210,74,270,colors.woodLight);R("door",12,254,53,163,colors.wood)
        T("house","家\n\n门",20,276,40,100,20)
        R("knob",54,333,5,5,colors.gold,2)
    end
    local function footer()
        T("saveStatus",saveStatus,18,565,225,20,12,colors.muted,3,"LEFT")
        T("message",message,18,518,924,27,14,colors.cream,3,"LEFT")
    end
    local function drawProfiles()
        gardenBackdrop(false)
        T("heading","艾泽拉斯庭院",28,10,450,38,28,colors.cream,3,"LEFT")
        T("tagline","十个清晨与夜晚 · 一座属于你的花园",36,80,880,34,21)
        sprite("welcomepea","pea",85,320,9,4);sprite("welcomesun","sunflower",760,314,9,4)
        R("profilesPanel",230,130,500,370,colors.wood,10)
        T("profilesTitle","选择存档",253,143,450,40,24,nil,11)
        for i=1,3 do
            local value=book.slots[tostring(i)];local y=202+(i-1)*92
            if value then
                local details=value.name.."  ·  "..value.cleared.." / 10 关  ·  "..value.coins.." 金币"
                T("slotText"..i,details,254,y,445,26,16,nil,11,"LEFT")
                B("load"..i,value.run and "读档 · 第 "..value.run.level.." 关" or "读档 · 庭院地图",254,y+31,318,36,function()loadSlot(i)end,nil,12)
                B("delete"..i,"删档",584,y+31,114,36,function()actions.requestDelete(i)end,colors.red,12)
            else
                B("create"..i,"＋  建档 · 花园 "..i,254,y+12,444,53,function()createSlot(i)end,nil,12)
            end
        end
        T("profilesNote","三个独立存档 · 建档、战局、通关均保存在本道具",235,565,690,22,14)
    end
    local function drawMap()
        gardenBackdrop(false)
        T("heading",slot.name.." / 庭院地图",24,12,470,34,24,nil,3,"LEFT")
        T("coins",slot.coins.." 金币  ·  已守住 "..slot.cleared.." / 10 关",537,14,400,30,17)
        T("mapTitle","从一颗豌豆，到整座花园。",120,84,740,38,26)
        R("mapBoard",150,167,710,331,{.21,.32,.15,1},10)
        for i=1,10 do
            local col=(i-1)%5;local row=floor((i-1)/5);local x=170+col*137;local y=190+row*150
            local unlocked=i<=min(10,slot.cleared+1)
            R("mapline"..i,x+15,y+37,130,6,unlocked and colors.gold or colors.leaf,10)
            B("level"..i,tostring(i)..(i<=slot.cleared and "  ✓" or ""),x+30,y,68,50,function()actions.chooseLevel(i)end,unlocked and colors.button or colors.wood,12,unlocked,22)
            T("levelName"..i,C.campaign[i].title,x,y+57,126,22,15,nil,11)
            T("unlock"..i,C.plants[i].name,x,y+85,126,22,13,unlocked and colors.gold or colors.muted,11)
        end
        B("profiles","存档管理",692,560,116,32,actions.openProfiles)
        B("continue",run and "继续战局" or "开始第一关",822,560,126,32,actions.continueBattle)
    end
    local function drawBattle()
        local def=C.campaign[run.level];gardenBackdrop(def.theme=="night")
        T("heading",string.format("%02d",run.level).."  "..def.title,24,8,320,36,23,nil,3,"LEFT")
        T("sunTotal","阳光  "..run.sun,371,10,175,34,24,colors.gold)
        local waveText=run.wave==0 and ("准备  "..math.ceil(max(0,run.nextWave-run.time)).." 秒") or ("波次 "..run.wave.." / "..#def.waves.."    场上 "..#run.zombies)
        T("wave",waveText,594,14,337,26,17)
        for i,p in ipairs(C.plants)do
            local x=12+(i-1)*94;local unlocked=i<=unlockCount();local cooldown=run.cooldowns[p.id] or 0
            R("seedborder"..i,x,69,90,72,selected==p.id and colors.gold or colors.wood,2)
            R("seedpaper"..i,x+3,72,84,66,unlocked and {.66,.65,.40,1} or {.29,.33,.23,1},2)
            if unlocked then sprite("seedart"..i,p.id,x+4,74,3,4)end
            T("seedcost"..i,unlocked and tostring(p.cost) or (i.."关"),x+43,78,43,22,16,colors.ink,5)
            T("seedname"..i,p.name,x+2,116,86,19,12,unlocked and colors.ink or colors.muted,5)
            if cooldown>0 then T("seedcool"..i,math.ceil(cooldown).."s",x+41,97,46,19,13,colors.red,5)end
            B("seed"..i,"",x,69,90,72,function()selectPlant(p.id)end,{0,0,0,0},8)
        end
        for row=1,5 do
            if rowActive(run.level,row) then
                local mower=run.mowers[row]
                if mower>=0 then
                    local x=mower==0 and 95 or mower
                    R("mowerbody"..row,x-15,rowY(row)+35,31,18,colors.red,5)
                    R("mowerwheels"..row,x-18,rowY(row)+51,37,6,colors.ink,5)
                    R("mowerhandle"..row,x-18,rowY(row)+19,4,20,colors.cream,5)
                end
                for col=1,9 do
                    local key=cellKey(row,col);local p=run.plants[key];local x=cellX(col)
                    B("cell"..key,"",x-42,rowY(row),82,66,function(mouse)plantAt(row,col,mouse)end,{0,0,0,0},7)
                    if p then
                        sprite("plant"..key,p.kind,x-26,rowY(row)+12,4,4)
                        if p.hp<plants[p.kind].hp then
                            R("hpbase"..key,x-25,rowY(row)+60,50,3,colors.wood,5)
                            R("hp"..key,x-25,rowY(row)+60,50*p.hp/plants[p.kind].hp,3,colors.gold,5)
                        end
                        if p.kind=="mine" and p.age<12 then T("pstate"..key,math.ceil(12-p.age).."s",x-23,rowY(row)+38,46,22,13,nil,5)
                        elseif p.kind=="chomper" and p.timer>0 then T("pstate"..key,math.ceil(p.timer).."s",x-23,rowY(row)+38,46,22,13,nil,5)
                        elseif (p.kind=="puff" or p.kind=="sunshroom") and def.theme~="night" then T("pstate"..key,"Z z",x-23,rowY(row)+10,46,22,15,nil,5)
                        elseif p.kind=="sunshroom" and p.age>=90 then T("pstate"..key,"＋",x+15,rowY(row)+13,20,20,15,colors.gold,5)end
                    end
                end
            else
                R("inactive"..row,130,rowY(row),756,66,{.18,.24,.15,.88},6)
                T("inactiveText"..row,"草坪养护中",135,rowY(row)+21,745,24,17,colors.muted,6)
            end
        end
        for i,z in ipairs(run.zombies)do
            local x=z.x-24;local y=rowY(z.row)+6+math.sin(run.time*4+i)*2
            sprite("zombie"..i,"zombie",x,y,4,5)
            if z.kind=="cone" and z.hp>200 then
                R("zacc1"..i,x+13,y-9,17,11,{1,.49,.13,1},6);R("zacc2"..i,x+8,y-1,27,5,colors.cream,6)
            elseif z.kind=="bucket" and z.hp>200 then
                R("zacc1"..i,x+8,y-8,28,17,{.60,.65,.65,1},6);R("zacc2"..i,x+5,y+6,33,4,{.82,.85,.81,1},6)
            elseif z.kind=="pole" and not z.jumped then
                R("zacc1"..i,x-14,y+26,70,4,colors.woodLight,6)
            elseif z.kind=="paper" and z.hp>180 then
                R("zacc1"..i,x-5,y+23,25,22,colors.cream,6);R("zacc2"..i,x-2,y+28,18,3,colors.woodLight,6)
            elseif z.kind=="flag" then
                R("zacc1"..i,x-6,y-13,3,55,colors.woodLight,6);R("zacc2"..i,x-29,y-13,24,19,colors.red,6)
            end
            if z.hp<C.enemies[z.kind].hp then R("zhp"..i,x+4,y+49,38*z.hp/C.enemies[z.kind].hp,3,z.slow>0 and palette.c or colors.red,6)end
            if z.slow>0 then T("zslow"..i,"冰",x+27,y-7,22,20,12,palette.C,6)end
        end
        for i,b in ipairs(run.bullets)do
            R("bullet"..i,b.x-4,rowY(b.row)+28,b.spore and 12 or 8,b.spore and 6 or 8,b.ice and palette.C or (b.spore and palette.P or palette.G),6)
        end
        for i,s in ipairs(run.suns)do
            B("sun"..i,"＋"..s.value,s.x-20,s.y-10,43,33,function()collect(i)end,{.90,.64,.08,s.ttl<3 and .6 or 1},9,true,15)
        end
        for i,f in ipairs(flashes)do
            R("flash"..i,max(125,f.x-f.radius),rowY(max(1,f.row-f.rows)),min(f.radius*2,756),68*(1+2*f.rows),{1,.69,.20,f.ttl},6)
        end
        B("shovel",selected=="shovel" and "铲子 ✓" or "铲子",258,560,82,32,actions.toggleShovel,selected=="shovel" and colors.gold or colors.button)
        B("collectAll","收阳",350,560,76,32,collectAll)
        B("pause","暂停",436,560,76,32,function()ctx.session.pause("user")end)
        B("map","地图",522,560,76,32,leaveBattle)
        B("sound",book.sound and "音效 开" or "音效 关",608,560,94,32,actions.toggleSound)
        B("help","玩法",712,560,76,32,actions.showHelp)
        B("save","保存",798,560,76,32,function()persist("manual")end)
        B("profiles","存档",884,560,65,32,actions.openProfiles)
    end
    local function modal(title)
        B("shield","",0,0,960,600,function()end,{.03,.06,.03,.75},20)
        R("modalborder",222,173,516,256,colors.gold,21)
        R("modalpanel",226,177,508,248,colors.wood,21)
        T("modalTitle",title,244,192,472,42,27,nil,22)
    end
    render=function()
        local state=read()
        book,slot,run,screen,selected=state.book,state.slot,state.run,state.screen,state.selected
        message,saveStatus,flashes,help,confirm=state.message,state.saveStatus,state.flashes,state.help,state.confirm
        ui.begin()
        if screen=="profiles" then drawProfiles()elseif screen=="map" then drawMap()else drawBattle()end
        footer()
        if screen=="battle" and run.status~="playing" then
            modal(run.status=="won" and (run.level==10 and "庭院守护者" or "守住了！") or "僵尸进屋了")
            local result=run.status=="won" and (run.level<10 and ("下一关解锁："..C.plants[run.level+1].name) or "十关全部完成 · 十种植物已收集") or "这次的阵型没守住。换个布局再试一次。"
            T("result",result,250,250,460,32,18,nil,22)
            T("resultKills","击退 "..run.kills.." 个敌人  ·  用时 "..floor(run.time).." 秒",250,291,460,30,16,nil,22)
            B("resultMap","返回地图",274,349,190,42,leaveBattle,nil,23)
            B("resultNext",run.status=="won" and run.level<10 and "下一关" or "重玩本关",496,349,190,42,function()startLevel(run.status=="won" and min(10,run.level+1) or run.level)end,nil,23)
        elseif help then
            modal("草坪守卫指南")
            T("helpBody","选种子 → 点草坪种植；点击阳光收集。\n铲子不返还阳光。每路有一台一次性割草机。\n撑杆跳过首株植物；读报破损后加速。\n夜间没有天降阳光，蘑菇白天会睡觉。\n战局自动保存。重开后读档可继续。",249,239,463,119,16,nil,22)
            B("helpBack","明白，继续守卫",320,372,320,35,actions.hideHelp,nil,23)
        elseif screen=="battle" and ctx.session.isPaused() then
            modal("庭院已暂停")
            T("pausedNote","阳光、敌人和种子冷却都已停止。\n"..saveStatus,254,257,452,58,18,nil,22)
            B("resume","继续游戏",276,354,190,43,function()ctx.session.resume()end,nil,23)
            B("pauseMap","保存并返回地图",495,354,190,43,leaveBattle,nil,23)
        end
        if confirm then
            modal(confirm.kind=="delete" and "删除这份花园存档？" or "重新开始一个关卡？")
            T("confirmNote",confirm.kind=="delete" and "该槽的关卡、金币和进行中的战局将被删除。\n其他存档不受影响。" or "当前战局会被替换。已通关进度和金币保留。",246,251,468,63,17,nil,22)
            B("confirmYes","确认",277,353,190,42,actions.acceptConfirm,colors.red,24)
            B("confirmNo","取消",495,353,190,42,actions.cancelConfirm,nil,24)
        end
        ui.finish()
    end
    return render
end
