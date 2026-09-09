-- Behavioral host double. It supplies no renderer, GPU, or real performance evidence.
Mock = { time=0, frames={}, timers={}, sounds={}, nextSound=0, keys={}, inCombat=false, instanceType="none", focus=nil,
    messages={}, writes=0, callbacks={}, capacity=5000, failures={}, inventory={id="bag",content={}}, classes={}, soundCalls={}, cvarWrites=0,
    cvars={Sound_EnableAllSound="1",Sound_EnableSFX="1",Sound_EnableMusic="1",Sound_MasterVolume="1",Sound_SFXVolume="1",Sound_MusicVolume="1"} }
local Frame={}; Frame.__index=Frame
function Frame:SetScript(name,fn) self.scripts[name]=fn end
function Frame:GetScript(name)return self.scripts[name]end
function Frame:Show()self.shown=true end
function Frame:Hide()local was=self.shown;self.shown=false;if was and self.scripts.OnHide then self.scripts.OnHide(self)end end
function Frame:IsShown()return self.shown and (not self.parent or self.parent:IsShown())end
Frame.IsVisible=Frame.IsShown
function Frame:SetSize(w,h)self.width=w;self.height=h end
function Frame:SetWidth(w)self.width=w end
function Frame:SetHeight(h)self.height=h end
function Frame:GetWidth()return self.width or (self.parent and self.parent:GetWidth()-24) or 1920 end
function Frame:GetHeight()return self.height or (self.parent and self.parent:GetHeight()-238) or 1080 end
function Frame:SetPoint(...)self.point={...}end
function Frame:ClearAllPoints()self.point=nil end
function Frame:SetAllPoints(parent)self.parent=parent or self.parent;self.allPoints=self.parent end
function Frame:SetText(text)self.text=text end
function Frame:GetText()return self.text or ""end
function Frame:SetFrameLevel(level)self.requestedLevel=level;self.level=math.max(0,math.min(10000,math.floor(level)))end
function Frame:GetFrameLevel()return math.min(10000,self.level or (self.parent and self.parent:GetFrameLevel()+1) or 1)end
function Frame:SetColorTexture(...)self.color={...}end
function Frame:SetTexture(asset,wrapX,wrapY)self.texture=asset;self.wrapX=wrapX;self.wrapY=wrapY;self.textureCalls=(self.textureCalls or 0)+1;return not Mock.noTextures end
function Frame:SetTexCoord(...)self.texCoord={...}end
function Frame:SetVertexColor(...)self.vertexColor={...}end
function Frame:SetBlendMode(mode)self.blend=mode end
function Frame:CreateMaskTexture()return CreateFrame("MaskTexture",nil,self)end
function Frame:AddMaskTexture(mask)self.mask=mask end
function Frame:RemoveMaskTexture(mask)if self.mask==mask then self.mask=nil end end
function Frame:SetAtlas(atlas)self.atlas=atlas;return not Mock.noTextures end
function Frame:SetRotation(value)self.rotation=value end
function Frame:SetVertexOffset(index,x,y)self.vertices=self.vertices or {};self.vertices[index]={x,y}end
function Frame:SetSnapToPixelGrid(value)self.snapToPixelGrid=value end
function Frame:SetTexelSnappingBias(value)self.texelSnappingBias=value end
function Frame:SetParent(parent)self.parent=parent end
function Frame:SetCamDistanceScale(value)self.cameraDistance=value end
function Frame:SetPortraitZoom(value)self.portraitZoom=value end
function Frame:SetTextColor(...)self.textColor={...}end
function Frame:SetFont(...)self.font={...}end
function Frame:SetAlpha(alpha)self.alpha=alpha end
function Frame:RegisterForClicks(...)self.clicks={...}end
function Frame:RegisterEvent(name)self.events[name]=true end
function Frame:UnregisterAllEvents()self.events={}end
function Frame:EnableKeyboard(enabled)
    if Mock.inCombat and Mock.restrictKeyboard then error("keyboard protected in combat")end
    self.keyboard=enabled
end
function Frame:SetPropagateKeyboardInput(value)
    if Mock.inCombat and Mock.restrictKeyboard then error("propagation restricted")end
    self.propagate=value
end
function Frame:SetFocus()Mock.focus=self end
function Frame:ClearFocus()if Mock.focus==self then Mock.focus=nil end end
function Frame:SetScrollChild(frame)self.scrollChild=frame end
function Frame:SetDisplayInfo(id)
    self.modelSetCalls=(self.modelSetCalls or 0)+1
    self.displayID=id
    self.loadedAt=Mock.time+(Mock.modelLoadDelay or 0)
    self.modelID=Mock.modelsNeverLoad and 0 or id+1000
    if self.modelID>0 and self.scripts.OnModelLoaded then self.scripts.OnModelLoaded(self)end
