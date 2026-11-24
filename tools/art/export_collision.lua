local spr = app.activeSprite
for _,l in ipairs(spr.layers) do l.isVisible = (l.name == "05_Collision") end
local img = Image(spr.spec)
img:drawSprite(spr, 1)
img:saveAs(app.params.out)
