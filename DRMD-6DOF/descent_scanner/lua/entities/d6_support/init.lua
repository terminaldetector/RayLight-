AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local definition = D6_Supports and D6_Supports.Definitions[self.D6_SupportKind]
    local model = definition and definition.model
    local hasStudioModel = model and util.IsValidModel(model)
    self:SetModel(hasStudioModel and model or "models/hunter/misc/sphere025x025.mdl")
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self:SetCollisionBounds(Vector(-28,-28,-28),Vector(28,28,28))
    self:DrawShadow(hasStudioModel == true)
end
