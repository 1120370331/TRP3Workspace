return (function()
    -- Hand-authored pixel silhouettes; no external image files or copyrighted art.
    local palette={
        g={.31,.67,.18,1},G={.55,.86,.27,1},d={.14,.32,.10,1},w={1,.97,.81,1},k={.10,.12,.10,1},
        y={1,.77,.18,1},o={.89,.43,.12,1},b={.45,.25,.12,1},B={.74,.47,.23,1},r={.87,.20,.21,1},
        c={.26,.72,.88,1},C={.65,.93,1,1},p={.50,.30,.66,1},P={.77,.56,.87,1},s={.57,.64,.44,1},
        t={.44,.40,.33,1},a={.67,.70,.65,1},n={.27,.36,.39,1}}
    local spriteRows={
        pea={"  GGGG      "," GGGGGG     "," GGGkGGGGGG "," GGGwGGGGkG ","  GGGGGGGGG ","   gggg     ","    gg      ","    gg      "," gg gg gg   ","  gggggg    "},
        snow={"  CCCC      "," CCCCCC     "," CCCkCCCCCC "," CCCwCCCCkC ","  CCCCCCCCC ","   cccc     ","    cc      ","    cc      "," cc cc cc   ","  cccccc    "},
        repeater={" dddGGG     "," dGGGGGG    "," GGGkGGGGGG "," GGGwGGGGkG ","  GGGGGGGGG ","   ggggGGGG ","    ggGGGkG ","    gg GGGG "," gg gg gg   ","  gggggg    "},
        sunflower={"   y yy     "," yyoooo yy  "," yowwwwooy  "," yo kwk oy  "," yo wkw oy  "," yyoooo yy  ","   y yy     ","    gg      "," gg gg gg   ","  gggggg    "},
        cherry={"    gg gg   ","     ggg    ","    bb bb   ","  rrr   rrr "," rwwrr rwwrr"," rrkrr rrkrr"," rrrrr rrrrr","  rrr   rrr ","            ","            "},
        wall={"    BBBB    ","  BBBBBBBB  "," BBBBBBBBBB "," BBwkBBwkBB "," BBBBBBBBBB "," BBBBbbBBBB "," BBBBBBBBBB "," BBbBBBBbBB ","  BBBBBBBB  ","   bbbbbb   "},
        mine={"     r      ","     b      ","    BBB     ","  BBBBBBB   "," BBwkBwkBB  "," BBBBBBBBB  ","  bbbbbbb   ","            ","            ","            "},
        chomper={"   PPPPP    ","  PPPPPPP   "," PPPwkPPPP  "," PPPPPPPPPP "," PPkwkwkwkw ","  PPkkkkkk  ","   PPPPPP   ","     gg     ","  gg gg gg  ","   gggggg   "},
        puff={"            ","            ","    PPPP    ","  PPwwPPPP  "," PPPPPPwwPP "," pppppppppp ","   wwkwkw   ","   wwwwwwww ","    wwwwwwk ","    wwwwww  "},
        sunshroom={"            ","    yyyy    ","  yyoo yyyy "," yyyyyyyoyy "," oooooooooo ","   wwwwww   ","   wwkwkw   ","   wwwwww   ","    wwww    ","    wwww    "},
        zombie={"   ssss     ","  ssssss    ","  swkswk    ","  ssssss    ","   skww     ","  tttttt    "," sttrttttss "," s ttntt  s ","   nnnn     ","   nn nn    ","  bb  bb    "}
    }
    local sprites={}
    for id,rows in pairs(spriteRows)do
        local runs={}
        for y,line in ipairs(rows)do
            local x=1
            while x<=#line do
                local key=line:sub(x,x);local last=x
                while last<#line and line:sub(last+1,last+1)==key do last=last+1 end
                if palette[key] then runs[#runs+1]={x=x-1,y=y-1,w=last-x+1,color=palette[key]}end
                x=last+1
            end
        end
        sprites[id]=runs
    end
    return {palette=palette,sprites=sprites}
end)()
