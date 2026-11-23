if not SERVER then return end
local A = D6_Arsenal

-- Equipment acquisition is distinct from configuration. A saved mount never
-- unlocks a weapon, and re-entering flight never replenishes carried ammunition.
function D6_Session.GiveLoadout(ply, all)
    if not IsValid(ply) or not ply:IsPlayer() then return 0 end
    local count, unlocks = 0, {}
    for class, earned in pairs(ply.D6_EpisodeUnlocks or {}) do
        local resolved = earned and A.ResolveClass(class)
        if resolved then unlocks[resolved] = true end
    end
    ply.D6_EpisodeUnlocks = unlocks
    for _, item in ipairs(A.Order) do
        if all or A.Starting[item.class] or unlocks[item.class] then
            if not IsValid(ply:GetWeapon(item.class)) and IsValid(ply:Give(item.class, true)) then
                D6_WeaponFeed.GrantInitial(ply, item.class)
                count = count + 1
            end
        end
    end
    -- Workshop autoGive is an explicit sandbox integration; it never silently
    -- grants retired native modules or bypasses progression outside debug give.
    if all then
        for class, data in pairs(D6_Weapons or {}) do
            if data.autoGive and not A.Entries[class] and not IsValid(ply:GetWeapon(class)) then
                if IsValid(ply:Give(class, true)) then
                    for ammoType, amount in pairs(data.ammoOnGive or {}) do ply:GiveAmmo(amount, ammoType, true) end
                    count = count + 1
                end
            end
        end
        local filled = {}
        for _, item in ipairs(A.Order) do
            local policy = A.Operating[item.class]
            if policy.ammo and not filled[policy.ammo] and IsValid(ply:GetWeapon(item.class)) then
                local needed = math.max(0, policy.maxAmmo - ply:GetAmmoCount(policy.ammo))
                if needed > 0 then ply:GiveAmmo(needed, policy.ammo, true) end
                filled[policy.ammo] = true
            end
        end
    end
    A.EnsureOwned(ply)
    if D6_Supports then D6_Supports.GrantInitial(ply, all == true) end
    return count
end
