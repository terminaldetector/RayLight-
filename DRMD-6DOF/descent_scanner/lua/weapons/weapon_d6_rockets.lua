-- ═══════════════════════════════════════════════════════════
-- weapon_d6_rockets.lua — РАКЕТЫ, 4 сабрежима
--   0 = ×1 ПРЯМАЯ   1 = ×3 ЗАЛП
--   2 = ×6 НАВЕДЕНИЕ   3 = ☢ АТОМКА
--   Умное наведение: 60% вероятность на цель с наибольшим HP,
--   ×6 режим — распределяет цели между ракетами.
-- ═══════════════════════════════════════════════════════════
AddCSLuaFile()

SWEP.PrintName       = "РАКЕТЫ"
SWEP.Author          = "Descent 6DOF"
SWEP.Category        = "Descent"
SWEP.Slot            = 4
SWEP.SlotPos         = 0
SWEP.Spawnable       = true
SWEP.AdminSpawnable  = true
SWEP.Base            = "weapon_base"
SWEP.HoldType        = "physgun"
SWEP.ViewModel       = "models/weapons/v_physics.mdl"
SWEP.WorldModel      = "models/weapons/w_physics.mdl"
SWEP.UseHands        = false
SWEP.DrawAmmo        = false
SWEP.DrawCrosshair   = false
SWEP.Primary.ClipSize    = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic   = true
SWEP.Primary.Ammo        = "none"
SWEP.Secondary.ClipSize    = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic   = false
SWEP.Secondary.Ammo        = "none"

local MDL_ROCKET = "models/weapons/w_missile.mdl"
if SERVER then
    util.PrecacheModel(MDL_ROCKET)
    util.PrecacheSound("weapons/rpg/rocketfire1.wav")
    util.PrecacheSound("weapons/rpg/rocket_explode.wav")
end

local ENERGY_COST = 20
local MODE_NAMES = {"Одиночная", "Веер", "Самонаведение", "Тяжёлый заряд"}

function SWEP:GetDRMDModeName()
    return MODE_NAMES[self:GetNWInt("D6_RktSub", 0) + 1] or MODE_NAMES[1]
end

local function lock(origin, direction, owner)
    local selected, score = nil, 0
    for _, candidate in ipairs(ents.FindInSphere(origin, 2450)) do
        if D6_Wep.Targetable(owner, candidate) then
            local offset = candidate:WorldSpaceCenter() - origin
            local alignment = direction:Dot(offset:GetNormalized())
            local rating = alignment - offset:Length()/3800
            if alignment > 0.35 and rating > score then
                local tr = D6_Wep.CombatTrace({start = origin, endpos = candidate:WorldSpaceCenter(), filter = owner, mask = MASK_SHOT})
                if not tr.Hit or tr.Entity == candidate then selected, score = candidate, rating end
            end
        end
    end
    return selected
end

local function fire(wep, owner, pos, dir, mode)
    local seek, heavy = mode == 2, mode == 3
    local speed = ({3000, 2650, 2200, 2000})[mode + 1]
    local seekAt, target = 0, nil
    local color = seek and Color(110, 213, 250) or Color(255, 159, 82)
    local function steer(_, origin, velocity, dt)
        if CurTime() >= seekAt then
            seekAt = CurTime() + 0.18
            target = lock(origin, velocity:GetNormalized(), owner)
        end
        if not IsValid(target) then return velocity end
        local aim = target:WorldSpaceCenter() + target:GetVelocity()*0.12 - origin
        return LerpVector(dt*3.5, velocity:GetNormalized(), aim:GetNormalized()):GetNormalized()*velocity:Length()
    end

    return D6_Wep.FireProjectile({
        art = heavy and "shot_mega" or "shot_homing", muzzleFX = true,
        weapon = wep, swept = true, steer = seek and steer or nil,
        owner = owner, pos = pos, dir = dir, speed = speed,
        model = "models/weapons/w_missile.mdl", mass = 4, physRadius = heavy and 5 or 3,
        dmgClass = "explosive", artScale = heavy and 1.7 or 0.9, life = heavy and 3.2 or 6.5,
        trails = {{col = color, sw = heavy and 18 or 8, ew = 1, life = heavy and 0.44 or 0.23}},
        onHit = function(projectile, victim, hitPos, normal)
            if victim == nil and not heavy then return end
            local center = hitPos + normal*3
            local radius = heavy and 365 or (seek and 96 or 136)
            local damage = heavy and 235 or (mode == 0 and 92 or 54)
            if IsValid(victim) and not victim:IsWorld() then
                D6_Wep.DirectDamage(owner, projectile, victim, damage, DMG_BLAST, dir*3500)
            end
            D6_Wep.SplashDamage(owner, projectile, center, 0, damage*0.72, radius, DMG_BLAST, 3200, victim)
            local fx = EffectData()
            fx:SetOrigin(center)
            fx:SetScale(heavy and 4 or 1)
            util.Effect(heavy and "HelicopterMegaBomb" or "Explosion", fx)
            sound.Play("weapons/rpg/rocket_explode.wav", center, heavy and 100 or 80, heavy and 77 or 104)
        end,
    })
end

function SWEP:Initialize()
    self:SetWeaponHoldType(self.HoldType)
end

function SWEP:Deploy()  return true end
function SWEP:Holster() return true end

-- Реген энергии теперь централизован в d6_energy.lua (D6_Energy.RegenTick).

function SWEP:SecondaryAttack()
    if not SERVER then return end
    local now = CurTime()
    if now < (self._NextSub or 0) then return end
    self._NextSub = now + 0.4
    local nxt = (self:GetNWInt("D6_RktSub", 0) + 1) % 4
    self:SetNWInt("D6_RktSub", nxt)
    local owner = self:GetOwner()
    if IsValid(owner) then owner:EmitSound("buttons/button14.wav", 65, 100 + nxt * 10) end
end

function SWEP:PrimaryAttack()
    if not SERVER or CurTime() < self:GetNextPrimaryFire() then return end
    local owner = self:GetOwner()
    if not IsValid(owner) or not D6_Wep.TrySpend(self, owner, ENERGY_COST) then return end
    self:SetNextPrimaryFire(CurTime() + 0.8)

    local aim = D6_Wep.AimAng(owner)
    local mode = self:GetNWInt("D6_RktSub", 0)
    local count = ({1, 3, 6, 1})[mode + 1]
    for i = 1, count do
        local spread = i - (count + 1)*0.5
        local src = D6_Wep.MuzzleFor(owner, self:GetClass(), i, {fwd = 34, rgt = spread*9, up = -4})
        local direction = (aim:Forward() + aim:Right()*spread*0.055):GetNormalized()
        if count == 1 then direction = D6_Wep.Converge(owner, src, direction) end
        fire(self, owner, src, direction, mode)
    end
    D6_Wep.ApplyRecoil(owner, aim:Forward(), mode == 3 and 160 or 105)
    owner:EmitSound("weapons/rpg/rocketfire1.wav", 82, mode == 3 and 86 or 104)
end

if CLIENT then
    function SWEP:DrawHUD()
        D6_Wep.DrawEnergyHUD(self:GetOwner(), "Ракеты · " .. self:GetDRMDModeName(), Color(242, 138, 89))
    end
end

function SWEP:DrawWorldModel()
    if D6_Art then D6_Art.DrawWorldWeapon(self) else self:DrawModel() end
end
function SWEP:DrawWorldModelTranslucent() end

print("[D6] weapon_d6_rockets.lua loaded")
