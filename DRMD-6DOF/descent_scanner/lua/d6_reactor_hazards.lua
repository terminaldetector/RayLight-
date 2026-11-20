D6_ReactorHazards = {}
local H = D6_ReactorHazards
local channel = "D6_ReactorHazard"
local survey, breach, egress = 1, 2, 3
local fan, ring, beam = 1, 2, 3
if CLIENT then
    local signals = {}
    local line = Material("sprites/laserbeam")
    local glow = Material("sprites/light_glow02_add")
    local cold = Color(106, 213, 255)
    local hot = Color(255, 121, 67)
    local ignition = Color(255, 229, 191)
    net.Receive(channel, function()
        local id = net.ReadUInt(16)
        local kind = net.ReadUInt(2)
        if kind == 0 then
            signals[id] = nil
            return
        end

        local phase = net.ReadUInt(2)
        local live = net.ReadBool()
        local duration = net.ReadFloat()
        local radius = net.ReadUInt(6)
        local lanes = {}
        for i = 1, net.ReadUInt(5) do
            lanes[i] = {net.ReadVector(), net.ReadVector()}
        end

        signals[id] = {
            kind = kind,
            phase = phase,
            live = live,
            untilTime = CurTime() + duration,
            lanes = lanes,
            radius = radius
        }
    end)

    hook.Add("PostDrawTranslucentRenderables", "D6_ReactorHazardSigns", function(depth, sky)
        if depth or sky then return end
        local now = CurTime()
        for id, signal in pairs(signals) do
            local t = signal.untilTime - now
            if t <= 0 then
                signals[id] = nil
                continue
            end

            local ink = signal.phase == survey and cold or hot
            local pulse = .68 + .32 * math.sin(now * (t < .28 and 31 or 14))
            local width = signal.radius * 2
            for _, lane in ipairs(signal.lanes) do
                local a, b = lane[1], lane[2]
                render.SetMaterial(line)
                if signal.live then
                    render.DrawBeam(a, b, width, 0, 1, Color(ink.r, ink.g, ink.b, 150 + pulse * 55))
                    render.DrawBeam(a, b, math.max(2, width * .25), 0, 1, ignition)
                else
                    render.DrawBeam(a, b, width, 0, 1, Color(ink.r, ink.g, ink.b, (signal.kind == beam and 25 or 12) * pulse))
                    render.DrawBeam(a, b, signal.kind == beam and 3 or 1.6, 0, 1, Color(ink.r, ink.g, ink.b, 88 + pulse * 68))
                end

                render.SetMaterial(glow)
                local flash = signal.live and width * 2.3 or 7 + pulse * 6
                render.DrawSprite(b, flash, flash, Color(ink.r, ink.g, ink.b, 160 * pulse))
                if signal.kind == beam then render.DrawSprite(a, flash, flash, ink) end
            end
        end
    end)
    return
end

util.AddNetworkString(channel)
local nextId = 0
local segments = {
    [survey] = {fan, beam, fan},
    [breach] = {ring, beam, ring},
    [egress] = {beam}
}

local rest = {
    [survey] = 3.6,
    [breach] = 3.15,
    [egress] = 4.5
}

local tau = math.pi * 2
local function pilot(state, ply)
    return IsValid(ply) and ply:Alive() and ply.D6On and (not state.rogue or ply == state.owner) and (not state.eligible or state.eligible(ply))
end

local function targetNear(state, position, range)
    if state.rogue then
        local ply = state.owner
        if pilot(state, ply) and ply:WorldSpaceCenter():DistToSqr(position) < range ^ 2 then return ply end
        return
    end

    local chosen, best = nil, range ^ 2
    for _, ply in ipairs(player.GetAll()) do
        if not pilot(state, ply) then continue end
        local dist = ply:WorldSpaceCenter():DistToSqr(position)
        if dist < best then chosen, best = ply, dist end
    end
    return chosen
end

