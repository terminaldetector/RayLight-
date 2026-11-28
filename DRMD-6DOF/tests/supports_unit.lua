-- texlua supports_unit.lua [path/to/lua/]
-- Executes the real support manager. Engine entities, delivery and traces are
-- mocked at the boundary; actual GMod physics/rendering still require a live run.
local root=arg[1] or "../descent_scanner/lua/"
local passed,now=0,100
local function check(label,ok)
    assert(ok,label); passed=passed+1; print("PASS | "..label)
end
SERVER,CLIENT=true,false
D_HT,D_LI,MASK_SOLID,MASK_SHOT,HUD_PRINTTALK=1,3,1,2,1
function CurTime() return now end
function IsValid(value) return type(value)=="table" and value.valid==true end
function Color(r,g,b,a) return {r=r,g=g,b=b,a=a or 255} end
math.Clamp=function(n,lo,hi) return math.max(lo,math.min(n,hi)) end
local vec={};vec.__index=vec
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},vec) end
function vec.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function vec.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function vec.__mul(a,b) return Vector(a.x*b,a.y*b,a.z*b) end
function vec.__unm(a) return a*-1 end
function vec:Dot(other) return self.x*other.x+self.y*other.y+self.z*other.z end
function vec:LengthSqr() return self:Dot(self) end
function vec:Length() return math.sqrt(self:LengthSqr()) end
function vec:GetNormalized() local l=self:Length();return l>0 and self*(1/l) or Vector() end
function vec:DistToSqr(other) return (self-other):LengthSqr() end
function vec:Distance(other) return (self-other):Length() end
function LerpVector(f,a,b) return a+(b-a)*f end
local ang={};ang.__index=ang
function Angle(p,y,r) return setmetatable({p=p or 0,y=y or 0,r=r or 0},ang) end
function ang:Forward()
    local p,y=math.rad(self.p),math.rad(self.y)
    return Vector(math.cos(p)*math.cos(y),math.cos(p)*math.sin(y),-math.sin(p))
end
function ang:Right()
    local p,y,r=math.rad(self.p),math.rad(self.y),math.rad(self.r)
    return Vector(-math.sin(r)*math.sin(p)*math.cos(y)+math.cos(r)*math.sin(y),
        -math.sin(r)*math.sin(p)*math.sin(y)-math.cos(r)*math.cos(y),-math.sin(r)*math.cos(p))
end
function ang:Up()
    local p,y,r=math.rad(self.p),math.rad(self.y),math.rad(self.r)
    return Vector(math.cos(r)*math.sin(p)*math.cos(y)+math.sin(r)*math.sin(y),
        math.cos(r)*math.sin(p)*math.sin(y)-math.sin(r)*math.cos(y),math.cos(r)*math.cos(p))
