include("shared.lua")
local glow=Material("sprites/light_glow02_add")

function ENT:Initialize()
    self:SetRenderBounds(Vector(-96,-96,-96),Vector(96,96,96))
end

function ENT:DrawTranslucent()
    local now=CurTime()
    local left=self:GetNW2Float("D6_CloudUntil",0)-now
    if left<=0 then return end
    local fade=math.Clamp(left/1.7,0,1)
    local origin=self:GetPos()
    render.SetMaterial(glow)
    render.DrawSprite(origin,102,102,Color(115,182,158,44*fade))
    render.DrawSprite(origin,49,49,Color(167,227,188,104*fade))
    for i=1,12 do
        local phase=i*2.4+now*(.64+(i%3)*.24)
        local radial=26+(i%4)*7+math.sin(phase+i)*6
        local offset=Vector(math.cos(phase)*radial,math.sin(phase)*radial,math.sin(phase*1.3)*radial*.75)
        local size=3+(i%5)*1.3
        render.DrawSprite(origin+offset,size,size,Color(147,222,183,(60+i*4)*fade))
    end
end
