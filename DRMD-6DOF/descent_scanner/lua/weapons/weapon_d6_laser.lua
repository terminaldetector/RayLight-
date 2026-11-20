-- ═══════════════════════════════════════════════════════════
-- weapon_d6_laser.lua — ЛАЗЕР (энергия, заряд+луч)
--   Удержание ЛКМ заряжает накопитель (~0.4с), затем — мгновенный
--   луч-разряд. Урон растёт с зарядом; полный заряд бьёт сам.
--   НАВЫК: тайминг заряда и удержание цели в момент разряда.
--   Хитскан (без упреждения), но с отдачей по разряду.
--   Рендер модели (strider_weapon) — в d6_wepview.lua.
-- ═══════════════════════════════════════════════════════════
AddCSLuaFile()

SWEP.PrintName       = "ЛАЗЕР"
SWEP.Author          = "Half-Life: Abaddon"
SWEP.Category        = "Descent"
SWEP.Slot            = 2
SWEP.SlotPos         = 3
SWEP.Spawnable       = false
SWEP.AdminSpawnable  = false
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

if SERVER and not _D6_LASER_NET then
    util.AddNetworkString("D6_LaserBeam")
    _D6_LASER_NET = true
end
if SERVER then
    util.PrecacheSound("weapons/physcannon/energy_sing_loop4.wav")
    util.PrecacheSound("weapons/physcannon/energy_sing_explosion2.wav")
end

local CHARGE_TIME  = 0.40   -- секунд до полного заряда
local CHARGE_DRAIN = 22     -- энергии/с во время заряда
local MIN_CHARGE   = 0.18   -- ниже — холостой щелчок
local MIN_DMG      = 40
local MAX_DMG      = 150
local COOLDOWN     = 0.20
local RECOIL       = 30

local function FireBeam(self, owner)
    local charge = math.Clamp(self._Charge or 0, 0, 1)
    local sa  = D6_Wep.ShootAng(owner)
    local src = D6_Wep.MuzzleFor(owner, self:GetClass(), 1, {fwd = 24, up = -4})
    local dir = D6_Wep.Converge(owner, src, sa:Forward())
    local tr  = D6_Wep.CombatTrace({ start = src, endpos = src + dir * 8000, filter = owner, mask = MASK_SHOT })

    local dmg = Lerp(charge, MIN_DMG, MAX_DMG)
    if IsValid(tr.Entity) and not tr.Entity:IsWorld() then
        D6_Wep.DirectDamage(owner, self, tr.Entity, dmg, D6_DAMAGE.energy.dmgType, dir * 600)
    end

    -- Отдача по разряду (сильнее на полном заряде)
    D6_Wep.ApplyRecoil(owner, dir, RECOIL * (0.4 + 0.6 * charge))

    D6_Wep.MarkShot(self, src, 0.55 + charge * 0.6)
    net.Start("D6_LaserBeam", true)
        net.WriteVector(src)
        net.WriteVector(tr.HitPos)
        net.WriteFloat(charge)
    net.SendPVS(src)
    owner:EmitSound("weapons/physcannon/energy_sing_explosion2.wav", 80, 95 + charge * 30)

    self._Charge    = 0
    self._Charging  = false
    self._NextFire  = CurTime() + COOLDOWN
    self:SetNextPrimaryFire(self._NextFire)
    self:SetNWFloat("D6_LaserCharge", 0)
end

function SWEP:Initialize()
    self:SetWeaponHoldType(self.HoldType)
    self._Charge   = 0
    self._Charging = false
    self._NextFire = 0
end

function SWEP:Deploy()
    if SERVER then self:SetNWFloat("D6_LaserCharge", 0) end
    self._Charge, self._Charging = 0, false
    return true
end

function SWEP:Holster()
    if SERVER then self:SetNWFloat("D6_LaserCharge", 0) end
    self._Charge, self._Charging = 0, false
    return true
end
SWEP.OnRemove = SWEP.Holster

function SWEP:PrimaryAttack()
    -- Темп ведёт Think (заряд/разряд); тут только глушим стандартный фолл.
    self:SetNextPrimaryFire(CurTime() + 9999)
