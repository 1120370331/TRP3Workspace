"""Local visual/input harness for the actual shipped Lua, not a JS game port.

Browser rasterizes native Texture vertex offsets captured by mock-wow.lua.
This proves geometry/UI integration only, never WoW GPU, input or performance.
"""
from pathlib import Path
import argparse
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'items/arcane-cube/tests'))
from harness import CubeHarness

PAGE='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>奥术魔方 · Lua 运行预览</title>
<style>html,body{margin:0;min-height:100%;background:#15191f;color:#aaa;font:13px 'Microsoft YaHei',sans-serif}main{max-width:1100px;margin:24px auto}header{display:flex;justify-content:space-between;margin:0 0 14px;padding:0 8px}canvas{display:block;width:100%;background:#0e1014;box-shadow:0 16px 70px #0008;touch-action:none}footer{margin:16px 8px;color:#8a929e;line-height:1.8}button{background:#303640;color:#eee;border:1px solid #59606c;padding:6px 14px;cursor:pointer}</style>
<main><header><span>奥术魔方 / 同一份 Lua 游戏与引擎源码</span><button id="reopen">模拟关闭并重开</button></header>
<canvas width="1920" height="1220" aria-label="可交互的奥术魔方"></canvas>
<footer>本地绘图与交互预览。浏览器显示 WoW 适配器产生的顶点；星光纹理用渐变近似，不能替代 WoW 客户端验收。<span id="status"></span></footer></main>
<script>
const canvas=document.querySelector('canvas'),g=canvas.getContext('2d');let state,queue=[],busy=false,down,button;
g.scale(2,2);const rgba=c=>`rgba(${c.slice(0,3).map(x=>Math.round(x*255))},${c[3]??1})`;
function draw(s){state=s;g.clearRect(0,0,960,610);const items=[...s.ui.map(v=>({...v,sort:v.layer*288})),...s.quads.map((v,i)=>({...v,sort:v.order??100+i,kind:'quad'}))].sort((a,b)=>a.sort-b.sort);
for(const v of items){g.globalAlpha=1;g.globalCompositeOperation=v.blend==='ADD'?'lighter':'source-over';if(v.kind==='quad'){g.beginPath();v.points.forEach((p,i)=>i?g.lineTo(p.x,p.y):g.moveTo(p.x,p.y));g.closePath();if(v.texture?.includes('star4')){g.save();g.clip();const p=v.points,uv=v.texCoord||[0,1,0,1],w=(p[1].x-p[0].x)/(uv[1]-uv[0]),h=(p[3].y-p[0].y)/(uv[3]-uv[2]),cx=p[0].x+(0.5-uv[0])*w,cy=p[0].y+(0.5-uv[2])*h;const glow=g.createRadialGradient(cx,cy,0,cx,cy,Math.max(w,h)/2);glow.addColorStop(0,rgba(v.color));glow.addColorStop(.2,rgba(v.color));glow.addColorStop(1,rgba([...v.color.slice(0,3),0]));g.fillStyle=glow;g.fillRect(p[0].x,p[0].y,p[2].x-p[0].x,p[2].y-p[0].y);g.restore();}else{g.fillStyle=rgba(v.color);g.fill();}}
else if(v.kind==='rect'||v.kind==='button'){g.fillStyle=rgba(v.color);g.fillRect(v.x,v.y,v.w,v.h);if(v.kind==='button'){g.strokeStyle=v.enabled?'#aa865645':'#ffffff08';g.strokeRect(v.x+.5,v.y+.5,v.w-1,v.h-1);}}
if(v.kind==='text'||v.kind==='button'){g.fillStyle=v.kind==='button'?(v.enabled?'#fff5d6':'#777'):rgba(v.color);g.font=`${v.size||14}px "Microsoft YaHei",sans-serif`;const align=v.kind==='button'?'CENTER':v.align||'CENTER';g.textAlign=align.toLowerCase();g.textBaseline='middle';const x=align==='LEFT'?v.x:align==='RIGHT'?v.x+v.w:v.x+v.w/2;g.fillText(v.text||'',x,v.y+v.h/2,v.w);}}
document.querySelector('#status').textContent=` · ${s.stats.scene3DNodes} 节点 / ${s.stats.scene3DDraws} 绘制面 / ${s.stats.particles3D||0} 粒子`;}
async function pump(){if(busy)return;busy=true;try{const events=queue.splice(0);const r=await fetch('/frame',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({events})});if(!r.ok)throw Error(await r.text());draw(await r.json());}catch(e){document.querySelector('#status').textContent=e;console.error(e);}finally{busy=false;}}
function point(e){const b=canvas.getBoundingClientRect();return {x:(e.clientX-b.left)*960/b.width,y:(e.clientY-b.top)*610/b.height};}
function target(p){return state?.ui.filter(v=>v.kind==='button'&&v.enabled&&p.x>=v.x&&p.x<=v.x+v.w&&p.y>=v.y&&p.y<=v.y+v.h).sort((a,b)=>b.layer-a.layer)[0];}
canvas.oncontextmenu=e=>e.preventDefault();canvas.onpointerdown=e=>{e.preventDefault();canvas.setPointerCapture(e.pointerId);const p=point(e);down=target(p);button=e.button===2?'RightButton':'LeftButton';if(!down)queue.push({kind:'pointer',phase:'down',...p,button});pump();};
canvas.onpointermove=e=>{if(e.buttons&&!down){queue.push({kind:'pointer',phase:'move',...point(e),button});pump();}};
canvas.onpointerup=e=>{const p=point(e);if(down){if(target(p)?.id===down.id)queue.push({kind:'click',id:down.id});}else queue.push({kind:'pointer',phase:'up',...p,button});down=null;pump();};
canvas.onwheel=e=>{e.preventDefault();queue.push({kind:'pointer',phase:'wheel',...point(e),button:'',delta:e.deltaY<0?1:-1});pump();};
document.onkeydown=e=>{if(['j','k','z','Escape'].includes(e.key)){e.preventDefault();queue.push({kind:'key',key:e.key.toUpperCase()});pump();}};
document.querySelector('#reopen').onclick=()=>{queue.push({kind:'reopen'});pump();};
window.cubePreview={get state(){return state},send:event=>{queue.push(event);return pump()}};setInterval(pump,34);pump();
</script>'''

SNAPSHOT='''
local out={ui={},quads={},stats=session.scene3d.stats(),saved=snapshot()}
for id,node in pairs(Mock.nodes)do if node.object:IsShown() then
 local s=node.previewSpec
 out.ui[#out.ui+1]={id=id,kind=s.kind,x=s.x,y=s.y,w=s.w,h=s.h,layer=s.layer or 0,color=s.color or {1,1,1,1},text=s.text,size=s.size,align=s.align,enabled=node.enabled==true}
end end
for _,h in ipairs(E.viewCache.scene3D.pool)do if h.texture:IsShown() then
 local x,y=h.texture.point[4],-h.texture.point[5];local w,ht=h.texture.width,h.texture.height;local v=h.texture.vertices
 out.quads[#out.quads+1]={order=h.frame:GetFrameLevel()-session.scene3d.cache.root:GetFrameLevel()+100,color=h.texture.vertexColor,texture=h.texture.texture,blend=h.texture.blend,texCoord=h.texture.texCoord,points={
  {x=x+v[1][1],y=y-v[1][2]}, {x=x+w+v[3][1],y=y-v[3][2]},
  {x=x+w+v[4][1],y=y+ht-v[4][2]}, {x=x+v[2][1],y=y+ht-v[2][2]}}}
