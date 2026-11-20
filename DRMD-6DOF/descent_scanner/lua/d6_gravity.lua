if not SERVER then return end
D6_Gravity = {}
local G = D6_Gravity
local carriers, caught, launched = {}, {}, {}
local radius, capacity, period = 700, 8, 0.05
local spin = math.pi*(3-math.sqrt(5))
local bounce = CreateConVar("d6_grav_bounce_enabled", "1", FCVAR_ARCHIVE, "Enable gravity drone throws and cargo handoffs")

function G.OrbitOffset(slot, count, time, distance)
    local z = (1 - 2*(slot - 0.5)/count)
    local ring = math.sqrt(math.max(0,1-z*z))
    local angle = (slot-1)*spin + time*2.04
    local x, y = math.cos(angle)*ring, math.sin(angle)*ring
    local tilt = 0.57 + math.sin(time*0.84)*0.36
    return Vector(x, y*math.cos(tilt)-z*math.sin(tilt), y*math.sin(tilt)+z*math.cos(tilt))*distance
end

local function physics(ent)
    if not IsValid(ent) then return end
    local body = ent:GetPhysicsObject()
    if IsValid(body) then return body end
end

local function sight(from, to, a, b)
    return not util.TraceLine({start = from, endpos = to, filter = {a,b}, mask = MASK_SOLID_BRUSHONLY}).Hit
end

local function available(ent)
    if not IsValid(ent) or ent.D6_BeingHeld or ent.D6_IsProjectile or ent.IsAirMine or ent.D6_RailNoBoom
        or ent.D6_MechCarrier or ent:IsPlayerHolding() then return end
    local class = ent:GetClass()
    if class ~= "prop_physics" and class ~= "prop_physics_multiplayer" and not ent.D6_Collectible then return end
    local body = physics(ent)
    if not body or not body:IsMotionEnabled() or body:GetMass() > 115 or constraint.HasConstraints(ent) then return end
    return body
end

