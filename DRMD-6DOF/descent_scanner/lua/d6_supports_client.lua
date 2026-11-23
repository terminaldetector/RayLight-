if not CLIENT then return end

D6_SupportUI = {}
local UI, S, U = D6_SupportUI, D6_Supports, D6_Interface
local C = U.colors
local actionKey = CreateClientConVar("d6_support_key", tostring(KEY_G), true, false,
    "In-flight support action shortcut; 0 disables it.")
local cycleKey = CreateClientConVar("d6_support_cycle_key", tostring(KEY_T), true, false,
    "In-flight support slot shortcut; 0 disables it.")
local pendingSlot, pendingUntil, nextRequest = nil, 0, 0
local held, actionWasDown, cycleWasDown = false, false, false
local frame
local stateLabels = {docked="ГОТОВ", deploying="ВЫНОС", active="АКТИВЕН", returning="ВОЗВРАТ"}

local function keyCode(setting)
    local code = setting:GetInt()
    return code > 0 and code <= KEY_LAST and code or nil
end

local function keyLabel(setting, binding)
    local bound = input.LookupBinding(binding)
    local code = keyCode(setting)
    local name = bound or (code and input.GetKeyName(code))
    return name and string.upper(name) or "—"
end

function UI.Selected(ply)
    if pendingSlot and RealTime() < pendingUntil then return pendingSlot end
    return math.Clamp(ply:GetNW2Int("D6_SupportSelected", 1), 1, S.MaxActive)
end

function UI.Select(slot)
    pendingSlot, pendingUntil = math.Clamp(slot, 1, S.MaxActive), RealTime()+0.5
    RunConsoleCommand("d6_support_select", tostring(pendingSlot))
end

function UI.InputReady(ply)
    return D6_Mines and D6_Mines.InputReady(ply)
end

function UI.Action()
    local ply = LocalPlayer()
    if not UI.InputReady(ply) or RealTime() < nextRequest then return end
    nextRequest = RealTime()+0.10
    RunConsoleCommand("d6_support_action", tostring(UI.Selected(ply)))
end

function UI.Cycle()
    local ply = LocalPlayer()
    if UI.InputReady(ply) then UI.Select(UI.Selected(ply)%S.MaxActive+1) end
end

-- The shortcuts are flight-only and never rewrite the user's bindings.
-- Consume key edges while a menu/chat is open, just like the mine bay.
concommand.Add("+d6_support", function() held = true end)
concommand.Add("-d6_support", function() held = false end)
concommand.Add("d6_support_cycle", UI.Cycle)
hook.Add("Think", "D6_SupportShortcuts", function()
    local a, b = keyCode(actionKey), keyCode(cycleKey)
    local actionDown = held or (a and input.IsKeyDown(a)) or false
    local cycleDown = (b and input.IsKeyDown(b)) or false
    if cycleDown and not cycleWasDown then UI.Cycle() end
    if actionDown and not actionWasDown then UI.Action() end
    actionWasDown, cycleWasDown = actionDown, cycleDown
    if not UI.InputReady(LocalPlayer()) then held = false end
end)

function UI.Snapshot(ply)
    local state = {
        slots={}, selected=UI.Selected(ply), ammo=ply:GetAmmoCount(S.Ammo), maximum=S.MaxAmmo,
        action=keyLabel(actionKey, "+d6_support"), cycle=keyLabel(cycleKey, "d6_support_cycle"),
    }
    for slot, id in ipairs(S.GetLoadout(ply)) do
        local spec = S.Definitions[id]
        local mode = IsValid(S.GetEntity(ply, slot)) and S.GetState(ply, slot) or "missing"
        local remaining = math.max(0, ply:GetNW2Float("D6_SupportReady"..slot, 0)-CurTime())
        local label = stateLabels[mode] or "ОЖИДАНИЕ"
        if mode == "docked" and remaining > 0 then label = string.format("%.1f С", remaining)
        elseif mode == "docked" and state.ammo < 1 then label = "НЕТ ЗАРЯДА" end
        state.slots[slot] = {id=id, name=spec.name, color=spec.color, label=label, mode=mode}
    end
    return state
