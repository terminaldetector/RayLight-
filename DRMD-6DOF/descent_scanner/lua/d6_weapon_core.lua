-- ═══════════════════════════════════════════════════════════
-- d6_weapon_core.lua — Unified Weapon Framework (Phase B)
--
-- ЦЕЛЬ: не визуал, а ВЫРАЖЕНИЕ НАВЫКА ПИЛОТА. Оружие связано с
-- движением корабля:
--   • наследование скорости — снаряды несут импульс корабля,
--     поэтому по движущейся цели нужно упреждение (lead);
--   • отдача — каждый выстрел толкает корабль через ply.D6Vel,
--     поэтому залпами надо управлять (drift management);
--   • параллельные стволы — все дула бьют по борсайту (прицелу)
--     на любой дистанции, без схождения в фиксированную точку;
--   • цветовой язык урона — единая читаемость боя по классам.
--
-- Этот файл устраняет дублирование (ShootAng/Muzzle/EnsurePhys/
-- энергобар/делегирование ракет были скопированы в каждом SWEP)
-- и даёт единый спавнер D6_Wep.FireProjectile().
-- ═══════════════════════════════════════════════════════════

D6_Wep    = D6_Wep or {}
D6_DAMAGE = D6_DAMAGE or {}

-- ── Тюнинг связи с движением (реплицируемые конвары) ──────
-- Полная связь по умолчанию (Descent). Меняй вживую без правки кода:
--   d6_wep_inherit 1   — наследование скорости (0..1+)
--   d6_wep_recoil  1   — множитель отдачи (0 = выкл)
local cv_inherit = CreateConVar("d6_wep_inherit", "1.0",
    bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED), "Projectile ship-velocity inheritance factor", 0, 2)
local cv_recoil = CreateConVar("d6_wep_recoil", "1.0",
    bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED), "Weapon firing recoil factor", 0, 3)

function D6_Wep.Inherit() return cv_inherit:GetFloat() end
function D6_Wep.Recoil()  return cv_recoil:GetFloat()  end

-- ═══════════════════════════════════════════════════════════
-- ТАКСОНОМИЯ УРОНА
-- Каждый класс задаёт: биты DMG_* (→ канал резиста в d6_shield),
-- цвета трассера/свечения (читаемость) и физпрофиль снаряда.
--   resist-канал d6_shield: BLAST→explosive, EBEAM/SHOCK→energy,
--   иначе→kinetic. Поэтому классы дают РАЗНЫЕ каналы.
-- ═══════════════════════════════════════════════════════════
D6_DAMAGE.kinetic = {
    dmgType = DMG_BULLET,                        -- → kinetic
    tracer  = Color(180, 220, 255),
    glow    = Color(140, 200, 255),
    gravity = false,                             -- пули быстрые, без дуги
}
D6_DAMAGE.energy = {
    dmgType = bit.bor(DMG_ENERGYBEAM, DMG_SHOCK),-- → energy
    tracer  = Color(80, 255, 140),
    glow    = Color(160, 255, 190),
    gravity = false,
}
D6_DAMAGE.explosive = {
    dmgType = DMG_BLAST,                          -- → explosive
    tracer  = Color(255, 140, 40),
    glow    = Color(255, 185, 95),
    gravity = false,
}
D6_DAMAGE.exotic = {
    dmgType = bit.bor(DMG_SHOCK, DMG_ENERGYBEAM), -- → energy (плазма-шар)
    tracer  = Color(0, 220, 255),
    glow    = Color(180, 255, 255),
    gravity = false,
}

function D6_Wep.DmgClass(name)
    return D6_DAMAGE[name] or D6_DAMAGE.kinetic
end

