D6_Drones = {}
local D = D6_Drones

local function airframe(mesh, color, scale, role, faction, guns)
    return {mesh = mesh, color = Color(color[1], color[2], color[3]), scale = scale,
        role = role, faction = faction or "combine", guns = guns}
end

-- Coordinates on the authored meshes are forward, model-left, up.
D.Types = {
    assault = airframe("assault", {218,156,107}, 1, "screen", nil, {{19,16,-4.6},{19,-16,-4.6}}),
    mg = airframe("combine_gunner", {228,159,109}, 0.93, "screen", nil, {{25,14,-1.8},{25,-14,-1.8}}),
    laser = airframe("combine_laser", {127,206,222}, 0.91, "flank", nil, {{27,0,0}}),
    interceptor = airframe("interceptor", {130,205,215}, 0.97, "flank", nil, {{16.4,12.3,-3.1},{16.4,-12.3,-3.1}}),
    rpg = airframe("combine_rocketeer", {237,172,97}, 1.04, "rear", nil, {{15,11.8,8},{15,-11.8,8}}),
    artillery = airframe("artillery", {242,183,110}, 0.96, "rear", nil, {{16.7,19,10},{16.7,-19,10}}),
    rocket_elite_homing = airframe("elite_homing", {125,191,221}, 1.12, nil, nil, {{21.7,16.8,5.5}}),
    rocket_elite_aa = airframe("elite_aa", {239,142,96}, 1.16, nil, nil, {{16.3,17,11.4},{16.3,-17,11.4}}),
    grav = airframe("grav", {175,132,230}, 1.16, "gravity", nil, {{24,0,0}}),
    support = airframe("support", {146,220,180}, 0.94, "support", nil, {{21.4,15.5,0.3},{21.4,-15.5,0.3}}),
    heavy = airframe("heavy", {228,145,119}, 1.02, nil, nil, {{35.3,0,-5.2}}),
    heavy_elite = airframe("combine_elite", {228,87,75}, D6_Session.Enforcer.scale),
    arc_elite = airframe("combine_arc_elite", {113,205,246}, D6_Session.ArcElite.scale, nil, nil,
        {{36.2,26.4,1.35},{36.2,-26.4,1.35},{16.45,0,-18.2}}),
    seeker = airframe("combine_seeker", {185,150,222}, 1.22, nil, nil, {{14,17,2.1},{14,-17,2.1}}),
    rocket_strider = airframe("rocket_strider", {237,98,85}, 1.35, nil, nil, {{19.2,33,10},{19.2,-33,10}}),
    plasma_strider = airframe("plasma_strider", {103,181,221}, 1.48, nil, nil, {{36.5,0,-1}}),
    manhack_fast = airframe("cutter", {247,135,88}, 0.78),
    wheatley = airframe("cutting_probe", {146,186,217}, 0.91),
    chopper = airframe("combine_gunship", {226,166,105}, 1.28, nil, nil, {{34,0,-5.6}}),
    worm = airframe("worm", {159,195,117}, 1.0),
    mine = airframe("mine", {230,141,79}, 0.85),
    resistance_scout = airframe("resistance_scout", {176,161,119}, 0.88, "flank", "resistance", {{24.8,-0.48,0.06}}),
    resistance_raider = airframe("resistance_raider", {216,155,104}, 1.0, "screen", "resistance", {{22.5,-13.25,-2.1},{21.7,1.7,1.85}}),
    resistance_hauler = airframe("resistance_hauler", {221,171,113}, 1.17, "rear", "resistance", {{23.2,17.4,-0.5},{23.5,-17.4,0.6}}),
}

function D.Get(ent)
    return D.Types[ent:GetNW2String("D6_ArtVariant", "")]
end

function D.Muzzle(ent, slot, fallback)
    local art = D.Get(ent)
    local guns = art and art.guns
    local point = guns and (guns[slot] or guns[1])
    if not point then return fallback or ent:GetPos() end
    local ang = ent:GetAngles()
    return ent:GetPos() + (ang:Forward()*point[1] - ang:Right()*point[2] + ang:Up()*point[3])*art.scale
end
