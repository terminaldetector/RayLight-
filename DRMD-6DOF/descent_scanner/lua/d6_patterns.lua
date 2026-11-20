if not SERVER then return end
D6_Patterns = {}
local P = D6_Patterns
util.AddNetworkString("D6_ArcDischarge")
util.AddNetworkString("D6_RepairLink")

function P.Warn(npc, target, delay, settle)
    npc:SetNWVector("D6_ThreatAim", target)
    npc:SetNWFloat("D6_ThreatAt", CurTime() + delay)
    if settle then
        npc.D6_FireAim=target
        npc.D6_BraceUntil=CurTime()+delay
    end
    npc:EmitSound("ambient/energy/zap_loop1.wav", 68, 123)
end

function P.Launch(npc, from, direction, kind, speed, damage, art, steer, bank, plasma)
    if util.TraceLine({start = npc:GetPos(), endpos = from, filter = npc, mask = MASK_SOLID_BRUSHONLY}).Hit then return end
    local missile = kind == "explosive"
    local dense = art == "shot_ion"
    local ink = plasma and Color(101,202,248) or missile and Color(247,141,89)
        or (art == "shot_arcpulse" and Color(125,219,228) or Color(253,190,109))
    local shot=D6_Wep.FireProjectile({
        owner = npc, pos = from, dir = direction, speed = speed, swept = true,
        art = art, steer = steer, muzzleFX = true, dmgClass = kind,
        physRadius = missile and 6 or (dense and 7 or 3), artScale = dense and 1.38 or 1.12,
        life = missile and 5 or 3, color = ink, inherit = 0, projectileTint=plasma,
        trails = {{col = ink, sw = plasma and 26 or missile and 16 or dense and 21 or 7, ew = 1, life = missile and 0.34 or 0.14}},
        onHit = function(projectile, victim, pos, normal)
            if victim == nil or not IsValid(npc) then return end
            local dtype = D6_Wep.DmgClass(kind).dmgType
            if IsValid(victim) and victim:IsPlayer() and victim:GetNWBool("D6On") then
                D6_Wep.DirectDamage(npc, projectile, victim, damage, dtype, direction*1200)
            end
            if missile or dense then
                if not (IsValid(victim) and victim:IsNPC() and victim.D6_Variant) then
                    for _, ply in ipairs(player.GetAll()) do
                        if ply == victim or not ply:Alive() or not ply:GetNWBool("D6On") then continue end
                        local point = ply:WorldSpaceCenter()
                        local dist = point:Distance(pos)
                        if dist > 110 then continue end
                        local tr = util.TraceLine({start = pos + normal*3, endpos = point, filter = {npc,projectile,ply}, mask = MASK_SOLID_BRUSHONLY})
                        if not tr.Hit then D6_Wep.DirectDamage(npc,projectile,ply,damage*(1-dist/110)*0.62,dtype) end
                    end
                end
                local fx = EffectData(); fx:SetOrigin(pos + normal*3); fx:SetScale(dense and 1.5 or 0.63)
                util.Effect((dense or plasma) and "cball_explode" or "Explosion", fx)
            end
        end,
    })
    if IsValid(shot) then D6_Drones.Fired(npc,bank) end
    return shot
end

function P.AimVolley(npc, target, index, kind, speed, damage, art, spread, steer)
    local from = D6_Drones.Muzzle(npc, index)
    local point = target:WorldSpaceCenter()
    local flight = math.Clamp(point:Distance(from)/speed, 0.03, 0.64)
    point = point + target:GetVelocity()*flight*0.55
    local blocked = util.TraceLine({start = from, endpos = point, filter = {target,npc}, mask = MASK_SHOT})
    if blocked.Hit then return end
    local axis = (point-from):Angle()
    local aim = (axis:Forward()+axis:Right()*(spread or 0)):GetNormalized()
    local bank=D6_Drones.PortBank(npc,index) or D6_Drones.PortBank(npc,1)
    return P.Launch(npc,from,aim,kind,speed,damage,art,steer,bank)
end

function P.Repair(npc, ally, slot, amount)
    local source=D6_Drones.Muzzle(npc,slot,npc:WorldSpaceCenter())
    local target=ally:WorldSpaceCenter()
    if util.TraceLine({start=source,endpos=target,filter={npc,ally},mask=MASK_SHOT}).Hit then return false end
    ally:SetHealth(math.min(ally:Health()+amount,ally:GetMaxHealth()))
    net.Start("D6_RepairLink",true)
    net.WriteVector(source)
    net.WriteVector(target)
    net.SendPVS(source)
    D6_Drones.Fired(npc,D6_Drones.PortBank(npc,slot))
    return true