-- ═══════════════════════════════════════════════════════════
-- ПРИЦЕЛИВАНИЕ (единый источник — раньше ShootAng был в 7 файлах)
-- ═══════════════════════════════════════════════════════════
-- Направление стрельбы: pitch+yaw без крена (снаряд летит туда,
-- куда смотрит нос, крен на траекторию не влияет).
function D6_Wep.ShootAng(ply)
    local a = ply.D6AngSynced or ply.D6Ang or ply:EyeAngles()
    return Angle(a.p, a.y, 0)
end

-- Полный угол с креном — для смещения дул (rgt/up вращаются с креном).
function D6_Wep.AimAng(ply)
    return ply.D6AngSynced or ply.D6Ang or ply:EyeAngles()
end

-- Мировая позиция дула из { fwd, rgt, up }.
-- fwd берётся без крена (ShootAng), rgt/up — с креном (AimAng).
local function oldMuzzle(ply, off, aim)
    return ply:GetShootPos() + aim:Forward()*(off.fwd or 0)
        + aim:Right()*(off.rgt or 0) + aim:Up()*(off.up or 0)
end

function D6_Wep.Muzzle(ply, off, class, index)
    local aim = D6_Wep.AimAng(ply)
    if not class then
        local active = ply:GetActiveWeapon()
        class = IsValid(active) and active:GetClass() or ""
    end
    local slot = ply:GetNWBool("D6On") and D6_Arsenal.Slot(ply, class)
    if not slot then return oldMuzzle(ply, off, aim) end
    local item = D6_Arsenal.Entries[class]
    local origin = D6_Arsenal.MountOrigin(D6_Arsenal.Anchor(ply, aim), aim, slot)
    return D6_Arsenal.Port(origin, aim, item, index, off)
end

-- The workshop's explicit attachment points still take priority.
function D6_Wep.MuzzleFor(ply, class, idx, defaultOff)
    local override = D6_SCKBridge and D6_SCKBridge.GetMuzzle and D6_SCKBridge.GetMuzzle(class, idx)
    if override then return oldMuzzle(ply, override, D6_Wep.AimAng(ply)) end
    return D6_Wep.Muzzle(ply, defaultOff or {}, class, idx)
end

function D6_Wep.Converge(ply, muzzle, direction)
    if not ply:GetNWBool("D6On") then return direction end
    local origin = ply:GetShootPos()
    local tr = D6_Wep.CombatTrace({start = origin, endpos = origin + direction*8192, filter = ply, mask = MASK_SHOT})
    local distance = math.max((tr.HitPos - origin):Length(), 96)
    return (origin + direction*distance - muzzle):GetNormalized()
end

function D6_Wep.Targetable(owner, target)
    if not IsValid(target) or target == owner or target:Health() <= 0 then return false end
    if target:IsPlayer() then return target:Alive() end
    if target:IsNPC() then return target:Disposition(owner) ~= D_LI end
    return target:IsNextBot()
end

local enforcerHulls = {}
local eliteScale = D6_Session.Enforcer.scale
local enforcerBoxes = {
    {Vector(-24,-18,-21)*eliteScale, Vector(26.7,18,15.5)*eliteScale},
    {Vector(-19,-31.6,-5.6)*eliteScale, Vector(28.8,-17,6)*eliteScale},
    {Vector(-19,17,-5.6)*eliteScale, Vector(28.8,31.6,6)*eliteScale},
    {Vector(-12,-22.5,16)*eliteScale, Vector(14.5,-6.4,28.7)*eliteScale},
    {Vector(-12,6.4,16)*eliteScale, Vector(14.5,22.5,28.7)*eliteScale},
}

function D6_Wep.RegisterEnforcerHull(npc, hull)
    local boxes = enforcerBoxes
    if hull and hull.parts then
        boxes = {}
        for i, part in ipairs(hull.parts) do
            boxes[i] = {Vector(unpack(part[1]))*hull.scale, Vector(unpack(part[2]))*hull.scale}
        end
    end
    enforcerHulls[npc] = boxes
    npc:CallOnRemove("D6_EnforcerHull", function(ent) enforcerHulls[ent] = nil end)
end

