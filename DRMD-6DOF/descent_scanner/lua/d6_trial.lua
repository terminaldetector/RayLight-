if not SERVER then return end
D6_Trial = {}
local T = D6_Trial
local waves = {
    {"assault", "interceptor", "interceptor"},
    {"grav", "mg", "rpg", "manhack_fast"},
    {"resistance_scout", "resistance_scout", "resistance_raider", "resistance_hauler"},
    {"rocket_strider", "heavy_elite", "interceptor"},
}
local sessions = {}
local labels = {"Перехват", "Гравитационный рой", "Дроны Сопротивления", "Тяжёлая группа Альянса"}

local function done(ply, message)
    local session = sessions[ply]
    if not session then return end
    sessions[ply] = nil
    for _, npc in ipairs(session.npcs) do
        if IsValid(npc) then npc:Remove() end
    end
    for _, ent in ipairs(session.props) do
        if IsValid(ent) then ent:Remove() end
    end
    if not IsValid(ply) then return end
    ply:SetNW2Int("D6_TrialWave", 0)
    ply:SetNW2String("D6_TrialStatus", message or "")
end

local function canSpawn(pos, ply)
    if not util.IsInWorld(pos) then return false end
    local hull = Vector(24, 24, 24)
    local check = util.TraceHull({start = ply:WorldSpaceCenter(), endpos = pos, filter = ply,
        mins = -hull, maxs = hull, mask = MASK_SOLID_BRUSHONLY})
    return not check.Hit
end

local function spawn(ply, session)
    local wave = waves[session.wave]
    if not wave then done(ply, "Испытание пройдено"); return end
    local origin = ply:WorldSpaceCenter()
    local direction = Angle(0, ply:EyeAngles().y, 0)
    local fwd, right = direction:Forward(), direction:Right()
    for i, name in ipairs(wave) do
        local lateral = (i - (#wave + 1)*0.5)*134
        local pos = origin + fwd*(560 + i*35) + right*lateral + Vector(0, 0, 105 + (i%2)*100)
        if not canSpawn(pos, ply) then
            pos = origin + fwd*190 + right*lateral*0.44 + Vector(0, 0, 70)
        end
        if not canSpawn(pos, ply) then continue end

        local npc
        if name == "rocket_strider" then npc = SpawnRocketStrider(ply, pos)
        elseif name == "manhack_fast" then npc = SpawnManhackKamikaze(ply, pos)
        elseif name == "grav" or name == "mg" or name == "rpg" then npc = SpawnEnemyDrone(ply, "npc_cscanner", name, pos)
        else npc = SpawnD6Role(name, pos, ply) end
        if IsValid(npc) then session.npcs[#session.npcs + 1] = npc end
    end

    if #session.npcs == 0 then
        done(ply, "Для волны нужно больше свободного места")
        return
    end
    if session.wave == 2 then
        for i = -2, 2 do
            local pos = origin + fwd*395 + right*i*89 + Vector(0, 0, 84)
            if not canSpawn(pos, ply) then continue end
            local ent = D6_Wep.Ordnance("salvage_ballast", pos, nil,
                {mobile = true, gravity = true, mass = 23, collectible = true, group = COLLISION_GROUP_NONE})
            if not IsValid(ent) then continue end
            session.props[#session.props + 1] = ent
        end
    end
    ply:SetNW2Int("D6_TrialWave", session.wave)
    ply:SetNW2String("D6_TrialStatus", labels[session.wave])
end

function T.IsActive(ply) return sessions[ply] ~= nil end

function T.Start(ply)
    if not IsValid(ply) or not ply.D6On or not D6_Session.IsArena() or sessions[ply] or D6_Rogue.IsActive(ply) then return false end
    local session = {wave = 1, npcs = {}, props = {}, advance = CurTime()}
    sessions[ply] = session
    spawn(ply, session)
    return sessions[ply] ~= nil
end

function T.Stop(ply) done(ply, "Испытание завершено") end

timer.Create("D6_TrialProgress", 0.25, 0, function()
    for ply, session in pairs(sessions) do
        if not IsValid(ply) or not ply:Alive() or not ply.D6On then
            done(ply, "")
        else
            local alive = false
            for _, npc in ipairs(session.npcs) do
                if IsValid(npc) and npc:Health() > 0 then alive = true; break end
            end
            if alive then
                session.advance = CurTime() + 2.5
            elseif CurTime() >= session.advance then
                session.wave = session.wave + 1
                for _, ent in ipairs(session.props) do if IsValid(ent) then ent:Remove() end end
                session.npcs, session.props = {}, {}
                spawn(ply, session)
            end
        end
    end
end)

concommand.Add("d6_trial_start", function(ply)
    if D6_Session.CanEditWorld(ply) then T.Start(ply) end
end)
concommand.Add("d6_trial_stop", function(ply) T.Stop(ply) end)
hook.Add("PlayerDisconnected", "D6_TrialCleanup", T.Stop)
