-- Granada's support interactions, adapted to a three-slot 6DOF formation.
-- Dormant bodies are equipment; only a paid activation gives them combat power.
D6_Supports = D6_Supports or {}
local S = D6_Supports
S.MaxActive, S.Ammo, S.MaxAmmo = 3, "d6_support_cell", 6
S.Defaults = {"reflector", "bulwark", "interceptor"}
S.Order = {
    {id="reflector", name="Призма", mesh="support_reflector", color=Color(108,207,222),
        description="Поставить отражатель: до четырёх своих пуль/плазмоидов в видимую цель.",
        energy=10, cooldown=7, duration=6, ports={{16,0,0}}},
    {id="bulwark", name="Створ", mesh="support_bulwark", color=Color(131,181,217),
        description="Короткий фронтальный перехват, пространственный веер и возврат.",
        energy=14, cooldown=9, duration=3.5, ports={{18,-10,-6},{18,10,-6},{18,-10,6},{18,10,6}}},
    {id="interceptor", name="Клык", mesh="support_interceptor", color=Color(196,191,142),
        description="Перехват видимого врага: четыре выстрела и возврат.",
        energy=14, cooldown=8, duration=4, ports={{24,-5,0},{24,5,0}}},
    {id="missile", name="Кассета", mesh="support_missile", color=Color(216,158,104),
        description="Одна управляемая ракета; модуль остаётся у корпуса.",
        energy=16, cooldown=8, duration=0.4, ports={{20,-7,-5},{20,7,-5},{20,-7,5},{20,7,5}}},
    {id="resonator", name="Резонатор", mesh="support_resonator", color=Color(160,202,178),
        description="Разместить заряд; свой рейл или тяжёлый снаряд вызывает взрыв.",
        energy=18, cooldown=12, duration=12, ports={{14,0,0}}},
}
S.Definitions = {}
for _, def in ipairs(S.Order) do S.Definitions[def.id] = def end

local function slotNumber(value)
    local n = tonumber(value)
    if n and n >= 1 and n <= S.MaxActive and n == math.floor(n) then return n end
end

function S.CanUse(ply)
    return IsValid(ply) and ply:IsPlayer() and ply:Alive()
        and ply:GetNWBool("D6On", false) and not ply:InVehicle()
end

function S.GetLoadout(ply)
    local out = {}
    for slot=1,S.MaxActive do
        local id = IsValid(ply) and ply:GetNW2String("D6_Support"..slot, S.Defaults[slot]) or S.Defaults[slot]
        out[slot] = S.Definitions[id] and id or S.Defaults[slot]
    end
    return out
end

function S.GetEntity(ply, slot)
    slot = slotNumber(slot)
    if not slot or not IsValid(ply) then return end
    local ent = ply:GetNW2Entity("D6_SupportEntity"..slot)
    if IsValid(ent) and ent:GetOwner() == ply then return ent end
end

function S.GetState(ply, slot)
    local ent = S.GetEntity(ply, slot)
    return IsValid(ent) and ent:GetNWString("D6_SupportState", "docked") or "docked"
end

