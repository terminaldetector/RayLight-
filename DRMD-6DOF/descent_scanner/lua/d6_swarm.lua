if not SERVER then return end
D6_Swarm = {}
local S = D6_Swarm
local members = {}
local priority = {gravity = 6, support = 4, screen = 3, rear = 2, flank = 1}
local range = 1450
local limit = 8

local function alive(ent)
    return IsValid(ent) and ent:Health() > 0
end

function S.Register(ent, art, target)
    members[ent] = {entity = ent, art = art, target = target}
end

function S.GetPlan(ent)
    local member = members[ent]
    return member and member.plan
end

local function apply(member, plan)
    member.plan = plan
    local ent = member.entity
    ent:SetNW2Entity("D6_SwarmLeader", plan and plan.leader or NULL)
    ent:SetNW2Int("D6_SwarmSlot", plan and plan.slot or 0)
    ent:SetNW2String("D6_SwarmPhase", plan and plan.phase or "")
end

local function pickTarget(member, pilots)
    local origin = member.entity:GetPos()
    if alive(member.target) and member.target:GetNWBool("D6On")
        and origin:DistToSqr(member.target:WorldSpaceCenter()) < 2400^2 then return member.target end
    local nearest, distance = nil, 2050^2
    for _, pilot in ipairs(pilots) do
        local span = origin:DistToSqr(pilot:WorldSpaceCenter())
        if span < distance then nearest, distance = pilot, span end
    end
    return nearest
end

local function rank(member)
    local role = member.art.role
    if role == "gravity" and member.entity:GetNW2Int("D6_GravityLoad", 0) > 0 then return 10 end
    return priority[role]
end

local function greater(a, b)
    local ra, rb = rank(a), rank(b)
    if ra == rb then return a.entity:EntIndex() < b.entity:EntIndex() end
    return ra > rb
end

