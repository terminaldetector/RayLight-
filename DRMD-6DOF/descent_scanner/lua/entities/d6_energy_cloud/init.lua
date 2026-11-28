AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/hunter/misc/sphere025x025.mdl")
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self:DrawShadow(false)
    self:SetNW2Float("D6_CloudUntil",CurTime()+13)
end

function ENT:Think()
    local now=CurTime()
    if now >= self:GetNW2Float("D6_CloudUntil",0) then self:Remove();return end
    local origin=self:GetPos()
    for _,ply in ipairs(player.GetAll()) do
        if not ply:Alive() or not (ply:GetNWBool("D6On") or D6_Mission.IsEpisode()) then continue end
        local center=ply:WorldSpaceCenter()
        if center:DistToSqr(origin) > 112^2 then continue end
        if util.TraceLine({start=origin,endpos=center,filter=ply,mask=MASK_SOLID_BRUSHONLY}).Hit then continue end
        local energy,maxEnergy=D6_Energy.Get(ply),D6_Energy.GetMax(ply)
        local hp,maxHP=ply:Health(),ply:GetMaxHealth()
        local shield,maxShield=ply:GetNWFloat("D6_Shield",0),ply:GetNWFloat("D6_ShieldMax",100)
        if energy >= maxEnergy and hp >= maxHP and shield >= maxShield then continue end
        if energy < maxEnergy then
            D6_Energy.Add(ply,self.D6_Charge or 22)
        end
        if hp < maxHP then
            ply:SetHealth(math.min(maxHP,hp+(self.D6_Healing or 12)))
        end
        if shield < maxShield then
            local repaired=math.min(maxShield,shield+9)
            ply:SetNWFloat("D6_Shield",repaired)
            if ply.D6_Shield then ply.D6_Shield=repaired end
        end
        ply:SetNW2Float("D6_CloudPickup",now)
        ply:EmitSound("items/suitchargeok1.wav",60,113)
        self:Remove()
        return
    end
    self:NextThink(now+.10)
    return true
end