function S.SocketAt(def, position, ang, port)
    local point = def and def.ports[((port or 1)-1) % #def.ports+1] or {0,0,0}
    -- Source model local +Y points left; Angle:Right() points toward local -Y.
    return position+ang:Forward()*point[1]-ang:Right()*point[2]+ang:Up()*point[3]
end

function S.Socket(ent, port)
    local def = S.Definitions[ent:GetNWString("D6_SupportKind", "")]
    return S.SocketAt(def,ent:GetPos(),ent:GetAngles(),port)
end

if not SERVER then return end

S.Players = S.Players or {}
local records = S.Players
local bodyRadius = 28
local bounds = Vector(bodyRadius,bodyRadius,bodyRadius)
local homes = {{8,-58,-18},{-8,0,50},{8,58,-18}}

local function record(ply)
    if not records[ply] then records[ply] = {entities={}} end
    return records[ply]
end

local function aim(ply)
    return D6_Wep.AimAng(ply)
end

function S.Home(ply, slot)
    local a, p = aim(ply), homes[slot]
    return ply:GetShootPos()+a:Forward()*p[1]+a:Right()*p[2]+a:Up()*p[3]
end

local function filterFor(ply)
    local filter = {ply}
    local rec = records[ply]
    if rec then for _, ent in pairs(rec.entities) do if IsValid(ent) then filter[#filter+1]=ent end end end
    return filter
end

-- Return a reachable point, never a point on the far side of a wall.
function S.SafePoint(ply, wanted, start)
    local tr = util.TraceHull({start=start or ply:GetShootPos(), endpos=wanted,
        mins=-bounds, maxs=bounds, mask=MASK_SOLID, filter=filterFor(ply)})
    if tr.StartSolid or not util.IsInWorld(tr.HitPos) then return end
    return tr.Hit and tr.HitPos+tr.HitNormal*2 or tr.HitPos
end

local function setState(ent, state)
    ent.D6_SupportMode = state
    ent:SetNWString("D6_SupportState", state)
end

function S.GrantInitial(ply, all)
    if not IsValid(ply) or not ply:IsPlayer() then return 0 end
    if ply.D6_SupportSupplyGranted and not all then return 0 end
    ply.D6_SupportSupplyGranted = true
    local amount = math.max(0, (all and S.MaxAmmo or 3)-ply:GetAmmoCount(S.Ammo))
    if amount > 0 then ply:GiveAmmo(amount, S.Ammo, true) end
    return amount
end

function S.Restock(ply)
    if not IsValid(ply) or not ply.D6_SupportSupplyGranted then return 0 end
    local amount = math.max(0, math.min(2, S.MaxAmmo-ply:GetAmmoCount(S.Ammo)))
    if amount > 0 then ply:GiveAmmo(amount, S.Ammo, true) end
    return amount
end

function S.Ensure(ply)
    if not S.CanUse(ply) then return false end
    local rec, loadout = record(ply), S.GetLoadout(ply)
    for slot=1,S.MaxActive do
        ply:SetNW2String("D6_Support"..slot, loadout[slot])
        local ent = rec.entities[slot]
        if IsValid(ent) and (ent:GetOwner() ~= ply or ent.D6_SupportKind ~= loadout[slot]) then
            if ent:GetOwner() == ply then ent:Remove() end
            ent, rec.entities[slot] = nil, nil
        end
        if not IsValid(ent) and CurTime() >= (rec.retryAt or 0) then
            local pos = S.SafePoint(ply, S.Home(ply,slot))
            if pos then
                ent = ents.Create("d6_support")
                if IsValid(ent) then
                    ent.D6_SupportKind, ent.D6_SupportSlot = loadout[slot], slot
                    ent.D6_WeaponClass = "d6_support"
                    ent:SetOwner(ply)
                    ent:SetPos(pos)
                    ent:SetAngles(aim(ply))
                    ent:SetNWString("D6_SupportKind", loadout[slot])
                    ent:SetNWInt("D6_SupportSlot", slot)
                    ent:SetNWFloat("D6_SupportPower", 0)
                    setState(ent,"docked")
                    rec.entities[slot] = ent
                    ent:Spawn()
                    if IsValid(ent) then ply:SetNW2Entity("D6_SupportEntity"..slot, ent) end
                end
            end
        end
    end
    return true
end

function S.Cleanup(ply)
    local rec = records[ply]
    if rec then
        for _, ent in pairs(rec.entities) do
            if IsValid(ent) and ent:GetOwner() == ply then ent:Remove() end
        end
    end
    records[ply] = nil
    if IsValid(ply) then
        for slot=1,S.MaxActive do ply:SetNW2Entity("D6_SupportEntity"..slot, NULL) end
    end
    -- Ready deadlines and D6_SupportSupplyGranted intentionally survive cleanup.
end

function S.Assign(ply, slot, id)
    slot = slotNumber(slot)
    if not S.CanUse(ply) or not slot or not S.Definitions[id] then return false,"invalid" end
    local loadout = S.GetLoadout(ply)
    for i=1,S.MaxActive do if i ~= slot and loadout[i] == id then return false,"duplicate" end end
    if loadout[slot] == id then return true end
    local rec = record(ply)
    local ent = rec.entities[slot]
    if IsValid(ent) and ent.D6_SupportMode ~= "docked" then return false,"busy" end
    if IsValid(ent) and ent:GetOwner() == ply then ent:Remove() end
    rec.entities[slot] = nil
    ply:SetNW2Entity("D6_SupportEntity"..slot, NULL)
    ply:SetNW2String("D6_Support"..slot, id)
    S.Ensure(ply)
    return true
end

function S.Select(ply, slot)
    slot = slotNumber(slot)
    if not S.CanUse(ply) or not slot then return false,"invalid" end
    ply:SetNW2Int("D6_SupportSelected", slot)
    return true
end

function S.Recall(ply, slot)
    if not IsValid(ply) then return false end
    if slot ~= nil and not slotNumber(slot) then return false end
    local rec = records[ply]
    if not rec then return false end
    for i=1,S.MaxActive do
        if slot == nil or i == tonumber(slot) then
            local ent = rec.entities[i]
            if IsValid(ent) and ent:GetOwner() == ply then
                ent.D6_SupportUntil, ent.D6_SupportRemaining, ent.D6_SupportTarget = 0,0,nil
                ent:SetNWFloat("D6_SupportPower",0)
                if ent.D6_SupportMode ~= "docked" then
                    if ent.D6_SupportMode ~= "returning" then ent.D6_SupportReturnBy=CurTime()+4 end
                    setState(ent,"returning")
                end
            end
        end
    end
    return true
end

function S.IsHostile(ply, target)
    if not IsValid(target) or target == ply or target:Health() <= 0 then return false end
    if target:IsNPC() then
        return target:Disposition(ply) == D_HT
            or (D6_Actors and D6_Actors.IsCombat(target) and target:Disposition(ply) ~= D_LI)
    end
    -- Do not silently turn co-op players or neutral props into auto-aim targets.
    return target.D6_EpisodeTarget == true and target:IsNextBot()
end

function S.TagProjectile(projectile, owner)
    if not IsValid(projectile) or not IsValid(owner) then return end
    local hostile = {}
    for ply in pairs(records) do
        if S.CanUse(ply) and S.IsHostile(ply,owner) then hostile[ply]=true end
    end
    projectile.D6_SupportHostility = hostile
end

function S.IsHostileShot(ply, projectile)
    local owner = projectile:GetOwner()
    if IsValid(owner) and owner:Health()>0 then return S.IsHostile(ply,owner) end
    -- A dead shooter's existing projectile remains hostile after NPC removal.
    return projectile.D6_SupportHostility and projectile.D6_SupportHostility[ply] == true or false
end

function S.Visible(ply, from, target, support)
    if not S.IsHostile(ply,target) then return false end
    local filter = filterFor(ply)
    if IsValid(support) then filter[#filter+1]=support end
    local tr = util.TraceLine({start=from, endpos=target:WorldSpaceCenter(), filter=filter, mask=MASK_SHOT})
    return not tr.StartSolid and (not tr.Hit or tr.Entity == target)
end

function S.FindTarget(ply, from, range, support)
    local best, score = nil, math.huge
    local forward = aim(ply):Forward()
    for _, target in ipairs(ents.FindInSphere(from, range)) do
        if S.IsHostile(ply,target) then
            local delta = target:WorldSpaceCenter()-from
            local facing = delta:GetNormalized():Dot(forward)
            local value = delta:LengthSqr()+(1-facing)*range*range*0.3
            if facing > -0.15 and value < score and S.Visible(ply,from,target,support) then
                best, score = target, value
            end
        end
    end
    return best
end

local function pay(ply, slot, def)
    if CurTime() < ply:GetNW2Float("D6_SupportReady"..slot,0) then return false,"cooldown" end
    if ply:GetAmmoCount(S.Ammo) < 1 then return false,"ammo" end
    if not D6_Energy.TryConsume(ply,"weapons",def.energy) then return false,"energy" end
    ply:RemoveAmmo(1,S.Ammo)
    ply:SetNW2Float("D6_SupportReady"..slot,CurTime()+def.cooldown)
    return true
end

local function muzzleClear(ply,origin,from)
    local clear = util.TraceHull({start=origin, endpos=from, mins=Vector(-3,-3,-3),
        maxs=Vector(3,3,3), filter=filterFor(ply), mask=MASK_SHOT})
    return not clear.Hit and not clear.StartSolid
end

local function fire(ent, direction, port, missile)
    local ply = ent:GetOwner()
    local from = S.Socket(ent,port)
    if not muzzleClear(ply,ent:GetPos(),from) then return false end
    local target = ent.D6_SupportTarget
    local shot = D6_Wep.FireProjectile({owner=ply, pos=from, dir=direction, sourceSupport=ent, support=true,
        speed=missile and 850 or 1350, inherit=0, swept=true, physRadius=missile and 4 or 2,
        dmgClass=missile and "explosive" or "kinetic", art=missile and "shot_rocket" or "shot_kinetic",
        renderAdd=false, life=missile and 3.5 or 1.3,
        steer=missile and function(projectile, pos, velocity, dt)
            if not S.CanUse(ply) or not S.Visible(ply,pos,target,ent) then return velocity end
            local desired=(target:WorldSpaceCenter()-pos):GetNormalized()
            return LerpVector(math.min(dt*2.4,1),velocity:GetNormalized(),desired):GetNormalized()*velocity:Length()
        end or nil,
        onHit=function(projectile,victim,pos,normal)
            if not victim or not IsValid(ply) then return end
            local dtype=missile and DMG_BLAST or DMG_BULLET
            if S.IsHostile(ply,victim) then D6_Wep.DirectDamage(ply,projectile,victim,missile and 65 or 13,dtype,direction*900) end
            if missile then
                for _, other in ipairs(ents.FindInSphere(pos,110)) do
                    if other ~= victim and S.Visible(ply,pos+normal*3,other,ent) then
                        local damage=35*math.max(0,1-other:WorldSpaceCenter():Distance(pos)/110)
                        D6_Wep.DirectDamage(ply,projectile,other,damage,DMG_BLAST)
                    end
                end
            end
        end,
    })
    if not shot then return false end
    ent:SetNWFloat("D6_SupportShotAt",CurTime())
    ent:SetNWInt("D6_SupportShotPort",port)
    D6_Wep.MuzzleFX(from,direction,missile and "explosive" or "kinetic")
    return true
end

function S.Activate(ply, slot)
    if not S.CanUse(ply) then return false,"invalid" end
    slot = slotNumber(slot or ply:GetNW2Int("D6_SupportSelected",1))
    if not slot then return false,"invalid" end
    S.Ensure(ply)
    local ent = S.GetEntity(ply,slot)
    if not IsValid(ent) then return false,"blocked" end
    if ent.D6_SupportMode ~= "docked" then return S.Recall(ply,slot) end
    local def = S.Definitions[ent.D6_SupportKind]
    local a = aim(ply)
    local goal, target, missileDir, missilePort, missileAng
    if def.id == "interceptor" or def.id == "missile" then
        target = S.FindTarget(ply,ent:GetPos(),1400,ent)
        if not IsValid(target) then return false,"target" end
    end
    if def.id == "missile" then
        goal = ent:GetPos()
        missileDir=(target:WorldSpaceCenter()-ent:GetPos()):GetNormalized()
        missileAng=missileDir:Angle()
        missilePort=(ent.D6_SupportPort or 0)%#def.ports+1
        if not muzzleClear(ply,ent:GetPos(),S.SocketAt(def,ent:GetPos(),missileAng,missilePort)) then
            return false,"blocked"
        end
    else
        local range=def.id == "resonator" and 320 or def.id == "bulwark" and 100 or 220
        goal = S.SafePoint(ply,ply:GetShootPos()+a:Forward()*range,ent:GetPos())
        if not goal or goal:DistToSqr(ent:GetPos()) < 32^2 then return false,"blocked" end
    end
    local previousReady=ply:GetNW2Float("D6_SupportReady"..slot,0)
    local previousAngles=ent:GetAngles()
    local paid, reason = pay(ply,slot,def)
    if not paid then return false,reason end
    ent.D6_SupportGoal, ent.D6_SupportTarget = goal,target
    ent.D6_SupportBasis = Angle(a.p,a.y,a.r)
    ent:SetAngles(ent.D6_SupportBasis)
    ent.D6_SupportUntil = CurTime()+def.duration
    ent.D6_SupportRemaining = def.id == "reflector" and 4 or def.id == "bulwark" and 6 or 4
    ent.D6_SupportNextShot, ent.D6_SupportShots = CurTime()+0.25,0
    ent:SetNWFloat("D6_SupportPower",1)
    setState(ent,def.id == "missile" and "active" or "deploying")
    if def.id == "missile" then
        ent:SetAngles(missileAng)
        if not fire(ent,missileDir,missilePort,true) then
            -- No projectile was created. A projectile that instantly hits cover
            -- still returns an entity and correctly remains a paid shot.
            D6_Energy.Add(ply,def.energy)
            local missing=math.max(0,math.min(1,S.MaxAmmo-ply:GetAmmoCount(S.Ammo)))
            if missing>0 then ply:GiveAmmo(missing,S.Ammo,true) end
            ply:SetNW2Float("D6_SupportReady"..slot,previousReady)
            ent.D6_SupportRemaining,ent.D6_SupportUntil,ent.D6_SupportTarget=0,0,nil
            ent:SetNWFloat("D6_SupportPower",0)
            ent:SetAngles(previousAngles)
            setState(ent,"docked")
            return false,"spawn"
        end
        ent.D6_SupportPort=missilePort
    end
    return true
end

-- The analytic intersections also work in the Lua contract test, without an engine trace substitute.
function S.SegmentSphere(from,to,center,radius)
    local delta,offset=to-from,from-center
    local a=delta:LengthSqr()
    if a < 0.000001 then return end
    local c=offset:LengthSqr()-radius*radius
    if c <= 0 then return 0 end
    local b=offset:Dot(delta)
    local disc=b*b-a*c
    if disc < 0 then return end
    local t=(-b-math.sqrt(disc))/a
    if t >= 0 and t <= 1 then return t end
end

function S.SegmentShield(from,to,ent,radius)
    local a=ent:GetAngles()
    local center=ent:GetPos()+a:Forward()*12
    local delta,offset=to-from,from-center
    -- Guard only a projectile approaching the front face, never a rear shot.
    if offset:Dot(a:Forward()) <= 0 or delta:Dot(a:Forward()) >= 0 then return end
    local near,far=0,1
    local axes={a:Forward(),a:Right(),a:Up()}
    local sizes={4+radius,22+radius,18+radius}
    for i,axis in ipairs(axes) do
        local p,d=offset:Dot(axis),delta:Dot(axis)
        if math.abs(d) < 0.000001 then
            if math.abs(p) > sizes[i] then return end
        else
            local t0,t1=(-sizes[i]-p)/d,(sizes[i]-p)/d
            if t0 > t1 then t0,t1=t1,t0 end
            near,far=math.max(near,t0),math.min(far,t1)
            if near > far then return end
        end
    end
    if near >= 0 and near <= 1 then return near end
end

local function armed(ent)
    return IsValid(ent) and ent.D6_SupportMode == "active" and CurTime() < (ent.D6_SupportUntil or 0)
end

local function reflectable(projectile,ply)
    if projectile:GetOwner() ~= ply or projectile.D6_SupportReflected
        or projectile.D6_SupportShot or IsValid(projectile.D6_SourceSupport) then return false end
    local class=projectile.D6_WeaponClass
    if class == "weapon_d6_bfg" then return false end
    return projectile.D6_DamageClass == "kinetic" or projectile.D6_DamageClass == "energy"
        or class == "weapon_d6_plasma"
end

function S.TraceProjectile(projectile,from,to,radius,maxFraction)
    if not IsValid(projectile) then return end
    local best,limit=nil,maxFraction or 1
    for ply,rec in pairs(records) do
        if S.CanUse(ply) then
            for _,ent in pairs(rec.entities) do
                if armed(ent) and ent:GetOwner() == ply then
                    local fraction,kind=nil,ent.D6_SupportKind
                    if kind == "reflector" and (ent.D6_SupportRemaining or 0)>0 and reflectable(projectile,ply) then
                        fraction=S.SegmentSphere(from,to,S.Socket(ent,1),14+(radius or 0))
                    elseif kind == "bulwark" and CurTime() < (ent.D6_SupportGuardUntil or 0) and (ent.D6_SupportRemaining or 0)>0
                        and S.IsHostileShot(ply,projectile) then
                        fraction=S.SegmentShield(from,to,ent,radius or 0)
                    elseif kind == "resonator" and projectile:GetOwner() == ply
                        and not projectile.D6_SupportShot and projectile.D6_WeaponClass == "weapon_d6_heavy" then
                        fraction=S.SegmentSphere(from,to,S.Socket(ent,1),14+(radius or 0))
                    end
                    if fraction and fraction < limit then
                        best,limit={fraction=fraction,pos=from+(to-from)*fraction,support=ent},fraction
                    end
                end
            end
        end
    end
    return best
end

local function detonate(ent)
    if not armed(ent) or ent.D6_SupportKind ~= "resonator" then return false end
    local ply,pos=ent:GetOwner(),ent:GetPos()
    if not S.CanUse(ply) then return false end
    -- Disarm before damage: chain callbacks cannot detonate the same charge twice.
    S.Recall(ply,ent.D6_SupportSlot)
    for _,target in ipairs(ents.FindInSphere(pos,280)) do
        if S.Visible(ply,pos,target,ent) then
            local toward=target:WorldSpaceCenter()-pos
            local damage=150+100*math.max(0,1-toward:Length()/280)
            D6_Wep.DirectDamage(ply,ent,target,damage,DMG_BLAST,toward:GetNormalized()*2600)
        end
    end
    D6_Wep.MuzzleFX(pos,ent:GetAngles():Forward(),"exotic")
    ent:EmitSound("weapons/physcannon/energy_sing_explosion2.wav",78,110)
    return true
end

function S.HandleProjectile(projectile,hit,velocity)
    local ent=hit and hit.support
    if not IsValid(projectile) or not armed(ent) then return end
    local ply=ent:GetOwner()
    if ent.D6_SupportKind == "reflector" and reflectable(projectile,ply) and (ent.D6_SupportRemaining or 0)>0 then
        local target=S.FindTarget(ply,hit.pos,1600,ent)
        if not target or not velocity or velocity:LengthSqr() < 1 then return end
        ent.D6_SupportRemaining=ent.D6_SupportRemaining-1
        projectile.D6_SupportReflected=true
        ent:SetNWFloat("D6_SupportShotAt",CurTime())
        ent:SetNWInt("D6_SupportShotPort",1)
        D6_Wep.MuzzleFX(hit.pos,(target:WorldSpaceCenter()-hit.pos):GetNormalized(),"energy")
        return {kind="redirect",pos=hit.pos,velocity=(target:WorldSpaceCenter()-hit.pos):GetNormalized()*velocity:Length()}
    elseif ent.D6_SupportKind == "bulwark" and CurTime() < (ent.D6_SupportGuardUntil or 0)
        and (ent.D6_SupportRemaining or 0)>0 and S.IsHostileShot(ply,projectile) then
        ent.D6_SupportRemaining=ent.D6_SupportRemaining-1
        ent:SetNWFloat("D6_SupportHitAt",CurTime())
        return {kind="consume"}
    elseif ent.D6_SupportKind == "resonator" and projectile:GetOwner() == ply
        and projectile.D6_WeaponClass == "weapon_d6_heavy" and not projectile.D6_SupportShot and detonate(ent) then
        return {kind="consume"}
    end
end

function S.TraceRail(ply,from,to,maxFraction)
    if not S.CanUse(ply) then return end
    local rec,best,limit=records[ply],nil,maxFraction or 1
    if not rec then return end
    for _,ent in pairs(rec.entities) do
        if armed(ent) and ent:GetOwner() == ply and ent.D6_SupportKind == "resonator" then
            local fraction=S.SegmentSphere(from,to,S.Socket(ent,1),14)
            if fraction and fraction < limit then best,limit={fraction=fraction,pos=from+(to-from)*fraction,support=ent},fraction end
        end
    end
    return best
end

function S.HitRail(ply,hit)
    local ent=hit and hit.support
    return IsValid(ent) and ent:GetOwner() == ply and detonate(ent) or false
end

-- A swept, sliding follower. A blocked return never teleports an armed device.
function S.Move(ent,wanted,dt)
    local ply,from=ent:GetOwner(),ent:GetPos()
    local delta=wanted-from
    if delta:LengthSqr() < 1 then return true end
    local step=delta:GetNormalized()*math.min(delta:Length(),(ent.D6_SupportMode == "docked" and 1800 or 900)*dt)
    local data={start=from,endpos=from+step,mins=-bounds,maxs=bounds,filter=filterFor(ply),mask=MASK_SOLID}
    local tr=util.TraceHull(data)
    if tr.StartSolid then return false end
    local destination=tr.HitPos
    if tr.Hit then
        destination=destination+tr.HitNormal*0.5
        local remainder=step*(1-tr.Fraction)
        local slide=remainder-tr.HitNormal*math.min(0,remainder:Dot(tr.HitNormal))
        data.start,data.endpos=destination,destination+slide
        local second=util.TraceHull(data)
        if not second.StartSolid then destination=second.HitPos end
    end
    if util.IsInWorld(destination) then ent:SetPos(destination) end
    return ent:GetPos():DistToSqr(wanted)<16^2
end

function S.Step(ply,dt)
    if not S.CanUse(ply) then S.Cleanup(ply); return end
    local rec=record(ply)
    for slot,ent in pairs(rec.entities) do
        if IsValid(ent) then
            local state,kind=ent.D6_SupportMode,ent.D6_SupportKind
            if state ~= "docked" and state ~= "returning" and CurTime()>=(ent.D6_SupportUntil or 0) then
                S.Recall(ply,slot); state="returning"
            end
            local home=S.Home(ply,slot)
            local wanted=(state=="docked" or state=="returning" or kind=="missile") and home or ent.D6_SupportGoal
            if kind=="interceptor" and (state=="deploying" or state=="active") then
                local target=ent.D6_SupportTarget
                if not S.IsHostile(ply,target) or target:WorldSpaceCenter():DistToSqr(ply:GetShootPos())>1600^2 then
                    S.Recall(ply,slot); state,wanted="returning",home
                elseif S.Visible(ply,ent:GetPos(),target,ent) then
                    local away=(ply:GetShootPos()-target:WorldSpaceCenter()):GetNormalized()
                    wanted=target:WorldSpaceCenter()+away*190
                end
            end
            local arrived=S.Move(ent,wanted or home,dt)
            if state=="returning" and arrived then
                setState(ent,"docked")
                ent.D6_SupportReturnBy=nil
            end
            if state=="deploying" and arrived then
                setState(ent,"active")
                ent.D6_SupportNextShot=CurTime()+0.15
                if kind=="bulwark" then
                    ent.D6_SupportGuardUntil=CurTime()+1
                    ent.D6_SupportNextShot=ent.D6_SupportGuardUntil
                end
            end
            if state=="docked" or state=="returning" then
                ent:SetAngles(aim(ply))
            elseif kind=="bulwark" and armed(ent) then
                if CurTime()>=(ent.D6_SupportNextShot or 0) then
                    local a=ent.D6_SupportBasis
                    local dirs={a:Forward(),a:Right(),-a:Forward(),-a:Right(),a:Up(),-a:Up()}
                    local index=(ent.D6_SupportShots or 0)+1
                    if index<=#dirs then
                        ent:SetAngles(dirs[index]:Angle())
                        fire(ent,dirs[index],(index-1)%4+1,false)
                        ent.D6_SupportShots=index
                        ent.D6_SupportNextShot=CurTime()+0.12
                    else S.Recall(ply,slot) end
                end
            elseif kind=="interceptor" then
                local target=ent.D6_SupportTarget
                if IsValid(target) then
                    local dir=(target:WorldSpaceCenter()-ent:GetPos()):GetNormalized()
                    ent:SetAngles(dir:Angle())
                    if armed(ent) and CurTime()>=(ent.D6_SupportNextShot or 0) and S.Visible(ply,S.Socket(ent,1),target,ent) then
                        local index=(ent.D6_SupportShots or 0)+1
                        fire(ent,dir,(index-1)%2+1,false)
                        ent.D6_SupportShots=index
                        ent.D6_SupportNextShot=CurTime()+0.16
                        if index>=4 then S.Recall(ply,slot) end
                    end
                end
            end
            if ent:GetPos():DistToSqr(ply:GetShootPos())>2000^2
                or (state=="returning" and not arrived and CurTime()>=(ent.D6_SupportReturnBy or math.huge)) then
                -- Retire a lost body; the next one is cold, never an active teleport.
                ent:Remove(); rec.entities[slot]=nil; rec.retryAt=CurTime()+1
                ply:SetNW2Entity("D6_SupportEntity"..slot,NULL)
            end
        end
    end
end

local nextEnsure,lastThink=0,CurTime()
hook.Add("Think","D6_SupportFormation",function()
    local now=CurTime()
    local dt=math.Clamp(now-lastThink,0,0.05)
    lastThink=now
    if now>=nextEnsure then
        nextEnsure=now+0.2
        for _,ply in ipairs(player.GetAll()) do if S.CanUse(ply) then S.Ensure(ply) end end
    end
    for ply in pairs(records) do S.Step(ply,dt) end
end)
hook.Add("PlayerDeath","D6_SupportDeath",S.Cleanup)
hook.Add("PlayerDisconnected","D6_SupportDisconnect",S.Cleanup)
hook.Add("PreCleanupMap","D6_SupportMapCleanup",function()
    for ply in pairs(records) do S.Cleanup(ply) end
end)

local errors={invalid="Нет доступа к управлению саппортами.",duplicate="Этот тип уже установлен.",
    busy="Дождитесь возврата модуля к корпусу.",
    spawn="Не удалось выпустить снаряд; ресурсы возвращены.",
    cooldown="Модуль ещё восстанавливается.",ammo="Нет ячеек саппортов.",energy="Недостаточно энергии.",
    target="Нет видимой враждебной цели.",blocked="Недостаточно свободного пространства."}
local function command(ply,verb,callback)
    if not S.CanUse(ply) then return end
    local rec=record(ply)
    rec.requests=rec.requests or {}
    if CurTime()<(rec.requests[verb] or 0) then return end
    rec.requests[verb]=CurTime()+0.08
    local ok,reason=callback()
    if not ok and errors[reason] then ply:PrintMessage(HUD_PRINTTALK,"[D6] "..errors[reason]) end
end
concommand.Add("d6_support_set",function(ply,_,args) command(ply,"set",function() return S.Assign(ply,args[1],args[2]) end) end)
concommand.Add("d6_support_select",function(ply,_,args) command(ply,"select",function() return S.Select(ply,args[1]) end) end)
concommand.Add("d6_support_action",function(ply,_,args) command(ply,"action",function() return S.Activate(ply,args[1]) end) end)
concommand.Add("d6_support_recall",function(ply,_,args) command(ply,"recall",function() return S.Recall(ply,args[1]) end) end)
