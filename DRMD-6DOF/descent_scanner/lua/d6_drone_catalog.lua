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
        {{36.2,26.4,1.35},{36.2,-26.4,1.35},{25.35,0,-18.2},{27.48,0,3.99},
            {9.58,2.56,22.10},{9.58,-2.56,22.10},{34.43,28.14,4.58},{34.43,-28.14,4.58}}),
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

D.Rigs = {
    combine_elite = {
        travel = {left=.82, right=.82, rockets_left=.32, rockets_right=.32},
        sections = {
            ["Port cannon"]="left", ["Starboard cannon"]="right",
            ["Port rocket cassette"]="rockets_left", ["Starboard rocket cassette"]="rockets_right",
        },
    },
    combine_arc_elite = {
        ports = {"left","right","thermal","eye","rack","rack","left_rotor","right_rotor"},
        travel = {left=.64, right=.64, thermal=.38, rack=.28},
        hinges = {left={-4.7,19.5,1},right={-4.7,-19.5,1}},
        rotors = {
            left_rotor={bank="left",pivot={20.5,26.4,4.58}},
            right_rotor={bank="right",pivot={20.5,-26.4,4.58}},
        },
        sections = {
            ["Port arc emitter and carriage"]="left", ["Starboard arc emitter and carriage"]="right",
            ["Port rotary barrels"]="left_rotor", ["Starboard rotary barrels"]="right_rotor",
            ["Ventral accelerator"]="thermal", ["Optical head"]="eye", ["Dorsal plasma rack"]="rack",
        },
    },
}

local pair = {
    ports={"left","right"},
    travel={left=.67,right=.67},
    sections={["Port armature"]="left",["Starboard armature"]="right"},
}
for _, name in ipairs({"assault","interceptor","combine_gunner","combine_rocketeer","artillery","combine_seeker","support"}) do
    D.Rigs[name]=pair
end
D.Rigs.combine_laser = {
    ports={"optic"}, travel={optic=.56}, sections={["Focusing cage"]="optic"},
}

function D.PortBank(ent, slot)
    local art=D.Get(ent)
    local rig=art and D.Rigs[art.mesh]
    return rig and rig.ports and rig.ports[slot]
end

function D.Recoil(ent, bank, now)
    if not bank then return 0 end
    local art=D.Get(ent)
    local rig=art and D.Rigs[art.mesh]
    local travel=rig and rig.travel[bank]
    if not travel then return 0 end
    local age=now-ent:GetNW2Float("D6_WeaponCycle_"..bank,-20)
    if age<0 or age>=.22 then return 0 end
    if age<.035 then return travel*age/.035 end
    return travel*(1-(age-.035)/.185)^2
end

function D.Fired(ent, bank)
    if bank then ent:SetNW2Float("D6_WeaponCycle_"..bank,CurTime()) end
end

local function basis(angle,point,scale)
    return (angle:Forward()*point[1]-angle:Right()*point[2]+angle:Up()*point[3])*scale
end

function D.TrackBanks(ent,aim,dt)
    local art=D.Get(ent)
    local rig=art and D.Rigs[art.mesh]
    if not rig or not rig.hinges then return end
    local localAim=WorldToLocal(aim,angle_zero,ent:GetPos(),ent:GetAngles())/art.scale
    for bank,hinge in pairs(rig.hinges) do
        local key="D6_BankAngle_"..bank
        local desired=(localAim-Vector(unpack(hinge))):Angle()
        desired.r=0
        ent:SetNW2Angle(key,LerpAngle(math.min(1,dt*8),ent:GetNW2Angle(key,angle_zero),desired))
    end
end

function D.Spin(ent, duration)
    ent:SetNW2Float("D6_RotaryStart",CurTime())
    ent:SetNW2Float("D6_RotaryEnd",CurTime()+duration)
end

local function spinAngle(ent,now)
    local start=ent:GetNW2Float("D6_RotaryStart",-5)
    local untilTime=ent:GetNW2Float("D6_RotaryEnd",-5)
    if now>untilTime+.28 then return 0 end
    local age=math.max(0,now-start)
    local acceleration=math.min(age,.35)
    return (640*(acceleration*acceleration/.70+math.max(0,age-.35)))%360
end

function D.BankPose(ent,bank,now)
    local art=D.Get(ent)
    local rig=art and D.Rigs[art.mesh]
    local pos,angle=ent:GetPos(),ent:GetAngles()
    local scale=art and art.scale or 1
    local rotor=rig and rig.rotors and rig.rotors[bank]
    local linked=rotor and rotor.bank or bank
    local pivot=rig and rig.hinges and rig.hinges[linked]
    if pivot then
        local world=pos+basis(angle,pivot,scale)
        local _,rotated=LocalToWorld(vector_origin,ent:GetNW2Angle("D6_BankAngle_"..linked,angle_zero),vector_origin,angle)
        angle=rotated
        pos=world-basis(angle,pivot,scale)
    end
    pos=pos-angle:Forward()*(D.Recoil(ent,linked,now)*scale)
    if rotor then
        local world=pos+basis(angle,rotor.pivot,scale)
        angle=Angle(angle.p,angle.y,angle.r)
        angle:RotateAroundAxis(angle:Forward(),spinAngle(ent,now))
        pos=world-basis(angle,rotor.pivot,scale)
    end
    return pos,angle
end

function D.Socket(ent,point,bank)
    local art=D.Get(ent)
    local pos,angle=D.BankPose(ent,bank,CurTime())
    return pos+basis(angle,point,art and art.scale or 1)
end

function D.Muzzle(ent, slot, fallback)
    local art = D.Get(ent)
    local guns = art and art.guns
    local point = guns and (guns[slot] or guns[1])
    if not point then return fallback or ent:GetPos() end
    return D.Socket(ent,point,D.PortBank(ent,guns[slot] and slot or 1))
end
