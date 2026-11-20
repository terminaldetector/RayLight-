-- ═══════════════════════════════════════════════════════════
-- D6 ФИЗИКА ПО DESCENT
-- Idle-таймер: гравитация выключена пока игрок активен.
-- ═══════════════════════════════════════════════════════════
-- ── Flight Feel Patch (Sprint: Linear + Thrust + Micro-Motion) ──────────────
-- Проблема до патча: inertia=0.96 давала равновесную скорость ~1497 ед/с
-- (68% от maxSpeed). Машина не могла разогнаться до кэпа органично —
-- maxSpeed срабатывал как жёсткий обрез, а не достигнутый предел.
-- Следствие: нет ощущения разгона, нет ощущения массы.
--
-- Решение: inertia=0.975 + accel=4200 → равновесная скорость ~2797 (127% cap).
-- Машина разгоняется до кэпа ОРГАНИЧНО за ~1с. Торможение занимает ~2с.
-- spoolUp=10: двигатель набирает 63% тяги за 100ms вместо 50ms — ощутима раскрутка.
-- brakeMult=0.012: Flight Assist мягче → инерция видима после отпускания.
-- strafeMult=0.65, vertMult=0.58: контраст осей усилен (синт-машина, не мяч).
-- Sprint 1: inertia 0.975→0.968 (коастинг −1.5с), brakeMult 0.012→0.020 (+67% FA),
--           spoolDown 3→4, strafeMult 0.65→0.72, vertMult 0.58→0.65.
-- Phase A: spoolUp 10→15 (отклик двигателя +50%), drag 2.4→2.1 (−13% пассивного сопр.).
local CFG = {
    gravity      = 200,
    accel        = 4200,
    drag         = 2.1,
    maxSpeed     = 2200,
    inertia      = 0.968,
    brakeMult    = 0.020,
    spoolUp      = 15,
    spoolDown    = 4,
    strafeMult   = 0.72,
    vertMult     = 0.65,
    wallBounce   = 0.5,
    idleGravSec  = 45,
    idleGravRamp = 5,
}

local ANG_RATE    = 0.045

if SERVER then
    util.AddNetworkString("D6_AngSync")
    util.AddNetworkString("D6_Toggle")
    util.AddNetworkString("D6_AlwaysRunSync")
    util.AddNetworkString("D6_WeaponSwitch")
    util.AddNetworkString("D6_RocketSubNext")
    -- Боевые оружия: регистрируем заранее при загрузке карты
    util.AddNetworkString("D6_LaserBeam")   -- weapon_d6_laser: серверный луч
    util.AddNetworkString("D6_RailFire")    -- weapon_d6_gravy_railgun: трассер выстрела

    -- ── Центральный прекеш ресурсов снарядов (внедрено в автолоад) ──
    -- Внутренние ресурсы HL2 для проджектайлов всех боевых оружий D6.
    local D6_PRECACHE_MDL = {
        "models/weapons/w_missile.mdl",          -- РАКЕТЫ (rpg_missile)
        "models/weapons/w_irifle_ball.mdl",      -- ПЛАЗМА (энергошар AR2)
        "models/weapons/w_grenade.mdl",          -- ТЯЖЁЛЫЙ (граната)
        "models/crossbow_bolt.mdl",    -- резерв (арбалетный болт)
        "models/weapons/shell.mdl",              -- ПУЛЬСАР (гильза)
        "models/effects/combineball.mdl",        -- AI heavy (combine ball)
    }
    for _, m in ipairs(D6_PRECACHE_MDL) do util.PrecacheModel(m) end

    local D6_PRECACHE_SND = {
        "weapons/rpg/rocketfire1.wav", "weapons/rpg/rocket_explode.wav",
        "weapons/irifle/irifle_fire2.wav", "weapons/ar2/ar2_fire1.wav",
        "weapons/grenade/grenade_explode.wav", "weapons/crossbow/fire1.wav",
        "weapons/shotgun/shotgun_fire6.wav",
    }
    for _, s in ipairs(D6_PRECACHE_SND) do util.PrecacheSound(s) end
