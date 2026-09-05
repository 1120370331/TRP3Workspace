
-- Written by Ovokalia-MoonGuard in 2023, 2024

scale = 2

if args._G == nil then
  effect("text", args, "No globals...", 1)
  return
end
if args._G.ovoframe ~= nil then
  args._G.ovoframe:Hide()
  args._G.ovoframe = nil
end
if args._G.ovoframe == nil then
  ovoframe = args._G.CreateFrame("Frame", nil, args._G.TRP3_DocumentFrame)
  ovoframe:SetPoint("TOP", 0, -100 * scale - 100)
  ovoframe:SetSize(100 * scale, 100 * scale)
  ovoframe:Show()
  ovotable = {}
  for ovox = 10, 90 do
    ovotable[ovox] = {}
    for ovoy = 10, 90 do
      -- 用 CreateTexture 代替 CreateLine
      local texture = ovoframe:CreateTexture(nil, "BACKGROUND")
      ovotable[ovox][ovoy] = texture
      texture:SetPoint("TOPLEFT", ovox * scale, ovoy * scale)
      texture:SetSize(scale, scale) -- 用方块代替线条
    end
  end
  args._G.ovoframe = ovoframe
  args._G.ovotable = ovotable
else
  ovoframe = args._G.ovoframe
  ovotable = args._G.ovotable
end

page = 1
setVar(args, "o", "shown", "打开")
ovobase = 0
ovox = 10
ovoy = 90
ovor = -1
ovob = -1
ovog = -1
ovodoc = args.class.IN.doc.PA[page].TX
for s in ovodoc:gmatch("[^%s]+") do
  if ovobase == 0 then
    if s == "255" then
      ovobase = 1
    end
  elseif ovor == -1 then
    ovor = 0 + s
  elseif ovob == -1 then
    ovob = 0 + s
  elseif ovog == -1 then
    ovog = 0 + s
    -- 修改颜色应用到矩形上
    ovotable[ovox][ovoy]:SetColorTexture(ovor / 255, ovob / 255, ovog / 255, 1)
    ovor = -1
    ovob = -1
    ovog = -1
    ovox = ovox + 1
    if ovox > 89 then
      ovox = 10
      ovoy = ovoy - 1
    end
  end
end