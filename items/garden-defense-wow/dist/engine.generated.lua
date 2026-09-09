local G=args._G
if not G then effect("text",args,"GUI host missing; use the item from your bag.",1);return end
local assert,error=G.assert,G.error
local old=G.TRP3_ItemGame
if old and old.bundleId~="bc6340778b4d4735a836325fd2b9e596a68a40701b59e1cb6611bdf00ff60a1a"and old.current then old.current.stop("engine_update")end
local E=old
if not E or E.bundleId~="bc6340778b4d4735a836325fd2b9e596a68a40701b59e1cb6611bdf00ff60a1a"then
E={bundleId="bc6340778b4d4735a836325fd2b9e596a68a40701b59e1cb6611bdf00ff60a1a",packages={["audio"]=true,["effects"]=true,["runtime"]=true,["surface"]=true,["surface-models"]=true,["world"]=true}}
do local install=(function()
return function(E,G)
local error,pcall,setmetatable=G.error,G.pcall,G.setmetatable
local floor,huge=math.floor,math.huge
E.VERSION,E.API_VERSION="0.5.0",1
E.util={}
function E.util.clamp(x,low,high)return math.max(low,math.min(high,x))end
function E.util.copy(value,depth)
if type(value)~="table"then return value end
if E.JSON and value==E.JSON.null then return value end
if(depth or 0)>32 then error("table depth exceeded")end
local out={}
for k,v in pairs(value)do out[k]=E.util.copy(v,(depth or 0)+1)end
return out
end
function E.util.count(t)local n=0;for _ in pairs(t or{})do n=n+1 end;return n end
function E.util.finite(n)return type(n)=="number"and n==n and n~=huge and n~=-huge end
function E.util.call(fn,...)
if type(fn)~="function"then return false,"unsupported"end
return pcall(fn,...)
end
function E.newScope()
local self={closed=false,disposers={}}
function self.add(fn)
if self.closed then pcall(fn);return fn end
self.disposers[#self.disposers+1]=fn;return fn
end
function self.dispose()
if self.closed then return end
self.closed=true
for i=#self.disposers,1,-1 do pcall(self.disposers[i])end
self.disposers={}
end
return self
end
function E.newEvents(onError)
local listeners,queue,closed={},{},false
local self={}
function self.on(name,fn)
local slot={fn=fn,live=true}
listeners[name]=listeners[name]or{}
listeners[name][#listeners[name]+1]=slot
return function()slot.live=false end
end
function self.emit(name,data)
if closed then return end
if#queue>=4096 then error("event queue budget exceeded")end
queue[#queue+1]={name,data}
end
function self.flush()
local current=queue;queue={}
for i=1,#current do
if closed then break end
local slots=listeners[current[i][1]]or{}
local limit=#slots
for j=1,limit do
if closed then break end
if slots[j].live then
local ok,err=pcall(slots[j].fn,current[i][2])
if not ok then onError(err);return end
end
end
end
end
function self.close()closed=true;queue={};listeners={}end
return self
end
local JSON={null={}};E.JSON=JSON
local escapes={['"']='\\"',['\\']='\\\\',['\b']='\\b',['\f']='\\f',['\n']='\\n',['\r']='\\r',['\t']='\\t'}
local function quote(s)
return'"'..s:gsub('[%z\1-\31\\"]',function(c)return escapes[c]or string.format('\\u%04x',string.byte(c))end)..'"'
end
function JSON.encode(value)
local seen,nodes={},0
local function encode(v,depth)
nodes=nodes+1
if depth>32 or nodes>80000 then error("JSON structure budget exceeded")end
if v==JSON.null or v==nil then return"null"end
local kind=type(v)
if kind=="boolean"then return v and"true"or"false"end
if kind=="number"then
if not E.util.finite(v)then error("JSON non-finite number")end
return string.format("%.17g",v)
end
if kind=="string"then return quote(v)end
if kind~="table"or seen[v]then error("JSON unsupported/cyclic value")end
seen[v]=true
local array,count,max=true,0,0
for k in pairs(v)do
count=count+1
if type(k)~="number"or k<1 or k~=floor(k)then array=false else max=math.max(max,k)end
end
array=array and count>0 and max==count
local out={}
if array then
for i=1,count do out[i]=encode(v[i],depth+1)end
else
local keys={}
for k in pairs(v)do if type(k)~="string"then error("JSON object keys must be strings")end;keys[#keys+1]=k end
table.sort(keys)
for i=1,#keys do out[i]=quote(keys[i])..":"..encode(v[keys[i]],depth+1)end
end
seen[v]=nil
return(array and"["or"{")..table.concat(out,",")..(array and"]"or"}")
end
return encode(value,0)
end
local function utf8(n)
if n<128 then return string.char(n)end
if n<2048 then return string.char(192+floor(n/64),128+n%64)end
if n<65536 then return string.char(224+floor(n/4096),128+floor(n/64)%64,128+n%64)end
return string.char(240+floor(n/262144),128+floor(n/4096)%64,128+floor(n/64)%64,128+n%64)
end
function JSON.decode(text,maxBytes)
if type(text)~="string"or#text>(maxBytes or 524288)then error("JSON input budget exceeded")end
local pos,nodes=1,0
local function skip()local _,finish=text:find("^[ \t\r\n]*",pos);pos=(finish or pos-1)+1 end
local function stringValue()
pos=pos+1;local out={}
while pos<=#text do
local c=text:sub(pos,pos);pos=pos+1
if c=='"'then return table.concat(out)end
if c=="\\"then
local e=text:sub(pos,pos);pos=pos+1
local map={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
if map[e]then out[#out+1]=map[e]
elseif e=="u"then
local hex=text:sub(pos,pos+3)
if not hex:match("^%x%x%x%x$")then error("bad unicode escape")end
local n=tonumber(hex,16);pos=pos+4
if n>=55296 and n<=56319 then
local low=text:sub(pos+2,pos+5)
if text:sub(pos,pos+1)~="\\u"or not low:match("^%x%x%x%x$")then error("bad surrogate")end
local m=tonumber(low,16)
if m<56320 or m>57343 then error("bad surrogate")end
pos=pos+6;n=65536+(n-55296)*1024+m-56320
elseif n>=56320 and n<=57343 then error("unpaired surrogate")end
out[#out+1]=utf8(n)
else error("bad string escape")end
else
if string.byte(c)<32 then error("control byte in JSON string")end
out[#out+1]=c
end
end
error("unterminated string")
end
local parse
parse=function(depth)
nodes=nodes+1
if depth>32 or nodes>80000 then error("JSON structure budget exceeded")end
skip();local c=text:sub(pos,pos)
if c=='"'then return stringValue()end
if c=="{"or c=="["then
local object,result,index=c=="{",{},1
local close=object and"}"or"]";pos=pos+1;skip()
if text:sub(pos,pos)==close then pos=pos+1;return result end
while true do
local key=index
if object then
skip();if text:sub(pos,pos)~='"'then error("object key expected")end
key=stringValue();skip()
if result[key]~=nil then error("duplicate JSON key")end
if text:sub(pos,pos)~=":"then error("colon expected")end;pos=pos+1
end
result[key]=parse(depth+1);index=index+1;skip()
c=text:sub(pos,pos);pos=pos+1
if c==close then return result end
if c~=","then error("separator expected")end
end
end
for _,pair in ipairs({{"true",true},{"false",false},{"null",JSON.null}})do
if text:sub(pos,pos+#pair[1]-1)==pair[1]then pos=pos+#pair[1];return pair[2]end
end
local start=pos
if c=="-"then pos=pos+1 end
local first=text:sub(pos,pos)
if not first:match("%d")then error("value expected at "..tostring(pos))end
if first=="0"then pos=pos+1 else while text:sub(pos,pos):match("%d")do pos=pos+1 end end
if text:sub(pos,pos)=="."then
pos=pos+1
if not text:sub(pos,pos):match("%d")then error("fraction expected")end
while text:sub(pos,pos):match("%d")do pos=pos+1 end
end
if text:sub(pos,pos):match("[eE]")then
pos=pos+1
if text:sub(pos,pos):match("[+-]")then pos=pos+1 end
if not text:sub(pos,pos):match("%d")then error("exponent expected")end
while text:sub(pos,pos):match("%d")do pos=pos+1 end
end
local n=tonumber(text:sub(start,pos-1))
if not E.util.finite(n)then error("invalid JSON number")end
return n
end
local result=parse(0);skip()
if pos<=#text then error("trailing JSON data")end
return result
end
end
end)();install(E,G)end
do local install=(function()
return function(E,G)
local floor,ceil=math.floor,math.ceil
local function meter(quantum)
local self={n=0,sum=0,max=0,bins={},quantum=quantum}
function self.add(value)
if not E.util.finite(value)or value<0 then return end
self.n=self.n+1;self.sum=self.sum+value;self.max=math.max(self.max,value)
local bucket=ceil(value/quantum)
self.bins[bucket]=(self.bins[bucket]or 0)+1
end
function self.summary()
if self.n==0 then return{count=0,available=false}end
local keys={};for k in pairs(self.bins)do keys[#keys+1]=k end;table.sort(keys)
local function q(f)
local target,seen=ceil(self.n*f),0
for _,k in ipairs(keys)do seen=seen+self.bins[k];if seen>=target then return k*quantum end end
end
return{count=self.n,mean=self.sum/self.n,max=self.max,p50=q(.5),p95=q(.95),p99=q(.99),quantileResolutionMs=quantum}
end
return self
end
E.newMeter=meter
function E.newTelemetry(host,metadata,options)
options=options or{}
local self={phase=nil,completed=0,records={},dropped=0,droppedSummaries=0,nextPhase=0,frameCount=0,counters={}}
local started,sampleAt=host.now(),host.now()
metadata=E.util.copy(metadata)
metadata.hostKind=host.kind;metadata.schema="trp3-item-perf/1"
metadata.clock=host.profileClock;metadata.startedAt=host.date()
local header={type="run.start",t=0,data=metadata}
function self.note(kind,data)
local record={type=kind,t=host.now()-started,data=data or{}}
self.records[#self.records+1]=record
if#self.records>480 then
if self.records[1].type=="phase.end"then self.droppedSummaries=self.droppedSummaries+1 end
table.remove(self.records,1);self.dropped=self.dropped+1
end
end
function self.increment(name,amount)self.counters[name]=(self.counters[name]or 0)+(amount or 1)end
function self.finish(status,resources)
local p=self.phase
if not p then return end
resources=resources or{}
if status=="complete"and(p.metadata.expectedModels or 0)>(resources.loadedModels or 0)then status="models_not_verified"end
if status=="complete"and p.metadata.kind=="music"and resources.musicBackend=="silent"then status="music_not_started"end
local summaries={};for name,m in pairs(p.meters)do summaries[name]=m.summary()end
local summary={
id=p.id,name=p.name,status=status or"complete",metadata=p.metadata,
measuredSeconds=p.measureStart and host.now()-p.measureStart or 0,
frames=p.frames,framesOver33Ms=p.longFrames,metrics=summaries,
counters=E.util.copy(self.counters),resources=resources or{},
}
self.lastPhase=summary;self.note("phase.end",summary)
self.phase=nil;self.completed=self.completed+1
end
function self.begin(name,phaseMetadata,options)
if self.phase then self.finish("interrupted")end
options=options or{};self.nextPhase=self.nextPhase+1;self.counters={}
local now=host.now()
self.phase={
id=self.nextPhase,name=name,metadata=E.util.copy(phaseMetadata or{}),
start=now,warmUntil=now+(options.warmup or 2),duration=options.duration or 10,
measuring=false,frames=0,longFrames=0,meters={},
}
sampleAt=now
self.note("phase.start",{id=self.nextPhase,name=name,warmup=options.warmup or 2,duration=options.duration or 10,metadata=phaseMetadata or{}})
end
function self.beforeFrame()
local p=self.phase
if p and not p.measuring and host.now()>=p.warmUntil then
p.measuring=true;p.measureStart=host.now();sampleAt=host.now();self.counters={}
end
end
function self.record(name,milliseconds)
local p=self.phase
if not p or not p.measuring then return end
p.meters[name]=p.meters[name]or meter(name=="frameMs"and.1 or.01)
p.meters[name].add(milliseconds)
end
function self.snapshot()
local p=self.phase
if not p then return{active=false,hostKind=host.kind,hostFPS=host.fps(),last=self.lastPhase and E.util.copy(self.lastPhase)}end
local metrics={};for name,m in pairs(p.meters)do metrics[name]=m.summary()end
return{active=true,hostKind=host.kind,hostFPS=host.fps(),name=p.name,measuring=p.measuring,
seconds=p.measureStart and host.now()-p.measureStart or 0,duration=p.duration,frames=p.frames,metrics=metrics}
end
function self.afterFrame(elapsed,luaMs,stats)
self.frameCount=self.frameCount+1
local p=self.phase
if not p or not p.measuring then return end
p.frames=p.frames+1
if elapsed>1/30 then p.longFrames=p.longFrames+1 end
self.record("frameMs",elapsed*1000);self.record("luaFrameMs",luaMs)
local now=host.now()
if now-sampleAt>=1 then
sampleAt=now
self.note("sample",{phaseId=p.id,seconds=now-p.measureStart,frames=p.frames,
frameMs=p.meters.frameMs.summary(),luaFrameMs=p.meters.luaFrameMs.summary(),
resources=stats(),counters=E.util.copy(self.counters),memoryKB=host.memoryKB(),hostFPS=host.fps()})
end
if now-p.measureStart>=p.duration then self.finish("complete",stats())end
end
function self.export(maxBytes)
local limit=math.min(maxBytes or 190000,options.maxBytes or 190000)
local lines={E.JSON.encode(header)}
local selected,encoded,count,bytes,summariesDropped={},{},0,#lines[1]+1,self.droppedSummaries
for i=1,#self.records do encoded[i]=E.JSON.encode(self.records[i])end
for pass=1,2 do
for i=#self.records,1,-1 do
local sample=self.records[i].type=="sample"
if(pass==1 and not sample)or(pass==2 and sample)then
if bytes+#encoded[i]+1<=limit-220 then selected[i]=true;count=count+1;bytes=bytes+#encoded[i]+1
elseif self.records[i].type=="phase.end"then summariesDropped=summariesDropped+1 end
end
end
end
local omitted=self.dropped+#self.records-count
lines[#lines+1]=E.JSON.encode({type="log.status",t=host.now()-started,data={droppedRecords=omitted,droppedSummaries=summariesDropped,phaseActive=self.phase~=nil}})
for i=1,#self.records do if selected[i]then lines[#lines+1]=encoded[i]end end
return table.concat(lines,"\n").."\n"
end
function self.close(reason,stats)
self.finish(reason=="complete"and"complete"or"stopped",stats and stats()or nil)
self.note("run.end",{reason=reason,frames=self.frameCount,seconds=host.now()-started})
end
return self
end
end
end)();install(E,G)end
do local install=(function()
return function(E,G)
local pcall,error=G.pcall,G.error
function E.newWoWHost(args,manifest)
local API=G.TRP3_API
if not API or not API.inventory or not G.CreateFrame then error("WoW/TRP3 host unavailable")end
local item=args.object
if type(item)~="table"or item.id~=manifest.rootId then error("A main-item instance is required")end
local host={kind="wow",G=G,item=item,rootId=manifest.rootId,objectVersion=manifest.objectVersion}
local initialClass=API.extended.getClass(host.rootId)
host.definitionVersion=initialClass and initialClass.MD and initialClass.MD.V
local function fingerprint(class)
return class and class.IN and class.IN.ig_manifest and class.IN.ig_manifest.PA and class.IN.ig_manifest.PA[1]and class.IN.ig_manifest.PA[1].TX
end
host.definitionFingerprint=fingerprint(initialClass)
host.bootstrapStartedMS=args._igLaunchMS
host.now=function()return G.GetTime()end
host.profileMS=G.debugprofilestop or function()return G.GetTime()*1000 end
host.profileClock=G.debugprofilestop and"debugprofilestop/ms"or"GetTime/ms-coarse"
host.date=function()return G.date("%Y-%m-%dT%H:%M:%S")end
host.fps=function()return G.GetFramerate and G.GetFramerate()or nil end
host.memoryKB=function()
if G.gcinfo then local ok,n=pcall(G.gcinfo);if ok and type(n)=="number"then return n end end
return nil
end
function host.inventoryRoot()return API.inventory.getInventory and API.inventory.getInventory()end
function host.findItem(predicate)
local seen,visited={},0
local function find(container,depth)
if type(container)~="table"or seen[container]or depth>32 then return end
seen[container]=true
for slot,object in pairs(container.content or{})do
visited=visited+1;if visited>20000 then return end
if predicate(object,container,slot)then return object,container,slot end
local a,b,c=find(object,depth+1);if a then return a,b,c end
end
end
return find(host.inventoryRoot(),0)
end
function host.owned()
if item.id~=manifest.rootId then return false,"item_missing"end
local found,parent=host.findItem(function(o)return o==item end)
if not found then return false,"item_missing"end
if API.inventory.isInTransaction and API.inventory.isInTransaction(item)then return false,"item_in_trade"end
return true,parent
end
function host.read(key)return item.vars and item.vars[key]end
function host.write(key,value)
local allowed,reason=host.owned();if not allowed then return false,reason end
if type(value)=="string"and#value>220000 then return false,"store_size_limit"end
if not API.script or not API.script.setVar then return false,"store_unavailable"end
local written,why=pcall(API.script.setVar,{object=item},"o","=",key,value)
if not written then return false,tostring(why)end
if host.read(key)==value then return true end
return false,"write_verification_failed"
end
function host.environment()
if not G.IsInInstance or not G.InCombatLockdown then return{allowed=false,reason="environment_unavailable"}end
local inside,kind=G.IsInInstance()
local combat=G.InCombatLockdown()==true
local blocked={party=true,raid=true,scenario=true,pvp=true,arena=true}
local known=not inside or kind=="none"or kind=="neighborhood"or kind=="interior"or blocked[kind]
return{inInstance=inside,instanceType=kind,inCombat=combat,
allowed=known and not combat and not blocked[kind],
reason=combat and"wow_combat"or(blocked[kind]and"wow_instance"or(not known and"unknown_instance"or nil))}
end
function host.definitionChanged()
local c=API.extended.getClass(host.rootId)
return not c or not c.MD or c.MD.V~=host.definitionVersion or fingerprint(c)~=host.definitionFingerprint
end
function host.metadata()
local version,build,date,toc=G.GetBuildInfo()
local result={clientVersion=version,clientBuild=build,interface=toc,clientDate=date,
objectRevision=host.definitionVersion,
extendedBuild=API.globals and API.globals.extended_version,locale=G.GetLocale and G.GetLocale(),
memoryScope="shared_client_lua_heap_not_gpu_or_engine_attribution",environment=host.environment()}
if G.GetCVar then
result.graphics={}
for _,k in ipairs({"gxWindow","gxResolution","gxVSync","maxFPS","graphicsQuality","Sound_EnableAllSound","Sound_EnableSFX","Sound_EnableMusic","Sound_MasterVolume","Sound_SFXVolume","Sound_MusicVolume","Sound_NumChannels"})do
local ok,v=pcall(G.GetCVar,k);if ok then result.graphics[k]=v end
end
end
return result
end
function host.watch(scope,callback)
E.eventFrame=E.eventFrame or G.CreateFrame("Frame")
local f=E.eventFrame
f:SetScript("OnEvent",function(_,name)callback(name)end)
for _,name in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_LEAVING_WORLD","PLAYER_LOGOUT","PLAYER_REGEN_DISABLED","ZONE_CHANGED_NEW_AREA"})do pcall(f.RegisterEvent,f,name)end
scope.add(function()f:UnregisterAllEvents();f:SetScript("OnEvent",nil)end)
if G.TRP3_Extended and API.RegisterCallback then
for _,name in ipairs({"REFRESH_BAG","ON_OBJECT_UPDATED","SECURITY_CHANGED"})do
if G.TRP3_Extended.Events[name]then
local ok,registration=pcall(API.RegisterCallback,G.TRP3_Extended,name,function()callback(name)end)
if ok and registration then scope.add(function()registration:Unregister()end)end
end
end
end
end
function host.allowedEffects()
if not API.security or not API.security.resolveEffectSecurity then return false end
return API.security.resolveEffectSecurity(host.rootId,"script")and API.security.resolveEffectSecurity(host.rootId,"secure_macro")
end
function host.keyDown(key)
if not G.IsKeyDown then return nil end
local ok,value=pcall(G.IsKeyDown,key)
if ok then return value end
return nil
end
function host.textFocused()
if G.GetCurrentKeyBoardFocus then
local ok,f=pcall(G.GetCurrentKeyBoardFocus);if ok and f then return true end
end
if G.GetCurrentKeyboardFocus then
local ok,f=pcall(G.GetCurrentKeyboardFocus);if ok and f then return true end
end
if G.ChatFrameUtil and G.ChatFrameUtil.GetActiveWindow then return G.ChatFrameUtil.GetActiveWindow()~=nil end
return false
end
function host.audioStatus(channel)
local result={channel=channel or"SFX",cvars={}}
local channels={
SFX={"Sound_EnableSFX","Sound_SFXVolume"},
Music={"Sound_EnableMusic","Sound_MusicVolume"},
Ambience={"Sound_EnableAmbience","Sound_AmbienceVolume"},
Dialog={"Sound_EnableDialog","Sound_DialogVolume"},
Master={},
}
local keys=channels[result.channel]
if not keys then result.reason="invalid_sound_channel";return result end
local function read(key)
if not key or not G.GetCVar then return nil end
local ok,value=pcall(G.GetCVar,key)
if ok and(type(value)=="string"or type(value)=="number")then result.cvars[key]=value;return value end
end
local all,volume,enabled,channelVolume=read("Sound_EnableAllSound"),read("Sound_MasterVolume"),read(keys[1]),read(keys[2])
if tonumber(all)==0 then result.reason="all_sound_disabled"
elseif tonumber(volume)==0 then result.reason="master_volume_zero"
elseif tonumber(enabled)==0 then result.reason="channel_disabled"
elseif tonumber(channelVolume)==0 then result.reason="channel_volume_zero"end
return result
end
function host.soundVolumeSupported(def)
return G.C_Sound~=nil and type(G.C_Sound.PlaySoundWithOptions)=="function"and
(def==nil or def.kind=="soundKitID"or def.volumeSoundKitID~=nil)
end
function host.playSound(def,volume)
local status=host.audioStatus(def.channel)
if status.reason then return nil,status.reason,status end
if volume~=nil and(not E.util.finite(volume)or volume<0 or volume>1)then return nil,"invalid_sound_volume",status end
if volume==0 then return nil,"volume_zero",status end
local volumePath=volume~=nil and(volume~=1 or def.baseVolume~=nil or def.volumeSoundKitID~=nil)
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
local fn=def.kind=="soundKitID"and G.PlaySound or G.PlaySoundFile
if not fn or type(def.id)~="number"then return nil,"sound_unavailable",status end
local ok,playing,handle=pcall(fn,def.id,status.channel)
if not ok then return nil,"sound_api_error",status end
if not playing or not handle then return nil,"sound_not_started",status end
return handle,nil,status
end
function host.stopSound(handle,fadeMs)if handle and G.StopSound then pcall(G.StopSound,handle,fadeMs or 0)end end
function host.soundPlaying(handle)
if G.C_Sound and G.C_Sound.IsPlaying then
local ok,active=pcall(G.C_Sound.IsPlaying,handle);if ok then return active end
end
return nil
end
function host.itemCount(classID)
return API.inventory.getItemCount and API.inventory.getItemCount(classID)or nil
end
function host.mutateInventory(operation,classID,amount,attributes)
local owned,reason=host.owned();if not owned then return{status="failed",applied=0,reason=reason}end
local found=host.findItem(function(o)return o.id==classID and API.inventory.isInTransaction and API.inventory.isInTransaction(o)end)
if found then return{status="failed",applied=0,reason="item_in_trade"}end
local before=host.itemCount(classID)
if before==nil then return{status="failed",applied=0,reason="inventory_unavailable"}end
if operation=="consume"and before<amount then return{status="failed",applied=0,reason="insufficient_items"}end
local ok,err
if operation=="grant"then
local data={count=amount}
if attributes then data.vars={IG_EQUIP_V1=E.JSON.encode(attributes)}end
ok,err=pcall(API.inventory.addItem,nil,classID,data,false)
else ok,err=pcall(API.inventory.removeItem,classID,amount)end
local after=host.itemCount(classID)
if not ok or after==nil then return{status="unknown",reason=tostring(err),requested=amount}end
local delta=operation=="grant"and after-before or before-after
if delta<0 or delta>amount then return{status="unknown",reason="unexpected_inventory_delta",requested=amount}end
return{status=delta==amount and"complete"or(delta==0 and"failed"or"partial"),requested=amount,applied=delta}
end
function host.openTrade(target)
if not target or target==""or not API.inventory.startEmptyExchangeWithUnit then return false,"select_a_player_target"end
if G.TRP3_ExchangeFrame and G.TRP3_ExchangeFrame:IsShown()then return false,"trade_already_open"end
local ok,err=pcall(API.inventory.startEmptyExchangeWithUnit,target);return ok,err
end
function host.targetPlayer()
if G.UnitIsPlayer and not G.UnitIsPlayer("target")then return nil end
if API.utils and API.utils.str and API.utils.str.getUnitID then return API.utils.str.getUnitID("target")end
return nil
end
return host
end
end
end)();install(E,G)end
do local install=(function()
return function(E,G)
local pcall,error=G.pcall,G.error
local function call(object,method,...)
if object and object[method]then return pcall(object[method],object,...)end
return false
end
local function resourceKey(def)return def.kind..":"..def.id..":"..(def.displayIndex or 1)end
function E.newSurfaceActors(session,root,cache,layer)
cache.actorScenes=cache.actorScenes or{}
cache.actorResources=cache.actorResources or{}
local groups,resources=cache.actorScenes,cache.actorResources
local generation,queue,queued=0,{},{}
local width,height=session.content.viewport.width,session.content.viewport.height
local unitsPerPixel,fov=.01,.55
local cameraDistance=height*unitsPerPixel/(2*math.tan(fov/2))
local limit=(session.content.limits or{}).maxSurfaceModels or 104
local self={}
local function group(z)
if session.host.now()<(self.nextSceneAttempt or 0)then return nil end
if not groups[z]then
local ok,f=pcall(G.CreateFrame,"ModelScene",nil,layer(z))
if not ok then
self.nextSceneAttempt=session.host.now()+1
if not self.unavailable then session.perf.note("surface.scene_unavailable",{reason=tostring(f)})end
self.unavailable=true
return nil
end
self.unavailable=false
f:SetAllPoints(root);f:EnableMouse(false)
call(f,"SetFixedFrameLevel",true);f:SetFrameLevel(layer(z):GetFrameLevel()+1)
f:SetCameraOrientationByYawPitchRoll(0,0,0)
f:SetCameraFieldOfView(fov)
f:SetCameraPosition(-cameraDistance,0,0)
call(f,"SetCameraNearClip",.01);call(f,"SetCameraFarClip",1000)
call(f,"ClearFog");call(f,"SetAllowOverlappedModels",true)
call(f,"SetLightVisible",true);call(f,"SetLightAmbientColor",.75,.75,.75)
call(f,"SetLightDiffuseColor",.25,.25,.25);call(f,"SetLightDirection",-1,-1,-1)
groups[z]={frame=f,actors={},z=z}
end
local g=groups[z];g.frame:Show();call(g.frame,"SetPaused",false,false)
return g
end
local function resource(def)
local key=resourceKey(def)
local r=resources[key]
if not r then r={key=key};resources[key]=r end
if not r.id and session.host.now()>=(r.nextResolve or 0)then
r.kind,r.id=E.resolveModel(def);r.nextResolve=session.host.now()+.1
end
return r
end
local function release(a,clear)
if a.owner then a.owner.actorLease=nil;a.owner.model=nil;a.owner.loaded=false;a.owner.fitReady=false end
a.owner=nil;a.actor:Hide();a.visible=false
if clear then
call(a.actor,"ClearModel");a.key=nil;a.requested=false;a.ready=false;a.notified=nil
a.nextLoadAttempt=nil
a.measureAfter=nil
a.anim=nil;a.animOffset=nil;a.animSpeed=nil
end
end
local function take(g,node,key)
if not node then
for _,a in ipairs(g.actors)do if a.key==key and a.ready then return a end end
end
if node and node.actorLease and node.actorLease.key==key then return node.actorLease end
if node and node.actorLease then release(node.actorLease,false)end
local chosen
for _,a in ipairs(g.actors)do
if not a.owner and a.key==key then chosen=a;break end
end
if not chosen then
for _,a in ipairs(g.actors)do if not a.owner and not a.key then chosen=a;break end end
end
if not chosen and(cache.modelCount or 0)<limit then
cache.modelCount=(cache.modelCount or 0)+1
chosen={actor=g.frame:CreateActor("IGSharedActor"..cache.modelCount)}
call(chosen.actor,"SetUseCenterForOrigin",false,false,false)
g.actors[#g.actors+1]=chosen
end
if not chosen then
for _,a in ipairs(g.actors)do
if not a.owner and(not chosen or(a.usedAt or 0)<(chosen.usedAt or 0))then chosen=a end
end
end
if not chosen then return nil end
if chosen.key~=key then release(chosen,true);chosen.key=key;chosen.started=session.host.now()end
chosen.owner=node;chosen.usedAt=session.host.now()
if node then node.actorLease=chosen;node.model=chosen.actor;node.scene=g.frame;node.sharedScene=true end
return chosen
end
local function load(a,r)
if a.ready then return true end
local actor=a.actor
actor:Show();call(actor,"SetAlpha",.01);call(actor,"SetScale",1)
call(actor,"SetPosition",0,0,0)
if r.id and not a.requested and session.host.now()>=(a.nextLoadAttempt or 0)then
a.requested=true;a.nextLoadAttempt=session.host.now()+.25
local ok,accepted=call(actor,r.kind=="creatureDisplayID"and"SetModelByCreatureDisplayID"or"SetModelByFileID",r.id)
if not ok or accepted==false then a.requested=false end
end
if not a.requested then return false end
local ok,loaded=call(actor,"IsLoaded")
if not ok then local valid,id=call(actor,"GetModelFileID");loaded=valid and type(id)=="number"and id>0 end
if not loaded then return false end
if not r.bounds then
if not a.measureAfter then
call(actor,"SetScale",1);call(actor,"SetYaw",0);call(actor,"SetPosition",0,0,0)
call(actor,"SetPitch",0);call(actor,"SetRoll",0)
call(actor,"SetUseCenterForOrigin",false,false,false);call(actor,"SetAnimation",0,0,0,0)
a.measureAfter=session.host.now()
return false
end
if session.host.now()<=a.measureAfter then return false end
local bottom,top=E.readModelBounds(actor,"GetActiveBoundingBox")
local fit=E.fitModelBounds(bottom,top,1,0,.82)
local source="idle"
if not fit and session.host.now()-a.measureAfter>=.5 then
bottom,top=E.readModelBounds(actor,"GetMaxBoundingBox")
fit=E.fitModelBounds(bottom,top,1,0,.82);source="maximum"
end
if fit then r.bounds={fit.bottom,fit.top};r.boundsSource=source end
end
a.ready=r.bounds~=nil
if a.ready then
session.perf.note("surface.model_ready",{resource=r.key,seconds=session.host.now()-(a.started or session.host.now())})
end
return a.ready
end
local function animate(a)
local spec,def=a.spec,a.def
local animation=spec.animation or def.animation or 0
if spec.animationTime~=nil then
local offset=spec.animationTime
if not session.paused and not spec.paused then offset=offset+math.max(0,session.time-a.sampleAt)*(spec.animationRate or 1)end
offset=math.min(spec.animationEnd or 100000,offset)
if a.anim~=animation or a.animOffset~=offset then
call(a.actor,"SetAnimation",animation,0,0,offset);a.anim=animation;a.animOffset=offset
end
else
local speed=(session.paused or spec.paused)and 0 or session.speed
if a.anim~=animation or a.animSpeed~=speed or a.animOffset then
call(a.actor,"SetAnimation",animation,0,speed,0);a.anim=animation;a.animSpeed=speed;a.animOffset=nil
end
end
end
local function projectionPlane(g,x)
local ok,u,v=call(g.frame,"Project3DPointTo2D",x,0,0)
local yOK,yu,yv=call(g.frame,"Project3DPointTo2D",x,1,0)
local zOK,zu,zv=call(g.frame,"Project3DPointTo2D",x,0,1)
local scaleOK,uiScale=call(g.frame,"GetEffectiveScale")
if not(ok and yOK and zOK and scaleOK)then return nil end
for _,value in ipairs({u,v,yu,yv,zu,zv,uiScale})do if not E.util.finite(value)then return nil end end
if not u or not v or not yu or not yv or not zu or not zv or not uiScale or uiScale<=0 then return nil end
local a,b,c,d=yu-u,zu-u,yv-v,zv-v
local determinant=a*d-b*c
if math.abs(determinant)<.000001 then return nil end
return{x=x,u=u,v=v,a=a,b=b,c=c,d=d,det=determinant,uiScale=uiScale,
pixelWidth=uiScale/math.sqrt(a*a+c*c),pixelHeight=uiScale/math.sqrt(b*b+d*d)}
end
local function pointOnPlane(p,x,y)
local du,dv=x*p.uiScale-p.u,(height-y)*p.uiScale-p.v
return(du*p.d-dv*p.b)/p.det,(p.a*dv-p.c*du)/p.det
end
local function actorSize(a,p)
local s,fit=a.spec,a.fit
return math.min((s.w or 1)*p.pixelWidth/fit.width,(s.h or 1)*p.pixelHeight/fit.height)*a.fill*a.sizeScale
end
local function projectedSize(a,g,x,y,z,scale)
local b,t=a.resource.bounds[1],a.resource.bounds[2]
local pivot=a.pivot
local c,s=math.cos(a.yaw),math.sin(a.yaw)
local left,right,bottom,top
for _,px in ipairs({b.x,t.x})do for _,py in ipairs({b.y,t.y})do for _,pz in ipairs({b.z,t.z})do
local dx,dy=px-pivot.x,py-pivot.y
local ok,u,v=call(g.frame,"Project3DPointTo2D",x+(dx*c-dy*s)*scale,
y+(dx*s+dy*c)*scale,z+(pz-pivot.z)*scale)
if not ok or not E.util.finite(u)or not E.util.finite(v)then return nil end
left=left and math.min(left,u)or u;right=right and math.max(right,u)or u
bottom=bottom and math.min(bottom,v)or v;top=top and math.max(top,v)or v
end end end
return right-left,top-bottom
end
local function facing(a,p)
local direction=a.spec.screenFacing or a.def.screenFacing
if direction then
local side=direction=="right"and 1 or-1
return side*(p.a>0 and 1 or-1)*math.pi/2-(a.def.forwardYaw or 0)
end
return a.spec.facing or a.def.facing or 0
end
local function pendingProjection(g,visible)
for _,a in ipairs(visible)do a.actor:Hide();a.visible=false;a.owner.fitReady=false end
g.dirty=true
if not g.projectionNotice then
session.perf.note("surface.projection_pending",{layer=g.z});g.projectionNotice=true
end
end
local function layout(g)
local visible={}
for _,a in ipairs(g.actors)do
if a.owner and a.generation==generation and a.ready then visible[#visible+1]=a end
end
table.sort(visible,function(a,b)
if a.owner.depth==b.owner.depth then return a.owner.order>b.owner.order end
return a.owner.depth>b.owner.depth
end)
if#visible==0 then g.dirty=false;return end
local headingPlane=projectionPlane(g,0)
if not headingPlane then pendingProjection(g,visible);return end
local cursor,index,retry=0,1,false
while index<=#visible do
local last=index
while last<=#visible and visible[last].owner.depth==visible[index].owner.depth do
local a=visible[last];local s,def=a.spec,a.def
a.yaw=facing(a,headingPlane)
a.fit=E.fitModelBounds(a.resource.bounds[1],a.resource.bounds[2],(s.w or 1)/(s.h or 1),a.yaw,def.fitFill or.82)
local b,t=a.resource.bounds[1],a.resource.bounds[2]
a.pivot=s.modelAnchor or def.modelAnchor or{x=(b.x+t.x)/2,y=(b.y+t.y)/2,z=b.z}
a.sizeScale=s.scale or def.scale or 1;a.fill=s.fitFill or def.fitFill or.82
if not E.util.finite(a.sizeScale)or a.sizeScale<=0 or
not E.util.finite(a.fill)or a.fill<=0 or a.fill>1 then error("invalid surface model size")end
for _,key in ipairs({"x","y","z"})do
if not E.util.finite(a.pivot[key])then error("invalid surface model anchor")end
end
local c,sine=math.cos(a.yaw),math.sin(a.yaw)
local centerOffset=((b.x+t.x)/2-a.pivot.x)*c-((b.y+t.y)/2-a.pivot.y)*sine
a.depthExtent=a.fit and a.fit.depth+2*math.abs(centerOffset)or 0
last=last+1
end
local center,plane,depth=cursor,nil,0
for _=1,5 do
plane=projectionPlane(g,center)
if not plane then
pendingProjection(g,visible)
return
end
depth=0
for i=index,last-1 do
local a=visible[i]
if a.fit then depth=math.max(depth,a.depthExtent*actorSize(a,plane))end
end
local nextCenter=cursor+depth/2
if math.abs(nextCenter-center)<.00001 then break end
center=nextCenter
end
center=plane.x
cursor=center+depth/2+.02
for i=index,last-1 do
local a=visible[i];local n,s,def,fit=a.owner,a.spec,a.def,a.fit
if fit then
local scale=actorSize(a,plane)
local anchorX=s.anchorX or(s.x or 0)+(s.w or 1)/2
local anchorY=s.anchorY or(s.y or 0)+(s.h or 1)*.9
if not E.util.finite(anchorX)or not E.util.finite(anchorY)then error("invalid surface screen anchor")end
local worldY,worldZ=pointOnPlane(plane,anchorX,anchorY)
local projectionReady=false
for _=1,6 do
local projectedW,projectedH=projectedSize(a,g,center,worldY,worldZ,scale)
if not projectedW or not projectedH or projectedW<=0 or projectedH<=0 then break end
local ratio=math.min((s.w or 1)*plane.uiScale*a.fill*a.sizeScale/projectedW,
(s.h or 1)*plane.uiScale*a.fill*a.sizeScale/projectedH)
if ratio>=1 and ratio<=1.005 then projectionReady=true;break end
scale=scale*ratio*.998
end
if projectionReady then
local c,sine=math.cos(a.yaw),math.sin(a.yaw)
local pivot=a.pivot
local scaleOK=call(a.actor,"SetScale",scale)
local yawOK=call(a.actor,"SetYaw",a.yaw)
local positionOK=call(a.actor,"SetPosition",center/scale-(pivot.x*c-pivot.y*sine),
worldY/scale-(pivot.x*sine+pivot.y*c),worldZ/scale-pivot.z)
projectionReady=scaleOK and yawOK and positionOK
end
if projectionReady then
call(a.actor,"SetAlpha",1);a.actor:Show();a.visible=true
n.loaded=true;n.fitReady=true;n.bounds=a.resource.bounds;n.framing=fit
n.sceneDepth={near=center-depth/2,far=center+depth/2}
n.projectedAnchor={x=anchorX,y=anchorY};n.modelAnchor=pivot
n.boundsSource=a.resource.boundsSource
animate(a)
else
pendingProjection(g,{a});retry=true
end
end
end
index=last
end
call(g.frame,"SetCameraFarClip",cameraDistance+cursor+10)
g.dirty=retry
end
function self.begin()generation=generation+1 end
function self.draw(node,spec,def)
if not def then error("unknown surface model: "..tostring(spec.asset))end
for _,key in ipairs({"w","h"})do
if not E.util.finite(spec[key]or 1)or(spec[key]or 1)<=0 then error("invalid surface model dimensions")end
end
node.sharedScene=true
node.fallback:Hide()
local g=group(node.z);if not g then return end
local r=resource(def);local a=take(g,node,r.key)
if not a then return end
a.spec=spec;a.def=def;a.resource=r;a.generation=generation;a.sampleAt=session.time
g.dirty=true
node.asset=spec.asset;node.loaded=a.ready or false
load(a,r)
end
function self.preload(asset,z)
local def=(session.content.assets.models or{})[asset]
if not def or queued[resourceKey(def)]or#queue>=32 then return false end
queued[resourceKey(def)]=true;queue[#queue+1]={asset=asset,def=def,z=z or 4};return true
end
function self.finish()
for _,g in pairs(groups)do
for _,a in ipairs(g.actors)do if a.owner and a.generation~=generation then release(a,false)end end
layout(g)
end
end
function self.update()
local now=session.host.now()
for _,g in pairs(groups)do
local _,effectiveScale=call(g.frame,"GetEffectiveScale")
local signature=tostring(effectiveScale)..":"..g.frame:GetWidth()..":"..g.frame:GetHeight()
if g.viewportSignature~=signature then g.viewportSignature=signature;g.dirty=true end
for _,a in ipairs(g.actors)do
if a.owner then
if not a.ready then
local wasReady=a.ready
load(a,resource(a.def))
if a.ready~=wasReady then g.dirty=true end
if not a.ready and now-(a.started or now)>8 and not a.notified then
a.notified=true;session.perf.note("surface.model_unavailable",{resource=a.key})
end
end
if a.ready then animate(a)end
elseif a.key and now-(a.usedAt or 0)>120 then release(a,true)end
end
if g.dirty then layout(g)end
local level=layer(g.z):GetFrameLevel()+1
if g.frame:GetFrameLevel()~=level then g.frame:SetFrameLevel(level)end
end
local count=0
for i=#queue,1,-1 do
if count>=4 then break end
local request=queue[i];local r=resource(request.def);local g=group(request.z)
if not g then break end
local a=take(g,nil,r.key)
if a then
count=count+1
if load(a,r)or now-(a.started or now)>8 then
if not a.owner then a.actor:Hide()end
table.remove(queue,i)
end
end
end
end
function self.dispose()
for _,g in pairs(groups)do
for _,a in ipairs(g.actors)do release(a,true);a.notified=nil end
g.frame:Hide();call(g.frame,"SetPaused",true,false)
end
end
return self
end
end
end)();install(E,G)end
do local install=(function()
return function(E,G)
local pcall=G.pcall
local LAYER_STRIDE=288
function E.readModelBounds(actor,method)
if not actor or not actor[method]then return nil end
local ok,a,b,c,d,e,f=pcall(actor[method],actor)
if not ok then return nil end
if type(a)~="number"then
local function xyz(v)if v.GetXYZ then return v:GetXYZ()end;return v.x,v.y,v.z end
ok,a,b,c,d,e,f=pcall(function()
local x,y,z=xyz(a);local xx,yy,zz=xyz(b)
return x,y,z,xx,yy,zz
end)
if not ok then return nil end
end
if not(E.util.finite(a)and E.util.finite(b)and E.util.finite(c)and
E.util.finite(d)and E.util.finite(e)and E.util.finite(f))then return nil end
return{x=a,y=b,z=c},{x=d,y=e,z=f}
end
function E.fitModelBounds(bottom,top,aspect,yaw,fill)
local function xyz(v)if v.GetXYZ then return v:GetXYZ()end;return v.x,v.y,v.z end
local ok,x0,y0,z0,x1,y1,z1=pcall(function()
local a,b,c=xyz(bottom);local d,e,f=xyz(top);return a,b,c,d,e,f
end)
if not ok then return nil end
local values={x0,y0,z0,x1,y1,z1,aspect,yaw,fill}
for i=1,9 do if not E.util.finite(values[i])then return nil end end
if not x1 or x1<=x0 or y1<=y0 or z1<=z0 or aspect<=0 then return nil end
local c,s=math.cos(yaw),math.sin(yaw)
local dx,dy,h=x1-x0,y1-y0,z1-z0
local depth=math.abs(c)*dx+math.abs(s)*dy
local width=math.abs(s)*dx+math.abs(c)*dy
local tangent=math.tan(.55/2)
fill=E.util.clamp(fill,.35,.9)
local nearest=math.max(h/(2*tangent*fill),width/(2*tangent*aspect*fill),.01)
local cx,cy,cz=(x0+x1)/2,(y0+y1)/2,(z0+z1)/2
return{distance=depth/2+nearest,cameraZ=-h/2+.8*nearest*tangent,
actorX=-(cx*c-cy*s),actorY=-(cx*s+cy*c),actorZ=-cz,
width=width,height=h,depth=depth,nearest=nearest,fov=.55,
bottom={x=x0,y=y0,z=z0},top={x=x1,y=y1,z=z1}}
end
function E.resolveModel(def)
if def.kind~="petSpeciesID"then return def.kind,def.id end
local journal=G.C_PetJournal
if not journal then return nil,nil,"pet_journal_unavailable"end
local display
if journal.GetDisplayIDByIndex then
local ok,value=pcall(journal.GetDisplayIDByIndex,def.id,def.displayIndex or 1)
if ok and type(value)=="number"and value>0 then display=value end
end
if not display and journal.GetPetInfoTableBySpeciesID then
local ok,info=pcall(journal.GetPetInfoTableBySpeciesID,def.id)
if ok and type(info)=="table"and type(info.displayID)=="number"and info.displayID>0 then display=info.displayID end
end
if display then return"creatureDisplayID",display end
return nil,nil,"pet_display_unavailable"
end
function E.newSurface(session,parent,cache)
cache=cache or{pools={},layers={}}
if not cache.root then cache.root=G.CreateFrame("Frame",nil,parent)end
local root,nodes,generation,count=cache.root,{},0,0
local width,height=session.content.viewport.width,session.content.viewport.height
root:ClearAllPoints();root:SetPoint("TOPLEFT",parent,"TOPLEFT",0,0)
root:SetSize(width,height);root:EnableMouse(false);root:Show()
local self={}
local actorSurface
local measuredBounds,preloadQueue,preloadSeen={},{},{}
local preloader
local function modelKey(def)return def.kind..":"..tostring(def.id)..":"..tostring(def.displayIndex or 1)end
local assets=session.content.assets or{}
local modelLimit=(session.content.limits or{}).maxSurfaceModels or 104
cache.modelCount=cache.modelCount or 0
cache.compatModelCount=cache.compatModelCount or 0
local function optional(object,method,...)
if object and object[method]then return pcall(object[method],object,...)end
return false
end
optional(root,"SetClipsChildren",false)
local function modelLevel(node,level)
optional(node.object,"SetFixedFrameLevel",true)
if node.object:GetFrameLevel()~=level then node.object:SetFrameLevel(level)end
local child=node.scene or node.model
if child then
optional(child,"SetFixedFrameLevel",true)
if child:GetFrameLevel()~=level+1 then child:SetFrameLevel(level+1)end
end
if node.compatModel then
optional(node.compatModel,"SetFixedFrameLevel",true)
if node.compatModel:GetFrameLevel()~=level+1 then node.compatModel:SetFrameLevel(level+1)end
end
node.drawLevel=level
end
local function texture(object,key,coords,color,repeatTexture,blend)
local def=(assets.textures or{})[key]
if not def then G.error("unknown surface texture: "..tostring(key))end
local wrap=repeatTexture and"REPEAT"or"CLAMP"
local ok,result,atlasApplied
if def.kind=="atlas"and object.SetAtlas then ok,result=pcall(object.SetAtlas,object,def.atlas,false)
atlasApplied=ok and result~=false
elseif def.kind=="atlas"then ok=false
else ok,result=pcall(object.SetTexture,object,def.id or def.path,wrap,wrap)end
if not ok or result==false then
pcall(object.SetTexture,object,def.fallbackPath or"Interface\\Icons\\INV_Misc_QuestionMark")
end
if coords or not atlasApplied then object:SetTexCoord(unpack(coords or{0,1,0,1}))end
object:SetVertexColor(unpack(color or{1,1,1,1}))
object:SetBlendMode(blend or"BLEND")
end
local function clearModel(node)
if node.model then
if not node.scene then optional(node.model,"SetScript","OnModelLoaded",nil)end
if node.scene then optional(node.scene,"SetPaused",true,false);node.scene:Hide()end
optional(node.model,"SetPaused",true);optional(node.model,"ClearModel")
node.model:Hide()
end
if node.compatModel then
node.compatModel:SetScript("OnModelLoaded",nil);optional(node.compatModel,"ClearModel");node.compatModel:Hide()
end
node.asset=nil;node.loaded=false;node.pose=nil;node.modelRequested=false;node.resolvedID=nil
node.bounds=nil;node.fitReady=false;node.framing=nil
node.compatActive=false;node.compatLoaded=false;node.compatRequested=false;node.failureNotice=false
node.hiddenAt=nil
end
local function legacyPose(model,spec,def,compat)
optional(model,"SetPortraitZoom",def.portraitZoom or 0)
optional(model,"SetCamDistanceScale",compat and(def.fallbackDistance or.65)or spec.distance or def.distance or 1)
optional(model,"SetModelScale",spec.scale or def.scale or 1)
optional(model,"SetFacing",spec.facing or def.facing or 0)
optional(model,"SetPosition",unpack(def.offset or{0,0,0}))
optional(model,"SetAnimation",spec.animation or def.animation or 0)
optional(model,"SetPaused",session.paused or spec.paused==true)
end
local function pose(node)
local model,spec,def=node.model,node.pose,node.modelDef
if not model or not spec or not def then return end
if node.scene then
if not node.loaded then return end
if not node.bounds then node.bounds=measuredBounds[modelKey(def)]end
if not node.bounds then
if session.host.now()-(node.requestedAt or 0)>3 then return end
optional(model,"SetScale",1);optional(model,"SetYaw",0);optional(model,"SetPosition",0,0,0)
optional(model,"SetUseCenterForOrigin",false,false,false)
local bottom,top=E.readModelBounds(model,"GetActiveBoundingBox")
local fit=E.fitModelBounds(bottom,top,(spec.w or 1)/(spec.h or 1),spec.facing or def.facing or 0,def.fitFill or.82)
if not fit then
bottom,top=E.readModelBounds(model,"GetMaxBoundingBox")
fit=E.fitModelBounds(bottom,top,(spec.w or 1)/(spec.h or 1),spec.facing or def.facing or 0,def.fitFill or.82)
end
if not fit then return end
node.bounds={fit.bottom,fit.top}
measuredBounds[modelKey(def)]=node.bounds
end
local fit=E.fitModelBounds(node.bounds[1],node.bounds[2],(spec.w or 1)/(spec.h or 1),spec.facing or def.facing or 0,def.fitFill or.82)
if not fit then return end
node.framing=fit;node.fitReady=true
optional(model,"SetScale",1);optional(model,"SetYaw",spec.facing or def.facing or 0)
optional(model,"SetPosition",fit.actorX,fit.actorY,fit.actorZ)
node.scene:SetCameraFieldOfView(fit.fov)
node.scene:SetCameraPosition(-fit.distance,0,fit.cameraZ)
optional(node.scene,"SetCameraNearClip",math.max(.001,fit.nearest*.01))
optional(node.scene,"SetCameraFarClip",fit.distance+fit.depth+fit.height+20)
optional(model,"SetAnimation",spec.animation or def.animation or 0)
optional(node.scene,"SetPaused",session.paused or spec.paused==true,false)
return
end
legacyPose(model,spec,def)
end
local function compatibilityModel(node,spec,def)
if not node.compatModel and cache.compatModelCount<modelLimit then
local ok,model=pcall(G.CreateFrame,"PlayerModel",nil,node.object)
if ok and model then
node.compatModel=model;cache.compatModelCount=cache.compatModelCount+1
model:SetAllPoints(node.object);model:EnableMouse(false)
model:SetFrameLevel(node.object:GetFrameLevel()+1)
end
end
local model=node.compatModel
if not model then return false end
if not node.compatActive then
node.compatActive=true
if node.scene then node.scene:Hide();optional(node.scene,"SetPaused",true,false)end
if node.model then node.model:Hide();optional(node.model,"ClearModel")end
end
if not node.compatRequested and session.host.now()>=(node.compatNextAt or 0)then
node.compatNextAt=session.host.now()+.5
local kind,id=E.resolveModel(def)
if kind then
node.compatRequested=true
model:SetScript("OnModelLoaded",function()
if node.claimed and not session.stopping and node.asset==spec.asset then
node.compatLoaded=true;legacyPose(model,node.pose or spec,def,true);model:Show()
end
end)
local ok,accepted=optional(model,kind=="creatureDisplayID"and"SetDisplayInfo"or"SetModel",id)
if not ok or accepted==false then node.compatRequested=false end
end
end
if model.GetModelFileID then
local ok,id=pcall(model.GetModelFileID,model)
node.compatLoaded=ok and type(id)=="number"and id>0
end
local signature=table.concat({spec.animation or def.animation or 0,(session.paused or spec.paused)and 1 or 0,spec.w or 1,spec.h or 1},":")
node.pose=spec
if node.compatLoaded then
if node.compatPose~=signature then legacyPose(model,spec,def,true);node.compatPose=signature end
model:Show()
else model:Hide()end
return node.compatLoaded
end
local function reportUnavailable(node,spec)
if node.preloading or node.failureNotice then return end
node.failureNotice=true
session.perf.note("model.unavailable",{asset=spec.asset,reason=node.loadReason or"model_or_bounds_unavailable"})
end
local function drawModel(node,spec)
local def=(assets.models or{})[spec.asset]
if not def then G.error("unknown surface model: "..tostring(spec.asset))end
local modelOnly=def.fallbackMode=="model"
local fallback=not modelOnly and(spec.fallback or def.fallback)
if fallback and node.fallbackAsset~=fallback then
texture(node.fallback,fallback,nil,{1,1,1,1});node.fallbackAsset=fallback
end
if not node.model and not node.unavailable and cache.modelCount<modelLimit then
if def.fitToBounds then
local ok,model=pcall(function()
node.scene=node.scene or G.CreateFrame("ModelScene",nil,node.object)
node.scene:SetAllPoints(node.object);node.scene:EnableMouse(false)
node.scene:SetAlpha(0)
node.scene:SetCameraOrientationByAxisVectors(1,0,0,0,-1,0,0,0,1)
optional(node.scene,"SetLightVisible",true)
optional(node.scene,"SetLightAmbientColor",.72,.72,.72)
optional(node.scene,"SetLightDiffuseColor",.28,.28,.28)
optional(node.scene,"SetLightDirection",-1,-1,-1)
return node.scene:CreateActor("IGSurfaceModel"..tostring(cache.modelCount+1))
end)
if ok and model then node.model=model;cache.modelCount=cache.modelCount+1
else node.unavailable=true;if node.scene then node.scene:Hide()end end
else
local ok,model=pcall(G.CreateFrame,"PlayerModel",nil,node.object)
if ok and model then
node.model=model;cache.modelCount=cache.modelCount+1
model:SetAllPoints(node.object);model:EnableMouse(false)
optional(model,"SetClipsChildren",false)
else node.unavailable=true end
end
end
local model=node.model
if node.asset~=spec.asset then
clearModel(node);node.asset=spec.asset;node.modelDef=def;node.pose=spec
node.requestedAt=session.host.now();node.failed=false;node.resolveNextAt=0
node.compatNextAt=0;node.compatPose=nil
node.lastPose=nil
end
if node.compatActive then
local ready=compatibilityModel(node,spec,def);node.fallback:Hide()
if not ready and session.host.now()-node.requestedAt>=3 then reportUnavailable(node,spec)end
return
end
if model and not node.modelRequested and node.asset and session.host.now()>=(node.resolveNextAt or 0)and session.host.now()-node.requestedAt<=3 then
local kind,id,reason=E.resolveModel(def)
node.resolveNextAt=session.host.now()+.5
node.failed=not kind;node.loadReason=reason
if kind then
node.modelRequested=true;node.resolvedID=id
if node.scene then optional(node.scene,"SetPaused",false,false)end
if not node.scene then
model:SetScript("OnModelLoaded",function()
if node.claimed and not session.stopping and node.asset==spec.asset then
node.loaded=true;node.failed=false;pose(node);node.fallback:Hide()
end
end)
end
local ok,accepted
if node.scene then
ok,accepted=optional(model,kind=="creatureDisplayID"and"SetModelByCreatureDisplayID"or"SetModelByFileID",id)
elseif kind=="creatureDisplayID"then ok,accepted=optional(model,"SetDisplayInfo",id)
else ok,accepted=optional(model,"SetModel",id)end
if not ok or accepted==false then node.failed=true end
end
end
if model and not node.failed then
if not node.loaded and model.GetModelFileID then
local ok,id=pcall(model.GetModelFileID,model)
node.loaded=ok and type(id)=="number"and id>0
if node.loaded then node.lastPose=nil end
end
local signature=table.concat({spec.scale or def.scale or 1,spec.distance or def.distance or 1,
spec.facing or def.facing or 0,spec.animation or def.animation or 0,
(session.paused or spec.paused)and 1 or 0,spec.w or 1,spec.h or 1},":")
node.pose=spec
if node.lastPose~=signature or(node.scene and node.loaded and not node.fitReady)then pose(node);node.lastPose=signature end
if node.scene then
if node.loaded and node.fitReady then model:Show();node.scene:SetAlpha(1);node.scene:Show()
elseif session.host.now()-(node.requestedAt or 0)<3 then model:Show();node.scene:SetAlpha(0);node.scene:Show()
else node.scene:Hide()end
elseif node.loaded or session.host.now()-(node.requestedAt or 0)<3 then model:Show()else model:Hide()end
elseif model then model:Hide()end
local ready=node.loaded and not node.failed and(not node.scene or node.fitReady)
if modelOnly then
node.fallback:Hide()
if not ready and(node.unavailable or node.failed or session.host.now()-node.requestedAt>=3)then
ready=compatibilityModel(node,spec,def)
if not ready and session.host.now()-node.requestedAt>=3 then reportUnavailable(node,spec)end
end
elseif ready then node.fallback:Hide()else node.fallback:Show()end
end
local function layer(n)
if not cache.layers[n]then
local f=G.CreateFrame("Frame",nil,root)
f:SetAllPoints(root);f:SetFrameLevel(root:GetFrameLevel()+n*LAYER_STRIDE)
optional(f,"SetClipsChildren",false)
f:EnableMouse(false)
cache.layers[n]=f
end
return cache.layers[n]
end
local function acquire(kind,z,nativeButton)
local key=kind..":"..z..(nativeButton and":native"or"")
local pool=cache.pools[key]or{};cache.pools[key]=pool
for _,node in ipairs(pool)do if not node.claimed then node.claimed=true;return node end end
local parentLayer,object=layer(z)
if kind=="text"then object=parentLayer:CreateFontString(nil,"OVERLAY","GameFontNormal")
elseif kind=="cooldown"then
object=G.CreateFrame("Cooldown",nil,parentLayer,"CooldownFrameTemplate")
object:EnableMouse(false);object:SetHideCountdownNumbers(true)
object:SetDrawSwipe(true);object:SetDrawEdge(true);object:SetDrawBling(false)
object:SetSwipeColor(.015,.03,.02,.78)
elseif kind=="button"or kind=="model"or kind=="panel"then
object=G.CreateFrame(kind=="button"and"Button"or"Frame",nil,parentLayer,
nativeButton and"UIPanelButtonTemplate"or nil)
object:EnableMouse(false)
else object=parentLayer:CreateTexture(nil,"ARTWORK")end
local node={object=object,claimed=true,kind=kind,nativeButton=nativeButton==true}
if kind=="panel"then
node.bg=object:CreateTexture(nil,"BACKGROUND");node.bg:SetAllPoints(object)
end
if kind=="model"then
node.fallback=object:CreateTexture(nil,"BACKGROUND");node.fallback:SetAllPoints(object)
if object.SetClipsChildren then object:SetClipsChildren(false)end
end
if kind=="button"then
node.bg=object:CreateTexture(nil,"BACKGROUND");node.bg:SetAllPoints(object)
node.label=object:CreateFontString(nil,"OVERLAY","GameFontNormal")
node.label:SetAllPoints(object)
object:RegisterForClicks("LeftButtonUp","RightButtonUp")
object:SetScript("OnClick",function(_,button)
if node.enabled and node.fn then session.safe("surface.click",node.fn,button)end
end)
object:SetScript("OnEnter",function()if node.enabled and not node.nativeButton then object:SetAlpha(.82)end end)
object:SetScript("OnLeave",function()object:SetAlpha(1)end)
end
pool[#pool+1]=node;return node
end
function self.begin()
generation=generation+1
if actorSurface then actorSurface.begin()end
root:SetScale(math.max(.1,math.min(parent:GetWidth()/width,parent:GetHeight()/height)))
end
function self.draw(id,spec)
local kind,z=spec.kind or"rect",spec.layer or 0
if kind~="rect"and kind~="text"and kind~="button"and kind~="texture"and kind~="model"and kind~="cooldown"and kind~="panel"then G.error("unsupported surface node")end
if z<0 or z>30 or z~=math.floor(z)then G.error("invalid surface layer")end
local node=nodes[id]
if not node then
count=count+1;if count>3600 then G.error("surface node budget exceeded")end
node=acquire(kind,z,kind=="button"and spec.nativeButton==true);node.z=z;node.order=count;nodes[id]=node
end
if node.kind~=kind or node.z~=z then G.error("surface node type/layer changed: "..id)end
if kind=="button"and(node.nativeButton==true)~=(spec.nativeButton==true)then G.error("surface button template changed: "..id)end
node.generation=generation
node.lastSpec=spec
if node.hiddenAt then node.hiddenAt=nil;node.lastPose=nil;node.compatPose=nil end
local object=node.object
local x,y,w,h=spec.x or 0,spec.y or 0,spec.w or 1,spec.h or 1
node.depth=spec.depth or(kind=="model"and spec.anchorY)or(y+h)
if not E.util.finite(node.depth)then G.error("invalid surface depth")end
if node.x~=x or node.y~=y then object:ClearAllPoints();object:SetPoint("TOPLEFT",layer(z),"TOPLEFT",x,-y);node.x=x;node.y=y end
if node.w~=w or node.h~=h then object:SetSize(math.max(.01,w),math.max(.01,h));node.w=w;node.h=h end
if kind=="panel"then
local layout=spec.layout or"Dialog"
if node.panelLayout~=layout then
local ns=G.NineSliceUtil
if node.panelLayout and ns and ns.HideLayout then pcall(ns.HideLayout,object)end
local ok=false
if ns and ns.GetLayout and ns.ApplyLayoutByName and ns.GetLayout(layout)then
ok=pcall(ns.ApplyLayoutByName,object,layout)
end
node.panelLayout=layout;node.panelBorderReady=ok
if not ok then
if ns and ns.HideLayout then pcall(ns.HideLayout,object)end
session.perf.note("surface.panel",{layout=layout,status="native_border_unavailable"})
end
end
end
local color=spec.color or((kind=="text"or kind=="texture")and{1,1,1,1}or{.2,.3,.2,1})
local signature=table.concat(color,":")
if kind=="texture"or((kind=="button"or kind=="panel")and spec.asset)then
local texSignature=tostring(spec.asset)..":"..signature..":"..table.concat(spec.texCoord or{0,1,0,1},":")..":"..tostring(spec.tile)..":"..(spec.blend or"BLEND")
if node.textureSignature~=texSignature then
texture(node.bg or object,spec.asset,spec.texCoord,color,spec.tile,spec.blend);node.textureSignature=texSignature
end
elseif kind=="model"then
if session.content.surfaceModelScene then
if not E.newSurfaceActors then G.error("package_not_included: surface-models")end
if not actorSurface then actorSurface=E.newSurfaceActors(session,root,cache,layer);actorSurface.begin()end
actorSurface.draw(node,spec,(assets.models or{})[spec.asset])
else drawModel(node,spec)end
elseif kind=="cooldown"then
local duration,remaining=spec.duration,spec.remaining
if not E.util.finite(duration)or duration<=0 or not E.util.finite(remaining)then G.error("invalid surface cooldown")end
remaining=math.max(0,math.min(duration,remaining))
duration=duration/(session.speed or 1);remaining=remaining/(session.speed or 1)
local now=session.host.now();local paused=session.paused or spec.paused==true
if node.cdDuration~=duration or node.cdPaused~=paused or not node.cdEnd or math.abs(node.cdEnd-now-remaining)>.12 then
object:SetCooldown(now-duration+remaining,duration)
object:SetPaused(paused);node.cdEnd=now+remaining;node.cdDuration=duration;node.cdPaused=paused
end
else
if node.textureSignature then node.color=nil;node.textureSignature=nil end
if node.color~=signature then
if kind=="text"then object:SetTextColor(unpack(color))
else(node.bg or object):SetColorTexture(unpack(color))end
node.color=signature
end
end
if kind=="text"or kind=="button"then
local font=node.label or object
if node.text~=spec.text then font:SetText(spec.text or"");node.text=spec.text end
local size=spec.size or 14
if node.size~=size then font:SetFont(G.STANDARD_TEXT_FONT or"Fonts\\FRIZQT__.TTF",size,"");node.size=size end
local align=spec.align or"CENTER"
if node.align~=align then font:SetJustifyH(align);node.align=align end
if kind=="button"then
node.fn=spec.onClick;node.enabled=spec.enabled~=false
object:EnableMouse(node.enabled)
if node.nativeButton then optional(object,"SetEnabled",node.enabled)end
if node.nativeButton or(not spec.asset and color[4]==0)then node.bg:Hide()else node.bg:Show()end
font:SetTextColor(1,.96,.84,node.enabled and 1 or.45)
end
end
object:Show();return node
end
function self.finish()
local groups={}
for _,node in pairs(nodes)do
if node.generation~=generation then
node.object:Hide();node.fn=nil
if node.kind=="model"and node.asset and not node.sharedScene then
node.hiddenAt=node.hiddenAt or session.host.now()
if node.scene then optional(node.scene,"SetPaused",true,false);node.scene:Hide()end
if node.compatModel then optional(node.compatModel,"SetPaused",true);node.compatModel:Hide()end
if not node.scene and node.model then optional(node.model,"SetPaused",true);node.model:Hide()end
if session.host.now()-node.hiddenAt>=15 then clearModel(node)end
end
if node.kind=="cooldown"then node.object:Clear();node.cdEnd=nil end
elseif node.kind=="model"and not node.sharedScene then
groups[node.z]=groups[node.z]or{};groups[node.z][#groups[node.z]+1]=node
end
end
for z,group in pairs(groups)do
table.sort(group,function(a,b)if a.depth==b.depth then return a.order<b.order end;return a.depth<b.depth end)
for rank,node in ipairs(group)do
local level=layer(z):GetFrameLevel()+rank*2
modelLevel(node,level)
end
end
if actorSurface then actorSurface.finish()end
end
function self.preloadModel(asset)
if session.content.surfaceModelScene then
if not E.newSurfaceActors then G.error("package_not_included: surface-models")end
if not actorSurface then actorSurface=E.newSurfaceActors(session,root,cache,layer);actorSurface.begin()end
return actorSurface.preload(asset,4)
end
local def=(assets.models or{})[asset]
if not def or preloadSeen[asset]or measuredBounds[modelKey(def)]or#preloadQueue>=32 then return false end
preloadSeen[asset]=true;preloadQueue[#preloadQueue+1]=asset;return true
end
function self.update()
if session.stopping then return end
if actorSurface then actorSurface.update()end
for _,node in pairs(nodes)do
if node.kind=="model"and not node.sharedScene and node.generation==generation and node.lastSpec then
local ready=(node.compatActive and node.compatLoaded)or(node.loaded and not node.failed and(not node.scene or node.fitReady))
if not ready then drawModel(node,node.lastSpec)end
if node.drawLevel then modelLevel(node,node.drawLevel)end
elseif node.kind=="model"and node.hiddenAt and session.host.now()-node.hiddenAt>=15 then clearModel(node)end
end
if#preloadQueue>0 then
if not preloader then
preloader=acquire("model",0);preloader.preloading=true
preloader.object:SetPoint("TOPLEFT",root,"TOPLEFT",0,0);preloader.object:SetSize(96,96)
preloader.object:SetAlpha(0);preloader.object:Show()
end
local asset=preloadQueue[1]
drawModel(preloader,{asset=asset,w=96,h=96,animation=0})
if preloader.fitReady or preloader.compatLoaded or(preloader.requestedAt and session.host.now()-preloader.requestedAt>=3.1)then
clearModel(preloader);table.remove(preloadQueue,1)
end
end
end
function self.dispose()
if actorSurface then actorSurface.dispose()end
if preloader then
clearModel(preloader);preloader.object:Hide();preloader.object:SetAlpha(1)
preloader.claimed=false;preloader.preloading=false;preloader.unavailable=nil
end
root:Hide()
for _,node in pairs(nodes)do
node.object:Hide();node.fn=nil;node.enabled=false;node.claimed=false;node.object:SetAlpha(1)
if node.kind=="button"then node.object:SetScript("OnClick",nil);node.object:SetScript("OnEnter",nil);node.object:SetScript("OnLeave",nil)end
if node.kind=="model"then
if node.sharedScene then node.scene=nil;node.sharedScene=nil else clearModel(node)end
node.fallbackAsset=nil;node.unavailable=nil
end
if node.kind=="cooldown"then node.object:Clear();node.object:SetPaused(false);node.cdEnd=nil end
node.textureSignature=nil;node.color=nil
end
end
for _,pool in pairs(cache.pools)do
for _,node in ipairs(pool)do
if node.kind=="button"then
node.object:SetScript("OnClick",function(_,button)if node.enabled and node.fn then session.safe("surface.click",node.fn,button)end end)
node.object:SetScript("OnEnter",function()if node.enabled and not node.nativeButton then node.object:SetAlpha(.82)end end)
node.object:SetScript("OnLeave",function()node.object:SetAlpha(1)end)
end
end
end
self.cache=cache
function self.stats()
local active,loaded,fallback=0,0,0
for _,node in pairs(nodes)do
if node.kind=="model"and node.claimed and node.generation==generation then
active=active+1
if(node.compatActive and node.compatLoaded)or(not node.compatActive and node.loaded and not node.failed and(not node.scene or node.fitReady))then loaded=loaded+1 else fallback=fallback+1 end
end
end
return{surfaceModels=active,surfaceModelsLoaded=loaded,surfaceModelFallbacks=fallback,pooledSurfaceModels=cache.modelCount+cache.compatModelCount,surfaceNodes=count}
end
return self
end
end
end)();install(E,G)end
do local install=(function()
return function(E,G)
local pcall=G.pcall
local function label(parent,size,layer)
local f=parent:CreateFontString(nil,layer or"OVERLAY",size or"GameFontNormalSmall")
f:SetJustifyH("LEFT");return f
end
local function background(parent,r,g,b,a)
local t=parent:CreateTexture(nil,"BACKGROUND");t:SetAllPoints(parent);t:SetColorTexture(r,g,b,a);return t
end
function E.newWoWView(session)
local host,config=session.host,session.content
local cache=E.viewCache
if not cache then
cache={rects={},models={},actors={},terrain={},buttons={},bounds={},health={},created=0}
E.viewCache=cache
local f=G.CreateFrame("Frame",nil,G.UIParent)
cache.frame=f;f:SetFrameStrata("DIALOG");f:SetClampedToScreen(true)
f:SetMovable(true);f:EnableMouse(true)
background(f,.035,.045,.065,.98)
cache.title=label(f,"GameFontNormalLarge");cache.title:SetPoint("TOPLEFT",14,-13)
cache.info=label(f);cache.info:SetPoint("TOPLEFT",14,-39);cache.info:SetSize(860,18)
cache.message=label(f);cache.message:SetPoint("BOTTOMLEFT",14,12);cache.message:SetSize(860,22)
cache.status=label(f);cache.status:SetPoint("BOTTOMLEFT",14,39);cache.status:SetSize(860,20)
cache.drag=G.CreateFrame("Frame",nil,f);cache.drag:SetPoint("TOPLEFT");cache.drag:SetPoint("TOPRIGHT",f,"TOPRIGHT",-46,0);cache.drag:SetHeight(33)
cache.drag:EnableMouse(true);cache.drag:RegisterForDrag("LeftButton")
cache.drag:SetScript("OnDragStart",function()f:StartMoving()end)
cache.drag:SetScript("OnDragStop",function()f:StopMovingOrSizing()end)
cache.close=G.CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
cache.close:SetSize(30,24);cache.close:SetPoint("TOPRIGHT",-8,-8);cache.close:SetText("X")
cache.canvas=G.CreateFrame("Frame",nil,f)
cache.canvas:SetPoint("TOPLEFT",12,-170);cache.canvas:SetPoint("BOTTOMRIGHT",-12,68)
if cache.canvas.SetClipsChildren then cache.canvas:SetClipsChildren(true)end
background(cache.canvas,.06,.08,.105,1)
cache.overlay=G.CreateFrame("Frame",nil,cache.canvas);cache.overlay:SetAllPoints(cache.canvas);cache.overlay:SetFrameLevel(cache.canvas:GetFrameLevel()+10)
cache.logFrame=G.CreateFrame("Frame",nil,f)
cache.logFrame:SetAllPoints(f);cache.logFrame:SetFrameLevel(f:GetFrameLevel()+9500);cache.logFrame:EnableMouse(true)
cache.close:SetFrameLevel(cache.logFrame:GetFrameLevel()+10)
background(cache.logFrame,.025,.03,.04,1)
local help=label(cache.logFrame);help:SetPoint("TOPLEFT",14,-15);help:SetWidth(690);cache.logHeader=help
local close=G.CreateFrame("Button",nil,cache.logFrame,"UIPanelButtonTemplate")
close:SetSize(90,24);close:SetPoint("TOPRIGHT",-52,-10);close:SetText("返回")
local function dismissPanel()
cache.logEdit:ClearFocus();cache.logFrame:Hide()
cache.apply:Hide();cache.apply:SetScript("OnClick",nil)
end
close:SetScript("OnClick",dismissPanel)
cache.apply=G.CreateFrame("Button",nil,cache.logFrame,"UIPanelButtonTemplate")
cache.apply:SetSize(90,24);cache.apply:SetPoint("TOPRIGHT",-148,-10);cache.apply:SetText("确定");cache.apply:Hide()
local scroll=G.CreateFrame("ScrollFrame",nil,cache.logFrame,"UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT",14,-45);scroll:SetPoint("BOTTOMRIGHT",-36,14)
local edit=G.CreateFrame("EditBox",nil,scroll)
edit:SetMultiLine(true);edit:SetAutoFocus(false);edit:SetFontObject("ChatFontNormal")
edit:SetWidth(830);edit:SetHeight(430);edit:SetMaxLetters(0)
edit:SetScript("OnEscapePressed",dismissPanel)
scroll:SetScrollChild(edit);cache.logEdit=edit;cache.logFrame:Hide()
end
local self={cache=cache,frame=cache.frame,canvas=cache.canvas,buttons=0,camera={x=0,y=0,zoom=1},showBounds=false,drawn=0,modelLoaded=0,modelFailed=0}
local f=cache.frame
local width=math.min(980,math.max(600,G.UIParent:GetWidth()-40))
local height=math.min(690,math.max(480,G.UIParent:GetHeight()-40))
f:SetSize(width,height);f:ClearAllPoints();f:SetPoint("CENTER")
local gameUI=config.presentation=="game"
cache.title:SetText(session.manifest.name..(gameUI and""or"  /  Engine "..E.VERSION))
cache.canvas:ClearAllPoints()
cache.canvas:SetPoint("TOPLEFT",12,gameUI and-44 or-170)
cache.canvas:SetPoint("BOTTOMRIGHT",-12,gameUI and 34 or 68)
if gameUI then cache.info:Hide();cache.status:Hide()else cache.info:Show();cache.status:Show()end
cache.logEdit:SetWidth(width-58)
cache.logHeader:SetWidth(width-265)
cache.title:SetWidth(width-70);cache.info:SetWidth(width-28);cache.message:SetWidth(width-28);cache.status:SetWidth(width-28)
cache.message:SetText(gameUI and""or"选择测试。性能数据必须在当前客户端运行后导出。")
if config.hideHostFooter then cache.message:Hide()else cache.message:Show()end
cache.logFrame:Hide();cache.logEdit:ClearFocus()
cache.close:SetScript("OnClick",function()session.requestClose("window_closed")end)
f:SetScript("OnHide",function()
if not session.stopping and not self.hiding then
self.hiding=true;if cache.escapeProxy then cache.escapeProxy:Hide()end;self.hiding=false
session.requestClose("window_hidden")
end
end)
f:Show()
local function acquire(pool,make)
for i=1,#pool do if not pool[i].active then pool[i].active=true;return pool[i]end end
if#pool>=1600 then return nil,"view_pool_limit"end
local h={object=make(),active=true};pool[#pool+1]=h;cache.created=cache.created+1;return h
end
function self.attach(entity)
local visual=entity.visual or{};local handle,kind
if visual.kind=="scene_model"then
local def=(config.assets.models or{})[visual.asset]
if not def then return nil,"missing_model_asset"end
local modelKind,modelID=E.resolveModel(def)
if not modelKind then return nil,"model_display_unavailable"end
local ok,result=pcall(function()
if not cache.scene then
cache.scene=G.CreateFrame("ModelScene",nil,cache.canvas)
cache.scene:SetPoint("BOTTOMLEFT",cache.canvas,"BOTTOMLEFT",0,0)
cache.scene:SetCameraFieldOfView(.9)
cache.scene:SetCameraPosition(-config.viewport.height/(24*math.tan(.45)),0,config.viewport.height/24)
if cache.scene.SetCameraFarClip then cache.scene:SetCameraFarClip(1000)end
end
local free=false;for _,h in ipairs(cache.actors)do if not h.active then free=true;break end end
if not free and#cache.actors>=40 then G.error("actor_pool_limit")end
return acquire(cache.actors,function()return cache.scene:CreateActor("IGActor"..(#cache.actors+1))end)
end)
if not ok or not result then self.modelFailed=self.modelFailed+1;return nil,"ModelScene_unavailable"end
handle=result;kind="scene_model";handle.loaded=false;handle.owner=session
local actor=handle.object
local called,accepted
if modelKind=="creatureDisplayID"then called,accepted=pcall(actor.SetModelByCreatureDisplayID,actor,modelID)
else called,accepted=pcall(actor.SetModelByFileID,actor,modelID)end
if not called or accepted==false then actor:Hide();handle.active=false;self.modelFailed=self.modelFailed+1;return nil,"actor_load_call_failed"end
if actor.SetScale then actor:SetScale(def.sceneScale or 1)end
if actor.SetYaw then actor:SetYaw(def.facing or 0)end
if actor.SetPaused then actor:SetPaused(false)end
cache.scene:Show()
elseif visual.kind=="model"then
if#cache.models>=40 then
local free=false;for _,h in ipairs(cache.models)do if not h.active then free=true;break end end
if not free then return nil,"model_pool_limit"end
end
local ok,result=pcall(acquire,cache.models,function()return G.CreateFrame("PlayerModel",nil,cache.canvas)end)
if not ok or not result then self.modelFailed=self.modelFailed+1;return nil,"PlayerModel_unavailable"end
handle=result;kind="model"
local def=(config.assets.models or{})[visual.asset]
if not def then handle.active=false;return nil,"missing_model_asset"end
local modelKind,modelID=E.resolveModel(def)
if not modelKind then handle.active=false;return nil,"model_display_unavailable"end
local model=handle.object
if model.ClearModel then model:ClearModel()end
model:SetSize(visual.width or 64,visual.height or 64)
handle.loaded=false;handle.owner=session
model:SetScript("OnModelLoaded",function()
if handle.active and handle.owner==session and not session.stopping and not handle.loaded then handle.loaded=true;self.modelLoaded=self.modelLoaded+1 end
end)
local success
if modelKind=="creatureDisplayID"and model.SetDisplayInfo then success=pcall(model.SetDisplayInfo,model,modelID)
elseif modelKind=="fileID"and model.SetModel then success=pcall(model.SetModel,model,modelID)end
if not success then model:Hide();handle.active=false;self.modelFailed=self.modelFailed+1;return nil,"model_load_call_failed"end
if model.SetModelScale then pcall(model.SetModelScale,model,def.scale or 1)end
if model.SetFacing then pcall(model.SetFacing,model,def.facing or 0)end
else
handle=acquire(cache.rects,function()return cache.canvas:CreateTexture(nil,"ARTWORK")end);kind="rect"
if not handle then return nil,"texture_pool_limit"end
local color=visual.color or{.3,.75,.95,1}
handle.object:SetColorTexture(color[1],color[2],color[3],color[4]or 1)
end
handle.kind=kind;handle.animation=nil;handle.object:Show();entity.view=handle
if entity.role=="player"or entity.ai then
entity.healthView=acquire(cache.health,function()return cache.overlay:CreateTexture(nil,"OVERLAY")end)
if entity.healthView then entity.healthView.object:SetColorTexture(.2,.95,.35,1);entity.healthView.object:Show()end
end
return handle
end
function self.detach(entity)
local h=entity.view
if h then
h.active=false;h.owner=nil;h.object:Hide()
if h.kind=="model"then h.object:SetScript("OnModelLoaded",nil);if h.object.ClearModel then h.object:ClearModel()end end
if h.kind=="scene_model"and h.object.SetPaused then h.object:SetPaused(true)end
entity.view=nil
end
if entity.boundsView then entity.boundsView.object:Hide();entity.boundsView.active=false;entity.boundsView=nil end
if entity.healthView then entity.healthView.object:Hide();entity.healthView.active=false;entity.healthView=nil end
end
function self.setTerrain(rectangles)
for _,h in ipairs(cache.terrain)do h.active=false;h.object:Hide()end
self.terrain=rectangles or{}
for _,rect in ipairs(self.terrain)do
local h=acquire(cache.terrain,function()return cache.canvas:CreateTexture(nil,"BACKGROUND")end)
if h then h.rect=rect;h.object:SetColorTexture(.19,.24,.29,1);h.object:Show()end
end
end
function self.render(world,alpha)
local logicalWidth=config.viewport.width or 960
local logicalHeight=config.viewport.height or 400
local scale=math.min(cache.canvas:GetWidth()/logicalWidth,cache.canvas:GetHeight()/logicalHeight)*self.camera.zoom
if scale<=0 then return end
local function place(object,x,y,w,h)
object:SetPoint("BOTTOMLEFT",cache.canvas,"BOTTOMLEFT",(x-self.camera.x)*scale,(y-self.camera.y)*scale)
object:SetSize(w*scale,h*scale)
end
self.drawn=0
local sceneActors=0
if cache.scene then cache.scene:SetSize(logicalWidth*scale,logicalHeight*scale)end
for _,h in ipairs(cache.terrain)do if h.active then local r=h.rect;place(h.object,r.x,r.y,r.w,r.h)end end
for i=1,#world.list do
local e=world.list[i];local h=e.view
if h and not e.removed then
local x=e.previousX+(e.x-e.previousX)*alpha
local y=e.previousY+(e.y-e.previousY)*alpha
local isModel=h.kind=="model"or h.kind=="scene_model"
local w=isModel and(e.visual.width or 64)or e.w
local height=isModel and(e.visual.height or 64)or e.h
if x+w>=self.camera.x and x-w<=self.camera.x+logicalWidth and y+height>=self.camera.y and y<=self.camera.y+logicalHeight then
h.object:Show()
if h.kind=="scene_model"then
sceneActors=sceneActors+1;h.object:SetPosition(0,(logicalWidth/2-x+self.camera.x)/12,(y-self.camera.y)/12)
else place(h.object,x-w/2,y,w,height)end
self.drawn=self.drawn+1
if isModel then
if not h.loaded and h.object.GetModelFileID then
local ok,id=pcall(h.object.GetModelFileID,h.object)
if ok and type(id)=="number"and id>0 then h.loaded=true;self.modelLoaded=self.modelLoaded+1 end
end
if e.animation~=h.animation and e.animation and h.object.SetAnimation then pcall(h.object.SetAnimation,h.object,e.animation);h.animation=e.animation end
end
else h.object:Hide()end
if e.healthView then
e.healthView.object:Show();place(e.healthView.object,x-e.w/2,y+height+3,math.max(.01,e.w*e.hp/e.maxHP),3)
end
if self.showBounds then
if not e.boundsView then e.boundsView=acquire(cache.bounds,function()return cache.overlay:CreateTexture(nil,"OVERLAY")end)end
if e.boundsView then e.boundsView.object:SetColorTexture(1,.25,.2,.22);e.boundsView.object:Show();place(e.boundsView.object,e.x-e.w/2,e.y,e.w,e.h)end
elseif e.boundsView then e.boundsView.object:Hide()end
end
end
if cache.scene then if sceneActors>0 then cache.scene:Show()else cache.scene:Hide()end end
end
function self.button(text,fn)
self.buttons=self.buttons+1;local n=self.buttons
if n>24 then G.error("UI button budget exceeded")end
local b=cache.buttons[n]
if not b then b=G.CreateFrame("Button",nil,f,"UIPanelButtonTemplate");cache.buttons[n]=b end
local columns,buttonWidth=8,(width-32)/8-4
b:ClearAllPoints();b:SetSize(buttonWidth,25)
b:SetPoint("TOPLEFT",14+((n-1)%columns)*(buttonWidth+4),-67-math.floor((n-1)/columns)*31)
b:SetText(text);b:Show();b:SetScript("OnClick",function()session.safe("ui",fn)end)
return b
end
function self.notify(text)cache.message:SetText(tostring(text):sub(1,600))end
function self.info(text)cache.info:SetText(text)end
function self.status(text)cache.status:SetText(text)end
function self.surface()
if not self.gameSurface then
self.gameSurface=E.newSurface(session,cache.canvas,cache.surface)
cache.surface=self.gameSurface.cache
end
return self.gameSurface
end
function self.scene3d(options)
if not self.gameScene3D then
self.gameScene3D=E.newWoWScene3D(session,cache.canvas,options,cache.scene3D)
cache.scene3D=self.gameScene3D.cache
end
return self.gameScene3D
end
function self.update()if self.gameSurface then self.gameSurface.update()end end
function self.showLog(text)
session.pause("log_viewer")
cache.logHeader:SetText("日志：Ctrl+A / Ctrl+C 复制为 .ndjson；当前游戏暂停。")
cache.apply:Hide();cache.apply:SetScript("OnClick",nil)
cache.logEdit:SetText(text or"暂无日志");cache.logFrame:Show();cache.logEdit:SetFocus();cache.logEdit:HighlightText()
end
function self.prompt(title,initial,callback)
session.pause("text_prompt");cache.logHeader:SetText(title)
cache.logEdit:SetText(initial or"");cache.logFrame:Show();cache.logEdit:SetFocus()
cache.apply:Show();cache.apply:SetScript("OnClick",function()
local text=cache.logEdit:GetText();cache.logEdit:ClearFocus();cache.logFrame:Hide()
cache.apply:Hide();cache.apply:SetScript("OnClick",nil);session.safe("prompt",callback,text)
end)
end
function self.stats()
local rects,models,loaded,actors=0,0,0,0
for _,h in ipairs(cache.rects)do if h.active then rects=rects+1 end end
for _,h in ipairs(cache.models)do if h.active then models=models+1;if h.loaded then loaded=loaded+1 end end end
for _,h in ipairs(cache.actors)do if h.active then actors=actors+1;if h.loaded then loaded=loaded+1 end end end
local result={visible=self.drawn,activeTextures=rects,activeModels=models+actors,activePlayerModels=models,activeActors=actors,loadedModels=loaded,
failedModels=self.modelFailed,pooledTextures=#cache.rects,pooledModels=#cache.models,
pooledTerrain=#cache.terrain,pooledBounds=#cache.bounds,pooledActors=#cache.actors,pooledHealthBars=#cache.health,createdRenderObjects=cache.created}
if self.gameSurface then for key,value in pairs(self.gameSurface.stats())do result[key]=value end end
if self.gameScene3D then for key,value in pairs(self.gameScene3D.stats())do result[key]=value end end
return result
end
function self.hide()
self.hiding=true
if cache.escapeProxy then cache.escapeProxy:Hide()end
f:SetScript("OnUpdate",nil);f:StopMovingOrSizing();f:Hide();self.hiding=false
end
function self.suspend()
self.hiding=true;f:StopMovingOrSizing();cache.logEdit:ClearFocus();cache.logFrame:Hide()
f:Hide();if cache.escapeProxy then cache.escapeProxy:Hide()end;self.hiding=false
end
function self.show()
f:Show();if cache.escapeProxy then cache.escapeProxy:Show()end
end
function self.dispose()
if cache.escapeProxy then cache.escapeProxy:SetScript("OnHide",nil);cache.escapeProxy:Hide()end
if self.gameSurface then self.gameSurface.dispose()end
if self.gameScene3D then self.gameScene3D.dispose()end
f:SetScript("OnUpdate",nil);f:SetScript("OnHide",nil)
f:SetScript("OnKeyDown",nil);f:SetScript("OnKeyUp",nil)
cache.close:SetScript("OnClick",nil)
cache.apply:SetScript("OnClick",nil);cache.apply:Hide()
for _,b in ipairs(cache.buttons)do b:Hide();b:SetScript("OnClick",nil)end
cache.logEdit:ClearFocus();cache.logEdit:SetText("");cache.logFrame:Hide();f:Hide()
if cache.scene then cache.scene:Hide()end
self.setTerrain({})
end
local escapeName="TRP3_ItemGameWindow"
if type(G.UISpecialFrames)=="table"then
if not cache.escapeProxy then
cache.escapeProxy=G.CreateFrame("Frame",nil,G.UIParent)
cache.escapeProxy:SetSize(1,1);cache.escapeProxy:EnableMouse(false)
end
cache.escapeProxy:SetScript("OnHide",function()
if session.stopping or self.hiding then return end
session.requestClose("escape")
if not session.stopping and f:IsShown()then cache.escapeProxy:Show()end
end)
cache.escapeProxy:Show();G[escapeName]=cache.escapeProxy
local registered=false
for _,name in ipairs(G.UISpecialFrames)do if name==escapeName then registered=true;break end end
if not registered then G.UISpecialFrames[#G.UISpecialFrames+1]=escapeName end
end
return self
end
end
end)();install(E,G)end
do local install=(function()
return function(E,G)
local pcall=G.pcall
function E.newInput(session)
local host,frame=session.host,session.view.frame
local self={mode="observe",down={},previous={},pressed={},blocked={},actionPress={},eventEdges={}}
local controls=session.content.controls or{left={"A","LEFT"},right={"D","RIGHT"},jump={"SPACE"},attack={"J"},fire={"K"}}
local keyActions={}
for action,keys in pairs(controls)do
for _,key in ipairs(keys)do keyActions[key]=keyActions[key]or{};keyActions[key][#keyActions[key]+1]=action end
end
function self.release()
self.mode="observe";self.down={};self.previous={};self.pressed={};self.actionPress={};self.blocked={};self.eventEdges={}
if frame.SetPropagateKeyboardInput then pcall(frame.SetPropagateKeyboardInput,frame,true)end
if frame.EnableKeyboard then pcall(frame.EnableKeyboard,frame,false)end
end
function self.acquire()
if not host.environment().allowed or host.textFocused()then return false,"input_context_blocked"end
if not frame.EnableKeyboard or not frame.SetPropagateKeyboardInput then return false,"keyboard_capture_unavailable"end
self.release()
local ok,err=pcall(frame.EnableKeyboard,frame,true)
if not ok then return false,tostring(err)end
ok,err=pcall(frame.SetPropagateKeyboardInput,frame,true)
if not ok then self.release();return false,tostring(err)end
self.mode="capture"
for key in pairs(keyActions)do self.blocked[key]=host.keyDown(key)==true end
return true
end
local function handle(key,down)
if session.stopping then return end
if key=="ESCAPE"and down and self.mode=="capture"then
session.requestClose("escape")
pcall(frame.SetPropagateKeyboardInput,frame,false);return
end
if self.mode=="capture"then pcall(frame.SetPropagateKeyboardInput,frame,keyActions[key]==nil or host.textFocused())end
if not keyActions[key]or host.textFocused()then return end
local was=self.down[key]
self.down[key]=down
if down and not was and not self.blocked[key]then
for _,action in ipairs(keyActions[key])do self.actionPress[action]=true end
self.eventEdges[key]=true;session.perf.increment("inputEdges")
end
if not down then self.blocked[key]=nil end
end
frame:SetScript("OnKeyDown",function(_,key)handle(key,true)end)
frame:SetScript("OnKeyUp",function(_,key)handle(key,false)end)
function self.poll()
if host.textFocused()then self.release();return end
if session.paused then return end
for key,actions in pairs(keyActions)do
local value=host.keyDown(key)
if value~=nil then self.down[key]=value end
if self.down[key]==false then self.blocked[key]=nil end
local active=self.down[key]==true and not self.blocked[key]
if active and not self.previous[key]and not self.eventEdges[key]then
for _,action in ipairs(actions)do self.actionPress[action]=true end
session.perf.increment("inputEdges")
end
self.previous[key]=active
end
self.eventEdges={}
end
function self.snapshot()
local held={}
for action,keys in pairs(controls)do
held[action]=false
for _,key in ipairs(keys)do if self.down[key]and not self.blocked[key]then held[action]=true end end
end
local out={
moveX=(held.right and 1 or 0)-(held.left and 1 or 0),
jumpPressed=self.actionPress.jump==true,attackPressed=self.actionPress.attack==true,
firePressed=self.actionPress.fire==true,attackHeld=held.attack==true,
held=held,pressed=E.util.copy(self.actionPress),
}
self.actionPress={};return out
end
function self.emitAction(action,phase)
if controls[action]==nil then return false,"unknown_action"end
if phase=="pressed"then self.actionPress[action]=true;return true end
return false,"only_engine_action_edges_supported"
end
function self.readKey(key)return host.keyDown(key)end
self.release()
return self
end
end
end)();install(E,G)end
do local install=(function()
return function(E,G)
local abs,min,max=math.abs,math.min,math.max
function E.overlap(a,b)return a.x<b.x+b.w and a.x+a.w>b.x and a.y<b.y+b.h and a.y+a.h>b.y end
function E.sweep(a,dx,dy,b)
if E.overlap(a,b)then return 0 end
local entry,exit=0,1
local function axis(p,size,delta,low,extent)
if delta==0 then return p+size>=low and p<=low+extent end
local first,last=(low-p-size)/delta,(low+extent-p)/delta
if first>last then first,last=last,first end
entry=max(entry,first);exit=min(exit,last)
return entry<=exit
end
if axis(a.x,a.w,dx,b.x,b.w)and axis(a.y,a.h,dy,b.y,b.h)and entry>=0 and entry<=1 then return entry end
return nil
end
function E.newWorld(session)
local self={list={},byId={},nextId=0,attackId=0,terrain={},mode="grid",gridDirty=true,grid={},usedCells={},queryStamp=0,queryBuffer={},candidateCount=0,contacts=0}
local data,events,perf=session.content,session.events,session.perf
local function updateBox(e)e.box.x=e.x-e.w/2;e.box.y=e.y;e.box.w=e.w;e.box.h=e.h end
function self.spawn(prefabId,position,overrides)
local def=data.prefabs[prefabId]
if not def then G.error("Unknown prefab: "..tostring(prefabId))end
if#self.list>=(data.limits.maxEntities or 1200)then G.error("entity budget exceeded")end
position=position or{x=0,y=0}
if not E.util.finite(position.x)or not E.util.finite(position.y)or abs(position.x)>100000 or abs(position.y)>100000 then G.error("invalid entity position")end
self.nextId=self.nextId+1
local e={id=self.nextId,prefabId=prefabId,x=position.x,y=position.y,previousX=position.x,previousY=position.y,
w=def.width or 16,h=def.height or 16,vx=def.vx or 0,vy=def.vy or 0,
hp=def.health or 100,maxHP=def.health or 100,role=def.role,faction=def.faction or"neutral",
motion=def.motion or"static",visual=def.visual or{},speed=def.speed or 180,
jumpSpeed=def.jumpSpeed or 330,gravity=def.gravity or 850,facing=1,intent={},box={},
ai=def.ai,ttl=def.ttl,spawnedAt=session.time,projectile=def.projectile==true,
damage=def.damage or 1,allowedActions=def.actions,invulnerability=def.invulnerability or.06,
animation=def.animation,wrap=def.wrap,removed=false,beforeBox={},sweepBox={}}
for _,k in ipairs({"vx","vy","faction","damage","sourceId","ttl"})do if overrides and overrides[k]~=nil then e[k]=overrides[k]end end
updateBox(e);self.list[#self.list+1]=e;self.byId[e.id]=e;self.gridDirty=true
local handle,reason=session.view.attach(e)
if not handle then perf.increment("renderAttachmentFailures");perf.note("capability",{feature="render",prefab=prefabId,reason=reason})end
return e.id
end
function self.despawn(id)
local e=self.byId[id];if not e or e.removed then return false end
e.removed=true;self.byId[id]=nil;self.gridDirty=true;session.view.detach(e);return true
end
function self.cleanup()
local n=1
for i=1,#self.list do local e=self.list[i];if not e.removed then self.list[n]=e;n=n+1 end end
for i=#self.list,n,-1 do self.list[i]=nil end
end
function self.clear()
for i=1,#self.list do self.despawn(self.list[i].id)end
self.list={};self.byId={};self.terrain={};self.grid={};self.usedCells={};self.queryBuffer={};self.gridDirty=true
session.view.setTerrain({})
end
function self.loadLevel(id)
local level=data.levels[id];if not level then G.error("Unknown level: "..tostring(id))end
self.clear();self.levelId=id;self.terrain=E.util.copy(level.terrain or{})
session.view.setTerrain(self.terrain)
for _,spawn in ipairs(level.spawns or{})do self.spawn(spawn.prefab,spawn)end
return true
end
function self.setIntent(id,intent)
local e=self.byId[id];if not e or e.hp<=0 then return false,"entity_unavailable"end
if intent.moveX~=nil then e.intent.moveX=E.util.clamp(tonumber(intent.moveX)or 0,-1,1)end
if intent.jumpPressed then e.intent.jumpPressed=true end
return true
end
function self.requestAction(id,actionId)
local e,def=self.byId[id],data.actions[actionId]
if not e or e.hp<=0 or e.removed then return false,"entity_unavailable"end
if not def then return false,"unknown_action"end
if e.allowedActions then
local allowed=false;for _,a in ipairs(e.allowedActions)do if a==actionId then allowed=true end end
if not allowed then return false,"action_not_allowed"end
end
if e.action then return false,"busy"end
self.attackId=self.attackId+1
e.action={id=self.attackId,def=def,start=session.time,last=session.time,hits={},active=false,box={}}
events.emit("combat.action",{sourceId=id,action=actionId,attackId=self.attackId,tick=session.tick})
return true
end
function self.updateAI()
local player
for i=1,#self.list do local e=self.list[i];if e.role=="player"and e.hp>0 then player=e;break end end
if not player then return end
for i=1,#self.list do
local e=self.list[i]
if e.ai and e.hp>0 and session.time>=(e.nextDecision or 0)then
e.nextDecision=session.time+(e.ai.interval or.2)
local dx=player.x-e.x;e.facing=dx>=0 and 1 or-1
self.setIntent(e.id,{moveX=abs(dx)>(e.ai.range or 48)and e.facing or 0})
if abs(dx)<=(e.ai.range or 48)and abs(player.y-e.y)<70 then self.requestAction(e.id,e.ai.action or"slash")end
perf.increment("aiDecisions")
end
end
end
function self.updateActions(dt)
local count=#self.list
for i=1,count do
local e,a=self.list[i],self.list[i].action
if a then
local age=session.time-a.start;local d=a.def
local activeFrom,activeTo=d.windup or 0,(d.windup or 0)+(d.active or.1)
a.active=age>=activeFrom and a.last-a.start<activeTo
if a.active and d.projectile and not a.fired then
a.fired=true
self.spawn(d.projectile,{x=e.x+e.facing*(e.w/2+12),y=e.y+e.h*.5},
{vx=e.facing*(d.projectileSpeed or 600),faction=e.faction,sourceId=e.id,damage=d.damage or 5})
end
a.finished=age>=activeTo+(d.recovery or.15)
a.last=session.time
end
end
end
function self.move(dt)
for i=1,#self.list do
local e=self.list[i]
e.previousX,e.previousY=e.x,e.y
if e.ttl and session.time-e.spawnedAt>=e.ttl then self.despawn(e.id)
elseif not e.removed then
if e.motion=="dynamic"and e.hp>0 then
local movement=e.intent.moveX or 0
if movement~=0 then e.facing=movement>0 and 1 or-1 end
e.vx=movement*e.speed+(e.knockbackX or 0)
e.knockbackX=(e.knockbackX or 0)*max(0,1-dt*10)
if e.intent.jumpPressed and e.grounded then e.vy=e.jumpSpeed;e.grounded=false end
e.intent.jumpPressed=false;e.vy=e.vy-e.gravity*dt
end
if e.motion~="static"then
local dx,dy=e.vx*dt,e.vy*dt
if e.motion=="dynamic"then
for _,r in ipairs(self.terrain)do
if e.y+e.h>r.y and e.y<r.y+r.h then
if dx>0 and e.x+e.w/2<=r.x and e.x+e.w/2+dx>=r.x then dx=min(dx,r.x-e.x-e.w/2)end
if dx<0 and e.x-e.w/2>=r.x+r.w and e.x-e.w/2+dx<=r.x+r.w then dx=max(dx,r.x+r.w-e.x+e.w/2)end
end
end
e.x=e.x+dx;e.grounded=false
for _,r in ipairs(self.terrain)do
if e.x+e.w/2>r.x and e.x-e.w/2<r.x+r.w then
if dy<=0 and e.y>=r.y+r.h-.001 and e.y+dy<=r.y+r.h then dy=max(dy,r.y+r.h-e.y);e.vy=0;e.grounded=true end
if dy>0 and e.y+e.h<=r.y and e.y+e.h+dy>=r.y then dy=min(dy,r.y-e.y-e.h);e.vy=0 end
end
end
e.y=e.y+dy
else e.x=e.x+dx;e.y=e.y+dy end
if e.wrap then
local width,height=data.viewport.width,data.viewport.height
if e.x<0 or e.x>width then e.x=e.x%width;e.previousX=e.x end
if e.y<25 or e.y>height-e.h then e.y=25+(e.y-25)%(height-e.h-25);e.previousY=e.y end
elseif e.x<-300 or e.x>data.viewport.width+300 or e.y<-300 then self.despawn(e.id)end
end
if e.x~=e.previousX or e.y~=e.previousY then self.gridDirty=true end
updateBox(e)
end
end
end
function self.rebuildGrid()
if not self.gridDirty then return end
self.gridDirty=false
for _,bucket in ipairs(self.usedCells)do bucket.n=0 end
self.usedCells={}
if self.mode=="naive"then return end
for _,e in ipairs(self.list)do
if not e.removed and not e.projectile and e.hp>0 then
local b=e.box
for x=math.floor(b.x/96),math.floor((b.x+b.w)/96)do
for y=math.floor(b.y/96),math.floor((b.y+b.h)/96)do
local key=x..":"..y
local bucket=self.grid[key]
if not bucket then bucket={n=0,values={}};self.grid[key]=bucket end
if bucket.n==0 then self.usedCells[#self.usedCells+1]=bucket end
bucket.n=bucket.n+1;bucket.values[bucket.n]=e
end
end
end
end
end
local function candidates(box)
self.queryStamp=self.queryStamp+1
local out,n=self.queryBuffer,0
local function add(e)
if not e.removed and not e.projectile and e.hp>0 and e.queryStamp~=self.queryStamp then
e.queryStamp=self.queryStamp;n=n+1;out[n]=e
end
end
if self.mode=="naive"then for _,e in ipairs(self.list)do add(e)end
else
for x=math.floor(box.x/96),math.floor((box.x+box.w)/96)do
for y=math.floor(box.y/96),math.floor((box.y+box.h)/96)do
local bucket=self.grid[x..":"..y]
if bucket then for i=1,bucket.n do add(bucket.values[i])end end
end
end
end
for i=#out,n+1,-1 do out[i]=nil end
self.candidateCount=self.candidateCount+n;return out
end
function self.query(box,faction)
self.rebuildGrid();local out={};local before=self.candidateCount
for _,e in ipairs(candidates(box))do if(not faction or e.faction==faction)and E.overlap(box,e.box)then out[#out+1]=e.id end end
perf.increment("queryCandidates",self.candidateCount-before)
return out
end
local function hit(source,target,damage,attackId)
if target.hp<=0 or session.time<(target.invUntil or 0)then return false end
target.hp=max(0,target.hp-damage);target.invUntil=session.time+target.invulnerability
target.knockbackX=((target.x>=source.x)and 1 or-1)*50
self.contacts=self.contacts+1;perf.increment("hits")
events.emit("combat.hit",{sourceId=source.sourceId or source.id,targetId=target.id,attackId=attackId,damage=damage,tick=session.tick})
if target.hp==0 then
target.vx,target.vy,target.action=0,0,nil
events.emit("entity.died",{sourceId=source.sourceId or source.id,targetId=target.id,attackId=attackId,tick=session.tick})
end
return true
end
function self.collide()
self.candidateCount=0;self.rebuildGrid()
for _,e in ipairs(self.list)do
if not e.removed then
if e.projectile then
local dx,dy=e.x-e.previousX,e.y-e.previousY
local before=e.beforeBox;before.x=e.previousX-e.w/2;before.y=e.previousY;before.w=e.w;before.h=e.h
local swept=e.sweepBox;swept.x=min(before.x,e.box.x);swept.y=min(before.y,e.box.y);swept.w=e.w+abs(dx);swept.h=e.h+abs(dy)
local first,earliest
for _,wall in ipairs(self.terrain)do local at=E.sweep(before,dx,dy,wall);if at and(not earliest or at<earliest)then earliest=at;first=nil end end
for _,target in ipairs(candidates(swept))do
if target.faction~=e.faction and target.faction~="neutral"and target.id~=e.sourceId then
local at=E.sweep(before,dx,dy,target.box)
if at and(not earliest or at<earliest)then first,earliest=target,at end
end
end
if earliest then if first then hit(e,first,e.damage,e.id)end;self.despawn(e.id)end
elseif e.action then
local a,d=e.action,e.action.def
if a.active and not d.projectile then
local box=a.box;box.w=d.width or 50;box.h=d.height or 36
box.x=e.x+(e.facing>0 and e.w/2 or-e.w/2-box.w);box.y=e.y+(d.offsetY or 0)
for _,target in ipairs(candidates(box))do
if target.id~=e.id and target.faction~=e.faction and target.faction~="neutral"and not a.hits[target.id]and E.overlap(box,target.box)then
if hit(e,target,d.damage or 10,a.id)then a.hits[target.id]=true end
end
end
end
if a.finished then e.action=nil end
end
end
end
perf.increment("collisionCandidates",self.candidateCount)
end
return self
end
end
end)();install(E,G)end
do local install=(function()
return function(E,G)
local pcall=G.pcall
function E.newSound(session)
local host,perf=session.host,session.perf
local self={enabled=true,playing={},last={},nextId=0,count=0,
limit=(session.content.limits or{}).maxSoundVoices or 12,peak=0,volume=1}
local buses=E.util.copy(session.content.soundBuses or{})
local groups,bySound,retryAt={},{},{}
local nextSweep=0
local function state(id,now)
local group=groups[id]
if not group then group={density=0,updated=now,nextAt=0,blockedUntil=0,active=0};groups[id]=group end
return group
end
local function admit(def,now)
local policy=def.group and(session.content.soundGroups or{})[def.group]
if not policy then return true end
local group=state(def.group,now)
group.density=group.density*math.exp(-(now-group.updated)/(policy.window or 1))+1;group.updated=now
if now<group.blockedUntil then return false,nil,nil,"ducked"end
if now<group.nextAt then return false,nil,nil,"interval"end
if group.active>=(policy.maxConcurrent or 1)then return false,nil,nil,"concurrency"end
return true,group,policy
end
function self.play(id,options)
options=options or{};local def=session.content.sounds[id]
if session.stopping then return nil,"stopped"end
if not self.enabled then return nil,"disabled"end
if not def then return nil,"unknown_sound"end
local requested=options.volume or 1
if not E.util.finite(requested)or requested<0 or requested>1 then return nil,"invalid_volume"end
local volume=self.volume*(def.volume or 1)*(def.bus and buses[def.bus]or 1)*requested
if volume==0 then perf.increment("soundVolumeMuted");return nil,"volume_zero"end
perf.increment("soundAttempts")
local now=host.now()
self.update(now)
if now<(retryAt[id]or 0)then perf.increment("soundRetryBackoff");return nil,"retry_backoff"end
if now-(self.last[id]or-100)<(def.cooldown or.08)then perf.increment("soundThrottled");return nil,"throttled"end
local allowed,group,policy,detail=admit(def,now)
if not allowed then
perf.increment("soundGroupMerged");perf.increment("soundGroup_"..detail);return nil,"group_merged",detail
end
if(bySound[id]or 0)>=(def.maxConcurrent or self.limit)then perf.increment("soundTypeBudgetDrops");return nil,"sound_budget"end
local victim,priority
if self.count>=self.limit then
for token,p in pairs(self.playing)do
local voicePriority=p.priority or 0
if not priority or voicePriority<priority or(voicePriority==priority and token<victim)then victim=token;priority=voicePriority end
end
if not victim or(def.priority or 0)<=priority then perf.increment("soundBudgetDrops");return nil,"voice_budget"end
end
perf.increment("soundRequests")
local handle,reason=host.playSound(def,volume)
if not handle then
retryAt[id]=now+.25;perf.increment("soundFailures")
perf.note("sound.failure",{sound=id,reason=reason,group=def.group});return nil,reason
end
if victim then self.stop(victim,60);perf.increment("soundPreemptions")end
self.last[id]=now;retryAt[id]=nil;perf.increment("soundStarted")
if group then group.nextAt=now+(policy.interval or.5)+math.min(policy.maxExtra or.6,group.density*(policy.densityStep or.025))end
for _,id in ipairs(def.duckGroups or{})do
local ducked=state(id,now)
ducked.blockedUntil=math.max(ducked.blockedUntil,now+(def.duckDuration or.8))
for token,voice in pairs(self.playing)do if voice.group==id then self.stop(token,80);perf.increment("soundDuckStops")end end
end
self.nextId=self.nextId+1
self.playing[self.nextId]={handle=handle,soundId=id,bus=def.bus,volume=volume,owner=options.owner,group=def.group,fadeMs=def.fadeMs or 0,
priority=def.priority or 0,expires=now+(def.maxDuration or 5)}
self.count=self.count+1;self.peak=math.max(self.peak,self.count)
bySound[id]=(bySound[id]or 0)+1
if group then group.active=group.active+1 end
return self.nextId
end
function self.stop(token,fadeMs)
local p=self.playing[token];if not p then return end
host.stopSound(p.handle,fadeMs or 0);self.playing[token]=nil;self.count=self.count-1
bySound[p.soundId]=bySound[p.soundId]-1
if p.group and groups[p.group]then groups[p.group].active=groups[p.group].active-1 end
end
function self.stopOwner(owner)
for token,p in pairs(self.playing)do if owner==nil or p.owner==owner then self.stop(token)end end
end
function self.update(now)
now=now or host.now()
if now<nextSweep then return end
nextSweep=now+.02
if self.count==0 then return end
perf.increment("soundSweeps")
for token,p in pairs(self.playing)do
if now>=p.expires then self.stop(token,p.fadeMs);perf.increment("soundTimeoutStops")
elseif host.soundPlaying(p.handle)==false then self.stop(token);perf.increment("soundFinished")end
end
end
function self.stats()
local active={};for id,g in pairs(groups)do if g.active>0 then active[id]=g.active end end
return{soundVoices=self.count,soundVoiceLimit=self.limit,peakSoundVoices=self.peak,soundGroups=active,soundVolume=self.volume,soundBusVolumes=E.util.copy(buses)}
end
function self.capabilities()return{volume=host.soundVolumeSupported and host.soundVolumeSupported()or false,volumeAppliesTo="new_voices"}end
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
function self.setEnabled(enabled)self.enabled=enabled==true;if not self.enabled then self.stopOwner()end end
return self
end
function E.newMusic(session)
local host,perf=session.host,session.perf
local self={enabled=true,backend="silent",state="stopped",generation=0,loop=false,
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
return self.preference~="native"and def and def.musicianCode and musicianAvailable()and"musician"or"native"
end
local function nativeSource(def)
if not def or not def.nativeFileId then return nil end
return{kind="fileID",id=def.nativeFileId,channel=def.channel or"SFX",
volumeSoundKitID=def.volumeSoundKitID,baseVolume=def.baseVolume}
end
function self.capabilities(id)
local def=id and session.content.music[id]or self.definition
local selected=preferred(def)
if not def and self.preference=="auto"and musicianAvailable()then selected="musician"end
if def==self.definition and self.state~="stopped"and self.backend~="silent"then selected=self.backend end
local source=nativeSource(def)
local volumeSupported=selected=="native"and(id==nil or def~=nil)and
host.soundVolumeSupported~=nil and host.soundVolumeSupported(source)or false
return{native=G.PlaySoundFile~=nil,musician=musicianAvailable(),selectedBackend=selected,
preferredBackend=preferred(def),localOnly=true,independentVolume=volumeSupported,
nativeDefaultChannel="SFX",nativePauseMode="restart",
pauseMode=selected=="musician"and"resume"or"restart",
volumeChangeMode=selected=="musician"and"mute_only"or"restart",
seek=self.song~=nil and type(self.song.Seek)=="function"}
end
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
self.channel=def and def.channel or"SFX"
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
if volume==0 and self.state=="playing"then
if self.song then songCall(self.song.Stop,self.song)end
state("musician","muted")
elseif volume>0 and self.state=="muted"then startSong()end
changed();return true
end
if self.backend=="native"and(self.state=="playing"or self.state=="muted")then
if self.handle then host.stopSound(self.handle);self.handle=nil end
local ok,why=native(self.definition);changed();return ok,why
end
changed();return true
end
function self.play(id,options)
options=options or{}
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
if not ok or(type(count)=="number"and count>0)then return fallback("musician_busy",false)end
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
if type(code)~="string"or#code==0 or#code>150000 then return false,"music_code_size_limit"end
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
end)();install(E,G)end
do local install=(function()
return function(E,G)
local floor,max,min=math.floor,math.max,math.min
local cos,sin,pi=math.cos,math.sin,math.pi
local pcall=G.pcall
local DEG=pi/180
local UL,LL,UR,LR=G.UPPER_LEFT_VERTEX or 1,G.LOWER_LEFT_VERTEX or 2,G.UPPER_RIGHT_VERTEX or 3,G.LOWER_RIGHT_VERTEX or 4
local LAYER_STRIDE,PARTICLE_OFFSET=288,160
local function range(value,random,fallback)
if value==nil then return fallback end
if type(value)=="table"then
local a,b=value[1],value[2]or value[1]
return a+(b-a)*random()
end
return value
end
local function color(value,fallback,out)
value=value or fallback
out=out or{}
out[1],out[2],out[3],out[4]=value[1],value[2],value[3],value[4]==nil and 1 or value[4]
return out
end
local function seedValue(value)
local text=tostring(value or 1)
local seed=1
for i=1,#text do seed=(seed*131+text:byte(i))%2147483647 end
return max(1,seed)
end
local function newRandom(seed)
local state=seedValue(seed)
return function()
state=(state*48271)%2147483647
return state/2147483647
end
end
function E.newEffects(session,view)
local content=session.content
local definitions=content.effects or{}
local limits=content.limits or{}
local capacity=limits.maxParticles or 128
local emitterCapacity=limits.maxEmitters or 24
local spawnStepCapacity=limits.maxParticleSpawnsPerStep or 32
local width,height=content.viewport.width,content.viewport.height
local assets=(content.assets or{}).textures or{}
local cache=E.effectsViewCache
if not cache then
local root=G.CreateFrame("Frame",nil,view.canvas)
cache={root=root,layers={},pool={},created=0}
E.effectsViewCache=cache
end
local root=cache.root
root:SetParent(view.canvas);root:ClearAllPoints();root:SetPoint("TOPLEFT",view.canvas,"TOPLEFT",0,0)
root:SetSize(width,height);root:EnableMouse(false);root:Show()
if root.SetClipsChildren then root:SetClipsChildren(false)end
local particles,emitters,counts,free={},{},{},{}
for i=#cache.pool,1,-1 do free[#free+1]=cache.pool[i]end
local sequence,nextEmitter=0,0
local spawned,dropped,evicted,peak,visibleCount=0,0,0,0,0
local budgetTick,budgetFrame,stepSpawns,frameSpawns=-1,-1,0,0
local lastScale
local unavailable={}
local self={particles=particles,emitters=emitters}
local function optional(object,method,...)
if object and object[method]then return pcall(object[method],object,...)end
return false
end
local function layer(z)
local frame=cache.layers[z]
if not frame then
frame=G.CreateFrame("Frame",nil,root)
frame:SetAllPoints(root);frame:EnableMouse(false)
cache.layers[z]=frame
end
local level=root:GetFrameLevel()+z*LAYER_STRIDE+PARTICLE_OFFSET
if frame:GetFrameLevel()~=level then frame:SetFrameLevel(level)end
if not frame:IsShown()then frame:Show()end
return frame
end
local function acquire(z)
local handle=free[#free];free[#free]=nil
if not handle then
if#cache.pool>=512 then return nil end
local frame=G.CreateFrame("Frame",nil,layer(z))
frame:EnableMouse(false)
local texture=frame:CreateTexture(nil,"ARTWORK")
texture:SetAllPoints(frame)
handle={frame=frame,texture=texture,particle={},rotate=texture.SetRotation}
cache.pool[#cache.pool+1]=handle;cache.created=cache.created+1
optional(texture,"SetSnapToPixelGrid",false)
optional(texture,"SetTexelSnappingBias",0)
end
local parent=layer(z)
handle.active=true;handle.visible=false;handle.parent=parent;handle.frame:SetParent(parent)
handle.frame:SetFrameLevel(parent:GetFrameLevel()+1)
handle.frame:ClearAllPoints();handle.frame:Hide();handle.texture:Show()
handle.x,handle.y,handle.size,handle.rotation,handle.alpha=nil,nil,nil,nil,nil
return handle
end
local function configure(handle,effect)
local asset=assets[effect.texture]
if not asset then return false end
local signature=effect.texture..":"..tostring(effect.blend or"BLEND")..":"..(effect.shape or"sprite")
if handle.signature==signature then return true end
local ok,result
if asset.kind=="atlas"and handle.texture.SetAtlas then
ok,result=pcall(handle.texture.SetAtlas,handle.texture,asset.atlas,false)
else
ok,result=pcall(handle.texture.SetTexture,handle.texture,asset.id or asset.path,"CLAMP","CLAMP")
end
if not ok or result==false then
if not unavailable[effect.texture]then
unavailable[effect.texture]=true
session.perf.note("particle.asset_unavailable",{asset=effect.texture})
end
pcall(handle.texture.SetTexture,handle.texture,asset.fallbackPath or"Interface\\Cooldown\\star4","CLAMP","CLAMP")
end
handle.texture:SetBlendMode(effect.blend or"BLEND")
if handle.facet then handle.facet:Hide()end
if handle.crystal and handle.texture.SetVertexOffset then
for _,vertex in ipairs({UL,LL,UR,LR})do handle.texture:SetVertexOffset(vertex,0,0)end
end
handle.crystal=effect.shape=="crystal"and handle.texture.SetVertexOffset~=nil
if handle.crystal then
if not handle.facet then handle.facet=handle.frame:CreateTexture(nil,"ARTWORK");handle.facet:SetAllPoints(handle.frame)end
handle.facet:SetTexture(asset.id or asset.path,"CLAMP","CLAMP")
handle.facet:SetBlendMode(effect.blend or"BLEND");handle.facet:Show()
if handle.rotate then handle.rotate(handle.texture,0)end
end
if handle.maskApplied then handle.texture:RemoveMaskTexture(handle.mask);handle.maskApplied=false end
if asset.maskPath and handle.frame.CreateMaskTexture then
if not handle.mask then handle.mask=handle.frame:CreateMaskTexture(nil,"ARTWORK");handle.mask:SetAllPoints(handle.texture)end
handle.mask:SetTexture(asset.maskPath,"CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
handle.texture:AddMaskTexture(handle.mask);handle.maskApplied=true
end
if asset.kind~="atlas"then handle.texture:SetTexCoord(0,1,0,1)end
handle.signature=signature;handle.cell=nil;handle.atlas=asset.kind=="atlas"
return true
end
local function releaseAt(index)
local particle=particles[index]
if not particle then return end
counts[particle.effectId]=max(0,(counts[particle.effectId]or 1)-1)
if particle.handle then
particle.handle.frame:Hide();particle.handle.texture:Hide()
particle.handle.active=false;particle.handle.visible=false
free[#free+1]=particle.handle;particle.handle=nil
end
particles[index]=particles[#particles];particles[#particles]=nil
end
local function noteDropped(amount)
amount=amount or 1;dropped=dropped+amount
session.perf.increment("particlesDropped",amount)
end
local function makeRoom(priority)
if#particles<capacity then return true end
local candidate,candidatePriority,candidateBirth
for i=1,#particles do
local particle=particles[i]
if not candidatePriority or particle.priority<candidatePriority or
(particle.priority==candidatePriority and particle.birth<candidateBirth)then
candidate,candidatePriority,candidateBirth=i,particle.priority,particle.birth
end
end
if candidate and priority>candidatePriority then
releaseAt(candidate);evicted=evicted+1;session.perf.increment("particlesEvicted");return true
end
noteDropped();return false
end
local function resolveOrigin(params,fallbackSpace)
params=params or{}
local space=params.space or fallbackSpace or"screen"
local x,y=params.x or 0,params.y or 0
if params.entityId then
local entity=session.world and session.world.byId[params.entityId]
if not entity or entity.removed then return nil,nil,nil,"entity_unavailable"end
x=entity.x+(params.x or 0);y=entity.y+(params.y or 0);space="world"
end
if not E.util.finite(x)or not E.util.finite(y)or(space~="screen"and space~="world")then
return nil,nil,nil,"invalid_origin"
end
return x,y,space
end
local function validateParams(params)
if type(params)~="table"then return false,"invalid_params"end
for _,key in ipairs({"x","y"})do if params[key]~=nil and(not E.util.finite(params[key])or math.abs(params[key])>100000)then return false,"invalid_origin"end end
if params.layer~=nil and(not E.util.finite(params.layer)or params.layer<0 or params.layer>30 or params.layer~=floor(params.layer))then return false,"invalid_layer"end
if params.scale~=nil and(not E.util.finite(params.scale)or params.scale<=0 or params.scale>20)then return false,"invalid_scale"end
if params.facing~=nil and params.facing~=1 and params.facing~=-1 then return false,"invalid_facing"end
if params.color~=nil then
if type(params.color)~="table"then return false,"invalid_color"end
for i=1,4 do if not E.util.finite(params.color[i])or params.color[i]<0 or params.color[i]>1 then return false,"invalid_color"end end
end
return true
end
local function spawnOne(effectId,effect,params,random,emitterId,originX,originY,space)
if budgetTick~=session.tick then budgetTick=session.tick;stepSpawns=0 end
if budgetFrame~=session.frameSerial then budgetFrame=session.frameSerial;frameSpawns=0 end
if stepSpawns>=spawnStepCapacity or frameSpawns>=spawnStepCapacity*2 then noteDropped();return false end
local priority=effect.priority or 0
if effect.maxAlive and(counts[effectId]or 0)>=effect.maxAlive then noteDropped();return false end
if not makeRoom(priority)then return false end
local z=params.layer or effect.layer or 0
local handle=acquire(z)
if not handle then noteDropped();return false end
if not configure(handle,effect)then handle.active=false;handle.frame:Hide();free[#free+1]=handle;noteDropped();return false end
local direction=range(effect.directionDeg,random,0)
local spread=range(effect.spreadDeg,random,0)
direction=(direction+(random()-.5)*spread)*DEG
local speed=range(effect.speed,random,0)
local facing=params.facing==-1 and-1 or 1
local vx=cos(direction)*speed*facing
local vy=sin(direction)*speed
if space=="screen"then vy=-vy end
local gravity=range(effect.gravity,random,0)
local rawSize=range(effect.startSize,random,8)
local startSize=rawSize*(params.scale or 1)
local endSize=range(effect.endSize,random,rawSize)*(params.scale or 1)
local particle=handle.particle
local startColor=color(params.color or effect.startColor,{1,1,1,1},particle.startColor)
local endColor=color(params.color or effect.endColor,startColor,particle.endColor)
local startAlpha=range(effect.startAlpha,random,1)
local endAlpha=range(effect.endAlpha,random,0)
local x=originX+range(effect.offsetX,random,0)*facing
local y=originY+range(effect.offsetY,random,0)
sequence=sequence+1
particle.effectId,particle.effect,particle.emitterId,particle.handle=effectId,effect,emitterId,handle
particle.x,particle.y,particle.previousX,particle.previousY,particle.vx,particle.vy=x,y,x,y,vx,vy
particle.gravity,particle.wind,particle.drag=gravity,range(effect.wind,random,0),range(effect.drag,random,0)
particle.age=-range(effect.delay,random,0);particle.previousAge=particle.age;particle.life=range(effect.lifetime,random,.5)
particle.startSize,particle.endSize,particle.startColor,particle.endColor=startSize,endSize,startColor,endColor
particle.startAlpha,particle.endAlpha=startAlpha,endAlpha
particle.rotation,particle.spin=range(effect.startRotationDeg,random,0)*DEG,range(effect.spinDeg,random,0)*DEG
if effect.alignToVelocity then particle.rotation=particle.rotation+(facing==-1 and pi-direction or direction)-pi/2 end
particle.space,particle.layer,particle.layerFrame,particle.priority,particle.birth=space,z,handle.parent,priority,sequence
particle.aspect=effect.aspectRatio or 1;particle.fadeIn=effect.fadeIn or 0
particle.previousRotation=particle.rotation
particles[#particles+1]=particle
counts[effectId]=(counts[effectId]or 0)+1
stepSpawns=stepSpawns+1;frameSpawns=frameSpawns+1;peak=max(peak,#particles)
spawned=spawned+1;session.perf.increment("particlesSpawned")
return true
end
local function spawnMany(effectId,effect,params,count,random,emitterId,x,y,space)
local made=0
for _=1,count do if spawnOne(effectId,effect,params,random,emitterId,x,y,space)then made=made+1 end end
return made
end
function self.burst(effectId,params)
if session.stopping then return nil,"stopped"end
local effect=definitions[effectId]
if not effect then return nil,"unknown_effect"end
params=params or{}
local valid,invalid=validateParams(params);if not valid then return nil,invalid end
local x,y,space,why=resolveOrigin(params,effect.space)
if not x then return nil,why end
local count=params.count or effect.count or effect.initialBurst or 1
if not E.util.finite(count)or count<1 or count>128 or count~=floor(count)then return nil,"invalid_count"end
local before=dropped
local random=newRandom(params.seed or(session.tick..":"..effectId..":"..(sequence+1)))
local made=spawnMany(effectId,effect,params,count,random,nil,x,y,space)
return made,dropped-before
end
local function removeEmitterAt(index)
emitters[index]=emitters[#emitters];emitters[#emitters]=nil
end
function self.start(effectId,params)
if session.stopping then return nil,"stopped"end
local effect=definitions[effectId]
if not effect then return nil,"unknown_effect"end
if effect.mode~="continuous"then return nil,"effect_not_continuous"end
if#emitters>=emitterCapacity then return nil,"emitter_budget_exceeded"end
params=params or{}
local valid,invalid=validateParams(params);if not valid then return nil,invalid end
local x,y,space,why=resolveOrigin(params,effect.space)
if not x then return nil,why end
local rate=params.rate or effect.rate
local duration=params.duration
if duration==nil then duration=effect.duration end
if not E.util.finite(rate)or rate<=0 or rate>512 then return nil,"invalid_rate"end
if duration~=nil and(not E.util.finite(duration)or duration<=0 or duration>3600)then return nil,"invalid_duration"end
nextEmitter=nextEmitter+1
local emitter={id=nextEmitter,effectId=effectId,effect=effect,params=params,
rate=rate,duration=duration,age=0,accumulator=0,
random=newRandom(params.seed or(session.tick..":emitter:"..nextEmitter)),x=x,y=y,space=space}
emitters[#emitters+1]=emitter
local initial=params.initialBurst
if initial==nil then initial=effect.initialBurst or 0 end
if E.util.finite(initial)and initial>0 and initial<=128 and initial==floor(initial)then
spawnMany(effectId,effect,params,initial,emitter.random,emitter.id,x,y,space)
end
return emitter.id
end
function self.stop(emitterId,immediate)
local found=false
for i=#emitters,1,-1 do
if emitters[i].id==emitterId then removeEmitterAt(i);found=true;break end
end
if immediate then
for i=#particles,1,-1 do if particles[i].emitterId==emitterId then releaseAt(i)end end
end
return found
end
function self.clear()
for i=#particles,1,-1 do releaseAt(i)end
for i=#emitters,1,-1 do emitters[i]=nil end
visibleCount=0
end
function self.update(dt)
if session.stopping then return end
for i=#particles,1,-1 do
local particle=particles[i]
particle.previousX,particle.previousY=particle.x,particle.y
particle.previousAge,particle.previousRotation=particle.age,particle.rotation
particle.age=particle.age+dt
if particle.age>=particle.life then
releaseAt(i)
elseif particle.age>0 then
local activeDt=min(dt,particle.age)
local damping=max(0,1-particle.drag*activeDt)
particle.vx=(particle.vx+particle.wind*activeDt)*damping
local gravity=particle.space=="screen"and particle.gravity or-particle.gravity
particle.vy=(particle.vy+gravity*activeDt)*damping
particle.x=particle.x+particle.vx*activeDt
particle.y=particle.y+particle.vy*activeDt
particle.rotation=particle.rotation+particle.spin*activeDt
end
end
for i=#emitters,1,-1 do
local emitter=emitters[i]
local emitDt=emitter.duration and min(dt,max(0,emitter.duration-emitter.age))or dt
emitter.age=emitter.age+dt
local x,y,space=resolveOrigin(emitter.params,emitter.effect.space)
if not x then
removeEmitterAt(i)
else
emitter.x,emitter.y,emitter.space=x,y,space
emitter.accumulator=emitter.accumulator+emitter.rate*emitDt
local count=floor(emitter.accumulator)
if count>0 then
emitter.accumulator=emitter.accumulator-count
if count>spawnStepCapacity then noteDropped(count-spawnStepCapacity);count=spawnStepCapacity end
spawnMany(emitter.effectId,emitter.effect,emitter.params,count,emitter.random,emitter.id,x,y,space)
end
if emitter.duration and emitter.age>=emitter.duration then removeEmitterAt(i)end
end
end
end
local function mix(a,b,t)return a+(b-a)*t end
local function crystal(handle,w,h,rotation)
local c,s=cos(rotation),sin(rotation)
local tx,ty=-s*h*.5,c*h*.5
local lx,ly=-c*w*.5,-s*w*.5
local rx,ry=-lx,-ly
local bx,by=-tx,-ty
local left,right=handle.texture,handle.facet
left:SetVertexOffset(UL,tx+w*.5,ty-h*.5)
left:SetVertexOffset(LL,lx+w*.5,ly+h*.5)
left:SetVertexOffset(UR,tx-w*.5,ty-h*.5)
left:SetVertexOffset(LR,bx-w*.5,by+h*.5)
right:SetVertexOffset(UL,tx+w*.5,ty-h*.5)
right:SetVertexOffset(LL,bx+w*.5,by+h*.5)
right:SetVertexOffset(UR,rx-w*.5,ry-h*.5)
right:SetVertexOffset(LR,bx-w*.5,by+h*.5)
end
function self.render(alpha)
if session.stopping then return end
visibleCount=0
if#particles==0 then return end
local canvasHeight=view.canvas:GetHeight()
local scale=max(.1,min(view.canvas:GetWidth()/width,canvasHeight/height))
local displayHeight=canvasHeight/scale
if lastScale~=scale then root:SetScale(scale);lastScale=scale end
local camera=view.camera or{x=0,y=0,zoom=1}
for i=1,#particles do
local particle=particles[i]
local age=mix(particle.previousAge,particle.age,alpha)
local progress=E.util.clamp(age/particle.life,0,1)
local x=mix(particle.previousX,particle.x,alpha)
local y=mix(particle.previousY,particle.y,alpha)
local size=mix(particle.startSize,particle.endSize,progress)
if particle.space=="world"then
x=(x-camera.x)*camera.zoom
y=displayHeight-(y-camera.y)*camera.zoom
size=size*camera.zoom
end
local handle=particle.handle
local radius=size*max(1,particle.aspect)
local visible=age>=0 and x+radius>=0 and x-radius<=width and y+radius>=0 and y-radius<=displayHeight
if visible then
visibleCount=visibleCount+1
if handle.x~=x or handle.y~=y then handle.frame:SetPoint("CENTER",particle.layerFrame,"TOPLEFT",x,-y);handle.x,handle.y=x,y end
if handle.size~=size then handle.frame:SetSize(max(.01,size*particle.aspect),max(.01,size));handle.size=size end
local c0,c1=particle.startColor,particle.endColor
local a=mix(particle.startAlpha,particle.endAlpha,progress)*mix(c0[4],c1[4],progress)
if particle.fadeIn>0 then a=a*min(1,age/particle.fadeIn)end
local r,g,b=mix(c0[1],c1[1],progress),mix(c0[2],c1[2],progress),mix(c0[3],c1[3],progress)
handle.texture:SetVertexColor(r,g,b,a)
local rotation=mix(particle.previousRotation,particle.rotation,alpha)
if handle.crystal then
crystal(handle,size*particle.aspect,size,rotation)
handle.facet:SetVertexColor(min(1,r*.45+.55),min(1,g*.45+.55),min(1,b*.45+.55),a)
elseif handle.rotate and handle.rotation~=rotation then handle.rotate(handle.texture,rotation);handle.rotation=rotation end
local flipbook=particle.effect.flipbook
if flipbook then
local frame=floor(age*flipbook.fps)%flipbook.frames
if handle.cell~=frame then
local column,row=frame%flipbook.columns,floor(frame/flipbook.columns)
handle.texture:SetTexCoord(column/flipbook.columns,(column+1)/flipbook.columns,
row/flipbook.rows,(row+1)/flipbook.rows)
handle.cell=frame
end
elseif handle.cell~=nil and not handle.atlas then handle.texture:SetTexCoord(0,1,0,1);handle.cell=nil end
if not handle.visible then handle.frame:Show();handle.texture:Show();handle.visible=true end
else
if handle.visible then handle.frame:Hide();handle.visible=false end
end
end
end
function self.stats()
return{activeParticles=#particles,activeEmitters=#emitters,
pooledParticles=#cache.pool,particleCapacity=capacity,
spawnedParticles=spawned,droppedParticles=dropped,evictedParticles=evicted,
peakParticles=peak,visibleParticles=visibleCount}
end
function self.dispose()
self.clear();root:Hide()
for _,frame in pairs(cache.layers)do frame:Hide()end
end
return self
end
end
end)();install(E,G)end
do local install=(function()
return function(E,G)
local pcall,error=G.pcall,G.error
E.games,E.lastLogs={},{}
function E.registerGame(id,definition)
if type(id)~="string"or type(definition.create)~="function"or definition.apiVersion~=E.API_VERSION then error("incompatible game definition")end
E.games[id]=definition
end
function E.start(host,manifest,content,viewFactory)
local initialEnvironment=host.environment()
if not initialEnvironment.allowed then return nil,initialEnvironment.reason end
if E.current and not E.current.stopping and not E.current.host.definitionChanged()and E.current.host.item==host.item and E.current.manifest.objectVersion==manifest.objectVersion then
if E.current.view.show then E.current.view.show()else E.current.view.frame:Show()end
return E.current
end
if E.current then E.current.stop("switch_game")end
local env=host.environment()
if not env.allowed then return nil,env.reason end
local owned,reason=host.owned();if not owned then return nil,reason end
local definition=E.games[manifest.gameId]
if not definition then return nil,"game_not_registered"end
local s={host=host,manifest=manifest,content=content,scope=E.newScope(),time=0,tick=0,
accumulator=0,speed=1,fixed=1/(content.simulationHz or 60),tasks={},nextTask=0,paused=false,stopping=false,
savePending=nil,revision=0,operations={},callbacks={},previousLog=host.read("IG_PERF_LOG_V1")or E.lastLogs[manifest.rootId],
id=manifest.gameId..":"..tostring(host.now()),nextWatch=0,nextHUD=0}
local metadata=host.metadata()
metadata.engineVersion=E.VERSION;metadata.gameId=manifest.gameId;metadata.rootId=manifest.rootId
metadata.objectVersion=manifest.objectVersion;metadata.sourceHash=manifest.sourceHash
metadata.releaseVersion=manifest.releaseVersion;metadata.simulationHz=content.simulationHz or 60
local logPolicy=manifest.logPolicy or{persist="auto",maxBytes=190000}
s.perf=E.newTelemetry(host,metadata,logPolicy)
function s.stats()
local out=s.view and s.view.stats()or{}
out.entities=s.world and#s.world.list or 0;out.scheduledTasks=#s.tasks
if s.effects then for key,value in pairs(s.effects.stats())do out[key]=value end end
out.soundVoices=s.sound and s.sound.count or 0;out.musicBackend=s.music and s.music.backend or"silent"
if s.sound then for key,value in pairs(s.sound.stats())do out[key]=value end end
out.musicState=s.music and s.music.state or"stopped"
out.musicChannel=s.music and s.music.channel;out.musicError=s.music and s.music.lastError
out.inputMode=s.input and s.input.mode or"none";return out
end
function s.saveLog()
local text=s.perf.export();E.lastLogs[manifest.rootId]=text
local start=host.profileMS();local ok,why=host.write("IG_PERF_LOG_V1",text)
s.perf.note("log.persist",{ok=ok,reason=why,bytes=#text,milliseconds=host.profileMS()-start})
return ok,why
end
function s.autoSaveLog()
if logPolicy.persist~="manual"then return s.saveLog()end
end
function s.fail(stage,message)
if s.stopping then return end
s.perf.note("error",{stage=stage,message=tostring(message):sub(1,3000)})
s.perf.finish("failed",s.stats());s.stop("script_error",{save=false})
if G.print then G.print("TRP3 游戏停止："..tostring(message))end
end
function s.safe(stage,fn,...)
if s.stopping then return false end
if not fn then return true end
local ok,a,b=pcall(fn,...)
if not ok then s.fail(stage,a)end
return ok,a,b
end
local gameState={}
local function decodeSave(raw)
if raw==nil or raw==""or raw=="nil"then return nil end
local ok,saved=pcall(E.JSON.decode,raw,220000)
if not ok or type(saved)~="table"then return nil,"invalid_save"end
if saved.gameId~=manifest.gameId then return nil,"save_game_mismatch"end
if saved.schemaVersion~=1 then return nil,"save_format_version_mismatch"end
if saved.gameSaveVersion~=definition.saveVersion then return nil,"save_version_mismatch"end
if type(saved.game)~="table"or type(saved.operations or{})~="table"then return nil,"invalid_save"end
return saved
end
local raw=host.read("IG_SAVE_V1")
local saved,saveError=decodeSave(raw)
if saveError then
if saveError~="invalid_save"then return nil,saveError..": save preserved; migration required"end
local backup=host.read("IG_SAVE_BACKUP_V1");local recovered=decodeSave(backup)
if not recovered then return nil,saveError..": keep item data and inspect the backup"end
saved,raw=recovered,backup;s.perf.note("save.recovered",{reason=saveError})
end
if saved then gameState=saved.game;s.operations=saved.operations or{};s.revision=saved.revision or 0;s.lastGoodRaw=raw end
function s.save(reason)
if s.saving then return false,"save_reentrant"end
local allowed,why=host.owned();if not allowed then return false,why end
s.saving=true;local start=host.profileMS()
local ok,state=true,gameState
if s.callbacks.onSave then ok,state=pcall(s.callbacks.onSave)end
if not ok or type(state)~="table"then s.saving=false;return false,"game_save_failed: "..tostring(state)end
local success,text=pcall(E.JSON.encode,{schemaVersion=1,gameSaveVersion=definition.saveVersion,
gameId=manifest.gameId,revision=s.revision+1,game=state,operations=s.operations})
if not success or#text>200000 then s.saving=false;return false,"save_encode_or_size_failed"end
if s.lastGoodRaw then
local backed,backupError=host.write("IG_SAVE_BACKUP_V1",s.lastGoodRaw)
if not backed then s.saving=false;return false,backupError end
end
local written,writeError=host.write("IG_SAVE_V1",text)
if written then s.lastGoodRaw=text;s.revision=s.revision+1;gameState=E.util.copy(state)end
s.saving=false
s.perf.note("save.write",{reason=reason,ok=written,error=writeError,bytes=#text,milliseconds=host.profileMS()-start,revision=s.revision})
return written,writeError
end
function s.stop(reason,options)
if s.stopping then return end
s.stopping=true;s.stopReason=reason;options=options or{}
local failures={};s.cleanupErrors=failures
local function clean(stage,fn,...)
if not fn then return true end
local ok,a,b=pcall(fn,...)
if not ok then
local message=tostring(a):sub(1,1000)
failures[#failures+1]={stage=stage,message=message}
pcall(s.perf.note,"error",{stage="cleanup."..stage,message=message})
end
return ok,a,b
end
if s.input then clean("input",s.input.release)end
if s.view then clean("hide",s.view.hide)end
clean("phase",function()s.perf.finish("stopped",s.stats())end)
if s.effects then clean("effects",s.effects.dispose)end
if s.sound then clean("sound",s.sound.stopOwner)end
if s.music then clean("music",s.music.stop,reason)end
if options.save~=false and s.started then
local called,ok,why=clean("save",s.save,reason)
if called and not ok then clean("save_status",s.perf.note,"save.skipped",{reason=why})end
end
clean("onStop",s.callbacks.onStop,reason)
s.tasks={};if s.events then clean("events",s.events.close)end
if s.world then clean("world",s.world.clear)end
clean("scope",s.scope.dispose);if s.view then clean("view",s.view.dispose)end
if E.current==s then E.current=nil end
clean("stats",function()s.perf.note("cleanup",s.stats())end)
clean("log_close",s.perf.close,reason)
clean("log_save",s.autoSaveLog)
clean("log_export",function()E.lastLogs[manifest.rootId]=s.perf.export()end)
s.closed=true
if reason=="definition_changed"then
local message="[IG STOP] 道具定义在运行中发生变化，已关闭；请重新使用道具。"
if G.print then pcall(G.print,message)end
pcall(host.write,"IG_BOOT_STATUS_V1",message)
end
if#failures>0 and G.print then pcall(G.print,"[IG CLOSE] 界面已关闭；清理异常 "..#failures.." 项，请保留日志。")end
end
function s.pause(reason)
if s.stopping or s.paused then return end
s.captureBeforePause=s.input and s.input.mode=="capture"
s.paused=true;s.accumulator=0
s.perf.finish("paused",s.stats())
if s.input then s.input.release()end
if s.scene3d then s.scene3d.cancelPointer()end
if s.sound then s.sound.stopOwner()end
if s.music then pcall(s.music.pause)end
s.perf.note("runtime.pause",{reason=reason})
s.safe("onPause",s.callbacks.onPause,reason)
end
function s.requestClose(reason)
if s.stopping then return false end
if s.callbacks.onCloseRequested then return s.safe("onCloseRequested",s.callbacks.onCloseRequested,reason)end
s.stop(reason);return true
end
function s.resume()
if s.stopping then return false,"stopped"end
local state=host.environment();local present,why=host.owned()
if not state.allowed or not present then s.stop(state.reason or why,{save=present});return false end
if not s.paused then return true end
s.paused=false;s.accumulator=0
if s.music then pcall(s.music.resume)end
if s.captureBeforePause then s.input.acquire()end
s.safe("onResume",s.callbacks.onResume);return true
end
E.current=s
s.events=E.newEvents(function(err)s.fail("event",err)end)
local constructed,view=pcall(viewFactory or E.newWoWView,s)
if not constructed then s.fail("view_init",view);return nil,tostring(view)end
s.view=view;s.input=E.newInput(s)
if E.newWorld then s.world=E.newWorld(s)end
if E.newSound then s.sound=E.newSound(s);s.music=E.newMusic(s)end
if E.newEffects then s.effects=E.newEffects(s,view)end
local packages=E.packages or{runtime=true,surface=E.newSurface~=nil,["surface-models"]=E.newSurfaceActors~=nil,
world=E.newWorld~=nil,audio=E.newSound~=nil,effects=E.newEffects~=nil,scene3d=E.newWoWScene3D~=nil,particles3d=E.newParticles3D~=nil,surfaceEffects3D=E.newSurfaceEffects3D~=nil}
local function requirePackage(name)
if not packages[name]then error("package_not_included: "..tostring(name).."; add it to item.json packages")end
return true
end
local function unavailable(name)
return G.setmetatable({},{__index=function()requirePackage(name)end})
end
local ctx={session={id=s.id,pause=s.pause,resume=s.resume,stop=s.stop,isPaused=function()return s.paused end},
content=content,events=s.events,world=unavailable("world"),motion=unavailable("world"),combat=unavailable("world"),collision=unavailable("world"),level=unavailable("world"),
sound=s.sound or unavailable("audio"),music=s.music or unavailable("audio"),input=s.input,fx=unavailable("effects"),clock={},save={},inventory={},trade={},ui={},perf={},assets={},data=E.JSON}
ctx.hasPackage=function(name)return packages[name]==true end
ctx.requirePackage=requirePackage
s.ctx=ctx
ctx.scene3d=unavailable("scene3d")
if E.newWoWScene3D then ctx.scene3d={math=E.math3d,boxMesh=E.boxMesh,create=function(options)
if s.stopping then return nil,"session_stopped"end
if s.scene3d then return s.scene3d end
s.scene3d=view.scene3d(options);return s.scene3d
end}end
ctx.session.isStopped=function()return s.stopping end
ctx.session.suspend=function()
if s.stopping then return false end
s.pause("suspend");if not s.stopping then view.suspend();return true end
return false
end
ctx.session.getSpeed=function()return s.speed end
ctx.session.setSpeed=function(speed)
if s.stopping or not E.util.finite(speed)or speed<.25 or speed>4 then return false,"invalid_simulation_speed"end
s.speed=speed;return true
end
if s.world then
ctx.world.spawn=s.world.spawn;ctx.world.despawn=s.world.despawn;ctx.world.clear=s.world.clear
ctx.world.get=function(id)return s.world.byId[id]end
ctx.world.count=function()return#s.world.list end
ctx.motion.setIntent=s.world.setIntent;ctx.combat.requestAction=s.world.requestAction
ctx.collision.query=s.world.query;ctx.collision.sweep=E.sweep
ctx.collision.setBroadphase=function(mode)if mode~="grid"and mode~="naive"then return false end;s.world.mode=mode;s.world.gridDirty=true;return true end
ctx.level.load=s.world.loadLevel
end
if s.effects then
ctx.fx.burst=s.effects.burst;ctx.fx.start=s.effects.start;ctx.fx.stop=s.effects.stop;ctx.fx.clear=s.effects.clear;ctx.fx.stats=s.effects.stats
end
ctx.level.checkpoint=function(id)s.perf.note("checkpoint",{id=id});s.savePending="checkpoint"end
ctx.clock.now=function()return s.time end;ctx.clock.wall=host.now
ctx.clock.after=function(delay,fn)
if s.stopping or not E.util.finite(delay)or delay<0 or#s.tasks>=256 then return nil,"task_budget_or_delay"end
s.nextTask=s.nextTask+1
local task={id=s.nextTask,at=s.time+delay,fn=fn}
s.tasks[#s.tasks+1]=task;return function()task.cancelled=true end
end
ctx.save.data=E.util.copy(gameState)
ctx.save.request=function(reason)if not s.stopping and not s.saving then s.savePending=reason or"requested";return true end;return false end
ctx.save.flush=function(reason)
if s.stopping or s.saving then return false,"session_busy"end
local ok,why=s.save(reason or"explicit")
if ok then s.savePending=nil end
return ok,why
end
ctx.save.probe=function()
local key,old="IG_STORAGE_PROBE_V1",host.read("IG_STORAGE_PROBE_V1")
local text=E.JSON.encode({test="变量往返",nonce=s.id,position={1.25,-4},enabled=true})
local start=host.profileMS();local ok,why=host.write(key,text)
local readOK=ok and host.read(key)==text
local restored,restoreWhy=host.write(key,old)
local result={ok=readOK and restored,writeReason=why,restoreReason=restoreWhy,milliseconds=host.profileMS()-start,bytes=#text}
s.perf.note("check.storage",result);return result
end
local function itemDefinition(id)
local d=content.items[id];if not d then return nil end
return manifest.rootId.." "..d.innerId,d
end
ctx.inventory.count=function(id)local class=itemDefinition(id);if not class then return nil,"unknown_item"end;return host.itemCount(class)end
local function mutate(operation,id,n,operationId)
if s.saving or s.stopping then return{status="failed",reason="session_busy"}end
local class,d=itemDefinition(id)
if not class or not E.util.finite(n)or n<1 or n>100 or n~=math.floor(n)or type(operationId)~="string"or#operationId>100 then return{status="failed",reason="invalid_request"}end
if s.operations[operationId]then
local op=s.operations[operationId]
if op.item~=id or op.requested~=n or op.operation~=operation then return{status="failed",reason="operation_id_conflict"}end
return op.result or{status="unknown",reason="pending_operation_not_retried"}
end
if operation=="consume"and not d.stack then return{status="failed",reason="use_exact_instance_ui_for_equipment"}end
if E.util.count(s.operations)>=128 then return{status="failed",reason="operation_journal_full"}end
local record={item=id,requested=n,operation=operation}
s.operations[operationId]=record
local persisted,why=s.save("inventory_pending")
if not persisted then s.operations[operationId]=nil;return{status="failed",reason=why}end
local result=host.mutateInventory(operation,class,n,d.attributes);record.result=result
local written=s.save("inventory_result")
if not written then record.result=nil;result={status="unknown",reason="inventory_changed_but_receipt_not_saved",applied=result.applied}end
s.perf.note("inventory.operation",{operationId=operationId,item=id,operation=operation,result=result})
s.events.emit("inventory.changed",{item=id,result=result});return result
end
ctx.inventory.grant=function(id,n,op)return mutate("grant",id,n,op)end
ctx.inventory.consume=function(id,n,op)return mutate("consume",id,n,op)end
ctx.trade.open=function(target)s.pause("trade");return host.openTrade(target or host.targetPlayer())end
ctx.ui.button=view.button;ctx.ui.notify=view.notify;ctx.ui.status=view.status;ctx.ui.prompt=view.prompt
ctx.ui.surface=function()requirePackage("surface");return view.surface()end
ctx.ui.showLog=function(previous)
view.showLog(previous and(s.previousLog or"暂无上次日志")or s.perf.export())
end
ctx.ui.toggleBounds=function()view.showBounds=not view.showBounds;return view.showBounds end
ctx.perf.begin=function(name,metadata,options)s.resume();s.perf.begin(name,metadata,options)end
ctx.perf.finish=function(status)s.perf.finish(status or"manual",s.stats())end
ctx.perf.isRunning=function()return s.perf.phase~=nil end
ctx.perf.note=s.perf.note;ctx.perf.stats=s.stats;ctx.perf.saveLog=s.saveLog
ctx.perf.snapshot=s.perf.snapshot
ctx.perf.measure=function(name,fn)
local start=host.profileMS();local ok,result=s.safe(name,fn)
s.perf.record(name,host.profileMS()-start);return ok,result
end
ctx.assets.recordModels=function()
local result={}
for _,e in ipairs(s.world and s.world.list or{})do
if e.view and(e.view.kind=="model"or e.view.kind=="scene_model")then
local ok,id=E.util.call(e.view.object.GetModelFileID,e.view.object)
local bounds
if e.view.kind=="scene_model"and e.view.loaded then
local bottom,top=E.readModelBounds(e.view.object,"GetActiveBoundingBox")
if bottom and top then bounds={bottom=bottom,top=top}end
end
result[#result+1]={entity=e.id,asset=e.visual.asset,fileID=ok and id or nil,
backend=e.view.kind,loaded=e.view.loaded==true,collider=E.util.copy(e.box),nativeBounds=bounds or"unavailable_for_this_backend_or_load_state"}
end
end
s.perf.note("check.models",{models=result,count=#result});return result
end
if s.sound then
for name,sound in pairs(content.feedback or{})do s.events.on(name,function()if not s.paused then s.sound.play(sound)end end)end
end
local function changed(event)
if s.stopping then return end
if event=="PLAYER_LEAVING_WORLD"or event=="PLAYER_LOGOUT"then s.stop(event);return end
local state=host.environment();local present,why=host.owned()
if not state.allowed or not present then s.stop(state.reason or why,{save=present});return end
if host.definitionChanged()then s.stop("definition_changed");return end
local command=host.read("IG_CONTROL_V1")
if command then
host.write("IG_CONTROL_V1",nil)
if command=="stop"or command=="destroy"then s.stop(command,{save=command~="destroy"});return end
if command=="pause"then s.pause("item_workflow")end
end
if event=="SECURITY_CHANGED"and not host.allowedEffects()then s.stop("security_changed",{save=false})end
end
host.watch(s.scope,changed)
local ok,callbacks=s.safe("createGame",definition.create,ctx)
if not ok or type(callbacks)~="table"or type(callbacks.onStart)~="function"then if not s.stopping then s.fail("createGame","onStart callback required")end;return nil,"invalid_game"end
s.callbacks=callbacks
local startOK=s.safe("onStart",callbacks.onStart)
if not startOK then return nil,"onStart_failed"end
s.started=true
s.perf.note("runtime.started",s.stats())
if host.bootstrapStartedMS then s.perf.note("startup",{bootstrapLuaToOnStartMs=host.profileMS()-host.bootstrapStartedMS,excludes="macro, intentional 0.1s delay, import, permission UI"})end
local function stage(name,fn,...)
local start=host.profileMS();fn(...);s.perf.record(name,host.profileMS()-start)
end
local function fixedStep()
s.time=s.time+s.fixed;s.tick=s.tick+1
local input=s.input.snapshot()
stage("gameMs",function()s.safe("onFixedUpdate",s.callbacks.onFixedUpdate,s.fixed,input)end)
if s.stopping or s.paused then return end
if s.world then
stage("aiMs",s.world.updateAI)
stage("actionsMs",s.world.updateActions,s.fixed)
stage("motionMs",s.world.move,s.fixed)
end
if s.scene3d then stage("scene3DStepMs",s.scene3d.step,s.fixed)end
if s.scene3d and s.scene3d.particles then stage("particles3DStepMs",s.scene3d.particles.update,s.fixed)end
if s.world then stage("collisionMs",s.world.collide)end
stage("eventsMs",s.events.flush)
if s.effects then stage("effectsMs",s.effects.update,s.fixed)end
if s.stopping then return end
if#s.tasks>0 then
local current=s.tasks;s.tasks={}
for _,task in ipairs(current)do
if not task.cancelled then
if task.at<=s.time then s.safe("scheduled",task.fn)else s.tasks[#s.tasks+1]=task end
end
if s.stopping then break end
end
end
if s.world then s.world.cleanup()end
if s.savePending and not s.stopping then
local why=s.savePending;s.savePending=nil
local ok,err=s.save(why)
if not ok then s.perf.note("save.failed",{reason=why,error=tostring(err)});view.notify("存档失败："..tostring(err))end
end
end
function s.frame(elapsed)
if s.stopping then return end
s.frameSerial=(s.frameSerial or 0)+1
local frameStart=host.profileMS();local now=host.now()
if now>=s.nextWatch then s.nextWatch=now+.25;changed("poll");if s.stopping then return end end
if view.update then s.safe("asset_update",view.update)end
if not s.paused then s.safe("onFrame",s.callbacks.onFrame,elapsed)end
if s.stopping then return end
s.perf.beforeFrame();stage("inputMs",s.input.poll)
if not s.paused then
s.accumulator=s.accumulator+math.min(elapsed,.25)*s.speed
if elapsed>.25 then s.perf.increment("clampedSimulationMs",(elapsed-.25)*1000)end
local steps=0
while s.accumulator>=s.fixed and steps<5 and not s.stopping and not s.paused do
s.accumulator=s.accumulator-s.fixed;steps=steps+1;fixedStep()
end
if s.stopping then return end
if s.accumulator>=s.fixed then
local dropped=math.floor(s.accumulator/s.fixed)*s.fixed
s.accumulator=s.accumulator-dropped;s.perf.increment("droppedSimulationMs",dropped*1000)
end
if s.world then stage("renderMs",view.render,s.world,E.util.clamp(s.accumulator/s.fixed,0,1))end
if s.effects then stage("effectsRenderMs",s.effects.render,E.util.clamp(s.accumulator/s.fixed,0,1))end
end
if s.scene3d then
if not s.paused and s.scene3d.particles then s.scene3d.particles.observeFrame(elapsed*1000)end
stage("scene3DRenderMs",s.scene3d.render,s.paused and 1 or E.util.clamp(s.accumulator/s.fixed,0,1))
end
if s.sound then s.sound.update()end
if s.music then
local audioOK,audioError=pcall(s.music.update)
if not audioOK then s.perf.note("music.error",{reason=tostring(audioError)});pcall(s.music.stop,"backend_error")end
end
if now>=s.nextHUD then
s.nextHUD=now+.3
local p=s.perf.phase
local mode=s.input.mode=="capture"and"键盘接管"or"按键只读/透传"
view.info((s.paused and"已暂停"or"运行中").." | "..mode.." | 实体 "..(s.world and#s.world.list or 0).." | Music "..(s.music and s.music.backend or"silent"))
if content.presentation~="game"then view.status(p and(p.name..(p.measuring and" 采样 "or" 预热 ")..string.format("%.1fs",now-(p.measureStart or p.start)))or"空闲：选择一项测试；自动基准包含预热，导出日志会暂停。")end
end
s.perf.afterFrame(elapsed,host.profileMS()-frameStart,s.stats)
if s.perf.completed~=s.lastLoggedCompletion then
s.lastLoggedCompletion=s.perf.completed
if s.perf.completed>0 then s.autoSaveLog()end
end
end
view.frame:SetScript("OnUpdate",function(_,elapsed)s.safe("frame",s.frame,elapsed)end)
return s
end
end
end)();install(E,G)end
G.TRP3_ItemGame=E
end
local gameModules={}
gameModules["enemies"]=(function()
return function(definitions,cellX)
local self={}
local nextBiteA=true
function self.cancelMelee(z)
local changed=z.attackTime~=nil
z.attackTime=nil;z.attackHit=nil;z.attackCol=nil
return changed
end
function self.melee(z,p,run,dt,sound)
local d=definitions[z.kind];local swing=d.melee
local changed=false
if z.attackTime==nil or z.attackCol~=p.col then
z.attackTime=0;z.attackHit=false;z.attackCol=p.col;changed=true
end
z.attackTime=z.attackTime+dt
if not z.attackHit and z.attackTime>=swing.impact then
z.attackHit=true;changed=true
p.hp=p.hp-d.bite*swing.period
sound(nextBiteA and"enemy_bite_a"or"enemy_bite_b");nextBiteA=not nextBiteA
if p.hp<=0 then run.plants[tostring((p.row-1)*9+p.col)]=nil end
end
if z.attackTime>=swing.period then
z.attackTime=z.attackTime-swing.period;z.attackHit=false;changed=true
end
return changed
end
local function targetAhead(z,run,range)
local target
for _,p in pairs(run.plants)do
local x=cellX(p.col)
if p.hp>0 and p.row==z.row and x<=z.x+20 and x+20>=z.x-range and(not target or p.col>target.col)then target=p end
end
return target
end
function self.step(z,run,dt,sound)
local d=definitions[z.kind]
if d.ability=="vomit"then
z.phase=z.phase or"advance";z.phaseTime=z.phaseTime or 0
z.abilityCooldown=math.max(0,(z.abilityCooldown or d.firstCast)-dt)
if z.phase=="stunned"then
z.phaseTime=math.max(0,z.phaseTime-dt)
if z.phaseTime<=0 then z.phase="advance";z.abilityCooldown=d.castInterval end
return true
end
if z.phase=="advance"and z.abilityCooldown<=0 and targetAhead(z,run,d.vomitRange)then
z.phase="vomit";z.phaseTime=d.vomitDuration;sound("vomit")
end
if z.phase=="vomit"then
local active=math.min(dt,z.phaseTime)
for key,p in pairs(run.plants)do
local x=cellX(p.col)
if p.row==z.row and x<=z.x+20 and x+20>=z.x-d.vomitRange then
p.hp=p.hp-d.vomitDPS*active
if p.hp<=0 then run.plants[key]=nil end
end
end
z.phaseTime=math.max(0,z.phaseTime-dt)
if z.phaseTime<=0 then z.phase="stunned";z.phaseTime=d.stunDuration end
return true
end
elseif d.ability=="necromancer"then
z.shotCooldown=math.max(0,(z.shotCooldown or d.firstShot)-dt)
if z.shotCooldown<=0 and#run.enemyBolts<80 and targetAhead(z,run,d.range)then
run.enemyBolts[#run.enemyBolts+1]={x=z.x-18,row=z.row,remaining=d.range,damage=d.shotDamage,speed=d.shotSpeed}
z.shotCooldown=d.shotInterval;sound("enemy_cast")
end
end
return false
end
function self.projectiles(run,dt,sound)
for i=#run.enemyBolts,1,-1 do
local b=run.enemyBolts[i];local old=b.x;local dx=math.min(b.speed*dt,b.remaining)
b.x=b.x-dx;b.remaining=b.remaining-dx
local target,key
for k,p in pairs(run.plants)do
local x=cellX(p.col)
if p.row==b.row and p.hp>0 and x-20<=old and x+20>=b.x and(not target or p.col>target.col)then target=p;key=k end
end
if target then
target.hp=target.hp-b.damage;if target.hp<=0 then run.plants[key]=nil end;sound("hit_shadow")
end
if target or b.remaining<=0 or b.x<70 then table.remove(run.enemyBolts,i)end
end
end
return self
end
end)()
gameModules["progress"]=(function()
local LIMIT=1000000000
local plantIds={"pea","sunflower","cherry","wall","mine","snow","chomper","repeater","puff","sunshroom"}
local enemyIds={"basic","flag","cone","bucket","pole","paper","abomination","necromancer"}
local statIds={"seconds","runsStarted","wins","losses","kills","sunCollected","sunSpent","plantsPlaced","mowersUsed","noMowerWins","cleared","endlessRuns","endlessBestRound","endlessBestScore"}
local definitions={
{id="first_plant",title="种下希望",description="首次部署一名守卫。",field="plantsPlaced",target=1},
{id="first_win",title="首次凯旋",description="成功守住任意一关。",field="firstWin",target=1},
{id="clean_win",title="防线固若金汤",description="不使用割草机赢得一局。",field="noMowerWins",target=1},
{id="hundred_kills",title="天灾克星",description="累计消灭 100 名天灾敌人。",field="kills",target=100},
{id="thousand_sun",title="日光收藏家",description="累计收集 1,000 点阳光。",field="sunCollected",target=1000},
{id="all_guardians",title="百花齐放",description="部署过全部 10 种守卫。",field="plantKindsUsed",target=10},
{id="five_levels",title="半程守护者",description="通关前 5 关。",field="cleared",target=5},
{id="ten_levels",title="艾泽拉斯园丁",description="通关全部 10 关。",field="cleared",target=10},
{id="abomination",title="拆解憎恶",description="消灭一只憎恶。",enemy="abomination",target=1},
{id="necromancer",title="终结死灵术",description="消灭一名通灵师。",enemy="necromancer",target=1},
}
local function finite(value)
if type(value)~="number"and type(value)~="string"then return nil end
local n=tonumber(value)
if not n or n~=n or n==math.huge or n==-math.huge then return nil end
return n
end
local function bounded(value,limit,fraction)
local n=math.max(0,math.min(limit or LIMIT,finite(value)or 0))
return fraction and n or math.floor(n)
end
local function validIndex(value,limit)
local n=finite(value)
if n and n>=1 and n<=limit and n==math.floor(n)then return n end
end
local function asTable(value)
return type(value)=="table"and value or{}
end
local function copyCounts(source,ids)
local result={}
source=asTable(source)
for _,id in ipairs(ids)do result[id]=bounded(source[id])end
return result
end
local function new(saved,seed)
saved,seed=asTable(saved),asTable(seed)
local original=asTable(saved.stats)
local data={
version=1,stats={},
plantsByKind=copyCounts(saved.plantsByKind,plantIds),
killsByKind=copyCounts(saved.killsByKind,enemyIds),
bestTimes={},unlocked={},
}
for _,id in ipairs(statIds)do
data.stats[id]=bounded(original[id],id=="cleared"and 10 or LIMIT,id=="seconds")
end
data.stats.cleared=math.max(data.stats.cleared,bounded(seed.cleared,10))
local oldTimes,oldUnlocks=asTable(saved.bestTimes),asTable(saved.unlocked)
for level=1,10 do
local key=tostring(level)
local duration=finite(oldTimes[key]or oldTimes[level])
if duration and duration>=0 then data.bestTimes[key]=math.min(LIMIT,duration)end
end
for _,def in ipairs(definitions)do
if oldUnlocks[def.id]==true then data.unlocked[def.id]=true end
end
local function kindCount()
local count=0
for _,id in ipairs(plantIds)do
if data.plantsByKind[id]>0 then count=count+1 end
end
return count
end
local function current(def)
if def.enemy then return data.killsByKind[def.enemy]end
if def.field=="plantKindsUsed"then return kindCount()end
if def.field=="firstWin"then
return(data.stats.wins>0 or data.stats.cleared>0)and 1 or 0
end
return data.stats[def.field]
end
local function achievement(def)
local unlocked=data.unlocked[def.id]==true
return{
id=def.id,title=def.title,description=def.description,
current=unlocked and def.target or math.min(def.target,current(def)),
target=def.target,unlocked=unlocked,
}
end
local function unlock()
local gained={}
for _,def in ipairs(definitions)do
if not data.unlocked[def.id]and current(def)>=def.target then
data.unlocked[def.id]=true
gained[#gained+1]=achievement(def)
end
end
return gained
end
local function add(field,value)
data.stats[field]=math.min(LIMIT,data.stats[field]+(value or 1))
end
local function record(event,payload)
payload=asTable(payload)
if event=="time"then
add("seconds",bounded(payload.seconds,LIMIT,true))
elseif event=="run_started"then
if not validIndex(payload.level,10)then return{}end
add("runsStarted")
if payload.mode=="endless"then add("endlessRuns")end
elseif event=="plant"then
if not data.plantsByKind[payload.kind]then return{}end
add("plantsPlaced")
add("sunSpent",bounded(payload.cost))
data.plantsByKind[payload.kind]=math.min(LIMIT,data.plantsByKind[payload.kind]+1)
elseif event=="sun"then
add("sunCollected",bounded(payload.amount))
elseif event=="kill"then
if not data.killsByKind[payload.kind]then return{}end
add("kills")
data.killsByKind[payload.kind]=math.min(LIMIT,data.killsByKind[payload.kind]+1)
elseif event=="mower"then
if not validIndex(payload.row,5)then return{}end
add("mowersUsed")
elseif event=="endless_progress"then
local round,score=validIndex(payload.round,1000000),bounded(payload.score)
if not round then return{}end
data.stats.endlessBestRound=math.max(data.stats.endlessBestRound,round)
data.stats.endlessBestScore=math.max(data.stats.endlessBestScore,score)
elseif event=="win"or event=="loss"then
local level=validIndex(payload.level,10)
if not level then return{}end
add(event=="win"and"wins"or"losses")
if event=="win"then
data.stats.cleared=math.max(data.stats.cleared,level)
if payload.noMowersUsed==true then add("noMowerWins")end
local duration,key=finite(payload.duration),tostring(level)
if duration and duration>=0 then
duration=math.min(LIMIT,duration)
if not data.bestTimes[key]or duration<data.bestTimes[key]then data.bestTimes[key]=duration end
end
end
else
return{}
end
return unlock()
end
local function achievements()
local result={}
for _,def in ipairs(definitions)do result[#result+1]=achievement(def)end
return result
end
local function summary()
local result={}
for _,id in ipairs(statIds)do result[id]=data.stats[id]end
result.plantKindsUsed,result.achievementCount,result.achievementTotal=kindCount(),0,#definitions
result.bestTimes={}
for level=1,10 do result.bestTimes[tostring(level)]=data.bestTimes[tostring(level)]end
result.plantsByKind=copyCounts(data.plantsByKind,plantIds)
result.killsByKind=copyCounts(data.killsByKind,enemyIds)
for _,def in ipairs(definitions)do
if data.unlocked[def.id]then result.achievementCount=result.achievementCount+1 end
end
return result
end
unlock()
return{data=data,record=record,summary=summary,achievements=achievements}
end
return{new=new}
end)()
gameModules["progress_ui"]=(function()
return function(surface,state,actions)
local gold,cream,muted={1,.78,.33,1},{1,.94,.77,1},{.72,.70,.61,1}
local active=state.tab=="achievements"and"achievements"or"stats"
local summary,achievements=state.summary or{},state.achievements or{}
local function draw(id,options)surface.draw("progress."..id,options)end
local function text(id,value,x,y,w,h,size,color,layer)
draw(id,{kind="text",text=value,x=x,y=y,w=w,h=h,
size=size or 15,color=color or cream,layer=layer or 24})
end
local function rect(id,x,y,w,h,color,layer)
draw(id,{kind="rect",x=x,y=y,w=w,h=h,color=color,layer=layer or 23})
end
local function button(id,label,x,y,w,h,callback,selected)
draw(id,{kind="button",text=label,x=x,y=y,w=w,h=h,size=16,
asset="ground_elwynn_wood",color=selected and{.88,.68,.36,1}or{.56,.46,.32,1},
layer=25,onClick=function()
callback()
actions.clickSound()
actions.redraw()
end})
end
local function count(value)return tostring(math.floor(value or 0))end
local function clock(value)
local seconds=math.floor(value or 0)
local hours=math.floor(seconds/3600)
local minutes=math.floor(seconds/60)%60
if hours>0 then return string.format("%d:%02d:%02d",hours,minutes,seconds%60)end
return string.format("%d:%02d",minutes,seconds%60)
end
draw("shield",{kind="button",text="",x=0,y=0,w=960,h=600,
layer=20,color={.015,.012,.008,.90},onClick=function()end})
draw("frame",{kind="texture",asset="ground_elwynn_road",x=32,y=24,w=896,h=552,
layer=21,color={.66,.54,.32,1}})
draw("panel",{kind="texture",asset="ui_leather_background",x=38,y=30,w=884,h=540,
layer=22,color={.40,.32,.23,1}})
text("title","花园手册",62,45,260,38,26,gold)
text("scope","当前存档 · "..count(summary.cleared).." / 10 关 · 成就 "..
count(summary.achievementCount).." / "..count(summary.achievementTotal or#achievements),
400,50,494,28,16,cream)
button("tab.stats","战斗统计",62,98,166,38,function()actions.onTab("stats")end,active=="stats")
button("tab.achievements","成就手册",240,98,166,38,function()actions.onTab("achievements")end,active=="achievements")
text("hint","每一场守护，都记在这里。",470,102,416,28,15,muted)
rect("divider",62,146,832,2,{.64,.49,.27,.85})
if active=="stats"then
local metrics={
{"战斗时长",clock(summary.seconds)},{"开局次数",count(summary.runsStarted)},
{"胜利 / 失败",count(summary.wins).." / "..count(summary.losses)},
{"消灭敌人",count(summary.kills)},{"收集阳光",count(summary.sunCollected)},
{"消耗阳光",count(summary.sunSpent)},{"部署守卫",count(summary.plantsPlaced)},
{"守卫种类",count(summary.plantKindsUsed).." / 10"},
{"割草机出动",count(summary.mowersUsed)},{"无割草机胜利",count(summary.noMowerWins)},
}
for i,metric in ipairs(metrics)do
local x,y=62+((i-1)%5)*168,162+math.floor((i-1)/5)*87
rect("stats.tile"..i,x,y,160,76,{.12,.095,.06,.67})
text("stats.label"..i,metric[1],x+8,y+7,144,23,14,muted)
text("stats.value"..i,metric[2],x+8,y+34,144,31,23,gold)
end
text("stats.endless","无尽挑战：开局 "..count(summary.endlessRuns).." 次 · 最高第 "..
count(summary.endlessBestRound).." 轮 · 最高 "..count(summary.endlessBestScore).." 分",62,329,832,22,14,gold)
text("stats.bestTitle","各关最快通关",62,353,390,29,19,gold)
text("stats.bestHint","按战局逻辑时间记录",555,358,339,23,13,muted)
for level=1,10 do
local x,y=62+((level-1)%5)*168,387+math.floor((level-1)/5)*53
local duration=summary.bestTimes and summary.bestTimes[tostring(level)]
rect("stats.bestCell"..level,x,y,160,44,{.14,.11,.07,.64})
text("stats.bestLevel"..level,"第 "..level.." 关",x+9,y+10,63,23,13,muted)
text("stats.bestTime"..level,duration and clock(duration)or"—",x+72,y+8,80,27,18,duration and cream or muted)
end
text("stats.note","旧存档保留已知通关进度；其余统计从启用手册后累计。",62,487,832,24,13,muted)
else
for i,achievement in ipairs(achievements)do
if i<=10 then
local x,y=62+((i-1)%2)*422,160+math.floor((i-1)/2)*67
local color=achievement.unlocked and gold or muted
rect("achievement.card"..i,x,y,410,59,
achievement.unlocked and{.27,.20,.10,.84}or{.11,.09,.065,.75})
rect("achievement.accent"..i,x,y,3,59,
achievement.unlocked and{.94,.68,.22,1}or{.38,.32,.23,1})
text("achievement.title"..i,achievement.title,x+12,y+4,269,23,16,color)
text("achievement.status"..i,
achievement.unlocked and"已达成"or(count(achievement.current).." / "..count(achievement.target)),
x+280,y+4,119,23,13,color)
text("achievement.description"..i,achievement.description,x+12,y+29,386,23,13,cream)
end
end
text("achievements.note","成就记录你的旅程，不额外发放金币或道具。",62,499,832,20,13,muted)
end
button("back","返回",735,523,159,35,actions.onBack,false)
text("footer","三份花园，三份独立记录。",62,530,620,22,13,muted)
end
end)()
gameModules["ui"]=(function()
return function(ctx,read,actions,drawProgress)
local C,floor,min,max=ctx.content,math.floor,math.min,math.max
local ui,render=ctx.ui.surface()
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
local size=def.render or{width=104,height=108}
local scale=(growth or 1)*(def.scale or 1)
local w,h=min(84*1.3,size.width*scale),min(68*1.3,size.height*scale)
local anchorX,anchorY=x+(size.offsetX or 0),feet+(size.offsetY or 0)
ui.draw(id,{kind="model",asset=asset,x=anchorX-w/2,y=anchorY-h*.9,w=w,h=h,scale=1,
anchorX=anchorX,anchorY=anchorY,layer=4,depth=feet,animation=animation,paused=paused,
animationTime=timeline and timeline.time,animationRate=timeline and timeline.rate,animationEnd=timeline and timeline.limit})
end
local function B(id,text,x,y,w,h,fn,z,enabled,icon,tint,transparent)
z=z or 8
local nativeButton=z>=24 and not transparent
ui.draw(id,{kind="button",text=icon and""or text,x=x,y=y,w=w,h=h,
nativeButton=nativeButton,asset=not transparent and not nativeButton and"ground_elwynn_wood"or nil,texCoord={0,1,0,1},
onClick=function(mouse)
fn(mouse)
if ctx.session.isStopped()then return end
if book.sound and id~="shield"and id~="collectAll"and not id:match("^cell")and not id:match("^sun%d")then
ctx.sound.play(id:match("^seed")and"ui_select"or"ui_click")
end
render()
end,color=(transparent or nativeButton)and{0,0,0,0}or tint or{.65,.65,.58,1},
layer=z,enabled=enabled,size=15})
if icon then
X("buttonIcon/"..id,icon,x+5,y+4,h-8,h-8,enabled==false and{.45,.45,.45,1}or white,z+1,{.07,.93,.07,.93})
T("buttonLabel/"..id,text,x+h,y+2,w-h-3,h-4,14,enabled==false and muted or cream,z+1)
end
end
local function panel(id,x,y,w,h,z)
R(id.."fill",x,y,w,h,paper,z)
X(id.."/paperTexture","ui_parchment_grain",x,y,w,h,{1,1,1,.85},z+1)
end
local function backdrop(night,level)
X("ground",V.materials.dirt.texture,0,0,960,600,night and{.32,.39,.52,1}or{.70,.66,.49,1},0,{0,4,0,3},true)
X("path",V.materials.road.texture,78,152,48,359,night and{.40,.49,.62,1}or{.86,.84,.69,1},1,{0,1,0,4},true)
X("road",V.materials.road.texture,889,152,71,359,night and{.28,.34,.44,1}or{.59,.61,.52,1},1,{0,1,0,4},true)
for row=1,5 do for col=1,9 do
local cultivated=not level or rowActive(level,row)
local color
if cultivated then
color=night and((row+col)%2==0 and{.35,.52,.65,1}or{.39,.58,.71,1})or
((row+col)%2==0 and{.49,.65,.42,1}or{.55,.71,.47,1})
else color=night and{.32,.34,.36,1}or{.55,.49,.36,1}end
X("lawn"..row.."_"..col,cultivated and V.materials.grass.texture or V.materials.dirt.texture,130+(col-1)*84,rowY(row),84,68,color,1,
{(col-1)*.5,col*.5,(row-1)*.5,row*.5},true)
end end
X("upperCurb",V.materials.road.texture,125,149,765,14,{.59,.58,.50,1},2,{0,7,0,.35},true)
X("lowerCurb",V.materials.road.texture,125,504,765,12,{.59,.58,.50,1},2,{0,7,.4,.7},true)
X("porch",V.materials.wood.texture,0,199,75,303,night and{.36,.42,.51,1}or{.71,.66,.48,1},1,{0,1,0,3},true)
X("porchFrame","ui_stone_frame",-14,240,105,204,{.78,.71,.53,1},2)
T("house","庭\n院\n入\n口",16,280,43,126,20,gold,3)
X("topbar",V.materials.wood.texture,0,0,960,60,{.53,.51,.39,1},12,{0,6,0,1},true)
X("toolbar",V.materials.wood.texture,0,550,960,50,{.46,.46,.37,1},12,{0,6,0,1},true)
R("messageShade",0,517,960,31,dark,12)
if night then X("moon","icon_sun_alt",899,161,45,45,{.46,.71,1,.8},3,nil,nil,"ADD")end
end
local function footer()
T("saveStatus",saveStatus,12,565,138,22,12,muted,13,"LEFT")
B("musicShortcut","音乐",155,559,85,34,actions.showMusicSettings,15,true,"icon_sound",book.music and{.65,.65,.58,1}or{.38,.40,.37,1})
T("message",achievementNotice or message,14,520,932,24,14,achievementNotice and gold or cream,13,"LEFT")
end
local function drawProfiles()
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
T("slotText"..i,value and value.name or"花园 "..i,contentX,y+8,160,24,17,ink,12,"LEFT")
T("slotStats"..i,value and value.cleared.." / 10 关 · "..value.coins.." 金币"or"空存档",contentX+168,y+8,contentW-168,24,14,softInk,12,"RIGHT")
if value then
B("load"..i,value.run and(value.run.mode=="endless"and"读档 · 无尽第 "..value.run.round.." 轮"or"读档 · 第 "..value.run.level.." 关")or"读档 · 庭院地图",contentX,y+42,loadW,36,function()actions.loadSlot(i)end,13,true)
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
for i=1,10 do
local x=164+((i-1)%5)*138;local y=183+floor((i-1)/5)*151
local unlocked=i<=min(10,slot.cleared+1)
if unlocked then ui.preloadModel(V.plants[C.plants[i].id].model)end
X("mapRoad"..i,"ground_elwynn_road",x+16,y+29,132,15,unlocked and{.8,.72,.48,1}or{.25,.3,.27,1},11,{0,1,0,.5})
X("levelIcon"..i,V.plants[C.plants[i].id].texture,x+29,y,65,65,unlocked and white or{.3,.3,.3,1},12,{.05,.95,.05,.95})
X("levelRing"..i,"action_border",x+19,y-10,85,85,unlocked and gold or muted,12)
T("levelIndex"..i,tostring(i)..(i<=slot.cleared and"  ✓"or""),x+53,y+41,39,25,18,gold,13)
B("level"..i,"",x+19,y-10,85,85,function()actions.chooseLevel(i)end,14,unlocked,nil,nil,true)
T("levelName"..i,C.campaign[i].title,x,y+70,126,25,15,unlocked and cream or muted,12)
T("unlock"..i,C.plants[i].name,x,y+99,126,22,13,unlocked and gold or muted,12)
end
local endlessUnlocked=slot.cleared>=10
local progress=slot.progress and slot.progress.stats or{}
T("endlessRules",endlessUnlocked and"积分：食尸鬼10 / 旗手20 / 披甲25 / 巨尸45 / 恶鬼35 / 侍僧40 / 亡灵师80 / 憎恶150"or
"通关第 10 关后解锁无尽挑战；首轮中间3路，第2轮起五路。",149,458,711,18,11,endlessUnlocked and cream or muted,13)
B("endless",endlessUnlocked and("无尽挑战 · 最高第 "..(progress.endlessBestRound or 0).." 轮 · "..(progress.endlessBestScore or 0).." 分")or
"无尽挑战 · 尚未解锁",149,480,711,34,actions.chooseEndless,14,endlessUnlocked,nil,endlessUnlocked and{.54,.38,.24,1}or nil)
B("progress","统计 / 成就",514,559,153,34,actions.showProgress,15,true,"icon_help")
B("profiles","存档管理",675,559,133,34,actions.openProfiles,15,true,"icon_profiles")
B("continue",run and(run.mode=="endless"and"继续无尽"or"继续战局")or"开始挑战",817,559,132,34,actions.continueBattle,15,true,"icon_farm_seed")
end
local function drawBattle()
local def=C.campaign[run.level];backdrop(def.theme=="night",run.level)
T("heading",run.mode=="endless"and"∞  无尽挑战"or string.format("%02d",run.level).."  "..def.title,18,10,343,35,24,gold,13,"LEFT")
X("sunCounter",V.tools.sun.texture,370,13,31,31,white,13)
T("sunTotal",tostring(run.sun),412,8,116,37,27,gold,13,"LEFT")
B("speed",book.speed==2 and"2× 加速"or"1× 速度",540,15,75,29,actions.toggleSpeed,15,true,nil,book.speed==2 and{.88,.65,.30,1}or nil)
local wave
if run.mode=="endless"then
local spawned=min(run.roundTotal,run.spawnIndex-1)
wave="第 "..run.round.." 轮 · "..run.score.." 分 · "..spawned.." / "..run.roundTotal.." · 场上 "..#run.zombies
if run.time<run.nextWave then wave="第 "..run.round.." 轮 · 准备 "..math.ceil(run.nextWave-run.time).." 秒 · "..run.score.." 分"end
else wave=run.wave==0 and("准备 "..math.ceil(max(0,run.nextWave-run.time)).." 秒")or("波次 "..run.wave.." / "..#def.waves.."  ·  场上 "..#run.zombies)end
T("wave",wave,616,13,325,30,17,cream,13)
for i,p in ipairs(C.plants)do
local x=9+(i-1)*95;local unlocked=i<=actions.unlockCount();local cooldown=run.cooldowns[p.id]or 0
local affordable=run.sun>=p.cost
if unlocked then ui.preloadModel(V.plants[p.id].model)end
X("card"..i,"ui_leather_background",x,68,90,75,unlocked and{.54,.57,.40,1}or{.25,.27,.24,1},12)
X("cardIcon"..i,unlocked and V.plants[p.id].texture or"icon_seed_bag",x+4,72,38,38,unlocked and(affordable and white or{.45,.45,.45,1})or{.4,.4,.4,1},13,{.07,.93,.07,.93})
X("cardRim"..i,"action_border",x-2,65,52,52,selected==p.id and gold or{.75,.72,.54,1},13)
T("cardCost"..i,unlocked and tostring(p.cost)or(i.."关"),x+43,75,44,24,18,unlocked and(affordable and gold or{1,.25,.18,1})or muted,14)
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
if rowActive(run.level,row)then
local mower=run.mowers[row]
if mower>=0 then unit("mower"..row,V.tools.mower.model,mower==0 and 99 or mower,rowY(row)+57,mower==0 and 0 or 4)end
for col=1,9 do
local key=cellKey(row,col);local p=run.plants[key];local x=cellX(col)
B("cell"..key,"",x-42,rowY(row),84,68,function(mouse)actions.plantAt(row,col,mouse)end,3,true,nil,nil,true)
if p then
local visual=V.plants[p.kind];local sleeping=(p.kind=="puff"or p.kind=="sunshroom")and def.theme~="night"
local attack=plants[p.kind].damage and p.timer>(plants[p.kind].interval or 1)-.25
R("plantShadow"..key,x-20,rowY(row)+53,40,4,{.025,.04,.02,.35},3)
unit("plant"..key,visual.model,x,rowY(row)+57,attack and 16 or 0,sleeping,p.kind=="sunshroom"and p.age<90 and.72 or 1)
if p.hp<plants[p.kind].hp then
R("plantHPBase"..key,x-26,rowY(row)+62,52,3,{.1,.1,.07,.9},5)
R("plantHP"..key,x-26,rowY(row)+62,52*p.hp/plants[p.kind].hp,3,{.56,.83,.28,1},6)
end
local status=sleeping and"休眠"or(p.kind=="mine"and p.age<12 and(math.ceil(12-p.age).."s"))or
(p.kind=="chomper"and p.timer>0 and("咀嚼 "..math.ceil(p.timer)))or nil
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
if z.phase=="vomit"then animation=53 elseif z.phase=="stunned"then animation=0
elseif not timeline and d.ability=="necromancer"and(z.shotCooldown or 0)>d.shotInterval-.4 then animation=51 end
unit("enemy"..i,visual.model,z.x,rowY(z.row)+57,animation,nil,nil,timeline)
if z.phase=="vomit"then
for cloud=1,3 do X("vomit"..i.."_"..cloud,"orb",z.x-cloud*52-15,rowY(z.row)+18,83,35,{.4,.85,.05,.50},7,nil,nil,"ADD")end
T("eliteState"..i,"呕吐 "..math.ceil(z.phaseTime or 0).."s",z.x-36,rowY(z.row)-1,72,15,10,{.7,1,.2,1},7)
elseif z.phase=="stunned"then T("eliteState"..i,"僵直 "..math.ceil(z.phaseTime or 0).."s",z.x-36,rowY(z.row)-1,72,15,10,gold,7)end
T("enemyName"..i,C.enemies[z.kind].name,z.x-29,rowY(z.row)+53,58,14,11,z.slow>0 and{.56,.85,1,1}or cream,6)
if z.hp<C.enemies[z.kind].hp then R("enemyHP"..i,z.x-26,rowY(z.row)+66,52*z.hp/C.enemies[z.kind].hp,3,{.88,.30,.19,1},6)end
if z.slow>0 then X("ice"..i,"icon_snow",z.x-24,rowY(z.row)+9,28,28,{.6,.8,1,.5},6,nil,nil,"ADD")end
end
for i,b in ipairs(run.bullets)do
X("bulletGlow"..i,"orb",b.x-9,rowY(b.row)+20,22,22,b.ice and{.35,.8,1,1}or b.spore and{.65,.35,1,.85}or{.38,1,.15,1},7,nil,nil,"ADD")
end
for i,b in ipairs(run.enemyBolts or{})do
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
for i,effect in ipairs(sunEffects or{})do
local alpha=max(0,effect.ttl/.45);local y=effect.y-(1-alpha)*22
X("sunCollectGlow"..i,"orb",effect.x-21,y-21,42,42,{1,.84,.3,alpha},9,nil,nil,"ADD")
X("sunCollectIcon"..i,V.tools.sun.texture,effect.x-11,y-11,23,23,{1,1,1,alpha},9,{.08,.92,.08,.92})
T("sunCollectValue"..i,"+"..effect.value,effect.x-22,y+10,44,19,14,{1,.87,.4,alpha},10)
end
B("shovel",selected=="shovel"and"铲除 ✓"or"铲除",249,559,83,34,actions.toggleShovel,15,true,"icon_shovel",selected=="shovel"and{.9,.72,.35,1}or nil)
B("collectAll","收阳",338,559,78,34,actions.collectAll,15,true,V.tools.sun.texture)
B("pause","暂停",422,559,78,34,actions.pause,15,true,"icon_pause")
B("map","地图",506,559,78,34,actions.leaveBattle,15,true,"icon_map")
B("sound",book.sound and"音效开"or"音效关",590,559,90,34,actions.toggleSound,15,true,"icon_sound")
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
return book.musicSource=="native"and"配乐：魔兽原生"or"配乐：自动（Musician 优先）"
end
local function musicFallbackNote(reason)
if reason=="musician_unavailable"then return"未启用 Musician，已回退魔兽原生配乐。"end
if reason=="musician_busy"then return"Musician 正在演奏其他曲目，暂用原生配乐。"end
if reason=="musician_muted"or reason=="musician_no_channel"then return"Musician 已静音或未启用通道，暂用原生配乐。"end
if reason then return"MIDI 无法播放，已回退原生；切换配乐方式可重试。"end
end
local function musicVolumeRow(y)
local caps=ctx.music.capabilities()
if caps.selectedBackend=="musician"then
T("musicVolume",book.musicVolume==0 and"MIDI 已静音"or"MIDI 无单曲音量调节",278,y,280,30,16,ink,24,"LEFT")
B("musicVolumeDown","−",579,y,50,30,function()end,24,false)
B("musicVolumeUp",book.musicVolume==0 and"开"or"+",640,y,50,30,actions.unmuteMusic,24,book.musicVolume==0)
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
local accent=i==2 and{.55,.75,1,1}or gold
R("musicCard"..i,x,228,146,112,i==2 and{.09,.15,.23,.9}or{.20,.19,.09,.9},23)
R("musicAccent"..i,x,228,146,3,accent,24)
T("musicTheme"..i,({"白天","夜晚","选关"})[i]..(music.track==id and" · 当前"or""),x+10,234,126,20,13,accent,24,"LEFT")
T("musicTitle"..i,isMidi and track.musicianTitle or track.title,x+10,256,126,24,15,cream,24,"LEFT")
local subtitle=isMidi and"社区 MIDI · 支持续播"or
(book.musicVolume>0 and book.musicVolume<1 and track.volumeSubtitle or track.subtitle)
T("musicFile"..i,subtitle,x+10,283,126,18,11,muted,24,"LEFT")
B("musicPreview"..i,music.preview==id and"从头试听"or"试听",x+10,305,126,30,function()actions.previewMusic(id)end,24,book.music)
end
B("musicEnabled",book.music and"背景音乐：开"or"背景音乐：关",267,346,207,30,actions.toggleMusic,24,true,"icon_sound")
B("musicStopPreview","停止试听",486,346,207,30,actions.stopMusicPreview,24,music.preview~=nil)
local volumeAvailable=musicVolumeRow(382)
local status
local id=music.preview or music.track
local track=id and C.music[id]
local title=track and(ctx.music.capabilities(id).selectedBackend=="musician"and track.musicianTitle or track.title)
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
(volumeAvailable and"原生曲目调音量会重播；夜曲低音量可能随机选曲。"or"当前客户端不支持独立音量。")
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
if screen=="profiles"then drawProfiles()elseif screen=="map"then drawMap()else drawBattle()end
footer()
if confirm then
modal(confirm.kind=="delete"and"删除这份花园存档？"or confirm.kind=="restart"and(confirm.mode=="endless"and"重新开始无尽挑战？"or"重新开始本关？")or confirm.kind=="replace_endless"and"开始无尽挑战？"or"重新开始一个关卡？")
T("confirmNote",confirm.kind=="delete"and"该槽的关卡、金币、战局及统计成就将被删除。\n其他花园和像素版存档均保留。"or confirm.kind=="restart"and"当前战局的植物、敌人、阳光、进度和计时将重置。\n通关进度、统计成就、金币及设置保留。"or confirm.kind=="replace_endless"and"当前战局将被替换为无尽挑战。\n通关进度、统计成就、金币及设置保留。"or"当前战局将被替换，通关进度、统计成就和金币保留。",249,252,462,63,17,ink,23)
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
B("settingSpeed",book.speed==2 and"游戏速度：2 倍速"or"游戏速度：正常 1 倍速",267,194,426,30,actions.toggleSpeed,24,true)
B("settingSound",book.sound and"游戏音效：开"or"游戏音效：关",267,231,207,30,actions.toggleSound,24,true,"icon_sound")
B("settingMusic",book.music and"背景音乐：开"or"背景音乐：关",486,231,207,30,actions.toggleMusic,24,true,"icon_sound")
B("settingMusicSource",musicSourceLabel(),267,268,426,30,actions.toggleMusicSource,24,true)
local volumeAvailable=ctx.sound.capabilities().volume
volumeRow("soundVolume","音效音量",book.soundVolume,304,function(delta)actions.adjustVolume("all",delta)end,volumeAvailable)
volumeRow("hitVolume","命中音量",book.hitVolume,340,function(delta)actions.adjustVolume("impact",delta)end,volumeAvailable)
local musicAvailable=musicVolumeRow(376)
local note=state.music.error or musicFallbackNote(state.music.fallback)or
(ctx.music.capabilities().selectedBackend=="musician"and"MIDI 支持续播；独立音量仅用于原生配乐。"or
(volumeAvailable and musicAvailable and"音效对新声音生效；音乐音量恢复后生效"or"当前客户端存在不支持的音量调节项"))
T("volumeNote",note,250,410,460,20,12,softInk,24)
B("musicLibrary","曲目 / 试听",267,436,426,25,actions.showMusicSettings,24,true,"icon_sound")
B("settingsBack","返回暂停菜单",320,469,320,23,actions.backToPause,24,true)
else
modal("游戏已暂停",true)
T("pausedNote",saveStatus.." · 阳光、敌人和冷却已冻结",247,195,466,25,15,ink,23)
B("resume","继续游戏",267,235,426,40,actions.resume,24,true,"icon_farm_seed")
B("settings","游戏设置",267,282,207,40,actions.showSettings,24,true)
if slot and screen~="profiles"then B("pauseProgress","统计 / 成就",486,282,207,40,actions.showProgress,24,true)end
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
B("pauseMap",slot and"返回庭院地图"or"返回存档选择",320,437,320,35,actions.leaveBattle,24,true,"icon_map")
end
end
elseif screen=="battle"and run.status~="playing"then
local endless=run.mode=="endless"
modal(endless and"无尽挑战结束"or run.status=="won"and(run.level==10 and"天灾终结者"or"防线守住了！")or"天灾突破了防线")
local result=endless and("到达第 "..run.round.." 轮 · 获得 "..run.score.." 分")or run.status=="won"and
(run.level<10 and("下一关解锁："..C.plants[run.level+1].name)or"十种植物集齐 · 无尽挑战已解锁")or"重新布置防线，再守一次。"
T("result",result,249,251,462,36,18,ink,23)
T("resultKills","击退 "..run.kills.." 个敌人 · 用时 "..floor(run.time).." 秒",249,297,462,27,16,softInk,23)
B("resultMap","返回地图",270,360,196,43,actions.leaveBattle,24,true,"icon_map")
B("resultNext",endless and"再战无尽"or run.status=="won"and run.level==10 and"进入无尽"or run.status=="won"and run.level<10 and"下一关"or"重玩本关",494,360,196,43,
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
end)()
gameModules["vfx"]=(function()
return function(ctx)
local serial=0
local self={}
local function emit(ids,x,y,scale)
serial=serial+1
for i,id in ipairs(ids)do
ctx.fx.burst(id,{x=x,y=y,scale=scale or 1,seed=serial*131+i})
end
end
function self.impact(ice,spore,x,y)
emit(spore and{"spore_flash","spore_dust","spore_wisp"}
or ice and{"ice_flash","ice_shards","ice_chips"}or{"pea_flash","pea_splash"},x,y)
end
function self.explosion(x,y,radius)
emit({"explosion_flash","explosion_ring","explosion_sparks","explosion_smoke"},x,y,
math.max(.65,math.min(1.5,radius/100)))
end
return self
end
end)()
local gameFactory=(function()
return function(ctx,modules)
local vfx=modules.vfx(ctx)
local C,floor,min,max,abs=ctx.content,math.floor,math.min,math.max,math.abs
local plants,plantIndex={},{}
for i,p in ipairs(C.plants)do plants[p.id]=p;plantIndex[p.id]=i end
local function copy(v)
if type(v)~="table"then return v end
local out={};for k,value in pairs(v)do out[k]=copy(value)end;return out
end
local function number(v,lo,hi,integer)
return type(v)=="number"and v==v and v>=lo and v<=hi and(not integer or v==floor(v))
end
local function check(ok)if not ok then error("庭院存档格式无效，原存档已保留。")end end
local function array(t,limit)
check(type(t)=="table"and#t<=limit)
local n=0;for k in pairs(t)do check(number(k,1,#t,true));n=n+1 end;check(n==#t)
end
local function rowActive(level,row)
for _,r in ipairs(C.campaign[level].rows)do if r==row then return true end end
return false
end
local function cellKey(row,col)return tostring((row-1)*9+col)end
local function cellX(col)return 130+(col-.5)*84 end
local function rowY(row)return 164+(row-1)*68 end
local CELL_WIDTH,BITE_CONTACT=84,38
local ENDLESS,MAX_SCORE=C.endless,1000000000
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
return"basic"
end
local elite=modules.enemies(C.enemies,cellX)
local function freeEnemySlot(zombies)
local used={};for _,z in ipairs(zombies)do if z.viewSlot then used[z.viewSlot]=true end end
for i=1,48 do if not used[i]then return i end end
end
local function validateRun(r,cleared)
check(type(r)=="table"and number(r.level,1,min(10,cleared+1),true))
local endless=r.mode=="endless"
local endlessTotal
check(r.mode==nil or r.mode=="campaign"or endless)
if endless then
check(cleared==10 and r.level==ENDLESS.level and number(r.round,1,1000000,true)and number(r.score,0,MAX_SCORE,true))
local _,total=endlessPlan(r.round);endlessTotal=total;check(number(r.roundTotal,1,1000000,true))
end
check(r.status=="playing"or r.status=="won"or r.status=="lost")
for _,key in ipairs({"time","nextSky","waveTime","nextWave","spawnClock"})do check(number(r[key],0,1e7))end
check(number(r.sun,0,9990,true)and number(r.wave,0,endless and 1 or#C.campaign[r.level].waves,true))
check(number(r.spawnIndex,1,endless and 1000000 or 100,true)and number(r.rng,1,2147483646,true)and number(r.kills,0,MAX_SCORE,true))
if endless then r.roundTotal=endlessTotal;r.spawnIndex=min(r.spawnIndex,endlessTotal+1)end
check(type(r.plants)=="table"and type(r.cooldowns)=="table")
for k,p in pairs(r.plants)do
check(type(p)=="table"and plants[p.kind]and plantIndex[p.kind]<=min(10,cleared+1))
check(number(p.row,1,5,true)and rowActive(r.level,p.row)and number(p.col,1,9,true)and k==cellKey(p.row,p.col))
check(number(p.hp,.001,plants[p.kind].hp)and number(p.age,0,1e7)and number(p.timer,0,100))
end
for id,v in pairs(r.cooldowns)do check(plants[id]and number(v,0,100))end
array(r.zombies,48);array(r.bullets,160);array(r.suns,60);array(r.mowers,5);check(#r.mowers==5)
if r.enemyBolts==nil then r.enemyBolts={}end
array(r.enemyBolts,80)
local viewSlots={}
for _,z in ipairs(r.zombies)do
check(type(z)=="table"and C.enemies[z.kind]and number(z.hp,.001,C.enemies[z.kind].hp))
check(number(z.row,1,5,true)and rowActive(r.level,z.row)and number(z.x,0,1000)and number(z.slow,0,6)and type(z.jumped)=="boolean")
if z.phase~=nil then check(z.phase=="advance"or z.phase=="vomit"or z.phase=="stunned")end
for _,key in ipairs({"phaseTime","abilityCooldown","shotCooldown","biteSoundCooldown"})do if z[key]~=nil then check(number(z[key],0,120))end end
z.biteSoundCooldown=nil
if z.viewSlot then check(number(z.viewSlot,1,48,true)and not viewSlots[z.viewSlot]);viewSlots[z.viewSlot]=true end
if z.attackTime~=nil then
check(number(z.attackTime,0,C.enemies[z.kind].melee.period)and type(z.attackHit)=="boolean"and number(z.attackCol,1,9,true))
end
end
for _,z in ipairs(r.zombies)do if not z.viewSlot then z.viewSlot=freeEnemySlot(r.zombies)end end
for _,b in ipairs(r.bullets)do
check(type(b)=="table"and number(b.row,1,5,true)and number(b.x,0,1100)and number(b.remaining,0,1100))
check(number(b.damage,1,100)and type(b.ice)=="boolean"and type(b.spore)=="boolean")
end
for _,b in ipairs(r.enemyBolts)do
check(type(b)=="table"and number(b.row,1,5,true)and number(b.x,0,1100)and number(b.remaining,0,600))
check(number(b.damage,0,300)and number(b.speed,1,1000))
end
for _,s in ipairs(r.suns)do
check(type(s)=="table"and number(s.x,100,940)and number(s.y,140,520)and number(s.ttl,0,20))
check(s.value==15 or s.value==25)
end
for _,m in ipairs(r.mowers)do check(number(m,-1,1000))end
end
local book=copy(ctx.save.data)
if next(book)==nil then book={format=1,slots={},active=0,sound=true,music=true}end
if book.speed==nil then book.speed=1 end
if book.music==nil then book.music=true end
if book.musicVolume==nil then book.musicVolume=1 end
if book.musicSource==nil then book.musicSource="auto"end
check(book.musicSource=="auto"or book.musicSource=="native")
if book.hitVolume==nil then book.hitVolume=.5 end
if book.soundVolume==nil then book.soundVolume=1 end
check(number(book.hitVolume,0,1)and number(book.soundVolume,0,1)and number(book.musicVolume,0,1))
check(book.speed==1 or book.speed==2)
check(book.format==1 and type(book.slots)=="table"and number(book.active,0,3,true)and type(book.sound)=="boolean"and type(book.music)=="boolean")
local trackers={}
for key,slot in pairs(book.slots)do
check(key=="1"or key=="2"or key=="3")
check(type(slot)=="table"and type(slot.name)=="string"and#slot.name<=60)
check(number(slot.cleared,0,10,true)and number(slot.coins,0,1000000,true))
if slot.run then validateRun(slot.run,slot.cleared)end
trackers[key]=modules.progress.new(slot.progress,{cleared=slot.cleared})
slot.progress=trackers[key].data
end
local screen,selected,message,saveStatus="profiles","pea","","存档保存在本道具"
local slot,run,render,confirm,help,dirty,saveTimer,drawTimer
local pauseMenu,settings,lastPauseSaved=false,false,true
local musicSettings,musicPreview,musicError=false,nil,nil
local tracker,progressTab,progressWasPaused,achievementNotice
local achievementTTL=0
saveTimer,drawTimer=0,0
local sunEffects={}
local function say(text)message=text end
local function sound(id)if book.sound then ctx.sound.play(id)end end
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
return messages[reason]or"音乐播放失败（"..tostring(reason).."）。"
end
local function sceneMusicId()
if screen=="profiles"or screen=="map"then return"menu"end
if screen=="battle"and run and run.status=="playing"then
return(run.mode=="endless"or C.campaign[run.level].theme=="night")and"battle_night"or"battle_day"
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
local ok,why=ctx.save.flush(reason)
if ok then dirty=false;saveTimer=0;saveStatus="已自动保存"
else dirty=true;saveTimer=0;saveStatus="保存失败，请勿关闭道具";ctx.ui.notify("存档未写入："..tostring(why))end
return ok
end
local function changed()dirty=true end
local function record(event,payload)
if not tracker then return end
local gained=tracker.record(event,payload)
if event~="time"then changed()end
if#gained>0 then
local titles={};for _,a in ipairs(gained)do titles[#titles+1]=a.title end
achievementNotice="成就达成："..table.concat(titles," · ");achievementTTL=5
sound("ui_select")
end
end
local function openPauseMenu(reason)
closeMusicSettings()
pauseMenu=true;settings=false;help=false;confirm=nil;progressTab=nil
if ctx.session.isPaused()then lastPauseSaved=persist(reason or"pause_menu")
else ctx.session.pause(reason or"pause_menu")end
if render then render()end
return lastPauseSaved
end
local function resumeGame()
closeMusicSettings()
pauseMenu=false;settings=false;help=false;progressTab=nil;ctx.session.resume()
end
local function random(n)
run.rng=(run.rng*16807)%2147483647
return(run.rng%n)+1
end
local function unlockCount()return slot and min(10,slot.cleared+1)or 1 end
local function addSun(x,y,value)
if#run.suns>=60 then return end
run.suns[#run.suns+1]={x=x,y=y,value=value,ttl=16}
end
local function collect(index)
if screen~="battle"or not run or run.status~="playing"or ctx.session.isPaused()then return end
local s=run.suns[index];if not s then return end
if#sunEffects<60 then sunEffects[#sunEffects+1]={x=s.x,y=s.y,value=s.value,ttl=.45}end
ctx.fx.burst("sun_collect",{x=s.x,y=s.y,seed=run.rng})
local amount=min(s.value,9990-run.sun)
run.sun=run.sun+amount;table.remove(run.suns,index);sound("sun");record("sun",{amount=amount});changed()
end
local function collectAll()
if not run then return end
for i=#run.suns,1,-1 do collect(i)end
end
local function createSlot(index)
local key=tostring(index);if book.slots[key]then return end
local previous=book.active
local value={name="花园 "..index,cleared=0,coins=0}
local progress=modules.progress.new()
value.progress=progress.data
book.slots[key]=value;book.active=index
if not persist("create_profile")then book.slots[key]=nil;book.active=previous;return end
trackers[key]=progress;tracker=progress
slot=value;run=nil;screen="map";progressTab=nil;achievementNotice=nil;message="第一关已开放。点击地图上的 1 开始。"
playSceneMusic()
end
local function loadSlot(index)
local value=book.slots[tostring(index)];if not value then return end
if dirty and not persist("before_load")then return end
slot=value;run=slot.run;book.active=index;screen=run and"battle"or"map";selected="pea";sunEffects={};ctx.fx.clear()
tracker=trackers[tostring(index)];progressTab=nil;achievementNotice=nil
ctx.level.load(run and C.campaign[run.level].theme=="night"and"lawn_night"or"lawn_day");playSceneMusic()
changed();persist("load_profile");message=run and"战局已恢复。阳光、冷却和波次均保留。"or"选择已开放的关卡。"
if run and run.status=="playing"then ctx.session.pause("loaded_game")end
end
local function deleteSlot(index)
local key=tostring(index);local previous=book.slots[key];local active=book.active
book.slots[key]=nil;if active==index then book.active=0 end
if not persist("delete_profile")then book.slots[key]=previous;book.active=active;return end
trackers[key]=nil
if active==index then slot=nil;run=nil;tracker=nil;progressTab=nil;achievementNotice=nil end
confirm=nil;say("存档已删除，可以在这个位置重新建档。")
end
local function startLevel(level)
if not slot or level>min(10,slot.cleared+1)then return end
local def=C.campaign[level]
run={mode="campaign",level=level,status="playing",time=0,sun=def.sun,nextSky=def.sky>0 and def.sky or 0,
nextWave=def.prepare,wave=0,waveTime=0,spawnIndex=1,spawnClock=0,plants={},zombies={},bullets={},enemyBolts={},suns={},
mowers={0,0,0,0,0},cooldowns={},kills=0,rng=1977+level*7919}
slot.run=run;selected="pea";screen="battle";sunEffects={};ctx.fx.clear();ctx.level.load(def.theme=="night"and"lawn_night"or"lawn_day")
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
if not persist("return_to_map")then return end
screen=slot and"map"or"profiles";ctx.fx.clear();ctx.music.stop("return_to_map");resumeGame()
playSceneMusic()
say(slot and"当前战局已保留，点击“继续战局”返回。"or"选择存档或建立新的防线。")
end
local function plantAt(row,col,mouse)
if screen~="battle"or ctx.session.isPaused()or not run or run.status~="playing"or not rowActive(run.level,row)then return end
if mouse=="RightButton"then selected=nil;say("已取消选择。");return end
local key=cellKey(row,col)
if selected=="shovel"then
if run.plants[key]then run.plants[key]=nil;changed();sound("plant");say("已铲除，不返还阳光。")end
return
end
local p=plants[selected];if not p then say("先点击一张种子卡。");return end
if run.plants[key]then say("这里已有植物。用铲子移除后再种植。");return end
if plantIndex[selected]>unlockCount()then return end
if run.sun<p.cost then say("阳光不足：需要 "..p.cost.." 阳光。");return end
if(run.cooldowns[selected]or 0)>0 then say("种子还在冷却。");return end
local value={kind=selected,row=row,col=col,hp=p.hp,age=0,timer=(selected=="sunflower"or selected=="sunshroom")and 6 or 0}
run.plants[key]=value;run.sun=run.sun-p.cost;run.cooldowns[selected]=p.reload;sound("plant");changed()
record("plant",{kind=selected,cost=p.cost})
say(p.name.."已种下。"..(selected=="mine"and"12秒后武装。"or p.tip))
end
local function nearest(row,x,range)
local target
for _,z in ipairs(run.zombies)do
if z.hp>0 and z.row==row and z.x>=x-18 and z.x-x<=range and(not target or z.x<target.x)then target=z end
end
return target
end
local function blast(row,x,radius,rows,lethal)
for _,z in ipairs(run.zombies)do
if abs(z.row-row)<=rows and abs(z.x-x)<=radius then z.hp=lethal and 0 or z.hp-1800 end
end
vfx.explosion(x,rowY(row)+32,radius)
sound("explode")
end
local function fire(p,offset)
if#run.bullets>=160 then return end
run.bullets[#run.bullets+1]={row=p.row,x=cellX(p.col)+24-(offset or 0),remaining=p.kind=="puff"and 252 or 920,
damage=plants[p.kind].damage,ice=p.kind=="snow",spore=p.kind=="puff"}
end
local schedules={}
for level,def in ipairs(C.campaign)do
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
if run.status~="playing"then return end
run.status=status;run.enemyBolts={};ctx.music.stop("battle_finished")
removeDefeated()
if run.mode=="endless"then
record("endless_progress",{round=run.round,score=run.score})
say("无尽挑战结束：到达第 "..run.round.." 轮，获得 "..run.score.." 分。")
sound("lose");changed();persist("endless_"..status);return
end
local noMowersUsed=true;for _,mower in ipairs(run.mowers)do if mower~=0 then noMowersUsed=false end end
record(status=="won"and"win"or"loss",{level=run.level,duration=run.time,noMowersUsed=noMowersUsed})
if status=="won"then
local first=run.level>slot.cleared
if first then slot.cleared=run.level;slot.coins=slot.coins+100+run.level*25 end
say(first and run.level==10 and"十关通关！无尽挑战已解锁。"or first and("首次通关！获得 "..(100+run.level*25).." 金币。")or"再次守住了庭院。")
sound("win")
else say("僵尸进入了家门。重试本关，调整你的防线。");sound("lose")end
changed();persist(status)
end
local function simulate(dt)
if screen~="battle"or not run or run.status~="playing"then return end
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
if run.spawnIndex<=total and run.spawnClock<=0 and#run.zombies<48 then
local kind=endlessKind(plan,total,run.round,run.spawnIndex);local d=C.enemies[kind]
local rows=endlessRows(run.round);local row=rows[random(#rows)];local viewSlot=freeEnemySlot(run.zombies)
run.zombies[#run.zombies+1]={kind=kind,row=row,x=925,hp=d.hp,slow=0,jumped=false,viewSlot=viewSlot}
run.spawnIndex=run.spawnIndex+1
run.spawnClock=max(ENDLESS.spawnIntervalMin,ENDLESS.spawnIntervalBase-run.round*ENDLESS.spawnIntervalStep)
end
if run.spawnIndex>total and#run.zombies==0 then
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
if run.wave==0 then
if run.time>=run.nextWave then run.wave=1;run.waveTime=run.time;run.spawnClock=0;sound("wave");changed()end
end
if run.wave>0 then
local sequence=schedules[run.level][run.wave];local wave=def.waves[run.wave]
run.spawnClock=max(0,run.spawnClock-dt)
if run.spawnIndex<=#sequence and run.spawnClock<=0 and#run.zombies<48 then
local kind=sequence[run.spawnIndex];local d=C.enemies[kind]
local row=def.rows[random(#def.rows)]
local viewSlot=freeEnemySlot(run.zombies)
run.zombies[#run.zombies+1]={kind=kind,row=row,x=925,hp=d.hp,slow=0,jumped=false,viewSlot=viewSlot}
run.spawnIndex=run.spawnIndex+1;run.spawnClock=wave.interval
end
if run.spawnIndex>#sequence and#run.zombies==0 then
if run.wave==#def.waves then finish("won");return end
if run.nextWave<=run.waveTime then run.nextWave=run.time+wave.gap;changed()end
if run.time>=run.nextWave then
run.wave=run.wave+1;run.waveTime=run.time;run.spawnIndex=1;run.spawnClock=0
sound("wave");say(run.wave==#def.waves and"最后一波！守住家门！"or"第 "..run.wave.." 波来袭。");changed()
end
end
end
end
for key,p in pairs(run.plants)do
p.age=p.age+dt;p.timer=max(0,p.timer-dt)
local sleeping=(p.kind=="puff"or p.kind=="sunshroom")and def.theme~="night"
if not sleeping then
if p.kind=="cherry"and p.age>=1.2 then blast(p.row,cellX(p.col),126,1);run.plants[key]=nil
elseif p.kind=="mine"and p.age>=12 and nearest(p.row,cellX(p.col),BITE_CONTACT)then blast(p.row,cellX(p.col),48,0,true);run.plants[key]=nil
elseif p.kind=="chomper"then
local z=nearest(p.row,cellX(p.col),CELL_WIDTH+BITE_CONTACT)
if p.timer<=0 and z then z.hp=0;p.timer=20;sound("hit_devour")end
elseif p.kind=="sunflower"or p.kind=="sunshroom"then
if p.timer<=0 then addSun(cellX(p.col)+8,rowY(p.row)+20,p.kind=="sunshroom"and p.age<90 and 15 or 25);p.timer=plants[p.kind].interval end
elseif plants[p.kind].damage and p.timer<=0 and nearest(p.row,cellX(p.col),p.kind=="puff"and 252 or 1000)then
fire(p);if p.kind=="repeater"then fire(p,24)end;p.timer=plants[p.kind].interval
end
end
end
for i=#run.bullets,1,-1 do
local b=run.bullets[i];local old=b.x;local dx=min(320*dt,b.remaining);b.x=b.x+dx;b.remaining=b.remaining-dx
local target
for _,z in ipairs(run.zombies)do
if z.hp>0 and z.row==b.row and z.x+18>=old and z.x-18<=b.x and(not target or z.x<target.x)then target=z end
end
if target then
target.hp=target.hp-b.damage;if b.ice then target.slow=5 end
vfx.impact(b.ice,b.spore,max(old,min(b.x,target.x-18)),rowY(b.row)+31)
sound(b.ice and"hit_frost"or b.spore and"hit_spore"or"hit_nature")
end
if target or b.x>950 or b.remaining<=0 then table.remove(run.bullets,i)end
end
elite.projectiles(run,dt,sound)
for _,z in ipairs(run.zombies)do
if z.hp>0 then
local d=C.enemies[z.kind];z.slow=max(0,z.slow-dt)
local speed=d.speed*(z.slow>0 and.5 or 1)
if z.kind=="pole"and z.jumped then speed=speed*.58 end
if z.kind=="paper"and z.hp<=180 then speed=speed*2.2 end
local obstacle
for _,p in pairs(run.plants)do
local x=cellX(p.col)
if p.row==z.row and z.x>=x-18 and z.x<=x+BITE_CONTACT and(not obstacle or p.col>obstacle.col)then obstacle=p end
end
local blocked=elite.step(z,run,dt,sound)
if not blocked and obstacle then
if z.kind=="pole"and not z.jumped then z.jumped=true;z.x=cellX(obstacle.col)-52;elite.cancelMelee(z)
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
run.mowers[row]=nextX>965 and-1 or nextX
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
if plantIndex[id]>unlockCount()then say("通关前一关后，在第 "..plantIndex[id].." 关解锁。");return end
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
if not musicSettings or not book.music or(id~="battle_day"and id~="battle_night"and id~="menu")then return end
ctx.music.stop("preview_switch");musicPreview=id;musicError=nil
local ok,reason=ctx.music.play(id,{loop=true,playWhilePaused=true,retry=true})
if not ok then musicPreview=nil;musicError=musicFailure(reason)end
end,
stopMusicPreview=function()
if not musicSettings then return end
musicPreview=nil;musicError=nil;ctx.music.stop("preview_stopped")
end,
showProgress=function()
if not tracker or screen=="profiles"then return end
progressWasPaused=ctx.session.isPaused();progressTab="stats";help=false;settings=false;confirm=nil
ctx.session.pause("progress")
end,
progressTab=function(tab)progressTab=tab=="achievements"and"achievements"or"stats"end,
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
if run and run.status=="playing"then confirm={kind="replace",level=level}else startLevel(level)end
end,
openProfiles=function()if persist("profiles")then screen="profiles";progressTab=nil;ctx.fx.clear();ctx.music.stop("profiles");ctx.session.resume();playSceneMusic()end end,
continueBattle=function()
if run then screen="battle";ctx.level.load(C.campaign[run.level].theme=="night"and"lawn_night"or"lawn_day");playSceneMusic()else startLevel(1)end
end,
toggleShovel=function()selected=selected=="shovel"and nil or"shovel";say("点击植物铲除；不返还阳光。")end,
toggleSound=function()book.sound=not book.sound;ctx.sound.setEnabled(book.sound);changed();persist("sound_setting")end,
adjustVolume=function(bus,delta)
local key=bus=="impact"and"hitVolume"or"soundVolume"
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
book.musicSource=book.musicSource=="auto"and"native"or"auto"
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
changed();persist("speed_setting");say(book.speed==2 and"2倍速：整场战局和冷却同步加速。"or"已恢复正常速度。")
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
return{book=book,slot=slot,run=run,screen=screen,selected=selected,message=message,
saveStatus=saveStatus,sunEffects=sunEffects,help=help,confirm=confirm,pauseMenu=pauseMenu,settings=settings,
music={open=musicSettings,preview=musicPreview,error=musicError or(ctx.music.lastError and musicFailure(ctx.music.lastError)),state=ctx.music.state,
track=sceneMusicId(),source=book.musicSource,backend=ctx.music.backend,
musicianAvailable=ctx.music.capabilities().musician,fallback=ctx.music.fallbackReason},
achievementNotice=achievementNotice,progress=progressTab and tracker and{
tab=progressTab,summary=tracker.summary(),achievements=tracker.achievements()}or nil}
end
return{
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
if(dirty and saveTimer>=.65)or(screen=="battle"and run.status=="playing"and saveTimer>=5)then persist("autosave")end
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
end)()
local function createGame(ctx)return gameFactory(ctx,gameModules)end
E.registerGame("garden_defense_wow",{apiVersion=1,saveVersion=1,create=createGame})
args.custom.ig_status="ready"
G.TRP3_API.script.runWorkflow(args,"o","wf_open")