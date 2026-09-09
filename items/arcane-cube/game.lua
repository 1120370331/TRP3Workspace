return function(ctx,modules)
    local P,art=modules.puzzle,modules.geometry
    local M=ctx.scene3d.math
    local s={schema=1,n=3,history={},moves=0,elapsed=0,started=false,won=false,challenge=false,assisted=false,bests={},
        yaw=.63,pitch=.42,distance=7.8,axis="y",layer=3,skin="tidal",message="海潮皮肤已应用。转动视角，或打乱魔方开始挑战。"}
    local saved=ctx.save.data
    if next(saved) then
        assert(saved.schema==1 and P.validOrder(saved.n),"魔方存档版本或阶数无效；原存档已保留。")
        P.restore(saved.n,saved.history)
        for _,k in ipairs({"moves","elapsed"})do assert(type(saved[k])=="number" and saved[k]>=0 and saved[k]<1e9,"invalid cube counter")end
        assert(saved.moves%1==0 and type(saved.bests)=="table","invalid cube score")
        for _,move in ipairs(saved.history)do assert(move.source=="scramble" or move.source=="player","invalid cube history source")end
        for key,b in pairs(saved.bests)do
            assert(P.validOrder(tonumber(key)) and type(b)=="table" and type(b.time)=="number" and b.time>=0 and b.time<1e9 and type(b.moves)=="number" and b.moves>=0 and b.moves%1==0,"invalid cube best score")
        end
        for _,k in ipairs({"n","history","moves","elapsed","started","won","challenge","assisted","bests"})do s[k]=saved[k]end
        for _,k in ipairs({"started","won","challenge","assisted"})do assert(type(s[k])=="boolean","invalid cube session flag")end
        for _,k in ipairs({"yaw","pitch","distance"})do if type(saved[k])=="number" and saved[k]==saved[k] and math.abs(saved[k])<1000 then s[k]=saved[k]end end
        s.pitch=math.max(-1.35,math.min(1.35,s.pitch));s.distance=math.max(5.4,math.min(12,s.distance))
        s.axis=(saved.axis=="x" or saved.axis=="y" or saved.axis=="z") and saved.axis or "y"
        s.layer=type(saved.layer)=="number" and saved.layer%1==0 and math.max(1,math.min(s.n,saved.layer)) or s.n
        assert(saved.skin==nil or saved.skin=="tidal" or saved.skin=="classic","invalid cube skin")
        s.skin=saved.skin or "tidal"
        s.message="已恢复上次局面；从完整的一步继续。"
    end
    local puzzle=P.restore(s.n,s.history)
    if s.won then assert(P.isSolved(puzzle),"invalid solved cube save")end
    local scene,ui,active,gesture,confirmation,fireworks,materials,savedCamera
    local byNode,actions={},{}
    local nextUI,nextSave=0,10
    local function display()
        if not ui then return end
        s.paused=ctx.session.isPaused();s.busy=active~=nil or s.replaying==true or (fireworks and fireworks.testing)==true
        s.confirm=confirmation~=nil;s.hasHistory=#s.history>0
        s.canUndo=#s.history>0 and s.history[#s.history].source=="player"
        s.fireworks=fireworks and fireworks.snapshot()
        s.benchmark=fireworks and fireworks.testing
        s.materials=materials and materials.snapshot()
        s.nativeFrames=scene and scene.stats().scene3DNativeFrames
        ui.draw(s,actions)
    end
    local function message(text)s.message=text;display()end
    local function remember()ctx.save.request("cube_move")end
    local function camera()
        scene.orbit(s.yaw,s.pitch,s.distance,M.vec());display()
    end
    local function selectSlice()
        for id,c in pairs(byNode)do
            local bright=P.inSlice(c,s.n,s.axis,s.layer) and 1 or .82
            scene.setTint(id,{bright,bright,bright,1})
        end
        display()
    end
    local function pose(c)
        local cell=3.35/s.n
        return {position=M.mul(c.position,cell/2),rotation=P.euler(c),scale=M.vec(cell,cell,cell)}
    end
    local function rebuild()
        scene.clear();byNode={};scene.create("turn",{})
        if s.skin=="tidal" then art.registerSkin(scene,modules.pixel_art)end
        for _,c in ipairs(puzzle.cubies)do
            local spec=pose(c);local bindings
            spec.mesh,bindings=art.mesh(c,ctx.scene3d,P,s.skin,s.n);spec.tag=c.id
            local id="cubie_"..c.id;scene.create(id,spec);byNode[id]=c
            if s.skin=="tidal" then assert(scene.setPixelMaterials(id,bindings),"cube skin exceeds face budget")end
        end
        selectSlice();camera()
    end
    local function checkWin()
        local solved=P.isSolved(puzzle)
        if solved and s.started and not s.replaying then
            if not s.won then
                s.won=true
                if s.challenge and not s.assisted then
                    local key=tostring(s.n);local best=s.bests[key]
                    if not best or s.elapsed<best.time then s.bests[key]={time=s.elapsed,moves=s.moves}end
                    message("六面归一！挑战完成，用时与成绩已保存。")
                else message("六面归一！已完成本次练习。")end
                fireworks.celebrate("solved")
            end
        elseif not solved then s.won=false end
    end
    local function startTurn(move,kind)
        if active or ctx.session.isPaused() or confirmation or fireworks.testing or s.materialsOpen then return false end
        if kind=="player" and #s.history>=P.MAX_HISTORY then message("本局已达 2000 步记录上限，请开始新局。");return false end
        assert(P.validMove(move,s.n))
        if kind=="player" then
            if s.won then s.challenge=false;s.started=false;s.won=false;s.elapsed=0;s.moves=0 end
            s.started=true
            s.message="正在转动 "..string.upper(move.axis).." 轴第 "..move.layer.." 层。"
        end
        active={move={axis=move.axis,layer=move.layer,dir=move.dir},kind=kind,elapsed=0,duration=kind=="replay" and .085 or .19,ids={}}
        for id,c in pairs(byNode)do if P.inSlice(c,s.n,move.axis,move.layer)then
            active.ids[#active.ids+1]=id;scene.setParent(id,"turn")
        end end
        display();return true
    end
    local function finishTurn()
        local turn=active;P.apply(puzzle,turn.move)
        scene.setTransform("turn",{rotation=M.vec()})
        for _,id in ipairs(turn.ids)do scene.setParent(id,nil);scene.setTransform(id,pose(byNode[id]))end
        if turn.kind=="player" then
            local move=turn.move;move.source="player";s.history[#s.history+1]=move;s.moves=s.moves+1
        else table.remove(s.history);s.assisted=true end
        active=nil;selectSlice()
        if turn.kind=="replay" then
            if #s.history==0 then
                s.replaying=false;s.won=P.isSolved(puzzle);s.started=false
                message("回放复原完成。演示按本局操作倒序返回，不计挑战成绩。")
                if s.won then fireworks.celebrate("replay_solved")end
            end
        else
            if not P.isSolved(puzzle)then s.message=turn.kind=="undo" and "已撤销一步，本局作为辅助练习。" or "继续转动，让六个面各归一色。"end
            checkWin()
        end
        remember();display()
    end
    local function fresh(n,scramble)
        fireworks.stop("new_game")
        active=nil;gesture=nil;s.replaying=false;s.n=n;s.history={};s.moves=0;s.elapsed=0;s.started=false;s.won=false
        s.challenge=scramble;s.assisted=false;s.axis="y";s.layer=n;puzzle=P.new(n)
        if scramble then
            local seed=math.floor(ctx.clock.wall()*1000)+n*173+#s.history
            for _,move in ipairs(P.scramble(n,seed))do move.source="scramble";s.history[#s.history+1]=move;P.apply(puzzle,move)end
            if P.isSolved(puzzle)then local move={axis="x",layer=n,dir=1,source="scramble"};P.apply(puzzle,move);s.history[#s.history+1]=move end
            s.message="已打乱。第一次转层开始计时，六面归一完成挑战。"
        else s.message="全新 "..n.." 阶魔方。可自由练习，也可打乱后计时挑战。"end
        rebuild();remember()
    end
    local function requestFresh(n,scramble)
        if active or fireworks.testing or s.materialsOpen then return end
        if #s.history>0 then confirmation={n=n,scramble=scramble};gesture=nil;display()
        else fresh(n,scramble)end
    end
    actions.order=function(n)if n~=s.n then requestFresh(n,false)end end
    actions.skin=function()
        if active or s.replaying or fireworks.testing or s.materialsOpen or ctx.session.isPaused()then return end
        s.skin=s.skin=="tidal" and "classic" or "tidal";rebuild();remember()
        ctx.perf.note("cube.skin",{skin=s.skin,order=s.n})
        message(s.skin=="tidal" and "已切换海潮皮肤；图案随实际方块一起转动。" or "已切换经典六色皮肤。")
    end
    actions.axis=function(axis)if not active and not s.replaying then s.axis=axis;selectSlice()end end
    actions.layer=function(layer)if not active and not s.replaying then s.layer=layer;selectSlice()end end
    actions.turn=function(dir)if not s.replaying then startTurn({axis=s.axis,layer=s.layer,dir=dir},"player")end end
    actions.scramble=function()requestFresh(s.n,true)end
    actions.reset=function()requestFresh(s.n,false)end
    actions.confirm=function()local c=confirmation;confirmation=nil;if c then fresh(c.n,c.scramble)end end
    actions.cancel=function()confirmation=nil;display()end
    actions.undo=function()
        if active or s.replaying then return end
        local last=s.history[#s.history]
        if last and last.source=="player" then s.assisted=true;startTurn(P.inverse(last),"undo");s.message="已使用撤销，本局作为辅助练习。"end
    end
    actions.replay=function()
        if s.replaying then s.replaying=false;message("已停止演示，可以继续操作。");return end
        if active or #s.history==0 then return end
        s.replaying=true;s.assisted=true
        message("正在倒序回放本局操作；可随时停止演示。")
    end
    actions.camera=function()s.yaw=.63;s.pitch=.42;s.distance=7.8;camera()end
    actions.fireworks=function()
        if s.materialsOpen then actions.materials()end
        s.fireworksOpen=not s.fireworksOpen;display()
    end
    actions.materials=function()
        if active or s.replaying or fireworks.testing then return end
        gesture=nil
        if s.materialsOpen then
            materials.leave();s.materialsOpen=false
            s.yaw,s.pitch,s.distance=savedCamera.yaw,savedCamera.pitch,savedCamera.distance;savedCamera=nil
            rebuild()
        else
            fireworks.stop("materials_view");s.fireworksOpen=false
            savedCamera={yaw=s.yaw,pitch=s.pitch,distance=s.distance}
            s.yaw,s.pitch,s.distance=.27,.24,5.8;s.materialsOpen=true;materials.enter()
        end
        display()
    end
    actions.materialSelect=function(index)materials.select(index);display()end
    actions.materialTexture=function(index)materials.texture(index);display()end
    actions.materialUV=function()materials.rotateUV();display()end
    actions.materialSix=function()materials.sixFaces();display()end
    actions.materialClear=function()materials.removeMaterial();display()end
    actions.materialSpin=function()materials.toggleSpin();display()end
    actions.materialGroup=function()materials.rotateGroup();display()end
    actions.materialMotion=function()materials.toggleMotion();display()end
    actions.materialEffects=function()materials.toggleEffects();display()end
    actions.fireworkKind=function(id)fireworks.select(id);display()end
    actions.fireworkIntensity=function(level)fireworks.setIntensity(level);display()end
    actions.fireworkQuality=function()fireworks.toggleQuality();display()end
    actions.fireworkPreview=function()fireworks.preview();display()end
    actions.fireworkShow=function()fireworks.show();display()end
    actions.fireworkStop=function()fireworks.stop("cancelled");display()end
    actions.fireworkBenchmark=function()if not active and not s.replaying then fireworks.benchmark();gesture=nil;display()end end
    actions.fireworkLog=function()fireworks.stop("log_export");ctx.perf.saveLog();ctx.ui.showLog();display()end
    actions.pause=function()
        if confirmation then confirmation=nil end
        if ctx.session.isPaused()then ctx.session.resume()else ctx.session.pause("cube_pause")end;display()
    end
    local function selectedPoint(hit)
        local c=byNode[hit.id];if not c then return end
        local normal=hit.normal;local axis="x"
        if math.abs(normal.y)>math.abs(normal.x)then axis="y"end
        if math.abs(normal.z)>math.abs(normal[axis])then axis="z"end
        s.axis=axis;s.layer=math.floor((c.position[axis]+s.n+1)/2);selectSlice()
    end
    local function pointer(event)
        if confirmation or ctx.session.isPaused() or fireworks.testing then gesture=nil;return end
        if event.phase=="wheel" then s.distance=math.max(5.4,math.min(12,s.distance-event.delta*.45));camera();return end
        if event.phase=="cancel" then gesture=nil;return end
        if event.phase=="down" then
            local hit=scene.pick(event.x,event.y)
            gesture={x=event.x,y=event.y,button=event.button,hit=hit,rotated=false}
            if event.button=="LeftButton" and hit and not active and not s.replaying then
                if s.materialsOpen then materials.pick(hit);display()else selectedPoint(hit)end
            end
        elseif event.phase=="move" and gesture then
            if event.button=="RightButton" or not gesture.hit or s.materialsOpen then
                s.yaw=(s.yaw-(event.dx or 0)*.008)%(2*math.pi);s.pitch=math.max(-1.35,math.min(1.35,s.pitch+(event.dy or 0)*.008));camera()
            end
        elseif event.phase=="up" and gesture then
            local g=gesture;gesture=nil
            if event.button~="LeftButton" or not g.hit or active or s.replaying or s.materialsOpen then return end
            local dx,dy=event.x-g.x,event.y-g.y
            if dx*dx+dy*dy<225 then return end
            -- Choose the in-plane rotation axis whose projected tangent best matches
            -- the gesture. This also makes inner slices accessible by dragging.
            local c=byNode[g.hit.id];if not c then return end
            local best,bestScore=nil,0
            for _,axis in ipairs({"x","y","z"})do
                if math.abs(g.hit.normal[axis])<.5 then
                    local tangent=M.cross(axis=="x" and M.vec(1,0,0) or axis=="y" and M.vec(0,1,0) or M.vec(0,0,1),g.hit.point)
                    local x1,y1=scene.project(g.hit.point);local x2,y2=scene.project(M.add(g.hit.point,M.mul(tangent,.1)))
                    if x1 and x2 then
                        local tx,ty=x2-x1,y2-y1;local length=math.sqrt(tx*tx+ty*ty)
                        if length>1e-6 then
                            local score=(dx*tx+dy*ty)/length
                            if math.abs(score)>bestScore then bestScore=math.abs(score);best={axis=axis,layer=math.floor((c.position[axis]+s.n+1)/2),dir=score>=0 and 1 or -1}end
                        end
                    end
                end
            end
            if best then s.axis=best.axis;s.layer=best.layer;startTurn(best,"player")end
        end
    end
    return {
        onStart=function()
            scene=ctx.scene3d.create({viewport={x=20,y=143,w=640,h=355}})
            fireworks=modules.fireworks.new(ctx,scene,function()return s.n end,function()return s.skin end)
            materials=modules.materials.new(ctx,scene,modules.pixel_art)
            ui=modules.ui.new(ctx,art);rebuild();scene.onPointer(pointer);ctx.input.acquire();display()
        end,
        onFixedUpdate=function(dt,input)
            fireworks.update(dt)
            materials.update(dt)
            if s.started and not s.won and not s.replaying and not fireworks.testing and not s.materialsOpen then s.elapsed=s.elapsed+dt end
            if active then
                active.elapsed=active.elapsed+dt
                local t=math.min(1,active.elapsed/active.duration);local smooth=t*t*(3-2*t)
                local rotation=M.vec();rotation[active.move.axis]=active.move.dir*math.pi/2*smooth
                scene.setTransform("turn",{rotation=rotation})
                if t>=1 then finishTurn()end
            elseif s.replaying then
                local last=s.history[#s.history]
                if last then startTurn(P.inverse(last),"replay")else s.replaying=false end
            end
            if not confirmation and not active and not s.replaying and not fireworks.testing and not s.fireworksOpen and not s.materialsOpen then
                if input.pressed.turn then actions.turn(1)elseif input.pressed.inverse then actions.turn(-1)elseif input.pressed.undo then actions.undo()end
            end
            if ctx.clock.now()>=nextSave then nextSave=ctx.clock.now()+10;remember()end
        end,
        onFrame=function()
            if ctx.clock.now()>=nextUI then nextUI=ctx.clock.now()+.1;display()end
        end,
        onPause=function()gesture=nil;if fireworks then fireworks.onPause()end;display()end,
        onResume=function()display()end,
        onCloseRequested=function(reason)
            if reason=="escape" then actions.pause();return end
            local ok=ctx.save.flush("cube_close")
            if ok then ctx.session.stop(reason,{save=false})
            else ctx.session.pause("save_failed");message("保存未成功，窗口已保留。请检查道具后再次关闭。")end
        end,
        onSave=function()
            local camera=savedCamera or s
            return {schema=1,n=s.n,history=s.history,moves=s.moves,elapsed=s.elapsed,started=s.started,won=s.won,
                challenge=s.challenge,assisted=s.assisted,bests=s.bests,yaw=camera.yaw,pitch=camera.pitch,distance=camera.distance,axis=s.axis,layer=s.layer,skin=s.skin}
        end,
        onStop=function()gesture=nil;active=nil;if fireworks then fireworks.stop("stopped")end end,
    }
end
