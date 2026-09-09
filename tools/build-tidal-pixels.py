"""Author compact pixel art from the six-face imagegen style reference.

The reference image is never sampled or embedded. Integer shapes below are the
editable source; Lua palette/RLE data is the only art consumed by the game.
PNG and rectangle-based SVG outputs are inspection/editing artifacts.
"""
from pathlib import Path
from PIL import Image, ImageDraw
import json
import math

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'items/arcane-cube/art/pixels'
PALETTE=['081A28','103449','185466','247C86','50BFB7','A8EFDA','B38E45','66512E','E9D69B','327A92','D9FFF0','244654']
IDS=['wave','shell','trident','whirlpool','crystal','moon']
NAMES=['潮涌','海贝','潮汐戟','漩涡','海晶','月潮']
ALPHABET='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_'
SIZE=24


def frame():
    im=Image.new('P',(SIZE,SIZE),0)
    palette=[v for c in PALETTE for v in bytes.fromhex(c)]
    im.putpalette(palette+[0]*(768-len(palette)))
    d=ImageDraw.Draw(im)
    d.rectangle((1,1,22,22),fill=1)
    d.rectangle((0,0,23,23),outline=6);d.line([(1,0),(22,0)],fill=8)
    d.line([(0,1),(0,22)],fill=8)
    d.ellipse((2,2,21,21),outline=6)
    for x,y in [(2,2),(21,2),(2,21),(21,21)]:
        d.rectangle((x-1,y-1,x+1,y+1),fill=7)
        d.point((x,y),fill=4);d.point((x,y-1),fill=10)
    for pts in [[(5,2),(7,1),(9,2)],[(14,2),(16,1),(18,2)],[(5,21),(7,22),(9,21)],[(14,21),(16,22),(18,21)]]:
        d.line(pts,fill=3)
    return im,d


def author(kind):
    im,d=frame()
    if kind=='wave':
        d.polygon([(6,19),(4,15),(5,11),(7,8),(10,6),(14,6),(17,8),(18,11),(17,13),(15,14),(13,13),(13,11),(15,10),(13,9),(10,10),(8,13),(9,16),(13,18),(18,17),(18,19),(13,20)],fill=3)
        d.line([(5,13),(6,10),(9,7),(13,6),(16,7),(18,10),(17,12),(15,13),(14,12)],fill=5,width=2)
        d.line([(6,15),(8,18),(12,20),(16,20)],fill=9)
        d.line([(9,12),(9,15),(12,17),(16,17)],fill=4)
        d.point((18,14),fill=10);d.point((19,11),fill=4)
    elif kind=='shell':
        edge=[(5,10),(7,7),(10,6),(12,5),(14,6),(17,7),(19,10),(18,13),(14,18),(10,18),(6,13)]
        d.polygon(edge,fill=6)
        for i,(a,b) in enumerate(zip(edge[:7],edge[1:8])):
            d.polygon([(12,18),a,b],fill=8 if i%2==0 else 6)
        for p in [(6,10),(8,7),(11,6),(14,7),(17,9),(18,12)]:d.line([(12,18),p],fill=7)
        d.rectangle((10,18,14,19),fill=6);d.point((12,20),fill=8)
        d.line([(5,15),(5,17),(7,19)],fill=3);d.line([(19,15),(19,17),(17,19)],fill=4)
    elif kind=='trident':
        d.line([(12,6),(12,19)],fill=8,width=2)
        d.polygon([(12,4),(10,8),(14,8)],fill=6)
        d.line([(7,9),(7,13),(10,15),(14,15),(17,13),(17,9)],fill=6,width=2)
        d.polygon([(7,7),(5,10),(9,10)],fill=8)
        d.polygon([(17,7),(15,10),(19,10)],fill=8)
        d.polygon([(12,12),(10,14),(12,16),(14,14)],fill=3);d.point((12,13),fill=10)
        d.line([(5,17),(6,16),(8,17),(8,19)],fill=4)
        d.line([(19,17),(18,16),(16,17),(16,19)],fill=3)
    elif kind=='whirlpool':
        for offset in [0,2*math.pi/3,4*math.pi/3]:
            pts=[]
            for i in range(25):
                t=i/24*3.8;r=1+t*1.7
                pts.append((round(11.5+math.cos(t+offset)*r),round(11.5+math.sin(t+offset)*r)))
            d.line(pts,fill=3,width=2);d.line(pts[9:20],fill=5)
        d.point((5,7),fill=4);d.point((19,16),fill=10)
    elif kind=='crystal':
        top,left,right,bottom=(12,4),(8,12),(16,12),(12,20)
        d.polygon([top,left,bottom],fill=4);d.polygon([top,right,bottom],fill=2)
        d.polygon([top,left,(12,11)],fill=5);d.polygon([top,right,(12,11)],fill=3)
        d.line([top,(12,11),bottom],fill=10)
        d.line([left,(12,11),right],fill=4)
        for x,y in [(6,7),(18,7),(6,17),(18,17)]:
            d.line([(x-1,y),(x+1,y)],fill=8);d.line([(x,y-1),(x,y+1)],fill=6)
    else:
        d.ellipse((5,5,16,16),fill=6);d.ellipse((6,5,16,15),fill=8)
        d.ellipse((9,3,19,13),fill=1)
        d.line([(5,17),(8,18),(12,16),(15,16),(18,18)],fill=5,width=2)
        d.line([(6,20),(10,21),(15,19),(18,19)],fill=3)
        d.point((17,7),fill=5);d.point((19,9),fill=4);d.point((18,12),fill=10)
    return im