local function place(group, member, now)
    local origin = member.entity:GetPos()
    local knobs = member.entity.D6_Swarm
    local reach = istable(knobs) and math.Clamp(tonumber(knobs.radius) or range, 160, range) or range
    local closest, best = nil, reach^2
    for _, squad in ipairs(group) do
        if #squad.members == limit or squad.target ~= member.targetChosen or squad.faction ~= member.art.faction then continue end
        local root = squad.members[1].entity
        local span = origin:DistToSqr(root:GetPos())
        if span < best then
            local sight = util.TraceLine({start = origin, endpos = root:GetPos(), mask = MASK_SOLID_BRUSHONLY})
            if not sight.Hit then closest, best = squad, span end
        end
    end
    if not closest then
        closest = {members = {}, target = member.targetChosen, faction = member.art.faction}
        group[#group + 1] = closest
    end
    closest.members[#closest.members + 1] = member
end

local function goalFor(role, seat, center, axis, escort)
    local side = seat % 2 == 0 and -1 or 1
    local tier = math.floor((seat - 1)/2)
    local vertical = ({76,-83,132,-118})[tier%4+1]
    local rear = role == "rear" and 235 or (role == "support" and 142 or 0)
    local wing = (role == "flank" and 205 or 116) + tier*21
    local forward = rear > 0 and -rear or (escort and 78 or 28)
    return center + axis:Forward()*forward + axis:Right()*(side*wing) + axis:Up()*vertical
end

local function formation(group, now)
    local first = group.members[1]
    local leader = first.entity
    local target = group.target
    local gravity = first.art.role == "gravity"
    local escort = gravity and leader:GetNW2Int("D6_GravityLoad", 0) > 0
    local anchor = leader:WorldSpaceCenter()
    local toTarget = IsValid(target) and (target:WorldSpaceCenter() - anchor) or leader:GetForward()*600
    local axis = toTarget:Angle()
    local distance = toTarget:Length()
    local retreat = IsValid(target) and distance < (escort and 300 or 225)
    local center = anchor
    if not gravity and IsValid(target) then
        local stride = math.Clamp(distance - 460, -170, 230)
        center = anchor + axis:Forward()*stride
    end
    local tight = util.TraceHull({start = anchor, endpos = anchor + axis:Forward()*140,
        mins = Vector(-19,-19,-18), maxs = Vector(19,19,18), mask = MASK_SOLID_BRUSHONLY}).Hit
    local phase = retreat and "disengage" or (escort and "escort" or (not IsValid(target) and "patrol"
        or (distance > 700 and "approach" or "attack")))
    local count = #group.members
    local shooters = 0
    for _, member in ipairs(group.members) do
        if member.art.role ~= "gravity" and member.art.role ~= "support" then shooters = shooters + 1 end
    end
    local nextGun = 0
    for i, member in ipairs(group.members) do
        local role = member.art.role
        local point = i == 1 and center or goalFor(role, i - 1, center, axis, escort)
        if tight and i > 1 then point = anchor - axis:Forward()*(i-1)*66 + axis:Up()*(i%2==0 and 22 or -22) end
        local gun = role ~= "gravity" and role ~= "support"
        if gun then nextGun = nextGun + 1 end
        local squadChanged = member.plan and member.plan.leader ~= leader
        apply(member, {leader = leader, target = target, goal = point, phase = phase, slot = i,
            regroup = squadChanged and now+0.4 or (member.plan and member.plan.regroup),
            members = group.members, count = count, shooters = shooters, gun = gun and nextGun or 0})
    end
end

local function update()
    if not D6_Session.IsArena() then return end
    local pilots, available, groups = {}, {}, {}
    for _, ply in ipairs(player.GetAll()) do
        if alive(ply) and ply:GetNWBool("D6On") then pilots[#pilots + 1] = ply end
    end
    for ent, member in pairs(members) do
        if not alive(ent) then members[ent] = nil; continue end
        if ent.D6_SwarmExclude then apply(member); continue end
        member.targetChosen = pickTarget(member, pilots)
        available[#available + 1] = member
    end
    table.sort(available, greater)
    local now = CurTime()
    for _, member in ipairs(available) do place(groups, member, now) end
    for _, group in ipairs(groups) do formation(group, now) end
end

timer.Create("D6_SwarmDirector", 0.16, 0, update)

function S.AllowsFire(ent, now)
    local plan = S.GetPlan(ent)
    if not plan or plan.gun == 0 then return true end
    if plan.regroup and now < plan.regroup then return false end
    if plan.shooters < 2 then return true end
    local turn = (math.floor(now/0.23) + plan.leader:EntIndex()) % plan.shooters + 1
    return turn == plan.gun
end

function S.Avoid(ent, wanted, size)
    local speed = wanted:Length()
    if speed <= 1 then return wanted end
    local aim = wanted/speed
    local radius = math.Clamp(size or 15, 9, 95)
    local extents = Vector(radius,radius,radius)
    local look = math.Clamp(speed*0.42, 82, 330)
    local origin = ent:WorldSpaceCenter()
    local trace = {start = origin, mins = -extents, maxs = extents, filter = ent, mask = MASK_NPCSOLID_BRUSHONLY}
    local function probe(dir)
        trace.endpos = origin + dir*look
        return util.TraceHull(trace)
    end
    local hit = probe(aim)
    if not hit.Hit then return wanted end
    local tangent = aim - hit.HitNormal*math.min(0, aim:Dot(hit.HitNormal))
    local axes = aim:Angle()
    local best, clear = hit.HitNormal, hit.Fraction
    for _, candidate in ipairs({tangent, axes:Right()*0.9+aim*0.43, -axes:Right()*0.9+aim*0.43,
        axes:Up()*0.9+aim*0.43, -axes:Up()*0.9+aim*0.43}) do
        if candidate:LengthSqr() < 0.02 then continue end
        local dir = candidate:GetNormalized()
        local test = probe(dir)
        if test.Fraction > clear + 0.02 then best, clear = dir, test.Fraction end
    end
    return best*speed*math.Clamp(0.25 + clear*0.68, 0.28, 0.88)
end

function S.Steering(ent, fallback, maxSpeed)
    local plan = S.GetPlan(ent)
    if not plan or (plan.count < 2 and not IsValid(plan.target)) then return fallback end
    local config = istable(ent.D6_Swarm) and ent.D6_Swarm or {}
    local cap = math.Clamp(tonumber(config.maxSpeed) or maxSpeed, 100, 1350)
    local separationRange = math.Clamp(tonumber(config.sepDist) or 144, 48, 280)
    local separation = Vector()
    local origin = ent:GetPos()
    local weight = math.Clamp(tonumber(config.separation) or 2.8, 0, 10)
    local cohesion = math.Clamp(tonumber(config.cohesion) or 0.8, 0, 4)
    local alignment = math.Clamp(tonumber(config.alignment) or 1, 0, 4)
    local pursuit = math.Clamp(tonumber(config.target) or 2.2, 0, 7)
    for _, neighbor in ipairs(plan.members) do
        local other = neighbor.entity
        if other == ent or not alive(other) then continue end
        local away = origin - other:GetPos()
        local distance = away:Length()
        if distance < separationRange and distance > 0.01 then
            separation = separation + away/distance*((separationRange-distance)*weight)
        end
    end
    local own = fallback or vector_origin
    local escort = plan.phase == "escort" and ent ~= plan.leader
    local planVel = (plan.goal-origin)*(escort and 3.35 or 2.15)*(cohesion/0.8)
    local leaderVel = ent ~= plan.leader and IsValid(plan.leader) and plan.leader:GetVelocity() or vector_origin
    local keepOwn = escort and 0.16 or (plan.count < 2 and 0.78 or 0.46)
    local blend = planVel + leaderVel * alignment*0.27 + own*(keepOwn*pursuit/2.2) + separation
    if blend:LengthSqr() > cap*cap then blend = blend:GetNormalized()*cap end
    return S.Avoid(ent, blend)
end

cvars.AddChangeCallback("d6_profile", function()
    if D6_Session.IsArena() then return end
    for ent, member in pairs(members) do if IsValid(ent) then apply(member) end end
end, "D6_SwarmProfile")
