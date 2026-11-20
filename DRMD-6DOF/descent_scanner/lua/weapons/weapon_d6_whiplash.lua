AddCSLuaFile()

SWEP.PrintName = "Луч сцепления"
SWEP.Category = "Half-Life: Abaddon"
SWEP.Spawnable = true
SWEP.Base = "weapon_base"
SWEP.HoldType = "physgun"
SWEP.ViewModel = "models/weapons/v_physics.mdl"
SWEP.WorldModel = "models/weapons/w_physics.mdl"
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.Primary = {ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none"}
SWEP.Secondary = {ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none"}

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

function SWEP:PrimaryAttack()
    if SERVER then D6_Mobility.Attach(self:GetOwner(), self) end
    self:SetNextPrimaryFire(CurTime() + 0.25)
end

function SWEP:SecondaryAttack()
    if SERVER then D6_Mobility.Attach(self:GetOwner(), self, true) end
    self:SetNextSecondaryFire(CurTime() + 0.25)
end

function SWEP:Holster()
    local owner = self:GetOwner()
    if SERVER and IsValid(owner) then D6_Mobility.Release(owner, self) end
    return true
end

function SWEP:DrawWorldModel()
    D6_Art.DrawWorldWeapon(self)
end

function SWEP:DrawWorldModelTranslucent() end