end
function vec:Angle() return Angle(math.deg(math.atan(-self.z,math.sqrt(self.x*self.x+self.y*self.y))),math.deg(math.atan(self.y,self.x)),0) end
local function near(a,b) return math.abs(a-b)<0.00001 end
local function same(a,b) return a:DistToSqr(b)<0.00001 end
local objects,players,targets,shots,damages={},{},{},{},{}
local function entity(class)
    local e={valid=true,class=class,network={},pos=Vector(),angles=Angle(),hp=100}
    function e:GetClass() return self.class end
    function e:IsPlayer() return self.class=="player" end
    function e:IsNPC() return self.npc==true end
    function e:IsNextBot() return false end
    function e:Health() return self.hp end
    function e:Alive() return self.hp>0 end
    function e:InVehicle() return self.vehicle==true end
    function e:GetOwner() return self.owner end
    function e:SetOwner(owner) self.owner=owner end
    function e:GetPos() return self.pos end
    function e:GetShootPos() return self.pos end
    function e:WorldSpaceCenter() return self.pos end
    function e:SetPos(value) self.pos=value end
    function e:SetAngles(value) self.angles=value end
    function e:GetAngles() return self.angles end
    function e:Disposition() return self.ally and D_LI or D_HT end
    function e:SetNWString(key,value) self.network[key]=value end
    e.SetNWInt,e.SetNWFloat=e.SetNWString,e.SetNWString
    function e:SetNW2String(key,value)
        assert(self.class~="d6_support","Lua support entities must use classic NW fields")
        self:SetNWString(key,value)
    end
    e.SetNW2Int,e.SetNW2Float,e.SetNW2Entity=e.SetNW2String,e.SetNW2String,e.SetNW2String
    function e:GetNWString(key,default) local value=self.network[key];if value==nil then return default end;return value end
    e.GetNWInt,e.GetNWFloat=e.GetNWString,e.GetNWString
    function e:GetNW2String(key,default)
        assert(self.class~="d6_support","Lua support entities must use classic NW fields")
        return self:GetNWString(key,default)
    end
    e.GetNW2Int,e.GetNW2Float,e.GetNW2Entity=e.GetNW2String,e.GetNW2String,e.GetNW2String
    function e:GetNWBool() return self.flight==true end
    function e:Spawn() end
    function e:Remove() self.valid=false end
    function e:EmitSound() end
    function e:PrintMessage(_,message) self.lastMessage=message end
    objects[#objects+1]=e
    return e
end
local function pilot()
    local p=entity("player");p.flight,p.ammo,p.energy,p.D6Ang=true,{},100,Angle()
    function p:GetAmmoCount(kind) return self.ammo[kind] or 0 end
    function p:GiveAmmo(n,kind) self.ammo[kind]=self:GetAmmoCount(kind)+n end
    function p:RemoveAmmo(n,kind) self.ammo[kind]=self:GetAmmoCount(kind)-n end
    players[#players+1]=p
    return p
end
local function enemy(x,y,z)
    local e=entity("d6_combat_drone");e.npc=true;e.pos=Vector(x,y,z);targets[#targets+1]=e;return e
end
local wallX,solidStart,blockedMuzzle,constructorFails=nil,false,false,false
local function trace(data)
    if solidStart or (blockedMuzzle and data.maxs and data.maxs.x==3) then
        return {StartSolid=true,Hit=true,HitPos=data.start,Fraction=0,HitNormal=Vector(-1,0,0)}
    end
    local radius=data.maxs and data.maxs.x or 0
    if wallX and data.start.x+radius>=wallX then
        return {StartSolid=true,Hit=true,HitPos=data.start,Fraction=0,HitNormal=Vector(-1,0,0)}
    end
    if wallX and data.endpos.x+radius>=wallX and data.endpos.x>data.start.x then
        local f=(wallX-radius-data.start.x)/(data.endpos.x-data.start.x)
        return {StartSolid=false,Hit=true,HitPos=data.start+(data.endpos-data.start)*f,Fraction=f,HitNormal=Vector(-1,0,0)}
    end
    return {StartSolid=false,Hit=false,HitPos=data.endpos,Fraction=1,HitNormal=Vector(-1,0,0)}
end
util={TraceHull=trace,TraceLine=trace,IsInWorld=function() return true end}
ents={Create=function(class) return entity(class) end,FindInSphere=function(pos,range)
    local out={};for _,e in ipairs(targets) do if e.pos:DistToSqr(pos)<=range*range then out[#out+1]=e end end;return out
end}
local hooks,commands={},{}
hook={Add=function(event,id,fn) hooks[event]=hooks[event] or {};hooks[event][id]=fn end}
concommand={Add=function(name,fn) commands[name]=fn end}
player={GetAll=function() return players end}
D6_Actors={IsCombat=function(e) return e:GetClass()=="d6_combat_drone" end}
D6_Energy={TryConsume=function(ply,_,amount) if ply.energy<amount then return false end;ply.energy=ply.energy-amount;return true end,
    Add=function(ply,amount) ply.energy=math.min(100,ply.energy+amount) end}
D6_Wep={AimAng=function(ply) return ply.D6Ang end,MuzzleFX=function() end,
    FireProjectile=function(config) if constructorFails then return end;shots[#shots+1]=config;return entity("d6_projectile") end,
    DirectDamage=function(owner,inflictor,target,amount) damages[#damages+1]={owner=owner,target=target,amount=amount} end}
dofile(root.."d6_supports.lua")
local S=D6_Supports
local function count(ply)
    local n=0;for _,e in ipairs(objects) do if e.valid and e.class=="d6_support" and e.owner==ply then n=n+1 end end;return n
end
local function advance(ply,seconds)
    for _=1,math.ceil(seconds/0.05) do now=now+0.05;S.Step(ply,0.05) end
end
local function ready(ply,slot)
    ply:SetNW2Float("D6_SupportReady"..slot,0);ply.energy=100;ply.ammo[S.Ammo]=6
end
local function projectile(owner,kind,class)
    local e=entity("d6_projectile");e.owner,e.D6_DamageClass,e.D6_WeaponClass=owner,kind,class;return e
end

local p=pilot()
check("catalogue has five types but only three equipment slots",#S.Order==5 and S.MaxActive==3)
check("ordinary initial grant is exactly three cells",S.GrantInitial(p)==3 and p:GetAmmoCount(S.Ammo)==3)
S.Ensure(p);S.Ensure(p)
check("repeated ensure creates at most three own bodies",count(p)==3)
check("all bodies use independent non-scanner support class",S.GetEntity(p,1):GetClass()=="d6_support")
check("docked equipment starts with no combat power",S.GetState(p,1)=="docked" and S.GetEntity(p,1):GetNWFloat("D6_SupportPower")==0)
check("fractional or out-of-range slots are rejected",not S.Select(p,0) and not S.Select(p,4) and not S.Select(p,1.5))
check("duplicate types cannot occupy multiple slots",not S.Assign(p,1,"interceptor"))
local p2=pilot();S.Ensure(p2)
check("three-slot limit is per owner",count(p)==3 and count(p2)==3)
local alien=S.GetEntity(p2,1);p:SetNW2Entity("D6_SupportEntity1",alien)
check("network entity accessor rejects a foreign owner's body",S.GetEntity(p,1)==nil)
p:SetNW2Entity("D6_SupportEntity1",S.Players[p].entities[1])

local oldHome=S.Home(p,1);p.D6Ang=Angle(0,0,90)
local rolledHome=S.Home(p,1)
check("formation rotates through ship roll, not world-up",not same(oldHome,rolledHome) and near(rolledHome.z,58))
p.D6Ang=Angle()
local ok,reason=S.Activate(p,1)
check("one activation atomically spends one cell and energy",ok and p:GetAmmoCount(S.Ammo)==2 and p.energy==90)
local deadline=p:GetNW2Float("D6_SupportReady1")
ok,reason=S.Assign(p,1,"missile")
check("active module cannot be replaced to bypass its lifecycle",not ok and reason=="busy" and count(p)==3)
check("second action recalls without further spending",S.Activate(p,1) and p:GetAmmoCount(S.Ammo)==2 and p.energy==90)
advance(p,0.5)
check("return reaches docked state",S.GetState(p,1)=="docked")
ok,reason=S.Activate(p,1)
check("recall does not reset paid cooldown",not ok and reason=="cooldown" and p:GetNW2Float("D6_SupportReady1")==deadline)
check("replacement preserves slot cooldown",S.Assign(p,1,"missile") and p:GetNW2Float("D6_SupportReady1")==deadline and count(p)==3)
local socketBody=S.GetEntity(p,1)
socketBody:SetAngles(Angle())
check("socket uses Source model local positive Y rather than camera right",same(S.Socket(socketBody,1),socketBody:GetPos()+Vector(20,-7,-5)))
socketBody:SetAngles(Angle(0,0,90))
check("socket rotates with a rolled model without mirroring its port",same(S.Socket(socketBody,1),socketBody:GetPos()+Vector(20,5,-7)))
socketBody:SetAngles(Angle())
p.ammo[S.Ammo]=0;S.Cleanup(p);S.Ensure(p)
check("cleanup/toggle never regrants starting ammunition",S.GrantInitial(p)==0 and p:GetAmmoCount(S.Ammo)==0)
check("explicit debug supply fills to six",S.GrantInitial(p,true)==6 and p:GetAmmoCount(S.Ammo)==6)
check("common supply clamps at capacity",S.Restock(p)==0)
p.ammo[S.Ammo]=5;check("partial common supply fills only missing cell",S.Restock(p)==1 and p:GetAmmoCount(S.Ammo)==6)
p.ammo[S.Ammo]=0;check("common supply grants two after initial inventory",S.Restock(p)==2)
check("supply does not unlock an uninitialized inventory",S.Restock(p2)==0)

local foe=enemy(500,0,0)
ready(p,1);wallX=150
ok,reason=S.Activate(p,1)
check("missile activation rejects enemies behind world cover before paying",not ok and reason=="target" and p:GetAmmoCount(S.Ammo)==6 and p.energy==100)
local safe=S.SafePoint(p,Vector(300,0,0))
check("deployment point stays on the near side of hull collision",safe and safe.x<=122)
local body=S.GetEntity(p,1);body:SetPos(Vector())
S.Move(body,Vector(300,0,0),1)
check("swept movement cannot cross a wall",body:GetPos().x<=122)
solidStart=true
check("deployment refuses a starting solid hull",S.SafePoint(p,Vector(300,0,0))==nil)
solidStart,wallX=false,nil
body:SetPos(S.Home(p,1));p.energy=2
ok,reason=S.Activate(p,1)
check("insufficient energy leaves cells and readiness untouched",not ok and reason=="energy" and p:GetAmmoCount(S.Ammo)==6 and p:GetNW2Float("D6_SupportReady1")==0)
p.energy,p.ammo[S.Ammo]=100,0
ok,reason=S.Activate(p,1)
check("empty cells leave energy untouched",not ok and reason=="ammo" and p.energy==100)
ready(p,1);blockedMuzzle=true
ok,reason=S.Activate(p,1)
check("blocked missile muzzle is rejected before consuming resources",not ok and reason=="blocked" and p.energy==100 and p:GetAmmoCount(S.Ammo)==6)
blockedMuzzle,constructorFails=false,true
ok,reason=S.Activate(p,1)
check("failed missile constructor refunds both resources and cooldown",not ok and reason=="spawn" and p.energy==100 and p:GetAmmoCount(S.Ammo)==6
    and p:GetNW2Float("D6_SupportReady1")==0 and S.GetState(p,1)=="docked")
constructorFails=false
local shotCount=#shots
check("missile fires one paid visible projectile",S.Activate(p,1) and #shots==shotCount+1 and shots[#shots].sourceSupport==body and shots[#shots].support==true)
check("missile starts at its actual model socket",same(shots[#shots].pos,S.Socket(body,1)))
advance(p,0.5)
check("missile carrier stays with the hull and becomes inert",S.GetState(p,1)=="docked" and body:GetNWFloat("D6_SupportPower")==0)

S.Assign(p,1,"reflector");ready(p,1);S.Activate(p,1);advance(p,0.4)
local prism=S.GetEntity(p,1)
check("reflector arms only after reaching deployment point",S.GetState(p,1)=="active")
local bolt=projectile(p,"exotic","weapon_d6_plasma")
local from,to=Vector(0,0,0),Vector(600,0,0)
local hit=S.TraceProjectile(bolt,from,to,3,1)
check("own plasma can intersect the reflector",hit and hit.support==prism)
check("earlier wall fraction wins over support contact",S.TraceProjectile(bolt,from,to,3,0.1)==nil)
local redirect=S.HandleProjectile(bolt,hit,Vector(1200,0,0))
check("reflection preserves projectile speed",redirect and redirect.kind=="redirect" and near(redirect.velocity:Length(),1200))
check("a projectile can be reflected only once",bolt.D6_SupportReflected and S.TraceProjectile(bolt,from,to,3,1)==nil)
local bfg=projectile(p,"exotic","weapon_d6_bfg")
check("BFG cannot be amplified through a reflector",S.TraceProjectile(bfg,from,to,3,1)==nil)
local foreign=projectile(p2,"kinetic","weapon_d6_mg")
check("foreign player's shots are not captured",S.TraceProjectile(foreign,from,to,3,1)==nil)
local ownSupport=projectile(p,"kinetic","d6_support");ownSupport.D6_SupportShot=true
check("support shots cannot form reflection feedback",S.TraceProjectile(ownSupport,from,to,3,1)==nil)
wallX=300
local blocked=projectile(p,"kinetic","weapon_d6_mg")
local blockedHit=S.TraceProjectile(blocked,from,to,3,1)
local remaining=prism.D6_SupportRemaining
check("reflector cannot acquire an enemy through a wall",S.HandleProjectile(blocked,blockedHit,Vector(900,0,0))==nil and prism.D6_SupportRemaining==remaining)
wallX=nil
for _=1,3 do local b=projectile(p,"kinetic","weapon_d6_mg");S.HandleProjectile(b,S.TraceProjectile(b,from,to,3,1),Vector(1000,0,0)) end
local extra=projectile(p,"kinetic","weapon_d6_mg")
check("one paid reflector window redirects at most four shots",prism.D6_SupportRemaining==0 and S.TraceProjectile(extra,from,to,3,1)==nil)
S.Recall(p,1);advance(p,0.5)

local stillPosition=prism:GetPos()
advance(p,0.65)
check("cold prism drifts around a stationary pilot without gaining combat power",not same(stillPosition,prism:GetPos())
    and prism:GetPos():DistToSqr(S.Home(p,1))<=11^2 and prism:GetNWFloat("D6_SupportPower")==0)
local heavyRound=projectile(p,"explosive","weapon_d6_heavy")
check("docked prism cannot charge from the pilot's heavy round",not S.TraceProjectile(heavyRound,
    prism:GetPos()-Vector(100,0,0),prism:GetPos()+Vector(100,0,0),10,1))
ready(p,1);S.Activate(p,1);advance(p,0.45)
check("deployed prism advertises redirect mode",prism:GetNWString("D6_SupportCombat")=="redirect")
local settled=prism:GetPos()
p.D6Ang=Angle(0,180,90);advance(p,0.2)
check("changing view does not pull the deployed prism to the new aim",prism:GetPos():DistToSqr(settled)<20^2)
p.pos=Vector(0,55,0);advance(p,0.25)
check("deployment translates with the pilot through swept movement",prism:GetPos().y>settled.y+35)
p.D6Ang=Angle();p.pos=Vector();advance(p,0.25)
local function prismSweep(projectile,cap)
    local core=S.Socket(prism,1)
    return S.TraceProjectile(projectile,core-Vector(100,0,0),core+Vector(100,0,0),10,cap or 1)
end
local fHeavy=projectile(p2,"explosive","weapon_d6_heavy")
check("prism rejects foreign heavy rounds and world-first crossings",not prismSweep(fHeavy) and not prismSweep(heavyRound,0.1))
local supportHeavy=projectile(p,"explosive","weapon_d6_heavy"); supportHeavy.D6_SupportShot=true
check("support-generated heavy rounds cannot charge a prism",not prismSweep(supportHeavy))
local chargeHit=prismSweep(heavyRound)
local budgetSince=p:GetNW2Float("D6_SupportReady1")
check("compatible heavy contact is absorbed once and advertises charged fire",chargeHit
    and S.HandleProjectile(heavyRound,chargeHit,Vector(1100,0,0)).kind=="consume"
    and prism:GetNWString("D6_SupportCombat")=="charged_fire"
    and not S.HandleProjectile(heavyRound,chargeHit,Vector(1100,0,0)))
check("a charged prism pauses normal redirects and rejects further charges",
    not prismSweep(projectile(p,"kinetic","weapon_d6_mg")) and not prismSweep(projectile(p,"explosive","weapon_d6_heavy")))
wallX=300;shotCount=#shots
advance(p,0.45)
check("charged prism waits without a visible target, spending no rounds through cover",
    #shots==shotCount and prism.D6_Prism.rounds==3 and prism:GetNWString("D6_SupportCombat")=="charged_fire")
wallX=nil
p.D6Ang=Angle(0,180,90);advance(p,1.25)
check("charged fire acquires in the device's sector independent of camera",#shots==shotCount+3
    and shots[#shots].sourceSupport==prism and shots[#shots].swept and shots[#shots].dir.x>0.8)
check("three paid rounds resume redirect without a second heavy charge or new resources",
    prism:GetNWString("D6_SupportCombat")=="redirect" and not prismSweep(projectile(p,"explosive","weapon_d6_heavy"))
    and prismSweep(projectile(p,"kinetic","weapon_d6_mg")) and prism.D6_SupportRemaining==4
    and p:GetAmmoCount(S.Ammo)==5 and p.energy==90 and p:GetNW2Float("D6_SupportReady1")==budgetSince)
advance(p,0.7)
check("finished prism cannot autonomously fire again during this deployment",#shots==shotCount+3)
S.Recall(p,1); advance(p,0.5); p.D6Ang=Angle()

ready(p,1);S.Activate(p,1);advance(p,0.45)
heavyRound=projectile(p,"explosive","weapon_d6_heavy")
wallX=300;shotCount=#shots
check("owner can feed one heavy round before any target arrives",S.HandleProjectile(heavyRound,
    prismSweep(heavyRound),Vector(1100,0,0)).kind=="consume")
advance(p,2)
check("absence of targets expires the charged window independently of deployment",
    #shots==shotCount and S.GetState(p,1)=="active" and prism:GetNWString("D6_SupportCombat")=="redirect")
wallX=nil;advance(p,0.4)
check("an enemy appearing after charge expiry does not restart the burst",#shots==shotCount)
S.Recall(p,1);advance(p,0.5)
ready(p,1);S.Activate(p,1);advance(p,5.5)
heavyRound=projectile(p,"explosive","weapon_d6_heavy")
S.HandleProjectile(heavyRound,prismSweep(heavyRound),Vector(1100,0,0))
check("charge near deadline cannot extend the paid activation",
    prism.D6_Prism.chargeUntil==prism.D6_SupportUntil)
S.Recall(p,1);advance(p,0.65)
check("recall clears charged fire and returns cold before the first round",
    #shots==shotCount and S.GetState(p,1)=="docked" and prism:GetNWString("D6_SupportCombat")=="idle")

ready(p,2);S.Activate(p,2);advance(p,0.3)
local shield=S.GetEntity(p,2)
local front=shield:GetPos()+Vector(100,0,0)
local rear=shield:GetPos()-Vector(100,0,0)
local enemyShot=projectile(foe,"energy")
local sh=S.TraceProjectile(enemyShot,front,rear,2,1)
check("shield catches a hostile front-to-back crossing",sh and sh.support==shield)
check("shield never catches a rear-to-front crossing",S.TraceProjectile(enemyShot,rear,front,2,1)==nil)
check("shield has finite lateral extent",S.TraceProjectile(enemyShot,front+Vector(0,80,0),rear+Vector(0,80,0),2,1)==nil)
check("shield lets owner's outgoing shots pass",S.TraceProjectile(projectile(p,"energy"),front,rear,2,1)==nil)
local ally=enemy(500,10,0);ally.ally=true
check("shield lets allied NPC fire pass",S.TraceProjectile(projectile(ally,"energy"),front,rear,2,1)==nil)
local lingering=projectile(foe,"energy")
S.TagProjectile(lingering,foe);foe.hp,foe.valid=0,false
check("enemy projectile remains blockable after shooter removal",S.TraceProjectile(lingering,front,rear,2,1)~=nil)
foe.hp,foe.valid=100,true
local friendlyLingering=projectile(ally,"energy")
S.TagProjectile(friendlyLingering,ally);ally.hp,ally.valid=0,false
check("hostility snapshot never converts a removed ally's shot",S.TraceProjectile(friendlyLingering,front,rear,2,1)==nil)
ally.hp,ally.valid=100,true
for _=1,6 do S.HandleProjectile(enemyShot,S.TraceProjectile(enemyShot,front,rear,2,1),Vector(-1000,0,0)) end
check("shield blocks no more than six shots per paid activation",shield.D6_SupportRemaining==0 and S.TraceProjectile(enemyShot,front,rear,2,1)==nil)
shotCount=#shots;advance(p,2)
check("bulwark fires exactly six radial projectiles then returns",#shots==shotCount+6 and S.GetState(p,2)=="docked")

S.Assign(p,1,"resonator");ready(p,1);S.Activate(p,1);advance(p,0.5)
local charge=S.GetEntity(p,1)
local rail=S.TraceRail(p,from,to,1)
check("armed resonator can be triggered by the owner's rail",rail and rail.support==charge)
check("foreign rail cannot address another player's charge",S.TraceRail(p2,from,to,1)==nil and not S.HitRail(p2,rail))
check("world cover prevents a rail-resonator intersection",S.TraceRail(p,from,to,0.1)==nil)
local before=#damages
check("owner rail detonation succeeds once",S.HitRail(p,rail) and not S.HitRail(p,rail))
check("blast excludes allied NPCs",#damages==before+1 and damages[#damages].target==foe)
check("detonation disarms before damage callbacks and starts return",S.GetState(p,1)=="returning" and S.TraceRail(p,from,to,1)==nil)
advance(p,0.5);ready(p,1);S.Activate(p,1);advance(p,0.5)
local heavy=projectile(p,"explosive","weapon_d6_heavy")
local heavyHit=S.TraceProjectile(heavy,from,to,10,1)
check("paid heavy orb can trigger a resonator",heavyHit and S.HandleProjectile(heavy,heavyHit,Vector(1000,0,0)).kind=="consume")

ready(p,3);shotCount=#shots
check("interceptor activation requires a visible target",S.Activate(p,3))
advance(p,2)
check("interceptor fires exactly four shots and returns",#shots==shotCount+4 and S.GetState(p,3)=="docked")
S.Assign(p,1,"reflector");ready(p,1);S.Activate(p,1);advance(p,0.4)
S.Recall(p,1)
local returning=S.GetEntity(p,1)
local returnBy,cells,readyAt=returning.D6_SupportReturnBy,p:GetAmmoCount(S.Ammo),p:GetNW2Float("D6_SupportReady1")
solidStart=true;advance(p,2);S.Activate(p,1)
check("repeated recall never extends a blocked return deadline",returning.D6_SupportReturnBy==returnBy)
advance(p,2.1)
check("blocked return retires its body within four seconds",not IsValid(returning) and S.GetEntity(p,1)==nil and count(p)==2)
solidStart=false;S.Ensure(p)
check("lost body waits before retrying safe formation spawn",count(p)==2)
now=now+1.1;S.Ensure(p)
check("recovery creates only a cold body without resetting resources",count(p)==3 and S.GetState(p,1)=="docked"
    and p:GetAmmoCount(S.Ammo)==cells and p:GetNW2Float("D6_SupportReady1")==readyAt)
local supplied=p.D6_SupportSupplyGranted
p.hp=0;hooks.PlayerDeath.D6_SupportDeath(p)
check("death removes all owned support bodies",count(p)==0 and S.Players[p]==nil)
check("death cleanup preserves no-refill flag",p.D6_SupportSupplyGranted==supplied)
check("cleanup never removes another player's formation",count(p2)==3)
p2.flight=false;S.Step(p2,0.05)
check("leaving flight removes companion entities",count(p2)==0)
check("non-flight player cannot activate support",not S.Activate(p2,1))
print(string.format("\n%d support contract checks passed; live GMod verification remains required.",passed))