def encode(pixels):
    data=[];i=0
    while i<len(pixels):
        count=1
        while i+count<len(pixels) and pixels[i+count]==pixels[i] and count<4:count+=1
        data.append(ALPHABET[pixels[i]*4+count-1]);i+=count
    return ''.join(data)


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    rows=[];images=[]
    for kind,name in zip(IDS,NAMES):
        im=author(kind);images.append(im);pixels=list(im.getdata());data=encode(pixels)
        rows.append({'id':kind,'name':name,'data':data})
        im.save(OUT/(kind+'.png'),bits=4,optimize=True)
    text='-- Generated from editable integer pixel shapes in tools/build-tidal-pixels.py.\n'
    text+='-- Imagegen supplies style references only; PNGs are never loaded in WoW.\n'
    text+='return {width=24,height=24,codec="rle4",palette={'+','.join('"'+c+'"' for c in PALETTE)+'},faces={\n'
    for row in rows:text+=' {id="'+row['id']+'",name="'+row['name']+'",data="'+row['data']+'"},\n'
    text+='}}\n'
    (ROOT/'items/arcane-cube/src/pixel-art.lua').write_text(text,encoding='utf-8',newline='\n')
    atlas=Image.new('RGB',(3*256,2*256),'#081A28')
    svg=['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 78 52" shape-rendering="crispEdges">','<rect width="78" height="52" fill="#081A28"/>']
    for i,im in enumerate(images):
        atlas.paste(im.resize((240,240),Image.Resampling.NEAREST).convert('RGB'),((i%3)*256+8,(i//3)*256+8))
        values=list(im.getdata());ox=(i%3)*26+1;oy=(i//3)*26+1
        for y in range(SIZE):
            x=0
            while x<SIZE:
                c=values[y*SIZE+x];w=1
                while x+w<SIZE and values[y*SIZE+x+w]==c:w+=1
                svg.append(f'<rect x="{ox+x}" y="{oy+y}" width="{w}" height="1" fill="#{PALETTE[c]}"/>');x+=w
    svg.append('</svg>')
    atlas.save(OUT/'six-faces-preview.png',optimize=True)
    (OUT/'six-faces.svg').write_text('\n'.join(svg),encoding='utf-8')
    metrics={'faceSize':[24,24],'paletteColors':len(PALETTE),'rawRGBBytes':6*24*24*3,'paletteAndRLEBytes':sum(len(r['data']) for r in rows)+len(PALETTE)*6,'luaBytes':len(text.encode())}
    (OUT/'compression.json').write_text(json.dumps(metrics,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(metrics))

if __name__=='__main__':main()
