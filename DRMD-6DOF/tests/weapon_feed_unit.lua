-- Run from tests/: texlua weapon_feed_unit.lua
-- Executes real policy/feed/energy code and the core payment entry point.
-- Engine transport, projectile collisions and visual timing still need GMod.
local root = arg[1] or "../descent_scanner/lua/"
local passed, now = 0, 100
local function check(name, condition)
    assert(condition, name)
    passed = passed + 1
    print("PASS | " .. name)
end
function CurTime() return now end
function IsValid(value) return type(value) == "table" and value.valid == true end
function AddCSLuaFile() end
function Color(...) return {...} end
math.Clamp = function(value, low, high) return math.max(low, math.min(high, value)) end
hook = {Add = function() end}
concommand = {Add = function() end}
util = {AddNetworkString = function() end}
timer = {Simple = function() end}
net = {Start = function() end, WriteVector = function() end,
    WriteBool = function() end, WriteFloat = function() end, Broadcast = function() end}
IN_ATTACK, MASK_SHOT = 1, 0

local vec = {}
vec.__index = vec
function Vector(x, y, z) return setmetatable({x=x or 0, y=y or 0, z=z or 0}, vec) end
function vec.__add(a, b) return Vector(a.x+b.x, a.y+b.y, a.z+b.z) end
function vec.__sub(a, b) return Vector(a.x-b.x, a.y-b.y, a.z-b.z) end
function vec.__mul(a, b) return Vector(a.x*b, a.y*b, a.z*b) end
function vec.__unm(a) return a * -1 end
function vec:DistToSqr(other) local d = self-other; return d:Dot(d) end
function vec:Dot(other) return self.x*other.x + self.y*other.y + self.z*other.z end
function vec:GetNormalized()
    local length = math.sqrt(self:Dot(self))
    return length > 0 and self*(1/length) or Vector()
end

local function entity()
    local e = {valid=true, network={}}
    function e:SetNWFloat(key, value) self.network[key] = value end
    function e:GetNWFloat(key, default)
        if self.network[key] == nil then return default end
        return self.network[key]
    end
    e.SetNW2Int, e.SetNW2Float = e.SetNWFloat, e.SetNWFloat
    e.GetNW2Int, e.GetNW2Float = e.GetNWFloat, e.GetNWFloat
    return e
end
local function pilot(energy)
    local p = entity()
    p.ammo, p.weapons, p.sounds = {}, {}, 0
    p:SetNWFloat("D6_Energy", energy or 100)
    function p:GetAmmoCount(ammo) return self.ammo[ammo] or 0 end
    function p:RemoveAmmo(amount, ammo) self.ammo[ammo] = self:GetAmmoCount(ammo)-amount end
    function p:GiveAmmo(amount, ammo) self.ammo[ammo] = self:GetAmmoCount(ammo)+amount end
    function p:GetWeapons() return self.weapons end
    function p:EmitSound() self.sounds = self.sounds+1 end
    function p:KeyDown() return self.held ~= false end
    function p:GetShootPos() return Vector() end
    function p:GetPos() return Vector() end
    return p
