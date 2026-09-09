"""Native assets API contracts under the existing Lua host double; no WoW automation."""
from pathlib import Path
import importlib.util
import unittest

ROOT=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('garden_cases',ROOT/'items/garden-defense/tests/test_game.py')
garden=importlib.util.module_from_spec(spec);spec.loader.exec_module(garden)


class NativeTests(garden.GardenTests):
    item_dir='garden-defense-wow'

    def click_surface_at(self,x,y):
        # Route through mouse-enabled rectangles and effective native levels,
        # instead of invoking a named callback regardless of which frame covers it.
        self.lua.execute('''
function clickSurfaceAt(x,y)
 local target,highest,tied=nil,-1,false
 for _,f in pairs(session.view.gameSurface.cache.layers)do
  assert(not f:IsMouseEnabled(),"decorative full-window layer intercepted clicks")
 end
 for id,n in pairs(Mock.nodes)do
  if n.object:IsShown() and n.object:IsMouseEnabled() and n.x and x>=n.x and x<=n.x+n.w and y>=n.y and y<=n.y+n.h then
   local level=n.object:GetFrameLevel()
   if level>highest then highest=level;target=n;tied=false
   elseif level==highest then tied=true end
  end
 end
 assert(not tied,"ambiguous topmost interactive layers")
 assert(target and target.object:GetScript("OnClick"),"no clickable frame at point")
 target.object:GetScript("OnClick")(target.object,"LeftButton")
end
''')
        self.lua.globals().clickSurfaceAt(x,y)

    def test_native_import_and_real_node_types(self):
        self.native_startup()
        self.lua.execute('Mock.scalarModelBounds=true')
        self.lua.globals().Mock.executeMacro(self.lua.globals().Mock.prepareUse())
        self.advance(.2)
        self.lua.execute('assert(TRP3_ItemGame and TRP3_ItemGame.current and not TRP3_ItemGame.current.stopping)')
        self.E=self.lua.globals().TRP3_ItemGame;self.boot()
        self.click('create1');self.click('level1');self.click('cell19')
        nodes=self.lua.globals().Mock.nodes
        self.assertEqual(nodes['lawn3_1'].kind,'texture')
        self.assertEqual(nodes['lawn3_1'].object.texture,187126)
        self.assertEqual(nodes['lawn3_1'].object.wrapX,'REPEAT')
        self.assertEqual(nodes['plant19'].kind,'model')
        self.assertTrue(nodes['plant19'].loaded)
        self.assertEqual(nodes['plant19'].scene.kind,'ModelScene')
        self.assertEqual(nodes['plant19'].model.kind,'Actor')
        self.assertEqual(nodes['mower3'].model.displayID,100000+338*10+1)
        self.assertEqual(nodes['plant19'].model.displayID,100000+1932*10+1)
        self.assertTrue(nodes['plant19'].fitReady)
        self.assertLessEqual(nodes['plant19'].object.height,68*1.3)
        self.assertFalse(nodes['plant19'].object.clipsChildren)
        self.assertAlmostEqual(-nodes['plant19'].object.point[5]+nodes['plant19'].object.height*.9,357)

    def test_native_map_omits_retired_slogan(self):
        self.boot();self.click('create1')
        self.assertIsNone(self.lua.globals().Mock.nodes['mapTitle'])

    def test_native_warcraft_names_and_distinct_elite_models(self):
        expected=['翡翠鞭笞者','向日葵','机械炸弹宝宝','红玉树苗','黑索微型地雷',
                  '寒霜精灵','邪恶南瓜娃娃','双生鞭笞者','赞加喷射孢子','辉光孢子']
        self.assertEqual([self.content.plants[i].name for i in range(1,11)],expected)
        self.assertTrue(all(len(name)<=6 for name in expected),'card labels must fit the 88 px name row')
        self.fresh(6)
        self.inject('''r.nextWave=10000;r.plants={};r.zombies={};r.enemyBolts={}
r.zombies[1]={kind="abomination",row=2,x=700,hp=2200,slow=0,jumped=false,viewSlot=1,abilityCooldown=120}
r.zombies[2]={kind="necromancer",row=4,x=700,hp=520,slow=0,jumped=false,viewSlot=2,shotCooldown=120}''')
        self.advance(.2)
        nodes=self.lua.globals().Mock.nodes
        self.assertEqual(nodes['enemy1'].model.displayID,28449)
        self.assertEqual(nodes['enemy1'].model.modelSourceKind,'creatureDisplayID')  # abomination skin requires the display, not its bare M2
        self.assertEqual(nodes['enemy2'].model.displayID,96088)
        self.assertEqual(nodes['enemy2'].model.modelSourceKind,'creatureDisplayID')  # lich skin requires the display, not its bare M2

    def test_native_day_bgm_and_independent_music_setting(self):
        self.fresh(1)
        self.lua.execute('''
assert(session.music.trackId=="battle_day" and session.music.state=="playing")
local found=false
for _,c in ipairs(Mock.soundCalls)do if c.id==1781897 and c.channel=="SFX"then found=true end end
assert(found)
''')
        self.click('pause');self.click('settings');self.click('settingMusic')
        self.lua.execute('assert(not snapshot().music and session.music.state=="stopped")')
        self.click('settingMusic')
        self.lua.execute('assert(snapshot().music and session.music.state=="paused")')
        self.click('settingsBack');self.click('resume')
        self.lua.execute('assert(session.music.trackId=="battle_day" and session.music.state=="playing")')

    def test_native_night_bgm_selection(self):
        self.fresh(9)
        self.lua.execute('''
assert(session.music.trackId=="battle_night" and session.music.state=="playing")
local found=false
for _,c in ipairs(Mock.soundCalls)do if c.id==2146621 and c.channel=="SFX"then found=true end end
assert(found)
''')

    def test_native_model_failures_do_not_pause_or_substitute_icons(self):
        self.lua.execute('Mock.noModels=true')
        self.fresh();self.click('cell19')
        node=self.lua.globals().Mock.nodes['plant19']
        self.assertIsNone(node.model)
        self.assertFalse(node.fallback.IsShown(node.fallback))
        self.advance(4)
        self.lua.execute('assert(not session.stopping and not session.paused);assert(snapshot().slots["1"].run.time>3)')
        self.lua.execute('Mock.noModels=false');self.advance(1.2)
        self.assertTrue(self.lua.globals().Mock.nodes['plant19'].loaded)

    def test_native_sun_collection_uses_bounded_engine_particles(self):
        self.fresh()
        self.inject('r.suns={{x=420,y=260,value=25,ttl=10}}')
        self.click('sun1')
        self.lua.execute('''
local stats=session.ctx.fx.stats()
assert(stats.activeParticles==18 and stats.droppedParticles==0)
local p=session.effects.particles[1]
assert(p.effectId=="sun_collect" and p.handle.texture.blend=="ADD")
''')
        self.advance(.7)
        self.lua.execute('assert(session.ctx.fx.stats().activeParticles==0)')

    def test_native_projectile_impacts_use_real_hit_coordinates_once(self):
        self.fresh(6)
        for ice,spore,effect,total,sound_id in [(False,False,'pea_splash',8,22889),(True,False,'ice_shards',16,7),(False,True,'spore_dust',10,41206)]:
            self.inject('''r.nextWave=10000;r.plants={};r.zombies={{kind="basic",row=3,x=500,hp=200,slow=0,jumped=false}}
r.bullets={{row=3,x=479,remaining=300,damage=20,ice=%s,spore=%s}}''' % ('true' if ice else 'false','true' if spore else 'false'))
            self.advance(.034)
            self.lua.execute('''
local r=snapshot().slots["1"].run
assert(r.zombies[1].hp==180 and #r.bullets==0)
assert(session.ctx.fx.stats().spawnedParticles==%d)
local seen=false
for _,p in ipairs(session.effects.particles)do if p.effectId=="%s"then seen=true;assert(p.previousX==482 and p.previousY==331)end end
assert(seen)
''' % (total,effect))
            if ice:self.assertGreater(self.state().slots['1'].run.zombies[1].slow,4.8)
            else:self.assertEqual(self.state().slots['1'].run.zombies[1].slow,0)
            self.assertTrue(any(c.id==sound_id and c.channel=='SFX' and c.volumeOverride==.5 for c in self.lua.globals().Mock.soundCalls.values()))
            self.advance(.08)
            self.assertEqual(self.lua.eval('session.ctx.fx.stats().spawnedParticles'),total)

    def test_native_spore_range_expiry_does_not_emit_hit_or_damage(self):
        self.fresh(9)
        self.inject('''r.nextWave=10000;r.plants={};r.zombies={{kind="basic",row=3,x=600,hp=200,slow=0,jumped=false}}
r.bullets={{row=3,x=400,remaining=1,damage=20,ice=false,spore=true}}''')
        self.advance(.034)
        self.lua.execute('''
local r=snapshot().slots["1"].run
assert(#r.bullets==0 and r.zombies[1].hp==200 and r.zombies[1].slow==0)
assert(session.ctx.fx.stats().spawnedParticles==0)
''')

    def test_native_cherry_explosion_composes_once_and_preserves_damage(self):
        self.fresh(3)
        self.inject('''r.nextWave=10000;r.plants={["19"]={kind="cherry",row=3,col=1,hp=300,age=1.19,timer=0}}
r.zombies={{kind="basic",row=3,x=220,hp=200,slow=0,jumped=false}}''')
        self.advance(.034)
        self.lua.execute('''
local r=snapshot().slots["1"].run;assert(not r.plants["19"] and #r.zombies==0 and r.kills==1)
assert(session.ctx.fx.stats().spawnedParticles==37)
local smoke=false;for _,p in ipairs(session.effects.particles)do if p.effectId=="explosion_smoke"then smoke=true;assert(p.age<0)end end
assert(smoke);assert(not Mock.nodes.explosion1)
session.pause("test");Mock.fxAge=session.effects.particles[1].age;Mock.advance(.3)
assert(session.effects.particles[1].age==Mock.fxAge)
session.resume();Mock.advance(1.5);assert(session.ctx.fx.stats().activeParticles==0)
''')
        self.assertTrue(any(c.id==16418 and c.channel=='SFX' for c in self.lua.globals().Mock.soundCalls.values()))

    def test_native_mower_crush_has_its_own_impact(self):
        self.fresh()
        self.inject('''r.nextWave=10000;r.plants={};r.zombies={};r.bullets={}
r.zombies[1]={kind="basic",row=3,x=160,hp=200,slow=0,jumped=false}
r.mowers={0,0,108,0,0}''')
        self.advance(.2)
        self.assertEqual(len(list(self.state().slots['1'].run.zombies.values())),0)
        self.assertTrue(any(c.id==18085 and c.channel=='SFX' for c in self.lua.globals().Mock.soundCalls.values()))

    def test_native_full_lawn_is_bounded_and_reopen_reuses_models(self):
        self.lua.execute('Mock.scalarModelBounds=true')
        self.fresh(10)
        self.inject('''r.nextWave=10000;r.plants={};r.zombies={}
for row=1,5 do for col=1,9 do
 local id=tostring((row-1)*9+col)
 r.plants[id]={kind="pea",row=row,col=col,hp=300,age=0,timer=1}
end end
for i=1,48 do r.zombies[i]={kind="basic",row=(i%5)+1,x=900,hp=200,slow=0,jumped=false}end''')
        self.advance(.2)
        stats=self.lua.globals().session.view.gameSurface.stats()
        self.assertEqual(stats.surfaceModels,98)
        self.assertEqual(stats.surfaceModelsLoaded,98)
        self.assertLessEqual(stats.pooledSurfaceModels,104)
        self.lua.execute('''
local scene=Mock.nodes.plant1.scene
assert(scene.fov>=.4 and scene.fov<=1)
assert(math.abs(scene.cameraPosition.x)<100 and scene.farClip<100)
assert(scene.allowOverlappedModels and scene.fogCleared)
for _,n in pairs(Mock.nodes)do
 if n.sharedScene and n.loaded and n.model then
  assert(n.model.scale>0 and n.model.scale<10)
  local b,t=n.bounds[1],n.bounds[2]
  local foot=Mock.actorWorldPoint(n.model,(b.x+t.x)/2,(b.y+t.y)/2,b.z)
  local px,py=scene:Project3DPointTo2D(foot.x,foot.y,foot.z)
  px=px/scene:GetEffectiveScale();py=600-py/scene:GetEffectiveScale()
  assert(math.abs(px-(n.x+n.w/2))<.01 and math.abs(py-(n.y+n.h*.9))<.01)
 end
end
''')
        before=stats.pooledSurfaceModels
        self.restart();self.click('load1');self.click('resume')
        self.assertLessEqual(self.lua.globals().session.view.gameSurface.stats().pooledSurfaceModels,before)
        self.lua.execute('session.stop("close");for _,pool in pairs(E.viewCache.surface.pools)do for _,node in ipairs(pool)do if node.model then assert(node.model:GetScript("OnModelLoaded")==nil);assert(node.model.modelID==0)end end end')

    def test_native_cached_texture_updates_and_load_timeout(self):
        self.content.surfaceModelScene=False  # retain the optional legacy renderer contract
        self.lua.execute('Mock.modelsNeverLoad=true')
        self.fresh();self.click('cell19')
        node=self.lua.globals().Mock.nodes['lawn3_1'];calls=node.object.textureCalls
        self.advance(4)
        self.assertEqual(node.object.textureCalls,calls)
        plant=self.lua.globals().Mock.nodes['plant19']
        self.assertFalse(plant.loaded)
        self.assertFalse(plant.model.IsShown(plant.model))
        self.assertFalse(plant.fallback.IsShown(plant.fallback))
        self.assertFalse(self.lua.globals().session.paused)

    def test_native_skin_resolver_never_uses_npc_or_raw_file_id(self):
        self.lua.execute('Mock.petTableOnly=true')
        self.fresh();self.click('cell19')
        node=self.lua.globals().Mock.nodes['plant19']
        self.assertEqual(node.model.displayID,119321)
        self.assertNotEqual(node.model.displayID,501932)
        self.assertTrue(node.loaded)
        self.lua.execute('Mock.petJournalPending=true')
        self.restart();self.click('load1');self.click('resume')
        node=self.lua.globals().Mock.nodes['plant19']
        self.assertTrue(node.loaded)  # resolved skins survive journal unavailability on reopen
        self.assertFalse(node.fallback.IsShown(node.fallback))
        self.lua.execute('Mock.petJournalPending=false')
        self.advance(.6)
        self.assertTrue(node.loaded or node.compatLoaded)

    def test_native_scene_loading_unpauses_before_measuring(self):
        self.lua.execute('Mock.requireUnpausedScene=true')
        self.fresh();self.click('cell19')
        node=self.lua.globals().Mock.nodes['plant19']
        self.assertTrue(node.fitReady)
        self.assertFalse(node.compatActive)
        self.assertFalse(node.fallback.IsShown(node.fallback))
        self.assertIsNone(self.lua.globals().Mock.nodes['plantBadge19'])

    def test_native_loaded_actor_with_false_geo_ready_becomes_visible(self):
        # Reproduce the real client: display and M2 are loaded, usable bounds
        # exist, but IsGeoReady never turns true (previously hidden forever).
        self.lua.execute('Mock.modelLoadDelay=.12;Mock.scalarModelBounds=true')
        self.fresh();self.click('cell19');self.click('pause');self.advance(.6)
        self.lua.execute('''
for _,id in ipairs({"plant19","mower3"})do
 local n=Mock.nodes[id]
 assert(n.model:IsLoaded() and not n.model:IsGeoReady())
 assert(n.model:GetModelFileID()>0 and n.bounds)
 assert(n.fitReady and n.model:IsShown() and n.model.alpha==1,
  "loaded native actor stranded behind IsGeoReady")
end
assert(session.paused)
''')

    def test_native_missing_bounds_switches_to_a_skinned_model(self):
        self.content.surfaceModelScene=False
        self.lua.execute('Mock.noModelBounds=true')
        self.fresh();self.click('cell19');self.advance(3.4)
        node=self.lua.globals().Mock.nodes['plant19']
        self.assertTrue(node.compatActive and node.compatLoaded)
        self.assertEqual(node.compatModel.kind,'PlayerModel')
        self.assertEqual(node.compatModel.displayID,119321)
        self.assertTrue(node.compatModel.IsShown(node.compatModel))
        self.assertFalse(node.fallback.IsShown(node.fallback))
        self.assertFalse(self.lua.globals().session.paused)

    def test_native_scalar_and_vector_bounds_have_identical_fit(self):
        self.lua.execute('''
local scalar={GetActiveBoundingBox=function()return -2,-3,-1,4,5,7 end}
local vectors={GetActiveBoundingBox=function()
 return {GetXYZ=function()return -2,-3,-1 end},{GetXYZ=function()return 4,5,7 end}
end}
local a,b=E.readModelBounds(scalar,"GetActiveBoundingBox")
local c,d=E.readModelBounds(vectors,"GetActiveBoundingBox")
assert(E.JSON.encode({a,b})==E.JSON.encode({c,d}))
local bad={GetActiveBoundingBox=function()return 0,0,nil,1,1,1 end}
assert(E.readModelBounds(bad,"GetActiveBoundingBox")==nil)
''')
        self.content.surfaceModelScene=False
        self.lua.execute('Mock.scalarModelBounds=true')
        self.fresh();self.click('cell19')
        self.assertTrue(self.lua.globals().Mock.nodes['plant19'].fitReady)
        self.assertFalse(self.lua.globals().Mock.nodes['plant19'].compatActive)

    def test_native_model_scaling_does_not_move_foot_anchor(self):
        self.lua.execute('''
Mock.actorBounds={
 [119321]={{x=-.08,y=-.05,z=-.02},{x=.12,y=.10,z=.16}},
 [119671]={{x=2,y=-4,z=-1},{x=6,y=3,z=9}}
}
''')
        self.fresh(10)
        self.lua.execute('''
local surface=session.view.gameSurface
local function checkFoot(n)
 local b,t=n.bounds[1],n.bounds[2]
 local foot=Mock.actorWorldPoint(n.model,(b.x+t.x)/2,(b.y+t.y)/2,b.z)
 local scene=n.scene
 local x,y=scene:Project3DPointTo2D(foot.x,foot.y,foot.z)
 x=x/scene:GetEffectiveScale();y=600-y/scene:GetEffectiveScale()
 assert(math.abs(x-(n.x+n.w/2))<.01 and math.abs(y-(n.y+n.h*.9))<.01,
  "model scale changed the foot anchor")
end
local small,large
for _,size in ipairs({88,52,88})do
 surface.begin()
 small=surface.draw("scaleSmall",{kind="model",asset="pea",x=110,y=210-size*.9,w=size,h=size,layer=4,depth=210})
 large=surface.draw("scaleLarge",{kind="model",asset="zombie",x=810,y=490-size*.9,w=size,h=size,layer=4,depth=490})
 surface.finish()
 assert(small.model.scale>1 and large.model.scale<1)
 checkFoot(small);checkFoot(large)
 assert(small.sceneDepth.near>large.sceneDepth.far)
end
-- Removing the front row changes the back row's perspective scale, not its cell.
surface.begin()
surface.draw("scaleSmall",{kind="model",asset="pea",x=110,y=210-88*.9,w=88,h=88,layer=4,depth=210})
surface.finish();checkFoot(small)
''')

    def test_native_idle_body_ignores_animation_envelope(self):
        self.lua.execute('''
Mock.actorMaxBounds={
 [119321]={{x=-15,y=-10,z=-8},{x=20,y=10,z=25}},
 [103381]={{x=-8,y=-6,z=-4},{x=12,y=6,z=10}}
}
''')
        self.fresh();self.click('cell19');self.advance(.2)
        self.lua.execute('''
for _,id in ipairs({"plant19","mower3"})do
 local n=Mock.nodes[id]
 assert(n.fitReady and n.model:IsShown())
 -- The host's actual idle mesh is (-1,-1,0)..(1,1,2). Its ground
 -- point must stay on the cell even when the all-animation box is huge.
 local foot=Mock.actorWorldPoint(n.model,0,0,0)
 local x,y=n.scene:Project3DPointTo2D(foot.x,foot.y,foot.z)
 local scale=n.scene:GetEffectiveScale()
 assert(math.abs(x/scale-(n.x+n.w/2))<.01 and math.abs(600-y/scale-(n.y+n.h*.9))<.01,
  "animation envelope moved the standing body off the ground")
 local tip=Mock.actorWorldPoint(n.model,0,0,2)
 local _,top=n.scene:Project3DPointTo2D(tip.x,tip.y,tip.z)
 assert((top-y)/scale>n.h*.75,"standing body shrank to fit unrelated animation extents")
end
''')

    def test_native_explicit_anchor_and_pixel_size_controls(self):
        self.fresh();self.click('pause')
        self.lua.execute('''
local surface=session.view.gameSurface
local function draw(scale,assetScale)
 content.assets.models.pea.scale=assetScale or 1
 surface.begin()
 local n=surface.draw("controlled",{kind="model",asset="pea",x=0,y=0,w=74,h=66,
  anchorX=200,anchorY=357,scale=scale,fitFill=1,modelAnchor={x=.2,y=-.15,z=.1},layer=4})
 surface.finish()
 assert(n.fitReady)
 local foot=Mock.actorWorldPoint(n.model,.2,-.15,.1)
 local x,y=n.scene:Project3DPointTo2D(foot.x,foot.y,foot.z)
 local uiScale=n.scene:GetEffectiveScale()
 assert(math.abs(x/uiScale-200)<.01 and math.abs(600-y/uiScale-357)<.01,"explicit anchor was ignored")
 local left,right,bottom,top
 for _,bx in ipairs({-1,1})do for _,by in ipairs({-1,1})do for _,bz in ipairs({0,2})do
  local p=Mock.actorWorldPoint(n.model,bx,by,bz)
  local sx,sy=n.scene:Project3DPointTo2D(p.x,p.y,p.z)
  left=left and math.min(left,sx)or sx;right=right and math.max(right,sx)or sx
  bottom=bottom and math.min(bottom,sy)or sy;top=top and math.max(top,sy)or sy
 end end end
 local fill=math.max((right-left)/(74*uiScale),(top-bottom)/(66*uiScale))
 assert(math.abs(fill-(scale or assetScale or 1))<.006,"scale does not control the projected body size")
 return n
end
draw(1);draw(.5);draw(nil,.75)
Mock.uiScale=.65;draw(1.25)
assert(session.paused)
''')

    def test_native_game_size_and_offsets_preserve_cell(self):
        self.content.assets.models.pea.scale=.6
        self.content.assets.models.pea.render.offsetX=7
        self.content.assets.models.pea.render.offsetY=-4
        self.fresh();self.click('cell19');self.advance(.2)
        node=self.lua.globals().Mock.nodes['plant19']
        self.assertAlmostEqual(node.w,106*.6)
        self.assertAlmostEqual(node.h,88*.6)
        self.assertEqual((node.projectedAnchor.x,node.projectedAnchor.y),(179,353))
        self.assertEqual(node.depth,357)
        self.lua.execute('content.assets.models.pea.scale=3')
        self.advance(.2)
        node=self.lua.globals().Mock.nodes['plant19']
        self.assertAlmostEqual(node.w,84*1.3)
        self.assertAlmostEqual(node.h,68*1.3)
        self.assertEqual((node.projectedAnchor.x,node.projectedAnchor.y),(179,353))
        self.assertEqual(self.state().slots['1'].run.plants['19'].col,1)

    def test_native_corner_projection_failure_is_isolated_and_retries(self):
        self.fresh();self.click('cell19');self.click('pause')
        self.lua.execute('''
local n=Mock.nodes.plant19
local project=n.scene.Project3DPointTo2D
n.scene.Project3DPointTo2D=function(self,x,y,z)
 local u,v,d=project(self,x,y,z)
 if u and u>115 and u<235 and y~=0 and z~=0 then return nil end
 return u,v,d
end
-- Force a fresh projection without changing gameplay or unpausing.
session.view.gameSurface.update()
Mock.uiScale=.9
session.view.gameSurface.update()
assert(not n.fitReady and not n.model:IsShown(),"unverified geometry was shown")
assert(Mock.nodes.mower3.fitReady and Mock.nodes.mower3.model:IsShown(),"one actor hid the entire scene")
n.scene.Project3DPointTo2D=project
session.view.gameSurface.update()
assert(n.fitReady and n.model:IsShown() and session.paused)
''')

    def test_native_projection_keeps_first_column_and_mowers_on_left(self):
        self.fresh(4)
        self.inject('''r.nextWave=10000;r.plants={};r.zombies={}
r.plants["10"]={kind="pea",row=2,col=1,hp=300,age=0,timer=0}
r.plants["19"]={kind="sunflower",row=3,col=1,hp=300,age=0,timer=0}
r.plants["28"]={kind="wall",row=4,col=1,hp=4000,age=0,timer=0}''')
        self.lua.execute('''
function checkVisibleAnchor(id,expectedX,expectedY)
 local n=Mock.nodes[id];assert(n and n.model:IsShown() and n.fitReady)
 local b,t=n.bounds[1],n.bounds[2]
 local foot=Mock.actorWorldPoint(n.model,(b.x+t.x)/2,(b.y+t.y)/2,b.z)
 local x,y=n.scene:Project3DPointTo2D(foot.x,foot.y,foot.z)
 local scale=n.scene:GetEffectiveScale()
 assert(math.abs(x/scale-expectedX)<.01 and math.abs(600-y/scale-expectedY)<.01,id.." moved away from its cell")
 local definition=content.assets.models[n.asset]
 if definition.screenFacing then
  local forward=definition.forwardYaw or 0
  local probe=Mock.actorWorldPoint(n.model,(b.x+t.x)/2+math.cos(forward)*.1,(b.y+t.y)/2+math.sin(forward)*.1,b.z)
  local ahead=n.scene:Project3DPointTo2D(probe.x,probe.y,probe.z)
  assert((ahead-x)*(definition.screenFacing=="right" and 1 or -1)>0,id.." faces backwards")
 end
 local left,right,bottom,top
 for _,bx in ipairs({b.x,t.x})do for _,by in ipairs({b.y,t.y})do for _,bz in ipairs({b.z,t.z})do
  local point=Mock.actorWorldPoint(n.model,bx,by,bz)
  local sx,sy=n.scene:Project3DPointTo2D(point.x,point.y,point.z)
  left=left and math.min(left,sx)or sx;right=right and math.max(right,sx)or sx
  bottom=bottom and math.min(bottom,sy)or sy;top=top and math.max(top,sy)or sy
 end end end
 assert((right-left)/scale<=n.w+.01 and (top-bottom)/scale<=n.h+.01,id.." exceeds its screen footprint")
end
''')
        for right,horizontal,ui_scale in [(1,False,1),(-1,False,.65),(1,True,1.8),(-1,True,1.2)]:
            self.lua.globals().Mock.modelProjectionRight=right
            self.lua.globals().Mock.horizontalModelFov=horizontal
            self.lua.globals().Mock.uiScale=ui_scale
            self.advance(.12)
            self.lua.execute('''
for row=2,4 do
 checkVisibleAnchor("plant"..tostring((row-1)*9+1),172,164+(row-1)*68+57)
 checkVisibleAnchor("mower"..row,99,164+(row-1)*68+57)
end
''')

    def test_native_delayed_bounds_recover_without_opening_pause_menu(self):
        self.lua.execute('Mock.noModelBounds=true;Mock.scalarModelBounds=true')
        self.fresh();self.click('cell19');self.advance(10)
        self.assertFalse(self.lua.globals().session.paused)
        self.assertFalse(self.lua.globals().Mock.nodes['plant19'].loaded)
        self.assertGreater(self.state().slots['1'].run.time,9)
        self.lua.execute('Mock.noModelBounds=false');self.advance(.1)
        self.assertTrue(self.lua.globals().Mock.nodes['plant19'].fitReady)
        self.assertFalse(self.lua.globals().session.paused)
        self.lua.globals().Mock.pressEscape()
        self.assertTrue(self.lua.globals().session.paused)

    def test_native_projection_readiness_recovers_during_user_pause(self):
        self.lua.execute('Mock.projectionUnavailable=true')
        self.fresh();self.click('cell19');self.click('pause');self.advance(.2)
        self.assertFalse(self.lua.globals().Mock.nodes['plant19'].fitReady)
        self.lua.execute('Mock.projectionUnavailable=false');self.advance(.05)
        self.assertTrue(self.lua.globals().Mock.nodes['plant19'].fitReady)
        self.assertTrue(self.lua.globals().session.paused)

    def test_native_chomper_reaches_enemy_biting_next_cell(self):
        self.fresh(7)
        self.inject('''r.nextWave=10000;r.plants={};r.zombies={}
r.plants["19"]={kind="chomper",row=3,col=1,hp=300,age=0,timer=0}
r.plants["20"]={kind="wall",row=3,col=2,hp=4000,age=0,timer=0}
r.zombies[1]={kind="bucket",row=3,x=293.9,hp=1100,slow=0,jumped=false}''')
        self.advance(.1)
        r=self.state().slots['1'].run
        self.assertEqual(len(list(r.zombies.values())),0)
        self.assertEqual(r.kills,1)
        self.assertEqual(r.plants['20'].hp,4000)
        self.assertGreater(r.plants['19'].timer,19)
        self.assertTrue(any(c.id==103506 and c.channel=='SFX' for c in self.lua.globals().Mock.soundCalls.values()))

    def test_native_armed_mine_uses_same_contact_as_enemy_bite(self):
        self.fresh(5)
        self.inject('''r.nextWave=10000;r.plants={};r.zombies={}
r.plants["19"]={kind="mine",row=3,col=1,hp=300,age=11.95,timer=0}
r.zombies[1]={kind="bucket",row=3,x=209.9,hp=1100,slow=0,jumped=false}''')
        self.advance(.15)
        r=self.state().slots['1'].run
        self.assertEqual(len(list(r.zombies.values())),0)
        self.assertIsNone(r.plants['19'])
        self.assertEqual(r.kills,1)

    def test_native_sun_and_ui_have_master_feedback_including_pause(self):
        self.fresh()
        self.inject('r.nextWave=10000;r.suns={{x=300,y=200,value=25,ttl=10}}')
        self.lua.execute('Mock.cvars.Sound_EnableSFX="0";Mock.soundCalls={}')
        self.click('sun1')
        calls=list(self.lua.globals().Mock.soundCalls.values())
        self.assertTrue(any(c.id==120 and c.channel=='Master' for c in calls))
        self.advance(.1)
        self.click('pause')
        calls=list(self.lua.globals().Mock.soundCalls.values())
        self.assertTrue(any(c.id==852 and c.channel=='Master' for c in calls))
        self.assertGreater(self.lua.globals().session.sound.count,0)
        self.click('resume');self.click('sound')
        before=len(list(self.lua.globals().Mock.soundCalls.values()))
        self.click('map')
        self.assertEqual(len(list(self.lua.globals().Mock.soundCalls.values())),before)

    def test_native_unaffordable_cards_show_red_cross_but_free_card_does_not(self):
        self.fresh(9);self.inject('r.nextWave=10000;r.sun=0;r.cooldowns={}')
        nodes=self.lua.globals().Mock.nodes
        cross=nodes['cardNoSun1']
        self.assertTrue(cross.object.IsShown(cross.object))
        self.assertEqual(cross.object.text,'×')
        self.assertGreater(cross.object.textColor[1],.9)
        self.assertLess(cross.object.textColor[2],.2)
        self.assertIsNone(nodes['cardNoSun9'])

    def test_native_plant_health_fill_is_green_and_above_dark_track(self):
        self.fresh(4)
        self.inject('''r.nextWave=10000;r.plants={};r.zombies={}
r.plants["19"]={kind="wall",row=3,col=1,hp=2000,age=0,timer=0}''')
        nodes=self.lua.globals().Mock.nodes
        track,fill=nodes['plantHPBase19'],nodes['plantHP19']
        self.assertGreater(fill.object.GetFrameLevel(fill.object),track.object.GetFrameLevel(track.object))
        self.assertEqual([round(fill.object.color[i],2) for i in range(1,5)],[.56,.83,.28,1])
        self.assertAlmostEqual(fill.object.width,26)

    def test_native_sun_fade_and_collect_effect_do_not_duplicate_value(self):
        self.fresh()
        self.inject('r.nextWave=10000;r.suns={{x=300,y=200,value=25,ttl=1.5}}')
        node=self.lua.globals().Mock.nodes['sunIcon1']
        self.assertAlmostEqual(node.object.vertexColor[4],.5,delta=.05)
        self.advance(.4)
        self.assertLess(node.object.vertexColor[4],.4)
        before=self.state().slots['1'].run.sun
        self.click('sun1')
        self.assertEqual(self.state().slots['1'].run.sun,before+25)
        effect=self.lua.globals().Mock.nodes['sunCollectIcon1']
        self.assertTrue(effect.object.IsShown(effect.object))
        self.advance(.25);self.assertLess(effect.object.vertexColor[4],.7)
        self.advance(.4);self.assertFalse(effect.object.IsShown(effect.object))
        self.assertEqual(self.state().slots['1'].run.sun,before+25)

    def test_native_double_speed_and_radial_cooldown_pause_resume(self):
        self.fresh();self.click('cell19')
        swipe=self.lua.globals().Mock.nodes['cardSwipe1']
        self.assertEqual(swipe.kind,'cooldown')
        self.assertEqual(swipe.object.cooldownDuration,5)
        self.assertTrue(swipe.object.drawSwipe)
        self.click('speed')
        self.assertEqual(self.state().speed,2)
        self.assertEqual(swipe.object.cooldownDuration,2.5)
        before=self.state().slots['1'].run.time
        self.advance(1)
        r=self.state().slots['1'].run
        self.assertAlmostEqual(r.time-before,2,delta=.08)
        self.assertAlmostEqual(r.cooldowns.pea,3,delta=.08)
        self.click('pause');self.assertTrue(swipe.object.paused)
        remaining=self.state().slots['1'].run.cooldowns.pea
        self.advance(1);self.assertEqual(self.state().slots['1'].run.cooldowns.pea,remaining)
        self.click('resume');self.assertFalse(swipe.object.paused)
        self.advance(2);self.assertFalse(swipe.object.IsShown(swipe.object))
        self.restart();self.assertEqual(self.state().speed,2)
        self.assertEqual(self.lua.globals().session.ctx.session.getSpeed(),2)

    def test_native_escape_settings_suspend_reopen_and_explicit_exit(self):
        self.fresh();self.click('cell19');self.advance(.2)
        self.lua.globals().Mock.pressEscape()
        self.assertTrue(self.lua.globals().session.paused)
        self.assertTrue(self.lua.globals().session.view.frame.IsShown(self.lua.globals().session.view.frame))
        self.click('settings');self.click('settingSpeed')
        self.assertEqual(self.state().speed,2)
        self.lua.globals().Mock.pressEscape()
        self.assertFalse(self.lua.globals().session.stopping)
        self.click('pauseSave')
        before=self.state().slots['1'].run.time
        self.lua.execute('local b=session.view.cache.close;b:GetScript("OnClick")(b)')
        self.lua.execute('assert(E.current==session and session.paused and not session.view.frame:IsShown());assert(not TRP3_ItemGameWindow:IsShown())')
        self.advance(1);self.assertEqual(self.state().slots['1'].run.time,before)
        self.lua.execute('local same=E.start(E.newWoWHost(args,manifest),manifest,content);assert(same==session);assert(session.view.frame:IsShown() and session.paused)')
        self.lua.execute('local n=Mock.nodes.saveExit;n.object:GetScript("OnClick")(n.object,"LeftButton")')
        self.lua.execute('assert(E.current==nil and session.closed);assert(not session.view.frame:IsShown());assert(session.sound.count==0)')

    def test_native_failed_save_does_not_hide_or_exit(self):
        self.fresh();self.lua.execute('Mock.failWriteKey="IG_SAVE_V1"')
        self.lua.execute('local b=session.view.cache.close;b:GetScript("OnClick")(b)')
        self.lua.execute('assert(session.paused and not session.stopping and session.view.frame:IsShown())')
        self.click('saveExit')
        self.lua.execute('assert(not session.stopping and session.view.frame:IsShown())')
        self.lua.execute('Mock.failWriteKey=nil')
        self.lua.execute('local n=Mock.nodes.saveExit;n.object:GetScript("OnClick")(n.object,"LeftButton")')
        self.assertTrue(self.lua.globals().session.closed)

    def test_native_pause_menu_before_selecting_a_save(self):
        self.boot();self.lua.globals().Mock.pressEscape()
        self.click('settings');self.click('settingsBack');self.click('pauseMap')
        self.lua.execute('assert(not session.paused and not session.stopping);assert(Mock.nodes.create1.object:IsShown())')

    def test_native_restart_current_level_confirms_and_resets_only_the_run(self):
        self.fresh(3);self.click('cell19');self.advance(.5)
        self.click('pause');before=self.state().slots['1']
        self.click('pauseRestart')
        self.lua.execute('''
assert(session.paused and Mock.nodes.confirmYes.object:IsShown() and Mock.nodes.confirmNo.object:IsShown())
for _,id in ipairs({"pausedNote","resume","settings","pauseProgress","pauseRestart","pauseSave","saveExit","exitRun","pauseMap","buttonLabel/resume"})do
    assert(not Mock.nodes[id].object:IsShown(), "parent pause menu overlaps confirmation: "..id)
end
''')
        self.click('confirmNo')
        self.lua.execute('''
assert(Mock.nodes.pauseRestart.object:IsShown() and Mock.nodes.resume.object:IsShown())
assert(not Mock.nodes.confirmYes.object:IsShown() and not Mock.nodes.confirmNote.object:IsShown())
''')
        self.assertIsNotNone(self.state().slots['1'].run.plants['19'])
        self.assertTrue(self.lua.globals().session.paused)
        self.click('pauseRestart');self.click('confirmYes')
        after=self.state().slots['1']
        self.assertEqual(after.run.level,3)
        self.assertEqual(after.run.status,'playing')
        self.assertEqual(len(list(after.run.plants.values())),0)
        self.assertEqual(after.run.sun,self.content.campaign[3].sun)
        self.assertLess(after.run.time,.2)
        self.assertEqual(after.cleared,before.cleared)
        self.assertEqual(after.coins,before.coins)
        self.assertFalse(self.lua.globals().session.paused)

    def test_native_exit_run_abandons_campaign_without_recording_a_loss(self):
        self.fresh(3);self.click('cell19');self.advance(.4)
        before=self.state().slots['1'].progress.stats.losses
        self.click('pause');self.click('exitRun')
        state=self.state()
        self.assertIsNone(state.slots['1'].run)
        self.assertEqual(state.slots['1'].progress.stats.losses,before)
        self.assertFalse(self.lua.globals().session.paused)
        self.lua.execute('assert(Mock.nodes.level3.object:IsShown())')
        self.restart();self.click('load1')
        self.assertIsNone(self.state().slots['1'].run)

    def test_native_endless_unlock_scoring_round_growth_and_persistence(self):
        self.boot();self.click('create1')
        self.assertFalse(self.lua.globals().Mock.nodes['endless'].enabled)
        self.click('level1')
        state=self.state();state.slots['1'].cleared=9;state.slots['1'].run=None
        self.lua.globals().seeded=state
        self.lua.execute('session.stop("seed_endless");local save=E.JSON.decode(item.vars.IG_SAVE_V1);save.game=seeded;item.vars.IG_SAVE_V1=E.JSON.encode(save)')
        self.boot();self.click('load1');self.click('level10')
        self.inject('''r.zombies={};r.wave=#content.campaign[r.level].waves;r.spawnIndex=1
for _,group in ipairs(content.campaign[r.level].waves[r.wave].types)do r.spawnIndex=r.spawnIndex+group[2]end''')
        self.advance(.2)
        self.assertEqual(self.state().slots['1'].cleared,10)
        self.lua.execute('assert(Mock.nodes["buttonLabel/resultNext"].object.text=="进入无尽")')
        self.click('resultNext')
        r=self.state().slots['1'].run
        self.assertEqual((r.mode,r.level,r.round,r.roundTotal,r.score),('endless',10,1,4,0))
        self.inject('''r.nextWave=0;r.spawnIndex=1;r.spawnClock=0;r.rng=5;r.zombies={}''')
        self.advance(.05)
        self.assertEqual(self.state().slots['1'].run.zombies[1].row,4)
        self.inject('''r.nextWave=0;r.spawnIndex=r.roundTotal+1;r.spawnClock=0;r.sun=0
r.zombies={{kind="basic",row=3,x=500,hp=20,slow=0,jumped=false}}
r.bullets={{row=3,x=479,remaining=300,damage=20,ice=false,spore=false}}''')
        self.advance(.15);r=self.state().slots['1'].run
        self.assertEqual((r.round,r.roundTotal,r.score,r.sun),(2,12,10,55))
        progress=self.state().slots['1'].progress.stats
        self.assertEqual((progress.endlessRuns,progress.endlessBestRound,progress.endlessBestScore),(1,2,10))
        self.inject('''r.nextWave=0;r.spawnIndex=1;r.spawnClock=0;r.rng=5;r.zombies={}''')
        self.advance(.05)
        self.assertEqual(self.state().slots['1'].run.zombies[1].row,1)
        self.click('pause');self.restart();self.click('load1')
        r=self.state().slots['1'].run
        self.assertEqual((r.mode,r.round,r.roundTotal,r.score),('endless',2,12,10))
        self.click('resume');self.click('pause');self.click('exitRun');r=self.state().slots['1'].run
        self.assertEqual(r.status,'lost')
        self.assertFalse(self.lua.globals().session.paused)
        self.assertEqual((r.round,r.score),(2,10))
        self.lua.execute('assert(Mock.nodes.resultNext.object:IsShown() and Mock.nodes["buttonLabel/resultNext"].object.text=="再战无尽")')

    def test_native_abomination_vomit_front_dot_stun_and_resume(self):
        self.fresh(5)
        self.inject('''r.nextWave=10000;r.plants={};r.zombies={}
r.plants["21"]={kind="wall",row=3,col=3,hp=4000,age=0,timer=0}
r.plants["22"]={kind="wall",row=3,col=4,hp=4000,age=0,timer=0}
r.plants["24"]={kind="wall",row=3,col=6,hp=4000,age=0,timer=0}
r.plants["12"]={kind="wall",row=2,col=3,hp=4000,age=0,timer=0}
r.zombies[1]={kind="abomination",row=3,x=500,hp=2200,slow=0,jumped=false,phase="advance",phaseTime=0,abilityCooldown=0}''')
        before=self.state().slots['1'].run.time
        self.advance(1);r=self.state().slots['1'].run
        self.assertEqual(r.zombies[1].phase,'vomit');self.assertEqual(r.zombies[1].x,500)
        self.assertAlmostEqual(r.plants['21'].hp,4000-120*(r.time-before),delta=.01)
        self.assertTrue(any(c.id==22028 and c.channel=='Master' for c in self.lua.globals().Mock.soundCalls.values()))
        self.assertEqual(r.plants['24'].hp,4000);self.assertEqual(r.plants['12'].hp,4000)
        left=r.zombies[1].phaseTime
        self.restart();self.click('load1');self.assertEqual(self.state().slots['1'].run.zombies[1].phaseTime,left)
        self.click('resume');self.advance(2.3);r=self.state().slots['1'].run
        self.assertEqual(r.zombies[1].phase,'stunned');self.assertEqual(r.zombies[1].x,500)
        hp=r.plants['21'].hp;self.advance(3)
        self.assertEqual(self.state().slots['1'].run.plants['21'].hp,hp)
        self.advance(1.3);self.assertLess(self.state().slots['1'].run.zombies[1].x,500)

    def test_native_necromancer_fires_while_moving_and_frontline_blocks(self):
        self.fresh(6)
        self.inject('''r.nextWave=10000;r.plants={};r.zombies={};r.enemyBolts={}
r.plants["21"]={kind="wall",row=3,col=3,hp=4000,age=0,timer=0}
r.plants["19"]={kind="wall",row=3,col=1,hp=4000,age=0,timer=0}
r.zombies[1]={kind="necromancer",row=3,x=620,hp=520,slow=0,jumped=false,shotCooldown=0}''')
        self.advance(.2);r=self.state().slots['1'].run
        self.assertLess(r.zombies[1].x,620);self.assertEqual(len(list(r.enemyBolts.values())),1)
        x=r.enemyBolts[1].x
        self.restart();self.click('load1');self.assertEqual(self.state().slots['1'].run.enemyBolts[1].x,x)
        self.click('resume');self.advance(1.2);r=self.state().slots['1'].run
        self.assertEqual(r.plants['21'].hp,3955);self.assertEqual(r.plants['19'].hp,4000)
        self.assertEqual(len(list(r.enemyBolts.values())),0)
        self.assertTrue(any(c.id==23249 and c.channel=='SFX' for c in self.lua.globals().Mock.soundCalls.values()))

    def test_native_framing_uses_real_bounds_and_keeps_ground_anchor(self):
        self.lua.execute('''
local small=E.fitModelBounds({x=-.1,y=-.1,z=0},{x=.1,y=.1,z=.2},1,0,.82)
local huge=E.fitModelBounds({x=-10,y=-10,z=0},{x=10,y=10,z=20},1,0,.82)
assert(math.abs(huge.distance/small.distance-100)<.0001)
local function projectedBottom(f)return(-f.height/2-f.cameraZ)/(f.nearest*math.tan(f.fov/2))end
assert(math.abs(projectedBottom(small)+.8)<.0001)
assert(math.abs(projectedBottom(huge)+.8)<.0001)
assert(E.fitModelBounds({x=0,y=0,z=0},{x=0,y=1,z=1},1,0,.82)==nil)
assert(E.fitModelBounds({}, {},1,0,.82)==nil)
''')
        self.fresh(4)
        self.inject('''r.nextWave=10000;r.plants={};r.zombies={}
r.plants["12"]={kind="sunflower",row=2,col=3,hp=300,age=0,timer=5}
r.plants["30"]={kind="wall",row=4,col=3,hp=4000,age=0,timer=0}
r.zombies[1]={kind="basic",row=3,x=430,hp=200,slow=0,jumped=false}''')
        nodes=self.lua.globals().Mock.nodes
        self.lua.execute('assert(Mock.nodes.plant12.scene==Mock.nodes.enemy1.scene and Mock.nodes.enemy1.scene==Mock.nodes.plant30.scene)')
        self.assertGreater(nodes['plant12'].sceneDepth.near,nodes['enemy1'].sceneDepth.far)
        self.assertGreater(nodes['enemy1'].sceneDepth.near,nodes['plant30'].sceneDepth.far)
        self.assertGreater(nodes['seed1'].object.GetFrameLevel(nodes['seed1'].object),nodes['plant30'].object.GetFrameLevel(nodes['plant30'].object))
        self.assertLessEqual(nodes['plant30'].object.height,68*1.3)
        self.assertAlmostEqual(nodes['plant12'].model.yaw,3.141592653589793)  # sunflower face toward camera
        for node in nodes.values():
            if node.kind=='model' and node.generation==nodes['plant30'].generation:
                self.assertLessEqual(node.object.height,68*1.3)
                self.assertLessEqual(node.object.width,84*1.3)
        self.assertLess(nodes['cell12'].object.GetFrameLevel(nodes['cell12'].object),nodes['plant12'].object.GetFrameLevel(nodes['plant12'].object))
        self.assertFalse(nodes['cell12'].bg.IsShown(nodes['cell12'].bg))
        self.lua.execute('''
local s=session.view.gameSurface
s.begin()
local a=s.draw("movingDepthA",{kind="model",asset="pea",x=100,y=100,w=100,h=100,layer=4,depth=450})
local b=s.draw("movingDepthB",{kind="model",asset="zombie",x=100,y=100,w=100,h=100,layer=4,depth=200})
s.finish();assert(a.sceneDepth.far<b.sceneDepth.near)
s.begin()
s.draw("movingDepthA",{kind="model",asset="pea",x=100,y=100,w=100,h=100,layer=4,depth=150})
s.draw("movingDepthB",{kind="model",asset="zombie",x=100,y=100,w=100,h=100,layer=4,depth=300})
s.finish();assert(a.sceneDepth.near>b.sceneDepth.far)
''')

    def test_native_model_loading_while_paused_repairs_actual_depth_and_reuses_bounds(self):
        self.content.surfaceModelScene=False
        self.fresh(2)
        self.click('seed2');self.click('cell19');self.click('pause')
        self.lua.execute('''
local n=Mock.nodes.plant19
local bounds=n.bounds
local s=session.view.gameSurface
n.scene:SetFrameLevel(8000);n.object:SetFrameLevel(8001)
s.update()
assert(n.scene:GetFrameLevel()==n.drawLevel+1 and n.object:GetFrameLevel()==n.drawLevel)
assert(not session.view.cache.message:IsShown())
-- Simulate a later asynchronous model becoming available without a game UI redraw.
s.begin()
Mock.modelsNeverLoad=true
local other=s.draw("pendingFlower",{kind="model",asset="sunflower",x=200,y=200,w=90,h=88,layer=4})
s.finish();assert(not other.loaded)
other.model.modelID=other.model.displayID+1000
Mock.modelsNeverLoad=false
s.update()
assert(other.loaded and other.fitReady and other.scene:IsShown())
assert(other.bounds==bounds and other.scene.paused)
-- A quick map/battle round trip retains the same loaded model.
s.begin();s.finish()
local id=other.model.modelID
s.begin();s.draw("pendingFlower",{kind="model",asset="sunflower",x=200,y=200,w=90,h=88,layer=4});s.finish()
assert(other.model.modelID==id and other.bounds==bounds)
s.begin();s.finish()
''')
        self.advance(16)
        self.lua.execute('for _,pool in pairs(session.view.gameSurface.cache.pools)do for _,n in ipairs(pool)do if n.hiddenAt then assert(Mock.time-n.hiddenAt<15)end end end')

    def test_native_progress_navigation_recording_and_slot_isolation(self):
        self.fresh();self.click('cell19');self.advance(1)
        stats=self.state().slots['1'].progress.stats
        self.assertEqual((stats.runsStarted,stats.plantsPlaced,stats.sunSpent),(1,1,100))
        self.assertAlmostEqual(stats.seconds,1,delta=.08)
        self.click('speed');self.advance(1)
        self.assertAlmostEqual(self.state().slots['1'].progress.stats.seconds,2,delta=.08)
        self.click('pause');self.click('pauseProgress')
        before=self.state().slots['1'].progress.stats.seconds
        self.advance(2)
        self.assertEqual(self.state().slots['1'].progress.stats.seconds,before)
        self.click_surface_at(320,117)
        self.lua.execute('assert(Mock.nodes["progress.achievement.title1"].object:IsShown())')
        self.click('progress.back');self.assertTrue(self.lua.globals().session.paused)
        self.click('pauseProgress');self.lua.globals().Mock.pressEscape()
        self.lua.execute('assert(not Mock.nodes["progress.frame"].object:IsShown() and Mock.nodes.resume.object:IsShown())')
        self.click('pauseMap');self.click('progress');self.click('progress.back')
        self.assertFalse(self.lua.globals().session.paused)
        self.click('profiles');self.click('create2');self.click('progress')
        self.assertEqual(self.state().slots['2'].progress.stats.plantsPlaced,0)
        self.click('progress.back');self.click('profiles');self.click('delete2');self.click('confirmYes')
        self.restart();self.click('load1')
        stats=self.state().slots['1'].progress.stats
        self.assertEqual((stats.runsStarted,stats.plantsPlaced,stats.sunSpent),(1,1,100))
        self.assertTrue(self.state().slots['1'].progress.unlocked.first_plant)
        self.assertIsNone(self.state().slots['2'])

    def test_native_progress_kills_and_outcomes_are_counted_once(self):
        self.fresh(5)
        self.inject('''r.nextWave=10000;r.plants={};r.zombies={}
r.plants["19"]={kind="mine",row=3,col=1,hp=300,age=13,timer=0}
r.zombies[1]={kind="abomination",row=3,x=209.9,hp=2200,slow=0,jumped=false}''')
        self.advance(.15)
        self.assertEqual(self.state().slots['1'].progress.stats.kills,1)
        self.assertTrue(self.state().slots['1'].progress.unlocked.abomination)
        self.inject('''r.zombies={};r.wave=#content.campaign[r.level].waves;r.spawnIndex=1
for _,group in ipairs(content.campaign[r.level].waves[r.wave].types)do r.spawnIndex=r.spawnIndex+group[2]end''')
        self.advance(.15)
        stats=self.state().slots['1'].progress.stats
        self.assertEqual((stats.wins,stats.kills,stats.noMowerWins),(1,1,1))
        self.restart();self.click('load1');self.advance(.3)
        self.assertEqual(self.state().slots['1'].progress.stats.wins,1)
        self.assertEqual(self.state().slots['1'].progress.stats.kills,1)

    def test_native_contact_damage_has_master_audio(self):
        self.fresh(5)
        self.inject('''r.nextWave=10000;r.plants={};r.zombies={}
r.plants["19"]={kind="wall",row=3,col=1,hp=4000,age=0,timer=0}
r.zombies[1]={kind="abomination",row=3,x=209.9,hp=2200,slow=0,jumped=false,abilityCooldown=120}''')
        self.lua.execute('Mock.cvars.Sound_EnableSFX="0";Mock.soundCalls={}')
        before=self.state().slots['1'].run.time
        self.advance(1)
        r=self.state().slots['1'].run
        self.assertEqual(r.plants['19'].hp,3875)  # one impact, no continuous DPS ticks
        calls=list(self.lua.globals().Mock.soundCalls.values())
        self.assertTrue(any(c.id==3176 and c.channel=='Master' for c in calls))

    def test_native_bite_variants_alternate_on_real_impacts(self):
        self.fresh(5)
        self.inject('''r.nextWave=10000;r.plants={};r.zombies={}
r.plants["19"]={kind="wall",row=3,col=1,hp=4000,age=0,timer=0}
r.zombies[1]={kind="abomination",row=3,x=209.9,hp=2200,slow=0,jumped=false,abilityCooldown=120}''')
        self.lua.execute('Mock.soundCalls={};Mock.biteRequests={};local play=session.ctx.sound.play;session.ctx.sound.play=function(id,options)if id:match("^enemy_bite")then Mock.biteRequests[#Mock.biteRequests+1]=id end;return play(id,options)end')
        self.advance(2.1)
        self.assertEqual(list(self.lua.globals().Mock.biteRequests.values()),['enemy_bite_a','enemy_bite_b'])
        self.assertEqual([c.id for c in self.lua.globals().Mock.soundCalls.values() if c.id==3176],[3176,3176])

    def test_native_attack_impact_pose_pause_and_saved_hit(self):
        self.fresh(4)
        self.inject('''r.nextWave=10000;r.plants={};r.zombies={}
r.plants["19"]={kind="wall",row=3,col=1,hp=4000,age=0,timer=0}
r.zombies[1]={kind="basic",row=3,x=209,hp=200,slow=0,jumped=false}''')
        self.advance(.25)
        r=self.state().slots['1'].run
        self.assertEqual(r.plants['19'].hp,4000)
        self.assertFalse(r.zombies[1].attackHit)
        actor=self.lua.globals().Mock.nodes['enemy1'].model
        self.assertEqual(actor.animation,16)
        self.assertEqual(actor.animationSpeed,0)
        self.assertGreater(actor.animationOffset,0)
        self.click('pause');offset=actor.animationOffset
        self.advance(.5)
        self.assertEqual(actor.animationOffset,offset)
        self.assertEqual(self.state().slots['1'].run.plants['19'].hp,4000)
        self.click('resume');self.advance(.13)
        self.assertEqual(self.state().slots['1'].run.plants['19'].hp,3936)
        self.assertTrue(self.state().slots['1'].run.zombies[1].attackHit)
        self.restart();self.click('load1');self.click('resume');self.advance(.1)
        self.assertEqual(self.state().slots['1'].run.plants['19'].hp,3936)
        self.click('shovel');self.click('cell19');self.advance(.08)
        self.assertIsNone(self.state().slots['1'].run.zombies[1].attackTime)

    def test_native_shared_scene_warming_and_stable_enemy_leases(self):
        self.lua.execute('Mock.modelLoadDelay=.3')
        self.fresh(4);self.advance(2)
        self.click('cell19')
        self.assertTrue(self.lua.globals().Mock.nodes['plant19'].loaded)
        self.lua.execute('''local scenes=0
for _,f in ipairs(Mock.frames)do if f.kind=="ModelScene" then scenes=scenes+1 end end
assert(scenes==1,"units must share one scene, not a rectangle per cell")''')
        self.inject('''r.nextWave=10000;r.plants={};r.zombies={};r.bullets={};r.cooldowns={};r.sun=999
r.zombies[1]={kind="basic",row=3,x=300,hp=20,slow=0,jumped=false}
r.zombies[2]={kind="bucket",row=3,x=750,hp=1100,slow=0,jumped=false}''')
        self.advance(.4)
        self.lua.execute('Mock.stableActor=Mock.nodes.enemy2.model;Mock.stableRequests=Mock.stableActor.modelSetCalls')
        # Kill only the earlier array element through a real projectile.
        self.click('seed1');self.click('cell19');self.advance(.6)
        self.lua.execute('assert(Mock.nodes.enemy2.model==Mock.stableActor and Mock.stableActor.modelSetCalls==Mock.stableRequests)')
        self.assertEqual(self.state().slots['1'].run.zombies[1].viewSlot,2)
        self.click('pause');self.advance(.2)
        self.lua.execute('assert(Mock.nodes.enemy2.model.animationSpeed==0)')

    def test_native_combat_audio_groups_are_bounded_and_feedback_is_independent(self):
        self.fresh();self.lua.execute('Mock.soundCalls={};session.sound.stopOwner()')
        self.lua.execute('''
local start=Mock.time
for tick=1,600 do
 Mock.advance(1/60)
 for i=1,12 do session.sound.play(i%2==0 and "enemy_bite_a" or "hit_nature")end
 local nature,melee=0,0
 for _,v in pairs(session.sound.playing)do
  if v.group=="impact_nature"then nature=nature+1 elseif v.group=="melee"then melee=melee+1 end
 end
 assert(nature<=2 and melee<=2 and session.sound.count<=16)
end
local calls=#Mock.soundCalls
local hist={};for _,c in ipairs(Mock.soundCalls)do hist[c.id]=(hist[c.id] or 0)+1 end
local summary={};for id,count in pairs(hist)do summary[#summary+1]=id.."="..count end
assert(calls<=200,"dense combat escaped configured group and voice budgets; calls="..calls.." "..table.concat(summary,","))
local active={};for token in pairs(session.sound.playing)do active[#active+1]=token end
local token=session.sound.play("vomit");assert(token)
for _,existing in ipairs(active)do assert(session.sound.playing[existing],"elite stopped another sound layer")end
local sun=session.sound.play("sun");assert(sun,"pickup feedback keeps its separate budget")
''')

    def test_native_victory_actions_are_above_shield_and_receive_coordinate_clicks(self):
        self.fresh(4)
        finish='''r.zombies={};r.wave=#content.campaign[r.level].waves;r.spawnIndex=1
for _,group in ipairs(content.campaign[r.level].waves[r.wave].types)do r.spawnIndex=r.spawnIndex+group[2]end'''
        self.inject(finish);self.advance(.2)
        self.lua.execute('''
assert(snapshot().slots["1"].run.status=="won")
assert(Mock.nodes.resultNext.object:GetFrameLevel()>Mock.nodes.shield.object:GetFrameLevel())
assert(Mock.nodes.resultMap.object:GetFrameLevel()>Mock.nodes.shield.object:GetFrameLevel())
for _,f in ipairs(Mock.frames)do assert(not f.requestedLevel or f.requestedLevel<10000,"frame-level overflow")end
''')
        self.click_surface_at(592,381)
        self.assertEqual(self.state().slots['1'].run.level,5)
        self.assertEqual(self.state().slots['1'].run.status,'playing')
        self.inject(finish);self.advance(.2)
        self.click_surface_at(368,381)
        self.lua.execute('assert(Mock.nodes.level6.object:IsShown() and Mock.nodes.level6.enabled)')


if __name__=='__main__':
    suite=unittest.TestSuite(NativeTests(name) for name in NativeTests.__dict__ if name.startswith('test_native_'))
    result=unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(not result.wasSuccessful())
