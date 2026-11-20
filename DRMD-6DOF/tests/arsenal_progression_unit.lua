-- Run from tests/: texlua arsenal_progression_unit.lua
-- Real catalogue/loadout/supply code; engine inventory and persistence are stubs.
SERVER, CLIENT = true, false
local root = "../descent_scanner/lua/"
local checks = 0
local function check(name, value)
    assert(value, name)
    checks = checks + 1
    print("PASS | " .. name)
end
function IsValid(value) return type(value)=="table" and value.valid==true end
function Color(...) return {...} end
function AddCSLuaFile() end
hook = {Add=function() end}
concommand = {Add=function() end}
D6_Session = {IsArena=function() return true end}
dofile(root .. "d6_arsenal.lua")
dofile(root .. "d6_weapon_feed.lua")
dofile(root .. "d6_loadout.lua")
dofile(root .. "d6_supplies.lua")
local A, F, S = D6_Arsenal, D6_WeaponFeed, D6_Supplies

local function pilot(saved)
    local p={valid=true, weapons={}, ammo={}, nw={}, D6_Mounts=A.Normalize(saved)}
    function p:IsPlayer() return true end
    function p:GetWeapon(class) return self.weapons[class] end
    function p:HasWeapon(class) return IsValid(self:GetWeapon(class)) end
    function p:GetWeapons()
        local result={}
        for _, weapon in pairs(self.weapons) do result[#result+1]=weapon end
        return result
    end
    function p:Give(class)
        local w={valid=true}
        function w:GetClass() return class end
        function w:GetOwner() return p end
        self.weapons[class]=w
        return w
    end
    function p:GetAmmoCount(ammo) return self.ammo[ammo] or 0 end
    function p:GiveAmmo(count, ammo)
        self.ammo[ammo]=self:GetAmmoCount(ammo)+count
        return count
    end
    function p:SetNW2String(key,value) self.nw[key]=value end
    function p:GetNW2String(key,default) return self.nw[key] or default end
    return p
end

check("catalogue has ten mounts and two mine payloads", #A.Order==12)
local mounts, mines=0,0
for _,item in ipairs(A.Order) do
    if A.CanMount(item.class) then mounts=mounts+1 end
    if A.CanMine(item.class) then mines=mines+1 end
end
check("mine payloads do not consume a main mount", mounts==10 and mines==2)
check("old source definitions remain addressable but unavailable as mounts",
    A.Entries.weapon_d6_hyperbeam and not A.CanMount("weapon_d6_hyperbeam"))
local migrated=A.Normalize({"weapon_d6_vulcan","weapon_d6_laser","weapon_d6_homing",
    "weapon_d6_homing","weapon_d6_darkfield"})
local seen={}
for i=1,4 do check("migrated slot "..i.." is playable and unique", A.CanMount(migrated[i]) and not seen[migrated[i]]);seen[migrated[i]]=true end
check("saved mine variant survives migration", migrated[5]=="weapon_d6_gravmine")
check("old mount and old reward have distinct intended migrations",
    A.ResolveClass("weapon_d6_hyperbeam")=="weapon_d6_plasma"
    and A.ResolveRewardClass("weapon_d6_hyperbeam")=="weapon_d6_bfg")
check("unknown classes never become rewards", A.ResolveRewardClass("weapon_unknown")==nil)

local p=pilot({"weapon_d6_bfg",nil,nil,nil,"weapon_d6_gravmine"})
check("fresh flight receives only five starter systems", D6_Session.GiveLoadout(p)==5)
check("saving an unowned BFG cannot unlock it", not p:HasWeapon("weapon_d6_bfg") and A.Get(p,1)~="weapon_d6_bfg")
check("starter finite reserves are supplied", p:GetAmmoCount("d6_shell")==4 and p:GetAmmoCount("d6_mine")==2)
p.ammo.d6_shell, p.ammo.d6_mine=0,0
check("repeat flight does not duplicate equipment", D6_Session.GiveLoadout(p)==0)
check("repeat flight cannot refill empty reserves", p:GetAmmoCount("d6_shell")==0 and p:GetAmmoCount("d6_mine")==0)
check("all three early module choices can be earned", #A.AvailableRewards(p,1)==3)
check("late draft can offer all seven nonstarter systems", #A.AvailableRewards(p,3)==7)
p.D6_EpisodeUnlocks={weapon_d6_homing=true,weapon_not_real=true}
check("old earned weapon migrates to the single rocket platform", D6_Session.GiveLoadout(p)==1 and p:HasWeapon("weapon_d6_rockets"))
check("unknown unlock does not survive normalization", p.D6_EpisodeUnlocks.weapon_not_real==nil)
check("owned rewards leave the draft pool", #A.AvailableRewards(p,1)==2)

local result=S.Collect({D6_Payload="module",D6_Module="weapon_d6_hyperbeam"},p)
check("legacy episode reward gives a new BFG", result and p:HasWeapon("weapon_d6_bfg") and p.D6_EpisodeUnlocks.weapon_d6_bfg)
check("new BFG receives one finite starting cell", p:GetAmmoCount("d6_bfg_cell")==1)
check("duplicate module pickup does not refill cells", S.Collect({D6_Payload="module",D6_Module="weapon_d6_hyperbeam"},p)==nil and p:GetAmmoCount("d6_bfg_cell")==1)
p.ammo.d6_bfg_cell=0
check("common supply fills owned ordinary reserves", S.Collect({D6_Payload="ammo"},p)~=nil and p:GetAmmoCount("d6_shell")==4)
check("common supply never adds a BFG cell", p:GetAmmoCount("d6_bfg_cell")==0)
check("rare supply gives exactly one BFG cell", S.Collect({D6_Payload="core"},p)~=nil and p:GetAmmoCount("d6_bfg_cell")==1)
S.Collect({D6_Payload="core"},p)
check("rare supply remains on the map when reserve is full", S.Collect({D6_Payload="core"},p)==nil and p:GetAmmoCount("d6_bfg_cell")==2)
S.Collect({D6_Payload="module",D6_Module="weapon_d6_gravmine"},p)
p.ammo.d6_mine=0
F.Restock(p,false)
check("two mine variants share one refill pack", p:GetAmmoCount("d6_mine")==2)
check("selected mine is persistent configuration", A.AssignMine(p.D6_Mounts,"weapon_d6_gravmine") and A.Normalize(p.D6_Mounts)[5]=="weapon_d6_gravmine")

D6_Session.GiveLoadout(p,true)
local count=0
for _,item in ipairs(A.Order) do if p:HasWeapon(item.class) then count=count+1 end end
check("explicit debug give exposes all twelve curated systems", count==12)
check("debug give does not resurrect retired duplicates", not p:HasWeapon("weapon_d6_hyperbeam") and not p:HasWeapon("weapon_d6_homing"))
check("debug ammo respects explicit limits", p:GetAmmoCount("d6_bfg_cell")==2 and p:GetAmmoCount("d6_mine")==6)
print("COMPLETE | "..checks.." catalogue/progression/supply checks; native engine not exercised")
