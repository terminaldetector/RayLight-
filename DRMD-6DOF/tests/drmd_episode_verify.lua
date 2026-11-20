if not SERVER or not D6_Mission.IsEpisode() then return end
local function check(id, title, okay, detail)
    MsgN(string.format("[DRMD MAP QA] %s | %02d · %s%s",okay and "PASS" or "FAIL",id,title,detail and (" | "..tostring(detail)) or ""))
end
local function named(name) return ents.FindByName(name)[1] end
local function move(ply,pos)
    ply.D6Vel=Vector()
    ply:SetVelocity(-ply:GetVelocity())
    ply:SetPos(pos)
end

hook.Add("InitPostEntity","DRMDEpisodeQA",function()
    timer.Simple(.8,function()
        local map=game.GetMap()
        local bot=player.CreateNextBot("DRMD Episode Pilot")
        timer.Simple(1.16,function()
            if not IsValid(bot) then check(100,"episode pilot",false);return end
            bot:GodEnable()
            if map == D6_Mission.City then
                local striders=ents.FindByClass("npc_strider")
                local combine=#ents.FindByClass("npc_combine_s")+#ents.FindByClass("npc_metropolice")
                check(71,"city BSP loads with native ground opponents",#striders==2 and combine>=5 and #ents.FindByClass("npc_helicopter")==1)
                check(72,"city chapter starts grounded with a stock firearm",not bot.D6On and bot:HasWeapon("weapon_smg1")
                    and bot:GetNW2Int("D6_EpisodeStage")==1)
                move(bot,Vector(589,0,20))
                timer.Simple(.38,function()
                    check(73,"the real Hammer trigger records the EMP on entering",bot:GetNW2Int("D6_EpisodeStage")==2)
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
                    MsgN("[DRMD MAP QA] COMPLETE CITY")
                    move(bot,Vector(4530,0,-376))
                end)
                return
            end
            check(76,"reactor BSP runs in 6DOF with native personnel and traps",bot.D6On and #ents.FindByClass("npc_combine_s")>=3
                and #ents.FindByClass("trigger_hurt")>=3 and IsValid(named("d6_reactor_core")))
            move(bot,Vector(1130,0,217))
            timer.Simple(.59,function()
                local counts=0
                for _,ent in ipairs(ents.FindByClass("npc_cscanner")) do if ent.D6_Variant=="grav" or ent.D6_Variant=="rpg" then counts=counts+1 end end
                check(77,"flight through the entry volume starts the gravity swarm",bot:GetNW2Int("D6_EpisodeStage")==2 and counts>=2)
                move(bot,Vector(3252,0,167))
                timer.Simple(.48,function()
                    local count=0
                    for _,npc in ipairs(ents.FindByClass("npc_cscanner")) do
                        if npc.D6_Variant=="rocket_strider" or npc.D6_Variant=="plasma_strider" then count=count+1 end
                    end
                    check(78,"guard section deploys rocket and plasma Striders",bot:GetNW2Int("D6_EpisodeStage")==3 and count==2,count)
                    local reactor=named("d6_reactor_core")
                    local door=named("d6_escape_door")
                    local closed=IsValid(door) and door:GetPos().z or 0
                    if IsValid(reactor) then reactor:TakeDamage(700,bot,bot) end
                    timer.Simple(1.88,function()
                        check(79,"lethal core damage activates the native OnBreak collapse relay",
                            bot:GetNW2Int("D6_EpisodeStage")==4 and bot:GetNW2Float("D6_EpisodeDeadline") > CurTime()+47)
                        check(80,"collapse opens the evacuation door and places live airborne mines",
                            IsValid(door) and door:GetPos().z>closed+100 and #ents.FindByClass("d6_ordnance")>=7,IsValid(door) and math.Round(door:GetPos().z))
                        move(bot,Vector(6310,0,240))
                        timer.Simple(.46,function()
                            check(81,"reaching the native exit cancels the failure clock",bot:GetNW2Int("D6_EpisodeStage")==5
                                and bot:GetNW2Float("D6_EpisodeDeadline")==0)
                            MsgN("[DRMD MAP QA] COMPLETE REACTOR")
                        end)
                    end)
                end)
            end)
        end)
    end)
end)
