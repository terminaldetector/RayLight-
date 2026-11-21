if not CLIENT then return end
D6_Hangar = {}
local H, U, A = D6_Hangar, D6_Interface, D6_Arsenal
local C = U.colors
local openFrame

function H.PaintHeader(w, h, scale, arena)
    U.Panel(0, 0, w, h, C.bg)
    U.Box(22*scale, 19*scale, 3*scale, 15*scale, C.aqua)
    U.Text("ABADDON  /  КОНФИГУРАЦИЯ КОРПУСА", "small", 35*scale, 18*scale, C.aqua)
    U.Text("Оружейный отсек", "title", 20*scale, 37*scale)
    U.Text(arena and "Профиль арены" or "Профиль кампании Half-Life 2", "small", 22*scale, 87*scale, C.muted)
    U.Line(22*scale, 113*scale, w-22*scale, 113*scale, C.edge)
end

function H.PaintSection(w, h, scale, index, item, selected, active)
    local family = A.Families[item.family]
    U.Panel(0, 0, w, h, selected and Color(36, 55, 53, 243) or C.card)
    U.Box(0, 0, selected and 3 or 2, h, active and family.color or (selected and C.aqua or C.edge))
    U.Text(string.format("%02d", index), "number", 12*scale, (h-31*scale)*0.5, selected and C.aqua or C.dim)
    U.Text(A.Mounts[index].label, "tiny", 56*scale, 8*scale, C.muted)
    U.Text(item.name, "label", 56*scale, 25*scale, C.text)
end

function H.PaintListItem(w, h, scale, item, chosen, owned)
    local family = A.Families[item.family]
    U.Box(0, 0, w, h, chosen and Color(52, 71, 62) or Color(29, 42, 43))
    U.Box(0, 0, 2, h, owned and family.color or C.dim)
    U.Text(item.name, "small", 10*scale, 7*scale, owned and C.text or C.dim)
    U.Text(chosen and "Установлено" or (owned and family.label or "Нет в арсенале"), "tiny",
        w-10*scale, 8*scale, chosen and C.lime or C.muted, TEXT_ALIGN_RIGHT)
end