local function includesEntity(filter, npc)
    if isfunction(filter) then return filter(npc) end
    if istable(filter) then return not table.HasValue(filter, npc) end
    return filter ~= npc
end

-- Stock scanner hitboxes don't extend to the custom chassis. Test the armour and pods
-- against the segment after the native trace so map cover and intervening hits still win.
function D6_Wep.CombatTrace(data)
    local result = data.mins and util.TraceHull(data) or util.TraceLine(data)
    if result.StartSolid or not next(enforcerHulls) then return result end
    local delta = data.endpos - data.start
    local length = delta:LengthSqr()
    if length < 0.001 then return result end
    local padding = data.maxs or vector_origin
    for npc, boxes in pairs(enforcerHulls) do
        if not IsValid(npc) or not includesEntity(data.filter, npc) then continue end
        local origin, angles = npc:GetPos(), npc:GetAngles()
        for _, box in ipairs(boxes) do
            local hit, normal = util.IntersectRayWithOBB(data.start, delta, origin, angles, box[1] - padding, box[2] + padding)
            if not hit then continue end
            local fraction = (hit - data.start):Dot(delta)/length
            if fraction >= 0 and fraction < result.Fraction then
                result = {Hit = true, HitNonWorld = true, HitWorld = false, StartSolid = false,
                    HitPos = hit, HitNormal = normal, Normal = delta:GetNormalized(), StartPos = data.start,
                    Fraction = fraction, Entity = npc, MatType = MAT_METAL, HitGroup = HITGROUP_GENERIC, PhysicsBone = 0}
            end
        end
    end
    return result
end

-- ═══════════════════════════════════════════════════════════
-- СВЯЗЬ С ДВИЖЕНИЕМ
-- ═══════════════════════════════════════════════════════════
-- Текущая скорость корабля. В 6DOF интегратор хранит ply.D6Vel
-- (d6_core.lua); вне 6DOF — обычный GetVelocity().
function D6_Wep.ShipVel(owner)
    if not IsValid(owner) then return Vector(0, 0, 0) end
    return (owner.D6On and owner.D6Vel) or owner:GetVelocity()
end

-- Отдача: толкает корабль ПРОТИВ направления выстрела.
-- Пишем прямо в ply.D6Vel — следующий тик Move() это интегрирует
-- (так же, как рывок/крюк в d6_core.lua). Сервер авторитетен.
function D6_Wep.ApplyRecoil(owner, dir, mag)
    if not SERVER or not IsValid(owner) then return end
    mag = (mag or 0) * D6_Wep.Recoil()
    if mag <= 0 then return end
    if owner.D6On and owner.D6Vel then
        owner.D6Vel = owner.D6Vel - dir * mag
    elseif owner.SetVelocity then
        owner:SetVelocity(-dir * mag)
    end
end

-- ═══════════════════════════════════════════════════════════
-- ФИЗИКА СНАРЯДА
-- ═══════════════════════════════════════════════════════════
function D6_Wep.EnsurePhys(ent, radius)
    local ph = ent:GetPhysicsObject()
    if IsValid(ph) then return ph end
    ent:PhysicsInitSphere(radius or 4, "metal")
    ent:SetMoveType(MOVETYPE_VPHYSICS)
    return ent:GetPhysicsObject()
end

