"""Surface effect color, geometry independence and lifecycle contracts."""
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.local-tools/python'))
from lupa.lua51 import LuaRuntime

class SurfaceEffects3DTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute('E={}')
        for name in ['core','math3d','surface-effects3d','scene3d']:
            self.lua.execute((ROOT/f'framework/item-game/{name}.lua').read_text('utf-8'))(self.lua.globals().E,self.lua.globals())
        self.lua.execute('''
M=E.math3d;s=E.newScene3D({width=400,height=300})
s.setCamera({position=M.vec(0,0,8),target=M.vec()})
s.create("box",{mesh=E.boxMesh(1,{.1,.2,.3,.7})})
''')

    def test_pulse_only_changes_colors_and_preserves_picking(self):
        self.lua.execute('''
local original=s.renderList();local points=original[1].points;local base=original[1].color[1]
s.effects.set("box",{color={1,0,0},emissive=.1,pulse=.2,speed=1})
local revision=s.revision;local first=s.renderList()[1].color[1]
s.step(.1);local next=s.renderList()
assert(next==original and next[1].points==points and s.revision==revision)
assert(next[1].color[1]>first and s.stats().scene3DProjectedVertices==0)
assert(next[1].color[4]==.7 and s.pick(200,150).id=="box")
s.effects.set("box",nil);assert(math.abs(s.renderList()[1].color[1]-base)<1e-8)
assert(not s.effects.capabilities().customGPUShader)
''')

    def test_rim_depends_on_camera_and_fog_keeps_alpha(self):
        self.lua.execute('''
s.effects.set("box",{color={1,0,0},rim=1,power=2})
local face=s.renderList()[1];local facing=face.color[1]
s.setCamera({position=M.vec(6,0,8)});local edge
for _,f in ipairs(s.renderList())do if f.sourceFace==face.sourceFace then edge=f.color[1]end end
assert(edge>facing)
s.effects.setFog({near=0,far=1,color={.2,.4,.6}})
for _,f in ipairs(s.renderList())do assert(f.color[1]==.2 and f.color[2]==.4 and f.color[3]==.6 and f.color[4]==.7)end
assert(not pcall(s.effects.setFog,{near=2,far=1}))
assert(not pcall(s.effects.set,"box",{rim=2}))
s.effects.setFog(nil);s.effects.set("box",nil)
assert(s.renderList()[1].color[1]<.2)
''')

    def test_remove_clear_and_pause_clock_do_not_leak_animation(self):
        self.lua.execute('''
s.effects.set("box",{pulse=.2,speed=1});s.effects.setFog({near=1,far=9,color={0,0,0}})
s.renderList();local revision=s.shadingRevision;s.step(0);assert(s.shadingRevision==revision)
s.clear();local revision=s.shadingRevision;s.step(.1);assert(s.shadingRevision==revision)
s.create("box",{mesh=E.boxMesh()});assert(s.renderList()[1].color[1]>.5)
s.effects.set("box",{pulse=.2});s.remove("box");local revision=s.shadingRevision
s.step(.1);assert(s.shadingRevision==revision)
s.dispose();assert(s.effects.set("box",{})==false)
''')

if __name__=='__main__':unittest.main(verbosity=2)