local function send(record, attack, kind, live, duration)
    net.Start(channel)
    net.WriteUInt(attack.id, 16)
    net.WriteUInt(kind, 2)
    if kind ~= 0 then
        net.WriteUInt(record.phase, 2)
        net.WriteBool(live)
        net.WriteFloat(duration)
        net.WriteUInt(attack.radius, 6)
        net.WriteUInt(#attack.lanes, 5)
        for _, lane in ipairs(attack.lanes) do
            net.WriteVector(lane[1])
            net.WriteVector(lane[2])
        end
    end

    net.Broadcast()
end

function H.Reset(state)
    local record = state.hazards
    if not record then return end
    if record.pending then send(record, record.pending, 0) end
    for shot in pairs(record.shots) do
        if IsValid(shot) then shot:Remove() end
    end

    state.hazards = nil
end

local function random(record, max)
    record.rng = record.rng * 16807 % 2147483647
    return record.rng % max
end

local function obstruction(state, ent)
    return ent ~= state.core and not ent:IsPlayer() and not ent:IsNPC() and not ent.D6_IsProjectile
end

local function clip(state, a, b, radius)
    local extents = Vector(radius, radius, radius)
    local tr = util.TraceHull({
        start = a,
        endpos = b,
        mins = -extents,
        maxs = extents,
        mask = MASK_SHOT,
        filter = function(ent) return obstruction(state, ent) end
    })

    if tr.StartSolid or tr.HitPos:DistToSqr(a) < 36 ^ 2 then return end
    return {a, tr.HitPos}
end

-- Two spaced emitters leave the middle lane open. A bank never lengthens after its warning.
local function banks(state, record)
    local lanes = {}
    local escape = record.phase == egress
    for i = 0, escape and 1 or 2 do
        local number = (record.offset + record.cycle + i) % (escape and 2 or 3) + 1
        local name = (escape and "d6_reactor_hazard_escape_" or "d6_reactor_hazard_") .. number
        local mark = ents.FindByName(name)[1]
        if not IsValid(mark) or not targetNear(state, mark:GetPos(), escape and 800 or 1200) then continue end
        local origin, angle = mark:GetPos(), mark:GetAngles()
        local forward = angle:Forward()
        local axis = number % 2 == 0 and angle:Right() or angle:Up()
        local radius = escape and 13 or 19
        for _, offset in ipairs(escape and {0} or {-42, 42}) do
            local start = origin + axis * offset
            local lane = clip(state, start, start + forward * 1390, radius)
            if lane then lanes[#lanes + 1] = lane end
        end

        if #lanes > 0 then
            return {
                kind = beam,
                lanes = lanes,
                radius = radius,
                windup = escape and .9 or 1.14,
                origin = origin,
                damage = escape and 21 or record.phase == breach and 30 or 24,
                hit = {}
            }
        end
    end
end

local function port(core, target)
    local pos, angles = core:GetPos(), core:GetAngles()
    local point = WorldToLocal(target, angle_zero, pos, angles)
    local planar = math.sqrt(point.x ^ 2 + point.y ^ 2)
    local a = math.floor(math.atan2(point.y, point.x) / (math.pi * .5)) * math.pi * .5 + math.pi * .25
    local axial = math.abs(point.z) > planar * 1.22
    local radius = axial and 104 or 143
    local height = axial and 125 or 12
    local pointLocal = Vector(math.cos(a) * radius, math.sin(a) * radius, point.z < 0 and -height or height)
    return LocalToWorld(pointLocal, angle_zero, pos, angles)
end

local function directions(kind, angles, gap, wave, spin)
    local forward, right, up = angles:Forward(), angles:Right(), angles:Up()
    local dirs = {}
    if kind == fan then
        for _, spread in ipairs({-.22, -.088, 0, .088, .22}) do
            dirs[#dirs + 1] = (forward + (right * .9 + up * spin * .34) * spread + up * (wave - 1) * .04):GetNormalized()
        end
    else
        for slot = 0, 11 do
            local t = (slot + .24 * (wave - 1) * spin) * tau / 12
            if (slot - gap) % 12 < 3 then continue end
            local spread = .29 + .075 * (wave - 1)
            dirs[#dirs + 1] = (forward + (right * math.cos(t) + up * math.sin(t)) * spread):GetNormalized()
        end
        if wave == 2 then dirs[#dirs + 1] = forward end
    end
    return dirs
end

local function barrage(state, record, kind, target)
    if not IsValid(state.core) or not IsValid(target) then return end
    local aim = target:WorldSpaceCenter()
    local origin = port(state.core, aim)
    local path = util.TraceLine({
        start = origin,
        endpos = aim,
        mask = MASK_SOLID_BRUSHONLY
    })

    if path.Hit or aim:DistToSqr(origin) < 100 ^ 2 then return end
    local angles = (aim - origin):Angle()
    local gap, spin = random(record, 12), record.cycle % 2 == 0 and 1 or -1
    local lanes, shots = {}, {}
    for wave = 1, kind == ring and 3 or 2 do
        shots[wave] = directions(kind, angles, gap, wave, spin)
    end

    local preview = table.Copy(shots[1])
    if kind == ring then preview[#preview + 1] = angles:Forward() end
    for _, dir in ipairs(preview) do
        local lane = clip(state, origin, origin + dir * 235, 2)
        if lane then lanes[#lanes + 1] = lane end
    end

    if #lanes == 0 then return end
    return {
        kind = kind,
        lanes = lanes,
        origin = origin,
        radius = 5,
        windup = kind == ring and 1.05 or .77,
        shots = shots,
        damage = kind == ring and 17 or 14,
        wave = 1,
        beat = kind == ring and .25 or .19
    }
end

local function fireShots(state, record, attack)
    local hot = attack.kind == ring
    local ink = hot and Color(255, 122, 75) or Color(83, 204, 249)
    local core = state.core
    if not IsValid(core) then return end
    for _, dir in ipairs(attack.shots[attack.wave]) do
        local shot = D6_Wep.FireProjectile({
            owner = core,
            pos = attack.origin,
            dir = dir,
            speed = hot and (750 + attack.wave * 57) or 1050,
            swept = true,
            inherit = 0,
            art = hot and "shot_arcpulse" or "shot_energy",
            dmgClass = "energy",
            physRadius = hot and 6 or 4,
            artScale = hot and 1.4 or 1.14,
            color = ink,
            projectileTint = true,
            life = 3.2,
            trails = {
                {
                    col = ink,
                    sw = hot and 13 or 8,
                    ew = 1,
                    life = hot and .19 or .14
                }
            },
            onHit = function(projectile, victim)
                if not IsValid(core) or state.hazards ~= record or not IsValid(victim) or not victim:IsPlayer() then return end
                if pilot(state, victim) then
                    D6_Wep.DirectDamage(core, projectile, victim, attack.damage, DMG_ENERGYBEAM, dir * 950)
                end
            end
        })

        if IsValid(shot) then
            record.shots[shot] = true
            shot:CallOnRemove("D6_HazardShot", function(ent) record.shots[ent] = nil end)
        end
    end

    sound.Play(hot and "ambient/energy/zap9.wav" or "ambient/energy/zap5.wav", attack.origin, 78, hot and 84 or 111, .82)
end

local function damageLane(state, attack)
    for _, ply in ipairs(player.GetAll()) do
        if attack.hit[ply] or not pilot(state, ply) then continue end
        local center = ply:WorldSpaceCenter()
        for _, lane in ipairs(attack.lanes) do
            local distance, point = util.DistanceToLine(lane[1], lane[2], center)
            if distance > attack.radius + 12 then continue end
            local trace = util.TraceLine({
                start = lane[1],
                endpos = point,
                mask = MASK_SHOT,
                filter = function(ent) return obstruction(state, ent) end
            })

            if trace.Hit and trace.HitPos:DistToSqr(point) > 3 ^ 2 then continue end
            local cover = util.TraceLine({
                start = point,
                endpos = center,
                mask = MASK_SOLID_BRUSHONLY
            })

            if cover.Hit then continue end
            attack.hit[ply] = true
            D6_Wep.DirectDamage(state.core, state.core, ply, attack.damage, DMG_ENERGYBEAM)
            break
        end
    end
end

local function update(state, record, attack, now)
    if now < attack.at then return end
    if attack.kind == beam then
        if not attack.untilTime then
            local lanes = {}
            for _, lane in ipairs(attack.lanes) do
                local clipped = clip(state, lane[1], lane[2], attack.radius)
                if clipped then lanes[#lanes + 1] = clipped end
            end

            attack.lanes = lanes
            attack.untilTime = now + .48
            record.fired = record.fired + 1
            send(record, attack, beam, true, .48)
            sound.Play("ambient/energy/weld2.wav", attack.origin, 84, 88, .9)
        end

        if now < attack.untilTime then
            damageLane(state, attack)
            return
        end
    else
        fireShots(state, record, attack)
        record.fired = record.fired + 1
        attack.wave = attack.wave + 1
        attack.at = now + attack.beat
        if attack.shots[attack.wave] then return end
    end

    record.pending = nil
    record.nextAt = now + rest[record.phase]
end

function H.Tick(state, now)
    local phase = state.phase
    if not segments[phase] or not IsValid(state.core) then
        H.Reset(state)
        return
    end

    local record = state.hazards
    if not record or record.phase ~= phase then
        H.Reset(state)
        local seed = math.floor(tonumber(state.seed) or 104729)
        record = {
            phase = phase,
            cycle = 0,
            warnings = 0,
            fired = 0,
            shots = {},
            nextAt = now + (phase == egress and 2.3 or 1.8),
            rng = (seed + phase * 773) % 2147483646 + 1
        }

        record.offset = state.rogue and random(record, 3) or 0
        state.hazards = record
    end

    if record.pending then
        update(state, record, record.pending, now)
        return
    end

    if now < record.nextAt then return end
    local pattern = segments[phase]
    local kind = pattern[(record.cycle + record.offset) % #pattern + 1]
    local target = targetNear(state, state.origin or state.core:GetPos(), 1900)
    local attack = kind == beam and banks(state, record)
    if not attack and phase ~= egress then attack = barrage(state, record, phase == breach and ring or fan, target) or banks(state, record) end
    if not attack then
        record.nextAt = now + .65
        return
    end

    nextId = nextId % 65535 + 1
    attack.id, attack.at = nextId, now + attack.windup
    record.cycle, record.warnings = record.cycle + 1, record.warnings + 1
    record.pending, record.lastAttack = attack, attack.kind
    send(record, attack, attack.kind, false, attack.windup)
    sound.Play("ambient/energy/zap2.wav", attack.origin, 73, phase == survey and 113 or 78, .8)
end
