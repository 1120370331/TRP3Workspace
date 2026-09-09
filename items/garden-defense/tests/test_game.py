"""Risk-focused garden tests against the real Lua game + engine (mock WoW APIs)."""
from pathlib import Path
import importlib.util
import json
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('engine_checks', ROOT / 'tools/test-engine.py')
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)


class GardenTests(engine.EngineTests):
    item_dir = 'garden-defense'

    def boot(self):
        project = ROOT / 'items' / self.item_dir
        manifest = json.loads((project/'item.json').read_text('utf-8'))
        parts = ['local gameModules={}']
        for name, path in sorted(manifest.get('modules', {}).items()):
            parts.append('gameModules['+json.dumps(name)+']=(function()\n'+(project/path).read_text('utf-8')+'\nend)()')
        parts.append('local factory=(function()\n'+(project/'game.lua').read_text('utf-8')+'\nend)()')
        parts.append('return function(ctx)return factory(ctx,gameModules)end')
        self.start('\n'.join(parts))
        self.lua.execute('''
Mock.nodes={}
local surface=session.view.gameSurface
local draw=surface.draw
surface.draw=function(id,spec)local node=draw(id,spec);Mock.nodes[id]=node;return node end
function clickNode(id,button)
 local node=Mock.nodes[id]
 assert(node and node.object:IsShown(),"node not visible: "..id)
 assert(node.enabled,"node disabled: "..id)
 node.object:GetScript("OnClick")(node.object,button or "LeftButton")
 assert(not session.stopping, "game stopped: "..tostring(Mock.messages[#Mock.messages]))
end
function snapshot()return session.callbacks.onSave()end
''')
        self.advance(.11)

    def click(self, key):
        self.lua.globals().clickNode(key)

    def state(self):
        return self.lua.globals().snapshot()

    def restart(self):
        self.lua.execute('session.stop("test_close")')
        self.boot()

    def fresh(self, level=1):
        self.boot()
        self.click('create1')
        if level > 1:
            state = self.state()
            state.slots['1'].cleared = level - 1
            self.lua.globals().seeded = state
            self.lua.execute('''session.stop("seed");local save=E.JSON.decode(item.vars.IG_SAVE_V1);save.game=seeded;item.vars.IG_SAVE_V1=E.JSON.encode(save)''')
            self.boot()
            self.click('load1')
        self.click(f'level{level}')

    def inject(self, code):
        # Controlled test fixture, never used by shipped gameplay.
        self.lua.execute('seeded=snapshot();r=seeded.slots["1"].run;' + code)
        self.lua.execute('session.stop("fixture");local save=E.JSON.decode(item.vars.IG_SAVE_V1);save.game=seeded;item.vars.IG_SAVE_V1=E.JSON.encode(save)')
        self.boot(); self.click('load1'); self.click('resume')

    def test_garden_profile_transactions_and_resume(self):
        self.fresh()
        self.click('cell19')  # row 3, col 1
        self.advance(7)
        before=self.state().slots['1'].run
        self.assertEqual(before.sun, 50)
        self.assertIsNotNone(before.plants['19'])
        self.restart();self.click('load1')
        after=self.state().slots['1'].run
        self.assertEqual(after.time,before.time)
        self.assertEqual(after.nextSky,before.nextSky)
        self.assertEqual(after.cooldowns.pea,before.cooldowns.pea)
        self.advance(2);self.assertEqual(self.state().slots['1'].run.time,after.time)
        self.click('resume');self.click('profiles');self.click('create2')
        self.assertEqual(self.state().slots['2'].cleared,0)
        self.assertEqual(self.state().slots['1'].run.time,after.time)
        self.click('profiles');self.click('delete1');self.click('confirmNo')
        self.assertIsNotNone(self.state().slots['1'])
        self.click('delete1');self.click('confirmYes');self.restart()
        self.assertIsNone(self.state().slots['1'])
        self.assertIsNotNone(self.state().slots['2'])

    def test_garden_write_failure_rolls_back_create_and_delete(self):
        self.boot();self.lua.execute('Mock.failWriteKey="IG_SAVE_V1"')
        self.click('create1');self.assertIsNone(self.state().slots['1'])
        self.lua.execute('Mock.failWriteKey=nil');self.click('create1');self.click('profiles')
        self.lua.execute('Mock.failWriteKey="IG_SAVE_V1"')
        self.click('delete1');self.click('confirmYes');self.assertIsNotNone(self.state().slots['1'])
        self.lua.execute('Mock.failWriteKey=nil');self.restart();self.assertIsNotNone(self.state().slots['1'])

    def test_garden_malformed_game_save_is_preserved(self):
        self.fresh();self.lua.execute('session.stop("close");local save=E.JSON.decode(item.vars.IG_SAVE_V1);save.game.slots["1"].run.zombies={{kind="bad"}};item.vars.IG_SAVE_V1=E.JSON.encode(save);oldRaw=item.vars.IG_SAVE_V1')
        result=self.E.start(self.E.newWoWHost(self.lua.globals().args,self.manifest),self.manifest,self.content)
        self.assertIsInstance(result,tuple)
        self.assertEqual(self.lua.globals().oldRaw,self.lua.globals().item.vars.IG_SAVE_V1)

    def test_garden_map_lock_cost_cooldown_and_shovel(self):
        self.fresh()
        self.click('seed2');self.click('cell19')
        self.assertEqual(self.state().slots['1'].run.plants['19'].kind,'pea')
        self.click('cell20');self.assertIsNone(self.state().slots['1'].run.plants['20'])
        self.click('cell19');self.assertEqual(self.state().slots['1'].run.sun,50)
        self.click('shovel');self.click('cell19')
        self.assertIsNone(self.state().slots['1'].run.plants['19'])
        self.assertEqual(self.state().slots['1'].run.sun,50)
        self.click('map')
        self.assertFalse(self.lua.globals().Mock.nodes['level2'].enabled)

    def test_garden_all_plants_and_enemy_specials(self):
        self.fresh(10)
        self.inject('''r.sun=9990;r.nextWave=10000;r.nextSky=10000
for i,p in ipairs(content.plants)do
 local row=i<=5 and 1 or 3;local col=((i-1)%5)+1
 r.plants[tostring((row-1)*9+col)]={kind=p.id,row=row,col=col,hp=p.hp,age=0,timer=0}
end
r.zombies={{kind="bucket",row=1,x=355,hp=1100,slow=0,jumped=false},{kind="pole",row=3,x=278,hp=340,slow=0,jumped=false},
{kind="basic",row=3,x=555,hp=200,slow=0,jumped=false}}''')
        self.advance(2)
        r=self.state().slots['1'].run
        self.assertIsNone(r.plants['3'])  # cherry fused and exploded
        self.assertGreaterEqual(r.kills,1)
        self.assertGreater(len(list(r.suns.values())),0)
        self.assertGreater(r.plants['20'].timer,0)  # chomper ate the pole
        self.assertGreater(len(list(r.bullets.values())),0)
        self.inject('''r.plants={};r.zombies={{kind="pole",row=2,x=200,hp=340,slow=0,jumped=false},{kind="paper",row=4,x=700,hp=170,slow=0,jumped=false}}
r.plants["10"]={kind="wall",row=2,col=1,hp=4000,age=0,timer=0};r.bullets={};r.nextWave=10000''')
        self.advance(.2);r=self.state().slots['1'].run
        self.assertTrue(r.zombies[1].jumped);self.assertLess(r.zombies[1].x,150)
        self.assertLess(r.zombies[2].x,696)

    def test_garden_snow_mine_night_production(self):
        self.fresh(10)
        self.inject('''r.nextWave=10000;r.plants={};r.suns={};r.sun=0
r.plants["1"]={kind="sunshroom",row=1,col=1,hp=300,age=89,timer=2}
r.plants["10"]={kind="snow",row=2,col=1,hp=300,age=0,timer=0}
r.plants["19"]={kind="mine",row=3,col=1,hp=300,age=11.5,timer=0}
r.zombies={{kind="basic",row=2,x=300,hp=200,slow=0,jumped=false},{kind="bucket",row=3,x=198,hp=1100,slow=0,jumped=false}}''')
        self.advance(3);r=self.state().slots['1'].run
        self.assertEqual(len(list(r.zombies.values())),1)
        self.assertGreater(r.zombies[1].slow,0)
        self.assertIsNone(r.plants['19'])
        self.assertEqual(len(list(r.suns.values())),1)
        self.assertEqual(r.suns[1].value,25)
        self.click('collectAll');self.assertEqual(self.state().slots['1'].run.sun,25)

    def test_garden_mower_loss_reward_and_unlock_once(self):
        self.fresh()
        self.inject('''r.nextWave=10000;r.zombies={{kind="basic",row=3,x=109,hp=200,slow=0,jumped=false}}''')
        self.advance(.4);r=self.state().slots['1'].run
        self.assertEqual(r.kills,1);self.assertGreater(r.mowers[3],108)
        self.inject('''r.mowers[3]=-1;r.zombies={{kind="basic",row=3,x=81,hp=200,slow=0,jumped=false}}''')
        self.advance(.3);self.assertEqual(self.state().slots['1'].run.status,'lost')
        self.restart();self.click('load1');self.click('resultNext')
        self.inject('''r.wave=3;r.spawnIndex=5;r.nextWave=0;r.zombies={}''')
        self.advance(.1);s=self.state().slots['1']
        self.assertEqual(s.cleared,1);self.assertEqual(s.coins,125)
        self.restart();self.click('load1');self.assertEqual(self.state().slots['1'].coins,125)
        self.click('resultNext');self.assertEqual(self.state().slots['1'].run.level,2)

    def test_garden_native_package_click_and_pool_reuse(self):
        self.native_startup()
        self.lua.globals().Mock.executeMacro(self.lua.globals().Mock.prepareUse())
        self.advance(.2)
        self.lua.execute('assert(TRP3_ItemGame.current and not TRP3_ItemGame.current.stopping);session=TRP3_ItemGame.current')
        self.assertIsNotNone(self.lua.globals().session.view.gameSurface)
        self.E=self.lua.globals().TRP3_ItemGame
        self.boot()  # same item returns the already started session
        self.click('create1');self.click('level1');self.click('cell19')
        self.advance(1);self.restart();self.click('load1');self.click('resume')
        first=len(list(self.lua.globals().Mock.frames.values()))
        self.restart();self.click('load1');self.click('resume')
        second=len(list(self.lua.globals().Mock.frames.values()))
        self.assertLessEqual(second-first,3)  # only the session event frame may be new


if __name__=='__main__':
    suite=unittest.TestSuite(GardenTests(name) for name in GardenTests.__dict__ if name.startswith('test_garden_'))
    result=unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(not result.wasSuccessful())