end

function P.HomeTowards(target, strength)
    return function(_, position, velocity, dt)
        if not IsValid(target) or target:Health() <= 0 then return velocity end
        local to = target:WorldSpaceCenter()+target:GetVelocity()*0.13-position
        if to:LengthSqr() < 8^2 then return velocity end
        return LerpVector(math.min(dt*strength, 1),velocity:GetNormalized(),to:GetNormalized()):GetNormalized()*velocity:Length()
    end
end

function P.Enforcer(npc, target)
    local aim = target:WorldSpaceCenter() + target:GetVelocity()*0.10
    local center = npc:GetPos()
    if util.TraceLine({start = center, endpos = aim, filter = {npc, target}, mask = MASK_SOLID_BRUSHONLY}).Hit then return end
    local volley = (npc.D6_EnforcerVolley or 0) + 1
    npc.D6_EnforcerVolley = volley
    local rockets = volley % 2 == 0
    local overheat=npc.D6_ReactorOvercharge
    local lock = overheat and .54 or (rockets and 0.82 or 0.52)
    P.Warn(npc, aim, lock,true)
    for wave = 1, rockets and 3 or 4 do
        timer.Simple(lock + (wave - 1)*(rockets and 0.18 or 0.115), function()
            if not IsValid(npc) or npc:Health() <= 0 then return end
            if wave==1 then npc:StopSound("ambient/energy/zap_loop1.wav") end
            local angles=npc:GetAngles()
            local right,up=angles:Right(),angles:Up()
            for side = -1, 1, 2 do
                local x, y, z = 29.2, 24.2+(wave%2 == 0 and 2.51 or -2.51), 0.4
                if rockets then x, y, z = 14.8, 14.45+(wave-2)*4.15, 22.15 end
                local port=side<0 and "left" or "right"
                local bank=rockets and ("rockets_"..port) or port
                local muzzle=D6_Drones.Socket(npc,{x,-side*y,z},bank)
                local ray = (aim - muzzle):GetNormalized()
                local height=overheat and .092 or .043
                local direction = (ray + right*(side*0.082) + up*(wave-2)*height):GetNormalized()
                local art=rockets and "shot_mega" or "shot_kinetic"
                P.Launch(npc,muzzle,direction,rockets and "explosive" or "kinetic",rockets and 1040 or 1260,
                    rockets and 32 or 16,art,nil,bank)
            end
            npc:EmitSound(rockets and "weapons/rpg/rocketfire1.wav" or "weapons/ar2/ar2_fire1.wav", 83, rockets and 91 or 84)
        end)
    end
end

local function discharge(npc, slot, aim, optic)
    local origin=D6_Drones.Muzzle(npc,slot)
    local dir=(aim-origin):GetNormalized()
    if util.TraceLine({start=npc:GetPos(),endpos=origin,filter=npc,mask=MASK_SOLID_BRUSHONLY}).Hit then return end
    local radius=optic and 13 or 8
    local width=Vector(radius,radius,radius)
    local trace=D6_Wep.CombatTrace({start=origin,endpos=origin+dir*1760,mins=-width,maxs=width,filter=npc,mask=MASK_SHOT})
    if IsValid(trace.Entity) and trace.Entity:IsPlayer() and trace.Entity:GetNWBool("D6On") then
        D6_Wep.DirectDamage(npc,npc,trace.Entity,optic and 57 or 22,DMG_ENERGYBEAM,dir*900)
    end
    net.Start("D6_ArcDischarge",true)
    net.WriteVector(origin)
    net.WriteVector(trace.HitPos)
    net.WriteBool(trace.Hit)
    net.WriteBool(optic==true)
    net.SendPAS((origin+trace.HitPos)*.5)
    D6_Drones.Fired(npc,D6_Drones.PortBank(npc,slot))
    return trace
end