end

-- ═══════════════════════════════════════════════════════════
-- D6_TrackProjectile — надёжная детекция столкновений снаряда
-- ───────────────────────────────────────────────────────────
-- ВАЖНО: хука "EntityCollision" в GMod НЕ существует — старый код
-- на нём не детектил НИ ОДНОГО попадания. Реальный физический
-- контакт ловится через ENT:PhysicsCollide у d6_projectile и через
-- Entity:AddCallback("PhysicsCollide") у старых VPhysics-сущностей.
-- Внутри колбэка НЕЛЬЗЯ удалять энтить или спавнить эффекты —
-- вся реакция переносится в timer.Simple(0, ...).
--
--   ent   — снаряд
--   owner — стрелок (контакт с ним игнорируется)
--   onHit(ent, hitEnt, hitPos, hitNormal) — реакция на удар;
--           hitEnt == nil при истечении времени жизни
--   life  — секунд до самоликвидации (по умолчанию 5)
-- ═══════════════════════════════════════════════════════════
if SERVER then
    function D6_TrackProjectile(ent, owner, onHit, life, skipPhysics)
        if not IsValid(ent) then return end
        ent.D6_IsProjectile = true
        local handled = false

        local function Fire(hitEnt, hitPos, hitNormal)
            if handled then return end
            handled = true
            ent.D6_Impact = nil
            ent.D6_PhysicsImpact = nil
            local he, hp, hn = hitEnt, hitPos, hitNormal
            timer.Simple(0, function()
                if onHit and IsValid(ent) then onHit(ent, he, hp, hn) end
                if IsValid(ent) then ent:Remove() end
            end)
        end

        ent.D6_Impact = Fire
        if not skipPhysics then
            local function onCollision(_, data)
                local hitEnt = data.HitEntity
                if IsValid(hitEnt) then
                    if hitEnt == owner then return end
                    if hitEnt.D6_IsProjectile then return end
                else
                    hitEnt = game.GetWorld()
                end
                Fire(hitEnt, data.HitPos, data.HitNormal)
            end
            if ent:GetClass() == "d6_projectile" then ent.D6_PhysicsImpact = onCollision
            else ent:AddCallback("PhysicsCollide", onCollision) end
        end

        timer.Simple(life or 5, function()
            if IsValid(ent) then Fire(nil, ent:GetPos(), vector_up) end
        end)
    end
end

local function D6_Activate(ply)
    if not D6_Session.IsArena() or not D6_Mission.AllowsFlight() or not ply:Alive() or ply:InVehicle()
    or ply:GetMoveType() ~= MOVETYPE_WALK or ply.D6On then return end
    ply.D6LastInput  = CurTime()  -- [D6 idle] таймер бездействия
    ply.D6On        = true
    ply.D6OldModel  = ply:GetModel()
    ply.D6OldScale  = ply:GetModelScale()
    ply.D6Vel       = Vector(0, 0, 0)
    ply.D6ThrustCur = Vector(0, 0, 0)
    D6_Mobility.Reset(ply)
    ply.D6Ang       = nil
    ply.D6AngSynced = nil
    ply.D6AlwaysRun = false
    ply:SetNWBool("D6On", true)
    ply:SetNWBool("D6AlwaysRun", false)
    ply:SetModel(D6_Arsenal.Scanner.model)
    ply:SetModelScale(D6_Arsenal.Scanner.scale, 0)
    ply:SetVelocity(-ply:GetVelocity())

    net.Start("D6_Toggle")
        net.WriteEntity(ply); net.WriteBool(true)
    net.Broadcast()

    if D6_Session.GiveLoadout and not ply.D6_GivenForLife then
        D6_Session.GiveLoadout(ply)
        ply.D6_GivenForLife = true
        if IsValid(ply:GetWeapon(D6_Arsenal.Get(ply, 1))) then ply:SelectWeapon(D6_Arsenal.Get(ply, 1)) end
    end
