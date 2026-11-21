-- Optional read-only GMod integration probe; not an autorun file.
-- Copy to garrysmod/lua/drmd_support_verify.lua on a development installation.
-- Server console: lua_openscript drmd_support_verify.lua
-- Admin player/server console: d6_support_verify [player entity index]
-- Client developer console: lua_openscript_cl drmd_support_verify.lua
-- Client developer console: d6_support_verify_client
--
-- Run after enabling flight in a clear test area and waiting at least one tick.
-- This script never spawns, equips, activates, recalls or refills anything.
-- It checks live state; firing, wall interception, rollover and prediction still
-- need the operator's normal controls and observation during a GMod playtest.
if SERVER then AddCSLuaFile() end

local prefix = "[D6 Support QA] "
local function finite(number)
    return isnumber(number) and number == number and math.abs(number) < math.huge
end
local function finiteVector(vector)
    return isvector(vector) and finite(vector.x) and finite(vector.y) and finite(vector.z)
end
local function reporter(ply)
    local checks, failures, warnings = 0, 0, 0
    local function line(message)
        MsgN(prefix..message)
        if SERVER and IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE,prefix..message.."\n") end
    end
    local function check(name, pass)
        checks=checks+1
        if not pass then failures=failures+1 end
        line((pass and "PASS" or "FAIL").." | "..name)
    end
    local function warn(message) warnings=warnings+1;line("WARN | "..message) end
    local function finish()
        line(string.format("READ-ONLY SNAPSHOT | %d checks | %d failures | %d warnings",checks,failures,warnings))
    end
    return line,check,warn,finish
end

