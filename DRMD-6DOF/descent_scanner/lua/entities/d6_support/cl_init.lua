include("shared.lua")

function ENT:Initialize()
    self:SetRenderBounds(Vector(-32,-32,-32),Vector(32,32,32))
end

function ENT:Draw()
    if not D6_Supports or not D6_Art then return end
    local def=D6_Supports.Definitions[self:GetNWString("D6_SupportKind","")]
    if not def then return end
    local power=self:GetNWFloat("D6_SupportPower",0)
    D6_Art.Draw(def.mesh,self:GetPos(),self:GetAngles(),1,def.color,0.22+0.48*power,true)
end