end

function SWEP:Think()
    if not SERVER then return end
    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    local ct = CurTime()
    local ft = FrameTime()
    local held = owner:KeyDown(IN_ATTACK) and ct >= (self._NextFire or 0)

    if held then
        if not self._Charging then
            self._Charging = true
            self._Charge   = 0
            owner:EmitSound("weapons/physcannon/energy_sing_loop4.wav", 60, 130)
        end
        self._Charge = math.min(1, (self._Charge or 0) + ft / CHARGE_TIME)
        self:SetNWFloat("D6_LaserCharge", self._Charge)

        -- Заряд черпает энергию; кончилась — разряд тем, что накоплено
        if not D6_Energy.TryConsume(owner, "weapons", CHARGE_DRAIN * ft) then
            if (self._Charge or 0) >= MIN_CHARGE then
                FireBeam(self, owner)
            else
                self._Charge, self._Charging = 0, false
                self:SetNWFloat("D6_LaserCharge", 0)
                self._NextFire = ct + COOLDOWN
            end
        elseif self._Charge >= 1 then
            FireBeam(self, owner)   -- полный заряд бьёт автоматически
        end
    elseif self._Charging then
        -- Отпустил: разряд если заряд достаточен, иначе холостой щелчок
        if (self._Charge or 0) >= MIN_CHARGE then
            FireBeam(self, owner)
        else
            owner:EmitSound("buttons/button19.wav", 55, 140)
            self._Charge, self._Charging = 0, false
            self:SetNWFloat("D6_LaserCharge", 0)
        end
    end
end

function SWEP:SecondaryAttack()
    if not SERVER then return end
    self:SetNextSecondaryFire(CurTime() + 0.8)
    D6_Wep.DelegateSecondary(self:GetOwner())
end

if CLIENT then
    local beams = {}
    local mat = Material("sprites/laserbeam")
    local glow = Material("sprites/light_glow02_add")
    net.Receive("D6_LaserBeam", function()
        local src, dest, charge = net.ReadVector(), net.ReadVector(), net.ReadFloat()
        beams[#beams + 1] = {src = src, dest = dest, charge = charge, stop = CurTime() + 0.16}
    end)

    hook.Add("PostDrawTranslucentRenderables", "D6_LaserBeamDraw", function(depth, sky)
        if depth or sky then return end
        for i = #beams, 1, -1 do
            local beam = beams[i]
            local fade = (beam.stop - CurTime()) / 0.16
            if fade <= 0 then
                table.remove(beams, i)
            else
                local w = 2.5 + beam.charge*6
                render.SetMaterial(mat)
                render.DrawBeam(beam.src, beam.dest, w*2.1, 0, 1, Color(80, 219, 221, 175*fade))
                render.DrawBeam(beam.src, beam.dest, w*0.65, 0, 1, Color(223, 255, 246, 255*fade))
                render.SetMaterial(glow)
                render.DrawSprite(beam.dest, 22, 22, Color(98, 235, 219, 195*fade))
            end
        end
    end)

    function SWEP:DrawHUD()
        local ply = self:GetOwner()
        if not (IsValid(ply) and ply == LocalPlayer()) then return end
        D6_Wep.DrawEnergyHUD(ply, "ЛАЗЕР", Color(255, 120, 80))
        -- Полоса заряда поверх энергобара
        local chg = self:GetNWFloat("D6_LaserCharge", 0)
        if chg > 0 then
            local sw, sh = ScrW(), ScrH()
            local bw, bh = 140, 4
            local bx, by = sw / 2 - bw / 2, sh - 80
            surface.SetDrawColor(255, 80 + chg * 120, 40, 230)
            surface.DrawRect(bx, by, bw * chg, bh)
        end
    end
end

function SWEP:DrawWorldModel()
    if D6_Art then D6_Art.DrawWorldWeapon(self) else self:DrawModel() end
end
function SWEP:DrawWorldModelTranslucent() end

print("[D6] weapon_d6_laser.lua loaded")
