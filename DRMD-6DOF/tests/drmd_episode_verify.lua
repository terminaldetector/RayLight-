if not SERVER or not (D6_Mission.IsEpisode() or game.GetMap()==D6_Supplies.Vault) then return end
local function check(id,title,okay,detail)
    MsgN(string.format("[DRMD MAP QA] %s | %02d · %s%s",okay and "PASS" or "FAIL",id,title,detail and (" | "..tostring(detail)) or ""))
end
local function named(name) return ents.FindByName(name)[1] end
local function move(ply,pos)
    ply.D6Vel=Vector()
    ply:SetVelocity(-ply:GetVelocity())
    ply:SetPos(pos)
end
local function unit(variant)
    for _, npc in ipairs(D6_Actors.GetAll()) do
        if npc.D6_Variant==variant and npc:Health()>0 then return npc end
    end
end
local function untilTime(label,seconds,predicate,done)
    local expire=CurTime()+seconds
    timer.Create("AbaddonQA"..label,.06,0,function()
        local value=predicate()
        if not value and CurTime()<expire then return end
        timer.Remove("AbaddonQA"..label)
        done(value)
    end)
end

local function city(bot)
    local striders=ents.FindByClass("npc_strider")
    local police=ents.FindByClass("npc_metropolice")
    local combine=#ents.FindByClass("npc_combine_s")+#police
    check(71,"city BSP loads with native ground opponents",#striders==2 and combine>=5 and #ents.FindByClass("npc_helicopter")==1)
    check(72,"city chapter starts grounded with a stock firearm",not bot.D6On and bot:HasWeapon("weapon_smg1")
        and bot:GetNW2Int("D6_EpisodeStage")==1)
    local neutral=IsValid(police[1]) and police[1]:Disposition(bot)==D_NU
    move(bot,Vector(385,0,16))
    timer.Simple(.32,function()
        local order=bot:GetNW2String("D6_EpisodeCaption")=="Диспетчер Альянса · Очистить площадь"
        move(bot,Vector(589,0,20))
        timer.Simple(.35,function()
            check(73,"the real Hammer trigger records the EMP on entering",bot:GetNW2Int("D6_EpisodeStage")==2)
            check(83,"station protest runs before the EMP flips the patrol relationship",#ents.FindByClass("npc_citizen")>=8
                and order and neutral and IsValid(police[1]) and police[1]:Disposition(bot)==D_HT)
            local walked=true
            for i=0,12 do
                local x=2958+i*64
                local tr=util.TraceLine({start=Vector(x,0,100),endpos=Vector(x,0,-600),mask=MASK_SOLID_BRUSHONLY})
                if not tr.HitWorld or math.abs(tr.HitPos.z+math.min(i+1,12)*32)>3 then walked=false end
            end
            check(74,"all stair steps and the sewer floor have BSP collision",walked)
            local gate=named("d6_city_exit")
            check(75,"Hammer exit contains the native landmark and the Sandbox transfer volume",
                IsValid(gate) and gate:GetClass()=="trigger_changelevel" and IsValid(named("d6_drain_link"))
                and IsValid(named("d6_city_transfer_path")) and IsValid(named("d6_city_transfer")))
            local enforcer,arc=named("d6_city_enforcer"),named("d6_city_arc")
            local a=IsValid(enforcer) and enforcer:GetPos()
            local b=IsValid(arc) and arc:GetPos()
            move(bot,Vector(758,0,16))
            timer.Simple(.45,function()
                local first=a and IsValid(enforcer) and enforcer:GetPos():DistToSqr(a)>13^2
                    and enforcer:GetModelScale()>4
                move(bot,Vector(1721,0,16))
                timer.Simple(.45,function()
                    local second=b and IsValid(arc) and arc:GetPos():DistToSqr(b)>13^2 and arc:GetModelScale()>5
                    check(84,"both distinct elite models travel on their Hammer rails along the opening route",
                        first and second,tostring(first).." / "..tostring(second))
                    MsgN("[DRMD MAP QA] COMPLETE CITY")
                    move(bot,Vector(4530,0,-376))
                end)
            end)
        end)
    end)
end

local function escape(bot)
    local core,door=named("d6_reactor_core"),named("d6_escape_door")
    local closed=IsValid(door) and door:GetPos().z or 0
    if IsValid(core) then core:TakeDamage(700,bot,bot) end
    timer.Simple(1.88,function()
        check(79,"lethal core damage activates the native OnBreak collapse relay",
            bot:GetNW2Int("D6_EpisodeStage")==4 and bot:GetNW2Float("D6_EpisodeDeadline") > CurTime()+47)
        check(80,"collapse opens the evacuation door and places live airborne mines",
            IsValid(door) and door:GetPos().z>closed+100 and #ents.FindByClass("d6_ordnance")>=7)
        move(bot,Vector(6310,0,240))
        timer.Simple(.46,function()
            check(81,"reaching the native exit cancels the failure clock",bot:GetNW2Int("D6_EpisodeStage")==5
                and bot:GetNW2Float("D6_EpisodeDeadline")==0)
            MsgN("[DRMD MAP QA] COMPLETE REACTOR")
        end)
    end)
end

local function defeatArc(bot,boss)
    if IsValid(boss) then boss:TakeDamage(4000,bot,bot) end
    timer.Simple(.36,function()
        check(92,"defeating both officers unlocks the core and removes the boss HUD",
            D6_ReactorBoss.Completed()==2 and bot:GetNW2String("D6_BossName")=="")
        escape(bot)
    end)
end

local function overload(bot,boss)
    local exposed=IsValid(boss) and not boss.D6_EncounterShield and bot:GetNW2Int("D6_BossPhase")==2
    check(90,"destroying both regulators disengages the shield",exposed)
    if not exposed then defeatArc(bot,boss); return end
    boss.D6_AI=nil
    boss:GetPhysicsObject():EnableMotion(false)
    boss:SetAngles(Angle(0,180,0))
    move(bot,boss:GetPos()-Vector(510,0,4))
    boss:SetHealth(math.floor(boss:GetMaxHealth()*.38))
    timer.Simple(.25,function()
        local phase=bot:GetNW2Int("D6_BossPhase")==3
        D6_Patterns.ArcElite(boss,bot)
        timer.Simple(1.46,function()
            local rounds=0
            for _,shot in ipairs(ents.FindByClass("d6_projectile")) do
                if shot:GetOwner()==boss and shot:GetNWString("D6_ProjectileArt")=="shot_arcpulse" then rounds=rounds+1 end
            end
            check(91,"overheat fires three staggered rings of actual projectiles with gaps",phase and rounds>=15,rounds)
            defeatArc(bot,boss)
        end)
    end)
end

local function guard(bot)
    move(bot,Vector(3252,0,167))
    timer.Simple(.48,function()
        local count=0
        for _,npc in ipairs(D6_Actors.GetAll()) do
            if npc.D6_Variant=="rocket_strider" or npc.D6_Variant=="plasma_strider" then count=count+1 end
        end
        check(78,"guard section deploys rocket and plasma Striders",bot:GetNW2Int("D6_EpisodeStage")==3 and count==2,count)
        local boss=unit("arc_elite")
        local start=IsValid(boss) and boss:Health()
        if start then boss:TakeDamage(1400,bot,bot) end
        check(88,"the final officer is linked to two regulators and has repair support",
            start and IsValid(boss) and boss:Health()==start and boss.D6_EncounterShield
            and bot:GetNW2Int("D6_BossPhase")==1 and IsValid(unit("support")))
        local regulator=named("d6_regulator_1")
        local weapon=bot:GetWeapon("weapon_d6_mg")
        if IsValid(regulator) and IsValid(weapon) then
            local point=regulator:WorldSpaceCenter()
            local approach=point-Vector(180,0,28)
            for i=1,14 do
                timer.Simple(i*.15,function()
                    if not IsValid(regulator) or not IsValid(weapon) then return end
                    move(bot,approach)
                    local aim=(point-bot:GetShootPos()):Angle()
                    bot:SetEyeAngles(aim)
                    bot.D6AngSynced=aim
                    bot:SetNWFloat("D6_Energy",100)
                    weapon:PrimaryAttack()
                end)
            end
        end
        timer.Simple(2.38,function()
            check(89,"an equipped arena weapon can break a shield regulator through normal fire",
                not IsValid(regulator) or regulator:Health()<=0 or bot:GetNW2String("D6_EpisodeOrder"):find("остался один",1,true),
                IsValid(regulator) and regulator:Health())
            if IsValid(regulator) then regulator:TakeDamage(300,bot,bot) end
            local second=named("d6_regulator_2")
            if IsValid(second) then second:TakeDamage(300,bot,bot) end
            timer.Simple(.3,function() overload(bot,boss) end)
        end)
    end)
end

local function reactor(bot)
    check(76,"reactor BSP runs in 6DOF with native personnel and traps",bot.D6On and #ents.FindByClass("npc_combine_s")>=3
        and #ents.FindByClass("trigger_hurt")>=3 and IsValid(named("d6_reactor_core")))
    local module=named("d6_supply_module_hyperbeam")
    -- The authored BSP marker retains its old name; its reward migrates to BFG.
    local reward=D6_Arsenal.ResolveRewardClass("weapon_d6_hyperbeam")
    local had=bot:HasWeapon("weapon_d6_bfg")
    if IsValid(module) then move(bot,module:GetPos()-Vector(0,0,28)) end
    timer.Simple(.24,function()
        check(96,"the legacy Hyperbeam cache unlocks BFG with one finite starting cell",
            reward=="weapon_d6_bfg" and not had and bot:HasWeapon("weapon_d6_bfg")
            and (bot.D6_EpisodeUnlocks or {}).weapon_d6_bfg and not bot:HasWeapon("weapon_d6_hyperbeam")
            and bot:GetAmmoCount("d6_bfg_cell")==1)
        move(bot,Vector(1130,0,217))
        timer.Simple(.59,function()
            local counts=0
            for _,ent in ipairs(D6_Actors.GetAll()) do
                if ent.D6_Variant=="grav" or ent.D6_Variant=="rpg" then counts=counts+1 end
            end
            check(77,"flight through the entry volume starts the gravity swarm",bot:GetNW2Int("D6_EpisodeStage")==2 and counts>=2)
            local boss,support,core=unit("heavy_elite"),unit("support"),named("d6_reactor_core")
            if IsValid(core) then core:TakeDamage(900,bot,bot) end
            check(85,"the first officer brings repair support and arriving early cannot destroy the core",
                IsValid(boss) and IsValid(support) and IsValid(core) and bot:GetNW2Int("D6_EpisodeStage")==2,
                tostring(boss).." / "..tostring(support).." / "..tostring(core).." / stage "..bot:GetNW2Int("D6_EpisodeStage"))
            if not IsValid(boss) then guard(bot);return end
            boss.D6_Modules.primaryL=nil
            for _,name in ipairs({D6_Actors.Class,"npc_manhack"}) do
                for _,npc in ipairs(ents.FindByClass(name)) do
                    if npc~=boss and npc~=support and npc.D6_Variant then npc:Remove() end
                end
            end
            move(bot,Vector(2280,0,432))
            untilTime("dash",5.9,function()
                return IsValid(boss) and boss.D6_BossBurst
            end,function(burst)
                check(86,"the heavyweight actually dashes along a tilted 6DOF vector",
                    burst and burst.velocity:Length()>1250 and math.abs(burst.velocity.z)>8,
                    burst and tostring(burst.velocity))
                untilTime("quake",7,function()
                    return bot:GetNW2String("D6_EpisodeOrder"):find("Ударная волна",1,true)
                end,function(warning)
                    bot:GodDisable()
                    bot:SetNWFloat("D6_Shield",100)
                    local clear
                    if IsValid(boss) then
                        local origin=boss:GetPos()
                        local centerOffset=bot:WorldSpaceCenter()-bot:GetPos()
                        for _, offset in ipairs({Vector(-306,0,52),Vector(0,-298,52),
                            Vector(0,300,60),Vector(306,0,75),Vector(0,0,291)}) do
                            local point=origin+offset
                            local trace=util.TraceLine({start=origin,endpos=point,mask=MASK_SOLID_BRUSHONLY})
                            if trace.Hit or not util.IsInWorld(point) then continue end
                            clear=point
                            move(bot,point-centerOffset)
                            break
                        end
                    end
                    timer.Simple(1.03,function()
                        check(87,"the warned shock hits a flight target inside its radius",
                            warning and clear and bot:GetNWFloat("D6_Shield",100)<98 and bot:Alive(),bot:GetNWFloat("D6_Shield",100))
                        bot:GodEnable()
                        if IsValid(boss) then boss:TakeDamage(4000,bot,bot) end
                        timer.Simple(.26,function() guard(bot) end)
                    end)
                end)
            end)
        end)
    end)
end

local function vault(bot)
    local marks=ents.FindByName("d6_supply_*")
    local low,high=math.huge,-math.huge
    for _,mark in ipairs(marks) do
        low,high=math.min(low,mark:GetPos().z),math.max(high,mark:GetPos().z)
    end
    local frame=util.TraceLine({start=Vector(1300,0,120),endpos=Vector(1610,0,120),mask=MASK_SOLID_BRUSHONLY})
    check(94,"the vault BSP mounts pickups across distinct elevations and has a real raised entrance frame",
        bot.D6On and high-low>600 and frame.HitWorld)
    local battery=named("d6_supply_battery_1")
    if IsValid(battery) then move(bot,battery:GetPos()-Vector(0,0,28)) end
    bot:SetNWFloat("D6_Energy",21)
    timer.Simple(.37,function()
        local recovered=D6_Energy.Get(bot)>64
        move(bot,Vector(840,36,466))
        local started=D6_Rogue.Start(bot,38271)
        for _,npc in ipairs(D6_Actors.GetAll()) do
            if npc.D6_Variant then npc:Remove() end
        end
        timer.Simple(.44,function()
            check(95,"a live bank recharges the weapons reserve and a seeded vault run stages the next cache",
                recovered and started and IsValid(bot.D6_VaultReserve) and bot:GetNW2String("D6_RogueState")=="draft")
            concommand.Run(bot,"d6_rogue_stop",{},"")
            local ammo=named("d6_supply_ammo_1")
            bot:SetAmmo(0,"d6_shell")
            if IsValid(ammo) then move(bot,ammo:GetPos()-Vector(0,0,28)) end
            timer.Simple(.37,function()
                check(98,"the elevated ammunition cache adds four finite mortar shells",
                    bot:HasWeapon("weapon_d6_heavy") and bot:GetAmmoCount("d6_shell")==4)
                MsgN("[DRMD MAP QA] COMPLETE VAULT")
            end)
        end)
    end)
end

hook.Add("InitPostEntity","DRMDEpisodeQA",function()
    timer.Simple(.8,function()
        local bot=player.CreateNextBot("Abaddon Episode Pilot")
        timer.Simple(1.16,function()
            if not IsValid(bot) then check(100,"episode pilot",false);return end
            bot:GodEnable()
            local map=game.GetMap()
            if map==D6_Mission.City then city(bot)
            elseif map==D6_Mission.Reactor then reactor(bot)
            else vault(bot) end
        end)
    end)
end)
