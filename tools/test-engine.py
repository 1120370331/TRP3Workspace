"""Lua 5.1 behavioral checks, including the generated sandbox/macro path.

The host double is deliberately labelled mock; this is not a WoW performance run.
"""
from pathlib import Path
import json
import sys
import unittest
import zlib
import hashlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.local-tools/python'))
try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    raise SystemExit('Install test runtime: python -m pip install --target .local-tools/python -r tools/requirements-test.txt')

MODULES = ['core', 'math3d', 'particles3d', 'pixel-materials', 'surface-effects3d', 'scene3d', 'view3d', 'telemetry', 'host', 'surface-actors', 'surface', 'view', 'input', 'world', 'audio', 'effects', 'runtime']

class EngineTests(unittest.TestCase):
    item_dir = 'performance-lab'
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute((ROOT / 'tests/support/mock-wow.lua').read_text('utf-8'))
        self.lua.execute('E={}'); self.E = self.lua.globals().E
        for name in MODULES:
            self.lua.execute((ROOT / f'framework/item-game/{name}.lua').read_text('utf-8'))(self.E, self.lua.globals())
        self.content = self.E.JSON.decode((ROOT / f'items/{self.item_dir}/content.json').read_text('utf-8'))
        manifest = json.loads((ROOT / f'items/{self.item_dir}/item.json').read_text('utf-8'))
        manifest['sourceHash'] = 'MOCK_FUNCTIONAL_TEST_ONLY'
        self.manifest = self.E.JSON.decode(json.dumps(manifest, ensure_ascii=False))
        self.lua.globals().manifest = self.manifest
        self.lua.globals().content = self.content
        self.lua.execute('item={id=manifest.rootId,vars={}};Mock.inventory.content["1"]=item;Mock.classes[manifest.rootId]={MD={V=manifest.objectVersion}};args={object=item,container=Mock.inventory}')

    def start(self, code='return function(ctx) return {onStart=function()end,onSave=function()return {ok=true}end} end'):
        self.E.registerGame(self.manifest.gameId, self.lua.table_from({'apiVersion':1,'saveVersion':1,'create':self.lua.execute(code)}))
        host = self.E.newWoWHost(self.lua.globals().args, self.manifest)
        host.kind = 'mock'
        result = self.E.start(host, self.manifest, self.content)
        self.assertFalse(isinstance(result, tuple), str(result))
        self.lua.globals().session = result
        return result

    def advance(self, seconds, step=1/60):
        self.lua.globals().Mock.advance(seconds, step)

    def test_json_roundtrip_rejects_code_and_cycles(self):
        self.lua.execute('v=E.JSON.decode([[{"中文":"🐺\\n|~^","values":[true,false,1.25],"null":null}]]);assert(v["中文"]=="🐺\\n|~^");assert(v.values[2]==false);assert(v.null==E.JSON.null)')
        for bad in ['{"x":1,"x":2}', '[01]', '{"x":function()end}', '"\\ud800"', '[1,]', '1e999', '{}tail']:
            with self.assertRaises(Exception): self.E.JSON.decode(bad)
        self.lua.execute('cycle={};cycle.self=cycle;assert(not pcall(E.JSON.encode,cycle))')
        self.lua.execute('assert(E.util.copy(v).null==E.JSON.null);local m=E.newMeter(.01);m.add(2500);assert(m.summary().p95>=2500)')

    def test_game_factory_and_timer_are_session_scoped(self):
        s = self.start('return function(ctx) local n=0; return {onStart=function()ctx.clock.after(.1,function()n=n+1 end)end,onSave=function()return {n=n}end} end')
        self.advance(.2); self.assertTrue(s.save('test')[0])
        self.assertEqual(self.E.JSON.decode(self.lua.globals().item.vars.IG_SAVE_V1).game.n, 1)
        s.stop('close'); writes = self.lua.globals().Mock.writes
        self.advance(1); self.assertEqual(self.lua.globals().Mock.writes, writes)
        self.lua.execute('assert(E.current==nil);for _,r in ipairs(Mock.callbacks)do assert(not r.active)end;for _,f in ipairs(Mock.frames)do assert(not f.scripts.OnUpdate)end')

    def test_input_edges_and_release_during_protected_combat(self):
        self.start('return function(ctx) return {onStart=function()end,onFixedUpdate=function(dt,input)if input.attackPressed then Mock.attacks=(Mock.attacks or 0)+1 end end}end')
        self.lua.execute('assert(session.input.acquire());Mock.keys.J=true')
        self.advance(.15); self.assertEqual(self.lua.globals().Mock.attacks, 1)
        self.lua.execute('Mock.keys.J=false'); self.advance(.05)
        self.lua.execute('Mock.keys.J=true'); self.advance(.1); self.assertEqual(self.lua.globals().Mock.attacks, 2)
        self.lua.execute('Mock.inCombat=true;Mock.restrictKeyboard=true;Mock.fire("PLAYER_REGEN_DISABLED");assert(E.current==nil);assert(not session.view.frame:IsShown())')

    def test_pause_no_catchup_and_instance_start_rejected(self):
        s=self.start(); self.advance(.1); before=s.time
        s.pause('test'); self.advance(3); self.assertEqual(s.time,before)
        s.resume(); self.advance(.05); self.assertLess(s.time-before,.1)
        self.lua.execute('Mock.instanceType="party";Mock.fire("PLAYER_ENTERING_WORLD");assert(E.current==nil)')
        host=self.E.newWoWHost(self.lua.globals().args,self.manifest);host.kind='mock'
        result=self.E.start(host,self.manifest,self.content)
        self.assertEqual(result,(None,'wow_instance'))

    def test_physics_jump_landing_and_fast_projectile_wall(self):
        self.start('return function(ctx)return {onStart=function()ctx.level.load("arena_01");Mock.hero=ctx.world.spawn("hero",{x=100,y=20})end}end')
        self.advance(.1)
        self.lua.execute('assert(session.world.byId[Mock.hero].grounded);session.world.setIntent(Mock.hero,{jumpPressed=true})')
        self.advance(.2); self.assertGreater(self.lua.eval('session.world.byId[Mock.hero].y'),20)
        self.advance(1); self.assertAlmostEqual(self.lua.eval('session.world.byId[Mock.hero].y'),20,places=5)
        self.lua.execute('assert(E.sweep({x=0,y=30,w=5,h=5},1000,0,{x=100,y=25,w=5,h=20})~=nil);assert(E.sweep({x=0,y=80,w=5,h=5},1000,0,{x=100,y=25,w=5,h=20})==nil)')
        self.lua.execute('session.world.terrain={{x=200,y=20,w=10,h=100}};Mock.target=session.world.spawn("target",{x=250,y=40});Mock.bullet=session.world.spawn("bullet",{x=150,y=40},{vx=12000});Mock.hp=session.world.byId[Mock.target].hp')
        self.advance(.04)
        self.lua.execute('assert(session.world.byId[Mock.bullet]==nil);assert(session.world.byId[Mock.target].hp==Mock.hp)')

    def test_attack_dedup_and_grid_naive_equivalence(self):
        self.start('return function(ctx)return {onStart=function()ctx.level.load("arena_01");Mock.hero=ctx.world.spawn("hero",{x=100,y=20});Mock.enemy=ctx.world.spawn("target",{x=135,y=20})end}end')
        self.lua.execute('Mock.hp=session.world.byId[Mock.enemy].hp;assert(session.world.requestAction(Mock.hero,"slash"))')
        self.advance(.45)
        self.lua.execute('assert(Mock.hp-session.world.byId[Mock.enemy].hp==12)')
        self.lua.execute('for i=1,200 do session.world.spawn("target",{x=(i*37)%900,y=30+(i*19)%300})end;local box={x=180,y=40,w=120,h=150};session.ctx.collision.setBroadphase("grid");a=session.ctx.collision.query(box,"enemy");session.ctx.collision.setBroadphase("naive");b=session.ctx.collision.query(box,"enemy");table.sort(a);table.sort(b);assert(E.JSON.encode(a)==E.JSON.encode(b))')

    def test_save_backup_and_journal_prevent_repeat_grants(self):
        s=self.start(); self.assertTrue(s.save('first')[0]); self.assertTrue(s.save('second')[0])
        r=s.ctx.inventory.grant('token',2,'reward-one');self.assertEqual(r.status,'complete')
        self.assertEqual(s.ctx.inventory.grant('token',2,'reward-one').status,'complete')
        self.assertEqual(s.ctx.inventory.count('token'),2)
        self.assertEqual(s.ctx.inventory.grant('token',3,'reward-one').reason,'operation_id_conflict')
        self.lua.execute('item.inTrade=true')
        self.assertFalse(s.save('trade')[0]); self.lua.execute('Mock.fireTRP("REFRESH_BAG");assert(E.current==nil)')

    def test_failure_cleanup_even_if_save_and_stop_throw(self):
        self.start('return function(ctx)return {onStart=function()ctx.clock.after(.02,function()error("boom")end)end,onSave=function()error("bad save")end,onStop=function()error("bad stop")end}end')
        self.advance(.1)
        self.lua.execute('assert(E.current==nil);assert(#session.tasks==0);assert(session.sound.count==0);for _,f in ipairs(Mock.frames)do assert(not f.scripts.OnUpdate)end')
        self.assertIn('boom',self.E.lastLogs[self.manifest.rootId])

    def test_frame_pools_plateau_on_reopen(self):
        code='return function(ctx)return {onStart=function()for i=1,30 do ctx.world.spawn("sprite",{x=i*20,y=60})end end}end'
        s=self.start(code);self.advance(.1);s.stop('close');first=self.lua.eval('#Mock.frames')
        for _ in range(4):
            s=self.start(code);self.advance(.1);s.stop('close')
            self.assertEqual(self.lua.eval('#Mock.frames'),first)

    def test_particle_burst_is_bounded_interpolated_and_session_timed(self):
        self.lua.execute('''
content.limits.maxParticles=4
content.assets.textures=content.assets.textures or {};content.assets.textures.particle_probe={kind="texturePath",path="Interface\\Cooldown\\star4"}
content.effects={spark={texture="particle_probe",mode="burst",count=6,space="screen",layer=7,blend="ADD",
 lifetime={.5,.5},speed={60,60},directionDeg={0,0},startSize={12,12},endSize={2,2},
 startAlpha={1,1},endAlpha={0,0},startColor={1,.5,.2,1},endColor={.2,.5,1,1},spinDeg={90,90}}}
''')
        s=self.start('return function(ctx)return {onStart=function()Mock.made,Mock.fxDropped=ctx.fx.burst("spark",{x=100,y=80,seed=42})end}end')
        self.assertEqual(self.lua.globals().Mock.made,4);self.assertEqual(self.lua.globals().Mock.fxDropped,2)
        self.lua.execute('assert(session.ctx.fx.stats().activeParticles==4);assert(session.ctx.fx.stats().droppedParticles==2)')
        self.advance(.1)
        self.lua.execute('''
local p=session.effects.particles[1]
assert(p.x>100 and p.age>0 and p.handle.texture.blend=="ADD")
assert(p.handle.texture.rotation~=0 and p.handle.texture.vertexColor[4]<1)
assert(p.handle.frame:GetFrameLevel()>p.handle.frame.parent:GetFrameLevel())
Mock.particleAge=p.age
session.pause("particle_test")
''')
        self.advance(.5);self.lua.execute('assert(session.effects.particles[1].age==Mock.particleAge)')
        self.lua.execute('session.resume();assert(session.ctx.session.setSpeed(2))');self.advance(.1)
        self.assertGreater(self.lua.eval('session.effects.particles[1].age-Mock.particleAge'),.15)
        self.advance(.3);self.lua.execute('assert(session.ctx.fx.stats().activeParticles==0);assert(session.ctx.fx.stats().pooledParticles==4)')
        s.stop('close');self.lua.execute('for _,h in ipairs(E.effectsViewCache.pool)do assert(not h.active and not h.frame:IsShown())end')

    def test_continuous_particle_emitter_finishes_follows_entity_and_clears(self):
        self.lua.execute('''
content.limits.maxParticles=16;content.limits.maxEmitters=2
content.assets.textures=content.assets.textures or {};content.assets.textures.particle_probe={kind="texturePath",path="Interface\\Cooldown\\star4"}
content.effects={mist={texture="particle_probe",mode="continuous",rate=60,duration=.12,initialBurst=2,
 lifetime=.2,speed=0,startSize=8,endSize=16,startAlpha=1,endAlpha=0,space="world",layer=4}}
''')
        self.start('return function(ctx)return {onStart=function()ctx.level.load("arena_01");Mock.owner=ctx.world.spawn("hero",{x=120,y=20});Mock.emitter=assert(ctx.fx.start("mist",{entityId=Mock.owner,seed=7}))end}end')
        self.advance(.06)
        self.lua.execute('''
assert(session.ctx.fx.stats().activeEmitters==1 and session.ctx.fx.stats().activeParticles>2)
local p=session.effects.particles[1];assert(p.space=="world" and p.x==120)
session.world.byId[Mock.owner].x=180
''')
        self.advance(.04)
        self.lua.execute('''
local newest=session.effects.particles[#session.effects.particles]
assert(newest.x==180)
assert(session.ctx.fx.burst("missing",{})==nil)
''')
        self.advance(.4)
        self.lua.execute('assert(session.ctx.fx.stats().activeEmitters==0 and session.ctx.fx.stats().activeParticles==0)')
        self.lua.execute('Mock.emitter=assert(session.ctx.fx.start("mist",{x=50,y=50,duration=1}));Mock.advance(.04);assert(session.ctx.fx.stop(Mock.emitter,true));assert(session.ctx.fx.stats().activeParticles==0)')

    def test_particle_native_anchor_budget_delay_and_pool_plateau(self):
        self.lua.execute('''
content.limits.maxParticles=12;content.limits.maxParticleSpawnsPerStep=8
content.assets.textures=content.assets.textures or {};content.assets.textures.fx={kind="fileID",id=131943}
content.effects={fx={texture="fx",count=6,lifetime=.3,startSize=10,delay=.1,aspectRatio=.3}}
''')
        self.start()
        self.lua.execute('''
local fx=session.ctx.fx
assert(fx.burst("fx",{x=100,y=100,scale=2,seed=12})==6)
assert(fx.burst("fx",{x=100,y=100})==2)
assert(fx.stats().droppedParticles==4)
local p=session.effects.particles[1]
assert(p.startSize==20 and p.endSize==20,"scale must apply once")
-- Native WoW doesn't populate .parent. Strip only this mock convenience;
-- the explicit anchor must remain the actual FX layer, not UIParent.
local saved=p.handle.frame.parent;p.handle.frame.parent=nil
session.effects.render(0);assert(not p.handle.visible)
p.handle.frame.parent=saved
Mock.advance(.15)
assert(p.handle.frame.point[2]==saved and p.handle.visible)
assert(math.abs(p.handle.frame.width/p.handle.frame.height-.3)<1e-6)
Mock.advance(.5)
local size=#Mock.frames;local pool=fx.stats().pooledParticles
for n=1,10 do fx.burst("fx",{x=100,y=100});Mock.advance(.5)end
assert(#Mock.frames==size and fx.stats().pooledParticles==pool)
assert(fx.stats().activeParticles==0 and fx.stats().visibleParticles==0)
''')

    def test_particle_shared_emitter_limit_and_priority_eviction(self):
        self.lua.execute('''
content.limits.maxParticles=8;content.limits.maxParticleSpawnsPerStep=8
content.assets.textures=content.assets.textures or {};content.assets.textures.fx={kind="fileID",id=131943}
content.effects={a={texture="fx",count=8,lifetime=1,priority=0},b={texture="fx",count=1,lifetime=.3,priority=3},
stream={texture="fx",mode="continuous",rate=512,lifetime=1}}
''')
        self.start()
        self.lua.execute('''
local fx=session.ctx.fx;fx.burst("a",{});Mock.advance(.04)
assert(fx.burst("b",{})==1);assert(fx.stats().activeParticles==8 and fx.stats().evictedParticles==1)
fx.clear();Mock.advance(.04)
fx.start("stream",{});fx.start("stream",{});Mock.advance(1/60)
assert(fx.stats().activeParticles<=8 and fx.stats().droppedParticles>0)
fx.clear();assert(fx.stats().activeEmitters==0)
''')

    def test_particle_mask_is_removed_when_pool_slot_changes_material(self):
        self.lua.execute('''
content.assets.textures={dot={kind="fileID",id=130871,maskPath="circle"},spark={kind="fileID",id=130725}}
content.effects={a={texture="dot",count=1,lifetime=.1},b={texture="spark",count=1,lifetime=.1}}
''')
        self.start()
        self.lua.execute('''
local fx=session.ctx.fx;fx.burst("a",{});local h=session.effects.particles[1].handle
assert(h.texture.mask and h.maskApplied);Mock.advance(.2)
fx.burst("b",{});assert(session.effects.particles[1].handle==h)
assert(not h.texture.mask and not h.maskApplied)
''')

    def test_particle_crystal_facets_form_diamond_and_reset_on_reuse(self):
        self.lua.execute('''
content.assets.textures={white={kind="fileID",id=130871}}
content.effects={shard={texture="white",shape="crystal",count=1,lifetime=.2,startSize=20,endSize=20,aspectRatio=.3,
speed=100,directionDeg=90,alignToVelocity=true},dot={texture="white",count=1,lifetime=.2}}
''')
        self.start()
        self.lua.execute('''
local fx=session.ctx.fx;fx.burst("shard",{x=100,y=100});session.effects.render(0)
local h=session.effects.particles[1].handle
assert(h.crystal and h.facet:IsShown() and not h.maskApplied)
-- Two triangles share top and bottom; their outer corners are left/right.
local left,right=h.texture.vertices,h.facet.vertices
assert(left[1][1]==3 and left[1][2]==0)
assert(left[2][1]==0 and left[2][2]==10)
assert(right[3][1]==0 and right[3][2]==-10)
assert(left[4][1]==-3 and left[4][2]==0)
Mock.advance(.3);fx.burst("dot",{});session.effects.render(0)
assert(session.effects.particles[1].handle==h and not h.crystal and not h.facet:IsShown())
for _,v in pairs(h.texture.vertices)do assert(v[1]==0 and v[2]==0)end
''')

    def test_escape_closes_observe_capture_and_paused_sessions(self):
        for mode in ['observe','capture','paused']:
            with self.subTest(mode=mode):
                self.start()
                if mode=='capture': self.lua.execute('assert(session.input.acquire())')
                if mode=='paused': self.lua.execute('session.pause("manual")')
                self.lua.execute('''
assert(session.music.play("arena"));local music=session.music.handle
Mock.pressEscape()
assert(not session.view.frame:IsShown());assert(E.current==nil);assert(session.closed)
assert(not session.view.frame.scripts.OnUpdate);assert(not session.view.frame.keyboard)
assert(not Mock.sounds[music]);assert(E.JSON.decode(item.vars.IG_SAVE_V1).game.ok)
assert(#UISpecialFrames==1)
''')

    def test_escape_dismisses_focused_panel_then_closes_game(self):
        for panel in ['log','prompt']:
            with self.subTest(panel=panel):
                self.start()
                if panel=='log': self.lua.execute('session.view.showLog("log sample")')
                else: self.lua.execute('session.view.prompt("input","draft",function()error("cancel must not submit")end)')
                self.lua.execute('''
local c=session.view.cache
assert(c.close:GetFrameLevel()>c.logFrame:GetFrameLevel())
Mock.pressEscape()
assert(not c.logFrame:IsShown());assert(Mock.focus==nil);assert(not c.apply.scripts.OnClick)
assert(session.view.frame:IsShown());assert(not session.stopping)
Mock.pressEscape();assert(E.current==nil);assert(session.closed)
''')

    def test_close_button_works_with_log_and_after_reopen(self):
        for _ in range(2):
            self.start()
            self.lua.execute('''
session.view.showLog("sample");Mock.click("X")
assert(not session.view.frame:IsShown());assert(not session.view.cache.logFrame:IsShown())
assert(Mock.focus==nil);assert(E.current==nil);assert(session.closed)
''')

    def test_close_cleanup_errors_do_not_strand_or_reopen_old_session(self):
        for failure in ['phase','log','save']:
            with self.subTest(failure=failure):
                self.start()
                if failure=='phase': self.lua.execute('session.perf.finish=function()error("phase summary failed")end')
                elif failure=='log': self.lua.execute('session.perf.export=function()error("log encoding failed")end')
                else: self.lua.execute('session.save=function()error("host save failed")end')
                self.lua.execute('''
Mock.click("X")
assert(E.current==nil);assert(session.closed);assert(#session.cleanupErrors>0)
assert(not session.view.frame:IsShown());assert(not session.view.frame.scripts.OnUpdate)
for _,r in ipairs(Mock.callbacks)do assert(not r.active)end
session.stop("again")
''')

    def test_benchmark_suite_and_log_export_are_structured(self):
        self.content.benchmark.warmup=.04; self.content.benchmark.duration=.08
        self.start((ROOT/'items/performance-lab/game.lua').read_text('utf-8'))
        self.lua.execute('Mock.click("自动基准")');self.advance(6)
        self.lua.execute('assert(session.paused);assert(not session.perf.phase)')
        log=self.lua.globals().session.perf.export()
        records=[json.loads(line) for line in log.splitlines()]
        phases=[r for r in records if r['type']=='phase.end']
        self.assertEqual(len(phases),24)
        self.assertTrue(all(r['data']['frames']>0 for r in phases))
        self.assertEqual(records[0]['data']['hostKind'],'mock')
        self.assertTrue(any(r['type']=='suite.end' for r in records))
        self.lua.execute('Mock.click("复制日志");assert(Mock.focus~=nil);assert(session.input.mode=="observe")')

    def test_model_load_failure_is_not_performance_pass(self):
        self.content.benchmark.warmup=.02;self.content.benchmark.duration=.05
        self.lua.execute('Mock.modelsNeverLoad=true')
        s=self.start((ROOT/'items/performance-lab/game.lua').read_text('utf-8'))
        self.lua.execute('Mock.click("模型/场景")');self.advance(.2)
        records=[json.loads(line) for line in s.perf.export().splitlines()]
        end=next(r for r in records if r['type']=='phase.end')
        self.assertEqual(end['data']['status'],'models_not_verified')

    def test_generated_package_compiles_with_lua51(self):
        data=json.loads((ROOT/'items/performance-lab/dist/item.decoded.json').read_text('utf-8'))
        for name,expected in data['summary']['sourceFiles'].items():
            canonical=(ROOT/f'framework/item-game/{name}.lua').read_text('utf-8').encode('utf-8')
            self.assertEqual(hashlib.sha256(canonical).hexdigest(),expected,'stale distribution: rebuild before tests')
        root=data['exportTuple']['3']
        compile_lua=self.lua.eval('function(source)local fn,err=loadstring(source);return fn~=nil,err end')
        def check(obj):
            for wf in obj.get('SC',{}).values():
                for step in wf['ST'].values():
                    for effect in step.get('e',{}).values():
                        if effect['id']=='script': self.assertEqual(compile_lua(effect['args']['1']),(True,None))
                        if effect['id']=='secure_macro': self.assertEqual(compile_lua(effect['args']['1'][5:]),(True,None))
            for child in obj.get('IN',{}).values():check(child)
        check(root)

    def test_fast_key_tap_survives_between_frames(self):
        self.start('return function(ctx)return {onStart=function()end,onFixedUpdate=function(dt,i)if i.attackPressed then Mock.edges=(Mock.edges or 0)+1 end end}end')
        self.lua.execute('session.input.acquire();local f=session.view.frame;f.scripts.OnKeyDown(f,"J");f.scripts.OnKeyUp(f,"J")')
        self.advance(.05);self.assertEqual(self.lua.globals().Mock.edges,1)

    def test_newer_save_is_preserved_instead_of_restoring_old_backup(self):
        self.lua.execute('item.vars.IG_SAVE_V1=E.JSON.encode({gameId=manifest.gameId,schemaVersion=1,gameSaveVersion=2,revision=8,game={future=true}});item.vars.IG_SAVE_BACKUP_V1=E.JSON.encode({gameId=manifest.gameId,schemaVersion=1,gameSaveVersion=1,game={old=true}})')
        original=self.lua.globals().item.vars.IG_SAVE_V1
        self.E.registerGame(self.manifest.gameId,self.lua.table_from({'apiVersion':1,'saveVersion':1,'create':self.lua.execute('return function(ctx)return {onStart=function()end}end')}))
        host=self.E.newWoWHost(self.lua.globals().args,self.manifest)
        result=self.E.start(host,self.manifest,self.content)
        self.assertIsNone(result[0]);self.assertIn('migration required',result[1]);self.assertEqual(self.lua.globals().item.vars.IG_SAVE_V1,original)

    def test_native_editor_revision_before_launch_is_not_a_runtime_change(self):
        self.lua.execute('Mock.classes[manifest.rootId].MD.V=manifest.objectVersion+7')
        s=self.start();self.advance(.6)
        self.lua.execute('assert(E.current==session);assert(not session.stopping);assert(session.view.frame:IsShown())')
        header=json.loads(s.perf.export().splitlines()[0])['data']
        self.assertEqual(header['objectRevision'],self.manifest.objectVersion+7)
        self.assertEqual(header['objectVersion'],self.manifest.objectVersion)
        self.assertEqual(s.host.definitionVersion,self.manifest.objectVersion+7)

    def test_definition_revision_or_manifest_changed_during_run_still_closes(self):
        for change in ['revision','manifest']:
            with self.subTest(change=change):
                self.lua.execute('Mock.classes[manifest.rootId].IN={ig_manifest={PA={{TX="initial"}}}}')
                self.start()
                if change=='revision': self.lua.execute('Mock.classes[manifest.rootId].MD.V=Mock.classes[manifest.rootId].MD.V+1')
                else: self.lua.execute('Mock.classes[manifest.rootId].IN.ig_manifest.PA[1].TX="updated"')
                self.advance(.3)
                self.lua.execute('assert(E.current==nil);assert(session.closed);assert(session.stopReason=="definition_changed");assert(item.vars.IG_BOOT_STATUS_V1:find("IG STOP",1,true))')

    def test_reuse_after_native_edit_starts_new_session_with_updated_content(self):
        self.start()
        self.lua.execute('Mock.oldSession=session;Mock.classes[manifest.rootId].MD.V=Mock.classes[manifest.rootId].MD.V+1')
        self.start()
        self.advance(.3)
        self.lua.execute('assert(Mock.oldSession.closed);assert(session~=Mock.oldSession);assert(E.current==session);assert(not session.stopping)')

    def test_equipment_attributes_are_instance_data(self):
        s=self.start();r=s.ctx.inventory.grant('blade',1,'equipment-one');self.assertEqual(r.status,'complete')
        self.lua.execute('local found;for _,o in pairs(Mock.inventory.content)do if o.id==manifest.rootId.." gear_blade"then found=o end end;assert(found);assert(E.JSON.decode(found.vars.IG_EQUIP_V1).attackBonus==2);assert(not Mock.classes[manifest.rootId].vars)')

    def test_cancelled_musician_import_cannot_restart_audio(self):
        self.lua.execute('Musician={Song={}};function Musician.Song.create()local s={};function s:ImportFromBase64(code,crop,done)Mock.importDone=done end;function s:Play()Mock.musicPlays=(Mock.musicPlays or 0)+1 end;function s:Resume()self:Play()end;function s:IsPlaying()return false end;function s:Stop()end;function s:CancelImport()Mock.importCancelled=true end;return s end')
        s=self.start();self.assertTrue(s.music.playCode('test-song-code'))
        self.lua.execute('assert(session.music.state=="loading" and type(Mock.importDone)=="function")')
        s.stop('close');self.lua.execute('Mock.importDone(true);assert(Mock.importCancelled);assert(Mock.musicPlays==nil)')

    def test_sound_polyphony_volume_and_failed_replacement_preserve_active_voice(self):
        self.lua.execute('''
content.limits.maxSoundVoices=2;content.soundBuses={impact=.5}
content.sounds={a={kind="soundKitID",id=10,bus="impact",baseVolume=1,cooldown=0,maxDuration=2},
b={kind="fileID",id=11,volumeSoundKitID=20,bus="impact",baseVolume=1,cooldown=0,maxDuration=2},
important={kind="soundKitID",id=30,priority=3,baseVolume=1,cooldown=0,maxDuration=2}}
Mock.soundKitDuration=1
''')
        self.start()
        self.lua.execute('''
local sound=session.sound
local a=sound.play("a");local b=sound.play("b");assert(a and b and sound.count==2)
assert(Mock.soundCalls[1].volumeOverride==.5 and Mock.soundCalls[2].volumeOverride==.5)
local original=sound.playing[a].handle
Mock.failSoundKit=30
assert(not sound.play("important"));assert(Mock.sounds[original] and sound.count==2)
Mock.failSoundKit=nil;Mock.advance(.3)
assert(sound.play("important"));assert(not Mock.sounds[original] and sound.count==2)
assert(sound.setBusVolume("impact",0));assert(sound.count==1)
assert(sound.setVolume(0));assert(sound.count==0);assert(Mock.cvarWrites==0)
assert(not sound.setVolume(-.1));assert(not sound.setBusVolume("missing",.5))
''')

    def test_sound_sweeps_are_bounded_under_duplicate_requests(self):
        self.start()
        self.lua.execute('''
local checks=0;local original=session.host.soundPlaying
session.host.soundPlaying=function(h)checks=checks+1;return original(h)end
session.sound.play("combat_hit")
for i=1,1000 do session.sound.play("combat_hit")end
assert(checks<=1,"duplicate requests must not rescan every voice")
''')

    def test_host_sound_volume_does_not_silently_ignore_unsupported_file_control(self):
        self.start()
        self.lua.execute('''
local h,why=session.host.playSound({kind="fileID",id=123,channel="SFX"},.5)
assert(not h and why=="sound_volume_unsupported")
assert(session.host.playSound({kind="fileID",id=123,channel="SFX"},1))
local count=#Mock.soundCalls
assert(not session.host.playSound({kind="soundKitID",id=12},0));assert(#Mock.soundCalls==count)
assert(Mock.cvarWrites==0)
''')

    def test_bgm_plays_with_wow_background_music_disabled(self):
        self.lua.execute('Mock.cvars.Sound_EnableMusic="0"')
        self.start()
        self.lua.execute('assert(session.music.play("arena"));assert(Mock.soundCalls[#Mock.soundCalls].channel=="SFX");assert(Mock.cvars.Sound_EnableMusic=="0");assert(Mock.cvarWrites==0)')
        records=[json.loads(line) for line in self.lua.globals().session.perf.export().splitlines()]
        playback=next(r['data'] for r in records if r['type']=='music.playback')
        self.assertTrue(playback['ok']);self.assertEqual(playback['channel'],'SFX')
        self.assertEqual(playback['audio']['cvars']['Sound_EnableSFX'],'1')

    def test_bgm_respects_mute_volume_and_explicit_music_channel(self):
        self.start()
        self.lua.execute('''
local cases={
 {key="Sound_EnableAllSound",reason="all_sound_disabled"},
 {key="Sound_MasterVolume",reason="master_volume_zero"},
 {key="Sound_EnableSFX",reason="channel_disabled"},
 {key="Sound_SFXVolume",reason="channel_volume_zero"},
 {key="Sound_EnableMusic",reason="channel_disabled",channel="Music"},
 {key="Sound_MusicVolume",reason="channel_volume_zero",channel="Music"},
}
for _,case in ipairs(cases)do
 content.music.arena.channel=case.channel;Mock.cvars[case.key]="0"
 local calls=#Mock.soundCalls
 local ok,why=session.music.play("arena")
 assert(ok==false and why==case.reason, tostring(why))
 assert(session.music.state=="unavailable" and session.music.lastError==why)
 assert(#Mock.soundCalls==calls);assert(Mock.cvarWrites==0)
 Mock.cvars[case.key]="1"
 assert(session.music.play("arena"));assert(session.music.channel==(case.channel or "SFX"))
 session.music.stop("case_end")
end
''')

    def test_bgm_unknown_settings_and_native_failure_are_diagnosed(self):
        self.start()
        self.lua.execute('''
GetCVar=function()error("CVar unavailable on this client")end
assert(session.music.play("arena"));session.music.stop("test")
Mock.muteSounds=true
local ok,why=session.music.play("arena");assert(ok==false and why=="sound_not_started")
PlaySoundFile=function()error("invalid resource")end
ok,why=session.music.play("arena");assert(ok==false and why=="sound_api_error")
content.music.arena.channel="Master"
ok,why=session.music.play("arena");assert(ok==false and why=="invalid_music_channel")
assert(Mock.cvarWrites==0)
''')
        records=[json.loads(line) for line in self.lua.globals().session.perf.export().splitlines()]
        failures=[r['data']['reason'] for r in records if r['type']=='music.playback' and not r['data']['ok']]
        self.assertEqual(failures,['sound_not_started','sound_api_error','invalid_music_channel'])

    def test_bgm_pause_resume_loop_and_stop_only_own_audio(self):
        self.start()
        self.lua.execute('''
local _,foreign=PlaySoundFile(123,"SFX")
assert(session.music.play("arena",{loop=true}));local first=session.music.handle
session.pause("test");assert(not Mock.sounds[first] and Mock.sounds[foreign]);assert(session.music.state=="paused")
session.resume();local second=session.music.handle
assert(second and second~=first and Mock.sounds[foreign]);assert(session.music.state=="playing")
Mock.sounds[second]=nil;session.music.update();local third=session.music.handle
assert(third and third~=second and Mock.sounds[third]);assert(Mock.sounds[foreign])
session.stop("test");assert(not Mock.sounds[third] and Mock.sounds[foreign]);assert(Mock.cvarWrites==0)
''')

    def test_bgm_test_button_with_music_disabled_records_native_load(self):
        self.lua.execute('Mock.cvars.Sound_EnableMusic="0"')
        self.content.benchmark.warmup=.04;self.content.benchmark.duration=.08
        self.start((ROOT/'items/performance-lab/game.lua').read_text('utf-8'))
        self.lua.execute('Mock.click("BGM测试")')
        self.advance(.2)
        records=[json.loads(line) for line in self.lua.globals().session.perf.export().splitlines()]
        phase=next(r['data'] for r in records if r['type']=='phase.end')
        self.assertEqual(phase['status'],'complete')
        self.assertEqual(phase['resources']['musicBackend'],'native')
        self.assertEqual(phase['resources']['musicChannel'],'SFX')
        self.assertEqual(phase['resources']['musicState'],'playing')

    def test_actor_bounds_record_is_separate_from_logical_collider(self):
        s=self.start('return function(ctx)return {onStart=function()ctx.world.spawn("scene_model",{x=200,y=60})end}end')
        self.advance(.05);records=s.ctx.assets.recordModels()
        self.assertEqual(records[1].backend,'scene_model');self.assertEqual(records[1].nativeBounds.top.z,2)
        self.assertEqual(records[1].collider.w,24)

    def native_package(self):
        fixture=ROOT/'.local-tools/AceSerializer-3.0.lua'
        if not fixture.exists() or 'local MAJOR,MINOR' not in fixture.read_text('utf-8'):
            self.skipTest('Native AceSerializer fixture missing; run tools/setup-tests.ps1')
        self.assertEqual(hashlib.sha256(fixture.read_bytes()).hexdigest(),'af2d55fd5ded8cca07608d20c40cc8aa776afbd417f936f5078c8b0054e713ff')
        self.lua.execute('LibStub={};function LibStub:NewLibrary(name,minor)self.library={};return self.library end')
        self.lua.execute(fixture.read_text('utf-8'))
        alphabet='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()'
        package_path=getattr(self,'package_path',ROOT/f'items/{self.item_dir}/dist/item.t3e.txt')
        text=package_path.read_text('utf-8').strip()[1:]
        bits=value=0;compressed=bytearray()
        for c in text:
            value|=alphabet.index(c)<<bits;bits+=6
            while bits>=8:
                compressed.append(value&255);value>>=8;bits-=8
        raw=zlib.decompress(bytes(compressed),-15).decode('utf-8').replace('||','|')
        success,decoded=self.lua.globals().LibStub.library.Deserialize(self.lua.globals().LibStub.library,raw)
        self.assertTrue(success);self.assertEqual(decoded[2],self.manifest.rootId)
        return decoded[3]

    def test_native_ace_deserializer_accepts_export_and_key_types(self):
        root=self.native_package()
        self.assertEqual(root.MD.CB,'斯提芬丶九二-金色平原')
        self.assertIsNotNone(root.SC.onUse.ST['1']);self.assertIsNone(root.SC.onUse.ST[1])
        self.assertEqual(root.IN.ig_game.PA[1].TX[0],'{')

    def native_startup(self):
        root=self.native_package();self.lua.globals().root=root
        self.lua.execute(r'''
Mock.classes[manifest.rootId]=root
TRP3_API.globals.empty={}
TRP3_API.extended.ID_SEPARATOR=" "
TRP3_API.utils.table={copy=function(a,b)for k,v in pairs(b)do a[k]=v end end}
TRP3_API.register={isUnitIDKnown=function()return false end,getUnitIDCurrentProfile=function()return nil end}
TRP3_API.loc=setmetatable({},{__index=function(t,k)return k end})
TRP3_API.Log=function()end
TRP3_API.security.SECURITY_LEVEL={LOW=1,MEDIUM=2,HIGH=3}
TRP3_DB={inner={},types={ITEM="IT",DOCUMENT="DO",CAMPAIGN="CA"}}
function wipe(t)for k in pairs(t)do t[k]=nil end end
function strsplit(separator,text)local t={};for part in text:gmatch("[^"..separator.."]+")do t[#t+1]=part end;return unpack(t)end
Mock.private={}
''')
        source=(ROOT/'references/total-rp-3-extended/totalRP3_Extended/Script/ScriptGeneration.lua').read_text('utf-8')
        self.lua.execute(source)
        enclave=(ROOT/'references/total-rp-3-extended/totalRP3_Extended/Script/SecuredMacroCommandsEnclave.lua').read_text('utf-8')
        self.lua.execute(enclave,'totalRP3_Extended',self.lua.globals().Mock.private)
        self.lua.execute(r'''
Mock.enclave=Mock.private.SecuredMacroCommandsEnclave
local effects={
 script={secured=1,method=function(_,c,x)TRP3_API.script.runLuaScriptEffect(c[1],x,false)end,
     securedMethod=function(_,c,x)TRP3_API.script.runLuaScriptEffect(c[1],x,true)end},
 secure_macro={secured=1,method=function(_,c,x)Mock.enclave:AddSecureCommands(TRP3_API.script.parseArgs(c[1],x))end,
     securedMethod=function()Mock.messages[#Mock.messages+1]="macro blocked"end},
 text={secured=3,method=function(_,c)Mock.messages[#Mock.messages+1]=tostring(c[1])end},
 document_show={secured=3,method=function(_,c)Mock.document=c[1]end},
}
TRP3_API.script.getEffect=function(id)return effects[id]end
Mock.originalExecutor=TRP3_API.script.runLuaScriptEffect
function Mock.prepareUse()
 Mock.enclave:StartCollectingSecureCommands()
 TRP3_API.script.executeClassScript("onUse",root.SC,{object=item,container=Mock.inventory},manifest.rootId)
 local command=Mock.enclave:GetSecureCommands()
 return command
end
function Mock.executeMacro(command)
 assert(#command:gsub("\n$", "")<=255)
 Mock.secureClick=true
 local ok,err=pcall(assert(loadstring(command:sub(6))))
 Mock.secureClick=false
 assert(ok,err)
end
''')
        return root

    def test_generated_click_uses_native_delay_and_restores_injector(self):
        self.native_startup()
        command=self.lua.globals().Mock.prepareUse()
        self.lua.execute('assert(TRP3_ItemGame==nil);assert(TRP3_API.script.runLuaScriptEffect==Mock.originalExecutor)')
        self.lua.globals().Mock.executeMacro(command)
        self.lua.globals().Mock.executeMacro(command)  # protected down/up can execute the same macro twice
        self.lua.execute('assert(TRP3_ItemGame==nil);assert(TRP3_API.script.runLuaScriptEffect~=Mock.originalExecutor)')
        self.lua.execute('foreign={classID="another-item"};TRP3_API.script.runLuaScriptEffect("args.received=args._G",foreign,false);assert(foreign.received==nil)')
        self.advance(.09);self.lua.execute('assert(TRP3_ItemGame==nil)')
        self.advance(.02)
        self.lua.execute('assert(TRP3_ItemGame.current);assert(TRP3_API.script.runLuaScriptEffect==Mock.originalExecutor);assert(item.vars.IG_BOOT_STATUS_V1:find("3/3",1,true))')
        self.lua.execute('TRP3_API.script.executeClassScript("wf_stop",root.SC,{object=item,container=Mock.inventory},manifest.rootId)')
        self.advance(.3);self.lua.execute('assert(TRP3_ItemGame.current==nil);assert(TRP3_API.script.runLuaScriptEffect==Mock.originalExecutor)')

    def test_missing_macro_gives_visible_injection_failure(self):
        self.native_startup();self.lua.globals().Mock.prepareUse()
        self.advance(.11)
        self.lua.execute('assert(TRP3_ItemGame==nil);assert(item.vars.IG_BOOT_STATUS_V1:find("INJECTION",1,true));assert(#Mock.messages>=2)')

    def test_native_package_escape_closes_after_macro_delay(self):
        self.native_startup()
        self.lua.globals().Mock.executeMacro(self.lua.globals().Mock.prepareUse())
        self.advance(.2)
        self.lua.execute('''
local active=TRP3_ItemGame.current
assert(active and active.view.frame:IsShown())
Mock.pressEscape()
assert(not active.view.frame:IsShown());assert(active.closed);assert(TRP3_ItemGame.current==nil)
assert(TRP3_API.script.runLuaScriptEffect==Mock.originalExecutor)
''')

    def test_native_package_launch_after_editor_save_remains_open(self):
        self.native_startup()
        self.lua.execute('root.MD.V=root.MD.V+1')
        self.lua.globals().Mock.executeMacro(self.lua.globals().Mock.prepareUse())
        self.advance(.7)
        self.lua.execute('''
local active=TRP3_ItemGame.current
assert(active and not active.stopping);assert(active.view.frame:IsShown())
assert(active.host.definitionVersion==root.MD.V)
assert(item.vars.IG_BOOT_STATUS_V1:find("3/3",1,true))
root.MD.V=root.MD.V+1;Mock.fireTRP("ON_OBJECT_UPDATED")
assert(active.closed);assert(TRP3_ItemGame.current==nil)
''')

    def test_injector_timeout_preserves_other_wrapper_and_is_inert(self):
        root=self.native_startup();macro=root.SC.onUse.ST['1'].e[1].args[1]
        self.lua.globals().Mock.executeMacro(macro)
        self.advance(2.1);self.lua.execute('assert(TRP3_API.script.runLuaScriptEffect==Mock.originalExecutor)')
        self.lua.globals().Mock.executeMacro(macro)
        self.lua.execute('Mock.injector=TRP3_API.script.runLuaScriptEffect;Mock.outer=function(...)return Mock.injector(...)end;TRP3_API.script.runLuaScriptEffect=Mock.outer')
        self.advance(2.1)
        self.lua.execute('assert(TRP3_API.script.runLuaScriptEffect==Mock.outer);probe={classID=manifest.rootId};Mock.injector("args.received=args._G",probe,false);assert(not probe.received)')

    def test_injector_does_not_elevate_secured_script(self):
        root=self.native_startup();self.lua.globals().Mock.executeMacro(root.SC.onUse.ST['1'].e[1].args[1])
        self.lua.execute('probe={classID=manifest.rootId};TRP3_API.script.runLuaScriptEffect("args.received=args._G",probe,true);assert(not probe.received);assert(TRP3_API.script.runLuaScriptEffect==Mock.originalExecutor)')

if __name__=='__main__':
    unittest.main(verbosity=2)
