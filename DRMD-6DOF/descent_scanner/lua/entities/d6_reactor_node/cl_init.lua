include("shared.lua")

function ENT:Initialize()
    local bounds = Vector(174, 174, 180)
    self:SetRenderBounds(-bounds, bounds)
end

function ENT:DrawTranslucent()
    if D6_ReactorVisual then D6_ReactorVisual.Draw(self) end
end
