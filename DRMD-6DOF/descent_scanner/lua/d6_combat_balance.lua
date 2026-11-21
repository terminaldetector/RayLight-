D6_Balance={}
local B=D6_Balance
B.TierLabel={"I","II","III"}
B.WeaponTier={}

local tiers={
    {"mg","vulcan","flak","plasma","laser","whiplash","phasegate"},
    {"quad_laser","overdrive","rockets","concussion","homing","frag","gravy_railgun",
        "shockwave","energytrap","darkfield","warp","plasmamine","gravmine"},
    {"heavy","smart_missile","mega_missile","railmk2","darklance","bfg","telefrag","reactor","hyperbeam"},
}
for level,classes in ipairs(tiers) do
    for _,name in ipairs(classes) do B.WeaponTier["weapon_d6_"..name]=level end
end

local weaponScale={1.06,1,.90}
local light={interceptor=true,laser=true,mg=true,manhack_fast=true,wheatley=true,resistance_scout=true}
B.Reactor={
    heavy_elite={hull=820,shield=120,armor=99,quake=46,ram=39},
    arc_elite={hull=1010,shield=184,armor=148,wave=12},
}

function B.Tier(class)
    local policy = D6_Arsenal.Operating[class]
    return policy and policy.tier or B.WeaponTier[class]
end

function B.Damage(attacker,inflictor,target,value)
    if not IsValid(attacker) or not D6_Session.IsArena() then return value end
    if attacker:IsPlayer() and attacker.D6On and (target.D6_Variant or target.D6_EpisodeTarget) then
        local class=IsValid(inflictor) and inflictor.D6_WeaponClass
        local weapon=attacker:GetActiveWeapon()
        if not class and IsValid(inflictor) and inflictor:IsWeapon() then class=inflictor:GetClass() end
        if not class and IsValid(weapon) then class=weapon:GetClass() end
        return value*(weaponScale[B.Tier(class)] or 1)
    end
    if attacker.D6_Variant and target:IsPlayer() and target.D6On and light[attacker.D6_Variant] then
        return value*.90
    end
    return value
end
