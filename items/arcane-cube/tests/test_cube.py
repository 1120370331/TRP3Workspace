"""Permutation, persistence and real Lua UI-path regressions; no WoW perf claims."""
import unittest
from harness import CubeHarness, ROOT


class CubeTests(CubeHarness):
    def test_surface_pulse_submits_only_color_changes_to_native_textures(self):
        self.boot()
        self.lua.execute('''
local scene=session.scene3d
scene.effects.set("cubie_1_3_3",{color={.2,.8,1},pulse=.3,speed=1,rim=.5})
scene.render(1);local count=scene.stats().scene3DPooledQuads
local mt=getmetatable(scene.cache.root).__index;local vertices,colors=0,0
local originalVertex,originalColor=mt.SetVertexOffset,mt.SetVertexColor
mt.SetVertexOffset=function(self,...)vertices=vertices+1;return originalVertex(self,...)end
mt.SetVertexColor=function(self,...)colors=colors+1;return originalColor(self,...)end
scene.step(.1);scene.render(1)
assert(colors>0 and vertices==0,"pulse must not re-submit geometry")
assert(scene.stats().scene3DProjectedVertices==0 and scene.stats().scene3DPooledQuads==count)
''')

    def test_material_motion_effects_and_fixed_benchmark_restore_game(self):
        self.boot();before=self.serial(self.state())
        self.click('materials');self.click('mat-effects');self.click('mat-motion');self.advance(2)
        self.lua.execute('''
assert(session.scene3d.get("material_group").position.x>5)
assert(session.scene3d.stats().scene3DCulledNodes>0)
assert(session.scene3d.particles.stats().particles3D>0)
''')
        self.click('mat-motion');self.advance(.2)
        self.assertNotEqual(self.lua.eval('session.scene3d.getCamera().target.x'),0)
        self.click('materials');after=self.serial(self.state())
        for key in ['n','history','moves','elapsed','yaw','pitch','distance','skin']:
            self.assertEqual(after[key],before[key])
        self.lua.execute('''
assert(session.scene3d.particles.stats().particles3D==0)
assert(session.scene3d.particles.getRenderPolicy().adaptive)
''')
        self.click('fireworks');self.click('fx-benchmark')
        self.assertFalse(self.lua.eval('session.scene3d.particles.getRenderPolicy().adaptive'))
        self.click('fx-stop')
        self.assertTrue(self.lua.eval('session.scene3d.particles.getRenderPolicy().adaptive'))

    def test_native_texture_batches_preserve_corners_and_reduce_frames(self):
        self.boot();self.advance(.03)
        self.lua.execute('''
local scene=session.scene3d;local expected={}
for _,face in ipairs(scene.renderList())do expected[face.key]=face end
local frames={};local textures=0
for _,h in ipairs(scene.cache.pool)do if h.texture:IsShown() then
 local f=assert(expected[h.drawKey]);frames[h.frame]=true;textures=textures+1
 local x,y=h.texture.point[4],-h.texture.point[5];local w,ht=h.texture.width,h.texture.height;local v=h.texture.vertices
 local actual={{x+v[1][1],y-v[1][2]},{x+w+v[3][1],y-v[3][2]},
  {x+w+v[4][1],y+ht-v[4][2]},{x+v[2][1],y+ht-v[2][2]}}
 for i,p in ipairs(f.points)do assert(math.abs(p.x-actual[i][1])<1e-8 and math.abs(p.y-actual[i][2])<1e-8,"batched native anchor drift")end
end end
local count=0;for _ in pairs(frames)do count=count+1 end
assert(count==scene.stats().scene3DNativeFrames and count<textures/4)
''')
        self.click('materials');self.advance(.03)
        self.assertLess(self.lua.eval('session.scene3d.stats().scene3DNativeFrames'),20)
        self.click('materials');self.click('skin');self.advance(.03)
        self.lua.execute('''
local count=0;for _,h in ipairs(session.scene3d.cache.pool)do if h.texture:IsShown()then count=count+1 end end
assert(count==session.scene3d.stats().scene3DDraws,"hidden textures leaked through a reused batch frame")
''')

    def test_additive_runs_batch_and_release_without_ghost_textures(self):
        self.boot()
        self.lua.execute('session.scene3d.particles.burst("peony",{position={x=0,y=1,z=2},seed=42})')
        self.advance(.12)
        self.lua.execute('''
local s=session.scene3d.stats();assert(s.particles3DVisible>0)
assert(s.scene3DNativeFrames<s.scene3DDraws/2)
-- Native batch levels must preserve geometry/particle boundaries in the
-- painter list, even when additive particles could otherwise share a frame.
local scene=session.scene3d;scene.render(1);local handles={}
for _,h in ipairs(scene.cache.pool)do if h.texture:IsShown()then handles[h.drawKey]=h end end
local faces={}
for _,f in ipairs(scene.renderList())do faces[#faces+1]=f end
for _,f in ipairs(scene.particles.renderList(1,4096-s.scene3DDraws+s.particles3DVisible))do faces[#faces+1]=f end
table.sort(faces,function(a,b)
 if math.abs(a.depth-b.depth)<1e-8 and a.order and b.order then return a.order<b.order end
 return a.depth>b.depth
end)
local previous,level=nil,-1
for _,f in ipairs(faces)do
 local h=assert(handles[f.key]);local nextLevel=h.frame:GetFrameLevel()
 assert(nextLevel>=level,"batch changed painter depth order")
 if previous and nextLevel==level then
  assert((f.blend=="ADD" and previous.blend=="ADD") or
   (not f.blend and not previous.blend and f.id==previous.id and f.sourceFace==previous.sourceFace),"batch crossed a geometry boundary")
 end
 previous,level=f,nextLevel
end
session.scene3d.particles.clear()
''')
        self.advance(.03)
        self.lua.execute('''
for _,h in ipairs(session.scene3d.cache.pool)do if h.texture:IsShown()then assert(h.texture.blend=="BLEND")end end
assert(session.scene3d.stats().scene3DNativeFrames==132)
session.stop("batch_cleanup")
for _,h in ipairs(session.scene3d.cache.pool)do assert(not h.texture:IsShown())end
for _,b in ipairs(session.scene3d.cache.frames)do assert(not b.frame:IsShown())end
''')

    def test_default_skin_covers_each_actual_cube_face_once_at_every_order(self):
        self.boot()
        for order in range(2,8):
            self.click('order'+str(order));self.advance(.02)
            self.assertEqual(self.state().skin,'tidal')
            self.lua.execute('''
local areas,counts={},{}
for _,node in ipairs(session.scene3d.order)do if node.id~="turn" then
 assert(node.paintMesh and node.pixelBindings,"skin missing on actual cubie")
 for index in pairs(node.pixelBindings)do
  local f=node.mesh.faces[index];local uv=f.uv
  local area=math.abs((uv[2].u-uv[1].u)*(uv[4].v-uv[1].v))
  areas[f.tag]=(areas[f.tag] or 0)+area;counts[f.tag]=(counts[f.tag] or 0)+1
 end
end end
for _,face in ipairs({"U","D","L","R","F","B"})do
 assert(math.abs(areas[face]-1)<1e-8,"face artwork is not covered exactly once")
 assert(counts[face]==snapshot().n^2)
end
assert(session.scene3d.stats().scene3DFaces<=4096 and session.scene3d.stats().scene3DDropped==0)
''')

    def test_skin_fragment_stays_on_cubie_during_turn_and_after_restore(self):
        self.boot()
        self.lua.execute('''
skinNode=session.scene3d.get("cubie_1_3_3");skinMesh=skinNode.paintMesh
skinUV=E.JSON.encode(skinNode.mesh.faces[8].uv)
skinPosition=session.scene3d.worldPoint(skinNode.id,skinMesh.vertices[1])
''')
        self.click('turn-plus');self.advance(.3)
        self.lua.execute('''
assert(skinNode.paintMesh==skinMesh,"a turn must transform the skin, not reassign it")
assert(E.JSON.encode(skinNode.mesh.faces[8].uv)==skinUV)
assert(E.math3d.length(E.math3d.sub(skinPosition,session.scene3d.worldPoint(skinNode.id,skinMesh.vertices[1])))>.1)
''')
        self.restart()
        self.lua.execute('assert(E.JSON.encode(session.scene3d.get("cubie_1_3_3").mesh.faces[8].uv)==skinUV)')
        self.assertEqual(self.state().skin,'tidal')

    def test_skin_choice_is_cosmetic_persistent_and_old_saves_get_tidal_default(self):
        self.boot();self.click('turn-plus');self.advance(.3);before=self.serial(self.state())
        self.click('skin');after=self.serial(self.state())
        self.assertEqual(after['skin'],'classic')
        for key in ['history','moves','elapsed','bests']:self.assertEqual(after[key],before[key])
        self.lua.execute('for _,n in ipairs(session.scene3d.order)do assert(not n.paintMesh)end')
        self.restart();self.assertEqual(self.state().skin,'classic')
        self.lua.execute('session.stop("old_save");local save=E.JSON.decode(item.vars.IG_SAVE_V1);save.game.skin=nil;item.vars.IG_SAVE_V1=E.JSON.encode(save)')
        self.boot();self.assertEqual(self.state().skin,'tidal')

    def test_pixel_subjects_switch_rotate_unbind_and_restore_cube_without_image_files(self):
        self.boot();self.click('turn-plus');self.advance(.3);before=self.serial(self.state())
        self.click('materials');self.advance(.05)
        self.assertEqual(self.lua.eval('session.scene3d.stats().scene3DNodes'),4)
        self.assertLess(self.lua.eval('session.scene3d.stats().scene3DFaces'),4096)
        self.click('mat-subject2');self.click('mat-texture6');self.click('mat-uv');self.click('mat-group')
        self.click('mat-spin');self.advance(.1);self.click('mat-spin')
        self.lua.execute('''
local n=session.scene3d.get("material_obelisk")
assert(n.pixelBindings[1].texture=="moon" and n.pixelBindings[1].rotation==1)
for _,h in ipairs(E.viewCache.scene3D.pool)do if h.texture:IsShown()then assert(h.texture.texture=="Interface\\\\Buttons\\\\WHITE8X8","pixel material requested an external image")end end
''')
        self.click('mat-clear');self.assertIsNone(self.lua.eval('session.scene3d.get("material_obelisk").paintMesh'))
        self.click('mat-six');self.click('materials')
        after=self.serial(self.state())
        self.assertEqual(after['history'],before['history']);self.assertEqual(after['elapsed'],before['elapsed'])
        self.assertEqual(after['yaw'],before['yaw']);self.assertEqual(self.lua.eval('session.scene3d.stats().scene3DNodes'),27)

    def test_closing_pixel_lab_preserves_canonical_cube_save(self):
        self.boot();self.click('scramble');before=self.serial(self.state());self.click('materials');self.restart()
        self.assertEqual(self.serial(self.state())['history'],before['history'])
        self.assertEqual(self.lua.eval('session.scene3d.stats().scene3DNodes'),27)

    def test_solved_reward_once_and_never_replays_on_load(self):
        self.boot();self.click('turn-plus');self.advance(.3);self.click('turn-minus');self.advance(1)
        self.assertGreater(self.lua.eval('session.scene3d.particles.stats().particles3DSpawned'),0)
        self.lua.execute('local n=0;for _,r in ipairs(session.perf.records)do if r.type=="fireworks.reward"then n=n+1 end end;assert(n==1)')
        self.restart();self.advance(.3)
        self.assertEqual(self.lua.eval('session.scene3d.particles.stats().particles3DSpawned'),0)
        self.assertTrue(self.state().won)

    def test_firework_preview_stop_pause_and_native_material_reuse(self):
        self.boot();self.click('fireworks');self.click('fx-preview');self.advance(.9)
        self.assertGreater(self.lua.eval('session.scene3d.particles.stats().particles3D'),0)
        self.lua.execute('''
local found=false
for _,h in ipairs(E.viewCache.scene3D.pool)do
 if h.texture:IsShown() and h.texture.blend=="ADD"then found=true;assert(h.texture.texture:find("star4",1,true))end
end
assert(found);savedParticles=E.JSON.encode(session.scene3d.particles.particles)
''')
        self.click('pause');self.advance(.5)
        self.lua.execute('assert(E.JSON.encode(session.scene3d.particles.particles)==savedParticles)')
        self.click('resume');self.click('fx-stop');self.advance(3)
        self.assertEqual(self.lua.eval('session.scene3d.particles.stats().particles3D'),0)
        self.lua.execute('for _,h in ipairs(E.viewCache.scene3D.pool)do if h.texture:IsShown()then assert(h.texture.blend=="BLEND")end end')

    def test_benchmark_produces_four_phases_and_preserves_puzzle(self):
        self.lua.execute('content.fireworksLab={duration=.8,warmup=.1}')
        self.boot();self.click('turn-plus');self.advance(.3);self.click('fireworks')
        before=self.serial(self.state());self.click('fx-benchmark');self.advance(2)
        self.assertEqual(self.state().elapsed,before['elapsed'])
        self.assertFalse(self.lua.globals().Mock.nodes['order4'].enabled)
        self.advance(2)
        self.assertEqual(self.serial(self.state())['history'],before['history'])
        self.lua.execute('''
local n=0
for _,r in ipairs(session.perf.records)do if r.type=="phase.end" and r.data.name:find("fireworks.",1,true)then
 n=n+1;assert(r.data.status=="complete" and r.data.metrics.frameMs.count>0)
 assert(r.data.resources.particles3DPeak~=nil)
end end
assert(n==4);assert(not session.ctx.perf.isRunning());assert(session.scene3d.particles.stats().particles3D==0)
assert(session.ctx.perf.snapshot().hostKind=="mock")
''')

    def test_imported_package_boots_in_real_trp3_script_sandbox(self):
        self.native_startup()
        command=self.lua.globals().Mock.prepareUse()
        self.lua.globals().Mock.executeMacro(command)
        self.advance(.15)
        self.lua.execute('''
local s=assert(TRP3_ItemGame.current,"packaged cube did not start")
assert(not s.stopping and s.scene3d.stats().scene3DDraws>0)
assert(s.callbacks.onSave().skin=="tidal" and s.scene3d.get("cubie_1_3_3").paintMesh)
assert(TRP3_API.script.runLuaScriptEffect==Mock.originalExecutor)
local f=s.view.frame;f:GetScript("OnKeyDown")(f,"J");f:GetScript("OnKeyUp")(f,"J")
''')
        self.advance(.3)
        self.lua.execute('''
local s=TRP3_ItemGame.current;assert(s.callbacks.onSave().moves==1)
local button
for _,f in ipairs(Mock.frames)do if f.text=="材质试验" and f.parent and f.parent.scripts.OnClick then button=f.parent;break end end
assert(button,"packaged material control missing");button:GetScript("OnClick")(button,"LeftButton")
assert(s.scene3d.stats().scene3DNodes==4 and s.scene3d.get("material_cube").paintMesh)
s.requestClose("window_closed");assert(TRP3_ItemGame.current==nil)
''')

    def test_all_orders_four_turns_and_random_inverse_preserve_exact_state(self):
        self.lua.globals().P = self.lua.execute((ROOT/'items/arcane-cube/src/puzzle.lua').read_text('utf-8'))
        self.lua.execute('''
for n=2,7 do
 local s=P.new(n);local before=E.JSON.encode(s)
 for _,axis in ipairs({"x","y","z"})do for layer=1,n do
  for i=1,4 do P.apply(s,{axis=axis,layer=layer,dir=1})end
  assert(E.JSON.encode(s)==before,"quarter-turn permutation drift")
 end end
 local moves=P.scramble(n,9157,250)
 for _,m in ipairs(moves)do P.apply(s,m)end
 assert(not P.isSolved(s))
 for _,c in ipairs(s.cubies)do
  local matrix=E.math3d.transform(nil,P.euler(c))
  for i,axis in ipairs({E.math3d.vec(1,0,0),E.math3d.vec(0,1,0),E.math3d.vec(0,0,1)})do
   local v=E.math3d.vector(matrix,axis)
   assert(E.math3d.length(E.math3d.sub(v,c.basis[i]))<1e-7,"visual orientation differs from permutation")
  end
 end
 for i=#moves,1,-1 do P.apply(s,P.inverse(moves[i]))end
 assert(E.JSON.encode(s)==before and P.isSolved(s),"scramble inverse failed")
end
''')

    def test_whole_cube_rotation_still_counts_as_solved(self):
        self.lua.globals().P = self.lua.execute((ROOT/'items/arcane-cube/src/puzzle.lua').read_text('utf-8'))
        self.lua.execute('for n=2,7 do local s=P.new(n);for i=1,n do P.apply(s,{axis="y",layer=i,dir=1})end;assert(P.isSolved(s))end')

    def test_inner_slice_turn_undo_and_restart_use_canonical_state(self):
        self.boot();self.click('order7');self.click('axisx');self.click('slice4');self.click('turn-plus');self.advance(.3)
        before=self.serial(self.state())
        self.assertEqual(before['history'], [{'axis':'x','layer':4,'dir':1,'source':'player'}])
        self.assertEqual(self.lua.eval('session.scene3d.stats().scene3DNodes'),219)
        self.assertEqual(self.lua.eval('session.scene3d.stats().scene3DDropped'),0)
        self.restart();self.assertEqual(self.serial(self.state())['history'],before['history'])
        self.click('undo');self.advance(.3)
        self.assertEqual(len(self.state().history),0);self.assertTrue(self.state().assisted)

    def test_pause_freezes_timer_and_turn_and_releases_drag(self):
        self.boot();self.click('turn-plus');self.advance(.06);self.click('pause')
        before=self.state().elapsed;rotation=self.lua.eval('session.scene3d.get("turn").rotation.y')
        self.advance(3)
        self.assertEqual(self.state().elapsed,before)
        self.assertEqual(self.lua.eval('session.scene3d.get("turn").rotation.y'),rotation)
        self.click('resume');self.advance(.3)
        self.assertEqual(len(self.state().history),1)
        self.assertLess(self.state().elapsed,1)

    def test_scramble_player_move_and_replay_restore_solved(self):
        self.boot();self.click('scramble');self.assertGreater(len(self.state().history),20)
        self.assertEqual(self.state().elapsed,0)
        self.click('turn-minus');self.advance(.3)
        self.assertEqual(self.state().moves,1)
        self.click('replay');self.advance(8)
        self.assertEqual(len(self.state().history),0)
        self.assertTrue(self.state().won);self.assertTrue(self.state().assisted)
        self.assertEqual(self.serial(self.state())['bests'],{})

    def test_close_mid_animation_restores_last_complete_turn_and_pool_is_reused(self):
        self.boot();self.click('turn-plus');self.advance(.04)
        self.assertEqual(len(self.state().history),0)
        self.restart();self.assertEqual(len(self.state().history),0)
        self.advance(.2);pool=self.lua.eval('#E.viewCache.scene3D.pool')
        self.restart();self.assertEqual(self.lua.eval('#E.viewCache.scene3D.pool'),pool)
        self.lua.execute('oldScene=session.scene3d;session.stop("close");assert(oldScene.closed and not oldScene.inputFrame:IsMouseEnabled());assert(not E.viewCache.scene3D.root:IsShown());assert(oldScene.inputFrame:GetScript("OnMouseDown")==nil)')

    def test_pointer_ray_selection_orbit_zoom_and_drag_turn(self):
        self.boot()
        self.lua.execute('''
local scene=session.scene3d
local hit=assert(scene.pick(350,310));assert(hit.id:find("cubie_"))
pointer("down",350,310,"LeftButton");pointer("up",350,310,"LeftButton")
local before=snapshot().yaw
pointer("down",350,310,"RightButton");pointer("move",410,330,"RightButton");pointer("up",410,330,"RightButton")
assert(snapshot().yaw~=before)
local distance=snapshot().distance;pointer("wheel",350,310,"",1);assert(snapshot().distance<distance)
pointer("down",350,310,"LeftButton");pointer("move",415,310,"LeftButton");pointer("up",415,310,"LeftButton")
''')
        self.advance(.3);self.assertEqual(self.state().moves,1)

    def test_new_game_confirmation_can_cancel_without_losing_state(self):
        self.boot();self.click('turn-plus');self.advance(.3)
        self.click('order5');self.click('confirm-no');self.assertEqual(self.state().n,3);self.assertEqual(len(self.state().history),1)
        self.click('order5');self.click('confirm-yes');self.assertEqual(self.state().n,5);self.assertEqual(len(self.state().history),0)

    def test_leaving_solved_state_clears_success_message(self):
        self.boot();self.click('turn-plus');self.advance(.3);self.click('turn-minus');self.advance(.3)
        self.assertTrue(self.state().won)
        self.click('turn-plus');self.advance(.3)
        self.assertFalse(self.state().won)
        self.assertNotIn('完成', self.lua.globals().Mock.nodes['status'].previewSpec.text)

    def test_bad_saved_move_does_not_overwrite_previous_data(self):
        self.boot();self.lua.execute('session.stop("seed");local save=E.JSON.decode(item.vars.IG_SAVE_V1);save.game.history={{axis="x",layer=999,dir=1,source="player"}};item.vars.IG_SAVE_V1=E.JSON.encode(save);oldRaw=item.vars.IG_SAVE_V1')
        host=self.E.newWoWHost(self.lua.globals().args,self.manifest)
        result=self.E.start(host,self.manifest,self.content)
        self.assertIsInstance(result,tuple)
        self.assertEqual(self.lua.globals().item.vars.IG_SAVE_V1,self.lua.globals().oldRaw)

    def test_unassisted_completion_records_best_through_real_turn(self):
        self.boot();self.lua.execute('''
session.stop("fixture");local save=E.JSON.decode(item.vars.IG_SAVE_V1)
save.game.history={{axis="y",layer=3,dir=1,source="scramble"}}
save.game.challenge=true;save.game.started=false;save.game.assisted=false
item.vars.IG_SAVE_V1=E.JSON.encode(save)
''')
        self.boot();self.click('turn-minus');self.advance(.3)
        self.assertTrue(self.state().won)
        self.assertEqual(self.state().bests['3'].moves,1)

if __name__=='__main__':
    unittest.main(verbosity=2)
