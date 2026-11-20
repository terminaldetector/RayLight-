-- ═══════════════════════════════════════════════════════════
-- d6_ai_roles.lua — Ролевые AI для Descent 6DOF
-- Пять ролей мигрированы на модульную систему (d6_modules.lua).
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
