-- Independent mine bay. The selected weapon never changes when a mine is dropped.
if SERVER then AddCSLuaFile() end

D6_Mines = {}
local M = D6_Mines
local message = "D6_MineDrop"

function M.CanUse(ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() or ply:InVehicle() then return false end
    if SERVER then return ply.D6On == true end
    return ply:GetNWBool("D6On", false)
end

if SERVER then
    util.AddNetworkString(message)

    function M.TryDeploy(ply)
        if not M.CanUse(ply) then return false end
        local now = CurTime()
        if now < (ply.D6_MineRequestAt or 0) or now < (ply.D6_MineNextFire or 0) then return false end
        ply.D6_MineRequestAt = now + 0.08
        local class = D6_Arsenal.Get(ply, 5)
        local item = D6_Arsenal.Entries[class]
        if not item or item.family ~= "mine" then return false end
        local weapon = ply:GetWeapon(class)
        if not IsValid(weapon) or weapon:GetOwner() ~= ply or not isfunction(weapon.DeployMine) then return false end
        return weapon:DeployMine() == true
    end

    net.Receive(message, function(length, ply)
        if length == 0 then M.TryDeploy(ply) end
    end)
    concommand.Add("d6_mine_drop", function(ply) M.TryDeploy(ply) end)
    return
end

-- No automatic changes to the user's bindings. C is an in-flight shortcut only.
-- Set d6_mine_key 0 to disable it; e.g. bind g +d6_mine assigns another key.
local key = CreateClientConVar("d6_mine_key", tostring(KEY_C), true, false,
    "Mine bay shortcut key code; 0 disables the shortcut. Bind another key to +d6_mine.")
local held, wasDown, chatting = false, false, false
local nextRequest = 0

function M.InputReady(ply)
    return M.CanUse(ply) and not chatting and not ply:IsTyping()
        and not gui.IsGameUIVisible() and not gui.IsConsoleVisible()
        and not vgui.CursorVisible() and not IsValid(vgui.GetKeyboardFocus())
        and (not system.HasFocus or system.HasFocus())
end

local function shortcut()
    local code = key:GetInt()
    return code > 0 and code <= KEY_LAST and code or nil
end

function M.KeyLabel()
    local bound = input.LookupBinding("+d6_mine") or input.LookupBinding("d6_mine_drop")
    local code = shortcut()
    local name = bound or (code and input.GetKeyName(code))
    return name and string.upper(name) or "—"
end

local function request()
    if not M.InputReady(LocalPlayer()) or RealTime() < nextRequest then return end
    nextRequest = RealTime() + 0.08
    net.Start(message)
    net.SendToServer()
end

concommand.Add("+d6_mine", function() held = true end)
concommand.Add("-d6_mine", function() held = false end)
concommand.Add("d6_mine_drop", request)
hook.Add("StartChat", "D6_MineChatStart", function() chatting = true end)
hook.Add("FinishChat", "D6_MineChatFinish", function() chatting = false end)

hook.Add("Think", "D6_MineShortcut", function()
    local code = shortcut()
    local down = held or (code and input.IsKeyDown(code)) or false
    -- Consume the edge even when a menu is open: closing a menu while holding C
    -- must never unexpectedly deploy a mine. Think also runs in singleplayer.
    if down and not wasDown then request() end
    wasDown = down
    if not M.InputReady(LocalPlayer()) then held = false end
end)

hook.Add("PlayerBindPress", "D6_MineContextShortcut", function(ply, bind, _, code)
    local mineKey = shortcut()
    if bind == "+menu_context" and mineKey and code == mineKey and M.InputReady(ply) then
        return true
    end
end)