if SERVER then
    concommand.Add("d6_support_verify",function(ply,_,args)
        if IsValid(ply) and not ply:IsAdmin() then return end
        local line,check,warn,finish=reporter(ply)
        local S=D6_Supports
        if not S or not S.Players then line("addon support manager is not loaded");return end
        local pilots
        if args[1] then
            local index=tonumber(args[1])
            local target=index and Entity(index)
            if not IsValid(target) or not target:IsPlayer() then line("expected a player entity index");return end
            pilots={target}
        elseif IsValid(ply) then pilots={ply}
        else pilots=player.GetAll() end
        check("support limit is three",S.MaxActive==3)
        check("finite support ammunition is registered",game.GetAmmoID(S.Ammo)>=0 and S.MaxAmmo==6)
        check("projectile integration is loaded",D6_Wep and isfunction(D6_Wep.StepProjectile)
            and isfunction(S.TraceProjectile) and isfunction(S.HandleProjectile))
        check("rail integration contract is loaded",isfunction(S.TraceRail) and isfunction(S.HitRail))
        local all=ents.FindByClass("d6_support")
        local actualByOwner={}
        for _,ent in ipairs(all) do
            local owner=ent:GetOwner()
            check("body "..ent:EntIndex().." has a live player owner",IsValid(owner) and owner:IsPlayer())
            if IsValid(owner) then
                actualByOwner[owner]=actualByOwner[owner] or {}
                actualByOwner[owner][#actualByOwner[owner]+1]=ent
            end
        end
        local states={docked=true,deploying=true,active=true,returning=true}
        for _,pilot in ipairs(pilots) do
            local tag="player "..pilot:EntIndex()
            local live=actualByOwner[pilot] or {}
            local rec=S.Players[pilot]
            local ammo=pilot:GetAmmoCount(S.Ammo)
            line(string.format("%s | flight=%s bodies=%d stock=%d/%d energy=%.1f",tag,
                tostring(S.CanUse(pilot)),#live,ammo,S.MaxAmmo,
                D6_Energy and D6_Energy.Get(pilot) or pilot:GetNWFloat("D6_Energy",0)))
            check(tag.." owns at most three real entities",#live<=S.MaxActive)
            check(tag.." stock is finite and within cap",finite(ammo) and ammo>=0 and ammo<=S.MaxAmmo)
            if S.CanUse(pilot) and #live<S.MaxActive then
                warn(tag.." has fewer than three bodies; inspect placement clearance/retry state")
            elseif not S.CanUse(pilot) and #live>0 then
                warn(tag.." still has bodies outside flight; repeat after the next Think cleanup")
            end
            local seen,tracked={},{}
            for slot,id in ipairs(S.GetLoadout(pilot)) do
                local def=S.Definitions[id]
                local ent=S.GetEntity(pilot,slot)
                local deadline=pilot:GetNW2Float("D6_SupportReady"..slot,0)
                check(tag.." slot "..slot.." has a unique known type",def~=nil and not seen[id])
                seen[id]=true
                check(tag.." slot "..slot.." cooldown is finite",finite(deadline) and deadline>=0)
                line(string.format("  slot=%d type=%s body=%s mode=%s ready_in=%.2fs",slot,id,
                    IsValid(ent) and tostring(ent:EntIndex()) or "missing",S.GetState(pilot,slot),
                    math.max(0,deadline-CurTime())))
                if IsValid(ent) then
                    tracked[ent]=true
                    check(tag.." slot "..slot.." registry and network agree",rec and rec.entities[slot]==ent
                        and ent:GetClass()=="d6_support" and ent:GetOwner()==pilot
                        and ent.D6_SupportSlot==slot and ent.D6_SupportKind==id
                        and ent:GetNWString("D6_SupportKind","")==id)
                    check(tag.." slot "..slot.." is a separate non-solid support",not ent:IsNPC()
                        and ent:GetSolid()==SOLID_NONE and ent:GetMoveType()==MOVETYPE_NONE)
                    check(tag.." slot "..slot.." has valid state",states[ent.D6_SupportMode]==true
                        and ent:GetNWString("D6_SupportState","")==ent.D6_SupportMode)
                    check(tag.." slot "..slot.." lies in world",finiteVector(ent:GetPos()) and util.IsInWorld(ent:GetPos()))
                    if def then
                        for port=1,#def.ports do
                            local pos=S.Socket(ent,port)
                            check(tag.." slot "..slot.." port "..port.." is finite",finiteVector(pos))
                        end
                    end
                    if ent.D6_SupportMode=="docked" then
                        check(tag.." slot "..slot.." is cold while docked",ent:GetNWFloat("D6_SupportPower",0)==0)
                    end
                elseif rec and IsValid(rec.entities[slot]) then
                    check(tag.." slot "..slot.." registry is visible through network reference",false)
                end
            end
            for _,ent in ipairs(live) do
                check(tag.." body "..ent:EntIndex().." belongs to a tracked slot",tracked[ent]==true)
            end
        end
        if #pilots==0 then warn("no player selected; flight/resource checks were skipped") end
        line("Procedural mesh presence is client-only; run d6_support_verify_client there.")
        finish()
    end)
else
    concommand.Add("d6_support_verify_client",function()
        local pilot=LocalPlayer()
        if not IsValid(pilot) or not pilot:IsAdmin() then return end
        local line,check,warn,finish=reporter()
        local S,G=D6_Supports,D6_ArtGeometry
        if not S or not G then line("shared catalogue or client geometry is not loaded");return end
        check("support UI loaded after interface",D6_SupportUI and isfunction(D6_SupportUI.Snapshot)
            and D6_Interface and isfunction(D6_Interface.Snapshot))
        check("procedural renderer is available",D6_Art and isfunction(D6_Art.Draw))
        for _,def in ipairs(S.Order) do
            local model=G.models[def.mesh]
            local triangles=0
            if model and model.parts then for _,faces in pairs(model.parts) do triangles=triangles+#faces end end
            check(def.id.." mesh is loaded with triangles",triangles>0)
            line(string.format("  %s | mesh=%s triangles=%d ports=%d",def.id,def.mesh,triangles,#def.ports))
        end
        for slot,id in ipairs(S.GetLoadout(pilot)) do
            local ent=S.GetEntity(pilot,slot)
            if IsValid(ent) then
                check("slot "..slot.." entity type replicated",ent:GetClass()=="d6_support"
                    and ent:GetNWString("D6_SupportKind","")==id)
            else warn("slot "..slot.." entity not visible to this client; inspect server snapshot/PVS") end
        end
        line("Presence checks do not prove the draw result; inspect sockets, flash position and occlusion in play.")
        finish()
    end)
end
MsgN(prefix.."read-only commands loaded for "..(SERVER and "server" or "client"))
