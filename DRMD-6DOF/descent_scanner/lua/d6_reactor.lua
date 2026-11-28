D6_Reactor = {
    RogueMap = "d6_rogue_reactor",
    Cooling = 1,
    Critical = 2,
    Escape = 3,
    StorySeconds = 58,
    RogueSeconds = 40,
}
local R = D6_Reactor

if CLIENT then return end

local current
local storyProfile = {hull = 455, coolant = 65, criticalDelay = 5.2}
local rogueProfile = {hull = 315, coolant = 53, criticalDelay = 4.2}

local function named(name)
    return ents.FindByName(name)[1]
end

local function canFly(ply)
    return IsValid(ply) and ply:IsPlayer() and ply:Alive() and ply.D6On
end

local function viewState(ply, state)
    local phase = state and state.phase or 0
    local actor = state and state.core
    local deadline = phase == R.Escape and state.deadline or 0
    local heat = IsValid(actor) and actor:GetCharge() or 0
    local hull = IsValid(actor) and actor:GetHealthFraction() or 0
    ply:SetNW2Int("D6_ReactorPhase", phase)
    ply:SetNW2Float("D6_ReactorHeat", heat)
    ply:SetNW2Float("D6_ReactorIntegrity", hull)
    ply:SetNW2Float("D6_ReactorDeadline", deadline)
    ply:SetNW2Int("D6_ReactorCoolantTotal", state and state.total or 0)
    ply:SetNW2Int("D6_ReactorCoolantDown", state and state.disabled or 0)
    ply:SetNW2String("D6_ReactorOrder", state and state.order or "")
    for i = 1, 3 do
        local node = state and state.nodes[i]
        ply:SetNW2Entity("D6_ReactorNode"..i, IsValid(node) and node:GetNodeEnabled() and node or NULL)
    end
    ply:SetNW2Vector("D6_ReactorWaypoint", state and (phase == R.Escape and state.goal or state.origin) or vector_origin)
end

local function sync()
    local state = current
    for _, ply in ipairs(player.GetAll()) do
        viewState(ply, state and (not state.rogue or state.owner == ply) and state or nil)
    end
end

local function spawnNode(mark, kind, hp, state, enabled)
    local node = ents.Create("d6_reactor_node")
    if not IsValid(node) then return end
    node.D6_ReactorState = state
    node:SetPos(mark:GetPos())
    node:SetAngles(mark:GetAngles())
    node:SetNodeKind(kind)
    node:SetNodeEnabled(enabled == true)
    node:SetHealthFraction(1)
    node:SetMaxHealth(hp)
    node:SetHealth(hp)
    node:Spawn()
    return node
end

local function clear()
    local state = current
    if not state then return end
    current = nil
    D6_ReactorHazards.Reset(state)
    if IsValid(state.core) then state.core:Remove() end
    for _, node in pairs(state.nodes) do
        if IsValid(node) then node:Remove() end
    end
    sync()
end

function R.Prepare(rogue)
    clear()
    local mark = named("d6_reactor_center")
    local goal = named("d6_reactor_escape_goal")
    local gate = named("d6_reactor_escape_gate")
    if not IsValid(mark) or not IsValid(goal) or (rogue and not IsValid(gate)) then return end
    local profile = rogue and rogueProfile or storyProfile
    local state = {phase = 0, rogue = rogue, nodes = {}, disabled = 0, total = 0,
        origin = mark:GetPos(), goal = goal:GetPos(), gate = gate, profile = profile}
    state.eligible = function(ply)
        return canFly(ply) and (not state.rogue or state.owner == ply)
    end
    state.core = spawnNode(mark, 0, profile.hull, state)
    if not IsValid(state.core) then return end
    current = state
    if rogue then
        gate:Fire("Close")
    else
        local native = named("d6_reactor_core")
        if IsValid(native) then
            native:SetNoDraw(true)
            native:SetNotSolid(true)
        end
        local oldProfile = named("d6_reactor_profile")
        if IsValid(oldProfile) then oldProfile:SetNoDraw(true) end
    end
    sync()
    return state
end

function R.Busy()
    return current and current.owner ~= nil
end

local function setPhase(state, phase, order)
    state.phase, state.order = phase, order
    state.core:SetReactorPhase(phase)
    sync()
end

local function start(state, owner, seed, onResult)
    local active = {}
    -- Two enabled conduits, one reserve. Only the seed chooses which reserve is visible.
    local reserve = state.rogue and (seed * 16807 % 2147483647) % 3 + 1 or nil
    for i = 1, 3 do
        local mark = named("d6_reactor_coolant_"..i)
        if not IsValid(mark) then return false end
        active[i] = mark
    end
    state.total = state.rogue and 2 or 3
    for i, mark in ipairs(active) do
        local node = spawnNode(mark, 1, state.profile.coolant, state, i ~= reserve)
        if not IsValid(node) then R.Prepare(state.rogue); return false end
        state.nodes[i] = node
        node:SetReactorPhase(R.Cooling)
    end
    state.owner, state.seed, state.onResult = owner, seed, onResult
    setPhase(state, R.Cooling, "Отключить контуры охлаждения")
    return true
