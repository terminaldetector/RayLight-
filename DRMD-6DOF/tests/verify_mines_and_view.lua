-- Run with: texlua tests/verify_mines_and_view.lua (from DRMD-6DOF).
-- Executes the real mine/input/view modules with a small engine boundary stub.
-- This verifies state and input contracts, not graphical appearance or physics.
local here = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "./"
local root = here .. "../descent_scanner/lua/"
local checks = 0
local function check(condition, message)
    assert(condition, message)
    checks = checks + 1
end

SERVER, CLIENT = true, false
local now = 10
function CurTime() return now end
function RealTime() return now end
function IsValid(value) return type(value) == "table" and value.valid ~= false end
function isfunction(value) return type(value) == "function" end
function AddCSLuaFile() end
function Color(r,g,b,a) return {r=r,g=g,b=b,a=a} end
function math.Clamp(value, low, high) return math.max(low, math.min(high, value)) end
local Vec = {}; Vec.__index = Vec
function Vector(x,y,z) return setmetatable({x=x,y=y,z=z}, Vec) end
function Vec.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function Vec.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function Vec.__mul(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
function Vec:Length() return math.sqrt(self.x*self.x+self.y*self.y+self.z*self.z) end
function Vec:GetNormalized() local n=self:Length(); return n > 0 and self*(1/n) or Vector(0,0,0) end
vector_origin = Vector(0,0,0)
local function basis(forward,right,up)
    return {Forward=function() return forward end, Right=function() return right end, Up=function() return up end}
end
local angles = basis(Vector(1,0,0),Vector(0,1,0),Vector(0,0,1))
local hooks, commands, receivers, timers = {}, {}, {}, {}
hook = {Add=function(_,name,fn) hooks[name]=fn end}
concommand = {Add=function(name,fn) commands[name]=fn end}
net = {Receive=function(name,fn) receivers[name]=fn end}
util = {AddNetworkString=function() end, PrecacheSound=function() end}
timer = {
    Create=function(name,_,_,fn) timers[name]=fn end,
    Remove=function(name) timers[name]=nil end,
    Simple=function() end,
}
D6_DAMAGE = {energy={dmgType=1}, exotic={dmgType=2}}
local selected = "weapon_d6_plasmamine"
D6_Arsenal = {
    Entries={weapon_d6_plasmamine={family="mine"}, weapon_d6_gravmine={family="mine"}, invalid={family="pulse"}},
    Get=function(_,slot) check(slot==5,"mine query must use bay 5"); return selected end,
}
local entities, failedSpawn, blocked, spends = {}, false, false, 0
local nextId = 0
local function ordnance(_,pos)
    if failedSpawn then return nil end
    nextId=nextId+1
    local ent={id=nextId,pos=pos,callbacks={}}
    function ent:EntIndex() return self.id end
    function ent:GetPos() return self.pos end
    function ent:EmitSound() end
    function ent:SetNWBool() end
    function ent:CallOnRemove(name,fn) self.callbacks[name]=fn end
    function ent:Remove()
        if self.valid == false then return end
        for _,fn in pairs(self.callbacks) do fn(self) end
        self.valid=false
    end
    entities[#entities+1]=ent
    return ent
end
D6_Wep = {
    ShootAng=function() return angles end, AimAng=function() return angles end,
    Muzzle=function() return Vector(0,0,0) end,
    DeployPoint=function(_,point) if not blocked then return point end end,
    Ordnance=ordnance, MarkShot=function() end,
    TrySpend=function(wep,owner,cost)
        spends=spends+1
        if owner.energy < cost or owner.ammo < 1 then wep:SetNextPrimaryFire(now+0.23); return false end
        owner.energy,owner.ammo=owner.energy-cost,owner.ammo-1
        return true
    end,
}

local function loadWeapon(name)
    SWEP={Primary={},Secondary={}}
    dofile(root .. "weapons/weapon_d6_" .. name .. ".lua")
    return SWEP
end
local plasma, gravity = loadWeapon("plasmamine"), loadWeapon("gravmine")
local function pilot()
    local ply={D6On=true,energy=1000,ammo=30,alive=true,inventory={}}
    function ply:IsPlayer() return true end
    function ply:Alive() return self.alive end
    function ply:InVehicle() return self.vehicle or false end
    function ply:GetNWBool() return self.D6On end
    function ply:IsTyping() return self.typing or false end
    function ply:GetWeapon(class) return self.inventory[class] end
    function ply:GetActiveWeapon() return self.active end
    function ply:SelectWeapon() error("mine drop changed active weapon") end
    function ply:EmitSound() end
    local function weapon(proto,class)
        local w=setmetatable({next=0,owner=ply,nw={},class=class},{__index=proto})
        function w:GetOwner() return self.owner end
        function w:GetClass() return self.class end
        function w:GetNextPrimaryFire() return self.next end
        function w:SetNextPrimaryFire(t) self.next=t end
        function w:SetNWInt(key,value) self.nw[key]=value end
        function w:SetWeaponHoldType() end
        w:Initialize()
        ply.inventory[class]=w
        return w
    end
    ply.plasma=weapon(plasma,"weapon_d6_plasmamine")
    ply.gravity=weapon(gravity,"weapon_d6_gravmine")
    ply.active={GetClass=function() return "weapon_d6_gravy_railgun" end,HeldEnt={}}
    return ply
end
dofile(root .. "d6_aux_mines.lua")
local ply=pilot()
local active,heldProp=ply.active,ply.active.HeldEnt
check(D6_Mines.TryDeploy(ply),"selected mine should deploy")
check(ply.energy==975 and ply.ammo==29 and spends==1,"one successful drop spends once")
check(ply.active==active and active.HeldEnt==heldProp,"rail and held prop must remain active")
check(not D6_Mines.TryDeploy(ply) and not ply.plasma:PrimaryAttack(),"command/primary repetition must respect cooldown")
check(not ply.gravity:DeployMine(),"changing mine type must not bypass bay cooldown")
now=now+1.01
selected="weapon_d6_gravmine"
check(D6_Mines.TryDeploy(ply),"selected gravity variant should deploy after bay cooldown")
check(entities[#entities].D6_WeaponClass==selected,"mine damage retains originating weapon class")
local energy,ammo=ply.energy,ply.ammo
ply.D6On=false; now=now+2
check(not D6_Mines.TryDeploy(ply),"auxiliary fire requires server flight state")
ply.D6On=true; ply.alive=false
check(not D6_Mines.TryDeploy(ply),"dead owner cannot use mine bay")
ply.alive=true; ply.vehicle=true
check(not D6_Mines.TryDeploy(ply),"vehicle input must not drop mines")
ply.vehicle=false; selected="invalid"
check(not D6_Mines.TryDeploy(ply),"non-mine class rejected")
check(ply.energy==energy and ply.ammo==ammo,"rejected requests do not spend")

ply=pilot(); selected="weapon_d6_plasmamine"; now=now+1
failedSpawn=true; energy,ammo,spends=ply.energy,ply.ammo,0
check(not D6_Mines.TryDeploy(ply),"failed entity creation returns failure")
check(ply.energy==energy and ply.ammo==ammo and spends==0,"spawn failure spends no stock, feed or energy")
failedSpawn=false; now=now+1; ply.ammo=0
check(not D6_Mines.TryDeploy(ply),"empty finite mine stock rejected")
check(entities[#entities].valid==false and ply.energy==energy,"denied payment removes tentative ordnance")
now=now+1; ply.ammo=20; blocked=true; spends=0
check(not D6_Mines.TryDeploy(ply) and spends==0,"blocked placement does not spend")
blocked=false; now=now+1
local first
for i=1,5 do
    check(D6_Mines.TryDeploy(ply),"valid repeated mine deployment after cooldown")
    first=first or entities[#entities]
    now=now+2
end
check(not IsValid(first) and ply.plasma.nw.D6_Deployed==4,"active mine cap removes oldest and preserves count")
check(timers["D6_PMine_"..first:EntIndex()]==nil,"removed mine polling timer is cancelled")
entities[#entities]:Remove()
check(ply.plasma.nw.D6_Deployed==3,"removed mine updates live bay count")

-- Client input is exercised via Think, including SP's absent PlayerButtonDown.
SERVER,CLIENT=false,true
KEY_C,KEY_LAST=13,106
local code=KEY_C
function CreateClientConVar() return {GetInt=function() return code end} end
function LocalPlayer() return ply end
local keys,ui={},{}
local boundKey
input={IsKeyDown=function(k) return keys[k] or false end,
    LookupBinding=function(name) if name=="+d6_mine" then return boundKey end end,
    GetKeyName=function(k) if k==KEY_C then return "c" end end}
gui={IsGameUIVisible=function() return ui.game end,IsConsoleVisible=function() return ui.console end}
vgui={CursorVisible=function() return ui.cursor end,GetKeyboardFocus=function() return ui.focus end}
system={HasFocus=function() return not ui.unfocused end}
local requests=0
net.Start=function(name) check(name=="D6_MineDrop","input uses dedicated message") end
net.SendToServer=function() requests=requests+1 end
dofile(root .. "d6_aux_mines.lua")
check(D6_Mines.KeyLabel()=="C","HUD shows default mine shortcut")
boundKey="g"
check(D6_Mines.KeyLabel()=="G","HUD shows explicit mine rebind")
boundKey=nil
local function step(down)
    keys[KEY_C]=down
    now=now+0.2
    hooks.D6_MineShortcut()
end
check(hooks.D6_MineContextShortcut(ply,"+menu_context",true,KEY_C)==true,"C suppresses context menu only while eligible")
check(hooks.D6_MineContextShortcut(ply,"+menu_context",true,99)==nil,"other context binding retained")
step(true); step(true)
check(requests==1,"holding C sends one drop")
step(false); ui.cursor=true; step(true)
ui.cursor=false; step(true)
check(requests==1,"closing a menu with C held must not deploy")
step(false); step(true)
check(requests==2,"new press after menu works")
step(false); hooks.D6_MineChatStart(); step(true)
check(requests==2,"chat blocks C")
hooks.D6_MineChatFinish(); step(false)
ui.focus={}; step(true)
check(requests==2,"keyboard-focused text input blocks C")
ui.focus=nil; step(false); ply.D6On=false; step(true)
check(requests==2 and hooks.D6_MineContextShortcut(ply,"+menu_context",true,KEY_C)==nil,"normal on-foot context bind preserved")
ply.D6On=true; step(false); code=0
check(D6_Mines.KeyLabel()=="—","HUD marks disabled unbound mine action")
commands["+d6_mine"](); step(false); step(false)
check(requests==3,"explicit rebind works with default shortcut disabled and does not repeat")
commands["-d6_mine"](); step(false)
commands.d6_mine_drop()
check(requests==4,"one-shot bind invokes same guarded path")

-- All four records retain their own weapon state. Projection follows full roll.
dofile(root .. "d6_view_mounts.lua")
local inventory,slots={},{}
for i=1,4 do
    slots[i]="module"..i
    inventory[slots[i]]={GetClass=function() return slots[i] end,charge=i*.1}
end
ply.inventory=inventory; ply.active=inventory.module4
local arsenal={Get=function(_,slot) return slots[slot] end,Entries={}}
for _,class in ipairs(slots) do arsenal.Entries[class]={class=class} end
local mounts=D6_ViewMounts.Collect(ply,arsenal,function() return false end)
check(#mounts==4,"all four mounts displayed simultaneously")
for i,mount in ipairs(mounts) do
    check(mount.weapon==inventory[slots[i]] and mount.slot==i,"mount uses its own equipped weapon state")
end
local origin=Vector(0,0,0)
local left=D6_ViewMounts.Pose(origin,angles,1,16/9)
local right=D6_ViewMounts.Pose(origin,angles,2,16/9)
local upper=D6_ViewMounts.Pose(origin,angles,3,16/9)
local lower=D6_ViewMounts.Pose(origin,angles,4,16/9)
check(left.y<0 and right.y>0 and upper.z>0 and lower.z<0,"view layout preserves four sides")
local rolled=basis(Vector(1,0,0),Vector(0,0,-1),Vector(0,1,0))
local rotated=D6_ViewMounts.Pose(origin,rolled,3,16/9)
check(rotated.y==upper.z and rotated.z==0,"upper mount rotates with camera roll")
local wide=D6_ViewMounts.Pose(origin,angles,3,21/9)
check(wide.z>0 and wide.z<upper.z,"ultrawide projection brings upper mount inward")
local overrides=D6_ViewMounts.Collect(ply,arsenal,function() return true end)
check(#overrides==4 and overrides[4].customActive and not overrides[1].customActive,"SCK active override does not discard other mounts")
print(string.format("PASS: %d mine/input/view contract checks (engine boundary stubs; no graphical playtest).",checks))
