"""Selected release packages through the upstream TRP3 workflow compiler (mock WoW)."""
from pathlib import Path
import importlib.util
import json
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('engine_checks',ROOT/'tools/test-engine.py')
engine=importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)


class PackageTests(unittest.TestCase):
    item_dir='performance-lab'
    setUp=engine.EngineTests.setUp
    advance=engine.EngineTests.advance
    native_package=engine.EngineTests.native_package
    native_startup=engine.EngineTests.native_startup

    @classmethod
    def setUpClass(cls):
        (ROOT/'.test-output').mkdir(exist_ok=True)
        cls.fixtures=Path(tempfile.mkdtemp(prefix='package-runtime-',dir=ROOT/'.test-output'))
        cases={
            'minimal':([], 'release', '''return function(ctx)
 local steps=0
 return {onStart=function()
  assert(ctx.hasPackage("runtime") and not ctx.hasPackage("world") and not ctx.hasPackage("audio"))
  ctx.ui.button("save","Save",function()ctx.save.flush("button")end)
 end,onFixedUpdate=function()steps=steps+1 end,
 onSave=function()return {steps=steps, text=[=[中文\n-- literal]=], concat=1 .. 2, value=3 - -2}end}
end'''),
            'scene':(['scene3d'],'release','''return function(ctx)
 return {onStart=function()
  assert(not ctx.hasPackage("particles3d"));local scene=ctx.scene3d.create()
  scene.create("box",{mesh=ctx.scene3d.boxMesh()})
 end,onSave=function()return {ok=true}end}
end'''),
            'missing':([], 'release','return function(ctx)return {onStart=function()ctx.world.spawn("hero")end}end'),
            'development':([], 'development','return function(ctx)return {onStart=function()end,onSave=function()return {ok=true}end}end'),
        }
        content={'viewport':{'width':640,'height':480},'limits':{'maxEntities':1},'controls':{},'prefabs':{},'actions':{},'levels':{},'assets':{},'sounds':{},'music':{},'items':{}}
        paths=[]
        for name,(packages,profile,source) in cases.items():
            path=cls.fixtures/name;path.mkdir()
            manifest=json.loads((ROOT/'items/performance-lab/item.json').read_text('utf-8'))
            # This relative engine path matches the fixture's bounded depth.
            manifest.update(engine='../../../framework/item-game',packages=packages,build={'profile':profile,'logs':{'maxBytes':8192}})
            (path/'item.json').write_text(json.dumps(manifest,ensure_ascii=False),encoding='utf-8')
            (path/'content.json').write_text(json.dumps(content),encoding='utf-8')
            (path/'game.lua').write_text(source,encoding='utf-8')
            paths.append(str(path/'item.json'))
        command="import {build} from './tools/build-item-game.mjs';for(const path of JSON.parse(process.argv[1]))await build(path);"
        subprocess.run(['node','--input-type=module','-e',command,json.dumps(paths)],cwd=ROOT,check=True,capture_output=True,text=True)

    def launch(self,name):
        self.package_path=self.fixtures/name/'dist/item.t3e.txt'
        self.native_startup()
        self.lua.globals().Mock.executeMacro(self.lua.globals().Mock.prepareUse())
        self.advance(.2)

    def test_minimal_release_runs_saves_pauses_and_cleans_up_without_optional_systems(self):
        self.launch('minimal')
        self.lua.execute('''
local e=assert(TRP3_ItemGame);local s=assert(e.current)
assert(e.newWorld==nil and e.newSound==nil and e.newSurface==nil and e.newEffects==nil)
assert(s.world==nil and s.sound==nil and s.effects==nil and e.effectsViewCache==nil)
assert(s.callbacks.onSave().steps>0)
local v=s.callbacks.onSave();assert(v.concat=="12" and v.value==5 and v.text:find("-- literal",1,true))
savedTime=s.time;s.pause("test")
''')
        self.advance(.3)
        self.lua.execute('assert(TRP3_ItemGame.current.time==savedTime);TRP3_ItemGame.current.resume()')
        self.advance(.1)
        self.lua.execute('''
local s=TRP3_ItemGame.current;assert(s.time>savedTime);assert(s.ctx.save.flush("test"))
assert(TRP3_ItemGame.JSON.decode(item.vars.IG_SAVE_V1).game.steps>0)
s.requestClose("window_closed");assert(TRP3_ItemGame.current==nil)
assert(item.vars.IG_PERF_LOG_V1==nil)
assert(TRP3_API.script.runLuaScriptEffect==Mock.originalExecutor)
for _,f in ipairs(Mock.frames)do assert(f:GetScript("OnUpdate")==nil)end
''')

    def test_scene3d_without_particle_package_projects_and_closes(self):
        self.launch('scene')
        self.lua.execute('''
local s=assert(TRP3_ItemGame.current)
assert(s.scene3d.particles==nil and TRP3_ItemGame.newParticles3D==nil)
assert(s.scene3d.stats().scene3DDraws>0)
s.pause("test");s.resume();s.stop("test")
assert(TRP3_ItemGame.current==nil)
''')

    def test_missing_api_fails_with_package_name_and_restores_native_executor(self):
        self.launch('missing')
        self.lua.execute('''
assert(TRP3_ItemGame.current==nil)
assert(table.concat(Mock.messages,"\\n"):find("package_not_included: world",1,true))
assert(TRP3_API.script.runLuaScriptEffect==Mock.originalExecutor)
assert(item.vars.IG_SAVE_V1==nil)
''')

    def test_release_logs_are_bounded_and_only_explicitly_persisted(self):
        self.launch('minimal')
        self.lua.execute('TRP3_ItemGame.current.ctx.perf.begin("test",{},{warmup=0,duration=.05})')
        self.advance(.2)
        self.lua.execute('''
local s=TRP3_ItemGame.current;assert(s.perf.completed==1 and item.vars.IG_PERF_LOG_V1==nil)
for i=1,100 do s.perf.note("large",{text=string.rep("a",500)})end
assert(s.ctx.perf.saveLog());local saved=item.vars.IG_PERF_LOG_V1
assert(#saved<=8192 and saved:find("log.status",1,true))
s.stop("test");assert(item.vars.IG_PERF_LOG_V1==saved)
''')

    def test_development_keeps_automatic_logs(self):
        self.launch('development')
        self.lua.execute('TRP3_ItemGame.current.stop("test");assert(item.vars.IG_PERF_LOG_V1:find("run.end",1,true))')


if __name__=='__main__':
    unittest.main(verbosity=2)
