if not SERVER or game.GetMap()~="gm_flatgrass" then return end

local function check(name, pass, detail)
    MsgN(string.format("[DRMD QA] %s | %s%s", pass and "PASS" or "FAIL", name, detail and (" | " .. tostring(detail)) or ""))
end
local function near(n, expected, tolerance) return math.abs(n - expected) <= tolerance end

local function verifyMobility(bot, ground, done)
    local M = D6_Mobility
    local origin = ground + Vector(0, -720, 500)
    local aim = Angle(0, 0, 84)
    bot:SetPos(origin)
    M.Reset(bot)
    bot:SetNWFloat("D6_Energy", 100)
    bot.D6AngSynced = aim
    bot.D6Vel = Vector(390, 0, 0)
    local started = M.StartDash(bot, Vector(0,0,1))
    check("36 · rolled dash follows local up and keeps a tangential impulse", started
        and bot.D6DashDir:Dot(aim:Up()) > 0.999 and bot.D6Vel:Dot(aim:Forward()) > 380)
    timer.Simple(0.29, function()
        local coast = bot.D6Vel:Length()
        check("37 · movement retains boosted speed beyond the dash window",
            not bot.D6DashOn and coast > 2200 and bot:GetPos():Distance(origin) > 350,
            math.Round(coast) .. " u/s")
        local input = IN_WALK
        hook.Add("StartCommand", "DRMDQAMobility", function(ply, cmd)
            if ply == bot then cmd:SetButtons(input) end
        end)
        timer.Simple(0.19, function()
            check("38 · airbrake reduces speed through ordinary game movement",
                bot:GetNWBool("D6_AirBrake") and bot.D6Vel:Length() < coast*0.65,
                math.Round(bot.D6Vel:Length()) .. " u/s")
            input = IN_USE
            bot:SetPos(origin)
            bot:SetEyeAngles(Angle(77, 0, 12))
            bot.D6AngSynced = Angle(77, 0, 12)
            bot.D6Vel = Vector(0, 470, 0)
            timer.Simple(0.21, function()
                local anchor = bot.D6_Adhesion
                check("39 · use attaches to a brush and keeps lateral momentum", anchor ~= nil
                    and not anchor.entity and bot:GetNW2Int("D6_AdhesionEntity", -1) == 0
                    and bot.D6Vel.y > 220 and bot.D6Vel.z < -290,
                    string.format("Y %.0f · Z %.0f", bot.D6Vel.y, bot.D6Vel.z))
                input = 0
                timer.Simple(0.09, function()
                    check("40 · releasing use clears the field and carries flight momentum",
                        not bot.D6_Adhesion and bot:GetNW2Int("D6_AdhesionEntity", -1) == -1
                        and bot.D6Vel:Length() > 450)
                    bot:SetPos(origin)
                    bot:SetEyeAngles(Angle())
                    bot.D6AngSynced, bot.D6Vel = Angle(), Vector()
                    local eye = D6_Arsenal.ScannerEye(bot, Angle())
                    local prop = ents.Create("prop_physics")
                    prop:SetModel("models/hunter/misc/sphere025x025.mdl")
                    prop:SetPos(eye + Vector(205,0,0))
                    prop:Spawn()
                    local phys = prop:GetPhysicsObject()
                    phys:EnableGravity(false)
                    local locked = M.Attach(bot, "test", true)
                    timer.Simple(0.22, function()
                        local propSpeed = phys:GetVelocity().x
                        check("41 · a free VPhysics anchor exchanges momentum with the scanner",
                            locked and bot.D6_Adhesion and bot.D6_Adhesion.entity == prop
                            and bot.D6Vel.x > 7 and propSpeed < -20 and not phys:IsGravityEnabled(),
                            string.format("ship %.0f · prop %.0f", bot.D6Vel.x, propSpeed))
                        prop:Remove()
                        timer.Simple(0.1, function()
                            check("42 · deleting an anchor automatically releases adhesion", not bot.D6_Adhesion)
                            hook.Remove("StartCommand", "DRMDQAMobility")
                            done()
                        end)
                    end)
                end)
            end)
        end)
    end)
end

local function verifyHyper(bot, ground, done)
    -- Retained legacy SWEP regression only; this is not part of either loadout.
    local beam = bot:Give("weapon_d6_hyperbeam", true)
    if not IsValid(beam) then check("43 · legacy Hyperbeam fixture available", false); done(); return end
    bot:SetMoveType(MOVETYPE_NONE)
    bot:SetPos(ground + Vector(0,-530,400))
    bot:SetEyeAngles(Angle(0,0,34))
    bot.D6AngSynced, bot.D6Vel = Angle(0,0,34), Vector()
    bot:SetNWFloat("D6_Energy", 100)
    local start = D6_Arsenal.ScannerEye(bot, bot.D6AngSynced)
    local function target(offset)
        local npc = ents.Create("npc_cscanner")
        local position = start + Vector(offset, 0, 0)
        npc:SetPos(position)
        npc:Spawn()
        npc:SetMoveType(MOVETYPE_NONE)
        local physics = npc:GetPhysicsObject()
        if IsValid(physics) then physics:EnableMotion(false) end
        npc:SetPos(position + npc:GetPos() - npc:WorldSpaceCenter())
        npc:SetMaxHealth(360)
        npc:SetHealth(360)
        return npc
    end
    local first, second = target(220), target(380)
    bot:SelectWeapon(beam:GetClass())
    timer.Simple(0.14, function()
        local input = IN_ATTACK
        hook.Add("StartCommand", "DRMDQAOptics", function(ply, cmd)
            if ply == bot then cmd:SetButtons(input) end
        end)
        timer.Simple(0.72, function()
            check("43 · Hyperbeam charges from the normal attack action",
                bot:GetActiveWeapon() == beam and beam:GetNWFloat("D6_HyperCharge") >= 0.90)
            input = 0
            local releaseEye = D6_Arsenal.ScannerEye(bot, D6_Wep.AimAng(bot))
            timer.Simple(0.19, function()
                check("44 · fired segment starts at the model lens under roll",
                    beam:GetNWBool("D6_HyperFiring")
                    and beam:GetNWVector("D6_ShotOrigin"):Distance(releaseEye) < 15
                    and bot:GetNWFloat("D6_Energy") < 70)
                timer.Simple(0.52, function()
                    check("45 · a released optical burst damages both targets and cools down",
                        not beam:GetNWBool("D6_HyperFiring") and first:Health() < 285 and second:Health() < 300
                        and beam:GetNextPrimaryFire() > CurTime(), first:Health() .. " / " .. second:Health())
                    local position = D6_Arsenal.ScannerEye(bot, bot.D6AngSynced)
                    local wall = ents.Create("prop_physics")
                    wall:SetModel("models/hunter/misc/sphere025x025.mdl")
                    wall:SetPos(position + Vector(80,0,0))
                    wall:Spawn()
                    wall:GetPhysicsObject():EnableMotion(false)
                    local health = first:Health()
                    local src, impact = beam:TracePulse(bot)
                    check("46 · solid geometry occludes targets behind the optical beam",
                        impact:Distance(src) < 100 and first:Health() == health)
                    wall:Remove()
                    first:Remove()
                    second:Remove()
                    hook.Remove("StartCommand", "DRMDQAOptics")
                    bot:StripWeapon("weapon_d6_hyperbeam")
                    done()
                end)
            end)
        end)
    end)
