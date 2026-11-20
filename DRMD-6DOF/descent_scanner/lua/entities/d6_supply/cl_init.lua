include("shared.lua")
local glow=Material("sprites/light_glow02_add")

function ENT:DrawTranslucent()
    if not D6_Art or not D6_Supplies then return end
    local spec=D6_Supplies.Types[self:GetNW2String("D6_SupplyType","")]
    if not spec then return end
    local now=CurTime()
    local pos=self:GetPos()+Vector(0,0,math.sin(now*2.8)*4)
    D6_Art.Draw("supply",pos,Angle(0,(now*46)%360,0),1,spec.color,.92,true)
    render.SetMaterial(glow)
    render.DrawSprite(pos,28,28,Color(spec.color.r,spec.color.g,spec.color.b,166))
end
