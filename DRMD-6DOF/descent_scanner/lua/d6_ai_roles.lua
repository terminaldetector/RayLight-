-- ═══════════════════════════════════════════════════════════
-- d6_ai_roles.lua — роли и координация перехватчиков.
-- SpawnD6Role() — публичный API: энкаунтеры, сущности, консоль.
-- ═══════════════════════════════════════════════════════════
if not SERVER then return end

-- ─── Boids exclusion ─────────────────────────────────────
D6_FragsBoidsExclude                = D6_FragsBoidsExclude or {}
D6_FragsBoidsExclude["assault"]     = true
D6_FragsBoidsExclude["interceptor"] = true
D6_FragsBoidsExclude["artillery"]   = true
D6_FragsBoidsExclude["support"]     = true
D6_FragsBoidsExclude["heavy_elite"] = true
D6_FragsBoidsExclude["arc_elite"] = true

-- ─── Loadouts ─────────────────────────────────────────────
-- Поля: ai, slots, hp, scale, color, speed, rangeMin, rangeMax,
--        retreatHP, retreatDist, chargeDist, chargeCD, chargeDur, chargeSpeed,
--        healRadius, healAmt, healInterval,
--        shield, shieldMax, armor, armorMax, resist={kinetic,energy,explosive}
local LOADOUTS = {
    assault = {
        ai    = "pressure",
        slots = { primaryL = "Pulsar", primaryR = "Pulsar" },
        hp = 200, scale = 1.2, color = Color(255, 80, 80),
        speed = 540, rangeMin = 400, rangeMax = 600,
        retreatHP = 0.30,
        shield = 50, shieldMax = 50, armor = 0, armorMax = 0,
        resist = { kinetic = 0, energy = 0.1, explosive = 0 },
        phys = {
            flightMode = "physics",
            -- balanced baseline — moderate speed, turn and bank
            mass = 80,   spoolUp = 9,  spoolDown = 3, velLerp = 5,  maxSpeed = 780,
            angPower = 240, angInertia = 0.87, angSpinSup = 0.18, angMax = 400,
            rollMul = 1.0, bankGain = 1.1, bankMax = 50,
        },
    },
    interceptor = {
        ai    = "flank",
        intercept = true,
        slots = { primaryL = "Laser", primaryR = "Laser" },
        hp = 150, scale = 1.0, color = Color(80, 255, 200),
        speed = 860, rangeMin = 250, rangeMax = 500,
        shield = 30, shieldMax = 30, armor = 0, armorMax = 0,
        resist = { kinetic = 0, energy = 0, explosive = 0 },
        phys = {
            flightMode = "physics",
            -- fast, aggressive, HIGH ROLL AUTHORITY — darts and banks hard
            mass = 45,   spoolUp = 14, spoolDown = 2, velLerp = 7,  maxSpeed = 1100,
            angPower = 380, angInertia = 0.80, angSpinSup = 0.12, angMax = 520,
            rollMul = 2.2, bankGain = 1.8, bankMax = 78,
        },
    },
    artillery = {
        ai    = "standoff",
        slots = { primaryR = "Missile" },
        hp = 180, scale = 1.3, color = Color(255, 200, 0),
        speed = 240, rangeMin = 1500, rangeMax = 2500,
        retreatDist = 800,
        shield = 0, shieldMax = 0, armor = 60, armorMax = 60,
        resist = { kinetic = 0.2, energy = 0, explosive = 0.1 },
        phys = {
            flightMode = "physics",
            -- distance-focused — slow, stable gun platform, barely banks
            mass = 150,  spoolUp = 4,  spoolDown = 2, velLerp = 3,  maxSpeed = 460,
            angPower = 130, angInertia = 0.93, angSpinSup = 0.25, angMax = 240,
            rollMul = 0.7, bankGain = 0.5, bankMax = 22,
        },
    },
    support = {
        ai    = "support",
        slots = { utility = "RepairBeam" },
        hp = 220, scale = 1.1, color = Color(100, 255, 100),
        speed = 600, healRadius = 300, healAmt = 4, healInterval = 0.5,
        shield = 40, shieldMax = 40, armor = 20, armorMax = 20,
        resist = { kinetic = 0, energy = 0.15, explosive = 0 },
        phys = {
            flightMode = "physics",
            -- high strafe capability — darts sideways fast, stays flat (utility)
            mass = 58,   spoolUp = 13, spoolDown = 4, velLerp = 8,  maxSpeed = 840,
            angPower = 200, angInertia = 0.84, angSpinSup = 0.16, angMax = 420,
            rollMul = 1.0, bankGain = 0.8, bankMax = 38,
        },
    },
    heavy_elite = {
        ai    = "anchor",
        slots = { primaryL = "EnforcerBattery", core = "ShieldGenerator" },
        hp = 960, scale = D6_Session.Enforcer.scale, hull = D6_Session.Enforcer, color = Color(40, 40, 40),
        speed = 205, rangeMin = 660, rangeMax = 1280,
        chargeDist = 680, chargeCD = 11, chargeDur = 0.45, chargeSpeed = 590,
        shield = 170, shieldMax = 170, armor = 130, armorMax = 130,
        resist = { kinetic = 0.2, energy = 0.2, explosive = 0.3 },
        phys = {
            flightMode = "physics",
            -- massive, deliberate, threatening — turns like a capital ship
            mass = 260,  spoolUp = 2.5, spoolDown = 1, velLerp = 1.6, maxSpeed = 440,
            angPower = 75,  angInertia = 0.97, angSpinSup = 0.30, angMax = 160,
            rollMul = 0.4, bankGain = 0.3, bankMax = 14,
        },
    },
    arc_elite = {
        ai="anchor", appearance="arc_elite", slots={primaryL="ArcBattery"},
        hp=1040, scale=D6_Session.ArcElite.scale, hull=D6_Session.ArcElite,
        color=Color(162,182,186), speed=260, rangeMin=635, rangeMax=1320,
        chargeDist=440, chargeCD=8.6, chargeDur=0.38, chargeSpeed=690,
        shield=175, shieldMax=175, armor=145, armorMax=145,
        resist={kinetic=.16, energy=.26, explosive=.08},
        phys={flightMode="physics", mass=317, spoolUp=3.8, spoolDown=2.1, velLerp=2.8,
            maxSpeed=470, angPower=97, angInertia=.94, angSpinSup=.29, angMax=198,
            rollMul=.53, bankGain=.42, bankMax=24},
    },
}