local function setCount(npc)
    if IsValid(npc) then npc:SetNW2Int("D6_GravityLoad", #npc.D6_HeldProps) end
end

local function capture(npc, ent, body)
    local props = npc.D6_HeldProps
    if #props >= capacity then return end
    launched[ent] = nil
    caught[ent] = {carrier = npc, list = props, collision = ent:GetCollisionGroup(), gravity = body:IsGravityEnabled()}
    ent.D6_BeingHeld, ent.D6_MasterOwner = true, npc
    ent:SetNWEntity("D6_GravityCarrier", npc)
    ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    body:EnableGravity(false)
    body:Wake()
    props[#props + 1] = ent
    npc:SetNW2Float("D6_GravityCapturedAt", CurTime())
    setCount(npc)
    npc:EmitSound("weapons/physcannon/physcannon_pickup.wav", 66, 128)
end

local function release(ent)
    local data = caught[ent]
    if not data then return end
    caught[ent] = nil
    if IsValid(ent) then
        ent.D6_BeingHeld, ent.D6_MasterOwner = nil, nil
        ent:SetCollisionGroup(data.collision)
        ent:SetNWEntity("D6_GravityCarrier", NULL)
        local body = physics(ent)
        if body then body:EnableGravity(data.gravity); body:Wake() end
    end
    table.RemoveByValue(data.list, ent)
    setCount(data.carrier)
end

local function dropAll(npc)
    local state = carriers[npc]
    if not state then return end
    for i = #state.props, 1, -1 do release(state.props[i]) end
end

function G.Register(npc, target)
    if not IsValid(npc) then return end
    if carriers[npc] then return end
    local props = {}
    carriers[npc] = {props = props, target = target, home = npc:GetPos(), phase = (npc:EntIndex()%13)*0.49}
    npc.D6_HeldProps = props
    setCount(npc)
end

local function scan(npc, state, now)
    if #state.props >= capacity or now < (state.scanAt or 0) then return end
    state.scanAt = now+0.23
    local origin = npc:WorldSpaceCenter()
    local nearest, nearestBody, distance = nil, nil, radius^2
    for _, ent in ipairs(ents.FindInSphere(origin, radius)) do
        local flight = launched[ent]
        local body = (not flight or flight.to == npc) and available(ent)
        if not body then continue end
        local point = ent:WorldSpaceCenter()
        local sq = point:DistToSqr(origin)
        if flight and (flight.to ~= npc or sq > 136^2) then continue end
        if sq <= distance and sight(origin, point, npc, ent) then
            nearest, nearestBody, distance = ent, body, sq
        end
    end
    if nearest then capture(npc, nearest, nearestBody) end
end

local function carry(npc, state, now)
    local center = npc:WorldSpaceCenter()
    local charge = now < npc:GetNWFloat("D6_ThreatAt", 0)
    for i = #state.props, 1, -1 do
        local ent = state.props[i]
        local body = physics(ent)
        if not body or not body:IsMotionEnabled() or ent:IsPlayerHolding()
            or center:DistToSqr(ent:WorldSpaceCenter()) > 780^2 then release(ent); continue end
        local current = ent:WorldSpaceCenter()
        local data = caught[ent]
        if not sight(center,current,npc,ent) then
            data.blocked = data.blocked or now
            if now-data.blocked > 0.40 then release(ent) end
            continue
        end
        data.blocked = nil
        local orbit = G.OrbitOffset(i, #state.props, now+state.phase, charge and 119 or 153)
        local edge = math.Clamp(ent:BoundingRadius()*0.55, 6, 29)
        local hull = Vector(edge,edge,edge)
        local corner = util.TraceHull({start = center, endpos = center + orbit,
            mins = -hull, maxs = hull, mask = MASK_SOLID_BRUSHONLY})
        local wanted = center + orbit*math.max(0, corner.Fraction-0.04)
        local targetVel = (wanted-current)*4.4 + npc:GetVelocity()
        if targetVel:LengthSqr() > 970^2 then targetVel = targetVel:GetNormalized()*970 end
        local change = (targetVel-body:GetVelocity())*0.35
        if change:LengthSqr() > 163^2 then change = change:GetNormalized()*163 end
        body:ApplyForceCenter(change*body:GetMass())
        body:Wake()
    end
end

local function aimAt(npc, state, goal)
    local origin = npc:WorldSpaceCenter()
    local plan = D6_Swarm.GetPlan(npc)
    local target = plan and plan.target or state.target
    if not IsValid(target) or not target:Alive() or not target:GetNWBool("D6On") then target = nil end
    local dest = IsValid(target) and target:WorldSpaceCenter() or state.home
    local vec = dest-origin
    local span = vec:Length()
    local aim = vec:Angle()
    local side = npc:EntIndex()%2 == 0 and 1 or -1
    if IsValid(target) and #state.props > 0 then
        local radial = math.Clamp((span-465)*2.1, -420, 435)
        goal = aim:Forward()*radial + aim:Right()*side*120 + aim:Up()*58
    else
        local drift = G.OrbitOffset(npc:EntIndex()%6+1, 6, CurTime()*0.3+state.phase, 310)
        goal = (state.home + drift-origin)*1.55
        if goal:LengthSqr() > 245^2 then goal = goal:GetNormalized()*245 end
    end
    return target, D6_Swarm.Avoid(npc, goal, 23), aim
end

local function throw(npc, item, target, pass)
    local body = physics(item)
    if not body then release(item); return end
    local from = item:WorldSpaceCenter()
    local where = target:WorldSpaceCenter()
    if not sight(from, where, npc, target) then return end
    local speed = pass and 1040 or 1460
    local flight = math.Clamp(from:Distance(where)/speed, 0.08, 0.65)
    where = where + target:GetVelocity()*flight - physenv.GetGravity()*(flight*flight*0.5)
    release(item)
    launched[item] = {from = npc, to = pass and target or nil, expires = CurTime()+2.8}
    local dir = (where-from):GetNormalized()
    body:SetVelocity(dir*speed)
    D6_Wep.MotionFX(from, from+dir*96, 3)
    npc:EmitSound("ambient/energy/zap5.wav", 79, pass and 129 or 107)
end

local function attacks(npc, state, target, now)
    if not bounce:GetBool() or now < (npc.D6_NextThrow or 0) or #state.props == 0 then return end
    local item = state.props[1]
    local pass = false
    local origin = npc:WorldSpaceCenter()
    if not IsValid(target) or origin:DistToSqr(target:WorldSpaceCenter()) > 560^2
        or not sight(origin, target:WorldSpaceCenter(), npc, target) then
        target = nil
        local best = 770^2
        for ally, other in pairs(carriers) do
            if ally == npc or not IsValid(ally) or ally:Health() <= 0 or #other.props >= capacity then continue end
            if IsValid(state.target) and IsValid(other.target) and state.target ~= other.target then continue end
            local d = origin:DistToSqr(ally:WorldSpaceCenter())
            if d > 355^2 and d < best and sight(origin, ally:WorldSpaceCenter(), npc, ally) then target, best = ally, d end
        end
        pass = IsValid(target)
    end
    if not IsValid(target) then return end
    local delay = pass and 0.3 or 0.56
    if not pass then D6_Patterns.Warn(npc, target:WorldSpaceCenter() + target:GetVelocity()*0.13, delay) end
    npc.D6_NextThrow = now+delay+2.55
    timer.Simple(delay, function()
        if IsValid(npc) and IsValid(item) and item.D6_MasterOwner == npc and IsValid(target)
            and target:Health() > 0 and D6_Session.IsArena() then throw(npc, item, target, pass) end
    end)
end

timer.Create("D6_GravityField", period, 0, function()
    if not D6_Session.IsArena() then return end
    local now = CurTime()
    for ent, flight in pairs(launched) do if not IsValid(ent) or flight.expires < now then launched[ent] = nil end end
    for npc, state in pairs(carriers) do
        if not IsValid(npc) or npc:Health() <= 0 then dropAll(npc); carriers[npc] = nil; continue end
        local body = physics(npc)
        if not body then continue end
        scan(npc,state,now)
        local target, desired, aim = aimAt(npc,state)
        body:EnableGravity(false)
        body:SetVelocity(LerpVector(0.18,body:GetVelocity(),desired))
        if IsValid(target) then npc:SetAngles(LerpAngle(0.23,npc:GetAngles(),aim)) end
        carry(npc,state,now)
        attacks(npc,state,target,now)
    end
end)

hook.Add("EntityTakeDamage", "D6_GravityCargoDamage", function(ent, info)
    local record = caught[ent]
    local inflictor = info:GetInflictor()
    local flight = launched[inflictor]
    if ent:IsPlayer() and flight and not flight.to then
        launched[inflictor] = nil
        if not IsValid(flight.from) then return end
        D6_Wep.SplashDamage(flight.from, inflictor, inflictor:GetPos(), 0, 43, 135, DMG_SHOCK, 3900)
        local effect = EffectData(); effect:SetOrigin(inflictor:GetPos()); effect:SetScale(1)
        util.Effect("cball_explode", effect)
        return
    end
    if not record or not info:IsDamageType(DMG_BLAST) then return end
    local model = ent:GetModel() or ""
    if not (model:find("explosive", 1, true) or model:find("gascan", 1, true) or model:find("canister", 1, true)) then return end
    local carrier = record.carrier
    release(ent)
    if IsValid(carrier) then
        dropAll(carrier)
        D6_Wep.DirectDamage(info:GetAttacker(),ent,carrier,90,DMG_BLAST)
    end
end)

hook.Add("EntityRemoved", "D6_GravityDropCargo", function(ent)
    if carriers[ent] then dropAll(ent); carriers[ent] = nil end
    if caught[ent] then release(ent) end
    launched[ent] = nil
end)

cvars.AddChangeCallback("d6_profile", function()
    if D6_Session.IsArena() then return end
    for npc in pairs(carriers) do dropAll(npc) end
    table.Empty(launched)
end, "D6_GravityProfile")
