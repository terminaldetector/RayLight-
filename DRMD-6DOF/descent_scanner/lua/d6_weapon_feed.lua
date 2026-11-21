-- Server-owned weapon cycles and finite reserve ammunition.
-- A cycle counts trigger pulls, not the projectiles or pellets in one volley.
-- Reloading restores local capacity only; it never creates reserve ammunition.
if SERVER then AddCSLuaFile() end

D6_WeaponFeed = D6_WeaponFeed or {}
local F = D6_WeaponFeed

local function policyFor(weapon)
    local class = type(weapon) == "string" and weapon
        or (IsValid(weapon) and weapon:GetClass())
    return D6_Arsenal and D6_Arsenal.Operating and D6_Arsenal.Operating[class]
end

-- Project an elapsed reload without mutating the weapon. Failed payment must not
-- consume a cycle, start a reload or alter the remaining reserve.
local function cycle(weapon, policy, now)
    local capacity = policy.capacity or 0
    if capacity <= 0 then return 0, 0 end
    local remaining, reloadAt
    if SERVER then
        local state = weapon.D6_FeedState
        remaining = state and state.remaining or capacity
        reloadAt = state and state.reloadAt or 0
    else
        remaining = weapon:GetNW2Int("D6_FeedRemaining", capacity)
        reloadAt = weapon:GetNW2Float("D6_FeedReloadAt", 0)
    end
    if reloadAt > 0 and now >= reloadAt then return capacity, 0 end
    return remaining, reloadAt
end

-- Shared HUD contract. A past reload deadline is presented as ready even while
-- the weapon is holstered; no per-frame network traffic or reload timer is needed.
function F.Status(weapon, now)
    if not IsValid(weapon) then return nil end
    local policy = policyFor(weapon)
    if not policy then return nil end
    local remaining, reloadAt = cycle(weapon, policy, now or CurTime())
    local owner = weapon:GetOwner()
    return {
        tier = policy.tier, kind = policy.kind,
        remaining = remaining, capacity = policy.capacity or 0, reloadAt = reloadAt,
        ammo = policy.ammo, maxAmmo = policy.maxAmmo,
        ammoCount = policy.ammo and IsValid(owner) and owner:GetAmmoCount(policy.ammo) or nil,
    }
end

-- Only the precision rail's explicitly named secondary action may omit primary
-- ammunition/capacity. Main attacks do not pass a context. This is not a generic
-- "skip resources" option and is never accepted from a network message.
function F.TrySpend(weapon, owner, amount, context)
    if not SERVER or not IsValid(weapon) or not IsValid(owner)
        or weapon:GetOwner() ~= owner then return false, "invalid" end
    local utility = context == "rail_lure" and weapon:GetClass() == "weapon_d6_railmk2"
    if context ~= nil and not utility then return false, "context" end

    local policy = policyFor(weapon)
    local remaining, reloadAt = 0, 0
    local now = CurTime()
    if policy and not utility then
        remaining, reloadAt = cycle(weapon, policy, now)
        if reloadAt > now then return false, "reload" end
        if policy.ammo and owner:GetAmmoCount(policy.ammo) < 1 then return false, "ammo" end
    end

    local energy = amount or 0
    if policy and not utility and policy.energy ~= nil then energy = policy.energy end
    if energy > 0 and not D6_Energy.TryConsume(owner, "weapons", energy) then
        return false, "energy"
    end

    -- There is no yield between preflight and commit. The engine's fire timestamp
    -- is intentionally not checked: charged weapons reserve it while charging.
    if policy and not utility then
        if policy.ammo then owner:RemoveAmmo(1, policy.ammo) end
        if (policy.capacity or 0) > 0 then
            remaining = remaining - 1
            reloadAt = remaining == 0 and (now + (policy.reload or 0)) or 0
            weapon.D6_FeedState = {remaining = remaining, reloadAt = reloadAt}
            weapon:SetNW2Int("D6_FeedRemaining", remaining)
            weapon:SetNW2Float("D6_FeedReloadAt", reloadAt)
        end
    end
    return true
end

local function grant(owner, ammo, amount, maximum)
    local before = owner:GetAmmoCount(ammo)
    local count = math.max(0, math.min(math.floor(amount or 0), (maximum or 0) - before))
    if count <= 0 then return 0 end
    owner:GiveAmmo(count, ammo, true)
    return math.max(0, owner:GetAmmoCount(ammo) - before)
end

-- The acquisition/loadout code owns when this is called. It raises a newly
-- acquired weapon's reserve to its starting amount, never adds a second starting
-- pack when another weapon uses the same ammunition (both mine types do).
function F.GrantInitial(owner, class)
    if not SERVER or not IsValid(owner) then return 0 end
    local policy = policyFor(class)
    if not policy or not policy.ammo then return 0 end
    return grant(owner, policy.ammo,
        (policy.initialAmmo or 0) - owner:GetAmmoCount(policy.ammo), policy.maxAmmo)
end

-- Common pickups replenish each owned ammo family once. A rare pickup grants
-- exactly one BFG cell if that module is owned; time and common supplies grant none.
function F.Restock(owner, rare)
    if not SERVER or not IsValid(owner) then return 0 end
    local supplies = {}
    for _, weapon in ipairs(owner:GetWeapons()) do
        local policy = policyFor(weapon)
        if policy and policy.ammo then
            local amount = rare and (policy.ammo == "d6_bfg_cell" and 1 or 0)
                or (not rare and (policy.pickup or 0) or 0)
            local pack = supplies[policy.ammo]
            if not pack then
                supplies[policy.ammo] = {amount = amount, maximum = policy.maxAmmo or 0}
            else
                pack.amount = math.max(pack.amount, amount)
                pack.maximum = math.max(pack.maximum, policy.maxAmmo or 0)
            end
        end
    end
    local added = 0
    for ammo, pack in pairs(supplies) do
        added = added + grant(owner, ammo, pack.amount, pack.maximum)
    end
    if not rare and D6_Supports and D6_Supports.Restock then
        added = added + D6_Supports.Restock(owner)
    end
    return added
end
