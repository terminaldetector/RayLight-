D6_Mission = {}
local M = D6_Mission
M.City = "d6_city17_drain"
M.Reactor = "d6_reactor_escape"

function M.IsEpisode()
    local map = game.GetMap()
    return map == M.City or map == M.Reactor
end

function M.AllowsFlight()
    return game.GetMap() ~= M.City
end

if CLIENT then return end
local stage, objective, expires = 0, "", 0
local caption, captionEnd, pendingGuard="",0,nil
local missionUnits = {}
local waveTypes = {
    swarm = {"grav","mg","laser","rpg","manhack_fast"},
    guard = {"rocket_strider","plasma_strider","manhack_fast"},
}

local function publish(ply)
    ply:SetNW2Int("D6_EpisodeStage",stage)
    ply:SetNW2String("D6_EpisodeOrder",objective)
    ply:SetNW2Float("D6_EpisodeDeadline",expires)
    ply:SetNW2String("D6_EpisodeCaption",caption)
    ply:SetNW2Float("D6_EpisodeCaptionEnd",captionEnd)
end

local function advance(nextStage, label, deadline)
    stage, objective, expires = nextStage, label, deadline or 0
    for _, ply in ipairs(player.GetAll()) do publish(ply) end
end

local function marker(name)
    local mark = ents.FindByName(name)[1]
    return IsValid(mark) and mark:GetPos() or nil
end

local function cue(text, duration)
    caption,captionEnd=text,CurTime()+(duration or 3)
    for _,ply in ipairs(player.GetAll()) do publish(ply) end
end

local function policeRelation(ply, hostile)
    for _,class in ipairs({"npc_combine_s","npc_metropolice","npc_strider","npc_helicopter"}) do
        for _,npc in ipairs(ents.FindByClass(class)) do
            npc:AddEntityRelationship(ply,hostile and D_HT or D_NU,96)
            if not hostile and npc:GetEnemy()==ply then npc:SetEnemy(NULL) end
        end
    end
end

local function crowdRuns()
    local safe=marker("d6_crowd_shelter")
    if not safe then return end
    for i,npc in ipairs(ents.FindByName("d6_citizen_*")) do
        local refugee=npc
        timer.Simple((i-1)*.13,function()
            if not IsValid(refugee) or refugee:Health()<=0 then return end
            refugee:SetLastPosition(safe+Vector((i%4)*22,math.floor(i/4)*23,0))
            refugee:SetSchedule(SCHED_FORCED_GO_RUN)
        end)
    end
end

function M.NewCloud(pos, energy, heal)
    local cloud = ents.Create("d6_energy_cloud")
    if not IsValid(cloud) then return end
    cloud.D6_Charge, cloud.D6_Healing = energy, heal
    cloud:SetPos(pos)
    cloud:Spawn()
    return cloud
end

