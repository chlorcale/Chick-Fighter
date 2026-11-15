-- Xuất mọi frame của một sheet chiến kê (128×112) – dùng chung cho mọi bộ chiêu (kit).
-- Ẩn layer bóng 00_Shadow (engine tự vẽ bóng), ghi thời lượng frame + tag vào meta.txt.
-- Không lưu lại file .aseprite (chỉ đọc).
-- aseprite -b <file>.aseprite --script-param out=<thư mục> --script export_fighter.lua
local spr = app.activeSprite
local out = app.params.out
for _, l in ipairs(spr.layers) do
  if l.name == "00_Shadow" then l.isVisible = false end
end
local meta = {}
for i = 1, #spr.frames do
  local img = Image(spr.spec)
  img:drawSprite(spr, i)
  img:saveAs(string.format("%s/body_%03d.png", out, i))
  meta[#meta + 1] = string.format("frame\t%d\t%d", i, math.floor(spr.frames[i].duration * 1000 + 0.5))
end
for _, t in ipairs(spr.tags) do
  meta[#meta + 1] = string.format("tag\t%s\t%d\t%d", t.name, t.fromFrame.frameNumber, t.toFrame.frameNumber)
end
for _, l in ipairs(spr.layers) do
  meta[#meta + 1] = string.format("layer\t%s", l.name)
end
local f = io.open(out .. "/meta.txt", "w")
f:write(table.concat(meta, "\n"))
f:close()
