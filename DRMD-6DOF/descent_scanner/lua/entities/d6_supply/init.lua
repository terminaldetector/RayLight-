AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/drmd/supply.mdl")
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self:DrawShadow(false)
    self:SetNW2String("D6_SupplyType",self.D6_Payload or "")
end

function ENT:Think()
    local origin=self:GetPos()
    if self.D6_Pilot and not IsValid(self.D6_Pilot) then self:Remove();return end
    for _,ply in ipairs(player.GetAll()) do
        if not ply:Alive() or not ply.D6On or (self.D6_Pilot and self.D6_Pilot~=ply) then continue end
        local center=ply:WorldSpaceCenter()
        if center:DistToSqr(origin)>58^2 then continue end
        if util.TraceLine({start=origin,endpos=center,mask=MASK_SOLID_BRUSHONLY}).Hit then continue end
        local result=D6_Supplies.Collect(self,ply)
        if not result then continue end
        ply:SetNW2String("D6_SupplyNotice",result)
        ply:SetNW2Float("D6_SupplyAt",CurTime())
        ply:EmitSound("items/suitchargeok1.wav",65,108)
        self:Remove()
        return
    end
    self:NextThink(CurTime()+.1)
    return true
end