end

local function D6_Deactivate(ply)
    if not ply.D6On then return end
    ply.D6On        = false
    D6_Mobility.Reset(ply)
    ply.D6Vel       = Vector(0, 0, 0)
    ply.D6ThrustCur = Vector(0, 0, 0)
    ply.D6AlwaysRun = false
    ply:SetNWBool("D6On", false)
    ply:SetNWBool("D6AlwaysRun", false)
    if ply.D6OldModel then ply:SetModel(ply.D6OldModel) end
    ply:SetModelScale(ply.D6OldScale or 1, 0)
    ply.D6OldModel, ply.D6OldScale, ply.D6Ang, ply.D6AngSynced, ply.D6AngApply = nil, nil, nil, nil, nil

    net.Start("D6_Toggle")
        net.WriteEntity(ply); net.WriteBool(false)
    net.Broadcast()

end

if SERVER then
    concommand.Add("6dof_toggle", function(ply)
        if not IsValid(ply) or not ply:Alive() then return end
        ply.D6On = ply.D6On or false
        if ply.D6On then
            D6_Deactivate(ply)
        elseif D6_Session.IsArena() and D6_Mission.AllowsFlight() then
            D6_Activate(ply)
        else
            ply:ChatPrint("[Abaddon] Управление полётом доступно в профиле арены.")
        end
    end)

    concommand.Add("6dof_alwaysrun", function(ply)
        if not IsValid(ply) or not ply.D6On then return end
        ply.D6AlwaysRun = not ply.D6AlwaysRun
        ply:SetNWBool("D6AlwaysRun", ply.D6AlwaysRun)
        net.Start("D6_AlwaysRunSync")
            net.WriteEntity(ply); net.WriteBool(ply.D6AlwaysRun)
        net.Broadcast()
        ply:PrintMessage(HUD_PRINTTALK,
            "[6DOF] Always-Run: " .. (ply.D6AlwaysRun and "ON ▶▶" or "OFF"))
    end)

    concommand.Add("6dof_flightassist", function(ply)
        if not IsValid(ply) or not ply.D6On then return end
        ply.D6_FlightAssist = ply.D6_FlightAssist == false
        ply:SetNWBool("D6_FlightAssist", ply.D6_FlightAssist)
        ply:PrintMessage(HUD_PRINTTALK, "[6DOF] Flight Assist: "
            .. (ply.D6_FlightAssist and "ON" or "OFF (Ньютон)"))
    end)

    -- Смена оружия колесом мыши (клиент отправляет classname)
    local _D6_WHEEL_WEPS = {
        ["weapon_d6_mg"]=true, ["weapon_d6_plasma"]=true,
        ["weapon_d6_heavy"]=true, ["weapon_d6_laser"]=true,
        ["weapon_d6_rockets"]=true, ["weapon_d6_gravy_railgun"]=true,
    }
    net.Receive("D6_WeaponSwitch", function(_, ply)
        if not IsValid(ply) then return end
        local class = net.ReadString()
        if not _D6_WHEEL_WEPS[class] then return end
        if IsValid(ply:GetWeapon(class)) then
            ply:SelectWeapon(class)
        end
    end)

    net.Receive("D6_RocketSubNext", function(_, ply)
        if not IsValid(ply) then return end
        local w = ply:GetActiveWeapon()
        if not IsValid(w) or w:GetClass() ~= "weapon_d6_rockets" then return end
        local sub = (ply:GetNWInt("D6_RktSub", 0) + 1) % 4
        ply:SetNWInt("D6_RktSub", sub)
        w:SetNWInt("D6_RktSub", sub)
        ply:EmitSound("buttons/blip1.wav", 65, 120)
    end)

    concommand.Add("d6_set", function(ply, _, args)
        if not IsValid(ply) then return end
        if not ply:IsAdmin() and not ply:IsListenServerHost() then
            ply:PrintMessage(HUD_PRINTTALK, "[D6] Нет прав (нужен admin)")
            return
        end
        local k, v = args[1], tonumber(args[2])
        if not k or not v then return end
        ply.D6_Params = ply.D6_Params or {}
        ply.D6_Params[k] = v
    end)

    concommand.Add("d6_kill_npcs", function(ply)
        if not D6_Session.CanEditWorld(ply) then return end
        local n = 0
        for _, e in ipairs(D6_Actors.GetAll()) do
            if IsValid(e) and e.D6_Variant then e:Remove(); n = n + 1 end
        end
        for _, e in ipairs(ents.FindByClass("d6_ordnance")) do
            if IsValid(e) and (e.D6_Variant or e.IsAirMine) then e:Remove(); n = n + 1 end
        end
        ply:PrintMessage(HUD_PRINTTALK, "[D6] Удалено: " .. n)
    end)

    concommand.Add("d6_reset_roll", function(ply)
        if not IsValid(ply) then return end
        if ply.D6AngSynced then ply.D6AngSynced.r = 0; ply:SetAngles(ply.D6AngSynced) end
    end)

    hook.Add("PlayerSpawn", "D6_Reset", function(ply)
        ply.D6On, ply.D6_GivenForLife = false, false
        ply.D6OldModel, ply.D6OldScale, ply.D6Ang, ply.D6AngSynced, ply.D6AngApply = nil, nil, nil, nil, nil
        D6_Mobility.Reset(ply)
        ply.D6AlwaysRun = false
        ply.D6Vel, ply.D6ThrustCur = nil, nil
        ply:SetNWBool("D6On", false)
        ply:SetNWBool("D6AlwaysRun", false)

        timer.Simple(0, function()
            if IsValid(ply) then D6_Activate(ply) end
        end)
    end)

    hook.Add("PlayerEnteredVehicle", "D6_LeaveFlight", D6_Deactivate)
    hook.Add("PlayerDeath", "D6_ResetOnDeath", D6_Deactivate)
    cvars.AddChangeCallback("d6_profile", function()
        if D6_Session.IsArena() then return end
        for _, ply in ipairs(player.GetAll()) do D6_Deactivate(ply) end
    end, "D6_ProfileChange")