end

function UI.PaintHUD(w, h, state)
    local scale = U.Scale(w, h)
    local x, y, width = 30*scale, h-220*scale, 268*scale
    U.Panel(x, y, width, 76*scale)
    U.Text("САППОРТЫ", "tiny", x+12*scale, y+8*scale, C.muted)
    U.Text(state.ammo.." / "..state.maximum, "small", x+width-12*scale, y+6*scale,
        state.ammo > 0 and C.energy or C.warn, TEXT_ALIGN_RIGHT)
    local gap, cw = 4*scale, (width-32*scale)/3
    for slot, item in ipairs(state.slots) do
        local left = x+12*scale+(slot-1)*(cw+gap)
        local selected = slot == state.selected
        U.Box(left, y+26*scale, cw, 30*scale, selected and Color(45,63,62) or C.bg)
        U.Box(left, y+26*scale, cw, 1.5*scale, selected and item.color or C.edge)
        U.Text(item.name, "tiny", left+cw/2, y+29*scale, selected and C.text or C.muted, TEXT_ALIGN_CENTER)
        U.Text(item.label, "tiny", left+cw/2, y+42*scale, item.mode == "active" and item.color or C.dim, TEXT_ALIGN_CENTER)
    end
    U.Text(state.action.." · пуск / возврат     "..state.cycle.." · выбор", "tiny",
        x+12*scale, y+62*scale, C.muted)
end

