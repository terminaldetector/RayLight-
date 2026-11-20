include("shared.lua")

function ENT:Initialize()
    self:SetRenderBounds(Vector(-28, -28, -28), Vector(28, 28, 28))
end

function ENT:DrawTranslucent()
    if not D6_Art or not D6_Art.DrawProjectile(self) then self:DrawModel() end
end
