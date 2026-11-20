AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local radius = self.D6_Radius or 12
    local hull = Vector(radius,radius,radius)
    -- A studio model gives Source an entity handle. The scripted draw pass emits the DRMD mesh.
    local model=self.D6_Model
    if not model or not file.Exists(model,"GAME") then model="models/hunter/misc/sphere025x025.mdl" end
    self:SetModel(model)
    self:PhysicsInitSphere(radius, "metal")
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionBounds(-hull,hull)
    self:DrawShadow(false)
end
