-- Optional client-side smoke test. Install only in the local test addon.
if not CLIENT then return end

local capture
local cases = {"cockpit", "mounts", "campaign_critical", "rogue_escape", "stock"}

local function eligible(name, ply, map)
    if name == "stock" then
        return (map == D6_Mission.City or D6_Session.Profile() == "campaign") and not ply:GetNWBool("D6On")
    end
    if not ply:GetNWBool("D6On") or GetViewEntity() ~= ply then return false end
    local phase = ply:GetNW2Int("D6_ReactorPhase", 0)
    if name == "campaign_critical" then
        return map == D6_Mission.Reactor and phase == D6_Reactor.Critical
    elseif name == "rogue_escape" then
        return map == D6_Reactor.RogueMap and phase == D6_Reactor.Escape
    end
    return true
end

local function status(message)
    MsgN("[Abaddon Capture] " .. message)
end

concommand.Add("d6_graphics_capture", function(_, _, args)
    local name = args[1]
    if not table.HasValue(cases, name) then
        status("Case: " .. table.concat(cases, " | "))
        return
    end
    if capture then
        status("A frame is already queued.")
        return
    end
    if not D6_Session or not D6_Mission or not D6_Reactor or not D6_Arsenal then
        status("Load Half-Life: Abaddon in a local Sandbox session.")
        return
    end
    capture = {name = name, expires = RealTime() + 12}
    status("Frame queued. Close the console or pause menu.")
end)

local directory = "abaddon_graphics"

local function fileName(name)
    local stamp = os.date("%Y%m%d-%H%M%S")
    local base = string.format("%s/%s-%s", directory, stamp, name)
    local result = base
    local suffix = 0
    while file.Exists(result .. ".png", "DATA") or file.Exists(result .. ".json", "DATA") do
        suffix = suffix + 1
        result = base .. "-" .. suffix
    end
    return result
end

hook.Add("PostRender", "D6_GraphicsSmokeCapture", function()
    if not capture then return end
    if RealTime() >= capture.expires then
        capture = nil
        status("No unobstructed frame was available within 12 seconds.")
        return
    end
    if gui.IsGameUIVisible() or gui.IsConsoleVisible() then return end
    local name = capture.name
    capture = nil
    local ply = LocalPlayer()
    local map = game.GetMap()
    if not IsValid(ply) or not ply:Alive() or not eligible(name, ply, map) then
        status("The live player, map, view or reactor phase does not match " .. name .. ".")
        return
    end

    local width, height = ScrW(), ScrH()
    local png = render.Capture({format = "png", x = 0, y = 0, w = width, h = height, alpha = false})
    if not png then
        status("The client returned no frame. Close the pause menu and retry.")
        return
    end

    local pos, angle = EyePos(), EyeAngles()
    local active = ply:GetActiveWeapon()
    local mounts = {}
    for i = 1, 4 do mounts[i] = D6_Arsenal.Get(ply, i) or "" end
    local metadata = {
        case = name,
        map = map,
        profile = D6_Session.Profile(),
        engine_branch = BRANCH,
        render_width = width,
        render_height = height,
        dx_level = render.GetDXLevel(),
        position = {pos.x, pos.y, pos.z},
        view = {angle.p, angle.y, angle.r},
        flight = ply:GetNWBool("D6On"),
        reactor_phase = ply:GetNW2Int("D6_ReactorPhase", 0),
        coolant_down = ply:GetNW2Int("D6_ReactorCoolantDown", 0),
        coolant_total = ply:GetNW2Int("D6_ReactorCoolantTotal", 0),
        deadline_seconds = math.max(0, ply:GetNW2Float("D6_ReactorDeadline", 0) - CurTime()),
        rogue_seed = ply:GetNW2Int("D6_RogueSeed", 0),
        active_weapon = IsValid(active) and active:GetClass() or "",
        mounts = mounts,
    }

    file.CreateDir(directory)
    local base = fileName(name)
    file.Write(base .. ".png", png)
    file.Write(base .. ".json", util.TableToJSON(metadata, true))
    if file.Exists(base .. ".png", "DATA") and file.Exists(base .. ".json", "DATA") then
        status("Wrote garrysmod/data/" .. base .. ".png and .json")
    else
        status("The client failed to save the frame or report.")
    end
end)
