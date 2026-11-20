include("shared.lua")

function ENT:Draw()
    -- D6_Art installs its variant renderer through RenderOverride.
    -- Keep a visible neutral model until the variant arrives over the network.
    self:DrawModel()
end
