if not SERVER then return end

D6_ReactorBoss={}
local R=D6_ReactorBoss
local active,completed=nil,0
local regulators={}
local profiles={
    {variant="heavy_elite", mark="d6_enforcer_boss", support="d6_enforcer_support", name="Бронедрон Альянса"},
    {variant="arc_elite", mark="d6_arc_boss", support="d6_arc_support", name="Дуговой штурмовик"},
}
util.AddNetworkString("D6_BossField")

local function named(name)
    return ents.FindByName(name)[1]
end

local function tell(label)
    if active and active.status then active.status(label) end
end

local function sync()
    local boss=active and active.boss
    for _,ply in ipairs(player.GetAll()) do
        ply:SetNW2String("D6_BossName",IsValid(boss) and profiles[active.id].name or "")
        ply:SetNW2Int("D6_BossPhase",IsValid(boss) and active.phase or 0)
        ply:SetNW2Float("D6_BossIntegrity",IsValid(boss) and math.Clamp(boss:Health()/math.max(1,boss:GetMaxHealth()),0,1) or 0)
    end
end

function R.Reset()
    active,completed,regulators=nil,0,{}
    for _,name in ipairs({"d6_reactor_core","d6_regulator_1","d6_regulator_2"}) do
        local ent=named(name)
        if IsValid(ent) then
            ent.D6_EpisodeTarget=true
            if name~="d6_reactor_core" then regulators[name]=true end
        end
    end
    sync()
end

function R.Completed() return completed end

function R.Start(id,ply,status,onDefeat)
    if active or completed~=id-1 then return end
    local profile=profiles[id]
    local mark=named(profile.mark)
    local boss
    if IsValid(mark) then
        for _, offset in ipairs({Vector(0,0,0),Vector(-142,-200,105),Vector(0,210,240)}) do
            boss=SpawnD6Role(profile.variant,mark:GetPos()+offset,ply)
            if IsValid(boss) then break end
        end
    end
    if not IsValid(boss) then
        completed=id
        onDefeat()
        return
    end
    local support=named(profile.support)
    local escort=IsValid(support) and SpawnD6Role("support",support:GetPos(),ply) or nil
    local locked=id==2 and next(regulators)~=nil
    local stats=D6_Balance.Reactor[profile.variant]
    boss:SetMaxHealth(stats.hull)
    boss:SetHealth(stats.hull)
    boss.D6_Shield,boss.D6_ShieldMax=stats.shield,stats.shield
    boss.D6_Armor,boss.D6_ArmorMax=stats.armor,stats.armor
    active={id=id,boss=boss,escort=escort,phase=locked and 1 or 2,nextMove=CurTime()+2.8,
        attack=0,status=status,onDefeat=onDefeat}
    boss.D6_EncounterShield=locked
    boss:SetNW2Bool("D6_EncounterShield",locked)
    if id==1 then tell("Бронедрон · уничтожить ремонтное прикрытие")
    elseif locked then tell("Штурмовик · разбить два регулятора его щита")
    else tell("Дуговой штурмовик · щит снят") end
    sync()
    return boss,escort
end

function R.RegulatorBroken(name)
    if not regulators[name] then return end
    regulators[name]=nil
    if not active or active.id~=2 or active.phase~=1 or not IsValid(active.boss) then return end
    if next(regulators) then tell("Щит штурмовика · остался один регулятор");return end
    local boss=active.boss
    boss.D6_EncounterShield=nil
    boss:SetNW2Bool("D6_EncounterShield",false)
    active.phase=2
    tell("Щит отключён · атаковать штурмовик")
    sync()
end

local function playerFor(boss)
    local nearest, distance
    for _,ply in ipairs(player.GetAll()) do
        if not ply:Alive() or not ply.D6On then continue end
        local d=ply:GetPos():DistToSqr(boss:GetPos())
        if not distance or d<distance then nearest,distance=ply,d end
    end
    return nearest,distance
end