local salvageRoles = {
    resistance_scout = {base = "interceptor", hp = 110, armor = 16, scale = 1.05,
        slots = {primaryL = "Pulsar"}, color = Color(136, 113, 74)},
    resistance_raider = {base = "assault", hp = 185, armor = 36, scale = 1.21,
        slots = {primaryL = "Pulsar", primaryR = "Pulsar"}, color = Color(140, 92, 63)},
    resistance_hauler = {base = "heavy_elite", hp = 470, armor = 78, scale = 1.44,
        slots = {primaryL = "Pulsar", primaryR = "Missile"}, color = Color(117, 105, 84)},
}
for name, parts in pairs(salvageRoles) do
    local role = table.Copy(LOADOUTS[parts.base])
    role.hull = nil
    role.appearance = name
    role.hp, role.scale, role.slots, role.color = parts.hp, parts.scale, parts.slots, parts.color
    role.shield, role.shieldMax = 0, 0
    role.armor, role.armorMax = parts.armor, parts.armor
    role.resist = {kinetic = 0.10, energy = 0, explosive = 0}
    LOADOUTS[name] = role
    D6_FragsBoidsExclude[name] = true
end

-- The approach frame is fixed for the engagement. It follows the target's
-- position and does not swivel whenever the pilot rolls or moves the camera.
local interceptGroups = setmetatable({}, {__mode = "k"})
local sectors = {
    {1,.72,.36}, {1,-.72,.36}, {1,.56,-.55}, {1,-.56,-.55},
    {-.55,.93,.51}, {-.55,-.93,.51},
}
local windupTime, passTime, recoveryTime = .27, .55, .72

local function endInterceptWarning(npc)
    npc:SetNWFloat("D6_ThreatAt", 0)
    npc:StopSound("ambient/energy/zap_loop1.wav")
end

local function releaseIntercept(npc)
    local run = npc.D6_Intercept
    if not run then return end
    local group = run.group
    if group.active == run then group.active = nil end
    group.lanes[run.lane] = nil
    if next(group.lanes) == nil then group.groups[group.faction] = nil end
    if IsValid(npc) and run.phase == "windup" then endInterceptWarning(npc) end
    npc.D6_Intercept = nil
end

