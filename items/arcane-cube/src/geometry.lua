-- Procedural stone, brass and gemstone faces: no external texture installation.
local A={}
A.colors={U={.90,.92,.84,1},D={1,.73,.14,1},R={.86,.17,.15,1},L={1,.39,.08,1},F={.12,.72,.43,1},B={.13,.43,.94,1}}
A.names={U="月石 · 白",D="圣光 · 金",R="烈焰 · 红",L="琥珀 · 橙",F="翡翠 · 绿",B="寒霜 · 蓝"}
A.faceTextures={U="crystal",D="moon",R="trident",L="shell",F="wave",B="whirlpool"}
local faceAxes={R={{0,0,-1},{0,1,0}},L={{0,0,1},{0,1,0}},U={{1,0,0},{0,0,-1}},D={{1,0,0},{0,0,1}},F={{1,0,0},{0,1,0}},B={{-1,0,0},{0,1,0}}}
function A.registerSkin(scene,pixels)
    for _,face in ipairs(pixels.faces)do if not scene.pixelTextures[face.id]then
        assert(scene.definePixelTexture(face.id,{width=pixels.width,height=pixels.height,codec=pixels.codec,palette=pixels.palette,data=face.data}))
    end end
end
function A.mesh(c,api,puzzle,skin,n)
    local M=api.math;local mesh=api.boxMesh(.93,{.065,.073,.082,1});local bindings={}
    if skin=="tidal" then
        for i,face in ipairs({"B","F","L","R","U","D"})do mesh.faces[i].surfaceGroup=face end
    end
    local function quad(normal,u,v,depth,cx,cy,rx,ry,color,tag)
        local start=#mesh.vertices
        for _,corner in ipairs({{-1,-1},{1,-1},{1,1},{-1,1}})do
            mesh.vertices[#mesh.vertices+1]=M.add(M.mul(normal,depth),M.add(M.mul(u,cx+corner[1]*rx),M.mul(v,cy+corner[2]*ry)))
        end
        mesh.faces[#mesh.faces+1]={start+1,start+2,start+3,start+4,color=color,tag=tag}
        if skin=="tidal" then mesh.faces[#mesh.faces].surfaceGroup=tag end
        return #mesh.faces
    end
    for _,face in ipairs({"R","L","U","D","F","B"})do if c.stickers[face]then
        local normal=puzzle.normals[face];local uv=faceAxes[face]
        local u,v=M.vec(unpack(uv[1])),M.vec(unpack(uv[2]))
        if skin=="tidal" then
            -- Keep the original face color as a thin gameplay-readable rim.
            quad(normal,u,v,.467,0,0,.435,.435,A.colors[face],face)
            local at=quad(normal,u,v,.469,0,0,.414,.414,{1,1,1,1},face)
            local col=(M.dot(c.home,u)+n-1)/2;local row=(n-1-M.dot(c.home,v))/2
            local l,r,t,b=col/n,(col+1)/n,row/n,(row+1)/n
            mesh.faces[at].uv={{u=l,v=b},{u=r,v=b},{u=r,v=t},{u=l,v=t}}
            bindings[at]=A.faceTextures[face]
        else
        quad(normal,u,v,.467,0,0,.423,.423,{.48,.35,.16,1},face)
        quad(normal,u,v,.469,0,0,.381,.381,A.colors[face],face)
        -- A small facet near the top edge reads as a cut gem under the light.
        local color=A.colors[face];local shine={math.min(1,color[1]*.55+.45),math.min(1,color[2]*.55+.45),math.min(1,color[3]*.55+.45),1}
        quad(normal,u,v,.471,0,.335,.325,.018,shine,face)
        end
    end end
    return mesh,bindings
end
return A
