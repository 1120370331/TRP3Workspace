"""Compressed pixel integrity and UV/world-space binding contracts."""
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'.local-tools/python'))
from lupa.lua51 import LuaRuntime

class PixelMaterialTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True);self.lua.execute('E={}')
        for name in ['core','math3d','pixel-materials','scene3d']:
            self.lua.execute((ROOT/f'framework/item-game/{name}.lua').read_text('utf-8'))(self.lua.globals().E,self.lua.globals())
        self.lua.execute('''
M=E.math3d;scene=E.newScene3D({maxFaces=4096})
scene.definePixelTexture("stripes",{width=2,height=2,codec="rle4",palette={"FF0000","0000FF"},data="15"})
mesh={vertices={M.vec(-1,-1,0),M.vec(1,-1,0),M.vec(1,1,0),M.vec(-1,1,0)},faces={{1,2,3,4}}}
''')

    def test_rle4_and_rectangle_merge_reconstruct_every_pixel(self):
        self.lua.globals().art=self.lua.execute((ROOT/'items/arcane-cube/src/pixel-art.lua').read_text('utf-8'))
        self.lua.execute('''
local bytes=#art.palette*6
for _,face in ipairs(art.faces)do
 local decoded=E.pixelMaterials.decode({width=art.width,height=art.height,palette=art.palette,codec=art.codec,data=face.data})
 local cells={}
 for _,r in ipairs(decoded.rectangles)do for y=r.y,r.y+r.h-1 do for x=r.x,r.x+r.w-1 do
  local i=y*decoded.width+x+1;assert(not cells[i],"merged rectangles overlap");cells[i]=r.index
 end end end
 for i,index in ipairs(decoded.pixels)do assert(cells[i]==index,"pixel missing after merge")end
 bytes=bytes+#face.data
end
assert(bytes<2048 and #art.faces==6)
''')

    def test_invalid_compressed_data_and_uv_are_rejected(self):
        self.lua.execute('''
local P=E.pixelMaterials
assert(not pcall(P.decode,{width=2,height=2,codec="rle4",palette={"FFFFFF"},data="_"}))
assert(not pcall(P.decode,{width=2,height=2,codec="rle4",palette={"FFFFFF"},data="0"}))
assert(not pcall(P.decode,{width=33,height=2,palette={"FFFFFF"},data="01"}))
mesh.faces[1].uv={{u=0,v=0},{u=0,v=0},{u=0,v=0},{u=0,v=0}}
assert(not pcall(P.bake,mesh,{default="stripes"},scene.pixelTextures,20))
''')

    def test_material_rotation_and_parent_transform_preserve_base_geometry(self):
        self.lua.execute('''
scene.create("group",{position=M.vec(1,2,3),rotation=M.vec(.2,.3,.4)})
scene.create("panel",{mesh=mesh,parent="group"})
assert(scene.setPixelMaterials("panel",{default="stripes"}))
local node=scene.get("panel");assert(node.mesh==mesh and #node.paintMesh.faces==2)
local original=E.JSON.encode(node.paintMesh.vertices)
scene.renderList()
for i,p in ipairs(node.paintMesh.vertices)do
 assert(M.length(M.sub(node.paintVertices[i],scene.worldPoint("panel",p)))<1e-8)
end
for i=1,4 do assert(scene.setPixelMaterials("panel",{default={texture="stripes",rotation=i%4}}))end
assert(E.JSON.encode(node.paintMesh.vertices)==original)
scene.setTransform("group",{rotation=M.vec(.6,.7,.8)});scene.renderList()
for i,p in ipairs(node.paintMesh.vertices)do assert(M.length(M.sub(node.paintVertices[i],scene.worldPoint("panel",p)))<1e-8)end
scene.setPixelMaterials("panel",nil);assert(node.paintMesh==nil and node.mesh==mesh and scene.faceCount==1)
''')

    def test_uv_rotation_moves_color_and_triangle_stays_inside_original_face(self):
        self.lua.execute('''
scene.create("panel",{mesh=mesh});scene.setPixelMaterials("panel",{default="stripes"})
local first=scene.get("panel").paintMesh
local maxY=-100
for _,f in ipairs(first.faces)do if f.color[1]==1 then for _,i in ipairs(f)do maxY=math.max(maxY,first.vertices[i].y)end end end
assert(maxY==1,"red top row should map to model top")
scene.setPixelMaterials("panel",{default={texture="stripes",rotation=1}})
local rotated=scene.get("panel").paintMesh
for _,f in ipairs(rotated.faces)do if f.color[1]==1 then for _,i in ipairs(f)do assert(rotated.vertices[i].x>=-1e-9)end end end
local tri={vertices={M.vec(-1,-1,0),M.vec(1,-1,0),M.vec(0,1,0)},faces={{1,2,3}}}
local painted=E.pixelMaterials.bake(tri,{default="stripes"},scene.pixelTextures,30)
for _,p in ipairs(painted.vertices)do assert(p.y>=-1-1e-9 and p.y<=1+1e-9 and math.abs(p.x)<=(1-p.y)/2+1e-9)end
''')

    def test_budget_rejection_is_atomic_and_picking_uses_original_mesh(self):
        self.lua.execute('''
local small=E.newScene3D({maxFaces=1,width=400,height=300})
small.definePixelTexture("stripes",{width=2,height=2,codec="rle4",palette={"FF0000","0000FF"},data="15"})
small.create("panel",{mesh=mesh})
local ok,why=small.setPixelMaterials("panel",{default="stripes"});assert(not ok and why=="pixel_face_budget")
assert(small.faceCount==1 and small.get("panel").paintMesh==nil)
scene.create("panel",{mesh=mesh});scene.setPixelMaterials("panel",{default="stripes"})
local hit=scene.raycast(M.vec(0,0,4),M.vec(0,0,-1))
assert(hit.id=="panel" and hit.face==1 and math.abs(hit.point.z)<1e-9)
''')

    def test_cropped_quad_samples_only_its_original_texture_region(self):
        self.lua.execute('''
mesh.faces[1].uv={{u=0,v=.5},{u=.5,v=.5},{u=.5,v=0},{u=0,v=0}}
scene.create("tile",{mesh=mesh});assert(scene.setPixelMaterials("tile",{default="stripes"}))
local p=scene.get("tile").paintMesh
assert(#p.faces==1 and p.faces[1].color[1]==1 and p.faces[1].color[3]==0)
for _,v in ipairs(p.vertices)do assert(math.abs(v.x)<=1+1e-9 and math.abs(v.y)<=1+1e-9)end
''')

    def test_surface_group_keeps_pixels_above_full_color_backing(self):
        self.lua.execute('''
mesh.vertices[5]=M.vec(-1,-1,.002);mesh.vertices[6]=M.vec(1,-1,.002)
mesh.vertices[7]=M.vec(1,1,.002);mesh.vertices[8]=M.vec(-1,1,.002)
mesh.faces={{1,2,3,4,color={0,1,0,1},surfaceGroup="front"},{5,6,7,8,surfaceGroup="front"}}
scene.create("layered",{mesh=mesh});scene.setPixelMaterials("layered",{[2]="stripes"})
scene.setCamera({position=M.vec(4,3,6),target=M.vec()})
local faces=scene.renderList();assert(#faces==3 and faces[1].sourceFace==1)
for i=2,#faces do assert(faces[i].sourceFace==2 and faces[i].depth==faces[1].depth)end
''')

if __name__=='__main__':unittest.main(verbosity=2)