hook.Add("OnNPCKilled", "D6_ReleaseIntercept", releaseIntercept)

local function laneTrace(npc, from, to, extents)
    return util.TraceHull({start=from, endpos=to, mins=-extents, maxs=extents,
        filter=npc, mask=MASK_NPCSOLID_BRUSHONLY})
end

local function claimIntercept(npc, target, origin, center, radius, extents)
    local groups = interceptGroups[target]
    if not groups then
        groups = {}
        interceptGroups[target] = groups
    end
    local art = D6_Drones.Get(npc)
    local faction = art and art.faction or "combine"
    local group = groups[faction]
    if not group then
        local radial = origin - center
        local heading = radial:LengthSqr() > 1 and radial:Angle() or npc:GetAngles()
        group = {lanes={}, heading=heading, faction=faction, groups=groups}
    end

    local lane, ray, cost
    local heading = group.heading
    local forward, right, up = heading:Forward(), heading:Right(), heading:Up()
    for index, sector in ipairs(sectors) do
        if not group.lanes[index] then
            local radial = (forward*sector[1] + right*sector[2] + up*sector[3]):GetNormalized()
            local goal = center + radial*radius
            if util.IsInWorld(goal) and not laneTrace(npc, goal, goal, extents).Hit then
                local blocked = laneTrace(npc, origin, goal, extents).Hit
                local score = origin:DistToSqr(goal) + (blocked and radius*radius*4 or 0)
                if not cost or score < cost then lane, ray, cost = index, radial, score end
            end
        end
    end
    if not lane then return end

    local run = {group=group, lane=lane, ray=ray, target=target, phase="approach"}
    groups[faction], group.lanes[lane] = group, run
    npc.D6_Intercept = run
    npc:CallOnRemove("D6_ReleaseIntercept", releaseIntercept)
    return run
end

local function steerTo(npc, offset, speed)
    local distance = offset:Length()
    npc.D6_DesiredVel = distance > 1 and offset/distance*math.min(speed, distance*3.2) or vector_origin
end

local function interceptSight(npc, target, origin, center)
    return not util.TraceLine({start=origin, endpos=center, filter={npc,target}, mask=MASK_SHOT}).Hit
end

local function canCommit(run)
    if run.group.active then return false end
    for _, other in pairs(run.group.lanes) do
        if other.ready and (other.ready < run.ready or (other.ready == run.ready and other.lane < run.lane)) then
            return false
        end
    end
    return true
end

-- Returns the existing dispatcher fire permission. The module still owns
-- the socket trace, projectile, energy and cooldown, including swarm turns.
function D6_RunInterceptor(npc, loadout, target, now)
    npc.D6_RoleState = 1
    local run = npc.D6_Intercept
    if run and (run.target ~= target or not IsValid(target)) then
        releaseIntercept(npc)
        npc.D6_InterceptRetryAt = nil
        run = nil
    end
    if not IsValid(target) then
        npc.D6_InterceptRetryAt = nil
        return false
    end

    npc.D6_RoleState = 2
    local origin, center = npc:GetPos(), target:WorldSpaceCenter()
    local rMax = loadout.rangeMax or 500
    local radius, speed = rMax*.86, loadout.speed or 750
    local hull = math.max(14, 16*(loadout.scale or 1)*(loadout.collisionScale or 1))
    local extents = Vector(hull,hull,hull)
    if not run and now >= (npc.D6_InterceptRetryAt or 0) then
        run = claimIntercept(npc, target, origin, center, radius, extents)
        npc.D6_InterceptRetryAt = now + .36
    end
    if not run then
        if origin:DistToSqr(center) > (radius*1.6)^2 then steerTo(npc, center-origin, speed*.45) end
        return false
    end

    local distanceSqr = origin:DistToSqr(center)
    local tooClose = distanceSqr < (math.min(loadout.rangeMin or 250, rMax*.55)*.75)^2
    local canSee = distanceSqr <= rMax*rMax and interceptSight(npc, target, origin, center)
    if run.phase == "windup" then
        if now >= run.untilTime and canSee and not tooClose then
            local side = run.group.heading:Right()*(sectors[run.lane][2] < 0 and -1 or 1)
            local exit = center + target:GetVelocity()*.16 + side*radius*.42
            local direction = (exit-origin):GetNormalized()
            if not laneTrace(npc, origin, origin + direction*115, extents).Hit then
                endInterceptWarning(npc)
                run.phase, run.untilTime, run.direction = "pass", now + passTime, direction
            end
        end
    end
    if run.phase == "pass" and now < run.untilTime and canSee and not tooClose then
        npc.D6_RoleState = 3
        npc.D6_DesiredVel = run.direction*speed
        run.goal = origin + run.direction*radius
        return true
    end
    if (run.phase == "windup" and (now >= run.untilTime or not canSee or tooClose)) or run.phase == "pass" then
        -- Hide a cancelled warning immediately, then clear the lane of fire.
        if run.phase == "windup" then endInterceptWarning(npc) end
        run.phase, run.untilTime, run.group.active = "recover", now + recoveryTime, nil
    end
    if run.phase == "recover" and now >= run.untilTime then
        releaseIntercept(npc)
        npc.D6_InterceptRetryAt = now + .45
        return false
    end

    local goal = center + run.ray*radius*(run.phase == "recover" and 1.22 or 1)
    run.goal = goal
    if run.phase == "approach" then
        if now >= (run.nextLaneCheck or 0) then
            run.nextLaneCheck = now + .45
            if not util.IsInWorld(goal) or laneTrace(npc, goal, goal, extents).Hit then
                releaseIntercept(npc)
                return false
            end
        end
        if canSee and not tooClose and origin:DistToSqr(goal) < 110^2 and npc:GetVelocity():LengthSqr() < 450^2 then
            run.ready = run.ready or now
            if canCommit(run) then
                run.group.active, run.ready = run, nil
                run.phase, run.untilTime = "windup", now + windupTime
                D6_Patterns.Warn(npc, center, windupTime, false)
            end
        else
            run.ready = nil
        end
    end
    steerTo(npc, goal-origin, speed*(run.phase == "recover" and 1 or .64))
    return false
