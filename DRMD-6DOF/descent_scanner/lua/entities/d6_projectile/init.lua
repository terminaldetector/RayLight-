AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local model=self.D6_Model
    if not model or not file.Exists(model,"GAME") then model="models/hunter/misc/sphere025x025.mdl" end
    self:SetModel(model)
    if self.D6_PhysRadius then
        local radius = self.D6_PhysRadius
        local bounds = Vector(radius,radius,radius)
        self:PhysicsInitSphere(radius, "metal")
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetCollisionBounds(-bounds,bounds)
    else
        self:SetSolid(SOLID_NONE)
        self:SetMoveType(MOVETYPE_NONE)
    end
    self:DrawShadow(false)
end

function ENT:PhysicsCollide(data)
    if self.D6_PhysicsImpact then self:D6_PhysicsImpact(data) end
end