end

local function removeTestDrones()
    for _,ent in ipairs(D6_Actors.GetAll()) do if ent.D6_Variant then ent:Remove() end end
end

local function verifyRogue(bot,ground,done)
    -- The earlier mechanics fixtures explicitly requested all curated modules.
    -- Return this fresh QA bot to the five starters before either seeded run.
    -- Do not erase EpisodeUnlocks: that would hide progression persistence bugs.
    local initialInventory = {}
    local starterCount = 0
    for _, item in ipairs(D6_Arsenal.Order) do
        if not D6_Arsenal.Starting[item.class] then bot:StripWeapon(item.class) end
        if bot:HasWeapon(item.class) then starterCount=starterCount+1 end
    end
    for _, item in ipairs(D6_Arsenal.LegacyOrder) do
        initialInventory[item.class] = bot:HasWeapon(item.class)
    end
    D6_Arsenal.EnsureOwned(bot)
    bot:SelectWeapon(D6_Arsenal.Defaults[1])
    bot:SetMoveType(MOVETYPE_WALK)
    bot:SetPos(ground+Vector(0,-1230,220))
    bot:SetMaxHealth(100)
    bot:SetHealth(100)
    local start=D6_Rogue.Start(bot,38271)
    check("61 · seeded roguelike starts actual enemies and excludes a concurrent trial",start
        and starterCount==5 and bot:GetNW2Int("D6_RogueWave")==1
        and bot:GetNW2Int("D6_RogueSeed")==38271 and not D6_Trial.Start(bot))
    removeTestDrones()
    timer.Simple(.45,function()
        local cards, firstDeck={},{}
        for i=1,3 do
            firstDeck[i]=bot:GetNW2String("D6_RogueCard"..i,"")
            cards[firstDeck[i]]=true
        end
        local module = D6_Rogue.Upgrades[firstDeck[1]]
        local second, third = D6_Rogue.Upgrades[firstDeck[2]], D6_Rogue.Upgrades[firstDeck[3]]
        check("62 · a wave offers one eligible new module and two distinct nonweapon upgrades",
            bot:GetNW2String("D6_RogueState")=="draft" and not cards[""] and table.Count(cards)==3
            and module and module.weapon and table.HasValue(D6_Rogue.ModuleOffers(bot,1),module.weapon)
            and second and not second.weapon and third and not third.weapon)
        local picked=D6_Rogue.Pick(bot,1)
        check("63 · choosing the temporary module grants it and starts exactly one next wave",picked
            and module and module.weapon and bot:HasWeapon(module.weapon)
            and not (bot.D6_EpisodeUnlocks or {})[module.weapon]
            and not D6_Rogue.Pick(bot,2) and bot:GetNW2Int("D6_RogueWave")==2)
        bot:KillSilent()
        timer.Simple(.37,function()
            check("64 · death clears the run and restores the baseline integrity",not D6_Rogue.IsActive(bot)
                and bot:GetNW2String("D6_RogueState")=="lost" and bot:GetMaxHealth()==100)
            bot:Spawn()
            timer.Simple(.55,function()
                bot:GodEnable()
                bot:SetPos(ground+Vector(0,-1230,220))
                bot.D6Vel=Vector()
                local sameInventory=true
                for class, owned in pairs(initialInventory) do
                    if bot:HasWeapon(class)~=owned then sameInventory=false end
                end
                local same=D6_Rogue.Start(bot,38271) and sameInventory
                local n=1
                local eliteSeen=false
                local function clearWave()
                    if n==4 then
                        for _,ent in ipairs(D6_Actors.GetAll()) do
                            if ent.D6_Variant=="arc_elite" then eliteSeen=true end
                        end
                    end
                    removeTestDrones()
                    timer.Simple(.39,function()
                        if n==1 then
                            for i,key in ipairs(firstDeck) do same=same and bot:GetNW2String("D6_RogueCard"..i)==key end
                        end
                        if n==5 or not D6_Rogue.Pick(bot,1) then
                            check("68 · the same inventory and seed repeat the draft and five waves finish with the new elite",same and eliteSeen
                                and n==5 and bot:GetNW2String("D6_RogueState")=="won" and not D6_Rogue.IsActive(bot),n)
                            done()
                            return
                        end
                        n=n+1
                        clearWave()
                    end)
                end
                clearWave()
            end)
        end)
    end)
