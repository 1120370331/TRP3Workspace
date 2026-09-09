// Keep the protected macro under TRP3's actual 255-byte editor limit.
// It only arms a root-scoped, one-use injector. The delayed Lua does all loading.
export function makeBootstrap(rootId) {
  if (!/^[a-zA-Z0-9]+$/.test(rootId)) throw new Error('Invalid bootstrap root ID');
  const macro = `/run local a,k=TRP3_API.script,"runLuaScriptEffect"local f,w=a[k]local function z()if w==a[k]then a[k]=f end;w=nil end;w=function(c,x,s)if w and x and x.classID=="${rootId}"then z()x._G=not s and _G end return f(c,x,s)end;a[k]=w;C_Timer.After(2,z)`;
  const bytes = Buffer.byteLength(macro, 'utf8');
  if (bytes > 255) throw new Error(`Bootstrap macro is ${bytes} bytes; TRP3 permits 255. Root ID is too long for this template.`);
  const launch = `-- ItemGame delayed launch: this script must follow the macro and a 0.1s delay.
local function report(stage,message)
 if args.object then setVar(args,"o","IG_BOOT_STATUS_V1",stage..": "..message) end
 effect("text",args,"[IG "..stage.."] "..message,1)
end
report("1/3","延时后的 Lua 已执行")
if not args.object or args.object.id~="${rootId}" then
 report("CONTEXT","请从 TRP3 背包使用主道具，不要预览执行启动工作流。")
 return
end
local G=args._G
if type(G)~="table" then
 report("INJECTION","宏注入未生效或脚本受限。入口必须为：短宏 → 延时 0.1 秒 → Lua。")
 return
end
args._igLaunchMS=G.debugprofilestop and G.debugprofilestop() or G.GetTime()*1000
args.custom=args.custom or {}
setVar(args,"o","IG_CONTROL_V1",nil)
setVar(args,"o","IG_LAUNCH_TOKEN",nil)
report("2/3","GUI 能力已注入，开始加载引擎")
local ok,err=G.pcall(G.TRP3_API.script.runWorkflow,args,"o","wf_bootstrap")
if not ok then
 local E=G.TRP3_ItemGame
 if E and E.current and E.current.host.item==args.object then G.pcall(E.current.stop,"bootstrap_error",{save=false}) end
 report("BOOTSTRAP",G.tostring(err))
end
`;
  return {macro, launch, delay:0.1, timeout:2, macroBytes:bytes};
}
