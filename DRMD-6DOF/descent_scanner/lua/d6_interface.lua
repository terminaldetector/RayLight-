if not CLIENT then return end
D6_Interface = {}
local U = D6_Interface
local A = D6_Arsenal

U.colors = {
    bg = Color(13, 19, 23, 246), card = Color(18, 26, 29, 237),
    edge = Color(65, 83, 85, 207), muted = Color(161, 179, 174),
    dim = Color(101, 123, 121), text = Color(230, 234, 218),
    aqua = Color(119, 230, 217), lime = Color(182, 222, 124),
    orange = Color(255, 173, 102), warn = Color(244, 112, 86),
    hull = Color(238, 78, 82), shield = Color(84, 164, 247), energy = Color(246, 209, 77),
}
local C = U.colors

function U.Scale(w, h)
    return math.Clamp(math.min(w/1280, h/828), 0.62, 1.55)
end

local sizes = {tiny = 11, small = 13, label = 15, number = 30, heading = 29, title = 37}
function U.Fonts(scale)
    for name, size in pairs(sizes) do
        surface.CreateFont("DRMD_" .. name, {font = "Roboto", size = math.floor(size*scale + 0.5),
            weight = (name == "title" or name == "number") and 780 or 560, antialias = true, extended = true})
    end
end

local function fonts() U.Fonts(U.Scale(ScrW(), ScrH())) end
fonts()
hook.Add("OnScreenSizeChanged", "D6_RefreshInterfaceFonts", fonts)

function U.Text(string, size, x, y, col, align, valign)
    draw.SimpleText(string, "DRMD_" .. size, x, y, col or C.text, align or TEXT_ALIGN_LEFT, valign or TEXT_ALIGN_TOP)
end

function U.Box(x, y, w, h, col)
    surface.SetDrawColor(col)
    surface.DrawRect(x, y, w, h)
end

function U.Line(x1, y1, x2, y2, col)
    surface.SetDrawColor(col)
    surface.DrawLine(x1, y1, x2, y2)
end

function U.Panel(x, y, w, h, col)
    local cut = 11
    draw.NoTexture()
    surface.SetDrawColor(col or C.card)
    surface.DrawPoly({{x=x,y=y}, {x=x+w-cut,y=y}, {x=x+w,y=y+cut}, {x=x+w,y=y+h}, {x=x,y=y+h}})
    U.Line(x, y, x+w-cut, y, C.edge)
    U.Line(x+w-cut, y, x+w, y+cut, C.edge)
    U.Line(x+w, y+cut, x+w, y+h, C.edge)
    U.Line(x+w, y+h, x, y+h, C.edge)
    U.Line(x, y+h, x, y, C.edge)
end

function U.Bar(x, y, w, h, frac, col)
    U.Box(x, y, w, h, Color(53, 70, 72, 188))
    U.Box(x, y, w*math.Clamp(frac, 0, 1), h, col)
end

function U.PaintDraft(w,h,s,seed,wave)
    U.Panel(0,0,w,h,C.bg)
    U.Box(19*s,22*s,3*s,24*s,C.aqua)
    U.Text("Выберите одно улучшение","heading",31*s,18*s)
    U.Text(string.format("Забег %d  ·  Следующая волна %d",seed,wave+1),"small",32*s,55*s,C.muted)
    U.Line(19*s,77*s,w-19*s,77*s,C.edge)
end

function U.PaintUpgrade(w,h,s,card,hovered)
    U.Panel(0,0,w,h,hovered and Color(38,59,56,247) or C.card)
    U.Box(0,0,2,h,hovered and C.aqua or C.edge)
    U.Text(card.name,"label",13*s,9*s,hovered and C.aqua or C.text)
    U.Text(card.note,"small",13*s,29*s,C.muted)
end

local function gauge(label, value, max, x, y, w, scale, color)
    U.Text(label, "tiny", x, y, C.muted)
    U.Text(string.format("%d / %d", math.floor(value), math.floor(max)), "small", x+w, y - 2*scale, color, TEXT_ALIGN_RIGHT)
    U.Bar(x, y+14*scale, w, 4*scale, value/math.max(max, 1), color)
end

