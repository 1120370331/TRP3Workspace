-- Palette/RLE pixels mapped onto mesh UVs. No external image or client asset.
-- The renderer receives merged, colored surface patches; picking keeps the base mesh.
return function(E,G)
    local P,assert={},G.assert
    E.pixelMaterials=P
    local alphabet="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"
    local digits={};for i=1,#alphabet do digits[alphabet:sub(i,i)]=i-1 end
    function P.decode(def)
        assert(type(def)=="table" and type(def.width)=="number" and def.width%1==0 and def.width>=1 and def.width<=32 and
            type(def.height)=="number" and def.height%1==0 and def.height>=1 and def.height<=32,"invalid pixel texture dimensions")
        assert(type(def.palette)=="table" and #def.palette>=1 and #def.palette<=32,"invalid pixel palette")
        local palette={}
        for i,hex in ipairs(def.palette)do
            assert(type(hex)=="string" and #hex==6 and hex:match("^[0-9a-fA-F]+$"),"invalid pixel color")
            palette[i]={tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255,1}
        end
        local data=def.data;local capacity=def.width*def.height
        local compact=def.codec=="rle4"
        assert(def.codec==nil or def.codec=="rle4","unknown pixel codec")
        assert(not compact or #palette<=16,"rle4 supports up to 16 colors")
        assert(type(data)=="string" and #data<=(compact and capacity or capacity*2) and (compact or #data%2==0),"invalid pixel RLE")
        local pixels={}
        for i=1,#data,compact and 1 or 2 do
            local value=digits[data:sub(i,i)]
            local index,count
            if compact then if value then index=math.floor(value/4);count=value%4 end
            else index=value;count=digits[data:sub(i+1,i+1)]end
            assert(index and index<#palette and count and #pixels+count+1<=capacity,"invalid pixel run")
            for _=1,count+1 do pixels[#pixels+1]=index+1 end
        end
        assert(#pixels==capacity,"incomplete pixel texture")
        local used,rectangles={},{}
        for y=0,def.height-1 do for x=0,def.width-1 do
            local at=y*def.width+x+1
            if not used[at]then
                local index=pixels[at];local w,h=1,1
                while x+w<def.width and not used[at+w] and pixels[at+w]==index do w=w+1 end
                while y+h<def.height do
                    local same=true
                    for dx=0,w-1 do local p=(y+h)*def.width+x+dx+1;if used[p] or pixels[p]~=index then same=false;break end end
                    if not same then break end;h=h+1
                end
                for dy=0,h-1 do for dx=0,w-1 do used[(y+dy)*def.width+x+dx+1]=true end end
                rectangles[#rectangles+1]={x=x,y=y,w=w,h=h,color=palette[index],index=index}
            end
        end end
        return {width=def.width,height=def.height,palette=palette,pixels=pixels,rectangles=rectangles,encodedBytes=#data+#palette*6}
    end
    local function rotate(u,v,turns)
        for _=1,turns do u,v=1-v,u end;return {u=u,v=v}
    end
    local function clipUV(poly,a,b,sign)
        local function side(p)return sign*((b.u-a.u)*(p.v-a.v)-(b.v-a.v)*(p.u-a.u))end
        local out={};if #poly==0 then return out end
        local p=poly[#poly];local dp=side(p)
        for _,q in ipairs(poly)do
            local dq=side(q)
            if (dp>=-1e-10)~=(dq>=-1e-10)then
                local t=dp/(dp-dq);out[#out+1]={u=p.u+(q.u-p.u)*t,v=p.v+(q.v-p.v)*t}
            end
            if dq>=-1e-10 then out[#out+1]=q end;p,dp=q,dq
        end
        return out
    end
    function P.bake(mesh,bindings,textures,budget)
        assert(mesh and type(bindings)=="table","pixel material needs a mesh and bindings")
        for key in pairs(bindings)do assert(key=="default" or (type(key)=="number" and key%1==0 and mesh.faces[key]),"unknown pixel material face")end
        local output={vertices={},faces={}};local bound=0
        local function append(points,source,color)
            if #output.faces>=budget then return false end
            local f={sourceFace=source,color=color};local base=#output.vertices
            for i,p in ipairs(points)do output.vertices[#output.vertices+1]=p;f[i]=base+i end
            output.faces[#output.faces+1]=f;return true
        end
        for fi,face in ipairs(mesh.faces)do
            local binding=bindings[fi] or bindings.default
            if not binding then
                local points={};for _,index in ipairs(face)do points[#points+1]=mesh.vertices[index]end
                if not append(points,fi,face.color or {1,1,1,1})then return nil,"pixel_face_budget" end
            else
                if type(binding)=="string"then binding={texture=binding}end
                assert(type(binding)=="table" and textures[binding.texture],"unknown pixel texture")
                local texture=textures[binding.texture];local turns=binding.rotation or 0
                assert(type(turns)=="number" and turns%1==0 and turns>=0 and turns<=3,"invalid pixel UV rotation")
                local uv=face.uv or (#face==4 and {{u=0,v=1},{u=1,v=1},{u=1,v=0},{u=0,v=0}} or {{u=0,v=1},{u=1,v=1},{u=.5,v=0}})
                assert(#uv==#face,"pixel UV count must match face corners")
                for _,p in ipairs(uv)do assert(E.util.finite(p.u) and E.util.finite(p.v) and p.u>=0 and p.u<=1 and p.v>=0 and p.v<=1,"pixel UV must be within 0..1")end
                bound=bound+1
                local quadFast=#face==4
                if quadFast then
                    local du1,dv1=uv[2].u-uv[1].u,uv[2].v-uv[1].v
                    local du2,dv2=uv[4].u-uv[1].u,uv[4].v-uv[1].v
                    quadFast=(math.abs(du1)<1e-9 and math.abs(dv2)<1e-9) or (math.abs(dv1)<1e-9 and math.abs(du2)<1e-9)
                    local a,b,c,d=mesh.vertices[face[1]],mesh.vertices[face[2]],mesh.vertices[face[3]],mesh.vertices[face[4]]
                    for _,key in ipairs({"x","y","z"})do if math.abs(a[key]+c[key]-b[key]-d[key])>1e-9 then quadFast=false end end
                    if math.abs(uv[1].u+uv[3].u-uv[2].u-uv[4].u)>1e-9 or math.abs(uv[1].v+uv[3].v-uv[2].v-uv[4].v)>1e-9 then quadFast=false end
                end
                local minU,maxU,minV,maxV=1,0,1,0
                for _,p in ipairs(uv)do minU=math.min(minU,p.u);maxU=math.max(maxU,p.u);minV=math.min(minV,p.v);maxV=math.max(maxV,p.v)end
                for ti=2,quadFast and 2 or #face-1 do
                    local ci=quadFast and 4 or ti+1
                    local a,b,c=uv[1],uv[ti],uv[ci]
                    local det=(b.u-a.u)*(c.v-a.v)-(c.u-a.u)*(b.v-a.v)
                    assert(math.abs(det)>1e-10,"degenerate pixel UV triangle")
                    local va,vb,vc=mesh.vertices[face[1]],mesh.vertices[face[ti]],mesh.vertices[face[ci]]
                    for _,rect in ipairs(texture.rectangles)do
                        local l,r,t,bottom=rect.x/texture.width,(rect.x+rect.w)/texture.width,rect.y/texture.height,(rect.y+rect.h)/texture.height
                        local poly
                        if quadFast then
                            -- A sticker can sample only its original N-by-N tile of a face.
                            -- Reject non-overlapping blocks without allocating clip polygons.
                            for _=1,turns do l,r,t,bottom=1-bottom,1-t,l,r end
                            l,r,t,bottom=math.max(l,minU),math.min(r,maxU),math.max(t,minV),math.min(bottom,maxV)
                            poly=r>l+1e-10 and bottom>t+1e-10 and {{u=l,v=t},{u=r,v=t},{u=r,v=bottom},{u=l,v=bottom}} or {}
                        else poly={rotate(l,t,turns),rotate(r,t,turns),rotate(r,bottom,turns),rotate(l,bottom,turns)}end
                        local sign=det>0 and 1 or -1
                        if not quadFast then poly=clipUV(poly,a,b,sign);poly=clipUV(poly,b,c,sign);poly=clipUV(poly,c,a,sign)end
                        local area=0
                        for i,p in ipairs(poly)do local q=poly[i%#poly+1];area=area+p.u*q.v-q.u*p.v end
                        if #poly>=3 and math.abs(area)>1e-10 then
                            local points={}
                            for _,p in ipairs(poly)do
                                local du,dv=p.u-a.u,p.v-a.v
                                local wb=(du*(c.v-a.v)-(c.u-a.u)*dv)/det
                                local wc=((b.u-a.u)*dv-du*(b.v-a.v))/det;local wa=1-wb-wc
                                points[#points+1]={x=va.x*wa+vb.x*wb+vc.x*wc,y=va.y*wa+vb.y*wb+vc.y*wc,z=va.z*wa+vb.z*wb+vc.z*wc}
                            end
                            -- Align patch winding with the original mesh, including mirrored UVs.
                            if area*det<0 then local reversed={};for i=#points,1,-1 do reversed[#reversed+1]=points[i]end;points=reversed end
                            if #points<=4 then
                                if not append(points,fi,rect.color)then return nil,"pixel_face_budget" end
                            else for i=2,#points-1 do if not append({points[1],points[i],points[i+1]},fi,rect.color)then return nil,"pixel_face_budget" end end end
                        end
                    end
                end
            end
        end
        return output,bound
    end
end
