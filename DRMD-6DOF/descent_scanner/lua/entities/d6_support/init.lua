AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    -- No npc_cscanner base, native schedules, flash attack or hitscan weapon.
    self:SetModel("models/hunter/misc/sphere025x025.mdl")
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self:SetCollisionBounds(Vector(-28,-28,-28),Vector(28,28,28))
    self:DrawShadow(false)
end