end
Frame.SetModel=Frame.SetDisplayInfo
function Frame:SetModelByCreatureDisplayID(id)
    self.modelSourceKind="creatureDisplayID";return self:SetDisplayInfo(id)
end
function Frame:SetModelByFileID(id)
    self.modelSourceKind="fileID";return self:SetDisplayInfo(id)
end
function Frame:CreateActor(name)return CreateFrame("Actor",name,self)end
function Frame:SetPosition(x,y,z)self.position={x=x,y=y,z=z}end
-- ModelSceneActor translations are scaled with the model (Blizzard's
-- AddOrUpdateDropShadow projects GetPosition() * GetScale()).
function Mock.actorWorldPoint(actor,x,y,z)
    local c,s=math.cos(actor.yaw or 0),math.sin(actor.yaw or 0)
    local p,scale=actor.position,actor.scale or 1
    return {x=(p.x+x*c-y*s)*scale,y=(p.y+x*s+y*c)*scale,z=(p.z+z)*scale}
end
function Frame:GetActiveBoundingBox()
    if not self:IsLoaded()then return {x=0,y=0,z=0},{x=0,y=0,z=0}end
    if Mock.requireUnpausedScene and self.parent and self.parent.kind=="ModelScene" and self.parent.paused then
        return {x=0,y=0,z=0},{x=0,y=0,z=0}
    end
    if Mock.noModelBounds then return {x=0,y=0,z=0},{x=0,y=0,z=0}end
    local b=Mock.actorBounds and Mock.actorBounds[self.displayID]
    local bottom,top=b and b[1] or {x=-1,y=-1,z=0},b and b[2] or {x=1,y=1,z=2}
    if Mock.scalarModelBounds then return bottom.x,bottom.y,bottom.z,top.x,top.y,top.z end
    return bottom,top
end
function Frame:GetMaxBoundingBox()
    local b=Mock.actorMaxBounds and Mock.actorMaxBounds[self.displayID]
    if not b then return self:GetActiveBoundingBox()end
    if Mock.scalarModelBounds then return b[1].x,b[1].y,b[1].z,b[2].x,b[2].y,b[2].z end
    return b[1],b[2]
end
function Frame:GetModelFileID()return self.modelID or 0 end
function Frame:IsLoaded()return (self.modelID or 0)>0 and Mock.time>=(self.loadedAt or 0)end
-- Observed on retail 12.1.0: this can stay false while IsLoaded and both
-- bounding boxes are valid. It is not the ModelSceneActor readiness contract.
function Frame:IsGeoReady()return false end
function Frame:ClearModel()self.modelID=0 end
function Frame:SetAnimation(id,variation,speed,offset)self.animation=id;self.animationSpeed=speed;self.animationOffset=offset end
function Frame:SetAttribute(key,value)self.attributes[key]=value end
function Frame:GetAttribute(key)return self.attributes[key]end
for _,name in ipairs({"SetJustifyH","SetFrameStrata","SetClampedToScreen","SetMovable","EnableMouse","RegisterForDrag","StartMoving","StopMovingOrSizing","SetClipsChildren","SetMultiLine","SetAutoFocus","SetFontObject","SetMaxLetters","HighlightText","SetModelScale","SetFacing","SetCameraFieldOfView","SetCameraPosition","SetCameraFarClip","SetScale","SetYaw","SetPaused"})do Frame[name]=function()end end
function Frame:EnableMouse(value)self.mouseEnabled=value end
function Frame:IsMouseEnabled()return self.mouseEnabled==true end
function Frame:SetClipsChildren(value)self.clipsChildren=value end
function Frame:SetCameraOrientationByAxisVectors(...)self.cameraAxes={...}end
function Frame:SetCameraOrientationByYawPitchRoll(yaw,pitch,roll)self.cameraOrientation={yaw,pitch,roll}end
function Frame:SetCameraFieldOfView(value)self.fov=value end
function Frame:SetCameraPosition(x,y,z)self.cameraPosition={x=x,y=y,z=z}end
function Frame:SetCameraNearClip(value)self.nearClip=value end
function Frame:SetCameraFarClip(value)self.farClip=value end
function Frame:SetAllowOverlappedModels(value)self.allowOverlappedModels=value end
function Frame:ClearFog()self.fogCleared=true end
function Frame:SetScale(value)self.scale=value end
function Frame:GetEffectiveScale()
    return (self.scale or 1)*(self.parent and self.parent:GetEffectiveScale() or (Mock.uiScale or 1))