local function defenseGauge(state, x, y, w, scale)
    local hpMax, shieldMax = math.max(state.hpMax, 0), math.max(state.shieldMax, 0)
    local total = math.max(hpMax + shieldMax, 1)
    local hullW, shieldW = w*hpMax/total, w*shieldMax/total
    U.Text("КОРПУС", "tiny", x, y, C.hull)
    U.Text("ЩИТ", "tiny", x+w, y, C.shield, TEXT_ALIGN_RIGHT)
    U.Text(string.format("%d / %d", math.floor(state.hp), math.floor(hpMax)),
        "small", x, y+13*scale, C.hull)
    U.Text(string.format("%d / %d", math.floor(state.shield), math.floor(shieldMax)),
        "small", x+w, y+13*scale, C.shield, TEXT_ALIGN_RIGHT)
    local barY, barH = y+31*scale, 8*scale
    U.Box(x, barY, w, barH, Color(53, 70, 72, 188))
    -- Segment widths follow the maximum capacities, never the current damage.
    -- A depleted shield therefore cannot stretch the remaining hull across it.
    U.Box(x, barY, hullW*math.Clamp(state.hp/math.max(hpMax, 1), 0, 1), barH, C.hull)
    U.Box(x+hullW, barY, shieldW*math.Clamp(state.shield/math.max(shieldMax, 1), 0, 1), barH, C.shield)
    if hpMax > 0 and shieldMax > 0 then
        U.Line(x+hullW, barY, x+hullW, barY+barH, C.bg)
    end
end

local headings = {"С", "В", "Ю", "З"}
local function compass(w, scale, yaw)
    local y, x = 37*scale, w/2
    local bearing = (-yaw + 90) % 360
    U.Box(x - 133*scale, y - 16*scale, 266*scale, 46*scale, Color(16, 22, 24, 179))
    local start = math.floor(bearing/10) - 3
    for i = start, start+6 do
        local pos = x + (i*10 - bearing)*3.4*scale
        local strong = i % 3 == 0
        U.Line(pos, y, pos, y+((strong and 8 or 4)*scale), strong and C.muted or C.dim)
        if strong and math.abs(pos-x) > 22*scale then
            local value = (i*10)%360
            U.Text(value%90 == 0 and headings[value/90+1] or tostring(value), "tiny",
                pos, y+11*scale, C.muted, TEXT_ALIGN_CENTER)
        end
    end
    U.Line(x-4*scale, y-6*scale, x, y, C.aqua)
    U.Line(x, y, x+4*scale, y-6*scale, C.aqua)
    U.Text(string.format("%03d°", math.floor(bearing)), "small", x, y+12*scale, C.text, TEXT_ALIGN_CENTER)
end

local function crosshair(w, h, scale, state)
    local x, y = w/2, h/2
    local ink = state.accent
    local extent = 8 + state.kick*8
    local function segment(a,b,c,d)
        U.Line(x+a*scale, y+b*scale+1, x+c*scale, y+d*scale+1, Color(13,20,20,200))
        U.Line(x+a*scale, y+b*scale, x+c*scale, y+d*scale, ink)
    end
    segment(-extent-10,0,-extent,0)
    segment(extent,0,extent+10,0)
    segment(0,-extent-9,0,-extent)
    segment(0,extent,0,extent+6)
    U.Box(x-1, y-1, 3, 3, C.text)

    if state.charge > 0 then
        U.Bar(x-35*scale, y+28*scale, 70*scale, 3*scale, state.charge, ink)
    end
    if state.drift then
        local dx, dy = x + state.drift[1]*58*scale, y + state.drift[2]*58*scale
        if math.abs(dx-x) + math.abs(dy-y) > 12*scale then
            U.Line(dx-4*scale, dy, dx, dy-4*scale, C.aqua)
            U.Line(dx, dy-4*scale, dx+4*scale, dy, C.aqua)
            U.Line(dx+4*scale, dy, dx, dy+4*scale, C.aqua)
            U.Line(dx, dy+4*scale, dx-4*scale, dy, C.aqua)
        end
    end
    if state.warning and state.warning ~= "" then
        U.Text(state.warning, "label", x, y + 57*scale, C.orange, TEXT_ALIGN_CENTER)
    end
