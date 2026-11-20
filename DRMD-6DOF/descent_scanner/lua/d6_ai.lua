if not SERVER then return end

local COLORS = {
    mine  = Color(255, 180, 0),
    mg    = Color(255, 40,  40),
    rpg   = Color(40,  100, 255),
    grav  = Color(160, 40,  255),
    laser = Color(0,   255, 255),
    heavy = Color(20,  20,  20),
}

local MINE_DRIFT_SPEED   = 45
local MINE_TRIGGER_DIST  = 160
local MINE_BLIP_INTERVAL = 1.2

local function SafeGetPhys(ent)
    if not IsValid(ent) then return nil end
    local ph = ent:GetPhysicsObject()
    return IsValid(ph) and ph or nil
end

function SpawnEnemyDrone(ply, class, variant, customPos)
    local npc = ents.Create(class)
    if not IsValid(npc) then return end
    if customPos then
        npc:SetPos(customPos)
    else
        local tr = ply:GetEyeTrace()
        npc:SetPos(tr.HitPos + tr.HitNormal * 50)
    end
    npc:Spawn()
    npc:Activate()
    D6_Session.SetVariant(npc, variant, ply)
    npc.D6_NextAttack     = CurTime()
    npc.D6_NextDodge      = CurTime() + 1
    npc.D6_NextThrow      = 0
    npc.D6_NextCatchScan  = 0
    npc.D6_PatrolTarget   = nil
    npc.D6_PatrolTimeout  = 0
    npc:SetRenderMode(RENDERMODE_TRANSCOLOR)
    npc:SetColor(COLORS[variant] or color_white)
    if variant == "mg" then
        npc:SetModelScale(1.0, 0); npc:SetMaxHealth(120); npc:SetHealth(120)
    elseif variant == "heavy" then
        -- [D6 AI] heavy теперь визуально отличим: используем dropship.mdl × 0.15
        npc:SetModel("models/combine_dropship.mdl")
        npc:SetModelScale(0.15, 0)
        npc:SetMaxHealth(450); npc:SetHealth(450)
    elseif variant == "seeker" then
        -- [D6 AI] seeker — крупнее dropship × 0.18 + фиолетовый цвет
        npc:SetModel("models/combine_dropship.mdl")
        npc:SetModelScale(0.18, 0)
        npc:SetMaxHealth(280); npc:SetHealth(280)
        npc:SetColor(Color(180, 80, 220))
    else
        npc:SetModelScale(1.4, 0); npc:SetMaxHealth(150); npc:SetHealth(150)
    end
    npc:AddEntityRelationship(ply, D_HT, 99)
    return npc
end

concommand.Add("6dof_spawn_mine",  function(ply) SpawnEnemyDrone(ply, "npc_cscanner", "mine")  end)
concommand.Add("6dof_spawn_mg",    function(ply) SpawnEnemyDrone(ply, "npc_cscanner", "mg")    end)
concommand.Add("6dof_spawn_rpg",   function(ply) SpawnEnemyDrone(ply, "npc_cscanner", "rpg")   end)
concommand.Add("6dof_spawn_grav",  function(ply) SpawnEnemyDrone(ply, "npc_cscanner", "grav")  end)
concommand.Add("6dof_spawn_laser", function(ply) SpawnEnemyDrone(ply, "npc_cscanner", "laser") end)
concommand.Add("6dof_spawn_heavy", function(ply) SpawnEnemyDrone(ply, "npc_cscanner", "heavy") end)