end

local function verifyArcArsenal(bot,elite,done)
    D6_Patterns.ArcElite(elite,bot)
    timer.Simple(.82,function()
        local rockets=0
        for _,shot in ipairs(ents.FindByClass("d6_projectile")) do
            if shot:GetOwner()~=elite then continue end
            if shot:GetNWString("D6_ProjectileArt")=="shot_mega" and shot:GetNW2Bool("D6_ProjectileTint") then rockets=rockets+1 end
            shot:Remove()
        end
        check("99 · the upper rack launches a pair of blue plasma rockets",rockets==2,rockets)
        bot:GodDisable()
        bot:SetNWFloat("D6_Shield",100)
        D6_Patterns.ArcElite(elite,bot)
        local eyeCharge=elite:GetNW2Int("D6_ArcMode")==4 and elite:GetNW2Float("D6_EyeCharge")>0
        timer.Simple(1.11,function()
            local shield=bot:GetNWFloat("D6_Shield",100)
            check("100 · the blue-to-red optic windup precedes the high-energy eye beam",eyeCharge and shield<=45,shield)
            bot:GodEnable()
            local idle=D6_Drones.Muzzle(elite,7)
            D6_Patterns.ArcElite(elite,bot)
            timer.Simple(.85,function()
                local rotating=D6_Drones.Muzzle(elite,7):Distance(idle)>2
                local rail=elite:GetNW2Float("D6_WeaponCycle_thermal",-5)>CurTime()-.25
                check("101 · the rotary group changes its muzzle pose and the belly rail actually fires",rotating and rail)
                elite:Remove()
                done()
            end)
        end)
    end)
end

local function verifyArcElite(bot,ground,done)
    local center=ground+Vector(760,-1300,320)
    bot:SetPos(center)
    bot.D6Vel=Vector()
    local pos=center+Vector(-530,0,22)
    local elite=SpawnD6Role("arc_elite",pos,bot)
    if not IsValid(elite) then
        check("65 · arc elite has a separate chassis and extended pod hitboxes",false)
        check("66 · thermal warning precedes the five-bolt gap pattern",false)
        check("67 · twin discharge traces can drain the pilot shield",false)
        done()
        return
    end
    elite.D6_AI=nil
    elite:SetAngles(Angle(0,0,0))
    elite:GetPhysicsObject():EnableMotion(false)
    local side=elite:GetRight()*(D6_Session.ArcElite.scale*26.5)
    local trace=D6_Wep.CombatTrace({start=pos+side+Vector(240,0,3),endpos=pos+side-Vector(240,0,3),
        mask=MASK_SHOT,filter=bot})
    check("65 · arc elite has a separate chassis and extended pod hitboxes",trace.Entity==elite
        and D6_Drones.Get(elite).mesh=="combine_arc_elite" and elite.D6_Modules.primaryL.name=="ArcBattery")
    local front=D6_Drones.Muzzle(elite,1)-elite:GetPos()
    D6_Drones.TrackBanks(elite,elite:GetPos()+Vector(-930,0,650),.5)
    local reversed=D6_Drones.Muzzle(elite,1)-elite:GetPos()
    check("97 · the gimbals carry the emission sockets through reverse yaw and positive elevation",
        front.x>100 and reversed.x<0 and reversed.z>55)
    elite:SetNW2Angle("D6_BankAngle_left",angle_zero)
    elite:SetNW2Angle("D6_BankAngle_right",angle_zero)
    local muzzle=D6_Drones.Muzzle(elite,1)
    D6_Drones.Fired(elite,"left")
    timer.Simple(.055,function()
        check("93 · weapon recoil moves the same bank used by the shot socket",
            IsValid(elite) and D6_Drones.Muzzle(elite,1):Distance(muzzle)>.22
            and D6_Drones.Recoil(elite,"right",CurTime())==0)
    end)
    local started=D6_Patterns.ArcElite(elite,bot)
    local warning=elite:GetNWBool("D6_ArcThermal") and elite:GetNWFloat("D6_ThreatAt")>CurTime()
    local custom=D6_Arsenal.NativeModel("shot_homing")
    local preview=D6_Wep.FireProjectile({owner=bot, pos=center+Vector(0,0,190), dir=Vector(0,0,1), speed=260,
        model=custom, scale=.72, swept=true, life=.22})
    check("69 · older workshop weapons preserve their explicit projectile model and scale",
        IsValid(preview) and preview:GetModel()==custom and near(preview:GetModelScale(),.72,.02)
        and preview:GetNWString("D6_ProjectileArt","")=="")
    timer.Simple(1.43,function()
        local count=0
        for _,shot in ipairs(ents.FindByClass("d6_projectile")) do
            if shot:GetOwner()==elite and shot:GetNWString("D6_ProjectileArt")=="shot_ion" then count=count+1;shot:Remove() end
        end
        check("66 · thermal warning precedes the five-bolt gap pattern",started and warning and count>=4,count)
        bot:GodDisable()
        bot:SetNWFloat("D6_Shield",100)
        D6_Patterns.ArcElite(elite,bot)
        timer.Simple(.88,function()
            local shield=bot:GetNWFloat("D6_Shield",100)
            check("67 · twin discharge traces can drain the pilot shield",not elite:GetNWBool("D6_ArcThermal") and shield<=78,shield)
            bot:GodEnable()
            D6_Modules.HomingMod.OnFire(elite,bot)
            local missile=false
            for _,shot in ipairs(ents.FindByClass("d6_projectile")) do
                if shot:GetOwner()==elite and shot:GetModel()==custom then missile=true;shot:Remove() end
            end
            check("70 · the workshop homing module launches the authored rocket as a scripted projectile",missile)
            verifyArcArsenal(bot,elite,done)
        end)
    end)