end

-- ─── Public API — thin wrapper over D6_BuildDrone ─────────
-- Доступ к стоковым ролям для NPC Workshop (клонирование в профили).
function D6_GetRoleLoadout(variant)
    return LOADOUTS[variant]
end

function D6_GetRoleNames()
    local names = {}
    for name in pairs(LOADOUTS) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function SpawnD6Role(variant, pos, targetPly)
    local lo = LOADOUTS[variant]
    -- NPC Workshop: кастомные профили (DATA/drmd_npcs) как фолбэк —
    -- энкаунтеры, волны и d6_npc_spawner понимают их без изменений.
    if not lo and D6_NPCWorkshop and D6_NPCWorkshop.ToLoadout then
        lo = D6_NPCWorkshop.ToLoadout(variant)
    end
    if not lo then
        MsgC(Color(255, 100, 0), "[D6 Roles] Unknown variant: " .. tostring(variant) .. "\n")
        return nil
    end
    if lo.hull then
        local hull = lo.hull
        local space = util.TraceHull({start = pos, endpos = pos, mask = MASK_NPCSOLID_BRUSHONLY,
            mins = Vector(-hull.radius, -hull.radius, -hull.below), maxs = Vector(hull.radius, hull.radius, hull.above)})
        if space.Hit or not util.IsInWorld(pos) then return end
    end
    local npc = D6_BuildDrone(lo, pos, targetPly)
    if IsValid(npc) then
        D6_Session.SetVariant(npc, variant, targetPly)
    end
    return npc
end

-- ─── Console commands ─────────────────────────────────────
for _, v in ipairs(D6_GetRoleNames()) do
    local vname = v
    concommand.Add("6dof_spawn_" .. vname, function(ply)
        if not IsValid(ply) or (salvageRoles[vname] and not D6_Session.IsArena()) then return end
        local tr  = ply:GetEyeTrace()
        local offset = 50
        local hull=LOADOUTS[vname].hull
        if hull then
            local normal = tr.HitNormal
            offset = (math.abs(normal.x)+math.abs(normal.y))*hull.radius
                + math.max(normal.z, 0)*hull.below + math.max(-normal.z, 0)*hull.above + 15
        end
        local pos = tr.HitPos + tr.HitNormal*offset
        SpawnD6Role(vname, pos, ply)
        ply:PrintMessage(HUD_PRINTTALK, "[Abaddon] " .. (vname=="arc_elite" and "Элитный дуговой штурмовик"
            or D6_Session.Resistance[vname] or vname))
    end)
end

print("[D6] d6_ai_roles.lua loaded")
