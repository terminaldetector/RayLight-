-- The flight integrator calls this module once per movement tick.
if SERVER then AddCSLuaFile() end

D6_Mobility = {DashCooldown = 1.20, DashDuration = 0.16, BurstSpeed = 3450}
local M = D6_Mobility
local RANGE = 2400
local SHIP_MASS = 110

function M.Steering(command)
    return Vector(
        (command:KeyDown(IN_FORWARD) and 1 or 0) - (command:KeyDown(IN_BACK) and 1 or 0),
        (command:KeyDown(IN_MOVERIGHT) and 1 or 0) - (command:KeyDown(IN_MOVELEFT) and 1 or 0),
        (command:KeyDown(IN_JUMP) and 1 or 0) - (command:KeyDown(IN_DUCK) and 1 or 0))
end

if CLIENT then return end

util.AddNetworkString("D6_DashDir")
util.AddNetworkString("D6_DashSync")

local function flying(ply)
    return IsValid(ply) and ply.D6On and ply:Alive() and not ply:InVehicle()
end

local function syncDash(ply, enabled, direction)
    net.Start("D6_DashSync")
    net.WriteEntity(ply)
    net.WriteBool(enabled)
    net.WriteVector(direction)
    net.Broadcast()
end

local function syncAdhesion(ply, anchor)
    if anchor then
        ply:SetNW2Vector("D6_AdhesionPoint", anchor.point)
        ply:SetNW2Vector("D6_AdhesionNormal", anchor.normal)
        ply:SetNW2Bool("D6_AdhesionPull", anchor.pull)
    end
    ply:SetNW2Int("D6_AdhesionEntity", anchor and (anchor.entity and anchor.entity:EntIndex() or 0) or -1)
end

function M.Carry(ply, duration)
    ply.D6_CarryUntil = math.max(ply.D6_CarryUntil or 0, CurTime() + duration)
end

function M.Release(ply, channel, carry)
    local anchor = ply.D6_Adhesion
    if not anchor or (channel and anchor.channel ~= channel) then return end
    ply.D6_Adhesion = nil
    if carry ~= false then M.Carry(ply, 0.68) end
    syncAdhesion(ply)
end

function M.Reset(ply)
    M.Release(ply, nil, false)
    if ply.D6DashOn then syncDash(ply, false, vector_origin) end
    ply.D6DashOn, ply.D6DashDir, ply.D6DashEnd, ply.D6DashCD = false, nil, nil, 0
    ply.D6_CarryUntil, ply.D6_UseHeld, ply.D6_AdhesionRetry = nil, nil, nil
    ply:SetNWFloat("D6DashCD", 0)
    ply:SetNWBool("D6_AirBrake", false)
end

function M.StartDash(ply, input)
    if not flying(ply) then return end
    local now = CurTime()
    if now < (ply.D6DashCD or 0) or ply.D6DashOn then return end
    if not D6_Energy.TryConsume(ply, "engines", 14) then
        if now >= (ply.D6_EngineDry or 0) then
            ply.D6_EngineDry = now + 0.3
            ply:EmitSound("buttons/button10.wav", 62, 101)
        end
        return
    end
    M.Release(ply)
    local aim = D6_Wep.AimAng(ply)
    local dir = aim:Forward()
    if input:LengthSqr() > 0 then
        dir = (dir*input.x + aim:Right()*input.y + aim:Up()*input.z):GetNormalized()
    end
    local vel = ply.D6Vel or vector_origin
    vel = vel + dir*math.max(1050, 2780 - vel:Dot(dir))
    if vel:LengthSqr() > M.BurstSpeed^2 then vel = vel:GetNormalized()*M.BurstSpeed end
    ply.D6Vel = vel
    ply.D6DashDir, ply.D6DashOn = dir, true
    ply.D6DashEnd, ply.D6DashCD = now + M.DashDuration, now + M.DashCooldown
    ply:SetNWFloat("D6DashCD", ply.D6DashCD)
    M.Carry(ply, 0.76)
    syncDash(ply, true, dir)
    local center = ply:WorldSpaceCenter()
    D6_Wep.MotionFX(center, center + dir*155, 1)
    ply:EmitSound("ambient/machines/thumper_top.wav", 72, 148)
    return true
end

concommand.Add("6dof_dash", function(ply)
    if IsValid(ply) then M.StartDash(ply, M.Steering(ply)) end
end)
net.Receive("D6_DashDir", function(length, ply)
    if length ~= 12 or not flying(ply) then return end
    local x, y, z = net.ReadInt(4), net.ReadInt(4), net.ReadInt(4)
    if math.abs(x) <= 1 and math.abs(y) <= 1 and math.abs(z) <= 1 then
        M.StartDash(ply, Vector(x, y, z))
    end
end)

local function movable(ent)
    if not IsValid(ent) or ent:GetMoveType() ~= MOVETYPE_VPHYSICS then return end
    local phy = ent:GetPhysicsObject()
    if IsValid(phy) and phy:IsMotionEnabled() then return phy end
end