end

-- ── Синхронизация угла ────────────────────────────────────
if SERVER then
    net.Receive("D6_AngSync", function(_, sender)
        if not IsValid(sender) or not sender.D6On then return end
        local now = CurTime()
        if now < (sender.D6AngApply or 0) then return end
        sender.D6AngApply = now + ANG_RATE
        local ang = net.ReadAngle()
        if ang.p ~= ang.p or ang.y ~= ang.y or ang.r ~= ang.r then return end
        sender.D6AngSynced = ang
        sender:SetAngles(ang)
        net.Start("D6_AngSync", true)
        net.WriteEntity(sender)
        net.WriteAngle(ang)
        net.SendOmit(sender)

    end)
end

-- One movement step owns propulsion, adhesion and collision for the server.
if SERVER then
    hook.Add("SetupMove", "D6_Flight_Move", function(ply, move, command)
        if not ply.D6On or ply:InVehicle() or ply:GetMoveType() ~= MOVETYPE_WALK then return end
        local dt = engine.TickInterval()
        local params = ply.D6_Params or {}
        local mobility = D6_Mobility
        local origin = move:GetOrigin()
        local mins, maxs = ply:GetHull()
        if ply:Crouching() then mins, maxs = ply:GetHullDuck() end
        local center = ply:WorldSpaceCenter() + origin - ply:GetPos()
        local input = mobility.Steering(command)
        if input:LengthSqr() > 1 then input:Normalize() end
        ply.D6Vel = ply.D6Vel or Vector()
        ply.D6ThrustCur = ply.D6ThrustCur or Vector()
        local previousSpeed = ply.D6Vel:Length()
        local attached, carry, braking = mobility.Step(ply, command, dt, center, (maxs - mins)*0.5)
        local active = input:LengthSqr() > 0 or attached or braking or ply.D6DashOn
            or command:KeyDown(IN_ATTACK) or command:KeyDown(IN_ATTACK2)
        local now = CurTime()
        if active then ply.D6LastInput = now end
        local lastInput = ply.D6LastInput or now
        if now >= (ply.D6_NextInputSync or 0) then
            ply:SetNWFloat("D6LastInput", lastInput)
            ply.D6_NextInputSync = now + 0.20
        end

        if ply.D6AlwaysRun and active and not D6_Energy.TryConsume(ply, "engines", 6*dt) then
            ply.D6AlwaysRun = false
            ply:SetNWBool("D6AlwaysRun", false)
            net.Start("D6_AlwaysRunSync")
            net.WriteEntity(ply)
            net.WriteBool(false)
            net.Broadcast()
        end

        local engines = D6_Energy.GetAlloc(ply, "engines")
        local boost = ply.D6AlwaysRun and Lerp(engines, 1.3, 1.9) or 1
        local angles = command:GetViewAngles()
        local thrust = (angles:Forward()*input.x + angles:Right()*(input.y*CFG.strafeMult)
            + angles:Up()*(input.z*CFG.vertMult)) * (params.accel or CFG.accel)*boost
        local spool = thrust:LengthSqr() >= ply.D6ThrustCur:LengthSqr() and CFG.spoolUp or CFG.spoolDown
        ply.D6ThrustCur = LerpVector(math.min(dt*spool, 1), ply.D6ThrustCur, thrust)
        local inertia = Lerp(carry, 1, 0.18)
        if attached then inertia = math.min(inertia, 0.34) end
        local vel = ply.D6Vel * CFG.inertia^(dt*60*inertia) + ply.D6ThrustCur*dt
        local idle = math.Clamp((now - lastInput - CFG.idleGravSec)/CFG.idleGravRamp, 0, 1)
        vel.z = vel.z - (20 + (params.gravity or CFG.gravity)*idle)*dt

        local speed = vel:Length()
        if speed > 0 then
            local drag = speed*speed*0.000020*(params.drag or CFG.drag)*dt*inertia
            if ply.D6_FlightAssist ~= false and not active then drag = drag + speed*CFG.brakeMult*dt end
            local cruise = (params.maxSpeed or CFG.maxSpeed) *(ply.D6AlwaysRun and Lerp(engines, 1.3, 1.8) or 1)
            local cap = math.max(cruise, previousSpeed*math.exp(-dt*1.8))
            if attached or carry > 0 then cap = math.max(cap, mobility.BurstSpeed) end
            local finalSpeed = math.Clamp(speed - drag, 0, cap)
            if finalSpeed < 2 and not active and ply.D6_FlightAssist ~= false then finalSpeed = 0 end
            vel = vel*(finalSpeed/speed)
        end
        ply.D6Vel = vel

        if not D6_Gates.MovePlayer(ply, move, command, dt) then
            local impact = util.TraceHull({start = origin, endpos = origin + vel*dt, filter = ply,
                mins = mins, maxs = maxs, mask = MASK_PLAYERSOLID_BRUSHONLY})
            local inward = impact.Hit and vel:Dot(impact.HitNormal) or 0
            if inward < 0 then
                -- During a manoeuvre, keep the tangential component along the surface.
                local bounce = (attached or carry > 0 or braking) and 0 or CFG.wallBounce
                ply.D6Vel = vel - impact.HitNormal*inward*(1 + bounce)
            end
        end
        move:SetVelocity(ply.D6Vel)
        move:SetForwardSpeed(0)
        move:SetSideSpeed(0)
        move:SetUpSpeed(0)
        command:SetForwardMove(0)
        command:SetSideMove(0)
        command:SetUpMove(0)
    end)
end

print("[D6] d6_core.lua OK")