local function armamentPhase(npc,target,mode)
    local aim=target:WorldSpaceCenter()+target:GetVelocity()*.1
    local sight=util.TraceLine({start=npc:GetPos(),endpos=aim,filter={npc,target},mask=MASK_SOLID_BRUSHONLY})
    if sight.Hit then return end
    local delay=mode==4 and .95 or .68
    npc:SetNW2Int("D6_ArcMode",mode)
    npc:SetNWBool("D6_ArcThermal",mode==5)
    if mode==4 then npc:SetNW2Float("D6_EyeCharge",CurTime()) end
    if mode==5 then D6_Drones.Spin(npc,1.3) end
    P.Warn(npc,aim,delay,true)
    timer.Simple(delay,function()
        if not IsValid(npc) or npc:Health()<=0 then return end
        npc:StopSound("ambient/energy/zap_loop1.wav")
        if mode==4 then
            discharge(npc,4,aim,true)
            npc:EmitSound("ambient/energy/zap9.wav",94,75)
        elseif mode==3 then
            local homing=IsValid(target) and P.HomeTowards(target,.86) or nil
            for slot=5,6 do
                local port=D6_Drones.Muzzle(npc,slot)
                local direction=(aim-port+npc:GetRight()*((slot-5.5)*67)):GetNormalized()
                P.Launch(npc,port,direction,"explosive",890,34,"shot_mega",homing,"rack",true)
            end
            for slot=1,2 do
                local port=D6_Drones.Muzzle(npc,slot)
                P.Launch(npc,port,(aim-port):GetNormalized(),"energy",1220,14,"shot_arcpulse",nil,D6_Drones.PortBank(npc,slot))
            end
            npc:EmitSound("weapons/rpg/rocketfire1.wav",89,78)
        else
            local rail=D6_Drones.Muzzle(npc,3)
            P.Launch(npc,rail,(aim-rail):GetNormalized(),"kinetic",3350,46,"shot_kinetic",nil,"thermal")
            npc:EmitSound("weapons/gauss/fire1.wav",88,85)
            for pulse=1,4 do
                timer.Simple((pulse-1)*.085,function()
                    if not IsValid(npc) or npc:Health()<=0 then return end
                    for slot=7,8 do
                        local port=D6_Drones.Muzzle(npc,slot)
                        local aimPoint=aim+npc:GetUp()*((pulse-2)*27)
                        P.Launch(npc,port,(aimPoint-port):GetNormalized(),"kinetic",1820,10,"shot_kinetic",nil,
                            slot==7 and "left" or "right")
                    end
                    npc:EmitSound("weapons/ar2/ar2_fire1.wav",79,92+pulse*3)
                end)
            end
        end
    end)
    return true
end

local function arcadeWaves(npc,target)
    local aim=target:WorldSpaceCenter()+target:GetVelocity()*.115
    if util.TraceLine({start=npc:GetPos(),endpos=aim,filter={npc,target},mask=MASK_SOLID_BRUSHONLY}).Hit then return end
    local cycle=(npc.D6_ArcWave or 0)+1
    npc.D6_ArcWave=cycle
    npc:SetNW2Int("D6_ArcMode",6)
    npc:SetNWBool("D6_ArcThermal",false)
    P.Warn(npc,aim,.76,true)
    for wave=1,3 do
        timer.Simple(.76+(wave-1)*.26,function()
            if not IsValid(npc) or npc:Health()<=0 then return end
            if wave==1 then npc:StopSound("ambient/energy/zap_loop1.wav") end
            local slot=1+(wave%2)
            local origin=D6_Drones.Muzzle(npc,slot)
            local axis=(aim-origin):Angle()
            local forward,right,up=axis:Forward(),axis:Right(),axis:Up()
            local bank=D6_Drones.PortBank(npc,slot)
            local damage=D6_Balance.Reactor.arc_elite.wave
            if cycle%2==1 then
                local gap=(cycle+wave*2)%14
                for i=0,13 do
                    if (i-gap)%14<3 then continue end
                    local theta=(i+wave*.33)*math.pi/7
                    local radius=.24+(wave-1)*.07
                    local jet=(forward+right*math.cos(theta)*radius+up*math.sin(theta)*radius):GetNormalized()
                    P.Launch(npc,origin,jet,"energy",680+wave*62,damage,"shot_arcpulse",nil,bank)
                end
            else
                local safe=(wave+cycle)%5-2
                for j=-3,3 do
                    if math.abs(j-safe)<=1 then continue end
                    for row=-1,1 do
                        local jet=(forward+right*(j*.11)+up*(row*.17+(wave-2)*.055)):GetNormalized()
                        P.Launch(npc,origin,jet,"energy",784+wave*34,damage,"shot_energy",nil,bank)
                    end
                end
            end
            npc:EmitSound("ambient/energy/zap7.wav",84,83+wave*8)
        end)
    end
    return true