if SERVER then
    util.AddNetworkString("D6_ImpactFX")
    util.AddNetworkString("D6_MuzzleFX")
    util.AddNetworkString("D6_MoveFX")

    function D6_Wep.MotionFX(from, to, kind)
        local recipients = RecipientFilter()
        recipients:AddPVS(from)
        recipients:AddPVS(to)
        net.Start("D6_MoveFX", true)
        net.WriteVector(from)
        net.WriteVector(to)
        net.WriteUInt(kind, 2)
        net.Send(recipients)
    end
    local tracked = {}
    local shotMesh = {kinetic = "shot_kinetic", energy = "shot_energy", explosive = "shot_rocket", exotic = "shot_exotic"}

    function D6_Wep.TagProjectile(ent, kind, scale)
        ent:SetNWString("D6_ProjectileArt", shotMesh[kind] or kind)
        ent:SetNWFloat("D6_ProjectileArtScale", scale or 1)
    end

    function D6_Wep.Ordnance(key, pos, owner, options)
        local spec = D6_Arsenal.Ordnance[key]
        if not spec or not spec.radius then return end
        local item = ents.Create("d6_ordnance")
        if not IsValid(item) then return end
        options = options or {}
        item.D6_Radius = spec.radius
        item.D6_Model = D6_Arsenal.NativeModel(spec.mesh)
        item.D6_Collectible = options.collectible
        item:SetPos(pos)
        item:SetAngles(options.angle or angle_zero)
        if IsValid(owner) then item:SetOwner(owner) end
        item:Spawn()
        item:SetCollisionGroup(options.group or COLLISION_GROUP_WEAPON)
        D6_Wep.TagProjectile(item, key, 1)
        local body = item:GetPhysicsObject()
        if not IsValid(body) then item:Remove(); return end
        body:SetMass(options.mass or 14)
        body:EnableGravity(options.gravity == true)
        body:EnableMotion(options.mobile == true)
        if options.mobile then body:Wake() end
        return item, body
    end

    function D6_Wep.MuzzleFX(pos, direction, kind)
        net.Start("D6_MuzzleFX", true)
        net.WriteVector(pos)
        net.WriteNormal(direction)
        net.WriteString(kind)
        net.SendPVS(pos)
    end

    function D6_Wep.MarkShot(weapon, origin, kick)
        if not IsValid(weapon) then return end
        weapon:SetNWFloat("D6_ShotAt", CurTime())
        weapon:SetNWFloat("D6_ShotKick", math.Clamp(kick or 1, 0.15, 2))
        if origin then weapon:SetNWVector("D6_ShotOrigin", origin) end
    end

    function D6_Wep.TrySpend(wep, ply, amount)
        if D6_Energy.TryConsume(ply, "weapons", amount) then return true end
        wep:SetNextPrimaryFire(math.max(wep:GetNextPrimaryFire(), CurTime() + 0.23))
        if CurTime() >= (wep.D6_NextDrySound or 0) then
            ply:EmitSound("buttons/button10.wav", 62, 102)
            wep.D6_NextDrySound = CurTime() + 0.23
        end
        return false
    end

    function D6_Wep.DeployPoint(ply, wanted, radius)
        local extents = Vector(radius, radius, radius)
        local tr = util.TraceHull({start = ply:GetShootPos(), endpos = wanted, filter = ply,
            mins = -extents, maxs = extents, mask = MASK_SOLID})
        if tr.StartSolid then return end
        if tr.Hit then return tr.HitPos + tr.HitNormal*2 end
        return wanted
    end

    function D6_Wep.FindBlink(ply, direction, range)
        local origin = ply:GetPos()
        local mins, maxs = ply:GetHull()
        local tr = util.TraceHull({start = origin, endpos = origin + direction*range,
            mins = mins, maxs = maxs, filter = ply, mask = MASK_PLAYERSOLID})
        if tr.StartSolid then return end
        local dest = tr.Hit and tr.HitPos + tr.HitNormal*5 or tr.HitPos
        if dest:DistToSqr(origin) < 50^2 or not util.IsInWorld(dest) then return end
        local clearance = util.TraceHull({start = dest, endpos = dest, mins = mins, maxs = maxs,
            filter = ply, mask = MASK_PLAYERSOLID})
        if not clearance.Hit then return dest end
    end

    hook.Add("Tick", "D6_ProjectileSweep", function()
        local dt = engine.TickInterval()
        for ent, state in pairs(tracked) do
            if not IsValid(ent) or not ent.D6_Impact then
                tracked[ent] = nil
            else
                local from = state.last
                if state.steer then state.velocity = state.steer(ent, from, state.velocity, dt) end
                local to = state.velocity and from + state.velocity*dt or ent:GetPos()
                local tr = D6_Wep.CombatTrace({
                    start = from, endpos = to, mask = MASK_SHOT, mins = -state.extents, maxs = state.extents,
                    filter = state.filter,
                })
                local dest, velocity
                if state.velocity then
                    dest, velocity = D6_Gates.MoveShot(ent, from, to, state.extents.x, state.velocity, tr.Fraction)
                end
                if dest then
                    state.velocity, state.last = velocity, dest
                    ent:SetPos(dest)
                    ent:SetAngles(velocity:Angle())
                elseif tr.Hit then
                    ent.D6_Impact(tr.Entity, tr.HitPos, tr.HitNormal)
                else
                    if state.velocity then
                        ent:SetPos(to)
                        if state.steer then ent:SetAngles(state.velocity:Angle()) end
                    end
                    state.last = to
                end
            end
        end
    end)

    -- ── Единый спавнер снаряда ───────────────────────────
    -- cfg:
    --   owner, pos, dir, speed              (обязательно)
    --   art                                (сетка DRMD)
    --   model, scale                       (своя модель при отсутствии art)
    --   color, renderAdd                    (визуал)
    --   dmgClass = "kinetic|energy|explosive|exotic"
    --   physRadius, mass, gravity, drag     (физика; gravity по умолчанию из класса)
    --   inherit                             (override фактора наследования)
    --   recoil                              (импульс отдачи на корабль)
    --   trails = { {col,sw,ew,life,mat}, {...} }
    --   life, onHit                         (→ D6_TrackProjectile)
    function D6_Wep.FireProjectile(cfg)
        local owner = cfg.owner
        local dc = D6_Wep.DmgClass(cfg.dmgClass)
        local direction = cfg.converge and D6_Wep.Converge(owner, cfg.pos, cfg.dir) or cfg.dir
        local velocity = direction * cfg.speed + D6_Wep.ShipVel(owner) * ((cfg.inherit or 1) * D6_Wep.Inherit())

        local radius = math.Clamp(cfg.physRadius or 3, 1, 16)
        local p = ents.Create("d6_projectile")
        if not IsValid(p) then return end
        if not cfg.swept then p.D6_PhysRadius = radius end
        p.D6_DamageClass = cfg.dmgClass
        local projectileArt = cfg.art or cfg.dmgClass or "kinetic"
        local customModel = not cfg.art and cfg.model and util.IsValidModel(cfg.model)
        p.D6_Model = customModel and cfg.model or D6_Arsenal.NativeModel(shotMesh[projectileArt] or projectileArt)
        p:SetPos(cfg.pos)
        p:SetAngles(direction:Angle())
        p:SetOwner(owner)
        p:Spawn()
        p:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
        if customModel and cfg.scale then p:SetModelScale(cfg.scale,0) end
        if cfg.color then p:SetColor(cfg.color) end
        p:SetRenderMode(cfg.renderAdd ~= false and RENDERMODE_TRANSADD or RENDERMODE_NORMAL)

        -- Трассеры
        if cfg.trails then
            for i, t in ipairs(cfg.trails) do
                local sw = t.sw or 12
                util.SpriteTrail(p, i - 1, t.col or dc.tracer, false,
                    sw, t.ew or 0, t.life or 0.2, 1 / (sw + 1) * 0.5,
                    t.mat or "trails/laser.vmt")
            end
        end

        if not cfg.swept then
            local ph = p:GetPhysicsObject()
            if not IsValid(ph) then p:Remove(); return end
            local grav = cfg.gravity
            if grav == nil then grav = dc.gravity end
            ph:EnableGravity(grav == true)
            ph:EnableDrag(cfg.drag == true)
            ph:SetMass(cfg.mass or 1)
            ph:SetVelocity(velocity)
            ph:Wake()
        end

        local weapon = cfg.weapon
        if not customModel then D6_Wep.TagProjectile(p, projectileArt, cfg.artScale) end
        if cfg.muzzleFX then D6_Wep.MuzzleFX(cfg.pos, direction, projectileArt) end
        if IsValid(weapon) then D6_Wep.MarkShot(weapon, cfg.pos, cfg.recoil and cfg.recoil / 80 or 0.8) end
        if cfg.recoil then D6_Wep.ApplyRecoil(owner, direction, cfg.recoil) end

        D6_TrackProjectile(p, owner, function(projectile, hitEnt, hitPos, normal)
            if hitEnt ~= nil then
                net.Start("D6_ImpactFX", true)
                net.WriteVector(hitPos)
                net.WriteNormal(normal)
                net.WriteString(projectileArt)
                net.SendPVS(hitPos)
            end
            if cfg.onHit then cfg.onHit(projectile, hitEnt, hitPos, normal) end
        end, cfg.life or 5, cfg.swept)

        local extents = Vector(radius, radius, radius)
        local state = {
            last = cfg.pos, extents = extents, velocity = cfg.swept and velocity or nil, steer = cfg.swept and cfg.steer,
            filter = function(ent) return ent ~= owner and ent ~= p and not ent.D6_IsProjectile end,
        }
        tracked[p] = state
        if IsValid(weapon) then
            local tr = D6_Wep.CombatTrace({start = owner:GetShootPos(), endpos = cfg.pos, mask = MASK_SHOT,
                mins = -extents, maxs = extents, filter = state.filter})
            if tr.Hit and p.D6_Impact then p.D6_Impact(tr.Entity, tr.HitPos, tr.HitNormal) end
        end
        return p
    end

    -- ── Хелперы урона для onHit-колбэков ─────────────────
    function D6_Wep.DirectDamage(attacker, inflictor, target, dmg, dmgType, force)
        if not IsValid(target) then return end
        local di = DamageInfo()
        di:SetAttacker(IsValid(attacker) and attacker or game.GetWorld())
        di:SetInflictor(IsValid(inflictor) and inflictor or game.GetWorld())
        di:SetDamage(dmg)
        di:SetDamageType(dmgType)
        di:SetDamageForce(force or Vector(0, 0, 0))
        target:TakeDamageInfo(di)
    end

    -- Радиальный урон: base в эпицентре + splash по спаду к радиусу.
    function D6_Wep.SplashDamage(attacker, inflictor, center, baseDmg, splashDmg, radius, dmgType, forceScale, ignore)
        for _, e in ipairs(ents.FindInSphere(center, radius)) do
            if IsValid(e) and e ~= ignore and (e:IsNPC() or e:IsPlayer() or e:IsNextBot()
            or e:GetClass() == "func_breakable" or e:GetClass() == "func_breakable_surf") then
                local toward = e:WorldSpaceCenter() - center
                local tr = util.TraceLine({start = center + toward:GetNormalized()*2, endpos = e:WorldSpaceCenter(),
                    filter = inflictor, mask = MASK_SHOT})
                if not tr.Hit or tr.Entity == e then
                    local dmg = baseDmg + splashDmg * math.max(0, 1 - toward:Length()/radius)
                    D6_Wep.DirectDamage(attacker, inflictor, e, dmg, dmgType, toward:GetNormalized()*(forceScale or 4000))
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- ОБЩИЕ ХЕЛПЕРЫ SWEP (раньше копировались в каждый файл)
-- ═══════════════════════════════════════════════════════════
-- Вторичка всех основных пушек = пуск ракет (делегирование).
-- (Пустые world-model стабы оставлены инлайн в каждом SWEP —
--  их вызов идёт на загрузке файла, до подключения этой либы.)
function D6_Wep.DelegateSecondary(owner)
    if not IsValid(owner) then return end
    local rkt = owner:GetWeapon("weapon_d6_rockets")
    if IsValid(rkt) and CurTime() >= rkt:GetNextPrimaryFire() then rkt:PrimaryAttack() end