end end
return E.JSON.encode(out)
'''

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--port',type=int,default=8766);args=parser.parse_args()
    h=CubeHarness();h.setUp();h.boot();last=time.monotonic()
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def do_GET(self):
            if self.path=='/favicon.ico':self.send_response(204);self.end_headers();return
            self.send_response(200);self.send_header('Content-Type','text/html; charset=utf-8');self.end_headers();self.wfile.write(PAGE.encode())
        def do_POST(self):
            nonlocal last
            try:
                count=int(self.headers.get('Content-Length',0))
                if count>32768:raise ValueError('request too large')
                data=json.loads(self.rfile.read(count))
                now=time.monotonic();h.advance(min(.1,now-last));last=now
                for e in data.get('events',[]):
                    if e['kind']=='click':h.click(e['id'])
                    elif e['kind']=='pointer':h.lua.globals().pointer(e['phase'],e['x'],e['y'],e.get('button','LeftButton'),e.get('delta',0))
                    elif e['kind']=='reopen':h.restart()
                    elif e['kind']=='key':
                        if e['key']=='ESCAPE':h.lua.globals().Mock.pressEscape()
                        else:
                            key=e['key'];frame=h.lua.globals().session.view.frame
                            frame.GetScript(frame,'OnKeyDown')(frame,key);frame.GetScript(frame,'OnKeyUp')(frame,key)
                h.lua.globals().session.scene3d.render()
                body=h.lua.execute(SNAPSHOT).encode()
                self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(body)
            except Exception as error:
                self.send_response(500);self.end_headers();self.wfile.write(str(error).encode())
    print(f'Actual Lua / mock-WoW preview: http://127.0.0.1:{args.port}',flush=True)
    HTTPServer(('127.0.0.1',args.port),Handler).serve_forever()

if __name__=='__main__':main()
