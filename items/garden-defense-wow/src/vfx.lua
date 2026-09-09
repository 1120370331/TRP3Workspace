-- Visual recipes only: damage and slow are settled by game.lua before these calls.
return function(ctx)
    local serial=0
    local self={}
    local function emit(ids,x,y,scale)
        serial=serial+1
        for i,id in ipairs(ids)do
            ctx.fx.burst(id,{x=x,y=y,scale=scale or 1,seed=serial*131+i})
        end
    end
    function self.impact(ice,spore,x,y)
        emit(spore and {"spore_flash","spore_dust","spore_wisp"}
            or ice and {"ice_flash","ice_shards","ice_chips"} or {"pea_flash","pea_splash"},x,y)
    end
    function self.explosion(x,y,radius)
        emit({"explosion_flash","explosion_ring","explosion_sparks","explosion_smoke"},x,y,
            math.max(.65,math.min(1.5,radius/100)))
    end
    return self
end
