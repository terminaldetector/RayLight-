-- ═══════════════════════════════════════════════════════════
-- weapon_d6_plasmamine.lua — ПЛАЗМА-МИНА (проксимити-отрицание)
--
--   Cat E: пространственный контроль. Ставит неподвижную мину
--   (замороженную в 6DOF-пространстве). При входе врага в 180u —
--   плазменный взрыв 120 + 100 AoE в 260u (exotic). Живёт 30 с.
--   До 4 активных мин. Минирование маршрутов и узких проходов.
--
--   Фреймворк: d6_weapon_core (Muzzle/ShootAng/SplashDamage),
--   d6_energy (TryConsume), d6_shield (exotic → energy-резист).
-- ═══════════════════════════════════════════════════════════
AddCSLuaFile()

SWEP.PrintName      = "ПЛАЗМА-МИНА"
SWEP.Author         = "Half-Life: Abaddon"
SWEP.Category       = "Half-Life: Abaddon / Оружие"
SWEP.ScriptedEntityType = "d6_weapon"
SWEP.Slot           = 5
SWEP.SlotPos        = 0
SWEP.Spawnable      = true
SWEP.AdminSpawnable = true
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

if SERVER then
    util.PrecacheSound("npc/roller/mine/rmine_chirp_answer1.wav")
    util.PrecacheSound("ambient/energy/whiteflash.wav")
end

local ENERGY_COST  = 25
local COOLDOWN     = 1.0
local MAX_ACTIVE   = 4
local ARM_DELAY    = 0.8
local TRIG_RAD     = 180
local BLAST_DIRECT = 120
local BLAST_SPLASH = 100
local BLAST_RAD    = 260
local LIFE         = 30

function SWEP:Initialize()
    self:SetWeaponHoldType(self.HoldType)
    self._Deployed = {}
end
function SWEP:Deploy()  return true end
function SWEP:Holster() return true end

function SWEP:_Register(ent)
    self._Deployed = self._Deployed or {}
    for i = #self._Deployed, 1, -1 do
        if not IsValid(self._Deployed[i]) then table.remove(self._Deployed, i) end
    end
    table.insert(self._Deployed, ent)
    if #self._Deployed > MAX_ACTIVE then
        local old = table.remove(self._Deployed, 1)
        if IsValid(old) then old:Remove() end
    end
    if SERVER then self:SetNWInt("D6_Deployed", #self._Deployed) end
    ent:CallOnRemove("D6_MineBay", function(removed)
        timer.Remove("D6_PMine_" .. removed:EntIndex())
        if not IsValid(self) then return end
        for i = #self._Deployed, 1, -1 do
            if self._Deployed[i] == removed or not IsValid(self._Deployed[i]) then
                table.remove(self._Deployed, i)
            end
        end
        self:SetNWInt("D6_Deployed", #self._Deployed)
    end)
end

local function Detonate(owner, mine)
    if not IsValid(mine) then return end
    local pos = mine:GetPos()
    timer.Remove("D6_PMine_" .. mine:EntIndex())
    D6_Wep.SplashDamage(owner, mine, pos, BLAST_DIRECT, BLAST_SPLASH, BLAST_RAD,
        D6_DAMAGE.exotic.dmgType, 6000, nil)
    local ef = EffectData(); ef:SetOrigin(pos); ef:SetScale(4); ef:SetMagnitude(BLAST_RAD)
    util.Effect("HelicopterMegaBomb", ef)
    local ef2 = EffectData(); ef2:SetOrigin(pos); ef2:SetScale(3)
    util.Effect("cball_explode", ef2)
    sound.Play("ambient/energy/whiteflash.wav", pos, 110, 95)
    mine:Remove()
end

-- Also called by the independent mine bay; do not rely on active-SWEP input
-- throttling. Both paths share the weapon and owner cooldowns.
function SWEP:DeployMine()
    if not SERVER then return false end
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() or not owner:Alive() or owner:InVehicle() then return false end
    local now = CurTime()
    if now < self:GetNextPrimaryFire() or now < (owner.D6_MineNextFire or 0) then return false end

    local dir = D6_Wep.ShootAng(owner):Forward()
    local muzzle = D6_Wep.Muzzle(owner, { fwd = 40, rgt = 0, up = -6 }, self:GetClass())
    local pos = D6_Wep.DeployPoint(owner, muzzle + dir * 60, 12)
    if not pos then return false end
    local mine = D6_Wep.Ordnance("mine_plasma", pos, owner, {angle = D6_Wep.AimAng(owner)})
    if not IsValid(mine) then
        self:SetNextPrimaryFire(now + 0.23)
        return false
    end
    -- A failed spawn must not consume finite mine stock or start its feed cycle.
    if not D6_Wep.TrySpend(self, owner, ENERGY_COST) then mine:Remove(); return false end
    self:SetNextPrimaryFire(math.max(self:GetNextPrimaryFire(), now + COOLDOWN))
    owner.D6_MineNextFire = self:GetNextPrimaryFire()
    mine.D6_WeaponClass = self:GetClass()
    D6_Wep.MarkShot(self, muzzle, 0.8)

    self:_Register(mine)

    mine.D6_Armed = false
    timer.Simple(ARM_DELAY, function()
        if IsValid(mine) then
            mine.D6_Armed = true
            mine:SetNWBool("D6_MineArmed", true)
            mine:EmitSound("npc/roller/mine/rmine_chirp_answer1.wav", 70, 130)
        end
    end)

    local idx = mine:EntIndex()
    timer.Create("D6_PMine_" .. idx, 0.2, 0, function()
        if not IsValid(mine) then timer.Remove("D6_PMine_" .. idx); return end
        if not mine.D6_Armed then return end
        for _, e in ipairs(ents.FindInSphere(mine:GetPos(), TRIG_RAD)) do
            if D6_Wep.Targetable(owner, e) then
                Detonate(owner, mine); return
            end
        end
    end)

    timer.Simple(LIFE, function()
        if IsValid(mine) then Detonate(owner, mine) end
    end)

    owner:EmitSound("weapons/physcannon/physcannon_drop.wav", 70, 120)
    return true
end

function SWEP:PrimaryAttack()
    return self:DeployMine()
end

function SWEP:SecondaryAttack()
    if not SERVER then return end
    self:SetNextSecondaryFire(CurTime() + 0.6)
    D6_Wep.DelegateSecondary(self:GetOwner())
end

if CLIENT then
    function SWEP:DrawHUD()
        D6_Wep.DrawReadyHUD(self:GetOwner(), self, "ПЛАЗМА-МИНА", Color(0, 220, 255), COOLDOWN)
        local n = self:GetNWInt("D6_Deployed", 0)
        draw.SimpleText("МИН: " .. n .. " / " .. MAX_ACTIVE, "DermaDefault",
            ScrW() / 2, ScrH() - 104, Color(0, 220, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

function SWEP:DrawWorldModel()
    if D6_Art then D6_Art.DrawWorldWeapon(self) else self:DrawModel() end
end
function SWEP:DrawWorldModelTranslucent() end

print("[D6] weapon_d6_plasmamine.lua loaded")