end
local function weapon(owner, suffix, prototype)
    local w = entity()
    w.class, w.owner, w.nextPrimary, w.nextSecondary = "weapon_d6_"..suffix, owner, 0, 0
    function w:GetClass() return self.class end
    function w:GetOwner() return self.owner end
    function w:GetNextPrimaryFire() return self.nextPrimary end
    function w:SetNextPrimaryFire(time) self.nextPrimary = time end
    function w:GetNextSecondaryFire() return self.nextSecondary end
    function w:SetNextSecondaryFire(time) self.nextSecondary = time end
    function w:SetWeaponHoldType() end
    if prototype then setmetatable(w, {__index=prototype}) end
    owner.weapons[#owner.weapons+1] = w
    return w
end

-- The catalogue's engine hooks are irrelevant to payment; load its actual data.
SERVER, CLIENT = false, false
dofile(root .. "d6_arsenal.lua")
SERVER = true
dofile(root .. "d6_energy.lua")
dofile(root .. "d6_weapon_feed.lua")
local F = D6_WeaponFeed
D6_Wep = {}
-- The rest of weapon_core contains GMod-only continue syntax. Load the actual
-- complete payment function, without translating or duplicating its logic.
local coreFile = assert(io.open(root .. "d6_weapon_core.lua", "r"))
local core = coreFile:read("*a"); coreFile:close()
local payment = assert(core:match("(function D6_Wep.TrySpend.-)\n    function D6_Wep.DeployPoint"))
assert(load(payment, "@d6_weapon_core.lua:TrySpend"))()

local owner = pilot(3)
local mortar = weapon(owner, "heavy")
owner.ammo.d6_shell = 4
local ok, reason = D6_Wep.TrySpend(mortar, owner, 20)
check("insufficient energy leaves reserve and local cycle untouched", not ok and reason == "energy"
    and owner:GetAmmoCount("d6_shell") == 4 and D6_Energy.Get(owner) == 3
    and mortar.D6_FeedState == nil and mortar.network.D6_FeedRemaining == nil)
owner:SetNWFloat("D6_Energy", 100); owner.ammo.d6_shell = 0
ok, reason = D6_Wep.TrySpend(mortar, owner, 20)
check("empty reserve is denied before spending energy", not ok and reason == "ammo"
    and D6_Energy.Get(owner) == 100 and mortar.D6_FeedState == nil)
owner.ammo.d6_shell = 4
check("successful mortar cycle consumes one shell and energy", D6_Wep.TrySpend(mortar, owner, 20)
    and owner:GetAmmoCount("d6_shell") == 3 and D6_Energy.Get(owner) == 80
    and F.Status(mortar).remaining == 1)
check("second mortar cycle starts its local reload", D6_Wep.TrySpend(mortar, owner, 20)
    and F.Status(mortar).remaining == 0 and F.Status(mortar).reloadAt == now+2.4)
ok, reason = D6_Wep.TrySpend(mortar, owner, 20)
check("reload denial leaves both paid resources intact", not ok and reason == "reload"
    and owner:GetAmmoCount("d6_shell") == 2 and D6_Energy.Get(owner) == 60)
now = now+2.4
check("elapsed reload restores capacity but never reserve", F.Status(mortar).remaining == 2
    and F.Status(mortar).reloadAt == 0 and owner:GetAmmoCount("d6_shell") == 2)

local flakOwner = pilot()
local flak = weapon(flakOwner, "flak")
check("flak permits exactly two trigger cycles before a pause", D6_Wep.TrySpend(flak, flakOwner, 10)
    and D6_Wep.TrySpend(flak, flakOwner, 10) and not D6_Wep.TrySpend(flak, flakOwner, 10)
    and F.Status(flak).reloadAt == now+1.8 and D6_Energy.Get(flakOwner) == 80)
local plasmaOwner, plasma = pilot()
plasma = weapon(plasmaOwner, "plasma")
for _ = 1, 6 do assert(D6_Wep.TrySpend(plasma, plasmaOwner, 1)) end
check("plasma capacitor counts six trigger cycles", not D6_Wep.TrySpend(plasma, plasmaOwner, 1)
    and F.Status(plasma).reloadAt == now+1.7 and D6_Energy.Get(plasmaOwner) == 94)

local dry = pilot(0)
local mg = weapon(dry, "mg")
for _ = 1, 100 do assert(D6_Wep.TrySpend(mg, dry, 1)) end
check("Tier 1 MG remains usable at zero energy without cycling", D6_Energy.Get(dry) == 0
    and F.Status(mg).capacity == 0 and mg.D6_FeedState == nil)
local legacyOwner = pilot(10)
local legacy = weapon(legacyOwner, "legacy_test")
check("unlisted legacy weapons retain energy-only payment", D6_Wep.TrySpend(legacy, legacyOwner, 4)
    and D6_Energy.Get(legacyOwner) == 6 and F.Status(legacy) == nil)
check("a caller cannot spend another owner's weapon", not D6_Wep.TrySpend(mg, legacyOwner, 0)
    and D6_Energy.Get(legacyOwner) == 6)

local bfgOwner = pilot()
local bfg = weapon(bfgOwner, "bfg")
check("BFG initial grant is one finite cell", F.GrantInitial(bfgOwner, bfg:GetClass()) == 1
    and F.GrantInitial(bfgOwner, bfg:GetClass()) == 0)
check("BFG shot spends its cell", D6_Wep.TrySpend(bfg, bfgOwner, 80)
    and bfgOwner:GetAmmoCount("d6_bfg_cell") == 0)
now = now+3600
D6_Energy.RegenTick(bfgOwner, 3600)
ok, reason = D6_Wep.TrySpend(bfg, bfgOwner, 80)
check("waiting and full energy regeneration never regenerate BFG ammunition", not ok
    and reason == "ammo" and D6_Energy.Get(bfgOwner) == 100
    and F.Status(bfg).remaining == 1 and bfgOwner:GetAmmoCount("d6_bfg_cell") == 0)
check("ordinary supplies do not grant BFG cells", F.Restock(bfgOwner, false) == 0)
check("rare supplies cap BFG reserve at two", F.Restock(bfgOwner, true) == 1
    and F.Restock(bfgOwner, true) == 1 and F.Restock(bfgOwner, true) == 0
    and bfgOwner:GetAmmoCount("d6_bfg_cell") == 2)
local mineOwner = pilot()
local mine = weapon(mineOwner, "plasmamine")
local gravityMine = weapon(mineOwner, "gravmine")
check("two mine modules share one starting reserve", F.GrantInitial(mineOwner, mine:GetClass()) == 2
    and F.GrantInitial(mineOwner, gravityMine:GetClass()) == 0)
mineOwner.ammo.d6_mine = 0
check("common restock does not double-count shared mine ammunition", F.Restock(mineOwner, false) == 2
    and mineOwner:GetAmmoCount("d6_mine") == 2)
mineOwner.ammo.d6_mine = 5
check("common stock respects explicit cap regardless of engine maxcarry", F.Restock(mineOwner, false) == 1
    and mineOwner:GetAmmoCount("d6_mine") == 6 and F.Restock(mineOwner, false) == 0)
check("rare pickup does not refill mines or unowned BFG", F.Restock(mineOwner, true) == 0
    and mineOwner:GetAmmoCount("d6_bfg_cell") == 0)

-- Real rail charge/release code, with only world/trace/transport boundaries stubbed.
D6_Wep.ShootAng = function() return {Forward=function() return Vector(1, 0, 0) end} end
D6_Wep.MuzzleFor = function() return Vector() end
D6_Wep.CombatTrace = function(trace) return {Hit=false, HitPos=trace.endpos} end
D6_Wep.ApplyRecoil = function() end
D6_Wep.MarkShot = function() end
SWEP = {Primary={}, Secondary={}}
dofile(root .. "weapons/weapon_d6_railmk2.lua")
local railOwner = pilot()
local rail = weapon(railOwner, "railmk2", SWEP)
rail:Initialize()
F.GrantInitial(railOwner, rail:GetClass())
rail:PrimaryAttack()
check("rail charge reserves engine fire time", rail:GetNextPrimaryFire() == now+10)
now = now+0.61
rail:Think()
check("charged rail ignores its charging timestamp and pays one cell", railOwner:GetAmmoCount("d6_rail_cell") == 2
    and D6_Energy.Get(railOwner) == 65 and rail._ChargeStart == nil
    and rail:GetNextPrimaryFire() == now+1.5 and F.Status(rail).remaining == 0)
local reloadAt = F.Status(rail).reloadAt
rail:Holster(); rail:Deploy()
check("holster and deploy preserve paid reload and reserve", F.Status(rail).reloadAt == reloadAt
    and F.Status(rail).remaining == 0 and railOwner:GetAmmoCount("d6_rail_cell") == 2)
railOwner.ammo.d6_rail_cell = 0
check("rail lure can use energy while primary is empty and reloading", D6_Wep.TrySpend(rail, railOwner, 12, "rail_lure")
    and D6_Energy.Get(railOwner) == 53 and F.Status(rail).reloadAt == reloadAt)
check("rail primary cannot use the utility exemption implicitly", not D6_Wep.TrySpend(rail, railOwner, 18)
    and D6_Energy.Get(railOwner) == 53)
check("utility context cannot bypass another weapon's finite stock", not D6_Wep.TrySpend(bfg, bfgOwner, 0, "rail_lure")
    and bfgOwner:GetAmmoCount("d6_bfg_cell") == 2)

now = now+2
railOwner.ammo.d6_rail_cell = 3
railOwner:SetNWFloat("D6_Energy", 0)
rail:PrimaryAttack(); now = now+0.61; rail:Think()
check("failed charged payment releases the ten-second engine lock", rail._ChargeStart == nil
    and rail:GetNWFloat("D6_RailCharge", -1) == 0 and rail:GetNextPrimaryFire() == now+0.23
    and railOwner:GetAmmoCount("d6_rail_cell") == 3)
now = now+0.24
rail:PrimaryAttack(); railOwner.held = false; now = now+0.1; rail:Think()
check("failed quick-shot payment also releases the charging lock", rail._ChargeStart == nil
    and rail:GetNextPrimaryFire() == now+0.23 and railOwner:GetAmmoCount("d6_rail_cell") == 3)
now = now+0.24
railOwner.held = true
rail:PrimaryAttack(); rail:Holster()
check("holstering an unfinished charge cancels only the temporary lock", rail._ChargeStart == nil
    and rail:GetNextPrimaryFire() == now+0.23 and railOwner:GetAmmoCount("d6_rail_cell") == 3)

-- The actual secondary handler must pass the narrow utility context and avoid
-- paying for an absent prop, rather than merely testing the feed API in isolation.
railOwner:SetNWFloat("D6_Energy", 30); railOwner.ammo.d6_rail_cell = 0
local prop, physics = entity(), entity()
function prop:GetClass() return "prop_physics" end
function prop:GetPhysicsObject() return physics end
function prop:GetPos() return Vector(100, 0, 0) end
function physics:GetMass() return 100 end
function physics:EnableGravity(enabled) self.gravity = enabled end
function physics:SetVelocity(value) self.velocity = value end
function physics:Wake() end
ents = {FindInSphere=function() return {} end}
rail:SecondaryAttack()
check("lure with no valid prop spends no energy", D6_Energy.Get(railOwner) == 30)
now = now+0.24
ents.FindInSphere = function() return {prop} end
rail:SecondaryAttack()
check("real lure handler moves a prop without rail ammunition", D6_Energy.Get(railOwner) == 18
    and railOwner:GetAmmoCount("d6_rail_cell") == 0 and physics.velocity ~= nil)

local quickOwner = pilot()
local quickRail = weapon(quickOwner, "railmk2", SWEP)
quickRail:Initialize(); F.GrantInitial(quickOwner, quickRail:GetClass())
check("quick rail recovery includes the local cell cycle", quickRail:_DoQuickShot(quickOwner)
    and quickRail:GetNextPrimaryFire() == now+1.5 and quickOwner:GetAmmoCount("d6_rail_cell") == 2)
now = now+0.51
quickRail:PrimaryAttack()
check("quick shot cannot start another charge during its reload", quickRail._ChargeStart == nil)

SERVER, CLIENT = false, true
now = reloadAt-0.1
check("client status reads replicated cycle state", F.Status(rail).remaining == 0
    and F.Status(rail).reloadAt == reloadAt)
now = reloadAt+0.1
check("client status projects elapsed reload without changing server stock", F.Status(rail).remaining == 1
    and railOwner:GetAmmoCount("d6_rail_cell") == 0)
check("clients cannot pay, initialize or restock resources", not F.TrySpend(rail, railOwner, 0, "rail_lure")
    and F.GrantInitial(railOwner, rail:GetClass()) == 0 and F.Restock(railOwner, false) == 0)
print("weapon_feed_unit: " .. passed .. " checks passed")
