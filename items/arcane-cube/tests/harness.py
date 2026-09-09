"""Runs the shipped Lua engine/game with the existing labelled WoW host double."""
from pathlib import Path
import importlib.util
import json
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('engine_checks', ROOT / 'tools/test-engine.py')
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)


class CubeHarness(unittest.TestCase):
    item_dir = 'arcane-cube'
    setUp = engine.EngineTests.setUp
    start = engine.EngineTests.start
    advance = engine.EngineTests.advance
    native_package = engine.EngineTests.native_package
    native_startup = engine.EngineTests.native_startup

    def boot(self):
        project = ROOT / 'items' / self.item_dir
        manifest = json.loads((project / 'item.json').read_text('utf-8'))
        parts = ['local gameModules={}']
        for name, path in sorted(manifest['modules'].items()):
            parts.append('gameModules[' + json.dumps(name) + ']=(function()\n' + (project / path).read_text('utf-8') + '\nend)()')
        parts.append('local factory=(function()\n' + (project / 'game.lua').read_text('utf-8') + '\nend)()')
        parts.append('return function(ctx)return factory(ctx,gameModules)end')
        self.lua.execute('''
Mock.nodes={}
if not Mock.originalSurface then
 Mock.originalSurface=E.newSurface
 E.newSurface=function(...)
  local surface=Mock.originalSurface(...);local draw=surface.draw
  surface.draw=function(id,spec)local node=draw(id,spec);node.previewSpec=spec;Mock.nodes[id]=node;return node end
  return surface
 end
end
function clickNode(id,button)
 local node=assert(Mock.nodes[id],"unknown UI node: "..id)
 assert(node.object:IsShown() and node.enabled,"inactive UI node: "..id)
 node.object:GetScript("OnClick")(node.object,button or "LeftButton")
 assert(not session.stopping,"game stopped")
end
function snapshot()return session.callbacks.onSave()end
''')
        self.start('\n'.join(parts))
        self.advance(.02)
        self.lua.execute('''
local scene=session.scene3d
-- Deliberate screen-coordinate fixture. Native GetLeft/GetTop are supplied by WoW.
scene.cache.root.GetLeft=function()return 0 end
scene.cache.root.GetTop=function()return 610 end
Mock.cursorX=0;Mock.cursorY=610;Mock.mouse={}
function GetCursorPosition()
 local scale=scene.cache.root:GetEffectiveScale()
 return Mock.cursorX*scale,Mock.cursorY*scale
end
function IsMouseButtonDown(button)return Mock.mouse[button]==true end
function pointer(phase,x,y,button,delta)
 local f=session.scene3d.inputFrame;Mock.cursorX=x;Mock.cursorY=610-y
 if phase=="down" then Mock.mouse[button]=true;f:GetScript("OnMouseDown")(f,button)
 elseif phase=="up" then Mock.mouse[button]=false;f:GetScript("OnMouseUp")(f,button)
 elseif phase=="wheel" then f:GetScript("OnMouseWheel")(f,delta)
 else session.scene3d.render() end
end
''')

    def click(self, key):
        self.lua.globals().clickNode(key)

    def state(self):
        return self.lua.globals().snapshot()

    def restart(self):
        self.lua.execute('session.stop("test_close")')
        self.boot()

    def serial(self, value):
        return json.loads(self.E.JSON.encode(value))
