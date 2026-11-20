D6_Rogue = {}
local R = D6_Rogue
R.MaxWaves = 5
R.Upgrades = {
    cells = {name="Конденсатор", note="+20 к пределу энергии и +20 к запасу"},
    frame = {name="Ремонтные пластины", note="+24 к пределу корпуса и ремонт 24 единиц"},
    shield = {name="Экранирование", note="+20 к пределу щита и заряд 20 единиц"},
    thrust = {name="Векторные сопла", note="+15% к набору скорости"},
    drive = {name="Повышенная тяга", note="+190 ед/с к крейсерскому пределу"},
    repair = {name="Резервная зарядка", note="+35 энергии, +30 корпуса и +28 щита"},
}
local keys = {"cells","frame","shield","thrust","drive","repair"}

if CLIENT then
    local frame
    local function open()
        local ply=LocalPlayer()
        if not IsValid(ply) or ply:GetNW2String("D6_RogueState") ~= "draft" then return end
        if IsValid(frame) then frame:Remove() end
        local ui=D6_Interface
        local scale=ui.Scale(ScrW(),ScrH())
        local width=math.min(ScrW()-38,491*scale)
        frame=vgui.Create("DFrame")
        frame:SetTitle("")
        frame:ShowCloseButton(false)
        frame:SetDraggable(false)
        frame:SetSize(width,290*scale)
        frame:Center()
        frame:MakePopup()
        frame.Paint=function(_,w,h)
            ui.PaintDraft(w,h,scale,ply:GetNW2Int("D6_RogueSeed"),ply:GetNW2Int("D6_RogueWave"))
        end
        frame.Think=function(self)
            if not IsValid(ply) or ply:GetNW2String("D6_RogueState")~="draft" then self:Close() end
        end
        frame.OnKeyCodePressed=function(self,key) if key==KEY_ESCAPE then self:Close() end end
        local close=frame:Add("DButton")
        close:SetPos(width-52*scale,20*scale)
        close:SetSize(32*scale,25*scale)
        close:SetText("")
        close.Paint=function(_,w,h)
            ui.Text("×","label",w*.5,h*.5,ui.colors.muted,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
        end
        close.DoClick=function() frame:Close() end
        for i=1,3 do
            local key=ply:GetNW2String("D6_RogueCard"..i)
            local card=R.Upgrades[key]
            if not card then continue end
            local button=frame:Add("DButton")
            button:SetPos(19*scale,(90+(i-1)*61)*scale)
            button:SetSize(width-38*scale,54*scale)
            button:SetText("")
            button:SetTooltip(card.name)
            button:SetCursor("hand")
            button.Paint=function(self,w,h) ui.PaintUpgrade(w,h,scale,card,self:IsHovered()) end
            button.DoClick=function() RunConsoleCommand("d6_rogue_pick",tostring(i));frame:Close() end
        end
    end
    concommand.Add("d6_rogue_upgrades",open)
    net.Receive("D6_RogueDraft",function() timer.Simple(.2,open) end)
    return
end

util.AddNetworkString("D6_RogueDraft")
local runs = {}
local roles = {"interceptor","assault","laser","mg","rpg","support","resistance_scout","resistance_raider"}

local function draw(run, max)
    run.rng = run.rng*16807 % 2147483647
    return run.rng%max+1
end

local function label(ply, run, state, message)
    ply:SetNW2String("D6_RogueState",state)
    ply:SetNW2String("D6_RogueStatus",message)
    ply:SetNW2Int("D6_RogueWave",run.wave)
    ply:SetNW2Int("D6_RogueSeed",run.seed)
end

local function cleanup(ply, state, message)
    local run=runs[ply]
    if not run then return end
    runs[ply]=nil
    for _,ent in ipairs(run.enemies) do if IsValid(ent) then ent:Remove() end end
    if not IsValid(ply) then return end
    local old=run.old
    ply:SetMaxHealth(old.hp)
    ply:SetHealth(math.min(ply:Health(),old.hp))
    ply:SetNWFloat("D6_EnergyMax",old.energy)
    ply:SetNWFloat("D6_Energy",math.min(D6_Energy.Get(ply),old.energy))
    ply:SetNWFloat("D6_ShieldMax",old.shield)
    ply:SetNWFloat("D6_Shield",math.min(ply:GetNWFloat("D6_Shield",0),old.shield))
    if ply.D6_Params then ply.D6_Params.accel,ply.D6_Params.maxSpeed = old.accel,old.speed end
    label(ply,run,state,message)
    for i=1,3 do ply:SetNW2String("D6_RogueCard"..i,"") end
end

function R.IsActive(ply) return runs[ply] ~= nil end

local function safe(origin, pos)
    if not util.IsInWorld(pos) then return false end
    local hull=Vector(26,26,26)
    local trace=util.TraceHull({start=origin,endpos=pos,mins=-hull,maxs=hull,mask=MASK_NPCSOLID_BRUSHONLY})
    return not trace.Hit
end

local function enemyAt(ply, variant, pos)
    if D6_GetRoleLoadout(variant) then return SpawnD6Role(variant,pos,ply) end
    if variant == "rocket_strider" then return SpawnRocketStrider(ply,pos) end
    return SpawnEnemyDrone(ply,"npc_cscanner",variant,pos)
end

local function wave(ply, run)
    run.wave=run.wave+1
    local chosen={}
    if run.wave==R.MaxWaves then chosen[1]=draw(run,2)==1 and "heavy_elite" or "rocket_strider"
    elseif run.wave==4 then chosen[1]="arc_elite"
    elseif run.wave>=3 then chosen[1]="grav" end
    for _=1,math.min(2+run.wave,6) do chosen[#chosen+1]=roles[draw(run,#roles)] end
    run.enemies={}
    run.offers=nil
    local origin=ply:WorldSpaceCenter()
    local base=ply:EyeAngles().y
    for i,variant in ipairs(chosen) do
        local npc
        for attempt=0,3 do
            local phi=math.rad(base)+(i-1)*math.pi*2/#chosen+attempt*.63
            local distance=645-attempt*116
            local pos=origin+Vector(math.cos(phi)*distance,math.sin(phi)*distance,106+i%3*99)
            if not safe(origin,pos) then continue end
            npc=enemyAt(ply,variant,pos)
            if IsValid(npc) then break end
        end
        if IsValid(npc) then run.enemies[#run.enemies+1]=npc end
    end
    if #run.enemies==0 then cleanup(ply,"lost","Нет места для следующей волны");return end
    label(ply,run,"fight",string.format("Забег %d · Волна %d / %d",run.seed,run.wave,R.MaxWaves))
end

function R.Start(ply, seed)
    if not IsValid(ply) or not ply:Alive() or not ply.D6On or not D6_Session.IsArena() or D6_Mission.IsEpisode()
        or runs[ply] or D6_Trial.IsActive(ply) then return false end
    seed=math.Clamp(math.floor(tonumber(seed) or math.random(10000,999999)),1,2147483646)
    local params=ply.D6_Params or {}
    local run={seed=seed,rng=seed,wave=0,enemies={},old={hp=ply:GetMaxHealth(),energy=D6_Energy.GetMax(ply),
        shield=ply:GetNWFloat("D6_ShieldMax",100),accel=params.accel,speed=params.maxSpeed}}
    runs[ply]=run
    wave(ply,run)
    return runs[ply]~=nil
end

local function offer(ply, run)
    local choices=table.Copy(keys)
    run.offers={}
    for i=1,3 do
        local key=table.remove(choices,draw(run,#choices))
        run.offers[i]=key
        ply:SetNW2String("D6_RogueCard"..i,key)
    end
    label(ply,run,"draft","Выбрать улучшение · d6_rogue_upgrades")
    net.Start("D6_RogueDraft");net.Send(ply)
end

local function useUpgrade(ply, key)
    if key=="cells" then
        ply:SetNWFloat("D6_EnergyMax",D6_Energy.GetMax(ply)+20)
        D6_Energy.Add(ply,20)
    elseif key=="frame" then
        ply:SetMaxHealth(ply:GetMaxHealth()+24)
        ply:SetHealth(ply:Health()+24)
    elseif key=="shield" then
        ply:SetNWFloat("D6_ShieldMax",ply:GetNWFloat("D6_ShieldMax",100)+20)
        ply:SetNWFloat("D6_Shield",ply:GetNWFloat("D6_Shield",0)+20)
    elseif key=="thrust" or key=="drive" then
        ply.D6_Params=ply.D6_Params or {}
        if key=="thrust" then ply.D6_Params.accel=(ply.D6_Params.accel or 4200)*1.15
        else ply.D6_Params.maxSpeed=(ply.D6_Params.maxSpeed or 2200)+190 end
    elseif key=="repair" then
        D6_Energy.Add(ply,35)
        ply:SetHealth(math.min(ply:GetMaxHealth(),ply:Health()+30))
        ply:SetNWFloat("D6_Shield",math.min(ply:GetNWFloat("D6_ShieldMax",100),ply:GetNWFloat("D6_Shield",0)+28))
    end
end

function R.Pick(ply, index)
    local run=runs[ply]
    local key=run and run.offers and run.offers[index]
    if not key then return false end
    run.offers=nil
    for i=1,3 do ply:SetNW2String("D6_RogueCard"..i,"") end
    useUpgrade(ply,key)
    wave(ply,run)
    return true
end

timer.Create("D6_RogueProgress",.28,0,function()
    for ply,run in pairs(runs) do
        if not IsValid(ply) or not ply:Alive() or not ply.D6On then cleanup(ply,"lost","Забег прерван");continue end
        if run.offers then continue end
        local alive=false
        for _,enemy in ipairs(run.enemies) do if IsValid(enemy) and enemy:Health()>0 then alive=true;break end end
        if alive then continue end
        if run.wave==R.MaxWaves then cleanup(ply,"won",string.format("Забег %d завершён",run.seed));continue end
        offer(ply,run)
    end
end)
concommand.Add("d6_rogue_start",function(ply,_,args) if D6_Session.CanEditWorld(ply) then R.Start(ply,args[1]) end end)
concommand.Add("d6_rogue_pick",function(ply,_,args)
    local index=tonumber(args[1]);if index and index%1==0 then R.Pick(ply,index) end
end)
concommand.Add("d6_rogue_stop",function(ply) if IsValid(ply) then cleanup(ply,"stopped","Забег остановлен") end end)
hook.Add("PlayerDeath","D6_RogueLose",function(ply) cleanup(ply,"lost","Корпус потерян · забег завершён") end)
hook.Add("PlayerDisconnected","D6_RogueLeave",function(ply) cleanup(ply,"lost","") end)
cvars.AddChangeCallback("d6_profile",function()
    if not D6_Session.IsArena() then for ply in pairs(runs) do cleanup(ply,"stopped","") end end
end,"D6_RogueProfile")