end

function U.PaintHUD(w, h, state)
    local scale = U.Scale(w, h)
    local margin = 30*scale
    local pad = 14*scale
    local panelH = 106*scale
    local y = h - margin - panelH
    local leftW, rightW, dockW = 268*scale, 307*scale, 311*scale
    local left, right, dock = margin, w-margin-rightW, (w-dockW)*0.5

    U.Box(margin, 30*scale, 3*scale, 34*scale, C.aqua)
    U.Text("ABADDON  /  ПОЛЁТ", "label", margin+12*scale, 27*scale, C.text)
    U.Text(state.map, "small", margin+12*scale, 47*scale, C.muted)
    U.Text(state.assist and "СТАБИЛИЗАЦИЯ" or "ИНЕРЦИОННЫЙ ПОЛЁТ", "tiny",
        w-margin, 30*scale, state.assist and C.aqua or C.orange, TEXT_ALIGN_RIGHT)
    U.Text(string.format("КРЕН  %+.0f°", state.roll), "small", w-margin, 47*scale, C.muted, TEXT_ALIGN_RIGHT)
    compass(w, scale, state.yaw)
    if state.order and state.order ~= "" then
        local danger=state.deadline and state.deadline>0
        U.Text(state.order,"label",w/2,78*scale,danger and C.orange or C.text,TEXT_ALIGN_CENTER)
        if danger then
            U.Text(string.format("ДО РАСПАДА  %02d",math.ceil(state.deadline)),"small",w/2,99*scale,C.orange,TEXT_ALIGN_CENTER)
            U.Bar(w/2-76*scale,118*scale,152*scale,2*scale,state.deadline/(state.deadlineSpan or 58),C.orange)
        end
    end
    if state.reactorPhase == 1 then
        local hue = state.reactorDown == state.reactorTotal and C.warn or C.aqua
        local label = string.format("КОНТУРЫ  %d/%d    ·    КРИТИЧНОСТЬ  %d%%",
            state.reactorDown,state.reactorTotal,math.floor(state.reactorHeat*100))
        U.Text(label,"small",w/2,102*scale,hue,TEXT_ALIGN_CENTER)
        U.Bar(w/2-114*scale,121*scale,228*scale,3*scale,state.reactorHeat,hue)
    elseif state.reactorPhase == 2 then
        U.Text("ЦЕЛОСТНОСТЬ ЯДРА","small",w/2,102*scale,C.warn,TEXT_ALIGN_CENTER)
        U.Bar(w/2-114*scale,121*scale,228*scale,3*scale,state.reactorHP,C.warn)
    elseif state.boss and state.boss~="" then
        local hue=state.phase==1 and C.aqua or (state.phase==3 and C.warn or C.orange)
        U.Text(state.boss,"small",w/2,102*scale,hue,TEXT_ALIGN_CENTER)
        U.Bar(w/2-114*scale,121*scale,228*scale,3*scale,state.bossHP or 1,hue)
    end

    U.Panel(left, y, leftW, panelH)
    defenseGauge(state, left+pad, y+12*scale, leftW-2*pad, scale)
    gauge("ЭНЕРГИЯ", state.energy, state.energyMax, left+pad, y+65*scale, leftW-2*pad, scale, C.energy)

    U.Panel(dock, y+14*scale, dockW, panelH - 14*scale)
    U.Text("СЕКЦИИ", "tiny", dock+pad, y+23*scale, C.muted)
    local mineKey = D6_Mines and D6_Mines.KeyLabel and D6_Mines.KeyLabel() or "C"
    U.Text("1–4  /  " .. mineKey .. ": МИНА", "tiny", dock+dockW-pad, y+23*scale, C.dim, TEXT_ALIGN_RIGHT)
    local cellW = (dockW - 2*pad - 4*5*scale)/5
    for i = 1, 5 do
        local x = dock+pad+(i-1)*(cellW+5*scale)
        local mount = state.mounts[i]
        local active = state.active == i
        local ink = mount and mount.color or C.dim
        U.Box(x, y+42*scale, cellW, 25*scale, active and Color(49, 69, 67) or Color(27, 40, 43))
        U.Box(x, y+42*scale, cellW, 1.5*scale, active and ink or C.edge)
        U.Text(i == 5 and mineKey .. " · М" or tostring(i), "small", x+cellW/2, y+48*scale,
            active and C.text or C.muted, TEXT_ALIGN_CENTER)
    end
    U.Text(state.dash >= 1 and "РЫВОК ГОТОВ" or "РЫВОК ВОССТАНАВЛИВАЕТСЯ", "tiny",
        dock+pad, y+76*scale, state.dash >= 1 and C.aqua or C.muted)
    U.Bar(dock+dockW-pad-58*scale, y+80*scale, 58*scale, 2*scale, state.dash, C.aqua)

    U.Panel(right, y, rightW, panelH)
    U.Text(state.weaponGroup, "tiny", right+pad, y+12*scale, state.accent)
    U.Text(state.weapon, "label", right+pad, y+29*scale, C.text)
    U.Text(state.weaponStatus, "small", right+pad, y+55*scale, C.muted)
    U.Line(right+pad, y+73*scale, right+rightW-pad, y+73*scale, C.edge)
    U.Text(string.format("%04d ед/с", math.floor(state.speed)), "small", right+pad, y+80*scale, C.text)
    U.Text(state.boost and "ФОРСАЖ" or "СКОРОСТЬ", "tiny", right+rightW-pad, y+82*scale, C.muted, TEXT_ALIGN_RIGHT)
    if state.trial and state.trial ~= "" then
        U.Text(state.trial, "small", dock+dockW*0.5, y-11*scale, C.orange, TEXT_ALIGN_CENTER)
    end

    crosshair(w, h, scale, state)
    if state.damage and state.damage > 0 then
        local alpha = state.damage*140
        U.Box(0, 0, 3*scale, h, Color(251, 122, 77, alpha))
        U.Box(w-3*scale, 0, 3*scale, h, Color(251, 122, 77, alpha))
    end
