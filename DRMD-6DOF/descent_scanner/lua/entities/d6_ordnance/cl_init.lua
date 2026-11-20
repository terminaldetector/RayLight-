include("shared.lua")

function ENT:Initialize()
    self:SetRenderBounds(Vector(-25,-25,-25), Vector(25,25,25))
end

function ENT:DrawTranslucent()
    if D6_Art then D6_Art.DrawProjectile(self) end
end
