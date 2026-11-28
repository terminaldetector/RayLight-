-- Optional autorun/server probe for an empty dedicated gm_flatgrass Sandbox.
if not SERVER or game.GetMap() ~= "gm_flatgrass" then return end

local prefix = "[D6 Combat Continuation QA] "
local checks, failures, fixtures = 0, 0, {}
local pilot

local function check(name, pass, detail)
    checks = checks + 1
    if not pass then failures = failures + 1 end
    MsgN(prefix .. (pass and "PASS" or "FAIL") .. " | " .. name
        .. (detail and (" | " .. tostring(detail)) or ""))
    return pass
end

local function track(ent)
    if IsValid(ent) then fixtures[#fixtures + 1] = ent end
    return ent
end

local function finish()
    for _, ent in ipairs(fixtures) do
        if IsValid(ent) then ent:Remove() end
    end
    if IsValid(pilot) then pilot:Kick("Abaddon test complete") end
    MsgN(string.format("%sCOMPLETE | %d checks | %d failures", prefix, checks, failures))
end

local function watch(name, duration, sample, done)
    local deadline = CurTime() + duration
    timer.Create(name, 0.03, 0, function()
        sample()
        if CurTime() < deadline then return end
        timer.Remove(name)
        done()
    end)
end

local function interceptors()
    local origin = pilot:GetPos()
    local first = track(SpawnD6Role("interceptor", origin + Vector(510, -35, 95), pilot))
    local second = track(SpawnD6Role("interceptor", origin + Vector(510, 35, 95), pilot))
    if not check("two real interceptor actors spawn", IsValid(first) and IsValid(second)) then
        finish()
        return
    end

    local startingPoint = first:GetPos()
    local distinct, denied, shot, recover, released, overlap = false, false, false, false, false, false
    local function committed(state)
        return state and (state.phase == "windup" or state.phase == "pass")
    end
    local function fired()
        for _, projectile in ipairs(ents.FindByClass("d6_projectile")) do
            local owner = projectile:GetOwner()
            if owner == first or owner == second then return true end
        end
        return false
    end
    watch("D6ContinuationInterceptors", 10, function()
        if not IsValid(first) or not IsValid(second) then return end
        local a, b = first.D6_Intercept, second.D6_Intercept
        if a and b and a.target == pilot and b.target == pilot and a.lane and b.lane then
            distinct = distinct or a.lane ~= b.lane
            overlap = overlap or (committed(a) and committed(b)) or a.lane == b.lane
            denied = denied or (committed(a) and b.phase == "approach")
                or (committed(b) and a.phase == "approach")
        end
        shot = shot or fired()
        recover = recover or (a and a.phase == "recover") or (b and b.phase == "recover")
        released = released or (recover and (not a or not b))
    end, function()
        check("interceptors reserve two distinct lanes on the same target", distinct and not overlap)
        check("only one interceptor commits at a time while the wingmate approaches", denied and not overlap)
        check("the committed group launches real NPC-owned projectiles", shot)
        check("the attack recovers and releases a lane for reserves", recover and released)
        check("the interceptor follows its path through VPhysics",
            IsValid(first) and first:GetPos():DistToSqr(startingPoint) > 100 ^ 2)
        pilot:KillSilent()
        timer.Simple(0.25, function()
            check("Prisma is removed when its pilot dies",
                not IsValid(D6_Supports.GetEntity(pilot, 1)))
            check("interceptors release their lanes when they lose the target",
                not first.D6_Intercept and not second.D6_Intercept)
            finish()
        end)
    end)
end

local function prism()
    local supports = D6_Supports
    local reflector = supports.GetEntity(pilot, 1)
    if not check("Prisma exists in the stock flight loadout", IsValid(reflector)) then
        finish()
        return
    end
    local dockBegin = reflector:GetPos()
    timer.Simple(0.5, function()
        check("unpowered Prisma follows its own orbit with the pilot stationary",
            reflector:GetPos():DistToSqr(dockBegin) > 1)
        local model = supports.Definitions.reflector.model
        local attachmentId = reflector:LookupAttachment("receptor")
        local receptor = reflector:GetAttachment(attachmentId)
        local socket = supports.Socket(reflector, 1)
        check("compiled Prisma and its receptor resolve in the Source engine",
            model and reflector:GetModel() == model and attachmentId > 0 and receptor
            and receptor.Pos:DistToSqr(socket) < 0.5 ^ 2,
            ("model=%s receptor=%d %s planned=%s"):format(reflector:GetModel(), attachmentId,
                tostring(receptor and receptor.Pos), tostring(socket)))

        local cells, energy = pilot:GetAmmoCount(supports.Ammo), D6_Energy.Get(pilot)
        local activated = supports.Activate(pilot, 1)
        check("manual deploy spends one cell and the specified energy",
            activated and pilot:GetAmmoCount(supports.Ammo) == cells - 1
            and math.abs(D6_Energy.Get(pilot) - (energy - supports.Definitions.reflector.energy)) < 0.01)
        timer.Simple(0.95, function()
            local socket = supports.Socket(reflector, 1)
            local forward, right = reflector:GetForward(), reflector:GetRight()
            local target = track(D6_Actors.Create())
            if not check("real off-axis combat target spawns", IsValid(target)) then finish(); return end
            local flank = Vector(right.x, right.y, 0):GetNormalized()
            local targetPosition = socket + 335 * forward + 120 * flank + Vector(0, 0, 32)
            target:SetPos(targetPosition)
            target:Spawn()
            target:SetMaxHealth(500)
            target:SetHealth(500)
            local physics = target:GetPhysicsObject()
            if IsValid(physics) then physics:EnableMotion(false) end
            target:AddEntityRelationship(pilot, D_HT, 99)
            local heavy = pilot:GetWeapon("weapon_d6_heavy")
            if not IsValid(heavy) then heavy = pilot:Give("weapon_d6_heavy") end
            local shot = track(D6_Wep.FireProjectile({
                owner=pilot, weapon=heavy, pos=socket - 110 * forward, dir=forward,
                speed=1850, swept=true, inherit=0, dmgClass="energy", life=1,
            }))
            check("charged-fire input is a real swept heavy projectile",
                IsValid(shot) and shot.D6_WeaponClass == "weapon_d6_heavy",
                "weapon=" .. tostring(heavy) .. " projectile=" .. tostring(shot and shot.D6_WeaponClass))

            local charged, stamps, diagnostic = false, 0, ""
            local lastShot = reflector:GetNWFloat("D6_SupportShotAt", 0)
            watch("D6ContinuationPrisma", 2.5, function()
                if not charged and reflector:GetNWString("D6_SupportCombat") == "charged_fire" then
                    charged = true
                    local muzzle = supports.Socket(reflector, 1)
                    local plan = supports.FindTarget(pilot, muzzle, 1250, reflector, forward)
                    local trace = util.TraceLine({start=muzzle, endpos=target:WorldSpaceCenter(),
                        filter={pilot, reflector}, mask=MASK_SHOT})
                    diagnostic = (" hostile=%s visible=%s candidate=%s hit=%s from=%s to=%s"):format(
                        tostring(supports.IsHostile(pilot, target)), tostring(supports.Visible(pilot, muzzle, target, reflector)),
                        tostring(plan), tostring(trace.Entity), tostring(muzzle), tostring(target:WorldSpaceCenter()))
                end
                local shotAt = reflector:GetNWFloat("D6_SupportShotAt", 0)
                if shotAt > lastShot then stamps, lastShot = stamps + 1, shotAt end
            end, function()
                check("own heavy contact starts the finite automatic burst", charged and not IsValid(shot))
                check("burst has three shots and causes damage on the real target",
                    stamps == 3 and target:Health() < 500, ("shots=%d hp=%d%s"):format(stamps, target:Health(),
                    stamps == 0 and diagnostic or ""))
                check("Prisma exits charged fire without a second payment or stock refill",
                    reflector:GetNWString("D6_SupportCombat") == "redirect"
                    and pilot:GetAmmoCount(supports.Ammo) == cells - 1)
                local redirected = false
                local origin, direction = supports.Socket(reflector, 1), reflector:GetForward()
                local plasma = pilot:GetWeapon("weapon_d6_plasma")
                track(D6_Wep.FireProjectile({
                    owner=pilot, weapon=plasma, pos=origin - 110 * direction, dir=direction,
                    speed=1850, swept=true, inherit=0, dmgClass="energy", life=1,
                    onHit=function(projectile, victim)
                        redirected = victim == target and projectile.D6_SupportReflected
                            and projectile:GetOwner() == pilot
                    end,
                }))
                timer.Simple(0.6, function()
                    check("ordinary reflection resumes after the burst and preserves ownership",
                        redirected and reflector.D6_SupportRemaining == 3)
                    supports.Recall(pilot, 1)
                    target:Remove()
                    interceptors()
                end)
            end)
        end)
    end)
end

hook.Add("InitPostEntity", "D6CombatContinuationProbe", function()
    timer.Simple(0.8, function()
        pilot = player.CreateNextBot("Abaddon Combat Pilot")
        if not check("flight test pilot connects", IsValid(pilot)) then finish(); return end
        pilot:GodEnable()
        timer.Simple(1.5, function()
            -- Clear the raised map spawn platform before laying out the shot.
            pilot:SetPos(pilot:GetPos() + Vector(0, 0, 850))
            pilot.D6Vel = Vector()
            pilot.D6AngSynced = Angle(0, 0, 28)
            if check("pilot is in Sandbox flight", D6_Supports and D6_Supports.CanUse(pilot)) then
                timer.Simple(0.25, prism)
            else
                finish()
            end
        end)
    end)
end)
