-- GMod server integration probe. Copy into garrysmod/lua/, then run:
-- lua_openscript drmd_actor_verify.lua
-- d6_verify_combat_actor
-- Use an empty test map. This checks the engine damage/death and physics contract;
-- it is deliberately not a substitute for visual flash/flight playtesting.
if not SERVER then return end

local running = false
concommand.Add("d6_verify_combat_actor", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    if running then MsgN("[D6 Actor QA] already running"); return end
    if not D6_Actors or not D6_Session then ErrorNoHalt("[D6 Actor QA] addon is not loaded\n"); return end
    running = true
    local failures, checks, fixtures, kills = 0, 0, {}, {}
    local function check(name, pass)
        checks = checks + 1
        if not pass then failures = failures + 1 end
        MsgN("[D6 Actor QA] " .. (pass and "PASS" or "FAIL") .. " | " .. name)
    end
    local origin = IsValid(ply) and ply:GetPos() + Vector(0, 0, 220) or Vector(0, 0, 500)
    local function track(ent)
        if not IsValid(ent) then return nil end
        fixtures[#fixtures + 1] = ent
        kills[ent] = 0
        return ent
    end
    local function spawn(ent, offset)
        if not track(ent) then return nil end
        ent:SetPos(origin + offset)
        ent:Spawn()
        ent:Activate()
        return ent
    end
    local hookID = "D6_CombatActorRegression"
    hook.Add("OnNPCKilled", hookID, function(ent)
        if kills[ent] ~= nil then kills[ent] = kills[ent] + 1 end
    end)
    local function finish()
        for _, ent in ipairs(fixtures) do if IsValid(ent) then ent:Remove() end end
        hook.Remove("OnNPCKilled", hookID)
        running = false
        MsgN(string.format("[D6 Actor QA] COMPLETE | %d checks | %d failures", checks, failures))
    end

    local stock = spawn(ents.Create("npc_cscanner"), Vector(400, 0, 0))
    local actor = spawn(D6_Actors.Create("npc_cscanner"), Vector(0, 0, 0))
    local cleanup = spawn(D6_Actors.Create(), Vector(-400, 0, 0))
    check("both native and combat entities spawn", IsValid(stock) and IsValid(actor) and IsValid(cleanup))
    if not IsValid(stock) or not IsValid(actor) or not IsValid(cleanup) then finish(); return end

    check("native scanner stays native and rejects D6 tagging", stock:GetClass() == "npc_cscanner"
        and not D6_Session.SetVariant(stock, "mg") and stock.D6_Variant == nil
        and not stock:GetNW2Bool("D6_CombatActor", false) and not D6_Actors.IsCombat(stock))
    check("legacy combat profile spawns a real independent NPC", actor:GetClass() == D6_Actors.Class
        and actor:IsNPC() and D6_Actors.IsCombat(actor) and actor:RunAI() == false)
    local physics = actor:GetPhysicsObject()
    check("combat body has gravity-free VPhysics", IsValid(physics) and not physics:IsGravityEnabled()
        and actor:GetMoveType() == MOVETYPE_VPHYSICS)
    check("modular builder is available", isfunction(D6_BuildDrone))
    if not isfunction(D6_BuildDrone) then finish(); return end
    -- Validate both the VPhysics collision body and the authored shot trace.
    local small = track(D6_BuildDrone({scale=1, collisionScale=1}, origin + Vector(600, -150, 0)))
    local large = track(D6_BuildDrone({scale=1, collisionScale=2}, origin + Vector(600, 150, 0)))
    local function boxFace(ent, expected)
        if not IsValid(ent) then return false end
        ent:SetAngles(angle_zero)
        local center = ent:GetPos() + Vector(0, 0, 3)
        local body = ent:GetPhysicsObject()
        if not IsValid(body) then return false end
        local mins, maxs = body:GetAABB()
        if math.abs(maxs.x-expected) > .01 or math.abs(mins.x+expected) > .01 then return false end
        local trace = D6_Wep.CombatTrace({start=center+Vector(80,0,0), endpos=center,
            mask=MASK_SOLID, ignoreworld=true, filter=function(hit) return hit == ent end})
        return trace.Entity == ent and math.abs(trace.HitPos.x - center.x - expected) < 1.5
    end
    check("ordinary owned hull has 12-unit half-width", boxFace(small, 12))
    check("collisionScale doubles physical hull half-width", boxFace(large, 24))
    local start = actor:GetPos()
    if IsValid(physics) then physics:SetVelocity(Vector(0, 120, 70)) end

    timer.Simple(0.15, function()
        if not IsValid(actor) then check("actor survives before lethal damage", false); finish(); return end
        check("VPhysics changes both horizontal and vertical position",
            actor:GetPos().y > start.y + 1 and actor:GetPos().z > start.z + 1)
        cleanup:Remove()
        check("cleanup emits no native kill event", kills[cleanup] == 0 and not D6_Actors.IsCombat(cleanup))
        actor:TakeDamage(10, game.GetWorld(), game.GetWorld())
        check("ordinary damage lowers hull without reporting a kill", actor:Health() == 90 and kills[actor] == 0)
        local damage = DamageInfo()
        damage:SetDamage(actor:GetMaxHealth() + 10000)
        damage:SetDamageType(DMG_GENERIC)
        damage:SetAttacker(game.GetWorld())
        damage:SetInflictor(game.GetWorld())
        actor:TakeDamageInfo(damage)
        timer.Simple(0.1, function()
            check("lethal engine damage emits exactly one OnNPCKilled", kills[actor] == 1)
            check("dead actor leaves active registry", not D6_Actors.IsCombat(actor))
            check("dedicated dead body retires without manual cleanup", not IsValid(actor))
            timer.Simple(0.1, function()
                check("post-death cleanup does not emit a duplicate event", kills[actor] == 1)
                check("ordinary scanner remains outside D6 dispatchers", IsValid(stock)
                    and not D6_Actors.IsCombat(stock) and stock.D6_Variant == nil)
                finish()
            end)
        end)
    end)
end)