end

local lastPly, lastHP, lastShield, flashUntil
function U.Snapshot(ply)
    local now = CurTime()
    local weapon = ply:GetActiveWeapon()
    local valid = IsValid(weapon)
    local class = valid and weapon:GetClass() or ""
    local item = A.Entries[class]
    local family = item and A.Families[item.family]
    local name = item and item.name or (valid and weapon:GetPrintName() or "Секция свободна")
    if #name > 58 then name = utf8.sub(name, 1, 27) .. "…" end
    local flight = D6_FlightHUDState()
    local ang = ply.D6Ang or ply:EyeAngles()
    local vel = ply:GetVelocity()
    local speed = vel:Length()
    local energy = D6_Energy.Get(ply)
    local shield = ply:GetNWFloat("D6_Shield", 100)
    local hp = ply:Health()
    if ply == lastPly and (hp < lastHP or shield < lastShield) then flashUntil = now+0.24 end
    lastPly, lastHP, lastShield = ply, hp, shield

    local charge = item and item.charge and weapon:GetNWFloat(item.charge, 0) or 0
    local readyAt = valid and weapon:GetNextPrimaryFire() or 0
    local feed = valid and D6_WeaponFeed and D6_WeaponFeed.Status(weapon, now)
    if feed then readyAt = math.max(readyAt, feed.reloadAt or 0) end
    local status = readyAt > now+0.08 and string.format("Цикл · %.1f с", math.min(readyAt-now, 9.9)) or "К стрельбе готово"
    if charge > 0 then status = string.format("Заряд  %d%%", math.floor(charge*100))
    elseif feed and (feed.reloadAt or 0) > now then status = string.format("Перезарядка · %.1f с", feed.reloadAt-now)
    elseif valid and item and item.ammo then status = string.format("Боезапас   %02d", ply:GetAmmoCount(item.ammo))
    elseif feed and feed.kind == "capacitor" and (feed.capacity or 0) > 0 then
        status = string.format("Серия   %d / %d", feed.remaining, feed.capacity)
    elseif valid and weapon.GetDRMDModeName then status = weapon:GetDRMDModeName()
    elseif class == "weapon_d6_hyperbeam" then
        if weapon:GetNWBool("D6_HyperFiring", false) then status = "Гиперлуч активен"
        elseif readyAt <= now then status = "Удерживайте ЛКМ для заряда" end
    elseif class == "weapon_d6_whiplash" then status = "ЛКМ  сцепление  /  ПКМ  притяжение"
    elseif class == "weapon_d6_gravy_railgun" and IsValid(weapon:GetNWEntity("D6_RailHeld")) then status = "Объект захвачен"
    elseif class == "weapon_d6_phasegate" then
        local a = IsValid(weapon:GetNWEntity("D6_PhaseGate1"))
        local b = IsValid(weapon:GetNWEntity("D6_PhaseGate2"))
        if a and b then status = "Пара порталов активна"
        elseif a then status = "Вход открыт · ПКМ для выхода"
        elseif b then status = "Выход открыт · ЛКМ для входа"
        else status = "ЛКМ  вход  /  ПКМ  выход" end
    elseif valid and not item and weapon:Clip1() >= 0 then
        status = weapon:Clip1() .. " / " .. ply:GetAmmoCount(weapon:GetPrimaryAmmoType())
    elseif not valid then status = "" end

    local idle = now - ply:GetNWFloat("D6LastInput", now)
    local warning = ""
    if now - ply:GetNW2Float("D6_SupplyAt",-20) < 1.4 then warning = ply:GetNW2String("D6_SupplyNotice","")
    elseif now - ply:GetNW2Float("D6_CloudPickup",-20) < 1.0 then warning = "Энергия принята"
    elseif flight.braking then warning = "Аэротормоз"
    elseif flight.dashing then warning = "Импульс"
    elseif flight.adhering then warning = "Сцепление активно"
    elseif idle > 45 then warning = "Гравитация активна"
    elseif idle > 38 then warning = string.format("Гравитация через %d с", math.ceil(45-idle)) end

    local mounts = {}
    for i = 1, 5 do
        local mount = A.Entries[A.Get(ply, i)]
        mounts[i] = mount and A.Families[mount.family]
    end
    local wave = ply:GetNW2Int("D6_TrialWave", 0)
    local trial = ply:GetNW2String("D6_TrialStatus", "")
    if wave > 0 then trial = string.format("Волна %d / 4   ·   %s", wave, trial) end
    local run = ply:GetNW2String("D6_RogueStatus", "")
    local tier=D6_Balance.Tier(class)
    if wave == 0 and run ~= "" then trial = run end
    local shot = valid and weapon:GetNWFloat("D6_ShotAt", -1) or -1
    local drift = speed > 80 and vel:GetNormalized() or nil
    local reactor = ply:GetNW2Int("D6_ReactorPhase",0)
    local order = ply:GetNW2String("D6_EpisodeOrder","")
    local deadline = ply:GetNW2Float("D6_EpisodeDeadline",0)
    if reactor > 0 then
        order = ply:GetNW2String("D6_ReactorOrder",order)
        deadline = ply:GetNW2Float("D6_ReactorDeadline",deadline)
    end
    return {
        order = order,
        deadline = math.max(0,deadline-now),
        deadlineSpan = game.GetMap()==D6_Reactor.RogueMap and D6_Reactor.RogueSeconds or D6_Reactor.StorySeconds,
        reactorPhase = reactor,
        reactorHeat = ply:GetNW2Float("D6_ReactorHeat",0),
        reactorHP = ply:GetNW2Float("D6_ReactorIntegrity",0),
        reactorDown = ply:GetNW2Int("D6_ReactorCoolantDown",0),
        reactorTotal = ply:GetNW2Int("D6_ReactorCoolantTotal",0),
        boss = ply:GetNW2String("D6_BossName",""),
        bossHP = ply:GetNW2Float("D6_BossIntegrity",0),
        phase = ply:GetNW2Int("D6_BossPhase",0),
        map = game.GetMap(), roll = flight.roll, yaw = ang.y, speed = speed, warning = warning,
        assist = ply:GetNWBool("D6_FlightAssist", true), boost = ply:GetNWBool("D6AlwaysRun"),
        hp = hp, hpMax = ply:GetMaxHealth(), shield = shield, shieldMax = ply:GetNWFloat("D6_ShieldMax", 100),
        energy = energy, energyMax = D6_Energy.GetMax(ply), weapon = name, mounts = mounts,
        accent = family and family.color or C.aqua, active = A.Slot(ply, class), charge = charge,
        weaponStatus = status, weaponGroup = family and (family.label..(tier and " · "..D6_Balance.TierLabel[tier] or "")) or "Вооружение",
        dash = 1 - math.Clamp((ply:GetNWFloat("D6DashCD", 0) - now)/D6_Mobility.DashCooldown, 0, 1),
        kick = shot > 0 and math.Clamp(1-(now-shot)*6, 0, 1) or 0,
        trial = trial, drift = drift and {drift:Dot(ang:Right()), -drift:Dot(ang:Up())},
        damage = math.Clamp(((flashUntil or 0)-now)/0.24, 0, 1),
    }
