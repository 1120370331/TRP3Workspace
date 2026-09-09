"""CPU comparison using actual Lua and the mock WoW adapter; never native FPS.

36 deterministic Y-layer angles per order, first six warmup frames excluded.
The setter counter intentionally wraps the mock's native property methods.
"""
import sys,json,statistics,hashlib,argparse
from pathlib import Path
root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'items/arcane-cube/tests'))
from harness import CubeHarness
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--adapter-bundle',type=Path,help='Use only the view3d module from a trusted development bundle, keeping the current game and geometry identical.')
args=parser.parse_args()
adapter=(root/'framework/item-game/view3d.lua').read_text(encoding='utf-8')
if args.adapter_bundle:
 bundle=args.adapter_bundle.read_text(encoding='utf-8')
 adapter=bundle.split('-- module: view3d\ndo local install=(function()\n',1)[1].split('\nend)();install(E,G) end',1)[0]
out=[]
for n in [3,4,5,7]:
 h=CubeHarness();h.setUp()
 h.lua.execute('(function()\n'+adapter+'\nend)()(E,_G)');h.boot()
 if n!=3:h.click('order'+str(n));h.advance(.02)
 initial=h.serial(h.lua.execute('''
 local frames={};local textures=0
 for _,h in ipairs(session.scene3d.cache.pool)do if h.texture:IsShown()then frames[h.frame]=true;textures=textures+1 end end
 local count=0;for _ in pairs(frames)do count=count+1 end
 return {nativeFrames=count,visibleTextures=textures}
 '''))
 h.click('turn-plus')
 h.lua.execute('''
 local mt=getmetatable(session.scene3d.cache.root).__index
 Mock.setterCalls=0;Mock.callsByMethod={}
 for _,name in ipairs({'ClearAllPoints','SetPoint','SetSize','SetFrameLevel','SetVertexOffset','SetVertexColor','SetTexCoord','SetTexture','SetBlendMode','SetParent','Show','Hide','SetScale'})do
  local original=mt[name];mt[name]=function(self,...)Mock.setterCalls=Mock.setterCalls+1;Mock.callsByMethod[name]=(Mock.callsByMethod[name] or 0)+1;return original(self,...)end
 end
 function benchmarkFrame(angle)
  local scene=session.scene3d;scene.setTransform('turn',{rotation=E.math3d.vec(0,angle,0)})
  local start=os.clock();scene.renderList();local projected=os.clock();scene.render(1);local finish=os.clock()
  return (projected-start)*1000,(finish-projected)*1000
 end
 ''')
 projection=[];draw=[]
 for i in range(36):
  p,d=h.lua.globals().benchmarkFrame((i+1)/36*1.5)
  if i>=6:projection.append(p);draw.append(d)
 out.append(dict(order=n,initial=initial,projectMeanMs=statistics.mean(projection),drawMeanMs=statistics.mean(draw),combinedP95Ms=sorted([p+d for p,d in zip(projection,draw)])[28],setterCalls=h.lua.globals().Mock.setterCalls,callsByMethod=h.serial(h.lua.globals().Mock.callsByMethod),resources=h.serial(h.lua.globals().session.scene3d.stats())))
sources={name:hashlib.sha256((root/'framework/item-game'/name).read_text(encoding='utf-8').encode()).hexdigest() for name in ['math3d.lua','scene3d.lua','view3d.lua','particles3d.lua']}
sources['view3d.lua']=hashlib.sha256(adapter.encode()).hexdigest()
print(json.dumps({'environment':'Lua 5.1 mock host; CPU comparison, not WoW FPS','adapterBundle':str(args.adapter_bundle) if args.adapter_bundle else None,'frames':36,'warmupFrames':6,'setterCountFrames':36,'sourceFiles':sources,'scenarios':out},indent=2))