end

if CLIENT then
    -- Единый энергобар над прицелом (раньше 5 копий DrawHUD).
    function D6_Wep.DrawEnergyHUD(ply, label, labelCol)
        if IsValid(ply) and ply:GetNWBool("D6On") then return end
        if not (IsValid(ply) and ply == LocalPlayer()) then return end
        local energy = ply:GetNWFloat("D6_WepEnergy", 100)
        local sw, sh = ScrW(), ScrH()
        local bw, bh = 140, 6
        local bx, by = sw / 2 - bw / 2, sh - 72
        surface.SetDrawColor(30, 30, 30, 180); surface.DrawRect(bx - 1, by - 1, bw + 2, bh + 2)
        local col = energy > 30 and Color(0, 180, 255) or Color(255, 60, 60)
        surface.SetDrawColor(col.r, col.g, col.b, 200)
        surface.DrawRect(bx, by, bw * (energy / 100), bh)
        draw.SimpleText(label .. "  ⚡ " .. math.floor(energy), "DermaDefault",
            sw / 2, sh - 90, labelCol or Color(180, 220, 255),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Ammo pip bar for Category B weapons (limited-ammo missiles).
    -- Shows individual missile pips so remaining count reads at a glance.
    function D6_Wep.DrawAmmoHUD(ply, label, ammoType, maxAmmo, col)
        if IsValid(ply) and ply:GetNWBool("D6On") then return end
        if not (IsValid(ply) and ply == LocalPlayer()) then return end
        local count = ply:GetAmmoCount(ammoType)
        local sw, sh = ScrW(), ScrH()
        local bw, bh = 140, 8
        local bx    = sw / 2 - bw / 2
        local by    = sh - 74
        local pip   = math.max(4, math.floor((bw - (maxAmmo - 1) * 3) / maxAmmo))
        for i = 1, maxAmmo do
            local x = bx + (i - 1) * (pip + 3)
            surface.SetDrawColor(30, 30, 30, 180)
            surface.DrawRect(x - 1, by - 1, pip + 2, bh + 2)
            if i <= count then
                surface.SetDrawColor(col.r, col.g, col.b, 220)
            else
                surface.SetDrawColor(50, 50, 50, 120)
            end
            surface.DrawRect(x, by, pip, bh)
        end
        local labelCol = count > 0 and col or Color(255, 60, 60)
        draw.SimpleText(label .. "   " .. count .. " / " .. maxAmmo, "DermaDefault",
            sw / 2, sh - 90, labelCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Energy bar + cooldown/ready indicator for high-cooldown weapons
    -- (BFG, ultimates, deployables). cooldown = total seconds for the bar fill.
    function D6_Wep.DrawReadyHUD(ply, wep, label, col, cooldown)
        if IsValid(ply) and ply:GetNWBool("D6On") then return end
        if not (IsValid(ply) and ply == LocalPlayer()) then return end
        D6_Wep.DrawEnergyHUD(ply, label, col)
        if not IsValid(wep) then return end
        local sw, sh = ScrW(), ScrH()
        local rem = wep:GetNextPrimaryFire() - CurTime()
        if rem > 0 and cooldown and cooldown > 0 then
            local frac   = 1 - math.Clamp(rem / cooldown, 0, 1)
            local bw, bh = 140, 4
            local bx, by = sw / 2 - bw / 2, sh - 80
            surface.SetDrawColor(20, 20, 20, 180); surface.DrawRect(bx - 1, by - 1, bw + 2, bh + 2)
            surface.SetDrawColor(col.r, col.g, col.b, 210); surface.DrawRect(bx, by, bw * frac, bh)
        else
            draw.SimpleText("● ГОТОВ", "DermaDefault", sw / 2, sh - 80,
                col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
end

print("[D6] d6_weapon_core.lua OK")
