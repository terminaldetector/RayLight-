-- Dedicated GMod, Sandbox, d6_native_flightlab, with the scanner addon mounted.
if not SERVER then return end

hook.Add("InitPostEntity", "AbaddonLiveRecoveryQA", function()
    if game.GetMap() ~= "d6_native_flightlab" then return end
    timer.Simple(.8, function()
        local pilot = player.CreateNextBot("Abaddon Service Pilot")
        if not IsValid(pilot) then ErrorNoHalt("RECOVERY PLAY FAIL | missing test pilot\n"); return end
        timer.Simple(1.2, function()
            local total, fails = 0, 0
            local field = Vector(1496,-450,480)
            local function check(label, ok)
                total = total + 1
                if not ok then fails = fails + 1 end
                print(("RECOVERY PLAY %s | %s"):format(ok and "PASS" or "FAIL",label))
            end
            local function move(center)
                pilot:SetPos(center - (pilot:WorldSpaceCenter() - pilot:GetPos()))
            end
            local function resources(energy, health, shield)
                pilot:SetNWFloat("D6_Energy", energy)
                pilot:SetHealth(health)
                pilot:SetNWFloat("D6_Shield", shield)
                pilot.D6_Shield = shield
            end
            local function cloud()
                return D6_Mission.NewCloud(field,22,12)
            end
            pilot:GodEnable()
            pilot:Freeze(true)
            pilot:SetMoveType(MOVETYPE_NONE)
            pilot:SetMaxHealth(100)
            pilot:SetNWFloat("D6_ShieldMax",100)
            pilot:SetNWFloat("D6_EnergyMax",100)
            local scenario = coroutine.create(function()
                local function tick() coroutine.yield() end
                pilot:SetNWBool("D6On",true)
                move(field + Vector(0,-90,0))
                resources(24,65,42)
                local pickup = cloud()
                check("live scripted cloud spawned", IsValid(pickup) and pickup:GetClass()=="d6_energy_cloud")
                tick()
                check("shielded approach preserves cloud", IsValid(pickup) and pilot:Health()==65)
                move(field + Vector(0,160,0))
                tick()
                check("outside sphere preserves cloud", IsValid(pickup))
                move(field + Vector(0,64,0))
                tick()
                check("clear approach consumes field", not IsValid(pickup))
                check("health repaired on server player", pilot:Health()==77)
                check("weapons bank gained salvage", D6_Energy.Get(pilot)>=46 and D6_Energy.Get(pilot)<66)
                check("shield and network value restored", pilot:GetNWFloat("D6_Shield")>=51 and pilot.D6_Shield>=51)
                check("HUD receives pickup time", CurTime()-pilot:GetNW2Float("D6_CloudPickup",-10)<.5)
                resources(100,100,100)
                pickup=cloud()
                tick()
                check("full pilot leaves field available", IsValid(pickup))
                resources(12,140,130)
                tick()
                check("energy pickup retains bonus hull and shield", not IsValid(pickup) and pilot:Health()==140 and pilot:GetNWFloat("D6_Shield")==130)
                resources(135,96,130)
                pickup=cloud()
                tick()
                check("hull-only pickup retains bonus energy and shield", not IsValid(pickup) and pilot:Health()==100 and D6_Energy.Get(pilot)==135 and pilot:GetNWFloat("D6_Shield")==130)
                resources(135,140,95)
                pickup=cloud()
                tick()
                check("shield-only pickup retains both other bonuses", not IsValid(pickup) and pilot:Health()==140 and D6_Energy.Get(pilot)==135 and pilot.D6_Shield==100)
                move(field + Vector(0,155,0))
                pickup=cloud()
                pickup:SetNW2Float("D6_CloudUntil",CurTime()+.08)
                tick()
                check("expired field removed on server tick", not IsValid(pickup))
                print(("RECOVERY PLAY COMPLETE | %d checks | %d failures"):format(total,fails))
            end)
            local function step()
                local ok, err=coroutine.resume(scenario)
                if not ok then ErrorNoHalt("RECOVERY PLAY FAIL | "..tostring(err).."\n"); return end
                if coroutine.status(scenario)~="dead" then timer.Simple(.26,step) end
            end
            step()
        end)
    end)
end)