end

local function cockpit(ply)
    return IsValid(ply) and ply:Alive() and ply:GetNWBool("D6On") and not ply:InVehicle()
        and GetViewEntity() == ply
end

local function paintReactorTarget(ply, state, w, h)
    if state.reactorPhase == 0 then return end
    local pos = ply:GetNW2Vector("D6_ReactorWaypoint",vector_origin)
    local label = state.reactorPhase == 3 and "ВЫХОД" or "ЯДРО"
    local hue = state.reactorPhase == 3 and C.lime or C.warn
    if state.reactorPhase == 1 then
        local nearest
        for i=1,3 do
            local target = ply:GetNW2Entity("D6_ReactorNode"..i)
            if IsValid(target) then
                local point = target:GetPos()
                local distance = point:DistToSqr(EyePos())
                if not nearest or distance < nearest then
                    pos,nearest,label = point,distance,"КОНТУР "..i
                end
            end
        end
        if not nearest then return end
        hue=C.aqua
    end
    local point=pos:ToScreen()
    local scale=U.Scale(w,h)
    if not point.visible or point.x<18*scale or point.x>w-18*scale or point.y<151*scale or point.y>h-150*scale then return end
    local x,y=point.x,point.y
    local a,b=6*scale,10*scale
    U.Line(x-a,y,x,y-a,hue)
    U.Line(x,y-a,x+a,y,hue)
    U.Line(x+a,y,x,y+a,hue)
    U.Line(x,y+a,x-a,y,hue)
    U.Text(string.format("%s · %.0f м",label,EyePos():Distance(pos)*.0254),"tiny",x,y+b,hue,TEXT_ALIGN_CENTER)
