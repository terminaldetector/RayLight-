-- Run from tests/: texlua actors_unit.lua
-- Executes the real registry/session logic with a small engine boundary stub.
-- Native NPC damage/death and VPhysics require drmd_actor_verify.lua in GMod.
local root = arg[1] or "../descent_scanner/lua/"
local passed = 0
local function check(name, condition)
    assert(condition, name)
    passed = passed + 1
    print("PASS | " .. name)
end

SERVER, CLIENT = true, false
D_LI, D_HT = 3, 1
FCVAR_ARCHIVE, FCVAR_REPLICATED = 0, 0
function CreateConVar() return {GetString = function() return "arena" end} end
function IsValid(value) return type(value) == "table" and value.valid == true end
local function point(x)
    return {x = x, DistToSqr = function(self, other) return (self.x - other.x)^2 end}
end
local function entity(class, isNPC)
    local ent = {valid = true, class = class, npc = isNPC ~= false, hp = 100,
        network = {}, callbacks = {}, callbackAdds = 0, networkWrites = 0,
        origin = point(0), relations = {}, spawnCalls = 0}
    function ent:GetClass() return self.class end
    function ent:IsNPC() return self.npc end
    function ent:IsMarkedForDeletion() return self.removing == true end
    function ent:IsPlayer() return self.player == true end
    function ent:Health() return self.hp end
    function ent:SetHealth(hp) self.hp = hp end
    function ent:Alive() return self.hp > 0 end
    function ent:GetNWBool() return self.flight == true end
    function ent:SetNW2Bool(key, value)
        self.networkWrites = self.networkWrites + 1
        self.network[key] = value
    end
    function ent:GetNW2Bool(key, default)
        if self.network[key] == nil then return default end
        return self.network[key]
    end
    function ent:CallOnRemove(key, callback)
        self.callbackAdds = self.callbackAdds + 1
        self.callbacks[key] = callback
    end
    function ent:Remove()
        for _, callback in pairs(self.callbacks) do callback(self) end
        self.valid = false
    end
    function ent:StopSound() end
    function ent:WorldSpaceCenter() return self.origin end
    function ent:Disposition(other) return self.relations[other] or D_HT end
    function ent:Spawn() self.spawnCalls = self.spawnCalls + 1 end
    return ent
