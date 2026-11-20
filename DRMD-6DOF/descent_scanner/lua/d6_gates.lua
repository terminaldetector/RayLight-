D6_Gates = {width = 48, height = 58, lifetime = 75, cost = 18}
local G = D6_Gates
local pi = math.pi

function G.Intersection(from, to, origin, angles, clearance, padding)
    local normal = angles:Forward()
    local a = (from - origin):Dot(normal) - clearance
    local b = (to - origin):Dot(normal) - clearance
    if a <= 0 or b > 0 then return end
    local fraction = a / (a - b)
    local hit = LerpVector(fraction, from, to) - origin
    local u = hit:Dot(angles:Right())
    local v = hit:Dot(angles:Up())
    if (u / (G.width - padding))^2 + (v / (G.height - padding))^2 > 1 then return end
    return fraction, u, v
end

function G.Rotate(direction, entry, exit)
    return exit:Forward() * -direction:Dot(entry:Forward())
        + exit:Right() * -direction:Dot(entry:Right())
        + exit:Up() * direction:Dot(entry:Up())
end

if CLIENT then return end
util.AddNetworkString("D6_GateView")

local pairsByOwner = {}
local function removePair(ply)
    local gates = pairsByOwner[ply]
    if not gates then return end
    for _, gate in pairs(gates) do
        if IsValid(gate) then gate:Remove() end
    end
    pairsByOwner[ply] = nil
end
hook.Add("PlayerDeath", "D6_RemoveGates", removePair)
hook.Add("PlayerDisconnected", "D6_RemoveGates", removePair)
cvars.AddChangeCallback("d6_profile", function()
    if D6_Session.IsArena() then return end
    for _, ply in ipairs(player.GetAll()) do removePair(ply) end
end, "D6_GateProfile")

function G.FindSurface(ply)
    local origin = ply:GetShootPos()
    local direction = D6_Wep.ShootAng(ply):Forward()
    local trace = util.TraceLine({start = origin, endpos = origin + direction * 2600, filter = ply, mask = MASK_SOLID})
    if not trace.HitWorld or trace.HitSky then return end
    local normal = trace.HitNormal
    local angles = normal:Angle()
    for i = 0, 11 do
        local phi = i*pi/6
        local rim = trace.HitPos + angles:Right() * (math.cos(phi)*G.width)
            + angles:Up() * (math.sin(phi)*G.height)
        local sample = util.TraceLine({
            start = rim + normal*5, endpos = rim - normal*5, mask = MASK_SOLID_BRUSHONLY,
        })
        if not sample.HitWorld or sample.HitSky or sample.StartSolid or sample.HitNormal:Dot(normal) < 0.97 then return end
    end
    return trace.HitPos + normal*1.4, angles
end

function G.Place(ply, wep, index)
    local pos, ang = G.FindSurface(ply)
    if not pos then return false end

    local gates = pairsByOwner[ply] or {}
    local other = gates[3 - index]
    if IsValid(other) and other:GetPos():DistToSqr(pos) < (G.width * 2)^2 then return false end

    local gate = ents.Create("d6_phase_gate")
    if not IsValid(gate) then return false end
    if not D6_Energy.TryConsume(ply, "weapons", G.cost) then gate:Remove(); return false end

    if IsValid(gates[index]) then gates[index]:Remove() end
    gate:SetPos(pos)
    gate:SetAngles(ang)
    gate:SetPolarity(index)
    gate:SetEndsAt(CurTime() + G.lifetime)
    gate:Spawn()
    gate:SetOwner(ply)
    wep:SetNWEntity("D6_PhaseGate" .. index, gate)
    gates[index] = gate
    pairsByOwner[ply] = gates
    if IsValid(other) then
        gate:SetLinkedGate(other)
        other:SetLinkedGate(gate)
    end

    D6_Wep.MarkShot(wep, D6_Wep.Muzzle(ply, {fwd = 24, rgt = 0, up = -4}, wep:GetClass()), 0.45)
    gate:EmitSound("ambient/energy/zap1.wav", 68, index == 1 and 104 or 88)
    return true
