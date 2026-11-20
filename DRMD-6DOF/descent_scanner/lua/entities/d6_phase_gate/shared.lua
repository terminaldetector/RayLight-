ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Abaddon Phase Gate"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Polarity")
    self:NetworkVar("Float", 0, "EndsAt")
    self:NetworkVar("Entity", 0, "LinkedGate")
end
