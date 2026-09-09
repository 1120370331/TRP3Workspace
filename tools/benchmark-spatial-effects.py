"""Deterministic Lua comparisons for offscreen motion and saturated particles.

The fixed baseline contributes only scene3d/particles3d. No WoW FPS claims.
"""
from pathlib import Path
import argparse
import hashlib
import json
import statistics
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.local-tools/python'))
from lupa.lua51 import LuaRuntime

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--frames',type=int,default=60)
args=parser.parse_args()
assert 10<=args.frames<=600
baseline=ROOT/'items/arcane-cube/candidates/native-batched-skin/engine.generated.lua'
bundle=baseline.read_text('utf-8')

def module(name,old):
    if old and name in ('scene3d','particles3d'):
        return bundle.split('-- module: '+name+'\ndo local install=(function()\n',1)[1].split('\nend)();install(E,G) end',1)[0]
    return (ROOT/'framework/item-game'/f'{name}.lua').read_text('utf-8')

def runtime(old):
    lua=LuaRuntime(unpack_returned_tuples=True);lua.execute('E={}')
    for name in ['core','math3d','pixel-materials','scene3d','particles3d']:
        lua.execute(module(name,old))(lua.globals().E,lua.globals())
    return lua

def measure(lua,fn):
    samples=[];checks=[];painted=projected=0
    for i in range(args.frames):
        milliseconds,checksum,p,v=fn(i)
        if i>=6:samples.append(milliseconds)
        checks.append(checksum);painted+=p;projected+=v
    return dict(meanMs=statistics.mean(samples),p95Ms=sorted(samples)[int((len(samples)-1)*.95)],
                trajectoryHash=hashlib.sha256('|'.join(checks).encode()).hexdigest(),
                transformedSkinVertices=painted,projectedNodes=projected)

report={'environment':'Lua 5.1; no WoW host, native layout or GPU timing',
        'baseline':str(baseline.relative_to(ROOT)),'frames':args.frames,'warmupFrames':6,'versions':{}}
for old,label in [(True,'before'),(False,'after')]:
    lua=runtime(old)
    lua.execute('''
M=E.math3d;s=E.newScene3D({width=400,height=300})
s.definePixelTexture("grid",{width=4,height=4,codec="rle4",palette={"FF0000","00FF00"},data="0404404004044040"})
for i=1,32 do
 local n=s.create("box"..i,{mesh=E.boxMesh(),position=M.vec((i-1)%8*1.5-5.25,math.floor((i-1)/8)*1.5-2.25,0),velocity=M.vec(.1,0,0)})
 assert(s.setPixelMaterials(n.id,{default="grid"}))
end
function motionFrame(i)
 local target=M.vec(40*math.sin(i*.09),0,0)
 local start=os.clock();s.setCamera({position=M.add(target,M.vec(0,0,8)),target=target});s.step(1/60)
 local faces=s.renderList();local ms=(os.clock()-start)*1000
 local signature={}
 for _,f in ipairs(faces)do
  signature[#signature+1]=f.key
  for _,channel in ipairs(f.color)do signature[#signature+1]=string.format("%.7f",channel)end
  for _,p in ipairs(f.points)do signature[#signature+1]=string.format("%.7f,%.7f",p.x,p.y)end
 end
 local stats=s.stats();local work=stats.scene3DPaintedVertices
 if not work then work=0;for _,n in ipairs(s.order)do work=work+#n.paintMesh.vertices end end
 return ms,table.concat(signature,";"),work,stats.scene3DProjectedNodes
end
''')
    moving=measure(lua,lua.globals().motionFrame)
    lua=runtime(old)
    lua.execute('''
M=E.math3d;s=E.newScene3D({width=400,height=300});s.setCamera({position=M.vec(0,0,8),target=M.vec()})
fx=E.newParticles3D(s,{spark={count=512,speed=0,lifetime=15,size=.1,gravity=M.vec()}},
 {maxParticles3D=1024,maxParticleSpawns3DPerStep=768})
fx.burst("spark",{seed=1});fx.update(.001);fx.burst("spark",{seed=2})
function saturatedFrame(i)
 local start=os.clock();fx.update(1/60);local made=fx.burst("spark",{count=768,seed=i})
 local ms=(os.clock()-start)*1000
 return ms,tostring(made)..":"..#fx.particles,0,0
end
''')
    saturation=measure(lua,lua.globals().saturatedFrame)
    report['versions'][label]={'sourceHashes':{name:hashlib.sha256(module(name,old).encode()).hexdigest() for name in ['scene3d','particles3d']},
                              'cameraAndModelMotion':moving,'saturatedSpawns':saturation}
for case in ['cameraAndModelMotion','saturatedSpawns']:
    assert report['versions']['before'][case]['trajectoryHash']==report['versions']['after'][case]['trajectoryHash'],case+' changed output'
report['sameOutput']=True
print(json.dumps(report,indent=2))
