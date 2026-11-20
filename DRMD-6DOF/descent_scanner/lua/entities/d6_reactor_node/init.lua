AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local coolant = self:GetNodeKind() == 1
    local bounds = coolant and Vector(35,35,41) or Vector(58,58,44)
    self:SetModel("models/drmd/supply.mdl")
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_BBOX)
    self:SetCollisionBounds(-bounds, bounds)
    self:DrawShadow(false)
    self.D6_EpisodeTarget = true
end

function ENT:OnTakeDamage(damage)
    D6_Reactor.Hit(self, damage)
end