end

function P.ArcElite(npc,target)
    if npc.D6_ReactorOvercharge then
        npc.D6_OverheatAttacks=(npc.D6_OverheatAttacks or 0)+1
        if npc.D6_OverheatAttacks%4==0 then return armamentPhase(npc,target,4) end
        return arcadeWaves(npc,target)
    end
    local aim=target:WorldSpaceCenter()+target:GetVelocity()*.065
    local sight=util.TraceLine({start=npc:GetPos(),endpos=aim,filter={npc,target},mask=MASK_SOLID_BRUSHONLY})
    if sight.Hit then return end
    local mode=(npc.D6_ArcAttack or 0)%5+1
    npc.D6_ArcAttack=mode
    if mode>2 then return armamentPhase(npc,target,mode) end
    local thermal=mode==1
    npc.D6_ArcThermal=thermal
    npc:SetNWBool("D6_ArcThermal",thermal)
    npc:SetNW2Int("D6_ArcMode",mode)
    local windup=thermal and .98 or .74
    P.Warn(npc,aim,windup,true)
    timer.Simple(windup,function()
        if not IsValid(npc) or npc:Health()<=0 then return end
        npc:StopSound("ambient/energy/zap_loop1.wav")
        if thermal then
            local origin=D6_Drones.Muzzle(npc,3)
            local axis=(aim-origin):Angle()
            for i=0,5 do
                if i==2 then continue end
                local phi=i*math.pi/3
                local direction=(axis:Forward()+axis:Right()*math.cos(phi)*.20+axis:Up()*math.sin(phi)*.20):GetNormalized()
                P.Launch(npc,origin,direction,"energy",700,22,"shot_ion")
            end
            D6_Drones.Fired(npc,"thermal")
            npc:EmitSound("ambient/energy/weld2.wav",84,88)
        else
            discharge(npc,1,aim)
            discharge(npc,2,aim)
            npc:EmitSound("ambient/energy/zap7.wav",86,88)
        end
    end)
    return true
end

function P.RocketStrider(npc, player, distance)
    if distance < 245 or distance > 2400 then return end
    local origin = npc:GetPos()
    local aim = player:WorldSpaceCenter() + player:GetVelocity()*0.10
    local sight = util.TraceLine({start = origin, endpos = aim, filter = {npc, player}, mask = MASK_SOLID_BRUSHONLY})
    if sight.Hit then return end

    local phase = (npc.D6_PatternIndex or 0) % 3 + 1
    npc.D6_PatternIndex = phase
    npc.D6_NextRocket = CurTime() + ({4.6, 5.3, 4.5})[phase]
    local windup = 0.72
    P.Warn(npc, aim, windup)
    local count = phase == 2 and 3 or 2
    for wave = 1, count do
        timer.Simple(windup + (wave-1)*0.25, function()
            if not IsValid(npc) or npc:Health() <= 0 then return end
            local pos = npc:GetPos()
            local axes = (aim - pos):Angle()
            local fwd, right, up = axes:Forward(), axes:Right(), axes:Up()
            if phase == 1 then
                for i = -4, 4 do
                    if i == (wave == 1 and -1 or 2) then continue end
                    local spread = (fwd + right*i*0.074 + up*(wave-1.5)*0.13):GetNormalized()
                    P.Launch(npc, pos + fwd*32, spread, "energy", 665, 13)
                end
            elseif phase == 2 then
                for i = 0, 7 do
                    if i == (wave + 1) % 8 or i == (wave + 2) % 8 then continue end
                    local theta = i*math.pi/4 + wave*math.pi/11
                    local spread = (fwd + right*math.cos(theta)*0.19 + up*math.sin(theta)*0.19):GetNormalized()
                    P.Launch(npc, pos + fwd*36, spread, "energy", 590 + wave*100, 16)
                end
            else
                for i = -1, 1 do
                    local muzzle = pos + fwd*30 + right*i*36
                    local spread = (fwd + right*i*0.16 + up*(wave-1.5)*0.15):GetNormalized()
                    P.Launch(npc, muzzle, spread, "explosive", 1020, 34)
                end
            end
            npc:EmitSound(phase == 3 and "weapons/rpg/rocketfire1.wav" or "ambient/energy/zap9.wav", 79, 84 + wave*9)
        end)
    end
end
