-- Xuất "mặt nạ bộ phận" cho shader đổi màu lông: mỗi frame một ảnh, kênh R = mã bộ phận * 32
-- (lớp trên cùng thắng). Mã: 1 đầu (mào, mặt, mỏ, mắt), 2 cổ (bờm), 3 thân + cánh, 4 đuôi,
-- 5 chân, 6 hiệu ứng 09_FX, 7 bóng mờ 01_Afterimage. 00_Shadow bỏ qua. Không lưu file .aseprite.
-- aseprite -b <file>.aseprite --script-param out=<thư mục> --script export_fighter_mask.lua
local spr = app.activeSprite
local out = app.params.out
local roles = {
  ["01_Afterimage"] = 7, ["09_FX"] = 6,
  ["02_Wing_Far"] = 3, ["03_Leg_Far"] = 5, ["04_Tail"] = 4, ["05_Body"] = 3, ["06_Leg_Near"] = 5,
  ["07_Head"] = 1, ["08_Wing_Near"] = 3,
  ["Tail"] = 4, ["Right_leg"] = 5, ["Body"] = 3, ["Left_leg"] = 5, ["Wing"] = 3, ["Neck"] = 2, ["Head"] = 1,
}
local pc = app.pixelColor
local indexed = spr.colorMode == ColorMode.INDEXED
local transparent = spr.transparentColor
for i = 1, #spr.frames do
  local mask = Image(spr.width, spr.height, ColorMode.RGB)
  mask:clear(pc.rgba(0, 0, 0, 0))
  for _, layer in ipairs(spr.layers) do
    local role = roles[layer.name]
    if role ~= nil and layer.isVisible then
      local cel = layer:cel(i)
      if cel ~= nil then
        local img = cel.image
        local ox, oy = cel.position.x, cel.position.y
        for it in img:pixels() do
          local v = it()
          local solid
          if indexed then
            solid = v ~= transparent
          else
            solid = pc.rgbaA(v) > 0
          end
          if solid then
            local x, y = ox + it.x, oy + it.y
            if x >= 0 and y >= 0 and x < spr.width and y < spr.height then
              mask:drawPixel(x, y, pc.rgba(role * 32, 0, 0, 255))
            end
          end
        end
      end
    end
  end
  mask:saveAs(string.format("%s/mask_%03d.png", out, i))
end
