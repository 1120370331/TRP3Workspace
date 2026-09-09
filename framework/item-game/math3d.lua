-- Right-handed coordinates: X right, Y up, Z towards the viewer. Angles in radians.
-- Affine matrices are row-major 3x4. No WoW API or game-specific rules here.
return function(E, G)
    local M, abs, sqrt = {}, math.abs, math.sqrt
    E.math3d = M
    function M.vec(x,y,z) return {x=x or 0,y=y or 0,z=z or 0} end
    function M.add(a,b) return M.vec(a.x+b.x,a.y+b.y,a.z+b.z) end
    function M.sub(a,b) return M.vec(a.x-b.x,a.y-b.y,a.z-b.z) end
    function M.mul(a,k) return M.vec(a.x*k,a.y*k,a.z*k) end
    function M.dot(a,b) return a.x*b.x+a.y*b.y+a.z*b.z end
    function M.cross(a,b) return M.vec(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x) end
    function M.length(a) return sqrt(M.dot(a,a)) end
    function M.unit(a)
        local l=M.length(a); if l<1e-10 then return M.vec() end
        return M.mul(a,1/l)
    end
    function M.finite(a)
        return type(a)=="table" and E.util.finite(a.x) and E.util.finite(a.y) and E.util.finite(a.z)
    end
    function M.identity() return {1,0,0,0,0,1,0,0,0,0,1,0} end
    function M.transform(p,r,s)
        p=p or M.vec();r=r or M.vec();s=s or M.vec(1,1,1)
        assert(M.finite(p) and M.finite(r) and M.finite(s) and s.x>0 and s.y>0 and s.z>0,"invalid 3D transform")
        local cx,sx,cy,sy,cz,sz=math.cos(r.x),math.sin(r.x),math.cos(r.y),math.sin(r.y),math.cos(r.z),math.sin(r.z)
        -- Rz * Ry * Rx, followed by translation; local scale first.
        return {cz*cy*s.x,(cz*sy*sx-sz*cx)*s.y,(cz*sy*cx+sz*sx)*s.z,p.x,
            sz*cy*s.x,(sz*sy*sx+cz*cx)*s.y,(sz*sy*cx-cz*sx)*s.z,p.y,
            -sy*s.x,cy*sx*s.y,cy*cx*s.z,p.z}
    end
    function M.compose(a,b)
        local o={}
        for row=0,2 do
            local i=row*4
            for col=1,3 do o[i+col]=a[i+1]*b[col]+a[i+2]*b[4+col]+a[i+3]*b[8+col] end
            o[i+4]=a[i+1]*b[4]+a[i+2]*b[8]+a[i+3]*b[12]+a[i+4]
        end
        return o
    end
    function M.point(a,p)
        return M.vec(a[1]*p.x+a[2]*p.y+a[3]*p.z+a[4],a[5]*p.x+a[6]*p.y+a[7]*p.z+a[8],a[9]*p.x+a[10]*p.y+a[11]*p.z+a[12])
    end
    function M.vector(a,p)
        return M.vec(a[1]*p.x+a[2]*p.y+a[3]*p.z,a[5]*p.x+a[6]*p.y+a[7]*p.z,a[9]*p.x+a[10]*p.y+a[11]*p.z)
    end
    function M.inverse(a)
        local det=a[1]*(a[6]*a[11]-a[7]*a[10])-a[2]*(a[5]*a[11]-a[7]*a[9])+a[3]*(a[5]*a[10]-a[6]*a[9])
        assert(abs(det)>1e-12,"singular 3D transform")
        local b={(a[6]*a[11]-a[7]*a[10])/det,(a[3]*a[10]-a[2]*a[11])/det,(a[2]*a[7]-a[3]*a[6])/det,0,
            (a[7]*a[9]-a[5]*a[11])/det,(a[1]*a[11]-a[3]*a[9])/det,(a[3]*a[5]-a[1]*a[7])/det,0,
            (a[5]*a[10]-a[6]*a[9])/det,(a[2]*a[9]-a[1]*a[10])/det,(a[1]*a[6]-a[2]*a[5])/det,0}
        b[4]=-(b[1]*a[4]+b[2]*a[8]+b[3]*a[12]);b[8]=-(b[5]*a[4]+b[6]*a[8]+b[7]*a[12]);b[12]=-(b[9]*a[4]+b[10]*a[8]+b[11]*a[12])
        return b
    end
    function M.rotate(p,axis,angle)
        local r=M.vec();r[axis]=angle;return M.vector(M.transform(nil,r),p)
    end
    function M.rayTriangle(origin,direction,a,b,c)
        local e1,e2=M.sub(b,a),M.sub(c,a)
        local h=M.cross(direction,e2);local det=M.dot(e1,h)
        if abs(det)<1e-9 then return nil end
        local s=M.sub(origin,a);local u=M.dot(s,h)/det
        if u< -1e-8 or u>1+1e-8 then return nil end
        local q=M.cross(s,e1);local v=M.dot(direction,q)/det
        if v< -1e-8 or u+v>1+1e-8 then return nil end
        local t=M.dot(e2,q)/det
        if t>=0 then return t,u,v end
    end
    function M.overlap(a,b)
        return a.min.x<b.max.x and a.max.x>b.min.x and a.min.y<b.max.y and a.max.y>b.min.y and a.min.z<b.max.z and a.max.z>b.min.z
    end
    -- Slab intersection; ray direction can be a finite displacement (t in 0..1).
    function M.rayBox(origin,direction,box,limit)
        local enter,leave,normal=0,limit or math.huge,M.vec()
        for _,axis in ipairs({"x","y","z"}) do
            local d,p,lo,hi=direction[axis],origin[axis],box.min[axis],box.max[axis]
            if abs(d)<1e-12 then if p<lo or p>hi then return nil end
            else
                local t1,t2=(lo-p)/d,(hi-p)/d;local sign=-1
                if t1>t2 then t1,t2=t2,t1;sign=1 end
                if t1>enter then enter=t1;normal=M.vec();normal[axis]=sign end
                leave=math.min(leave,t2);if enter>leave then return nil end
            end
        end
        return enter,normal
    end
    function M.sweepBox(box,delta,target)
        if M.overlap(box,target)then return 0,M.vec()end
        local enter,leave,normal=-math.huge,math.huge,M.vec()
        for _,axis in ipairs({"x","y","z"})do
            local d=delta[axis]
            if abs(d)<1e-12 then
                if box.max[axis]<=target.min[axis] or box.min[axis]>=target.max[axis]then return nil end
            else
                local first,last=(target.min[axis]-box.max[axis])/d,(target.max[axis]-box.min[axis])/d
                local sign=-1;if first>last then first,last=last,first;sign=1 end
                if first>enter then enter=first;normal=M.vec();normal[axis]=sign end
                leave=math.min(leave,last)
            end
        end
        if enter<=leave and leave>0 and enter>=0 and enter<=1 then return enter,normal end
        return nil
    end
end
