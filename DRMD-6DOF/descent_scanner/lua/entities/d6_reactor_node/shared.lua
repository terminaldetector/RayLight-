ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Abaddon reactor assembly"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "NodeKind")
    self:NetworkVar("Int", 1, "ReactorPhase")
    self:NetworkVar("Float", 0, "Charge")
    self:NetworkVar("Float", 1, "HealthFraction")
    self:NetworkVar("Bool", 0, "NodeEnabled")
end
