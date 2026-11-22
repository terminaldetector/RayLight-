if SERVER then AddCSLuaFile() end

SWEP.Base = "weapon_base"
SWEP.PrintName = "Фазовая пушка"
SWEP.Category = "Half-Life: Abaddon / Оружие"
SWEP.ScriptedEntityType = "d6_weapon"
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.Slot = 4
SWEP.SlotPos = 14
SWEP.ViewModel = "models/weapons/v_physics.mdl"
SWEP.WorldModel = "models/weapons/w_physics.mdl"
SWEP.HoldType = "physgun"
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.Primary = {ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none"}
SWEP.Secondary = {ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none"}

function SWEP:Initialize() self:SetHoldType(self.HoldType) end

local function openGate(wep, polarity)
    local owner = wep:GetOwner()
    if not IsValid(owner) or not owner.D6On or not D6_Session.IsArena() then return end
    if not D6_Gates.Place(owner, wep, polarity) then
        wep:SetNextPrimaryFire(CurTime() + 0.23)
        wep:SetNextSecondaryFire(CurTime() + 0.23)
        owner:EmitSound("buttons/button10.wav", 62, 98)
        return
    end
    local ready = CurTime() + 0.48
    wep:SetNextPrimaryFire(ready)
    wep:SetNextSecondaryFire(ready)
end

function SWEP:PrimaryAttack()
    if SERVER then openGate(self, 1) end
end

function SWEP:SecondaryAttack()
    if SERVER then openGate(self, 2) end
end

function SWEP:DrawWorldModel()
    if D6_Art then D6_Art.DrawWorldWeapon(self) else self:DrawModel() end
end