end

function R.StartStory()
    return current and not current.rogue and current.phase == 0 and start(current, nil, 26743)
end

function R.StartRogue(ply, seed, onResult)
    if not current or not current.rogue or current.phase ~= 0 or not canFly(ply) then return false end
    return start(current, ply, seed, onResult)
end

function R.EndRogue(ply)
    if current and current.rogue and current.owner == ply then R.Prepare(true) end
end

function R.FinishStory()
    if not current or current.rogue or current.phase ~= R.Escape then return end
    D6_ReactorHazards.Reset(current)
    current.phase, current.order = 0, nil
    sync()
end

function R.NativeCoreCanBreak()
    return current and not current.rogue and current.phase == R.Escape
end

function R.Hittable(ent, ply)
    local state = ent.D6_ReactorState
    if not state or current ~= state or not state.eligible(ply) then return false end
    if ent == state.core then return state.phase == R.Critical end
    return state.phase == R.Cooling and ent:GetNodeEnabled()
end

local function breach(state)
    local core = state.core
    core:SetSolid(SOLID_NONE)
    core:EmitSound("ambient/explosions/explode_4.wav", 100, 91)
    util.ScreenShake(state.origin, 9, 45, 1.2, 2850)
    local effect = EffectData()
    effect:SetOrigin(state.origin)
    util.Effect("Explosion", effect, true, true)
    state.deadline = CurTime() + (state.rogue and R.RogueSeconds or R.StorySeconds)
    setPhase(state, R.Escape, "Аварийный выход открыт")
    if state.rogue then
        if IsValid(state.gate) then state.gate:Fire("Open") end
    else
        local native = named("d6_reactor_core")
        local relay = named("d6_core_failure")
        if IsValid(native) and IsValid(relay) then native:Fire("Break")
        elseif IsValid(relay) then relay:Fire("Trigger") end
    end
end

function R.Hit(ent, damage)
    if damage:GetDamage() <= 0 or not R.Hittable(ent, damage:GetAttacker()) then return end
    local state = current
    local hp = math.max(0, ent:Health() - math.max(1, math.floor(damage:GetDamage()+.5)))
    ent:SetHealth(hp)
    ent:SetHealthFraction(hp / ent:GetMaxHealth())
    if hp > 0 then sync(); return end
    ent:SetNodeEnabled(false)
    if ent == state.core then breach(state); return end

    ent:SetSolid(SOLID_NONE)
    ent:EmitSound("ambient/energy/spark4.wav", 84, 85)
    state.disabled = state.disabled + 1
    state.core:SetCharge(state.disabled / state.total * .74)
    if state.disabled == state.total then
        state.criticalAt = CurTime() + state.profile.criticalDelay
        state.order = "Охлаждение отключено · растёт температура"
        state.core:EmitSound("ambient/alarms/klaxon1.wav", 86, 104)
    end
    sync()
end

timer.Create("D6_ReactorControl", .12, 0, function()
    local state = current
    if not state or state.phase == 0 then return end
    if not IsValid(state.core) then
        if state.rogue and state.onResult then state.onResult(false) end
        return
    end
    local now = CurTime()
    if state.criticalAt and state.phase == R.Cooling then
        state.core:SetCharge(.74 + .26 * math.Clamp(1-(state.criticalAt-now)/state.profile.criticalDelay, 0, 1))
        if now >= state.criticalAt then
            state.core:EmitSound("ambient/machines/teleport3.wav", 88, 79)
            setPhase(state, R.Critical, "КРИТИЧЕСКАЯ МАССА · пробить ядро")
        else
            sync()
        end
    end
    if state.rogue and state.phase == R.Escape and canFly(state.owner) then
        local center = state.owner:WorldSpaceCenter()
        if now >= state.deadline then
            state.onResult(false)
            return
        end
        if center:DistToSqr(state.goal) <= 112^2 and
            not util.TraceLine({start=center, endpos=state.goal, mask=MASK_SOLID_BRUSHONLY}).Hit then
            state.onResult(true)
            return
        end
    end
    D6_ReactorHazards.Tick(state, now)
end)

hook.Add("InitPostEntity", "D6_RogueReactorInit", function()
    if game.GetMap() == R.RogueMap then R.Prepare(true) end
end)
hook.Add("PlayerSpawn", "D6_ReactorPilotSync", function() sync() end)
