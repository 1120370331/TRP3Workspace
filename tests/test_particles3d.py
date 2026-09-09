"""3D particle invariants: bounded work, exact ownership, projection and reuse."""
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.local-tools/python'))
from lupa.lua51 import LuaRuntime

class Particles3DTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute('E={}')
        for name in ['core','math3d','particles3d','scene3d']:
            self.lua.execute((ROOT/f'framework/item-game/{name}.lua').read_text('utf-8'))(self.lua.globals().E,self.lua.globals())
        self.lua.execute('''
M=E.math3d;scene=E.newScene3D({width=400,height=300})
scene.setCamera({position=M.vec(0,0,8),target=M.vec()})
defs={ball={count=6,shape="sphere",speed=2,lifetime=1,size=.1,gravity=M.vec(0,-1,0)},
 ring={count=8,shape="ring",direction=M.vec(0,1,0),speed=2,lifetime=1},
 high={count=2,priority=2,speed=0,lifetime=1},
 trail={mode="continuous",shape="cone",spread=0,speed=0,rate=60,duration=1,lifetime=.1}}
fx=E.newParticles3D(scene,defs,{maxParticles3D=8,maxEmitters3D=2,maxParticleSpawns3DPerStep=8})
''')

    def test_shared_step_budget_eviction_and_pool_reuse(self):
        self.lua.execute('''
assert(fx.burst("ball",{seed=1})==6)
assert(fx.burst("ball",{seed=2})==2)
assert(fx.stats().particles3D==8 and fx.stats().particles3DDropped==4)
fx.update(.01);assert(fx.burst("high",{})==2);assert(fx.stats().particles3DEvicted==2)
assert(fx.stats().particles3DPooled==8)
fx.clear();assert(fx.burst("ball",{})==6)
fx.clear();assert(fx.burst("ball",{})==0,"clear must not bypass shared step budget")
fx.update(.01);assert(fx.burst("ball",{})==6);assert(fx.stats().particles3DPooled==8)
''')

    def test_seeded_world_motion_and_ring_plane(self):
        self.lua.execute('''
local other=E.newParticles3D(scene,defs,{maxParticles3D=8,maxParticleSpawns3DPerStep=8})
fx.burst("ball",{seed=42});other.burst("ball",{seed=42})
local z=false
for i,p in ipairs(fx.particles)do assert(p.vz==other.particles[i].vz);if math.abs(p.vz)>.2 then z=true end end
assert(z,"sphere must expand in the third dimension")
local p=fx.particles[1];local y=p.vy;fx.update(.1)
assert(math.abs(p.vy-(y-.1))<1e-8 and math.abs(p.y-p.vy*.1)<1e-8)
fx.clear();fx.update(.01);fx.burst("ring",{})
for _,p in ipairs(fx.particles)do assert(math.abs(p.vy)<1e-8 and math.abs(math.sqrt(p.vx*p.vx+p.vz*p.vz)-2)<1e-8)end
''')

    def test_emitter_ownership_lifetime_and_orphan_cleanup(self):
        self.lua.execute('''
scene.create("owner",{position=M.vec(2,0,0)})
local id=fx.start("trail",{nodeId="owner"});assert(id)
fx.update(1/60);assert(fx.particles[1].x==2)
scene.setTransform("owner",{position=M.vec(3,0,0)})
fx.update(1/60);assert(fx.particles[#fx.particles].x==3)
scene.remove("owner");fx.update(.02);assert(fx.stats().emitters3D==0)
for i=1,10 do fx.update(.02)end;assert(fx.stats().particles3D==0)
local a=assert(fx.start("trail",{}));assert(fx.start("trail",{}));assert(fx.start("trail",{})==nil)
fx.update(.02);fx.stop(a,true)
for _,p in ipairs(fx.particles)do assert(p.owner~=a)end
''')

    def test_perspective_depth_clipping_and_render_budget(self):
        self.lua.execute('''
fx.burst("high",{position=M.vec(0,0,2),seed=1});fx.update(.01)
fx.burst("high",{position=M.vec(0,0,-2),seed=1})
local list=fx.renderList(1,8);assert(#list==4 and list[1].depth>list[4].depth)
assert(list[4].points[2].x-list[4].points[1].x>list[1].points[2].x-list[1].points[1].x)
assert(#fx.renderList(1,1)==1 and fx.stats().particles3DRenderDropped==3)
scene.setCamera({position=M.vec(0,0,20),target=M.vec(0,0,30)})
assert(#fx.renderList(1,8)==0)
''')

    def test_particles_do_not_dirty_mesh_cache_or_participate_in_picking(self):
        self.lua.execute('''
scene.create("box",{mesh=E.boxMesh()});local mesh=scene.renderList()
fx.burst("ball",{position=M.vec(0,0,2)});fx.update(.1);fx.renderList(1,8)
assert(scene.renderList()==mesh and scene.pick(200,150).id=="box")
fx.dispose();assert(fx.stats().particles3D==0 and fx.start("trail",{})==nil and fx.burst("ball",{})==nil)
''')

    def test_saturated_equal_priority_rejection_does_not_scan_live_pool(self):
        self.lua.execute('''
fx.burst("ball",{count=8});fx.update(.01)
assert(fx.burst("ball",{count=8})==0)
assert(fx.stats().particles3DEvictionScans==0)
fx.update(.01);assert(fx.burst("high",{count=2})==2)
assert(fx.stats().particles3DEvictionScans==2 and fx.stats().particles3DEvicted==2)
fx.clear();fx.update(.01);assert(fx.burst("ball",{count=8})==8)
''')

    def test_render_quality_preserves_simulation_and_prioritizes_important_particles(self):
        self.lua.execute('''
fx.burst("ball",{count=6,seed=42});fx.update(.01);fx.burst("high",{count=2,seed=1})
local before={};for i,p in ipairs(fx.particles)do before[i]={p.x,p.y,p.z,p.age,p.serial}end
fx.setRenderPolicy({maxVisible=1})
local list=fx.renderList(1,8);assert(#list==1 and list[1].order==7)
assert(fx.stats().particles3D==8 and fx.stats().particles3DRenderDropped==7)
for i,p in ipairs(fx.particles)do assert(p.x==before[i][1] and p.y==before[i][2] and p.z==before[i][3] and p.age==before[i][4] and p.serial==before[i][5])end
fx.setRenderPolicy({maxScreenArea=.00001});assert(#fx.renderList(1,8)==0)
assert(fx.stats().particles3DScreenArea<=.00001)
fx.setRenderPolicy({maxDistance=1});assert(#fx.renderList(1,8)==0)
fx.setRenderPolicy();assert(#fx.renderList(1,8)==8)
assert(not pcall(fx.setRenderPolicy,{maxVisible=0}))
assert(#fx.renderList(1,8)==8,"invalid policy must not replace current policy")
''')

    def test_adaptive_budget_has_hysteresis_and_does_not_change_spawns(self):
        self.lua.execute('''
fx.burst("ball",{count=8});fx.setRenderPolicy({adaptive=true,targetMs=1000/60})
for i=1,80 do fx.observeFrame(50)end
assert(fx.stats().particles3DQualityScale==.25 and #fx.renderList(1,8)==2)
assert(fx.stats().particles3D==8 and fx.stats().particles3DSpawned==8)
for i=1,120 do fx.observeFrame(1000/60)end
assert(fx.stats().particles3DQualityScale==.25,"recovery must wait for sustained headroom")
for i=1,125 do fx.observeFrame(1000/60)end
assert(fx.stats().particles3DQualityScale==.5)
fx.setRenderPolicy();assert(#fx.renderList(1,8)==8)
''')

    def test_cached_projection_matches_fresh_scene_after_parent_and_camera_changes(self):
        self.lua.execute('''
scene.create("group",{});scene.create("moving",{parent="group",mesh=E.boxMesh()})
scene.create("still",{position=M.vec(2,0,0),mesh=E.boxMesh()});scene.renderList()
local stillVertices=scene.get("still").vertices
for i=1,8 do
 scene.setTransform("group",{rotation=M.vec(.1*i,.2*i,0)})
 if i%2==0 then scene.orbit(.3*i,.2,8,M.vec())end
 local cached=scene.renderList()
 local fresh=E.newScene3D({width=400,height=300});fresh.setCamera(scene.getCamera())
 fresh.create("group",{rotation=M.vec(.1*i,.2*i,0)})
 fresh.create("moving",{parent="group",mesh=E.boxMesh()})
 fresh.create("still",{position=M.vec(2,0,0),mesh=E.boxMesh()})
 local expected=fresh.renderList();assert(#cached==#expected)
 for j,f in ipairs(cached)do
  assert(f.id==expected[j].id and math.abs(f.depth-expected[j].depth)<1e-8)
  for k,p in ipairs(f.points)do assert(math.abs(p.x-expected[j].points[k].x)<1e-8 and math.abs(p.y-expected[j].points[k].y)<1e-8)end
 end
 assert(scene.get("still").vertices==stillVertices,"unchanged world vertices must be reused")
end
scene.setVisible("group",false);assert(#scene.renderList()==3)
''')

if __name__=='__main__':unittest.main(verbosity=2)
