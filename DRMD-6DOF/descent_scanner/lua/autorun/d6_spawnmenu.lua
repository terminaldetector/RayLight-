-- Direct visual access to Abaddon's current arsenal, units and support loadout.
-- Catalogue data stays in D6_Arsenal / D6_Drones / D6_Supports.
if SERVER then
    AddCSLuaFile()
    concommand.Add("d6_spawn_weapon", function(ply, _, args)
        if not D6_Session.CanEditWorld(ply) or not ply:Alive() then return end
        if not D6_Session.IsArena() then
            ply:PrintMessage(HUD_PRINTTALK, "[Abaddon] Выдача оружия доступна в режиме арены.")
            return
        end
        local class, slot = args[1], tonumber(args[2] or "1")
        local arsenal = D6_Arsenal
        if not class or not arsenal.Playable[class] then return end
        if not slot or slot % 1 ~= 0 or slot < 1 or slot > 4 then return end
        if CurTime() < (ply.D6_NextMenuWeapon or 0) then return end
        ply.D6_NextMenuWeapon = CurTime() + 0.15
        local stored = weapons.GetStored(class)
        if not stored or gamemode.Call("PlayerGiveSWEP", ply, class, stored) == false then return end
        local weapon = ply:GetWeapon(class)
        if not IsValid(weapon) then
            weapon = ply:Give(class, true)
            if not IsValid(weapon) then return end
            D6_WeaponFeed.GrantInitial(ply, class)
        end
        arsenal.EnsureOwned(ply)
        if arsenal.CanMine(class) then
            -- Both values come from the fixed playable catalogue, never free text.
            concommand.Run(ply, "d6_mine_set", {class}, class)
            ply:PrintMessage(HUD_PRINTTALK, "[Abaddon] Минный отсек: " .. arsenal.Entries[class].name .. " (C)")
        else
            concommand.Run(ply, "d6_mount_set", {tostring(slot), class}, slot .. " " .. class)
            ply:SelectWeapon(class)
        end
    end)
    return
end

local colors = {text = Color(224,235,232), muted = Color(145,173,178), accent = Color(99,200,207)}
local npcNames = {
    assault="Средний штурмовик", mg="Дрон с парными пушками", laser="Лазерный дрон",
    interceptor="Лёгкий перехватчик", rpg="Ракетоносец", artillery="Дальняя артиллерия",
    rocket_elite_homing="Элитный ракетчик", rocket_elite_aa="Элитный зенитный дрон",
    grav="Грависканер", support="Ремонтный дрон", heavy="Тяжёлый плазмодрон",
    heavy_elite="Ракетно-пулемётный бронедрон", arc_elite="Сверхтяжёлый дуговой штурмовик",
    seeker="Ловец", rocket_strider="Rocket Strider", plasma_strider="Плазменный страйдер",
    manhack_fast="Манхак", wheatley="Подрывной дрон", chopper="Летающая огневая платформа",
    worm="Наземный червь", mine="Минный дрон",
}

local function page(sheet, title, icon, help)
    local pane = vgui.Create("DPanel", sheet)
    pane:DockPadding(8,8,8,8)
    pane.Paint = function(_,w,h) surface.SetDrawColor(19,28,32,255); surface.DrawRect(0,0,w,h) end
    local hint = vgui.Create("DLabel", pane)
    hint:Dock(TOP); hint:SetTall(38); hint:SetWrap(true)
    hint:SetTextColor(colors.text); hint:SetText(help)
    local bar = vgui.Create("DPanel",pane)
    bar:Dock(TOP); bar:SetTall(32); bar:DockMargin(0,0,0,8); bar.Paint = nil
    local scroll = vgui.Create("DScrollPanel",pane)
    scroll:Dock(FILL)
    local grid = vgui.Create("DIconLayout",scroll)
    grid:Dock(TOP); grid:SetSpaceX(8); grid:SetSpaceY(8)
    sheet:AddSheet(title,pane,icon)
    return bar, grid
end

local function action(parent, text, command, ...)
    local arguments = {...}
    local button = vgui.Create("DButton",parent)
    button:Dock(LEFT); button:SetWide(160); button:DockMargin(0,0,8,0)
    button:SetText(text)
    button.DoClick = function() RunConsoleCommand(command,unpack(arguments)) end
    return button
end

local function chooseSlot(parent, labels)
    local combo = vgui.Create("DComboBox",parent)
    combo:Dock(LEFT); combo:SetWide(222); combo:DockMargin(0,0,8,0)
    for i,label in ipairs(labels) do combo:AddChoice(label,i) end
    combo:ChooseOptionID(1)
    local selected = 1
    combo.OnSelect = function(_,_,_,data) selected = data end
    return function() return selected end
end

local function card(grid, item, title, subtitle, clicked, tooltip)
    local button = grid:Add("DButton")
    button:SetSize(184,160); button:SetText("")
    button:SetTooltip(tooltip or title)
    button.Paint = function(self,w,h)
        surface.SetDrawColor(self:IsHovered() and Color(36,59,65) or Color(26,39,44))
        surface.DrawRect(0,0,w,h)
        surface.SetDrawColor(self:IsHovered() and colors.accent or Color(58,80,85))
        surface.DrawOutlinedRect(0,0,w,h)
        if D6_SpawnPreview then D6_SpawnPreview.Draw(item,4,4,w-8,103) end
        draw.SimpleText(subtitle or "", "DermaDefault",8,h-17,colors.muted)
    end
    local label = vgui.Create("DLabel",button)
    label:SetPos(8,109); label:SetSize(168,34); label:SetWrap(true)
    label:SetFont("DermaDefaultBold"); label:SetTextColor(colors.text)
    label:SetText(title); label:SetMouseInputEnabled(false)
    button.DoClick = clicked