local function makeButton(parent, text, action)
    local button = parent:Add("DButton")
    button:SetText("")
    button:SetCursor("hand")
    button.Paint = function(self, w, h)
        local enabled = self:IsEnabled()
        U.Panel(0, 0, w, h, self:IsHovered() and enabled and Color(45, 68, 65) or C.card)
        U.Text(text, "small", w/2, h/2, enabled and C.text or C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    button.DoClick = action
    return button
end

function H.Open()
    if IsValid(openFrame) then openFrame:Close(); return end
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local scale = U.Scale(ScrW(), ScrH())
    local width = math.min(ScrW() - 36, math.floor(1030*scale))
    local height = math.min(ScrH() - 42, math.floor(666*scale))
    local frame = vgui.Create("DFrame")
    openFrame = frame
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetSize(width, height)
    frame:Center()
    frame:MakePopup()
    frame.Paint = function(_, w, h) H.PaintHeader(w, h, scale, D6_Session.IsArena()) end
    frame.OnKeyCodePressed = function(self, key)
        if key == KEY_ESCAPE or key == KEY_F6 then self:Close() end
    end

    local active = ply:GetActiveWeapon()
    local section = (IsValid(active) and A.Slot(ply, active:GetClass())) or 1
    local gap = 16*scale
    local left = math.floor(width*0.39)
    local rightX = left+gap+22*scale
    local rightW = width - rightX - 22*scale
    local top = 130*scale
    local cardH = 56*scale
    local previewH = 159*scale
    local reloadList

    local close = makeButton(frame, "Закрыть", function() frame:Close() end)
    close:SetPos(width-113*scale, 21*scale)
    close:SetSize(91*scale, 29*scale)

    for i = 1, 5 do
        local card = frame:Add("DButton")
        card:SetText("")
        card:SetCursor("hand")
        card:SetPos(22*scale, top+(i-1)*(cardH+7*scale))
        card:SetSize(left, cardH)
        card.Paint = function(_, w, h)
            local item = A.Entries[A.Get(ply, i)]
            local weapon = ply:GetActiveWeapon()
            local slot = IsValid(weapon) and A.Slot(ply, weapon:GetClass())
            H.PaintSection(w, h, scale, i, item, i == section, i == slot)
        end
        card.DoClick = function()
            section = i
            reloadList()
        end
        card.DoDoubleClick = function()
            if i < 5 then RunConsoleCommand("d6_mount_select", tostring(i)) end
            frame:Close()
        end
    end

    local preview = frame:Add("DPanel")
    preview:SetPos(rightX, top)
    preview:SetSize(rightW, previewH)
    preview.Paint = function(self, w, h)
        U.Panel(0, 0, w, h, Color(17, 25, 28, 250))
        for i = 1, 12 do
            local x = i*w/13
            U.Line(x, 16*scale, x, h-16*scale, Color(49, 66, 68, 102))
        end
        for i = 1, 5 do
            local y = i*h/6
            U.Line(14*scale, y, w-14*scale, y, Color(49, 66, 68, 102))
        end
        local item = A.Entries[A.Get(ply, section)]
        local model = A.Families[item.family]
        local x, y = self:LocalToScreen(1, 1)
        local camera = Vector(50, -58, 31)
        local turn = math.sin(RealTime()*0.8)*13
        render.SetScissorRect(x, y, x+w-3, y+h-3, true)
        cam.Start3D(camera, (-camera):Angle(), 34, x, y, w-3, h-3, 1, 512)
        cam.IgnoreZ(true)
        D6_Art.Draw(item.mesh, vector_origin, Angle(0, turn, 0), 1, model.color, 1, false)
        cam.IgnoreZ(false)
        cam.End3D()
        render.SetScissorRect(0, 0, 0, 0, false)
        U.Text(item.family == "mine" and "Выдвижной минный отсек" or "Текущий модуль",
            "tiny", 12*scale, h-23*scale, C.muted)
    end

    local title = frame:Add("DLabel")
    title:SetPos(rightX, top+previewH+9*scale)
    title:SetSize(rightW, 22*scale)
    title:SetFont("DRMD_label")
    title:SetTextColor(C.text)

    local entries = frame:Add("DScrollPanel")
    entries:SetPos(rightX, top+previewH+36*scale)
    entries:SetSize(rightW, math.max(58*scale, height - top - previewH - 108*scale))
    local bar = entries:GetVBar()
    bar.Paint = function(_, w, h) U.Box(0, 0, w, h, C.bg) end
    bar.btnGrip.Paint = function(_, w, h) U.Box(1, 0, w-2, h, C.edge) end

    reloadList = function()
        entries:Clear()
        local mineKey = D6_Mines and D6_Mines.KeyLabel and D6_Mines.KeyLabel() or "C"
        title:SetText(section == 5 and ("Минный отсек · сброс " .. mineKey) or "Оружие для секции " .. section)
        for _, item in ipairs(A.Order) do
            if (section == 5) == (item.family == "mine") then
                local row = entries:Add("DButton")
                row:Dock(TOP)
                row:DockMargin(0, 0, 6*scale, 4*scale)
                row:SetTall(31*scale)
                row:SetText("")
                row.Paint = function(self, w, h)
                    local assigned = A.Get(ply, section) == item.class
                    local owned = IsValid(ply:GetWeapon(item.class))
                    H.PaintListItem(w, h, scale, item, assigned or self:IsHovered(), owned)
                end
                row.DoClick = function()
                    if not IsValid(ply:GetWeapon(item.class)) then return end
                    if section == 5 then
                        if D6_Session.IsArena() then RunConsoleCommand("d6_mine_set", item.class) end
                    elseif D6_Session.IsArena() then
                        RunConsoleCommand("d6_mount_set", tostring(section), item.class)
                    end
                end
            end
        end
    end
    reloadList()

    local use = makeButton(frame, "К полёту", function()
        if section < 5 then RunConsoleCommand("d6_mount_select", tostring(section)) end
        frame:Close()
    end)
    use:SetPos(rightX, height-55*scale)
    use:SetSize(rightW, 32*scale)
    use:SetEnabled(ply:GetNWBool("D6On"))

    local flight = makeButton(frame, "Вкл. / выкл. полёт", function() RunConsoleCommand("6dof_toggle") end)
    flight:SetPos(22*scale, top+5*(cardH+7*scale)+5*scale)
    flight:SetSize((left-gap)*0.5, 33*scale)
    flight:SetEnabled(D6_Session.IsArena())

    local trial = makeButton(frame, "Испытание", function()
        local command = ply:GetNW2Int("D6_TrialWave", 0) > 0 and "d6_trial_stop" or "d6_trial_start"
        RunConsoleCommand(command)
        frame:Close()
    end)
    trial:SetPos(22*scale+(left+gap)*0.5, top+5*(cardH+7*scale)+5*scale)
    trial:SetSize((left-gap)*0.5, 33*scale)
    trial:SetEnabled(D6_Session.IsArena() and D6_Session.CanEditWorld(ply) and ply:GetNWBool("D6On"))

    local assist = makeButton(frame, "Стабилизация", function() RunConsoleCommand("6dof_flightassist") end)
    assist:SetPos(22*scale, top+5*(cardH+7*scale)+44*scale)
    assist:SetSize((left-gap)*0.5, 32*scale)
    assist:SetEnabled(ply:GetNWBool("D6On"))
    local legacy = makeButton(frame, "Настройки", function()
        frame:Close()
        RunConsoleCommand("d6_menu_open")
    end)
    legacy:SetPos(22*scale+(left+gap)*0.5, top+5*(cardH+7*scale)+44*scale)
    legacy:SetSize((left-gap)*0.5, 32*scale)
end

concommand.Add("d6_menu_toggle", H.Open)