local function button(parent, label, action)
    local item = parent:Add("DButton")
    item:SetText("")
    item:SetCursor("hand")
    item.Paint = function(self, w, h)
        U.Panel(0, 0, w, h, self:IsHovered() and Color(45,63,62) or C.card)
        U.Text(label, "small", w/2, h/2, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    item.DoClick = action
    return item
end

function UI.Open()
    if IsValid(frame) then frame:Close(); return end
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local scale = U.Scale(ScrW(), ScrH())
    local width = math.min(ScrW()-36, math.floor(1030*scale))
    local height = math.min(ScrH()-42, math.floor(700*scale))
    local selected = UI.Selected(ply)
    frame = vgui.Create("DFrame")
    local window = frame
    window:SetTitle("")
    window:ShowCloseButton(false)
    window:SetSize(width, height)
    window:Center()
    window:MakePopup()
    window.OnKeyCodePressed = function(self, key) if key == KEY_ESCAPE then self:Close() end end
    window.Paint = function(_, w, h)
        U.Panel(0, 0, w, h, C.bg)
        U.Text("ABADDON  /  ВСПОМОГАТЕЛЬНЫЕ УСТРОЙСТВА", "small", 22*scale, 20*scale, C.aqua)
        U.Text("Три места. Пять ролей.", "heading", 22*scale, 44*scale, C.text)
        local caption = S.CanUse(ply) and "Смена устройства доступна после возврата в корпус."
            or "Включите полёт для смены комплекта."
        U.Text(caption, "small", 22*scale, 85*scale, C.muted)
        U.Line(22*scale, 112*scale, w-22*scale, 112*scale, C.edge)
    end
    local close = button(window, "Закрыть", function() window:Close() end)
    close:SetPos(width-113*scale, 18*scale); close:SetSize(91*scale, 29*scale)
    local left, top, gap = math.floor(width*0.37), 128*scale, 16*scale
    local rightX, rightW = left+gap+22*scale, width-left-gap-44*scale

    for slot = 1, S.MaxActive do
        local card = button(window, "", function() selected=slot; UI.Select(slot) end)
        card:SetPos(22*scale, top+(slot-1)*79*scale)
        card:SetSize(left, 70*scale)
        card.Paint = function(_, w, h)
            local snap = UI.Snapshot(ply)
            local item = snap.slots[slot]
            U.Panel(0, 0, w, h, slot == selected and Color(38,55,53) or C.card)
            U.Text("0"..slot, "number", 12*scale, 14*scale, slot == selected and C.aqua or C.dim)
            U.Text(item.name, "label", 60*scale, 13*scale, C.text)
            U.Text(item.label, "small", 60*scale, 37*scale, item.color)
        end
    end
    local supply = window:Add("DPanel")
    supply:SetPos(22*scale, top+246*scale); supply:SetSize(left, 96*scale)
    supply.Paint = function(_, w, h)
        U.Panel(0, 0, w, h, C.card)
        U.Text("ЗАРЯДЫ  "..ply:GetAmmoCount(S.Ammo).." / "..S.MaxAmmo, "label", 12*scale, 12*scale, C.energy)
        U.Text("Активация расходует заряд и энергию.", "tiny", 12*scale, 37*scale, C.muted)
        U.Text("Боезапас пополняется припасами.", "tiny", 12*scale, 53*scale, C.muted)
        U.Text("Возврат не восстанавливает заряд.", "tiny", 12*scale, 69*scale, C.muted)
    end

    local previewH = 156*scale
    local preview = window:Add("DPanel")
    preview:SetPos(rightX, top); preview:SetSize(rightW, previewH)
    preview.Paint = function(self, w, h)
        U.Panel(0, 0, w, h, Color(17,25,28,250))
        local spec = S.Definitions[S.GetLoadout(ply)[selected]]
        local x, y = self:LocalToScreen(1, 1)
        local camera = Vector(88,-100,62)
        render.SetScissorRect(x,y,x+w-3,y+h-3,true)
        cam.Start3D(camera,(-camera):Angle(),36,x,y,w-3,h-3,1,512)
        cam.IgnoreZ(true)
        D6_Art.Draw(spec.mesh, vector_origin, Angle(0,math.sin(RealTime()*0.6)*18,0),1,spec.color,1,false)
        cam.IgnoreZ(false); cam.End3D()
        render.SetScissorRect(0,0,0,0,false)
        U.Text("Слот "..selected.." · "..spec.name, "tiny", 12*scale, h-22*scale, C.muted)
    end
    local entries = window:Add("DScrollPanel")
    entries:SetPos(rightX, top+previewH+10*scale)
    entries:SetSize(rightW, height-top-previewH-80*scale)
    for _, spec in ipairs(S.Order) do
        local row = entries:Add("DButton")
        row:SetText(""); row:SetCursor("hand")
        row:SetTooltip(spec.description)
        row:Dock(TOP); row:DockMargin(0,0,6*scale,5*scale); row:SetTall(48*scale)
        row.Paint = function(self, w, h)
            local loadout = S.GetLoadout(ply)
            local chosen, occupied = loadout[selected] == spec.id, false
            for i, id in ipairs(loadout) do if i ~= selected and id == spec.id then occupied = true end end
            local docked = S.GetState(ply, selected) == "docked"
            U.Box(0,0,w,h,chosen and Color(45,63,62) or C.card)
            U.Box(0,0,2*scale,h,spec.color)
            U.Text(spec.name, "small", 10*scale, 6*scale, occupied and C.dim or C.text)
            local status = chosen and "Установлен" or (occupied and "В другом слоте" or (docked and "Установить" or "Верните устройство"))
            U.Text(status, "tiny", w-10*scale, 7*scale, C.muted, TEXT_ALIGN_RIGHT)
            U.Text(string.format("1 заряд · %d энергии · цикл %.1f с", spec.energy, spec.cooldown),
                "tiny", 10*scale, 28*scale, C.muted)
        end
        row.DoClick = function()
            RunConsoleCommand("d6_support_set", tostring(selected), spec.id)
        end
    end
    local back = button(window, "Оружейный отсек", function() window:Close(); D6_Hangar.Open() end)
    back:SetPos(22*scale, height-53*scale); back:SetSize(left, 31*scale)
    local recall = button(window, "Вернуть все устройства", function() RunConsoleCommand("d6_support_recall") end)
    recall:SetPos(rightX, height-53*scale); recall:SetSize(rightW, 31*scale)
end

concommand.Add("d6_support_menu", UI.Open)
