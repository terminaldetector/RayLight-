-- ═══════════════════════════════════════════════════════════
-- weapon_d6_warp.lua — БОЕВОЙ ВАРП (модуль рывка-блинка)
--
--   Cat F: оружие движения. Короткий блинк на 700u по прицелу
--   (проверка корпусом). Оставляет разрыв тёмной энергии в точке
--   входа И выхода: 100 + AoE в 200u (exotic). И атака, и уход —
--   репозиционирование сквозь строй с уроном на обоих концах.
--   КД 2.5 с, 30 энергии.
--
--   Фреймворк: d6_weapon_core (Muzzle/SplashDamage), d6_energy
--   (TryConsume), d6_shield (exotic → energy-резист).
-- ═══════════════════════════════════════════════════════════
AddCSLuaFile()

SWEP.PrintName      = "БОЕВОЙ ВАРП"
SWEP.Author         = "Half-Life: Abaddon"
SWEP.Category       = "Descent"
SWEP.Slot           = 6
SWEP.SlotPos        = 2
SWEP.Spawnable      = false
SWEP.AdminSpawnable = false
SWEP.Base           = "weapon_base"
SWEP.HoldType       = "physgun"
SWEP.ViewModel      = "models/weapons/v_physics.mdl"
SWEP.WorldModel     = "models/weapons/w_physics.mdl"
SWEP.UseHands       = false
SWEP.DrawAmmo       = false
SWEP.DrawCrosshair  = false
SWEP.Primary.ClipSize      = -1
SWEP.Primary.DefaultClip   = -1
SWEP.Primary.Automatic     = false
SWEP.Primary.Ammo          = "none"
SWEP.Secondary.ClipSize    = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic   = false
SWEP.Secondary.Ammo        = "none"

if SERVER and not _D6_WARP_NET then
    util.AddNetworkString("D6_WarpBlink")
    _D6_WARP_NET = true
    util.PrecacheSound("ambient/machines/teleport1.wav")
    util.PrecacheSound("ambient/levels/labs/electric_explosion1.wav")
end

local ENERGY_COST  = 30
local COOLDOWN     = 2.5
local BLINK_DIST   = 700
local RUPTURE_DMG  = 100
local RUPTURE_RAD  = 200

function SWEP:Initialize() self:SetWeaponHoldType(self.HoldType) end
function SWEP:Deploy()  return true end
function SWEP:Holster() return true end

local function Rupture(owner, pos)
    D6_Wep.SplashDamage(owner, owner, pos, 0, RUPTURE_DMG, RUPTURE_RAD,
        D6_DAMAGE.exotic.dmgType, 4000, owner)
    local ef = EffectData(); ef:SetOrigin(pos); ef:SetScale(2.5); ef:SetMagnitude(RUPTURE_RAD)
    util.Effect("cball_explode", ef)
    sound.Play("ambient/levels/labs/electric_explosion1.wav", pos, 95, 95)
end

function SWEP:PrimaryAttack()
    if not SERVER then return end
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner.D6On or CurTime() < self:GetNextPrimaryFire() then return end

    local dir = D6_Wep.ShootAng(owner):Forward()
    local origin = D6_Wep.FindBlink(owner, dir, BLINK_DIST)
    if not origin or not D6_Wep.TrySpend(self, owner, ENERGY_COST) then return end
    self:SetNextPrimaryFire(CurTime() + COOLDOWN)
    local center = owner:WorldSpaceCenter()
    local dest = origin + (center - owner:GetPos())

    D6_Mobility.Release(owner)
    Rupture(owner, center)
    owner:SetPos(origin)
    D6_Wep.MotionFX(center, dest, 2)
    local before = D6_Wep.ShipVel(owner)
    owner.D6Vel = before + dir*math.max(0, 800-before:Dot(dir))
    D6_Mobility.Carry(owner, 0.56)
    Rupture(owner, dest)

    D6_Wep.MarkShot(self, nil, 0.55)
    net.Start("D6_WarpBlink")
        net.WriteVector(center)
        net.WriteVector(dest)
    net.Broadcast()

    owner:EmitSound("ambient/machines/teleport1.wav", 95, 120)
end

function SWEP:SecondaryAttack()
    if not SERVER then return end
    self:SetNextSecondaryFire(CurTime() + 0.6)
    D6_Wep.DelegateSecondary(self:GetOwner())
end

if CLIENT then
    local BEAM_MAT = Material("cable/xbeam")

    net.Receive("D6_WarpBlink", function()
        local src  = net.ReadVector()
        local dst  = net.ReadVector()
        local key  = "D6_WarpStreak_" .. CurTime() .. "_" .. math.random(99999)
        local born = CurTime()
        local dur  = 0.28
        hook.Add("PostDrawTranslucentRenderables", key, function(d, s)
            if d or s then return end
            local age = CurTime() - born
            if age >= dur then hook.Remove("PostDrawTranslucentRenderables", key); return end
            local a = (1 - age / dur) * 255
            render.SetMaterial(BEAM_MAT)
            render.DrawBeam(src, dst, 8, 0, 1, Color(150, 60, 220, a))
            render.DrawBeam(src, dst, 2, 0, 1, Color(220, 180, 255, a))
        end)
    end)

    function SWEP:DrawHUD()
        D6_Wep.DrawReadyHUD(self:GetOwner(), self, "БОЕВОЙ ВАРП", Color(170, 90, 235), COOLDOWN)
    end
end

function SWEP:DrawWorldModel()
    if D6_Art then D6_Art.DrawWorldWeapon(self) else self:DrawModel() end
end
function SWEP:DrawWorldModelTranslucent() end

print("[D6] weapon_d6_warp.lua loaded")
