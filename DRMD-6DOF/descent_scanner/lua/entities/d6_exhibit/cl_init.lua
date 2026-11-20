include("shared.lua")
function ENT:Initialize()
    self:SetRenderBounds(Vector(-52,-52,-48),Vector(52,52,48))
end
function ENT:DrawTranslucent()
    if not D6_Art then return end
    local finish = self:GetNW2Float("D6_ExhibitEnd",0)
    if finish <= CurTime() then return end
    local angle = self:GetAngles()
    angle.y = angle.y + math.sin(CurTime()*0.58)*26
    local scale = self:GetNW2Float("D6_ExhibitScale",0.72)
    D6_Art.DrawDrone(self:GetNW2String("D6_ExhibitModel",""),self:GetPos(),angle,0.87,true,scale)
end