end
function Frame:Project3DPointTo2D(x,y,z)
    if Mock.projectionUnavailable then return nil end
    local camera=self.cameraPosition
    if not camera then return nil end
    local depth=x-camera.x
    if depth<=(self.nearClip or .01) or depth>=(self.farClip or 1000)then return nil end
    local bounds=self.allPoints or self
    local w,h=bounds:GetWidth(),bounds:GetHeight()
    local half=depth*math.tan(self.fov/2)
    local halfHeight=Mock.horizontalModelFov and half*h/w or half
    local halfWidth=halfHeight*w/h
    local scale=self:GetEffectiveScale()
    return (w/2+(Mock.modelProjectionRight or 1)*(y-camera.y)*w/(2*halfWidth))*scale,
        (h/2+(z-camera.z)*h/(2*halfHeight))*scale,depth
end
function Frame:SetYaw(value)self.yaw=value end
function Frame:SetCooldown(start,duration)self.cooldownStart=start;self.cooldownDuration=duration end
function Frame:SetPaused(value)self.paused=value end
function Frame:Clear()self.cooldownStart=nil;self.cooldownDuration=nil end
function Frame:SetDrawSwipe(value)self.drawSwipe=value end
function Frame:SetDrawEdge(value)self.drawEdge=value end
function Frame:SetDrawBling(value)self.drawBling=value end
function Frame:SetHideCountdownNumbers(value)self.hideCountdownNumbers=value end
function Frame:SetSwipeColor(...)self.swipeColor={...}end
function CreateFrame(kind,name,parent,template)
    if Mock.secureClick then error("GUI creation during secure macro; delayed Lua is required")end
    if (kind=="PlayerModel" or kind=="ModelScene") and Mock.noModels then error("models unavailable")end
    local f=setmetatable({kind=kind,name=name,parent=parent,scripts={},events={},attributes={},shown=true},Frame)
    Mock.frames[#Mock.frames+1]=f;return f
end
function Frame:CreateTexture()return CreateFrame("Texture",nil,self)end
function Frame:CreateFontString()return CreateFrame("FontString",nil,self)end
UIParent=CreateFrame("Frame");UIParent:SetSize(1920,1080)
C_PetJournal={
    GetDisplayIDByIndex=function(species,index)
        if Mock.petJournalPending or Mock.petTableOnly then return nil end
        return 100000+species*10+index
    end,
    GetPetInfoTableBySpeciesID=function(species)
        if Mock.petJournalPending then return nil end
        return {displayID=100000+species*10+1,creatureID=species+500000}
    end,
}
UISpecialFrames={}
-- Models Escape dispatch only; it does not prove native hit testing or protected input behavior.
function Mock.pressEscape()
    if Mock.focus and Mock.focus.scripts.OnEscapePressed then
        Mock.focus.scripts.OnEscapePressed(Mock.focus); return
    end
    for i=#Mock.frames,1,-1 do
        local f=Mock.frames[i]
        if f:IsShown() and f.keyboard and f.scripts.OnKeyDown then
            f.scripts.OnKeyDown(f,"ESCAPE")
            if f.propagate==false then return end
        end
    end
    for _,name in ipairs(UISpecialFrames)do
        local f=_G[name];if f and f:IsShown()then f:Hide()end
    end
end
function GetTime()return Mock.time end
C_Timer={After=function(delay,fn)Mock.timers[#Mock.timers+1]={at=Mock.time+delay,fn=fn}end}
function GetFramerate()return 60 end
function debugprofilestop()return os.clock()*1000 end
function date(format)return os.date(format,1700000000+math.floor(Mock.time))end
function gcinfo()return collectgarbage("count")end
function GetBuildInfo()return "MOCK", "0", "not a client", 0 end
function GetLocale()return "zhCN"end
function GetCVar(name)return Mock.cvars[name]or "mock"end
function SetCVar(name,value)Mock.cvarWrites=Mock.cvarWrites+1;Mock.cvars[name]=tostring(value)end
function IsInInstance()return Mock.instanceType~="none",Mock.instanceType end
function InCombatLockdown()return Mock.inCombat end
function IsKeyDown(key)if key=="UNSUPPORTED"then return nil end;return Mock.keys[key]==true end
function GetCurrentKeyBoardFocus()return Mock.focus end
ChatFrameUtil={GetActiveWindow=function()return nil end}
function print(...)Mock.messages[#Mock.messages+1]=table.concat({...}," ")end
local function play(duration,id,channel)
    channel=channel or "SFX";Mock.soundCalls[#Mock.soundCalls+1]={id=id,channel=channel}
    local enabled=channel~="Master" and (channel=="Music" and "Sound_EnableMusic" or "Sound_EnableSFX") or nil
    local volume=channel~="Master" and (channel=="Music" and "Sound_MusicVolume" or "Sound_SFXVolume") or nil
    if Mock.muteSounds or Mock.cvars.Sound_EnableAllSound=="0" or Mock.cvars[enabled]=="0" or tonumber(Mock.cvars.Sound_MasterVolume)==0 or tonumber(Mock.cvars[volume])==0 then return false,nil end
    Mock.nextSound=Mock.nextSound+1;Mock.sounds[Mock.nextSound]=Mock.time+duration;return true,Mock.nextSound
end
function PlaySound(id,channel)return play(.15,id,channel)end
function PlaySoundFile(id,channel)return play(600,id,channel)end
function StopSound(handle,fadeMs)Mock.sounds[handle]=nil;Mock.lastSoundFade=fadeMs end
C_Sound={IsPlaying=function(handle)return Mock.sounds[handle]~=nil and Mock.sounds[handle]>Mock.time end}
function C_Sound.PlaySoundWithOptions(params)
    if Mock.failSoundKit==params.soundKitID then return false,nil end
    local ok,handle=play(Mock.soundKitDuration or .15,params.soundKitID,params.uiSoundSubType)
    local call=Mock.soundCalls[#Mock.soundCalls];call.volumeOverride=params.volumeOverride;call.forceNoDuplicates=params.forceNoDuplicates
    return ok,handle
end
function UnitIsPlayer()return true end
TRP3_Extended={Events={REFRESH_BAG="REFRESH_BAG",ON_OBJECT_UPDATED="ON_OBJECT_UPDATED",SECURITY_CHANGED="SECURITY_CHANGED"}}
TRP3_API={globals={extended_version=1061,extended_display_version="mock",player_id="测试-测试服"},inventory={},extended={},script={},security={},utils={str={getUnitID=function()return "目标-测试服"end}}}
function TRP3_API.RegisterCallback(registry,name,fn)
    local r={fn=fn,event=name,active=true};Mock.callbacks[#Mock.callbacks+1]=r
    function r:Unregister()self.active=false end;return r
end
function Mock.fireTRP(name)for _,r in ipairs(Mock.callbacks)do if r.active and r.event==name then r.fn(r)end end end
function Mock.fire(name)
    for _,f in ipairs(Mock.frames)do if f.events[name] and f.scripts.OnEvent then f.scripts.OnEvent(f,name)end end
end
function Mock.advance(seconds,step)
    step=step or 1/60
    local target=Mock.time+seconds
    while Mock.time<target-1e-8 do
        local dt=math.min(step,target-Mock.time);Mock.time=Mock.time+dt
        local pending=Mock.timers;Mock.timers={}
        for _,timer in ipairs(pending)do
            if timer.at<=Mock.time+1e-8 then timer.fn()else Mock.timers[#Mock.timers+1]=timer end
        end
        local n=#Mock.frames
        for i=1,n do local f=Mock.frames[i];if f:IsShown() and f.scripts.OnUpdate then f.scripts.OnUpdate(f,dt)end end
    end
end
function Mock.click(label)
    for _,f in ipairs(Mock.frames)do if f.text==label and f.scripts.OnClick and f:IsShown()then f.scripts.OnClick(f);return true end end
    error("button not found: "..label)
end
function TRP3_API.inventory.getInventory()return Mock.inventory end
function TRP3_API.inventory.isInTransaction(item)return item.inTrade==true end
function TRP3_API.inventory.getItemCount(classID)
    local total=0
    local function count(c)for _,o in pairs(c.content or {})do if o.id==classID then total=total+(o.count or 1)end;count(o)end end
    count(Mock.inventory);return total
end
function TRP3_API.extended.getClass(id)return Mock.classes[id]end
function TRP3_API.security.resolveEffectSecurity(id,effect)return not Mock.blockSecurity end
function TRP3_API.script.setVar(args,source,operator,key,value)
    assert(source=="o" and operator=="=");Mock.writes=Mock.writes+1
    if Mock.failWriteKey==key then return end
    args.object.vars=args.object.vars or {};args.object.vars[key]=value
end
function TRP3_API.inventory.addItem(container,classID,data)
    container=container or Mock.inventory;local applied=0
    for i=1,data.count do
        local size=0;for _ in pairs(container.content)do size=size+1 end
        if size>=Mock.capacity then Mock.fireTRP("REFRESH_BAG");return 1,applied end
        local id=1;while container.content[tostring(id)]do id=id+1 end
        local vars={};for k,v in pairs(data.vars or {})do vars[k]=v end
        container.content[tostring(id)]={id=classID,count=1,vars=vars};applied=applied+1
    end
    Mock.fireTRP("REFRESH_BAG");return 0,applied
end
function TRP3_API.inventory.removeItem(classID,amount)
    for key,o in pairs(Mock.inventory.content)do
        if amount>0 and o.id==classID then
            local n=math.min(amount,o.count or 1);amount=amount-n;o.count=(o.count or 1)-n
            if o.count==0 then Mock.inventory.content[key]=nil end
        end
    end
    Mock.fireTRP("REFRESH_BAG")
end
function TRP3_API.inventory.startEmptyExchangeWithUnit(target)Mock.tradeTarget=target end
