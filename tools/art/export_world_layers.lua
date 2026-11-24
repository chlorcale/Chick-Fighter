-- Xuất bản đồ thế giới mở rộng (Chick_Fighter_World_Map_Expanded.aseprite) cho build_world_map.py.
-- Chạy: aseprite -b <file.aseprite> --script-param out=<thư_mục> --script export_world_layers.lua
-- KHÔNG sửa file .aseprite (chỉ đọc, không lưu).
--
-- Kết quả trong <out>:
--   manifest.tsv : mỗi dòng một layer lá hiện (thứ tự vẽ dưới→trên)
--                  idx \t nhóm_gốc \t đường_dẫn_nhóm \t tên \t số_ảnh_khác_nhau \t 96 token "u:x:y:op" hoặc "-1"
--   L####_##.png : ảnh duy nhất thứ ## của layer ####
--   hidden.tsv   : layer lá bị ẩn (bỏ qua) – để báo cáo
--   coll/C##.png + coll.tsv : từng layer lá của 05_Collision (frame 1) + vị trí
--   guide/G##.png + guide.tsv : từng layer lá của 06_Guide / 08_Ve_Tay (frame 1) + vị trí
-- Khử trùng lặp ảnh giữa các frame: cel liên kết (cùng image.id) dùng lại ngay; còn lại so bytes.
local spr = app.activeSprite
local out = app.params.out
local skip = { ["05_Collision"]=true, ["06_Guide"]=true, ["08_Ve_Tay"]=true }
local lines, hidden, coll, guide = {}, {}, {}, {}
local idx = 0
local function top(l)
  local t = l
  while t.parent ~= spr do t = t.parent end
  return t
end
local function grouppath(l)
  local p = ""
  local t = l.parent
  while t ~= spr do
    p = (p == "") and t.name or (t.name .. "/" .. p)
    t = t.parent
  end
  return p
end
local function visible(l)
  local t = l
  while t ~= spr do
    if not t.isVisible then return false end
    t = t.parent
  end
  return true
end
local function save_first(l, dir, list, prefix)
  local n = #list + 1
  local cel = l:cel(1)
  if cel == nil or cel.image:isEmpty() then
    list[n] = string.format("%d\t%s\t%s\t-1\t-1\t%s", n, grouppath(l), l.name, tostring(l.isVisible))
    return
  end
  cel.image:saveAs(string.format("%s/%s/%s%02d.png", out, dir, prefix, n))
  list[n] = string.format("%d\t%s\t%s\t%d\t%d\t%s", n, grouppath(l), l.name, cel.position.x, cel.position.y, tostring(l.isVisible))
end
local function walk(layers)
  for _, l in ipairs(layers) do
    local t = top(l)
    if l.isGroup then
      walk(l.layers)
    elseif t.name == "05_Collision" then
      save_first(l, "coll", coll, "C")
    elseif t.name == "06_Guide" or t.name == "08_Ve_Tay" then
      save_first(l, "guide", guide, "G")
    elseif not visible(l) then
      hidden[#hidden + 1] = grouppath(l) .. "/" .. l.name
    elseif not skip[t.name] then
      idx = idx + 1
      local by_id, by_bytes = {}, {}
      local n = 0
      local frames = {}
      for fi = 1, #spr.frames do
        local cel = l:cel(fi)
        if cel == nil or cel.image:isEmpty() then
          frames[#frames + 1] = "-1"
        else
          local img = cel.image
          local u = by_id[img.id]
          if u == nil then
            local key = img.width .. "x" .. img.height .. ":" .. img.bytes
            u = by_bytes[key]
            if u == nil then
              u = n
              n = n + 1
              by_bytes[key] = u
              img:saveAs(string.format("%s/L%04d_%02d.png", out, idx, u))
            end
            by_id[img.id] = u
          end
          local op = math.floor((cel.opacity or 255) * (l.opacity or 255) / 255)
          frames[#frames + 1] = string.format("%d:%d:%d:%d", u, cel.position.x, cel.position.y, op)
        end
      end
      lines[#lines + 1] = string.format("%d\t%s\t%s\t%s\t%d\t%s", idx, t.name, grouppath(l), l.name, n, table.concat(frames, " "))
    end
  end
end
walk(spr.layers)
local function write(name, list)
  local f = io.open(out .. "/" .. name, "w")
  f:write(table.concat(list, "\n"))
  f:close()
end
write("manifest.tsv", lines)
write("hidden.tsv", hidden)
write("coll.tsv", coll)
write("guide.tsv", guide)
local f = io.open(out .. "/size.txt", "w")
f:write(string.format("%d %d %d %d", spr.width, spr.height, #spr.frames, spr.frames[1].duration * 1000))
f:close()
