-- First-person projection of the four physical mounts. These offsets are visual
-- only: simulation and world muzzle positions remain D6_Arsenal.MountOrigin/Port.
D6_ViewMounts = {}
local V = D6_ViewMounts
V.Slots = {
    {pos = {24, -16, -5}, scale = 0.64},
    {pos = {24,  16, -5}, scale = 0.64},
    {pos = {23,   0, 11}, scale = 0.60},
    {pos = {24,   0,-12}, scale = 0.60},
}

function V.Collect(ply, arsenal, hasOverride)
    local active = ply:GetActiveWeapon()
    local activeClass = IsValid(active) and active:GetClass() or ""
    local mounts = {}
    for slot = 1, 4 do
        local class = arsenal.Get(ply, slot)
        local item = arsenal.Entries[class]
        if item then
            mounts[#mounts + 1] = {
                slot = slot, item = item, weapon = ply:GetWeapon(class),
                active = class == activeClass,
                -- The SCK bridge renders its own active override. Other mounts
                -- must remain visible instead of returning from the entire pass.
                customActive = class == activeClass and hasOverride and hasOverride(class),
            }
        end
    end
    return mounts
end

function V.Pose(origin, angles, slot, aspect, drift, bob)
    local view = V.Slots[slot]
    if not view then return end
    -- Keep upper/lower mounts inside the shorter vertical field of ultrawide
    -- displays without moving their simulation sockets or covering the reticle.
    local vertical = math.min(1, (16/9) / math.max(aspect or 16/9, 0.1))
    local p = view.pos
    local position = origin + angles:Forward()*p[1]
        + angles:Right()*(p[2] + math.Clamp(drift or 0, -0.6, 0.6))
        + angles:Up()*(p[3]*vertical + (bob or 0))
    return position, view.scale*math.max(0.72, vertical)
end
