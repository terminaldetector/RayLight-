-- Combat identity is independent of a model or an engine NPC class.
-- Only D6 factories translate old scanner profiles; normal HL2 scanners are untouched.
D6_Actors = D6_Actors or {}
local A = D6_Actors
A.Class = "d6_combat_drone"
A.Members = A.Members or {}
local members = A.Members

function A.ResolveClass(class)
    if class == nil or class == "" or class == "npc_cscanner" or class == "npc_clawscanner" then
        return A.Class
    end
    return class
end

function A.IsCombat(ent)
    if not IsValid(ent) then return false end
    if SERVER then return members[ent] == true end
    return ent:GetClass() == A.Class or ent:GetNW2Bool("D6_CombatActor", false)
end

if not SERVER then return end

function A.Unregister(ent)
    members[ent] = nil
end

function A.Register(ent, target)
    if not IsValid(ent) or not ent:IsNPC() then return false end
    -- Never turn a native map scanner into a combat actor through a stray variant call.
    local class = ent:GetClass()
    if class == "npc_cscanner" or class == "npc_clawscanner" then return false end
    if not members[ent] then
        members[ent] = true
        ent:SetNW2Bool("D6_CombatActor", true)
        ent:CallOnRemove("D6_ActorRegistry", A.Unregister)
    end
    if IsValid(target) then ent.D6_Target = target end
    return true
end

-- Returns an unspawned NPC, matching ents.Create's contract. Callers retain their
-- existing position/model/Spawn/Activate ordering and loadout setup.
function A.Create(class)
    local ent = ents.Create(A.ResolveClass(class))
    if not IsValid(ent) then return nil end
    if not A.Register(ent) then ent:Remove(); return nil end
    return ent
end

-- A snapshot lets dispatchers safely remove actors while walking the list.
function A.GetAll()
    local result = {}
    for ent in pairs(members) do
        if not IsValid(ent) then
            members[ent] = nil
        elseif not ent.D6_Dead and ent:Health() > 0 then
            result[#result + 1] = ent
        end
    end
    return result
end

-- Legacy batteries cannot rely on scanner schedules to acquire their enemy.
function A.FindTarget(ent, range, requireFlight)
    local origin = ent:WorldSpaceCenter()
    local limit = (range or 3000)^2
    local function eligible(ply)
        return IsValid(ply) and ply:IsPlayer() and ply:Alive()
            and (requireFlight == false or ply:GetNWBool("D6On", false))
            and ent:Disposition(ply) ~= D_LI
    end
    local target = ent.D6_Target
    if eligible(target) and origin:DistToSqr(target:WorldSpaceCenter()) <= limit then return target end
    local best
    for _, ply in ipairs(player.GetAll()) do
        if eligible(ply) then
            local distance = origin:DistToSqr(ply:WorldSpaceCenter())
            if distance < limit then best, limit = ply, distance end
        end
    end
    return best
end

-- Base AI owns damage, health and the native death event. Do not synthesize a
-- second OnNPCKilled from OnTakeDamage/OnRemove: cleanup must never award a kill.
hook.Add("OnNPCKilled", "D6_ActorDied", function(ent)
    if not members[ent] then return end
    ent.D6_Dead = true
    ent:StopSound("ambient/energy/zap_loop1.wav")
    A.Unregister(ent)
    if ent:GetClass() == A.Class then
        -- RunAI deliberately disables engine schedules, including SCHED_DIE for
        -- non-ragdoll chassis. Retire only our body after all native death hooks
        -- have observed it; explicit Workshop NPCs keep their own corpse policy.
        timer.Simple(0, function() if IsValid(ent) then ent:Remove() end end)
    end
end)