end

local function findCrossing(from, to, hull, padding, maxFraction)
    local entry, exit, foundU, foundV
    for _, gates in pairs(pairsByOwner) do
        if IsValid(gates[1]) and IsValid(gates[2]) then
            for i = 1, 2 do
                local gate = gates[i]
                local normal = gate:GetForward()
                local clearance = math.abs(normal.x)*hull.x + math.abs(normal.y)*hull.y + math.abs(normal.z)*hull.z + 3
                local fraction, u, v = G.Intersection(from, to, gate:GetPos(), gate:GetAngles(), clearance, padding)
                if fraction and fraction < maxFraction then
                    entry, exit, foundU, foundV, maxFraction = gate, gates[3-i], u, v, fraction
                end
            end
        end
    end
    return entry, exit, foundU, foundV, maxFraction
end

local function exitPoint(exit, u, v, hull)
    local norm = exit:GetForward()
    local clearance = math.abs(norm.x)*hull.x + math.abs(norm.y)*hull.y + math.abs(norm.z)*hull.z + 7
    return exit:GetPos() + norm*clearance - exit:GetRight()*u + exit:GetUp()*v
end

function G.MovePlayer(ply, move, cmd, dt)
    if not next(pairsByOwner) or CurTime() < (ply.D6_GateReady or 0) then return false end
    local mins, maxs = ply:GetHull()
    local centerOffset = (mins + maxs)*0.5
    local hull = (maxs - mins)*0.5
    local from = move:GetOrigin() + centerOffset
    local entry, exit, u, v, fraction = findCrossing(from, from + ply.D6Vel*dt, hull, 17, 1)
    if not entry then return false end

    local reach = util.TraceHull({start = from - centerOffset, endpos = from + ply.D6Vel*(dt*fraction) - centerOffset,
        mins = mins, maxs = maxs, filter = ply, mask = MASK_PLAYERSOLID})
    if reach.Hit then return false end

    local dest = exitPoint(exit, u, v, hull) - centerOffset
    local blocked = util.TraceHull({start = dest, endpos = dest, mins = mins, maxs = maxs,
        filter = ply, mask = MASK_PLAYERSOLID})
    if blocked.Hit or not util.IsInWorld(dest) then return false end

    local old, new = entry:GetAngles(), exit:GetAngles()
    local view = cmd:GetViewAngles()
    local angle = G.Rotate(view:Forward(), old, new):AngleEx(G.Rotate(view:Up(), old, new))
    D6_Mobility.Release(ply)
    ply.D6Vel = G.Rotate(ply.D6Vel, old, new)
    ply.D6ThrustCur = Vector()
    if ply.D6DashOn and ply.D6DashDir then ply.D6DashDir = G.Rotate(ply.D6DashDir, old, new) end
    ply.D6AngSynced = angle
    ply.D6_GateReady = CurTime() + 0.35
    move:SetOrigin(dest)
    cmd:SetViewAngles(angle)
    ply:SetEyeAngles(angle)
    ply:SetAngles(angle)
    net.Start("D6_GateView")
    net.WriteAngle(angle)
    net.Send(ply)
    D6_Wep.MotionFX(from, dest + centerOffset, 2)
    exit:EmitSound("ambient/energy/weld2.wav", 65, 107)
    return true
end

function G.MoveShot(ent, from, to, radius, velocity, maxFraction)
    if not next(pairsByOwner) or CurTime() < (ent.D6_GateReady or 0) then return end
    local hull = Vector(radius, radius, radius)
    local entry, exit, u, v = findCrossing(from, to, hull, radius, maxFraction)
    if not entry then return end
    local dest = exitPoint(exit, u, v, hull)
    local blocked = util.TraceHull({start = dest, endpos = dest, mins = -hull, maxs = hull,
        filter = ent, mask = MASK_SHOT})
    if blocked.Hit or not util.IsInWorld(dest) then return end
    ent.D6_GateReady = CurTime() + 0.2
    return dest, G.Rotate(velocity, entry:GetAngles(), exit:GetAngles())
end
