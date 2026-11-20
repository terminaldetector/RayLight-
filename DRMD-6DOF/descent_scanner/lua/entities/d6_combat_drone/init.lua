AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    -- This is only the neutral mesh used by the procedural chassis renderer.
    -- The entity is NOT a CNPC_CScanner and has no inspection or flash attack.
    self:SetModel("models/combine_scanner.mdl")
    self:SetHullType(HULL_TINY)
    self:SetHullSizeNormal()
    self:PhysicsInitBox(Vector(-12, -12, -10), Vector(12, 12, 18))
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_NPC)
    self:CapabilitiesClear()
    self:CapabilitiesAdd(CAP_MOVE_FLY)
    self:SetNPCClass(CLASS_COMBINE)
    self:SetBloodColor(BLOOD_COLOR_MECH)
    self:SetMaxHealth(100)
    self:SetHealth(100)
    local physics = self:GetPhysicsObject()
    if IsValid(physics) then
        physics:SetMass(80)
        physics:EnableGravity(false)
        physics:Wake()
    end
    D6_Actors.Register(self)
end

-- The D6 role/legacy flight controller owns movement and attack decisions.
-- Returning false prevents CAI_BaseNPC::MaintainSchedule from competing with it.
function ENT:RunAI()
    return false
end

function ENT:OnRemove()
    self:StopSound("ambient/energy/zap_loop1.wav")
    if D6_Actors then D6_Actors.Unregister(self) end
end