end

local function verifyAssetsAndSwarm(bot,ground,done)
    local native=file.Find("models/drmd/*.mdl","GAME")
    local valid=#native==79
    for _,name in ipairs(native) do if not util.IsValidModel("models/drmd/"..name) then valid=false end end
    check("51 · 79 native Source model files mount and validate",valid,#native)
    local source=ground+Vector(-170,-1105,320)
    bot:SetPos(source)
    bot:SetEyeAngles(Angle(0,0,0))
    bot.D6AngSynced=Angle()
    local picks={plasmamine="mine_plasma",gravmine="mine_gravity",darkfield="node_dark",energytrap="node_snare"}
    -- These are independent model/physics fixtures, not a mine cadence test.
    -- Only here, clear the shared bay lock between the two fixture deployments;
    -- retain the latest resulting lock afterwards. The mine suite checks cadence.
    local bayReady=bot.D6_MineNextFire or 0
    for key in pairs(picks) do
        bot:SetNWFloat("D6_Energy",100)
        local class="weapon_d6_"..key
        local legacy=key=="darkfield" or key=="energytrap"
        local weapon=legacy and bot:Give(class,true) or bot:GetWeapon(class)
        if IsValid(weapon) then
            local ready=weapon:GetNextPrimaryFire()
            if not legacy then bot.D6_MineNextFire=0; weapon:SetNextPrimaryFire(0) end
            weapon:PrimaryAttack()
            if not legacy then
                weapon:SetNextPrimaryFire(math.max(ready,weapon:GetNextPrimaryFire()))
                bayReady=math.max(bayReady,bot.D6_MineNextFire or 0,weapon:GetNextPrimaryFire())
            end
        end
    end
    bot.D6_MineNextFire=bayReady
    local used={}
    for _,ent in ipairs(ents.FindByClass("d6_ordnance")) do
        if ent:GetOwner()~=bot then continue end
        local kind=ent:GetNWString("D6_ProjectileArt")
        if IsValid(ent:GetPhysicsObject()) and ent:GetModel()==D6_Arsenal.NativeModel(kind) then used[kind]=ent end
    end
    check("52 · all four deployables use scripted entities with distinct models and physics",
        used.mine_plasma and used.mine_gravity and used.node_dark and used.node_snare,table.Count(used))
    local hits, hitWorld, impact = 0, false, "none"
    local above=source+Vector(70,330,320)
    local brush=util.TraceLine({start=above,endpos=above-Vector(0,0,6000),mask=MASK_SOLID_BRUSHONLY})
    local bomb=D6_Wep.FireProjectile({owner=bot,pos=brush.HitPos+Vector(0,0,260),dir=Vector(0,0,-1),speed=1750,
        art="shot_cluster",dmgClass="explosive",physRadius=8,gravity=true,inherit=0,life=1.2,
        onHit=function(_,victim,pos)
            hits=hits+1
            hitWorld=victim==game.GetWorld()
            impact=tostring(victim).." at "..tostring(pos)
        end})
    check("53 · a live physics bomb carries its detailed Source mesh",IsValid(bomb)
        and IsValid(bomb:GetPhysicsObject()) and bomb:GetModel()==D6_Arsenal.NativeModel("shot_cluster"))
    local flight={}
    for _,delay in ipairs({.04,.22,.55}) do
        timer.Simple(delay,function()
            if IsValid(bomb) then
                flight[#flight+1]=string.format("%.0f/%.0f",bomb:GetPos().z,bomb:GetPhysicsObject():GetVelocity().z)
            end
        end)
    end
    local tiers={}
    local mapped=true
    for _, item in ipairs(D6_Arsenal.Order) do
        local tier=D6_Balance.Tier(item.class)
        if tier then tiers[tier]=true else mapped=false end
    end
    check("82 · all 12 curated classes are classified into three active damage tiers",
        #D6_Arsenal.Order==12 and mapped and table.Count(tiers)==3)
    local layout=true
    for _, section in pairs(D6_Campaign.Maps) do if #D6_Campaign.Layout(bot,section)~=3 then layout=false end end
    check("54 · all three campaign profiles resolve safe exhibit positions on real test geometry",layout and table.Count(D6_Campaign.Maps)==3)
    bot:SetNWFloat("D6_Energy",35)
    bot:SetHealth(53)
    local cloud=D6_Mission.NewCloud(bot:WorldSpaceCenter(),26,19)
    timer.Simple(.96,function()
        check("55 · the physics bomb reports a single world impact",brush.HitWorld and hits==1 and hitWorld,
            hits.." | "..impact..(hits~=1 and (" | floor Z "..brush.HitPos.z.." | height/speed "..table.concat(flight,", ")) or ""))
        check("56 · plasma mine arms on its timer",IsValid(used.mine_plasma) and used.mine_plasma:GetNWBool("D6_MineArmed"))
        check("57 · a recovery cloud charges and heals the player on contact",not IsValid(cloud)
            and bot:Health()>=72 and D6_Energy.Get(bot)>59)
        for _,ent in pairs(used) do if IsValid(ent) then ent:Remove() end end
        bot:StripWeapon("weapon_d6_darkfield")
        bot:StripWeapon("weapon_d6_energytrap")
        local anchor=source+Vector(1090,37,110)
        local carrier=SpawnEnemyDrone(bot,"npc_cscanner","grav",anchor)
        local gun=SpawnEnemyDrone(bot,"npc_cscanner","mg",anchor+Vector(60,210,18))
        local launch=SpawnEnemyDrone(bot,"npc_cscanner","rpg",anchor+Vector(-65,-200,12))
        local flank=SpawnEnemyDrone(bot,"npc_cscanner","laser",anchor+Vector(-100,34,160))
        local scrap=SpawnD6Role("resistance_scout",anchor+Vector(125,130,82),bot)
        carrier.D6_NextThrow=math.huge
        local cargo={}
        for i=1,7 do
            local phi=i*2.4
            local pos=anchor+Vector(math.cos(phi)*118,math.sin(phi)*118,(i-4)*39)
            local box,body=D6_Wep.Ordnance("salvage_ballast",pos,nil,{mobile=true,mass=15,collectible=true})
            if IsValid(box) then cargo[#cargo+1]=box end
        end
        timer.Simple(2.15,function()
            local low,high,number=9999,-9999,0
            for _,ent in ipairs(cargo) do
                if ent:GetNWEntity("D6_GravityCarrier")~=carrier then continue end
                local z=ent:WorldSpaceCenter().z-carrier:WorldSpaceCenter().z
                low,high,number=math.min(low,z),math.max(high,z),number+1
            end
            check("58 · gravity carrier holds physical cargo above and below its spherical field",number>=5 and low<-37 and high>37,
                string.format("%d props, Z %.0f to %.0f",number,low,high))
            local p1,p2,p3=D6_Swarm.GetPlan(gun),D6_Swarm.GetPlan(launch),D6_Swarm.GetPlan(flank)
            local foreign=D6_Swarm.GetPlan(scrap)
            local now=CurTime()
            local fire=(D6_Swarm.AllowsFire(gun,now) and 1 or 0)+(D6_Swarm.AllowsFire(launch,now) and 1 or 0)
                +(D6_Swarm.AllowsFire(flank,now) and 1 or 0)
            check("59 · escort plans separate factions, reserve 3D slots and stagger fire",p1 and p2 and p3 and foreign
                and p1.leader==carrier and p2.leader==carrier and p3.leader==carrier and foreign.leader~=carrier
                and p1.slot~=p2.slot and p3.slot~=p1.slot and p1.phase=="escort" and fire==1,
                p1 and p1.phase)
            carrier:Remove()
            timer.Simple(.35,function()
                local plan=D6_Swarm.GetPlan(gun)
                local released=true
                for _,ent in ipairs(cargo) do
                    if IsValid(ent:GetNWEntity("D6_GravityCarrier")) then released=false end
                    ent:Remove()
                end
                check("60 · losing the leader promotes an escort and frees cargo",plan and IsValid(plan.leader)
                    and plan.leader~=carrier and released)
                for _,ent in ipairs({gun,launch,flank,scrap}) do if IsValid(ent) then ent:Remove() end end
                verifyArcElite(bot,ground,function() verifyRogue(bot,ground,done) end)
            end)
        end)
    end)
end

local function verifyCampaign(bot)
    RunConsoleCommand("d6_profile", "campaign")
    timer.Simple(0.3, function()
        bot:GodDisable()
        bot:StripWeapons()
        bot:Spawn()
        timer.Simple(0.6, function()
            check("20 · campaign spawn preserves stock player",
                not bot.D6On and bot:GetModel() ~= "models/combine_scanner.mdl")
            check("21 · campaign suppresses auto kit and removes portals",
                not IsValid(bot:GetWeapon("weapon_d6_phasegate")) and #ents.FindByClass("d6_phase_gate") == 0)
            check("22 · campaign leaves stock engine physics cap", GetConVar("sv_maxvelocity"):GetInt() < 999999,
                GetConVar("sv_maxvelocity"):GetInt())
            local parsed = true
            for _, file in ipairs({"d6_art_geometry.lua", "d6_art_models.lua", "d6_art_elites.lua", "d6_art_render.lua",
                "d6_interface.lua", "d6_hangar.lua", "d6_client.lua", "d6_rogue.lua", "autorun/d6_whiplash.lua",
                "weapons/weapon_d6_hyperbeam.lua", "entities/d6_phase_gate/cl_init.lua",
                "entities/d6_projectile/cl_init.lua"}) do
                if type(CompileFile(file)) ~= "function" then parsed = false end
            end
            check("27 · native GLua compiler accepts client HUD, models and effects", parsed)
            MsgN("[DRMD QA] COMPLETE")
        end)
    end)
end

hook.Add("InitPostEntity", "DRMDCloudVerify", function()
    timer.Simple(0.7, function()
        check("01 · Sandbox server boot", engine.ActiveGamemode() == "sandbox", game.GetMap())
        check("02 · arena profile", D6_Session.IsArena())
        check("03 · Half-Life 2 map detection", D6_Session.Resolve("d1_trainstation_01", "sandbox", "auto") == "campaign"
            and D6_Session.Resolve("d3_citadel_04", "sandbox", "auto") == "campaign"
            and D6_Session.Resolve("ep2_outland_12", "sandbox", "auto") == "campaign")
        check("04 · all 12 curated classes and the explicit SCK tool registered",
            #D6_Arsenal.Order == 12 and weapons.GetStored("swep_construction_kit") ~= nil, #D6_Arsenal.Order)
        for _, item in ipairs(D6_Arsenal.Order) do
            if not weapons.GetStored(item.class) then check("missing SWEP", false, item.class) end
        end
        local axesCorrect = true
        for _, aim in ipairs({Angle(0, 0, 0), Angle(-25, 116, 37), Angle(72, -93, -122), Angle(-88, 22, 94)}) do
            local old = Angle(aim.p, aim.y, aim.r)
            local render = D6_Arsenal.ScannerAngles(aim)
            axesCorrect = axesCorrect and render:Right():Dot(aim:Forward()) > 0.9999
                and render:Up():Dot(aim:Up()) > 0.9999 and aim == old
        end
        check("32 · scanner optic matches muzzle axis with pitch and roll", axesCorrect)
        local finishes = file.Find("materials/drmd/drmd_finish_*.vtf", "GAME")
        local eliteFinishes = {
            ["drmd_finish_arc_shell.vtf"]=true,
            ["drmd_finish_siege_plate.vtf"]=true,
            ["drmd_finish_turned_steel.vtf"]=true,
        }
        local mountedFinishes = #finishes == 8
        for _, name in ipairs(finishes) do
            local raw = file.Read("materials/drmd/" .. name, "GAME")
            local detail = eliteFinishes[name]
            eliteFinishes[name] = nil
            mountedFinishes = mountedFinishes and raw ~= nil and raw:sub(1,4) == "VTF\0"
                and raw:byte(57) == (detail and 10 or 9) and #raw == (detail and 1398180 or 349604)
        end
        check("33 · eight mipmapped finishes, including all three elite textures, mount in Garry's Mod",
            mountedFinishes and not next(eliteFinishes))
        local bot = player.CreateNextBot("DRMD Test Pilot")
        if not IsValid(bot) then check("pilot connected", false); return end

        timer.Simple(1.3, function()
            check("05 · flight, scanner and active first mount",
                bot.D6On and bot:GetModel() == "models/combine_scanner.mdl" and
                IsValid(bot:GetActiveWeapon()) and bot:GetActiveWeapon():GetClass() == D6_Arsenal.Defaults[1])
            check("06 · no workshop and stock tools auto-granted",
                not IsValid(bot:GetWeapon("swep_construction_kit")) and not IsValid(bot:GetWeapon("weapon_d6_spawn_mg")))
            local starters, starterOnly=0,true
            for _, item in ipairs(D6_Arsenal.LegacyOrder) do
                local owned=bot:HasWeapon(item.class)
                if owned then starters=starters+1 end
                if owned~=(D6_Arsenal.Starting[item.class]==true) then starterOnly=false end
            end
            check("102 · normal activation gives exactly five starters and no retired or earned modules",
                starterOnly and starters==5,starters)
            check("103 · starter ordnance is finite and no advanced ammunition is gifted",
                bot:GetAmmoCount("d6_shell")==4 and bot:GetAmmoCount("d6_mine")==2
                and bot:GetAmmoCount("d6_rocket")==0 and bot:GetAmmoCount("d6_rail_cell")==0
                and bot:GetAmmoCount("d6_bfg_cell")==0)
            -- The remaining broad mechanics fixtures require the explicit debug kit.
            D6_Session.GiveLoadout(bot,true)
            local allCurated,noRetired=true,true
            for _, item in ipairs(D6_Arsenal.LegacyOrder) do
                if D6_Arsenal.Playable[item.class] then
                    if not bot:HasWeapon(item.class) then allCurated=false end
                elseif bot:HasWeapon(item.class) then noRetired=false end
            end
            check("104 · explicit debug give supplies all 12 curated classes but no retired weapons",allCurated and noRetired)
            concommand.Run(bot, "6dof_flightassist", {}, "")
            check("23 · control panel can disable stabilization on the first press", bot.D6_FlightAssist == false)
            concommand.Run(bot, "6dof_flightassist", {}, "")
            local cfg = D6_Arsenal.Normalize({[1] = "weapon_d6_rockets", [2] = "weapon_d6_rockets", [3] = "bad"})
            check("07 · mount migration and swap",
                D6_Arsenal.Assign(cfg, 1, "weapon_d6_phasegate") and cfg[1] == "weapon_d6_phasegate" and cfg[5] == D6_Arsenal.Defaults[5])
            check("08 · fifth mount rejects reassignment",
                not D6_Arsenal.Assign(cfg, 5, "weapon_d6_mg") and not D6_Arsenal.Assign(cfg, 1, "weapon_d6_gravmine"))
            local floor = util.TraceLine({start = bot:GetPos() + Vector(0,0,50), endpos = bot:GetPos() - Vector(0,0,450),
                filter = bot, mask = MASK_SOLID_BRUSHONLY})
            local org = floor.HitPos
            local resistance = true
            for variant in pairs(D6_Session.Resistance) do
                local drone = SpawnD6Role(variant, org + Vector(640, 0, 250), bot)
                resistance = resistance and IsValid(drone) and drone:GetNW2String("D6_ArtVariant") == variant
                    and drone.D6_Armor > 0 and drone.D6_Shield == 0
                if IsValid(drone) then drone:Remove() end
            end
            check("34 · all three Resistance variants spawn with their own art and armor", resistance)
            local a = org + Vector(0,0,165)
            bot:SetPos(org + Vector(0,0,100))
            bot:SetNWFloat("D6_Energy", 100)
            local pod = bot:GetWeapon("weapon_d6_rockets")
            local rocketStock=bot:GetAmmoCount("d6_rocket")
            bot.D6AngSynced = Angle(0,0,0)
            pod:PrimaryAttack()
            check("09 · a rocket trigger cycle spends finite stock and energy and publishes recoil",
                bot:GetNWFloat("D6_Energy", 100) < 90 and pod:GetNWFloat("D6_ShotAt", -1) > 0
                and bot:GetAmmoCount("d6_rocket")==rocketStock-1
                and D6_WeaponFeed.Status(pod).remaining==2)
            local after = bot:GetNWFloat("D6_Energy", 100)
            pod:PrimaryAttack()
            check("10 · rocket cooldown denies a duplicate energy and ammunition charge",
                near(bot:GetNWFloat("D6_Energy", 100), after, 0.01)
                and bot:GetAmmoCount("d6_rocket")==rocketStock-1)

            bot:SetNWFloat("D6_Energy", 100)
            concommand.Run(bot, "6dof_dash", {}, "")
            check("24 · dash impulse publishes its cooldown and consumes reserve",
                bot.D6DashOn and bot:GetNWFloat("D6DashCD") > CurTime() and bot:GetNWFloat("D6_Energy") < 90)

            local hitCount, hitWorld = 0, false
            D6_Wep.FireProjectile({
                owner = bot, pos = a, dir = Vector(0,0,-1), speed = 5200, swept = true, inherit = 0,
                model = "models/weapons/w_crossbow_bolt.mdl", dmgClass = "kinetic", life = 0.5,
                onHit = function(_, victim) hitCount = hitCount + 1; hitWorld = victim == game.GetWorld() end,
            })
            timer.Simple(0.72, function()
                check("11 · swept projectile hits world exactly once at 5200 u/s", hitCount == 1 and hitWorld, hitCount)

                -- Both paired portals use real brush hits and the production surface validator.
                local phase = bot:GetWeapon("weapon_d6_phasegate")
                local placements = {}
                bot:SetNWFloat("D6_Energy", 100)
                for step = 1, 2 do
                    local found = false
                    for _, offset in ipairs({Vector(0,0,0), Vector(150,0,0), Vector(0,160,0), Vector(-170,0,0),
                        Vector(305,0,0), Vector(0,310,0), Vector(-310,0,0), Vector(0,-310,0)}) do
                        bot:SetPos(org + offset + Vector(0,0,95))
                        bot.D6AngSynced = Angle(89,0,0)
                        if D6_Gates.Place(bot, phase, step) then found = true; break end
                    end
                    placements[step] = found
                end
                local gates = ents.FindByClass("d6_phase_gate")
                check("12 · phase weapon places a linked pair on real brush surfaces",
                    placements[1] and placements[2] and #gates == 2 and IsValid(gates[1]:GetLinkedGate()), #gates)
                if #gates == 2 then
                    local gate = gates[1]
                    local start = gate:GetPos() + gate:GetForward()*70
                    local finish = gate:GetPos() - gate:GetForward()*8
                    local shot = ents.Create("prop_physics")
                    shot:SetModel("models/hunter/misc/sphere025x025.mdl")
                    shot:SetPos(start)
                    shot:Spawn()
                    local dest, vector = D6_Gates.MoveShot(shot, start, finish, 2, -gate:GetForward()*500, 1)
                    check("13 · phase traversal preserves speed and exits the linked portal",
                        dest and vector and near(vector:Length(), 500, 0.1) and dest:Distance(gate:GetLinkedGate():GetPos()) < 18)
                    local mins, maxs = bot:GetHull()
                    local center = (mins+maxs)*0.5
                    local mock = {origin = gate:GetPos() + gate:GetForward()*84 - center}
                    function mock:GetOrigin() return self.origin end
                    function mock:SetOrigin(pos) self.origin = pos end
                    local cmd = {value = (-gate:GetForward()):Angle()}
                    function cmd:GetViewAngles() return self.value end
                    function cmd:SetViewAngles(angle) self.value = angle end
                    bot:SetPos(mock.origin)
                    bot.D6Vel = gate:GetForward()*-620
                    local obstructed = D6_Gates.MovePlayer(bot, mock, cmd, 0.13)
                    check("28 · phase traversal respects an obstruction on the entry side", not obstructed)
                    shot:Remove()
                    local moved = D6_Gates.MovePlayer(bot, mock, cmd, 0.13)
                    check("25 · phase gates transport a full player hull and rotate momentum",
                        moved and near(bot.D6Vel:Length(), 620, 0.1)
                        and mock.origin:Distance(gate:GetLinkedGate():GetPos()) < 35)
                else
                    check("13 · phase traversal preserves speed and exits the linked portal", false, "no pair")
                end

                bot:SetPos(org + Vector(0,0,120))
                bot:SetEyeAngles(Angle(0,0,0))
                bot.D6AngSynced = Angle(0,0,0)
                bot:SetNWFloat("D6_Energy", 100)
                -- Explicit compatibility fixture; warp is not a curated reward.
                local warp = bot:Give("weapon_d6_warp",true)
                local before = bot:GetPos()
                bot.D6Vel = Vector(0,360,0)
                warp:PrimaryAttack()
                check("26 · warp reaches a clear destination and preserves a flight impulse",
                    bot:GetPos():DistToSqr(before) > 100^2 and near(bot.D6Vel.x, 800, 0.1) and near(bot.D6Vel.y, 360, 0.1)
                    and bot:GetNWFloat("D6_Energy") < 95)
                bot:StripWeapon("weapon_d6_warp")
                bot:SetPos(org + Vector(0,0,120))
                bot.D6Vel = Vector()

                local strider = SpawnRocketStrider(bot, org + Vector(310,0,145))
                check("14 · Rocket Strider initialized and publishes its custom appearance",
                    IsValid(strider) and strider:GetNW2String("D6_ArtVariant") == "rocket_strider")
                local grav = SpawnEnemyDrone(bot, "npc_cscanner", "grav", org + Vector(250,120,145))
                check("15 · gravity unit initialized with its own mesh tag",
                    IsValid(grav) and grav:GetNW2String("D6_ArtVariant") == "grav")
                local cargo = ents.Create("prop_physics")
                cargo:SetModel("models/props_junk/metal_paintcan001a.mdl")
                cargo:SetPos(grav:GetPos() + Vector(36,0,2))
                cargo:Spawn()
                local initialGroup = cargo:GetCollisionGroup()
                grav.D6_NextThrow = CurTime() + 20

                if IsValid(strider) then
                    D6_Patterns.RocketStrider(strider, bot, 450)
                    check("16 · Strider telegraph precedes projectile wave", strider:GetNWFloat("D6_ThreatAt", 0) > CurTime())
                end

                local active = D6_Trial.Start(bot)
                check("17 · trial starts with first group",
                    active and bot:GetNW2Int("D6_TrialWave", 0) == 1)
                D6_Trial.Stop(bot)
                check("18 · trial cleanup releases tracked entities", bot:GetNW2Int("D6_TrialWave", 0) == 0)

                timer.Simple(1.2, function()
                    local pattern = 0
                    for _, ent in ipairs(ents.FindByClass("d6_projectile")) do
                        if ent:GetOwner() == strider and ent:GetNWString("D6_ProjectileArt") == "shot_energy" then
                            pattern = pattern + 1
                        end
                    end
                    check("19 · actual Strider projectiles spawned", pattern > 2, pattern)
                    if IsValid(strider) then strider:Remove() end
                    local captured = IsValid(cargo) and cargo:GetNWEntity("D6_GravityCarrier") == grav
                    check("29 · gravity drone captures real VPhysics debris into orbit", captured)
                    if IsValid(grav) then grav:Remove() end
                    timer.Simple(0.10, function()
                        check("30 · deleting a gravity drone restores the debris physics",
                            captured and not IsValid(cargo:GetNWEntity("D6_GravityCarrier"))
                            and cargo:GetPhysicsObject():IsGravityEnabled() and cargo:GetCollisionGroup() == initialGroup)
                        if IsValid(cargo) then cargo:Remove() end

                        bot:SetPos(org + Vector(0,0,100))
                        bot:GodEnable()
                        D6_Trial.Start(bot)
                        timer.Simple(0.4, function()
                            for _, enemy in ipairs(D6_Actors.GetAll()) do
                                if enemy.D6_Variant == "assault" or enemy.D6_Variant == "interceptor" then enemy:Remove() end
                            end
                            timer.Simple(3.4, function()
                                check("31 · clearing a group advances to the next encounter wave", bot:GetNW2Int("D6_TrialWave", 0) == 2)
                                for _, enemy in ipairs(D6_Actors.GetAll()) do
                                    if enemy.D6_Variant == "grav" or enemy.D6_Variant == "mg" or enemy.D6_Variant == "rpg" then
                                        enemy:Remove()
                                    end
                                end
                                for _, enemy in ipairs(ents.FindByClass("npc_manhack")) do
                                    if enemy.D6_Variant == "manhack_fast" then enemy:Remove() end
                                end
                                timer.Simple(3.4, function()
                                    local seen = {}
                                    for _, enemy in ipairs(D6_Actors.GetAll()) do
                                        local variant = enemy:GetNW2String("D6_ArtVariant")
                                        if D6_Session.Resistance[variant] then seen[variant] = true end
                                    end
                                    check("35 · trial wave three brings all three Resistance hulls",
                                        bot:GetNW2Int("D6_TrialWave", 0) == 3
                                        and seen.resistance_scout and seen.resistance_raider and seen.resistance_hauler,
                                        bot:GetNW2Int("D6_TrialWave", 0) .. " / " .. table.Count(seen))
                                    for _, enemy in ipairs(D6_Actors.GetAll()) do
                                        if D6_Session.Resistance[enemy:GetNW2String("D6_ArtVariant")] then enemy:Remove() end
                                    end
                                    timer.Simple(3.4, function()
                                        local elite
                                        for _, enemy in ipairs(D6_Actors.GetAll()) do
                                            if enemy:GetNW2String("D6_ArtVariant") == "heavy_elite" then elite = enemy end
                                        end
                                        check("47 · elite enforcement drone deploys in the final wave",
                                            bot:GetNW2Int("D6_TrialWave", 0) == 4 and IsValid(elite))
                                        local sweptHit
                                        if IsValid(elite) then
                                            local pos, angles = elite:GetPos(), elite:GetAngles()
                                            local side = angles:Right()*106
                                            local start = pos + side + angles:Forward()*180
                                            local finish = pos + side - angles:Forward()*175
                                            local trace = D6_Wep.CombatTrace({start = start, endpos = finish, filter = bot, mask = MASK_SHOT})
                                            local shield = elite.D6_Shield
                                            if trace.Entity == elite then D6_Wep.DirectDamage(bot, bot, trace.Entity, 16, DMG_ENERGYBEAM) end
                                            check("48 · a hit on the giant hull reaches the boss shield",
                                                elite:GetModelScale() >= 4 and trace.Entity == elite and elite.D6_Shield < shield,
                                                tostring(trace.Entity) .. " / " .. math.Round(elite:GetModelScale(), 1))
                                            D6_Wep.FireProjectile({owner = bot, pos = start, dir = (finish-start):GetNormalized(),
                                                speed = 5200, swept = true, inherit = 0, dmgClass = "kinetic", life = 0.55,
                                                onHit = function(_, victim) if victim then sweptHit = victim end end})
                                        end
                                        if IsValid(elite) then
                                            elite.D6_Modules.primaryL = nil
                                            D6_Patterns.Enforcer(elite, bot)
                                        end
                                        local warning = IsValid(elite) and elite:GetNWFloat("D6_ThreatAt") > CurTime()
                                        timer.Simple(1.22, function()
                                            local projectiles = 0
                                            for _, ent in ipairs(ents.FindByClass("d6_projectile")) do
                                                if ent:GetOwner() == elite then projectiles = projectiles + 1 end
                                            end
                                            check("49 · the boss telegraphs and fires physical projectiles", warning and projectiles > 0,
                                                projectiles)
                                            check("50 · swept projectiles also hit the extended weapon pods", IsValid(elite) and sweptHit == elite)
                                            D6_Trial.Stop(bot)
                                            verifyMobility(bot, org, function()
                                                verifyHyper(bot, org, function()
                                                    verifyAssetsAndSwarm(bot,org,function() verifyCampaign(bot) end)
                                                end)
                                            end)
                                        end)
                                    end)
                                end)
                            end)
                        end)
                    end)
                end)
            end)
        end)
    end)
end)