end

function U.PaintGround(w,h,order,caption,remaining)
    local s=U.Scale(w,h)
    U.Box(30*s,30*s,3*s,34*s,C.orange)
    if caption~="" and remaining>0 then
        local opacity=math.min(remaining*2,1)
        U.Box(w/2-206*s,h*.747,412*s,49*s,Color(10,17,23,210*opacity))
        U.Text(caption,"label",w/2,h*.747+17*s,Color(222,231,224,255*opacity),TEXT_ALIGN_CENTER)
    end
    U.Text("ABADDON  /  ОПТИКА АЛЬЯНСА", "label",42*s,27*s,C.text)
    U.Text(order,"small",42*s,48*s,C.muted)
end

hook.Add("HUDPaint", "D6_Cockpit", function()
    local ply = LocalPlayer()
    if cockpit(ply) then
        local state=U.Snapshot(ply)
        U.PaintHUD(ScrW(),ScrH(),state)
        paintReactorTarget(ply,state,ScrW(),ScrH())
        return
    end
    if not IsValid(ply) or not ply:Alive() or game.GetMap()~=D6_Mission.City then return end
    local order=ply:GetNW2String("D6_EpisodeOrder","")
    if order=="" then return end
    U.PaintGround(ScrW(),ScrH(),order,ply:GetNW2String("D6_EpisodeCaption",""),
        ply:GetNW2Float("D6_EpisodeCaptionEnd",0)-CurTime())
end)
local replaced = {CHudHealth = true, CHudBattery = true, CHudAmmo = true,
    CHudSecondaryAmmo = true, CHudCrosshair = true}
hook.Add("HUDShouldDraw", "D6_CockHideDefaultHUD", function(name)
    if replaced[name] and cockpit(LocalPlayer()) then return false end
end)
