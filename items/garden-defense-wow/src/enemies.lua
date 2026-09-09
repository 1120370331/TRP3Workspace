-- Game-owned elite behavior. All timers/projectiles are plain saved data.
return function(definitions,cellX)
    local self={}
    local nextBiteA=true
    function self.cancelMelee(z)
        local changed=z.attackTime~=nil
        z.attackTime=nil;z.attackHit=nil;z.attackCol=nil
        return changed
    end
    function self.melee(z,p,run,dt,sound)
        local d=definitions[z.kind];local swing=d.melee
        local changed=false
        if z.attackTime==nil or z.attackCol~=p.col then
            z.attackTime=0;z.attackHit=false;z.attackCol=p.col;changed=true
        end
        z.attackTime=z.attackTime+dt
        if not z.attackHit and z.attackTime>=swing.impact then
            z.attackHit=true;changed=true
            p.hp=p.hp-d.bite*swing.period
            sound(nextBiteA and "enemy_bite_a" or "enemy_bite_b");nextBiteA=not nextBiteA
            if p.hp<=0 then run.plants[tostring((p.row-1)*9+p.col)]=nil end
        end
        if z.attackTime>=swing.period then
            z.attackTime=z.attackTime-swing.period;z.attackHit=false;changed=true
        end
        return changed
    end
    local function targetAhead(z,run,range)
        local target
        for _,p in pairs(run.plants)do
            local x=cellX(p.col)
            if p.hp>0 and p.row==z.row and x<=z.x+20 and x+20>=z.x-range and (not target or p.col>target.col)then target=p end
        end
        return target
    end
    function self.step(z,run,dt,sound)
        local d=definitions[z.kind]
        if d.ability=="vomit" then
            z.phase=z.phase or "advance";z.phaseTime=z.phaseTime or 0
            z.abilityCooldown=math.max(0,(z.abilityCooldown or d.firstCast)-dt)
            if z.phase=="stunned" then
                z.phaseTime=math.max(0,z.phaseTime-dt)
                if z.phaseTime<=0 then z.phase="advance";z.abilityCooldown=d.castInterval end
                return true
            end
            if z.phase=="advance" and z.abilityCooldown<=0 and targetAhead(z,run,d.vomitRange)then
                z.phase="vomit";z.phaseTime=d.vomitDuration;sound("vomit")
            end
            if z.phase=="vomit" then
                local active=math.min(dt,z.phaseTime)
                for key,p in pairs(run.plants)do
                    local x=cellX(p.col)
                    if p.row==z.row and x<=z.x+20 and x+20>=z.x-d.vomitRange then
                        p.hp=p.hp-d.vomitDPS*active
                        if p.hp<=0 then run.plants[key]=nil end
                    end
                end
                z.phaseTime=math.max(0,z.phaseTime-dt)
                if z.phaseTime<=0 then z.phase="stunned";z.phaseTime=d.stunDuration end
                return true
            end
        elseif d.ability=="necromancer" then
            z.shotCooldown=math.max(0,(z.shotCooldown or d.firstShot)-dt)
            if z.shotCooldown<=0 and #run.enemyBolts<80 and targetAhead(z,run,d.range) then
                run.enemyBolts[#run.enemyBolts+1]={x=z.x-18,row=z.row,remaining=d.range,damage=d.shotDamage,speed=d.shotSpeed}
                z.shotCooldown=d.shotInterval;sound("enemy_cast")
            end
            -- Casting does not stop forward movement. Ordinary contact still blocks walking.
        end
        return false
    end
    function self.projectiles(run,dt,sound)
        for i=#run.enemyBolts,1,-1 do
            local b=run.enemyBolts[i];local old=b.x;local dx=math.min(b.speed*dt,b.remaining)
            b.x=b.x-dx;b.remaining=b.remaining-dx
            local target,key
            for k,p in pairs(run.plants)do
                local x=cellX(p.col)
                if p.row==b.row and p.hp>0 and x-20<=old and x+20>=b.x and (not target or p.col>target.col)then target=p;key=k end
            end
            if target then
                target.hp=target.hp-b.damage;if target.hp<=0 then run.plants[key]=nil end;sound("hit_shadow")
            end
            if target or b.remaining<=0 or b.x<70 then table.remove(run.enemyBolts,i)end
        end
    end
    return self
end
