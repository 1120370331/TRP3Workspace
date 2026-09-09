-- ItemGame delayed launch: this script must follow the macro and a 0.1s delay.
local function report(stage,message)
 if args.object then setVar(args,"o","IG_BOOT_STATUS_V1",stage..": "..message) end
 effect("text",args,"[IG "..stage.."] "..message,1)
end
report("1/3","延时后的 Lua 已执行")
if not args.object or args.object.id~="0905221530PvZ01" then
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