local function quake(record)
    local boss=record.boss
    local origin=boss:GetPos()
    local delay,radius=.86,430
    D6_Patterns.Warn(boss,origin+boss:GetForward()*110,delay,true)
    net.Start("D6_BossField")
    net.WriteVector(origin)
    net.WriteFloat(radius)
    net.WriteFloat(delay)
    net.SendPVS(origin)
    tell("Ударная волна · покинуть радиус")
    timer.Simple(delay,function()
        if active~=record or not IsValid(boss) or boss:Health()<=0 then return end
        local center=origin
        boss:StopSound("ambient/energy/zap_loop1.wav")
        util.ScreenShake(center,7,120,.5,radius)
        boss:EmitSound("ambient/machines/thumper_dust.wav",93,83)
        for _,ply in ipairs(player.GetAll()) do
            if not ply:Alive() or not ply.D6On then continue end
            local offset=ply:WorldSpaceCenter()-center
            local distance=offset:Length()
            if distance>=radius then continue end
            local line=util.TraceLine({start=center,endpos=ply:WorldSpaceCenter(),mask=MASK_SOLID_BRUSHONLY})
            if line.Hit then continue end
            local strength=1-distance/radius
            local damage=D6_Balance.Reactor.heavy_elite.quake
            D6_Wep.DirectDamage(boss,boss,ply,9+damage*strength,DMG_BLAST,offset:GetNormalized()*6200*strength)
            ply.D6Vel=(ply.D6Vel or vector_origin)+offset:GetNormalized()*(360+630*strength)
        end
        tell("Бронедрон · восстановление после импульса")
    end)
end

local function dash(record,ply)
    local boss=record.boss
    local origin=boss:GetPos()
    local to=ply:WorldSpaceCenter()-origin
    local axes=to:Angle()
    local side=record.attack%4==0 and -1 or 1
    local wanted=origin+to:GetNormalized()*math.Clamp(to:Length()-270,180,580)+axes:Up()*125+axes:Right()*side*138
    local hull=D6_Session.Enforcer
    local tr=util.TraceHull({start=origin,endpos=wanted,mins=Vector(-hull.radius,-hull.radius,-hull.below),
        maxs=Vector(hull.radius,hull.radius,hull.above),mask=MASK_NPCSOLID_BRUSHONLY})
    if tr.Fraction<.32 then quake(record);return end
    local dest=tr.Hit and tr.HitPos+tr.HitNormal*13 or wanted
    D6_Patterns.Warn(boss,dest,.52,true)
    tell("Таран · сместиться с направления рывка")
    timer.Simple(.52,function()
        if active~=record or not IsValid(boss) or boss:Health()<=0 then return end
        boss:StopSound("ambient/energy/zap_loop1.wav")
        boss:EmitSound("ambient/machines/teleport3.wav",83,85)
        boss.D6_BossBurst={velocity=(dest-boss:GetPos()):GetNormalized()*1335,expires=CurTime()+.39,hit={}}
        tell("Бронедрон · огонь по боковой броне")
    end)
end

function R.Ram(boss,burst,dt)
    local start=boss:GetPos()
    local finish=start+burst.velocity*dt
    for _,ply in ipairs(player.GetAll()) do
        if burst.hit[ply] or not ply:Alive() or not ply.D6On then continue end
        local point=ply:WorldSpaceCenter()
        if util.DistanceToLine(start,finish,point)>88 then continue end
        if util.TraceLine({start=start,endpos=point,mask=MASK_SOLID_BRUSHONLY}).Hit then continue end
        burst.hit[ply]=true
        D6_Wep.DirectDamage(boss,boss,ply,D6_Balance.Reactor.heavy_elite.ram,DMG_CRUSH,burst.velocity*4)
    end
end

local function defeated(boss)
    if not active or active.boss~=boss then return end
    local record=active
    active=nil
    completed=record.id
    sync()
    record.onDefeat()
end

hook.Add("OnNPCKilled","D6_ReactorBossDefeated",defeated)
hook.Add("EntityTakeDamage","D6_CoreLock",function(target,damage)
    if game.GetMap()==D6_Mission.Reactor and target.D6_EpisodeTarget and target:GetName()=="d6_reactor_core" then
        damage:SetDamage(0)
        return true
    end
end)

timer.Create("D6_ReactorBossUpdate",.15,0,function()
    local record=active
    if not record then return end
    local boss=record.boss
    if not IsValid(boss) or boss:Health()<=0 then defeated(boss);return end
    if record.id==2 and record.phase==2 and boss:Health()<=boss:GetMaxHealth()*.42 then
        record.phase=3
        boss.D6_ReactorOvercharge=true
        boss:SetNW2Bool("D6_ReactorOvercharge",true)
        local module=boss.D6_Modules and boss.D6_Modules.primaryL
        if module then module.lastFire=CurTime()-3.6 end
        tell("ПЕРЕГРЕВ · проходить через разрывы в залпах")
    end
    sync()
    if record.id~=1 or CurTime()<record.nextMove or (boss.D6_BraceUntil or 0)>CurTime() then return end
    local ply,distance=playerFor(boss)
    if not IsValid(ply) or distance>1650^2 then return end
    record.attack=record.attack+1
    record.nextMove=CurTime()+4.8
    if record.attack%2==1 then dash(record,ply) else quake(record) end
end)