concommand.Add("6dof_spawn_squad", function(ply)
    local tr      = ply:GetEyeTrace()
    local basePos = tr.HitPos + tr.HitNormal * 60
    local layout  = { "heavy", "mg", "mg", "rpg", "laser", "mine" }
    for i, variant in ipairs(layout) do
        local angle  = (i / #layout) * math.pi * 2
        local offset = Vector(math.sin(angle) * 120, math.cos(angle) * 120, 40)
        SpawnEnemyDrone(ply, "npc_cscanner", variant, basePos + offset)
    end
    ply:PrintMessage(HUD_PRINTTALK, "[ОТРЯД] Тактическое звено Альянса развернуто!")
end)

concommand.Add("6dof_spawn_airmine", function(ply)
    local tr       = ply:GetEyeTrace()
    local spawnPos = tr.HitPos + tr.HitNormal * 70
    if tr.HitNormal.z == 0 then spawnPos.z = spawnPos.z + 80 end
    local mine, phys = D6_Wep.Ordnance("mine_air", spawnPos, ply, {mobile = true, mass = 16, group = COLLISION_GROUP_PROJECTILE})
    if not IsValid(mine) then return end
    phys:SetDamping(8,8)
    mine.IsAirMine = true
    mine:SetNWBool("D6_MineArmed", true)
    mine.NextScan  = CurTime()
    mine.NextBlip  = CurTime()
    mine.NextDrift = CurTime()
end)

local D6_LegacyFire = {
    mg = {move=535,standoff=390,range=1150,cooldown=1.42,windup=0.22,burst=4,interval=0.104,
        kind="kinetic",speed=1460,damage=9,spread=.069,sound="weapons/ar2/ar2_fire1.wav"},
    laser = {move=640,standoff=550,range=1350,cooldown=1.76,windup=0.42,burst=3,interval=0.128,
        kind="energy",art="shot_arcpulse",speed=1710,damage=14,spread=.048,sound="weapons/irifle/irifle_fire2.wav"},
    rpg = {move=435,standoff=760,range=1710,cooldown=2.92,windup=0.62,burst=2,interval=0.23,
        kind="explosive",art="shot_homing",speed=1140,damage=29,spread=.102,sound="weapons/rpg/rocketfire1.wav"},
    heavy = {move=330,standoff=705,range=1560,cooldown=2.65,windup=0.7,burst=1,interval=0,
        kind="energy",art="shot_ion",speed=975,damage=38,spread=0,sound="ambient/energy/zap5.wav"},
}

local _D6PropCache    = {}; local _D6PropT    = 0
local _D6ScannerCache = {}; local _D6ScannerT = 0

-- =========================================================
-- ГЛАВНЫЙ AI THINK
-- =========================================================
hook.Add("Think", "D6_AI_Core", function()
    if not D6_Session.IsArena() then return end
    local ct = CurTime()
    if ct - _D6PropT    > 0.12 then _D6PropCache    = ents.FindByClass("d6_ordnance");  _D6PropT    = ct end
    if ct - _D6ScannerT > 0.10 then _D6ScannerCache = ents.FindByClass("npc_cscanner"); _D6ScannerT = ct end

    -- ── 1. Воздушные мины ─────────────────────────────────
    for _, mine in ipairs(_D6PropCache) do
        if not mine.IsAirMine then continue end
        if not IsValid(mine) then continue end
        local minePos = mine:GetPos()
        if ct > (mine.NextBlip or 0) then
            mine:EmitSound("buttons/button14.wav", 60, 120)
            mine.NextBlip = ct + MINE_BLIP_INTERVAL
        end
        if ct > (mine.NextDrift or 0) then
            mine.NextDrift = ct + 0.2
            local closestPly, minDist = nil, 9999999
            for _, p in ipairs(player.GetAll()) do
                if p:Alive() then
                    local d = minePos:Distance(p:GetPos())
                    if d < minDist then minDist = d; closestPly = p end
                end
            end
            if IsValid(closestPly) then
                local phys = SafeGetPhys(mine)
                if phys then
                    local driftDir = (closestPly:GetPos() - minePos):GetNormalized()
                    phys:SetVelocity(LerpVector(0.15, phys:GetVelocity(), driftDir * MINE_DRIFT_SPEED))
                end
            end
        end
        if ct > (mine.NextScan or 0) then
            mine.NextScan = ct + 0.15
            for _, ent in ipairs(ents.FindInSphere(minePos, MINE_TRIGGER_DIST)) do
                if (ent:IsPlayer() or ent:IsNPC()) and ent:GetClass() ~= "npc_cscanner" then
                    mine:EmitSound("ambient/explosions/explode_1.wav", 90, 100)
                    local explode = ents.Create("env_explosion")
                    if IsValid(explode) then
                        explode:SetPos(minePos)
                        explode:Spawn()
                        explode:SetKeyValue("iMagnitude", "120")
                        explode:Fire("Explode", 0, 0)
                        timer.Simple(0.1, function() if IsValid(explode) then explode:Remove() end end)
                    end
                    mine:Remove()
                    break
                end
            end
        end
    end

    local dt = math.min(FrameTime(), 0.06)
    for _, npc in ipairs(_D6ScannerCache) do
        if not IsValid(npc) or npc:Health() <= 0 then continue end
        local spec = D6_LegacyFire[npc.D6_Variant]
        local body = spec and SafeGetPhys(npc)
        if not body then continue end
        local plan = D6_Swarm.GetPlan(npc)
        local enemy = plan and plan.target or npc:GetEnemy()
        local center = npc:WorldSpaceCenter()
        if not IsValid(enemy) or not enemy:IsPlayer() or not enemy:Alive() or not enemy:GetNWBool("D6On") then continue end
        local point = enemy:WorldSpaceCenter()
        local travel = point-center
        local dist = travel:Length()
        local aim = travel:Angle()
        if npc.D6_FireAim and (npc.D6_BraceUntil or 0)>ct then
            aim=(npc.D6_FireAim-center):Angle()
        end
        local previous = npc:GetAngles()
        aim.r = math.Clamp(math.AngleDifference(previous.y,aim.y)*0.54, -28, 28)
        npc:SetAngles(LerpAngle(dt*6,previous,aim))
        local desired = aim:Forward()*math.Clamp((dist-spec.standoff)*1.72,-285,480)
            + aim:Right()*(npc:EntIndex()%2 == 0 and 84 or -84)
        if ct < (npc.D6_BreakUntil or 0) then desired = desired + (npc.D6_BreakVector or vector_origin) end
        if dist < 1100 and ct > (npc.D6_NextDodge or 0) and enemy:EyeAngles():Forward():Dot(-aim:Forward()) > 0.92 then
            npc.D6_NextDodge = ct+math.Rand(1.7,2.6)
            npc.D6_BreakUntil = ct+0.26
            npc.D6_BreakVector = aim:Right()*(npc:EntIndex()%2 == 0 and 510 or -510)+aim:Up()*129
        end
        desired = D6_Swarm.Steering(npc, desired, spec.move)
        if (npc.D6_BraceUntil or 0)>ct then desired=desired*.25 end
        body:SetVelocity(LerpVector(dt*4.8,body:GetVelocity(),desired))
        body:EnableGravity(false)
        body:AddAngleVelocity(-body:GetAngleVelocity()*dt*9)
        if dist <= spec.range and dist > 140 and ct >= (npc.D6_NextAttack or 0) and D6_Swarm.AllowsFire(npc, ct)
            and not util.TraceLine({start = center, endpos = point, filter = {npc,enemy}, mask = MASK_SHOT}).Hit then
            npc.D6_NextAttack = ct+spec.cooldown
            D6_Patterns.Warn(npc,point,spec.windup,spec.kind=="explosive" or npc.D6_Variant=="laser")
            for i=1,spec.burst do
                timer.Simple(spec.windup+(i-1)*spec.interval, function()
                    if not IsValid(npc) or not IsValid(enemy) or npc:Health() <= 0 or not enemy:Alive() or not D6_Session.IsArena() then return end
                    local side = i%2 == 0 and 1 or -1
                    local steered = spec.kind == "explosive" and D6_Patterns.HomeTowards(enemy,0.83) or nil
                    if D6_Patterns.AimVolley(npc,enemy,1+(i%2),spec.kind,spec.speed,spec.damage,spec.art,side*spec.spread,steered) then
                        npc:EmitSound(spec.sound, 74, 100+i*3)
                    end
                end)
            end
        end
    end
end)

print("[D6] d6_ai.lua OK")