end
local hooks, deathEvents = {}, 0
local pending = {}
timer = {Simple = function(_, callback) pending[#pending+1] = callback end}
local function nextTick()
    local callbacks = pending
    pending = {}
    for _, callback in ipairs(callbacks) do callback() end
end
hook = {}
function hook.Add(event, id, fn)
    hooks[event] = hooks[event] or {}
    hooks[event][id] = fn
end
function hook.Run(event, ...)
    if event == "OnNPCKilled" then deathEvents = deathEvents + 1 end
    for _, fn in pairs(hooks[event] or {}) do fn(...) end
end
local players = {}
player = {GetAll = function() return players end}
ents = {Create = function(class)
    if class == "missing_class" then return nil end
    return entity(class, class ~= "prop_physics")
end}
dofile(root .. "d6_actors.lua")
dofile(root .. "d6_session.lua")
local A = D6_Actors

check("legacy scanner profiles resolve to independent actor",
    A.ResolveClass("npc_cscanner") == A.Class and A.ResolveClass("npc_clawscanner") == A.Class
    and A.ResolveClass(nil) == A.Class and A.ResolveClass("") == A.Class)
check("explicit non-scanner workshop NPC remains selectable", A.ResolveClass("npc_manhack") == "npc_manhack")
local ordinary = entity("npc_cscanner")
check("stock scanner cannot enter registry", not A.Register(ordinary) and not A.IsCombat(ordinary))
check("stock scanner cannot receive D6 variant", not D6_Session.SetVariant(ordinary, "mg")
    and ordinary.D6_Variant == nil and ordinary.networkWrites == 0 and ordinary.callbackAdds == 0)
local claw = entity("npc_clawscanner")
check("stock claw scanner is also untouched", not A.Register(claw) and claw.networkWrites == 0)

local actor = A.Create("npc_cscanner")
check("factory retains unspawned NPC contract", actor:GetClass() == A.Class
    and A.IsCombat(actor) and actor.spawnCalls == 0)
check("repeated registration does not duplicate lifecycle hooks", A.Register(actor)
    and actor.callbackAdds == 1 and #A.GetAll() == 1)
check("invalid and non-NPC factory requests fail", A.Create("missing_class") == nil
    and A.Create("prop_physics") == nil)
local custom = A.Create("npc_manhack")
check("custom NPC participates through explicit identity", A.IsCombat(custom) and #A.GetAll() == 2)
custom:Remove()
check("removal releases registry without inventing a kill", not A.IsCombat(custom)
    and #A.GetAll() == 1 and deathEvents == 0)

local alive = A.Create()
local stale = A.Create()
stale.valid = false -- Engine invalidation even if another addon skipped callbacks.
actor.hp = 0
check("dispatcher snapshot excludes dead and invalid actors", #A.GetAll() == 1
    and A.GetAll()[1] == alive and not A.Members[stale])
hook.Run("OnNPCKilled", actor)
check("native death notification only consumes registry membership", actor.D6_Dead
    and not A.IsCombat(actor) and deathEvents == 1 and IsValid(actor))
nextTick()
check("dedicated corpse retires after native death hooks without a second kill",
    not IsValid(actor) and deathEvents == 1)
local nativeCorpse = A.Create("npc_manhack")
nativeCorpse.hp = 0
hook.Run("OnNPCKilled", nativeCorpse)
nextTick()
check("explicit Workshop NPC retains its native corpse lifecycle",
    IsValid(nativeCorpse) and not A.IsCombat(nativeCorpse) and deathEvents == 2)
nativeCorpse:Remove()
nextTick()
check("post-death cleanup does not synthesize another kill", deathEvents == 2)

local function pilot(x, flying)
    local ply = entity("player", false)
    ply.player, ply.flight, ply.origin = true, flying, point(x)
    return ply
end
local ally, walking, near, far, dead = pilot(1, true), pilot(2, false), pilot(30, true), pilot(50, true), pilot(3, true)
dead.hp = 0
alive.relations[ally] = D_LI
players = {ally, walking, far, dead, near}
check("target acquisition excludes allies, dead and non-flight players", A.FindTarget(alive, 100) == near)
check("campaign targeting can explicitly allow a walking player", A.FindTarget(alive, 100, false) == walking)
check("target acquisition respects range", A.FindTarget(alive, 10) == nil)
A.Register(alive, far)
check("explicit eligible target is retained", A.FindTarget(alive, 100) == far)
far.flight = false
check("ineligible explicit target falls back to nearest pilot", A.FindTarget(alive, 100) == near)

SERVER, CLIENT = false, true
dofile(root .. "d6_actors.lua")
check("client identity accepts actor class and explicit network marker",
    A.IsCombat(alive) and A.IsCombat({valid=true, GetClass=function() return "npc_manhack" end,
        GetNW2Bool=function() return true end}) and not A.IsCombat(ordinary))

ENT = {}
function AddCSLuaFile() end
function include(path) dofile(root .. "entities/d6_combat_drone/" .. path) end
dofile(root .. "entities/d6_combat_drone/init.lua")
check("combat body is an AI NPC with its own flight and damage",
    ENT.Type == "ai" and ENT.Base == "base_ai" and ENT.RunAI({}) == false and type(ENT.OnTakeDamage) == "function")

SERVER, CLIENT = true, false
local testBody = A.Create()
local lethal = {GetDamage=function() return 1000 end,
    GetAttacker=function() return near end, GetInflictor=function() return near end}
ENT.OnTakeDamage(testBody, lethal)
ENT.OnTakeDamage(testBody, lethal)
check("dedicated lethal damage publishes exactly one common kill event", testBody.hp == 0 and deathEvents == 3)
print(string.format("COMPLETE | %d registry/session checks; native GMod test still required", passed))