local function spawnWave(ply, which)
    for i, variant in ipairs(waveTypes[which]) do
        local pos = marker("d6_"..which.."_"..i)
        if not pos then continue end
        local npc
        if variant == "manhack_fast" then npc = SpawnManhackKamikaze(ply,pos)
        elseif variant == "rocket_strider" then npc = SpawnRocketStrider(ply,pos)
        elseif variant == "plasma_strider" then npc = SpawnPlasmaStrider(ply,pos)
        else npc = SpawnEnemyDrone(ply,"npc_cscanner",variant,pos) end
        if IsValid(npc) then missionUnits[#missionUnits+1] = npc end
    end
end

local function cargo(x,z)
    for i=1,7 do
        local side=(i%2==0 and 1 or -1)*(104+i*31)
        local pos=Vector(x+i*77,side,z+i*64)
        local ent,body=D6_Wep.Ordnance("salvage_ballast",pos,nil,
            {mobile=true,mass=22,collectible=true,group=COLLISION_GROUP_NONE})
        if not IsValid(ent) then continue end
        body:SetVelocity(Vector(38-i*3,side>0 and -62 or 57,31+i*8))
        body:AddAngleVelocity(Vector(i*8,22,17))
        missionUnits[#missionUnits+1]=ent
    end
end

local function reset()
    for _, entity in ipairs(missionUnits) do if IsValid(entity) then entity:Remove() end end
    missionUnits = {}
    caption,captionEnd,pendingGuard="",0,nil
    local map=game.GetMap()
    if map == M.City then
        advance(1,"ДИРЕКТИВА 04 · Разогнать протест у станции")
        cue("Сити 17 · Площадь у станции",5)
    elseif map == M.Reactor then
        D6_ReactorBoss.Reset()
        advance(1,"Найти реактор · зарядить корпус")
    end
end

hook.Add("InitPostEntity","D6_EpisodeEntry",reset)
hook.Add("PostCleanupMap","D6_EpisodeReset",reset)
hook.Add("PlayerSpawn","D6_EpisodeSpawn",function(ply)
    if not M.IsEpisode() then return end
    publish(ply)
    if game.GetMap() == M.City then
        timer.Simple(0,function()
            if not IsValid(ply) or not ply:Alive() then return end
            policeRelation(ply,stage>=2)
            for _,class in ipairs({"weapon_physgun","weapon_physcannon","gmod_tool","gmod_camera"}) do ply:StripWeapon(class) end
            if not ply:HasWeapon("weapon_smg1") then ply:Give("weapon_smg1") end
            ply:SetAmmo(90,"SMG1")
        end)
    end
end)

local function track(...)
    for _,ent in ipairs({...}) do if IsValid(ent) then missionUnits[#missionUnits+1]=ent end end
end

local function startGuard(ply)
    if stage>=3 or D6_ReactorBoss.Completed()~=1 then return end
    pendingGuard=nil
    advance(3,"Реакторный зал · последний заслон")
    spawnWave(ply,"guard")
    local pos=marker("d6_charge_2")
    if pos then M.NewCloud(pos,52,35) end
    track(D6_ReactorBoss.Start(2,ply,function(order) advance(3,order) end,function()
        advance(3,"Охрана уничтожена · разрушить реакторное ядро")
        local charge=marker("d6_arc_boss")
        if charge then M.NewCloud(charge,62,44) end
    end))
end

local function startSwarm(ply)
    if stage~=1 then return end
    advance(2,"Гравитационный рой · Пройти в реакторный зал")
    cargo(1550,135)
    spawnWave(ply,"swarm")
    local pos=marker("d6_charge_1")
    if pos then M.NewCloud(pos,45,35) end
    track(D6_ReactorBoss.Start(1,ply,function(order) advance(2,order) end,function()
        advance(2,"Бронедрон уничтожен · в реакторный зал")
        if IsValid(pendingGuard) then startGuard(pendingGuard) end
    end))
end

hook.Add("AcceptInput","D6_EpisodeEvents",function(ent,input,activator)
    if not M.IsEpisode() or input:lower() ~= "trigger" or not IsValid(ent) then return end
    local event = ent:GetName()
    if game.GetMap() == M.City then
        if event=="d6_protest_order" and stage==1 then
            cue("Диспетчер Альянса · Очистить площадь",3.3)
            crowdRuns()
        elseif event=="d6_emp" and stage==1 then
            advance(2,"ЭМИ · Найти технический канал")
            for _,ply in ipairs(player.GetAll()) do policeRelation(ply,true) end
            cue("Связь потеряна · приоритеты изменены",4)
            crowdRuns()
        elseif event=="d6_city_enforcer_sighting" then
            cue("Патруль Альянса · тяжёлый бронедрон",2.8)
        elseif event=="d6_city_arc_sighting" then
            cue("Патруль Альянса · дуговой штурмовик",2.8)
        end
        if event == "d6_city_transfer" and stage < 3 and IsValid(activator) and activator:IsPlayer() then
            advance(3,"Технический канал · Переход в реактор")
            RunConsoleCommand("changelevel", M.Reactor)
        end
        return
    end
    if not IsValid(activator) or not activator:IsPlayer() then activator = player.GetAll()[1] end
    if not IsValid(activator) then return end
    if event == "d6_swarm_enter" and stage == 1 then
        startSwarm(activator)
    elseif event == "d6_guard_enter" and stage <= 2 then
        if stage==1 then startSwarm(activator) end
        if D6_ReactorBoss.Completed()==1 then startGuard(activator)
        else pendingGuard=activator end
    elseif event == "d6_regulator_1_broken" or event == "d6_regulator_2_broken" then
        D6_ReactorBoss.RegulatorBroken(string.sub(event,1,-8))
    elseif event == "d6_core_failure" and stage < 4 then
        advance(4,"РАСПАД · Эвакуационный шлюз",CurTime()+58)
        cargo(4670,88)
        for _, pos in ipairs({Vector(5132,-242,245),Vector(5545,280,535),Vector(5940,-198,286)}) do
            local ent=D6_Wep.Ordnance("mine_air",pos,nil,{mobile=true,mass=15,group=COLLISION_GROUP_PROJECTILE})
            if not IsValid(ent) then continue end
            ent.IsAirMine=true
            ent.NextScan=CurTime()+0.85
            ent:SetNWBool("D6_MineArmed",true)
            missionUnits[#missionUnits+1]=ent
        end
    elseif event == "d6_escape_complete" and stage == 4 then
        advance(5,"ВЫХОД НАЙДЕН · Приоритеты сохранены")
    end
end)

timer.Create("D6_EpisodeDeadline",.25,0,function()
    if game.GetMap() ~= M.Reactor or stage ~= 4 or expires > CurTime() then return end
    advance(6,"ОТСЕК ПОТЕРЯН · d6_episode_restart")
    for _,ply in ipairs(player.GetAll()) do if ply:Alive() then ply:Kill() end end
end)

concommand.Add("d6_episode_restart",function(ply)
    if M.IsEpisode() and (not IsValid(ply) or D6_Session.CanEditWorld(ply)) then game.CleanUpMap() end
end)

hook.Add("OnNPCKilled","D6_CargoAfterKill",function(npc,attacker)
    if not D6_Session.IsArena() or not npc.D6_Variant or not IsValid(attacker) or not attacker:IsPlayer() then return end
    if #ents.FindByClass("d6_energy_cloud") >= 20 then return end
    local strength=math.Clamp(npc:GetMaxHealth()/220,0.62,2.3)
    M.NewCloud(npc:WorldSpaceCenter(),math.floor(18*strength),math.floor(12*strength))
end)
