D6_Supplies={}
local S=D6_Supplies
S.Vault="d6_relay_vault"
S.Types={
    battery={name="Энергобанк",color=Color(99,220,232)},
    repair={name="Ремкомплект",color=Color(167,226,134)},
    ammo={name="Боезапас",color=Color(244,180,100)},
    core={name="Ионный заряд",color=Color(188,245,139)},
    module={name="Оружейный модуль",color=Color(171,151,245)},
}

if not SERVER then return end

function S.Spawn(pos,kind,class,owner)
    if not S.Types[kind] then return end
    local ent=ents.Create("d6_supply")
    if not IsValid(ent) then return end
    ent.D6_Payload=kind
    ent.D6_Module=class
    ent.D6_Pilot=owner
    ent:SetPos(pos)
    ent:Spawn()
    return ent
end

function S.Collect(cache,ply)
    local kind=cache.D6_Payload
    if kind=="battery" then
        if D6_Energy.Get(ply)>=D6_Energy.GetMax(ply) then return end
        D6_Energy.Add(ply,46)
    elseif kind=="repair" then
        local shield,max=ply:GetNWFloat("D6_Shield",0),ply:GetNWFloat("D6_ShieldMax",100)
        if ply:Health()>=ply:GetMaxHealth() and shield>=max then return end
        ply:SetHealth(math.min(ply:GetMaxHealth(),ply:Health()+36))
        ply:SetNWFloat("D6_Shield",math.min(max,shield+28))
    elseif kind=="ammo" then
        if D6_WeaponFeed.Restock(ply,false)<=0 then return end
    elseif kind=="core" then
        if D6_WeaponFeed.Restock(ply,true)<=0 then return end
    elseif kind=="module" then
        local class=D6_Arsenal.ResolveRewardClass(cache.D6_Module)
        if not class or ply:HasWeapon(class) or not IsValid(ply:Give(class,true)) then return end
        ply.D6_EpisodeUnlocks=ply.D6_EpisodeUnlocks or {}
        ply.D6_EpisodeUnlocks[class]=true
        D6_WeaponFeed.GrantInitial(ply,class)
        return "Новый модуль · "..D6_Arsenal.Entries[class].name
    else
        return
    end
    return S.Types[kind].name
end

local function populate()
    if not D6_Session.IsArena() then return end
    for _,marker in ipairs(ents.FindByName("d6_supply_*")) do
        local kind,value=marker:GetName():match("^d6_supply_([a-z]+)_(.+)$")
        if kind=="module" then S.Spawn(marker:GetPos(),kind,"weapon_d6_"..value)
        elseif kind~="reload" then S.Spawn(marker:GetPos(),kind) end
    end
end

hook.Add("InitPostEntity","D6_PlaceSupplies",populate)
hook.Add("PostCleanupMap","D6_ReplaceSupplies",populate)

function S.VaultReserve(ply,wave)
    if game.GetMap()~=S.Vault then return end
    if IsValid(ply.D6_VaultReserve) then ply.D6_VaultReserve:Remove() end
    local mark=ents.FindByName("d6_supply_reload_"..((wave-1)%3+1))[1]
    if not IsValid(mark) then return end
    local kind=({"battery","ammo","repair"})[(wave-1)%3+1]
    ply.D6_VaultReserve=S.Spawn(mark:GetPos(),kind,nil,ply)
end
