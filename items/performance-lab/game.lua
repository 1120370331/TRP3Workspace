-- The performance project consumes only the public ctx API.
return function(ctx)
    local auto, index, current, player = false, 0, nil, nil
    local projectiles, operationNumber, fxEmitter = {}, 0, nil
    local probeCount = ctx.save.data.probeCount or 0
    local startTime, nextSound, nextStorage, payload = 0, 0, 0, nil
    local duration = ctx.content.benchmark.duration
    local warmup = ctx.content.benchmark.warmup
    local stages = {
        {name="baseline_empty",kind="empty",count=0},
        {name="texture_static_256",kind="static",count=256},
        {name="texture_move_128",kind="moving",count=128},
        {name="texture_move_512",kind="moving",count=512},
        {name="texture_move_1024",kind="moving",count=1024},
        {name="particles_64",kind="particles",count=64},
        {name="particles_128",kind="particles",count=128},
        {name="particles_256",kind="particles",count=256},
        {name="model_1",kind="model",count=1},
        {name="model_8",kind="model",count=8},
        {name="model_16",kind="model",count=16},
        {name="model_scene_1",kind="scene_model",count=1},
        {name="model_scene_8",kind="scene_model",count=8},
        {name="query_grid_400",kind="query",mode="grid",count=400},
        {name="query_naive_400",kind="query",mode="naive",count=400},
        {name="ai_30",kind="ai",count=30},
        {name="projectile_128",kind="projectile",count=80,shots=128},
        {name="mixed_30_128",kind="mixed",count=30,shots=128},
        {name="json_4kb",kind="codec",count=4096},
        {name="json_32kb",kind="codec",count=32768},
        {name="item_variable_roundtrip",kind="storage",count=0},
        {name="sound_5_per_second",kind="sound",count=0},
        {name="native_music",kind="music",count=0},
        {name="baseline_after_load",kind="empty",count=0},
    }
    local function stageByName(name)for _,stage in ipairs(stages)do if stage.name==name then return stage end end end
    local function spawnGrid(prefab, n)
        local columns = math.ceil(math.sqrt(n * 2.4))
        local rows = math.ceil(n / columns)
        for i = 1, n do
            ctx.world.spawn(prefab, {x=20+((i-1)%columns)*900/columns,y=35+math.floor((i-1)/columns)*270/rows})
        end
    end
    local function start(stage)
        local musicMessage
        ctx.session.resume(); ctx.perf.finish("interrupted")
        ctx.level.load("arena_01");ctx.fx.clear();fxEmitter=nil;projectiles = {}; player = nil; payload = nil
        ctx.sound.setEnabled(false); ctx.music.stop("phase_switch"); ctx.music.setEnabled(false)
        ctx.collision.setBroadphase(stage.mode or "grid")
        current = stage; startTime = ctx.clock.wall(); nextSound = startTime; nextStorage = startTime
        if stage.kind == "static" then spawnGrid("sprite",stage.count)
        elseif stage.kind == "moving" then spawnGrid("moving",stage.count)
        elseif stage.kind == "particles" then
            fxEmitter=assert(ctx.fx.start("perf_particles",{x=480,y=200,rate=stage.count,initialBurst=math.min(128,stage.count),seed=stage.count}))
        elseif stage.kind == "model" then spawnGrid("model",stage.count)
        elseif stage.kind == "scene_model" then spawnGrid("scene_model",stage.count)
        elseif stage.kind == "query" or stage.kind == "projectile" then spawnGrid("target",stage.count)
        elseif stage.kind == "ai" or stage.kind == "mixed" or stage.kind == "combat" then
            player = ctx.world.spawn(stage.kind=="combat" and "hero_play" or "hero",{x=90,y=20})
            for i=1,stage.count do ctx.world.spawn(stage.kind=="combat" and "enemy_play" or "enemy",{x=300+(i%20)*28,y=20+math.floor(i/20)*45}) end
        elseif stage.kind == "codec" then payload={marker="性能测试",text=string.rep("x",stage.count),values={1,true,"|~^"}}
        elseif stage.kind == "sound" then ctx.sound.setEnabled(true)
        elseif stage.kind == "music" then
            ctx.music.setEnabled(true)
            local ok, why=ctx.music.play("arena")
            ctx.perf.note("check.music",{ok=ok,reason=why,channel=ctx.music.channel})
            local reasons = {
                all_sound_disabled="魔兽总声音已关闭", master_volume_zero="魔兽主音量为 0",
                channel_disabled="播放通道已关闭", channel_volume_zero="播放通道音量为 0",
                sound_not_started="客户端未起播，请复制日志检查曲目资源",
                sound_unavailable="音频 API 或曲目资源不可用", sound_api_error="音频 API 调用失败",
            }
            musicMessage = ok and "BGM 已请求播放（"..ctx.music.channel.." 通道），请确认是否听到。"
                or "BGM 播放失败："..(reasons[why] or tostring(why)).."（"..tostring(ctx.music.channel).."）。"
        end
        ctx.perf.begin(stage.name,{kind=stage.kind,requested=stage.count,projectiles=stage.shots or 0,
            expectedModels=(stage.kind=="model" or stage.kind=="scene_model") and stage.count or 0,algorithm=stage.mode or "grid",
            soundEnabled=stage.kind=="sound",musicEnabled=stage.kind=="music",baseline="empty_engine_window"},
            {warmup=warmup,duration=duration})
        ctx.ui.notify(musicMessage or (stage.name .. "：预热 " .. warmup .. "s + 采样 " .. duration .. "s"))
    end
    local function single(stage) auto=false; start(stage) end
    local function nextOperation()
        operationNumber=operationNumber+1;return ctx.session.id..":"..operationNumber
    end
    local function reportResult(result) ctx.ui.notify(ctx.data.encode(result));ctx.perf.saveLog() end
    return {
        onStart=function()
            ctx.level.load("arena_01");ctx.sound.setEnabled(false)
            ctx.ui.button("自动基准",function()auto=true;index=1;ctx.perf.note("suite.start",{phases=#stages});start(stages[index])end)
            ctx.ui.button("纯纹理",function()single(stageByName("texture_static_256"))end)
            local textureParticleMode=false
            ctx.ui.button("纹理/粒子",function()
                single(stageByName(textureParticleMode and "particles_128" or "texture_move_1024"))
                textureParticleMode=not textureParticleMode
            end)
            local sceneMode=false
            ctx.ui.button("模型/场景",function()single(stageByName(sceneMode and "model_scene_8" or "model_16"));sceneMode=not sceneMode end)
            ctx.ui.button("碰撞 Grid",function()single(stageByName("query_grid_400"))end)
            ctx.ui.button("碰撞 Naive",function()single(stageByName("query_naive_400"))end)
            ctx.ui.button("AI 30",function()single(stageByName("ai_30"))end)
            ctx.ui.button("综合负载",function()single(stageByName("mixed_30_128"))end)
            ctx.ui.button("战斗试跑",function()single({name="manual_combat",kind="combat",count=3,continuous=true})end)
            ctx.ui.button("接管/释放",function()
                if ctx.input.mode=="capture" then ctx.input.release();ctx.ui.notify("已释放键盘；按键只读透传。")
                else ctx.session.resume();local ok,why=ctx.input.acquire();ctx.ui.notify(ok and "已接管：A/D 移动，Space 跳跃，J 近战，K 弹体；Esc 关闭游戏，暂停请点暂停/继续。" or tostring(why)) end
            end)
            ctx.ui.button("暂停/继续",function() if ctx.session.isPaused() then ctx.session.resume() else ctx.session.pause("user") end end)
            ctx.ui.button("停止测试",function()auto=false;current=nil;ctx.perf.finish("manual_stop");ctx.world.clear();ctx.fx.clear();fxEmitter=nil;ctx.sound.stopOwner();ctx.music.stop("user");ctx.perf.saveLog()end)
            ctx.ui.button("复制日志",function()auto=false;ctx.ui.showLog(false)end)
            ctx.ui.button("上次日志",function()auto=false;ctx.ui.showLog(true)end)
            ctx.ui.button("道具读写",function()probeCount=probeCount+1;reportResult(ctx.save.probe());ctx.save.request("manual_probe")end)
            ctx.ui.button("库存查询",function()reportResult({token=ctx.inventory.count("token"),blade=ctx.inventory.count("blade")})end)
            ctx.ui.button("发1材料",function()reportResult(ctx.inventory.grant("token",1,nextOperation()))end)
            ctx.ui.button("消耗1材料",function()reportResult(ctx.inventory.consume("token",1,nextOperation()))end)
            ctx.ui.button("发1装备",function()reportResult(ctx.inventory.grant("blade",1,nextOperation()))end)
            ctx.ui.button("交易目标",function()local ok,why=ctx.trade.open();reportResult({opened=ok,reason=why})end)
            ctx.ui.button("音效测试",function()single(stageByName("sound_5_per_second"))end)
            ctx.ui.button("BGM测试",function()single(stageByName("native_music"))end)
            ctx.ui.button("MIDI导入",function()
                auto=false
                if not ctx.music.capabilities().musician then reportResult({status="skipped",reason="Musician_not_loaded"});return end
                ctx.ui.prompt("粘贴 Musician 转换工具生成的曲目码（不是原始 MIDI 的 Base64）", "", function(code)
                    ctx.session.resume();ctx.music.setEnabled(true)
                    local ok,why=ctx.music.playCode(code);ctx.perf.note("check.musician",{accepted=ok,reason=why,bytes=#code});ctx.ui.notify(ok and "曲目加载中；只在本机播放。" or tostring(why))
                end)
            end)
            ctx.ui.button("模型/碰撞框",function()ctx.ui.toggleBounds();local records=ctx.assets.recordModels();ctx.ui.notify("模型记录已写日志，数量 "..#records.."；碰撞框显示已切换。")end)
        end,
        onFrame=function()
            if not current then return end
            if not ctx.perf.isRunning() and not current.continuous then
                if auto then
                    index=index+1
                    if stages[index] then start(stages[index])
                    else auto=false;current=nil;ctx.perf.note("suite.end",{phases=#stages});ctx.perf.saveLog();ctx.session.pause("suite_complete");ctx.ui.notify("自动基准完成。点复制日志，在游戏外保存为 .ndjson。") end
                else current=nil;ctx.session.pause("phase_complete") end
                return
            end
            local now=ctx.clock.wall()
            if current.shots then
                for i=#projectiles,1,-1 do if not ctx.world.get(projectiles[i]) then projectiles[i]=projectiles[#projectiles];projectiles[#projectiles]=nil end end
                while #projectiles<current.shots do
                    local i=#projectiles+1
                    projectiles[i]=ctx.world.spawn("bullet",{x=5+(i%8)*3,y=40+(i*17)%280},{faction="player",vx=550})
                end
            end
            if current.kind=="query" then
                ctx.perf.measure("queryBatchMs",function()
                    for i=1,10 do ctx.collision.query({x=(i*67)%800,y=35+(i*19)%250,w=70,h=70},"enemy") end
                end)
            elseif current.kind=="codec" then
                local encoded
                ctx.perf.measure("jsonEncodeMs",function()encoded=ctx.data.encode(payload)end)
                if encoded then ctx.perf.measure("jsonDecodeMs",function()ctx.data.decode(encoded)end) end
            elseif current.kind=="storage" and now>=nextStorage then
                nextStorage=now+1;ctx.save.probe()
            elseif current.kind=="sound" and now>=nextSound then
                nextSound=now+.2;ctx.sound.play("combat_hit")
            end
        end,
        onFixedUpdate=function(dt,input)
            if player and ctx.world.get(player) then
                ctx.motion.setIntent(player,{moveX=input.moveX,jumpPressed=input.jumpPressed})
                if input.attackPressed then ctx.combat.requestAction(player,"slash") end
                if input.firePressed then ctx.combat.requestAction(player,"shoot") end
                if auto and current and current.kind=="mixed" then ctx.combat.requestAction(player,"shoot") end
            end
        end,
        onPause=function()auto=false end,
        onSave=function()return {probeCount=probeCount}end,
    }
end