function M.Attach(ply, channel, pull, aim)
    if not flying(ply) or ply.D6DashOn or ply.D6_Adhesion then return end
    local now = CurTime()
    if now < (ply.D6_AdhesionRetry or 0) then return end
    ply.D6_AdhesionRetry = now + 0.12
    aim = aim or D6_Wep.AimAng(ply)
    local eye, occlusion = D6_Arsenal.EyeClearance(ply, aim, MASK_SOLID)
    local hit = occlusion.Hit and occlusion or util.TraceLine({start = eye,
        endpos = eye + aim:Forward()*RANGE, filter = ply, mask = MASK_SOLID})
    if not hit.Hit or hit.HitSky or hit.StartSolid then return end
    local ent = not hit.HitWorld and hit.Entity or nil
    if ent and (not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsNextBot()
        or ent.D6_IsProjectile) then return end
    if pull and not movable(ent) then return end
    if not D6_Energy.TryConsume(ply, "engines", 4) then return end
    local point, normal = hit.HitPos, hit.HitNormal
    if ent then
        point = ent:WorldToLocal(hit.HitPos)
        normal = (ent:WorldToLocal(hit.HitPos + hit.HitNormal) - point):GetNormalized()
    end
    local anchor = {entity = ent, point = point, normal = normal, channel = channel, pull = pull == true}
    ply.D6_Adhesion = anchor
    syncAdhesion(ply, anchor)
    ply:EmitSound("weapons/physcannon/physcannon_pickup.wav", 64, 123)
    return true
end

for _, name in ipairs({"d6_adhere", "d6_whiplash"}) do
    concommand.Add("+" .. name, function(ply) M.Attach(ply, name) end)
    concommand.Add("-" .. name, function(ply)
        if IsValid(ply) then M.Release(ply, name) end
    end)
end

local function advanceField(ply, anchor, dt, ang, center, half)
    local ent = anchor.entity
    if ent and not IsValid(ent) then M.Release(ply); return end
    local point, normal = anchor.point, anchor.normal
    local physics = movable(ent)
    local anchorVelocity = vector_origin
    if ent then
        point = ent:LocalToWorld(anchor.point)
        normal = (ent:LocalToWorld(anchor.point + anchor.normal) - point):GetNormalized()
        anchorVelocity = physics and physics:GetVelocityAtPoint(point) or ent:GetVelocity()
    end
    local eye = D6_Arsenal.ScannerEye(ply, ang, center)
    local sight = util.TraceLine({start = eye, endpos = point + normal*3, filter = ply, mask = MASK_SOLID})
    if center:DistToSqr(point) > (RANGE + 260)^2 or (anchor.pull and not physics)
        or (sight.Hit and sight.Entity ~= ent and sight.HitPos:DistToSqr(point) > 12^2)
        or not D6_Energy.TryConsume(ply, "engines", dt*4.5) then
        M.Release(ply)
        return
    end
    -- Stand off by the full projected player hull, including floors and ceilings.
    local clearance = math.abs(normal.x)*half.x + math.abs(normal.y)*half.y + math.abs(normal.z)*half.z + 15
    if anchor.pull then clearance = clearance + 34 end
    local delta = point + normal*clearance - center
    local distance = delta:Length()
    if distance < 0.1 then return true end
    local dir = delta / distance
    local relativeSpeed = (ply.D6Vel - anchorVelocity):Dot(dir)
    local speed = math.min(distance*4.8, anchor.pull and 1600 or 2300)
    local accel = math.Clamp((speed - relativeSpeed)*8.5, -5800, 5800)
    -- Split the impulse by effective mass. A free prop is never assigned a velocity.
    if physics then accel = accel * physics:GetMass() / (physics:GetMass() + SHIP_MASS) end
    local impulse = dir * (accel*dt)
    ply.D6Vel = ply.D6Vel + impulse
    if physics then physics:ApplyForceOffset(-impulse*SHIP_MASS, point) end
    return true
end

function M.Step(ply, command, dt, center, half)
    local now = CurTime()
    if ply.D6DashOn and now >= ply.D6DashEnd then
        ply.D6DashOn = false
        syncDash(ply, false, vector_origin)
    end
    local use = command:KeyDown(IN_USE)
    if use and not ply.D6_UseHeld then M.Attach(ply, "use", false, command:GetViewAngles()) end
    if not use and ply.D6_UseHeld then M.Release(ply, "use") end
    ply.D6_UseHeld = use
    local anchor = ply.D6_Adhesion
    if anchor and IsEntity(anchor.channel) then
        local held = anchor.pull and IN_ATTACK2 or IN_ATTACK
        if ply:GetActiveWeapon() ~= anchor.channel or not command:KeyDown(held) then
            M.Release(ply, anchor.channel)
            anchor = nil
        end
    end
    local brake = command:KeyDown(IN_WALK)
    if brake ~= ply:GetNWBool("D6_AirBrake", false) then ply:SetNWBool("D6_AirBrake", brake) end
    local attached = anchor and advanceField(ply, anchor, dt, command:GetViewAngles(), center, half)
    if brake then
        ply.D6Vel = ply.D6Vel * math.exp(-dt*4.5)
        ply.D6_CarryUntil = nil
    end
    return attached, math.Clamp(((ply.D6_CarryUntil or 0) - now)/0.45, 0, 1), brake
end
