AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/hunter/plates/plate025x025.mdl")
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
end

function ENT:Think()
    if not IsValid(self:GetOwner()) or CurTime() >= self:GetEndsAt() then
        self:Remove()
        return
    end
    self:NextThink(CurTime() + 0.25)
    return true
end
