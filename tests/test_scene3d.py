"""Host-independent geometric contracts and clipping regressions for Scene3D."""
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.local-tools/python'))
from lupa.lua51 import LuaRuntime

class Scene3DTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute('E={}')
        for name in ['core','math3d','scene3d']:
            self.lua.execute((ROOT/f'framework/item-game/{name}.lua').read_text('utf-8'))(self.lua.globals().E,self.lua.globals())

    def test_affine_inverse_hierarchy_and_cycle_rejection(self):
        self.lua.execute('''
local M=E.math3d;local s=E.newScene3D()
s.create("parent",{position=M.vec(3,2,1),rotation=M.vec(.2,.5,.7),scale=M.vec(2,3,4)})
s.create("child",{parent="parent",position=M.vec(1,0,0),mesh=E.boxMesh()})
local p=s.worldPoint("child",M.vec(.1,.3,.5));local back=M.point(M.inverse(s.get("child").matrix),p)
assert(M.length(M.sub(back,M.vec(.1,.3,.5)))<1e-8)
assert(not pcall(s.setParent,"parent","child"))
s.remove("parent");assert(#s.order==0)
''')

    def test_projection_ray_roundtrip_and_nearest_visible_hit(self):
        self.lua.execute('''
local M=E.math3d;local s=E.newScene3D({width=600,height=400})
s.setCamera({position=M.vec(0,0,8),target=M.vec()})
s.create("front",{position=M.vec(0,0,2),mesh=E.boxMesh()})
s.create("back",{mesh=E.boxMesh()})
local x,y=s.project(M.vec(.2,.1,2));local o,d=s.screenRay(x,y)
assert(M.length(M.cross(d,M.sub(M.vec(.2,.1,2),o)))<1e-8)
assert(s.pick(x,y).id=="front")
s.setVisible("front",false);assert(s.pick(300,200).id=="back")
assert(s.pick(-1,200)==nil)
''')

    def test_six_plane_clipping_stays_finite_inside_viewport(self):
        self.lua.execute('''
local M=E.math3d;local s=E.newScene3D({width=200,height=100})
s.setCamera({position=M.vec(0,0,2),target=M.vec(),near=.2,far=10})
local mesh=E.boxMesh(2);for _,face in ipairs(mesh.faces)do face.doubleSided=true end
s.create("crossing",{position=M.vec(0,0,1.7),rotation=M.vec(.3,.2,.1),mesh=mesh})
local list=s.renderList();assert(#list>0)
for _,f in ipairs(list)do for _,p in ipairs(f.points)do
 assert(p.x>=-1e-7 and p.x<=200+1e-7 and p.y>=-1e-7 and p.y<=100+1e-7)
end end
s.setTransform("crossing",{position=M.vec(0,0,-20)});assert(#s.renderList()==0)
''')

    def test_spatial_query_sweep_and_fixed_velocity(self):
        self.lua.execute('''
local M=E.math3d;local s=E.newScene3D()
s.create("wall",{position=M.vec(10,0,0),mesh=E.boxMesh(2),collider=true})
local b={min=M.vec(-1,-1,-1),max=M.vec(1,1,1)}
local hit=assert(s.sweepAABB(b,M.vec(100,0,0)))
assert(hit.id=="wall" and math.abs(hit.time-.08)<1e-8 and hit.normal.x==-1)
assert(s.sweepAABB(b,M.vec(100,100,0))==nil)
local touching={min=M.vec(7,-1,-1),max=M.vec(9,1,1)}
assert(s.sweepAABB(touching,M.vec(-1,0,0))==nil,"moving away from contact must not stick")
assert(s.sweepAABB(touching,M.vec(0,1,0))==nil,"sliding along contact must not stick")
assert(s.sweepAABB(touching,M.vec(1,0,0)).time==0,"moving into contact must collide")
assert(#s.queryAABB({min=M.vec(8,-2,-2),max=M.vec(12,2,2)})==1)
s.create("moving",{velocity=M.vec(1,2,3)})
s.step(.1);assert(math.abs(s.get("moving").position.z-.3)<1e-8)
''')

    def test_budgets_invalid_input_and_closed_scene(self):
        self.lua.execute('''
local s=E.newScene3D({maxNodes=1,maxFaces=6})
s.create("box",{mesh=E.boxMesh()})
assert(not pcall(s.create,"extra",{}))
assert(not pcall(s.setCamera,{near=0}))
assert(not pcall(s.setParent,"box","box"))
s.dispose();assert(s.create("late",{})==nil and #s.renderList()==0)
''')

    def test_offscreen_skin_is_deferred_but_motion_and_collision_remain_live(self):
        self.lua.execute((ROOT/'framework/item-game/pixel-materials.lua').read_text('utf-8'))(self.lua.globals().E,self.lua.globals())
        self.lua.execute('''
local M=E.math3d;local s=E.newScene3D({width=400,height=300})
s.setCamera({position=M.vec(0,0,8),target=M.vec()})
s.definePixelTexture("grid",{width=4,height=4,codec="rle4",palette={"FF0000","00FF00"},data="0404404004044040"})
s.create("parent",{position=M.vec(100,0,0),rotation=M.vec(.2,.3,.1),scale=M.vec(2,1,3)})
local n=s.create("moving",{parent="parent",mesh=E.boxMesh(),collider=true,velocity=M.vec(1,0,0)})
assert(s.setPixelMaterials("moving",{default="grid"}))
assert(#s.renderList()==0 and s.stats().scene3DCulledNodes==1)
assert(s.stats().scene3DPaintedVertices==0 and n.paintVertices==nil)
s.step(.1);s.renderList();assert(n.position.x==.1 and n.paintVertices==nil)
assert(s.queryAABB({min=M.vec(90,-10,-10),max=M.vec(110,10,10)})[1]=="moving")
s.setTransform("parent",{position=M.vec()})
assert(#s.renderList()>0 and s.stats().scene3DPaintedVertices>0)
assert(s.pick(200,150).id=="moving")
local world=n.paintWorld
s.setTransform("parent",{position=M.vec(100,0,0)});s.step(.1);s.renderList()
assert(n.paintWorld==world and s.stats().scene3DPaintedVertices==0)
s.setPixelMaterials("moving",nil);s.setTransform("parent",{position=M.vec()})
assert(#s.renderList()>0 and n.paintVertices==nil)
''')

    def test_noop_transforms_camera_and_zero_velocity_reuse_projection(self):
        self.lua.execute('''
local M=E.math3d;local s=E.newScene3D({width=400,height=300})
s.create("still",{mesh=E.boxMesh(),velocity=M.vec()})
local list=s.renderList();local project=s.projector();local revision=s.revision
s.setTransform("still",{position=M.vec(),scale=M.vec(1,1,1),rotation=M.vec()})
s.setCamera(s.getCamera());s.setViewport(s.getViewport());s.step(.1)
assert(s.revision==revision and s.renderList()==list and s.projector()==project)
s.setVelocity("still",M.vec(1,0,0));s.step(.1)
assert(s.get("still").position.x==.1 and s.renderList()~=list)
''')

if __name__=='__main__':unittest.main(verbosity=2)
