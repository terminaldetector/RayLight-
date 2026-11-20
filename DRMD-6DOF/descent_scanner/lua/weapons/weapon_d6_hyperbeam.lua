AddCSLuaFile()

SWEP.PrintName = "Гиперлуч"
SWEP.Category = "DRMD 6DOF"
SWEP.Spawnable = true
SWEP.Base = "weapon_base"
SWEP.HoldType = "physgun"
SWEP.ViewModel = "models/weapons/v_physics.mdl"
SWEP.WorldModel = "models/weapons/w_physics.mdl"
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.Primary = {ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none"}
SWEP.Secondary = {ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none"}

local READY = 0.64
local MAX_HOLD = 1.8
local ENERGY = 42
local RANGE = 6800
local PULSES = 6
local INTERVAL = 0.088
local COOLDOWN = 2.45

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

local function clear(weapon)
    weapon.D6_ChargeStarted, weapon.D6_Pulses, weapon.D6_NextPulse = nil, nil, nil
    weapon:SetNWFloat("D6_HyperCharge", 0)
    weapon:SetNWBool("D6_HyperFiring", false)
end

function SWEP:Holster()
    if SERVER then
        if self.D6_ChargeStarted then self:SetNextPrimaryFire(CurTime() + 0.18) end
        clear(self)
    end
    return true
end

function SWEP:PrimaryAttack()
    if not SERVER then return end
    local owner = self:GetOwner()
    local now = CurTime()
    if not IsValid(owner) or not owner.D6On or self.D6_ChargeStarted or self.D6_Pulses
        or now < self:GetNextPrimaryFire() then return end
    if D6_Energy.Get(owner) < ENERGY then
        self:SetNextPrimaryFire(now + 0.24)
        owner:EmitSound("buttons/button10.wav", 63, 100)
        return
    end
    self.D6_ChargeStarted = now
    self:SetNextPrimaryFire(now + MAX_HOLD + 0.1)
    owner:EmitSound("ambient/energy/weld1.wav", 69, 82)
end

function SWEP:SecondaryAttack()
    if not SERVER then return end
    self:SetNextSecondaryFire(CurTime() + 0.6)
    if not self.D6_ChargeStarted and not self.D6_Pulses then D6_Wep.DelegateSecondary(self:GetOwner()) end
end

if SERVER then
    util.AddNetworkString("D6_HyperPulse")

    function SWEP:TracePulse(owner)
        local aim = D6_Wep.AimAng(owner)
        local direction = aim:Forward()
        local source, obstruction = D6_Arsenal.EyeClearance(owner, aim, MASK_SHOT)
        if obstruction.Hit then
            if not obstruction.HitWorld and not obstruction.StartSolid then
                D6_Wep.DirectDamage(owner, self, obstruction.Entity, 31, DMG_ENERGYBEAM, direction*780)
            end
            return obstruction.HitPos + obstruction.HitNormal, obstruction.HitPos, obstruction.HitNormal
        end
        local ignored = {owner}
        local destination = source + direction*RANGE
        local trace = {start = source, endpos = destination, filter = ignored, mask = MASK_SHOT}
        for i = 1, 4 do
            local hit = D6_Wep.CombatTrace(trace)
            if not hit.Hit then return source, destination, vector_origin end
            local target = hit.Entity
            if hit.HitWorld or not IsValid(target) then return source, hit.HitPos, hit.HitNormal end
            local actor = target:IsNPC() or target:IsPlayer() or target:IsNextBot()
            if i > 3 then return source, hit.HitPos, hit.HitNormal end
            ignored[#ignored + 1] = target
            D6_Wep.DirectDamage(owner, self, target, 31 * 0.74^(i - 1), DMG_ENERGYBEAM, direction*780)
            if not actor then return source, hit.HitPos, hit.HitNormal end
        end
    end

    function SWEP:Think()
        if not self.D6_ChargeStarted and not self.D6_Pulses then return end
        local owner = self:GetOwner()
        if not IsValid(owner) or not owner.D6On or not owner:Alive() or owner:GetActiveWeapon() ~= self then
            self:Holster()
            return
        end
        local now = CurTime()
        if self.D6_ChargeStarted then
            local elapsed = now - self.D6_ChargeStarted
            local charge = math.Clamp(elapsed/READY, 0, 1)
            if self:GetNWFloat("D6_HyperCharge") ~= charge then self:SetNWFloat("D6_HyperCharge", charge) end
            if owner:KeyDown(IN_ATTACK) and elapsed < MAX_HOLD then return end
            clear(self)
            self:SetNextPrimaryFire(now + 0.22)
            if elapsed < READY or not D6_Wep.TrySpend(self, owner, ENERGY) then return end
            self.D6_Pulses, self.D6_NextPulse = PULSES, now
            self:SetNWBool("D6_HyperFiring", true)
            self:SetNextPrimaryFire(now + COOLDOWN)
            owner:EmitSound("npc/strider/fire.wav", 82, 119)
        end
        if now < self.D6_NextPulse then return end
        if self.D6_Pulses == 0 then clear(self); return end
        local origin, impact, normal = self:TracePulse(owner)
        if self.D6_Pulses == PULSES then
            D6_Wep.MarkShot(self, origin, 0.62)
            D6_Wep.ApplyRecoil(owner, D6_Wep.AimAng(owner):Forward(), 165)
        end
        local recipients = RecipientFilter()
        recipients:AddPlayer(owner)
        recipients:AddPVS(origin)
        recipients:AddPVS(impact)
        net.Start("D6_HyperPulse")
        net.WriteEntity(owner)
        net.WriteVector(origin)
        net.WriteVector(impact)
        net.WriteVector(normal)
        net.WriteBool(self.D6_Pulses == PULSES)
        net.Send(recipients)
        self.D6_Pulses = self.D6_Pulses - 1
        self.D6_NextPulse = now + INTERVAL
    end
end

function SWEP:DrawWorldModel()
    D6_Art.DrawWorldWeapon(self)
end

function SWEP:DrawWorldModelTranslucent() end
