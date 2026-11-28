-- Run with texlua from tests/. Engine globals below model the capture boundary.
CLIENT = true
BRANCH = "x86-64"

local callback, post, report
local messages, files = {}, {}
local now, busy, menu, ready, alive, flying, shooter = 1, false, false, true, true, true, true
local phase, map, profile, frames = 0, "gm_flatgrass", "arena", 0
local mounts = {"mg", "plasma", "heavy", "gravy"}
table.HasValue = function(items, value)
    for _, item in ipairs(items) do if item == value then return true end end
    return false
end
os.date = function() return "20261121-013000" end
MsgN = function(message) messages[#messages + 1] = message end
concommand = {Add = function(_, fn) callback = fn end}
hook = {Add = function(event, _, fn) assert(event == "PostRender"); post = fn end}
RealTime = function() return now end
CurTime = function() return 8 end
gui = {IsGameUIVisible = function() return menu end, IsConsoleVisible = function() return busy end}
game = {GetMap = function() return map end}
IsValid = function(ent) return type(ent) == "table" end
D6_Session = {Profile = function() return profile end}
D6_Mission = {City = "d6_city17_drain", Reactor = "d6_reactor_escape"}
D6_Reactor = {RogueMap = "d6_rogue_reactor", Critical = 2, Escape = 3}
D6_Arsenal = {Get = function(_, i) return mounts[i] end}
local player = {
    Alive = function() return alive end,
    GetNWBool = function(_, key) return key == "D6On" and flying end,
    GetNW2Int = function(_, key, default)
        local values = {D6_ReactorPhase = phase, D6_ReactorCoolantDown = 2, D6_ReactorCoolantTotal = 3, D6_RogueSeed = 38271}
        return values[key] or default
    end,
    GetNW2Float = function() return 32 end,
    GetActiveWeapon = function() return {GetClass = function() return mounts[2] end} end,
}
LocalPlayer = function() return player end
GetViewEntity = function() return shooter and player or nil end
ScrW = function() return 1024 end
ScrH = function() return 768 end
render = {
    GetDXLevel = function() return 95 end,
    Capture = function(params)
        frames = frames + 1
        assert(params.w == 1024 and params.h == 768 and params.format == "png" and params.alpha == false)
        return ready and "test_frame" or nil
    end,
}
EyePos = function() return {x = 7, y = 12, z = 31} end
EyeAngles = function() return {p = 22, y = 50, r = 80} end
file = {
    CreateDir = function(path) assert(path == "abaddon_graphics") end,
    Exists = function(path, root) return root == "DATA" and files[path] ~= nil end,
    Write = function(path, value) files[path] = value end,
}
util = {TableToJSON = function(values) report = values; return "test_report" end}
dofile("d6_graphics_capture.lua")
local function request(name) callback(nil, nil, {name}) end
local function expectMessage(pattern) assert(messages[#messages]:find(pattern, 1, true)) end

request("invalid")
expectMessage("Case:")
busy = true
request("cockpit")
post()
assert(frames == 0)
busy = false
post()
assert(frames == 1 and report.map == "gm_flatgrass" and report.view[3] == 80 and report.mounts[4] == "gravy")
assert(files["abaddon_graphics/20261121-013000-cockpit.png"] == "test_frame")
request("cockpit")
post()
assert(frames == 2 and files["abaddon_graphics/20261121-013000-cockpit-1.json"] == "test_report")
request("campaign_critical")
post()
expectMessage("does not match campaign_critical")
assert(frames == 2)
map, phase = "d6_reactor_escape", 2
request("campaign_critical")
post()
assert(frames == 3 and report.reactor_phase == 2 and report.deadline_seconds == 24)
map, phase = "d6_rogue_reactor", 3
request("rogue_escape")
post()
assert(frames == 4 and report.rogue_seed == 38271)
menu = true
request("mounts")
post()
now = 14
post()
expectMessage("within 12 seconds")
assert(frames == 4)
menu, flying = false, false
request("stock")
post()
expectMessage("does not match stock")
profile = "campaign"
request("stock")
post()
assert(frames == 5 and report.flight == false)
map, profile = "d6_city17_drain", "arena"
request("stock")
post()
assert(frames == 6 and report.map == "d6_city17_drain")
flying, ready = true, false
request("mounts")
post()
expectMessage("client returned no frame")
assert(frames == 7 and files["abaddon_graphics/20261121-013000-mounts.png"] == nil)
print("PASS: capture labels, state validation, console deferral, timeout, metadata, unique names, empty frame.")
