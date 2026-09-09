-- Exact N-cube permutation model. Positions and orientation bases stay integer;
-- animation never becomes the authority for the puzzle or its save data.
local P={MIN_ORDER=2,MAX_ORDER=7,MAX_HISTORY=2000}
local axes={"x","y","z"}
local normals={R={x=1,y=0,z=0},L={x=-1,y=0,z=0},U={x=0,y=1,z=0},D={x=0,y=-1,z=0},F={x=0,y=0,z=1},B={x=0,y=0,z=-1}}
P.normals=normals
local function vector(x,y,z)return {x=x,y=y,z=z}end
local function copy(v)return vector(v.x,v.y,v.z)end
function P.validOrder(n)return type(n)=="number" and n%1==0 and n>=P.MIN_ORDER and n<=P.MAX_ORDER end
function P.validMove(move,n)
    return type(move)=="table" and (move.axis=="x" or move.axis=="y" or move.axis=="z") and
        type(move.layer)=="number" and move.layer%1==0 and move.layer>=1 and move.layer<=n and (move.dir==1 or move.dir==-1)
end
function P.rotate(v,axis,dir)
    if axis=="x" then return vector(v.x,-dir*v.z,dir*v.y)
    elseif axis=="y" then return vector(dir*v.z,v.y,-dir*v.x)
    else return vector(-dir*v.y,dir*v.x,v.z)end
end
function P.new(n)
    assert(P.validOrder(n),"魔方阶数必须为 2–7")
    local s={n=n,cubies={}}
    for x=1,n do for y=1,n do for z=1,n do
        if x==1 or y==1 or z==1 or x==n or y==n or z==n then
            local stickers={}
            if x==n then stickers.R=true end;if x==1 then stickers.L=true end
            if y==n then stickers.U=true end;if y==1 then stickers.D=true end
            if z==n then stickers.F=true end;if z==1 then stickers.B=true end
            s.cubies[#s.cubies+1]={id=x.."_"..y.."_"..z,position=vector(2*x-n-1,2*y-n-1,2*z-n-1),
                home=vector(2*x-n-1,2*y-n-1,2*z-n-1),
                basis={vector(1,0,0),vector(0,1,0),vector(0,0,1)},stickers=stickers}
        end
    end end end
    return s
end
function P.inSlice(c,n,axis,layer)return c.position[axis]==2*layer-n-1 end
function P.apply(s,move)
    assert(P.validMove(move,s.n),"invalid cube move")
    for _,c in ipairs(s.cubies)do if P.inSlice(c,s.n,move.axis,move.layer)then
        c.position=P.rotate(c.position,move.axis,move.dir)
        for i=1,3 do c.basis[i]=P.rotate(c.basis[i],move.axis,move.dir)end
    end end
end
function P.direction(c,v)
    return vector(c.basis[1].x*v.x+c.basis[2].x*v.y+c.basis[3].x*v.z,
        c.basis[1].y*v.x+c.basis[2].y*v.y+c.basis[3].y*v.z,c.basis[1].z*v.x+c.basis[2].z*v.y+c.basis[3].z*v.z)
end
function P.isSolved(s)
    local colors,counts={},{}
    for _,c in ipairs(s.cubies)do for color in pairs(c.stickers)do
        local normal=P.direction(c,normals[color]);local key=normal.x..":"..normal.y..":"..normal.z
        if colors[key] and colors[key]~=color then return false end
        colors[key]=color;counts[key]=(counts[key] or 0)+1
    end end
    local n=0;for key in pairs(colors)do if counts[key]~=s.n*s.n then return false end;n=n+1 end
    return n==6
end
function P.inverse(move)return {axis=move.axis,layer=move.layer,dir=-move.dir}end
function P.scramble(n,seed,count)
    assert(P.validOrder(n));local rng=math.floor(math.abs(seed or 1))%2147483646+1
    local function random(max)rng=(rng*16807)%2147483647;return rng%max+1 end
    local out,last={},nil
    for i=1,(count or (20+n*6))do
        local axis=axes[random(3)]
        if axis==last then axis=axes[(axis=="x" and 1 or axis=="y" and 2 or 3)%3+1]end
        out[i]={axis=axis,layer=random(n),dir=random(2)==1 and 1 or -1};last=axis
    end
    return out
end
function P.restore(n,history)
    assert(P.validOrder(n) and type(history)=="table" and #history<=P.MAX_HISTORY,"invalid cube save")
    local count=0;for key in pairs(history)do assert(type(key)=="number" and key%1==0 and key>=1 and key<=#history,"invalid cube history");count=count+1 end
    assert(count==#history,"sparse cube history")
    local s=P.new(n);for _,move in ipairs(history)do P.apply(s,move)end;return s
end
-- Euler angles for Rz * Ry * Rx; exact bases are retained separately.
function P.euler(c)
    local b=c.basis;local y=math.asin(math.max(-1,math.min(1,-b[1].z)))
    if math.abs(math.cos(y))>1e-7 then return vector(math.atan2(b[2].z,b[3].z),y,math.atan2(b[1].y,b[1].x))end
    return vector(math.atan2(-b[3].y,b[2].y),y,0)
end
return P