end

-- The normal Weapons tab uses the same model thumbnails as the Abaddon tab.
spawnmenu.AddContentType("d6_weapon", function(container, object)
    local icon = spawnmenu.CreateContentIcon("weapon", container, object)
    if not IsValid(icon) then return end
    local entry = D6_Arsenal.Entries[object.spawnname]
    if not entry then return icon end
    local item = {kind="weapon",key=entry.class,class=entry.class,mesh=entry.mesh,
        color=D6_Arsenal.Families[entry.family].color}
    icon:SetContentType("d6_weapon")
    icon.DoClick = function()
        local ply = LocalPlayer()
        local active = IsValid(ply) and ply:GetActiveWeapon()
        local slot = IsValid(active) and D6_Arsenal.Slot(ply,active:GetClass()) or 1
        if not slot or slot > 4 then slot = 1 end
        RunConsoleCommand("d6_spawn_weapon",entry.class,tostring(slot))
        surface.PlaySound("ui/buttonclickrelease.wav")
    end
    icon.OpenMenuExtra = function(_, menu)
        menu:AddOption("Получить и установить",icon.DoClick):SetIcon("icon16/add.png")
    end
    local original = icon.PaintOver
    icon.PaintOver = function(self,w,h)
        if D6_SpawnPreview then D6_SpawnPreview.Draw(item,4,4,w-8,h-30) end
        if original then original(self,w,h) end
    end
    return icon
end)

spawnmenu.AddCreationTab("Abaddon", function()
    local sheet = vgui.Create("DPropertySheet")
    local bar, grid = page(sheet,"Оружие","icon16/gun.png",
        "Нажмите на оружие, чтобы получить его и поставить в выбранный узел. Мины занимают минный отсек. Выдача — в арене у хозяина сервера.")
    local weaponSlot = chooseSlot(bar,{"1 · Левое крыло","2 · Правое крыло","3 · Верхний узел","4 · Нижний узел"})
    action(bar,"Выдать весь арсенал","d6_give_weapons")
    action(bar,"Оружейный отсек","d6_menu_toggle")
    for _,entry in ipairs(D6_Arsenal.Order) do
        local item = entry
        local family = D6_Arsenal.Families[item.family]
        card(grid,{kind="weapon",key=item.class,class=item.class,mesh=item.mesh,color=family.color},
            item.name,family.label,function()
                RunConsoleCommand("d6_spawn_weapon",item.class,tostring(weaponSlot()))
            end)
    end

    bar, grid = page(sheet,"Юниты","icon16/bug.png",
        "Нажмите на карточку: юнит появится у точки прицела. Доступно в арене хозяину сервера; Z отменяет вызов.")
    action(bar,"Включить / выключить полёт","6dof_toggle")
    action(bar,"Открыть бестиарий","d6_bestiary")
    local units = {}
    for key,definition in pairs(D6_Drones.Types) do
        units[#units+1] = {key=key,definition=definition,
            name=npcNames[key] or D6_Session.Resistance[key] or key}
    end
    table.sort(units,function(a,b) return a.name < b.name end)
    for _,entry in ipairs(units) do
        local item, definition = entry, entry.definition
        local faction = definition.faction == "resistance" and "Сопротивление" or "Альянс"
        card(grid,{kind="npc",key=item.key,mesh=definition.mesh,color=definition.color},item.name,faction,
            function() RunConsoleCommand("d6_spawn_unit",item.key) end)
    end

    bar, grid = page(sheet,"Саппорты","icon16/shield.png",
        "Включите полёт и выберите место в строю. Нажатие на карточку меняет саппорта; G запускает выбранного. Активация расходует ячейку и энергию.")
    local supportSlot = chooseSlot(bar,{"Саппорт 1 · слева","Саппорт 2 · сверху","Саппорт 3 · справа"})
    action(bar,"Включить / выключить полёт","6dof_toggle")
    local launch = action(bar,"Пуск / возврат","d6_support_action")
    launch.DoClick = function() RunConsoleCommand("d6_support_action",tostring(supportSlot())) end
    for _,entry in ipairs(D6_Supports.Order) do
        local item = entry
        card(grid,{kind="support",key=item.id,mesh=item.mesh,color=item.color},item.name,
            item.energy .. " энергии",function()
                local slot = tostring(supportSlot())
                RunConsoleCommand("d6_support_set",slot,item.id)
                RunConsoleCommand("d6_support_select",slot)
            end,item.description)
    end

    local settings = vgui.Create("DForm",sheet)
    settings:SetName("Обзор и положение оружия")
    settings:CheckBox("Показывать задний обзор","d6_rearview")
    settings:NumSlider("Разведение боковых пушек","d6_view_mount_spread",1,1.5,3)
    settings:Help("1 — прежнее положение; 1.125 — новый стандарт. Настройки сохраняются на этом компьютере.")
    sheet:AddSheet("Обзор",settings,"icon16/eye.png")
    return sheet
end,"icon16/controller.png",25,"Оружие, юниты, саппорты и настройки Abaddon")
