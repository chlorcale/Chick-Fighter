-- Xuất từng layer lá (theo thứ tự vẽ dưới→trên), khử trùng lặp ảnh giữa các frame.
local spr = app.activeSprite
local out = app.params.out
local skip = { ["05_Collision"]=true, ["06_Guide"]=true, ["08_Ve_Tay"]=true }
local lines = {}
local idx = 0
local function topname(l)
  local t = l
  while t.parent ~= spr do t = t.parent end
  return t.name
end
local function visible(l)
  local t = l
  while t ~= spr do
    if not t.isVisible then return false end
    t = t.parent
  end
  return true
end
local function walk(layers)
  for _, l in ipairs(layers) do
    if l.isGroup then
      if not skip[l.name] then walk(l.layers) end
    elseif visible(l) and not skip[topname(l)] then
      idx = idx + 1
      local uniq = {}
      local n = 0
      local frames = {}
      for fi = 1, #spr.frames do
        local cel = l:cel(fi)
        if cel == nil or cel.image:isEmpty() then
          frames[#frames + 1] = "-1"
        else
          local key = cel.image.bytes
          local u = uniq[key]
          if u == nil then
            u = n
            n = n + 1
            uniq[key] = u
            cel.image:saveAs(string.format("%s/L%03d_%02d.png", out, idx, u))
          end
          local op = math.floor((cel.opacity or 255) * (l.opacity or 255) / 255)
          frames[#frames + 1] = string.format("%d:%d:%d:%d", u, cel.position.x, cel.position.y, op)
        end
      end
      local parentname = l.parent ~= spr and l.parent.name or ""
      lines[#lines + 1] = string.format("%d\t%s\t%s\t%s\t%d\t%s", idx, topname(l), parentname, l.name, n, table.concat(frames, " "))
    end
  end
end
walk(spr.layers)
local f = io.open(out .. "/manifest.tsv", "w")
f:write(table.concat(lines, "\n"))
f:close()
