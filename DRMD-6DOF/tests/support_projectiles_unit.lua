-- texlua tests/support_projectiles_unit.lua, from DRMD-6DOF.
-- Executes the real segment arbiter, projectile constructor and rail SWEP at
-- mocked engine boundaries. Native physics/render/network need GMod playtests.
local here = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "./"
local root, passed = here .. "../descent_scanner/lua/", 0
local function check(ok, message) assert(ok, message); passed = passed + 1 end
local function near(a,b) return math.abs(a-b) < 0.00001 end
SERVER, CLIENT = true, false
MASK_SHOT, DMG_BULLET, COLLISION_GROUP_PROJECTILE = 1, 2, 3
RENDERMODE_TRANSADD, RENDERMODE_NORMAL = 4, 5
function IsValid(v) return type(v)=="table" and v.valid==true end
function AddCSLuaFile() end
function CurTime() return 10 end
function Color(...) return {...} end
function math.Clamp(v,a,b) return math.max(a,math.min(b,v)) end
local Vec = {}; Vec.__index = Vec
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},Vec) end
function Vec.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function Vec.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function Vec.__mul(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
function Vec.__unm(a) return a*-1 end
function Vec:Dot(b) return self.x*b.x+self.y*b.y+self.z*b.z end
function Vec:LengthSqr() return self:Dot(self) end
function Vec:Length() return math.sqrt(self:LengthSqr()) end
function Vec:GetNormalized() local l=self:Length(); return l>0 and self*(1/l) or Vector() end
function Vec:DistToSqr(b) return (self-b):LengthSqr() end
function Vec:Angle() return {direction=self} end
vector_origin = Vector()
local function same(a,b) return (a-b):LengthSqr()<0.00001 end
local timers, vectors = {}, {}
timer = {Simple=function(_,fn) timers[#timers+1]=fn end}
local function flush() local queued=timers; timers={}; for _,fn in ipairs(queued) do fn() end end
net = {Start=function() vectors={} end,WriteVector=function(v) vectors[#vectors+1]=v end,
    WriteBool=function() end,WriteFloat=function() end,Broadcast=function() end}
util = {AddNetworkString=function() end,IsValidModel=function() return false end,
    SpriteTrail=function() end,Effect=function() end}
function EffectData() return {SetOrigin=function() end,SetNormal=function() end,SetMagnitude=function() end} end
local world={valid=true,GetClass=function() return "worldspawn" end,
    GetPhysicsObject=function() return nil end,IsNPC=function() return false end,IsPlayer=function() return false end}
game={GetWorld=function() return world end}
local nativeHits=0
local function projectile()
    local e={valid=true,pos=Vector(),impacts=0}
    local body={valid=true,velocity=Vector(30,40,50)}
    function body:GetVelocity() return self.velocity end
    function body:SetVelocity(v) self.velocity=v end
    function body:Wake() end
    function body:EnableGravity() end
    function body:EnableDrag() end
    function body:SetMass() end
    function e:GetPhysicsObject() return body end
    function e:GetVelocity() return body.velocity end
    function e:SetPos(p) self.pos=p end
    function e:GetPos() return self.pos end
    function e:SetAngles(a) self.angles=a end
    function e:SetOwner(o) self.owner=o end
    function e:GetOwner() return self.owner end
    function e:Spawn() end
    function e:SetCollisionGroup() end
    function e:SetRenderMode() end
    function e:SetNW2Bool() end
    function e:SetNWFloat() end
    function e:SetColor() end
    function e:Remove() self.valid=false end
    e.D6_Impact=function(entity,pos) e.impacts=e.impacts+1; e.hit=entity; e.hitPos=pos end
    return e, body
end
ents={Create=function() return projectile() end}
function D6_TrackProjectile(e,_,callback,_,swept)
    e.D6_IsProjectile=true
    e.D6_Impact=function(hit,pos,normal) nativeHits=nativeHits+1; callback(e,hit,pos,normal) end
    if not swept then
        e.D6_PhysicsImpact=function(_,data) e.D6_Impact(data.HitEntity,data.HitPos,data.HitNormal) end
    end
end
local file=assert(io.open(root.."d6_weapon_core.lua","r"))
local core=file:read("*a");file:close()
D6_Wep={Recoil=function() return 1 end,Inherit=function() return 1 end,
    ShipVel=function() return Vector() end,DmgClass=function() return {} end,
    TagProjectile=function() end,MarkShot=function() end}
local step=assert(core:match('(function D6_Wep.StepProjectile.-)\n    hook.Add%("Tick", "D6_ProjectileSweep"'))
assert(load(step,"@d6_weapon_core.lua:StepProjectile"))()
local recoil=assert(core:match('(function D6_Wep.ApplyRecoil.-)\n%-%- ═'))
assert(load(recoil,"@d6_weapon_core.lua:ApplyRecoil"))()
local fire=assert(core:match('(function D6_Wep.FireProjectile.-)\n    %-%- ── Хелперы'))
-- Constructor dependencies are the same upvalues it has in the real module.
assert(load("local tracked,shotMesh={},{}\n"..fire,"@d6_weapon_core.lua:FireProjectile"))()
D6_Arsenal={NativeModel=function() return "models/test.mdl" end}

local wallFraction, portalFraction, supportFraction, mode = 1, nil, nil, nil
local queried,handled,gates=0,0,{}
local supportPos, portalPos=Vector(2,0,0),Vector(90,80,70)
D6_Wep.CombatTrace=function(data)
    return {Fraction=wallFraction,Hit=wallFraction<1,Entity=wallFraction<1 and world or nil,
        HitPos=data.start+(data.endpos-data.start)*wallFraction,HitNormal=Vector(-1,0,0)}
end
D6_Gates={MoveShot=function(_,_,_,_,velocity,limit)
    gates[#gates+1]=limit
    if portalFraction and portalFraction<limit then return portalPos,Vector(0,velocity:Length(),0) end
end}
local supports={}
function supports.TraceProjectile(_,_,_,_,limit)
    queried=queried+1
    if supportFraction and supportFraction<limit then
        return {fraction=supportFraction,pos=supportPos,support={valid=true}}
    end
end
function supports.HandleProjectile()
    handled=handled+1
    if mode=="consume" then return {kind="consume"} end
    if mode=="redirect" then return {kind="redirect",pos=supportPos,velocity=Vector(0,0,9999)} end
end
local function state(velocity)
    return {last=Vector(),velocity=velocity,extents=Vector(3,3,3),filter=function() return true end}
end
local function reset()
    wallFraction,portalFraction,supportFraction,mode=1,nil,nil,nil
    queried,handled,gates=0,0,{}
    D6_Supports=supports
end
reset()
local e,body=projectile();local s=state(Vector(30,40,50));D6_Supports=nil
check(D6_Wep.StepProjectile(e,s,.1)=="move" and same(e.pos,Vector(3,4,5)),"absent supports preserve native swept advance")
check(e.impacts==0,"unobstructed movement does not impact")
reset();wallFraction=.3;supportFraction=.7;portalFraction=.6
e=projectile();s=state(Vector(100,0,0))
check(D6_Wep.StepProjectile(e,s,.1)=="impact" and e.hit==world,"map before support and portal wins")
check(handled==0 and gates[1]==.3,"wall fraction bounds all auxiliary interception")
reset();wallFraction=.9;supportFraction=.4;portalFraction=.2;mode="consume"
e=projectile();s=state(Vector(30,40,50))
check(D6_Wep.StepProjectile(e,s,.1)=="portal" and same(e.pos,portalPos),"portal before support wins")
check(handled==0 and near(gates[1],.4),"earlier portal does not spend support capacity")
reset();supportFraction=.2;portalFraction=.6;mode="consume"
e=projectile();s=state(Vector(30,40,50))
check(D6_Wep.StepProjectile(e,s,.1)=="consume" and not IsValid(e),"support before portal absorbs round")
check(e.impacts==0 and e.D6_Impact==nil and e.D6_PhysicsImpact==nil,"absorbed explosive cannot also run damage callback")
reset();supportFraction=.2;mode="redirect"
e=projectile();e.owner={valid=true};e.damage=25;s=state(Vector(30,40,50))
local originalOwner=e.owner
s.steer=function(_,_,v) return v end
check(D6_Wep.StepProjectile(e,s,.1)=="redirect","reflection redirects real projectile")
check(near(s.velocity:Length(),math.sqrt(5000)) and same(s.velocity:GetNormalized(),Vector(0,0,1)),"redirect preserves speed in 3D even if callback requests larger speed")
check(s.steer==nil and e.D6_SupportReflected==true,"redirect clears homing and records one-reflection flag")
check(same(s.last,e.pos) and e.owner==originalOwner and e.damage==25,"redirect synchronizes position without cloning damage or owner")
reset();supportFraction=.2;portalFraction=.6
e=projectile();s=state(Vector(30,40,50))
check(D6_Wep.StepProjectile(e,s,.1)=="portal" and #gates==2,"denied support preserves farther portal crossing")
check(handled==1 and same(e.pos,portalPos),"denied support handled only once")
reset();supportFraction=.2;mode="redirect"
e,body=projectile();e.pos=Vector(3,4,5);s=state(nil)
check(D6_Wep.StepProjectile(e,s,.1)=="redirect" and s.velocity==nil,"physical projectile retains physical integration")
check(near(body.velocity:Length(),math.sqrt(5000)) and same(body.velocity:GetNormalized(),Vector(0,0,1)),"physical body receives conserved redirected velocity")
reset();e=projectile();s=state(Vector(10,0,0));e.D6_SupportImpactPending=true
check(D6_Wep.StepProjectile(e,s,.1)==nil and queried==0 and same(e.pos,Vector()),"pending physics interception cannot race Tick")

-- Constructor metadata must never impersonate the pilot's active weapon.
local activeQueries=0
local owner={valid=true,D6On=true,D6Vel=Vector()}
function owner:IsPlayer() return true end
function owner:GetActiveWeapon() activeQueries=activeQueries+1; return {valid=true,GetClass=function() return "weapon_d6_bfg" end} end
function owner:GetShootPos() return Vector() end
function owner:EmitSound() end
reset()
local sourceSupport={valid=true}
local taggedOwner,taggedClass
supports.TagProjectile=function(shot,who) taggedOwner,taggedClass=who,shot.D6_WeaponClass end
local cfg={owner=owner,pos=Vector(),dir=Vector(1,0,0),speed=100,dmgClass="kinetic",sourceSupport=sourceSupport,swept=true}
e=D6_Wep.FireProjectile(cfg)
check(e.D6_SourceSupport==sourceSupport and e.D6_SupportShot,"support origin preserved on projectile")
check(activeQueries==0 and e.D6_WeaponClass=="d6_support","support projectile has neutral identity instead of active BFG")
check(taggedOwner==owner and taggedClass=="d6_support","hostility snapshot receives shooter and finalized weapon identity")
local supportShot=e
cfg.sourceSupport=nil;e=D6_Wep.FireProjectile(cfg)
check(activeQueries==1 and e.D6_WeaponClass=="weapon_d6_bfg","ordinary projectile retains weapon fallback identity")
local oldActive=owner.GetActiveWeapon
local activeClass="weapon_d6_bfg"
owner.GetActiveWeapon=function() return {valid=true,GetClass=function() return activeClass end} end
D6_Arsenal.Operating={weapon_d6_bfg={tier=3},weapon_d6_mg={tier=1}}
D6_Session={IsArena=function() return true end}
dofile(root.."d6_combat_balance.lua")
local damageTarget={D6_Variant="heavy"}
check(D6_Balance.Damage(owner,supportShot,damageTarget,65)==65,"support damage ignores active Tier 3 penalty")
activeClass="weapon_d6_mg"
check(D6_Balance.Damage(owner,supportShot,damageTarget,65)==65,"support damage ignores active Tier 1 bonus")
owner.GetActiveWeapon=oldActive

-- A native contact is deferred before support mutation and uses pre-bounce speed.
reset();supportFraction=.25;mode="redirect";cfg.swept=false
e=D6_Wep.FireProjectile(cfg);body=e:GetPhysicsObject();body.velocity=Vector(-1,0,0)
e.D6_PhysicsImpact(e,{HitEntity=world,HitPos=Vector(20,0,0),HitNormal=Vector(-1,0,0),OurOldVelocity=Vector(100,0,0)})
check(e.D6_SupportImpactPending and nativeHits==0 and body.velocity.x==-1,"PhysicsCollide defers both movement and native damage")
flush()
check(not e.D6_SupportImpactPending and e.D6_SupportReflected,"deferred physical contact reaches same arbiter")
check(near(body.velocity:Length(),100) and nativeHits==0,"reflection retains pre-collision speed and suppresses native contact")

-- Granada's recoil is physical, including vertical aim, and stays server-owned.
owner.D6Vel=Vector(10,20,30)
D6_Wep.ApplyRecoil(owner,Vector(0,0,1),150)
check(same(owner.D6Vel,Vector(10,20,-120)),"upward heavy shot accelerates hull downward")
D6_Wep.ApplyRecoil(owner,Vector(-1,0,0),90)
check(same(owner.D6Vel,Vector(100,20,-120)),"rearward quick shot accelerates hull forward")
SERVER=false;local old=owner.D6Vel;D6_Wep.ApplyRecoil(owner,Vector(1,0,0),90)
check(same(owner.D6Vel,old),"client cannot apply second physical impulse")
SERVER=true

-- Run the actual rail methods: payment happens before any trigger, and a
-- resonator terminates penetration without damaging targets behind it.
local paid,spends,railTriggers,damageCalls,traceCount=true,0,0,0,0
local railFraction,railAfter=0.2,0
D6_Wep.TrySpend=function() spends=spends+1;return paid end
D6_Wep.MarkShot=function() end
D6_Wep.ShootAng=function() return {Forward=function() return Vector(1,0,0) end} end
D6_Wep.MuzzleFor=function() return Vector() end
D6_Wep.DirectDamage=function() damageCalls=damageCalls+1 end
local enemy={valid=true,GetClass=function() return "d6_combat_drone" end,
    IsNPC=function() return true end,GetPhysicsObject=function() return nil end}
D6_Wep.CombatTrace=function(data)
    traceCount=traceCount+1
    local entity=traceCount<=railAfter and enemy or world
    return {Fraction=.7,Hit=true,Entity=entity,HitPos=data.start+(data.endpos-data.start)*.7,HitNormal=Vector(-1,0,0)}
end
D6_Supports={TraceRail=function(_,from,to,limit)
    if traceCount>railAfter and railFraction<limit then return {fraction=railFraction,pos=from+(to-from)*railFraction} end
end,HitRail=function() railTriggers=railTriggers+1;return true end}
SWEP={Primary={},Secondary={}}
dofile(root.."weapons/weapon_d6_railmk2.lua")
local rail=setmetatable({valid=true,next=0},{__index=SWEP})
function rail:GetClass() return "weapon_d6_railmk2" end
function rail:SetNextPrimaryFire(value) self.next=value end
function rail:GetNextPrimaryFire() return self.next end
paid=false
check(not rail:_DoQuickShot(owner) and spends==1 and traceCount==0 and railTriggers==0,"unpaid rail cannot trigger resonator")
paid=true;spends=0
check(rail:_DoQuickShot(owner) and spends==1 and railTriggers==1,"paid quick rail triggers resonator once")
check(damageCalls==0 and near(vectors[2].x,1600),"quick beam ends at resonator and does not hit world behind it")
traceCount,railTriggers,spends,damageCalls=0,0,0,0;railAfter=1
check(rail:_DoChargedShot(owner) and spends==1,"charged rail spends its finite shot once")
check(traceCount==2 and railTriggers==1 and damageCalls==1,"charged penetration hits earlier enemy then stops at resonator")
traceCount,railTriggers,spends=0,0,0;railAfter=0;railFraction=.9
check(rail:_DoQuickShot(owner) and railTriggers==0 and near(vectors[2].x,5600),"world obstruction prevents resonator trigger behind wall")
print("PASS | support projectile/rail boundary checks: "..passed)
