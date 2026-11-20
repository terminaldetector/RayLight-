local G = D6_ArtGeometry
local tau = math.pi * 2

local function radial(angle, radius, z, offset)
    local tangent = offset or 0
    local cos, sin = math.cos(angle), math.sin(angle)
    return {cos * radius - sin * tangent, sin * radius + cos * tangent, z}
end

local function ring(radius, z, sides)
    local points = {}
    for i = 1, sides do
        points[i] = radial((i - .5) * tau / sides, radius, z)
    end
    return points
end

local function lathe(model, material, slices, sides, cap)
    local rings = {}
    for _, slice in ipairs(slices) do
        rings[#rings + 1] = ring(slice[1], slice[2], sides)
    end
    model:Rings(material, rings, {0, 0, (slices[1][2] + slices[#slices][2]) * .5}, cap)
end

-- Draw a closed annular sector so shutter faces, lips and recesses read from the shaft below.
local function segment(model, material, angle, spread, slices)
    local rings = {}
    for _, slice in ipairs(slices) do
        local inner, outer, z = slice[1], slice[2], slice[3]
        local a, b = angle - spread, angle + spread
        rings[#rings + 1] = {
            radial(a, inner, z), radial(a, outer, z), radial(angle, outer, z),
            radial(b, outer, z), radial(b, inner, z),
        }
    end
    local middle = slices[math.ceil(#slices * .5)]
    model:Rings(material, rings, radial(angle, (middle[1] + middle[2]) * .5, middle[3]))
end

local function conduit(model, angle, stations, radius, material)
    local previous
    for _, station in ipairs(stations) do
        local point = radial(angle, station[1], station[2])
        if previous then
            model:Rod(material, previous, point, radius, 12)
        end
        previous = point
    end
end

local frame = G.New("reactor_frame")
for _, side in ipairs({-1, 1}) do
    frame.section = side > 0 and "Suspension head" or "Induction return head"
    lathe(frame, "arc_plate", {{67,side*107},{75,side*113},{75,side*126},{63,side*132},
        {46,side*132},{38,side*141},{25,side*142}}, 24)
    lathe(frame, "turned_steel", {{76,side*117},{77.5,side*119},{77.5,side*123},{76,side*125}}, 24, false)
    lathe(frame, "frame", {{42,side*132},{42,side*137},{38,side*142},{22,side*146}}, 16)
    lathe(frame, "dark", {{23,side*140},{25,side*143},{25,side*146},{22,side*150}}, 16)
    lathe(frame, "emit", {{19,side*147},{19,side*150}}, 16)

    for i = 0, 7 do
        local angle = (i + .5) * tau / 8
        frame.section = "Stationary actuator rails"
        segment(frame, "black_steel", angle, .105, {{65,99,side*101},{70,112,side*109},
            {71,113,side*121},{61,96,side*130}})
        local bolt = radial(angle, 96, side * 121)
        frame:Rod("turned_steel", bolt, {bolt[1],bolt[2],bolt[3]+side*6}, 4.55, 6)
        frame:Rod("rubber", radial(angle,100,13*side), radial(angle,100,110*side), 4.7, 8)
        frame:Rod("turned_steel", radial(angle,102,27*side), radial(angle,102,79*side), 3.42, 8)
        segment(frame, "arc_sink", angle, .064, {{95,109,side*92},{95,111,side*117}})
    end
end

for i = 0, 3 do
    local angle = tau * (i + .5) / 4
    frame.section = "Double-walled cooling feed"
    conduit(frame, angle, {{50,-130},{81,-130},{109,-117},{125,-91},{127,-66},{127,66},
        {125,91},{109,117},{81,130},{50,130}}, 8, "black_steel")
    conduit(frame, angle + .08, {{76,-121},{113,-110},{132,-80},{132,-64}}, 3.6, "copper")
    conduit(frame, angle + .08, {{76,121},{113,110},{132,80},{132,64}}, 3.6, "copper")
    for _, z in ipairs({-87,-70,-42,0,42,70,87}) do
        frame:Rod("turned_steel", radial(angle,127,z-3.2), radial(angle,127,z+3.2), 10.7, 12)
    end
    local start, finish = radial(angle,127,-59), radial(angle,127,59)
    frame:Rod("dark", start, finish, 7.7, 12)
    for j = -5, 5 do
        local z = j*10
        frame:Rod("arc_shell", radial(angle,127,z-1.25), radial(angle,127,z+1.25), 9.7, 12)
    end
    segment(frame, "emit", angle, .014, {{135,136,-42},{135,136,42}})
    segment(frame, "arc_plate", angle, .085, {{121,130,-26},{121,139,-18},{121,139,18},{121,130,26}})
    segment(frame, "hazard", angle, .037, {{139,140,-15},{139,140,-10}})
    segment(frame, "hazard", angle, .037, {{139,140,-4},{139,140,1}})
    segment(frame, "hazard", angle, .037, {{139,140,7},{139,140,12}})
end

for _, side in ipairs({-1, 1}) do
    local shutter = G.New(side > 0 and "reactor_shutter_upper" or "reactor_shutter_lower")
    for i = 0, 7 do
        local angle = i * tau / 8
        shutter.section = "Bevelled armour petal"
        segment(shutter, "siege_cast", angle, .325, {{70,84,side*14},{70,98,side*23},
            {73,108,side*43},{79,109,side*78},{66,91,side*103},{63,76,side*111}})
        segment(shutter, "arc_plate", angle, .260, {{98,104,side*34},{104,112,side*43},
            {106,113,side*68},{99,108,side*86},{91,96,side*96}})
        segment(shutter, "turned_steel", angle, .190, {{111,113.2,side*57},{111,113.2,side*60}})
        segment(shutter, "dark", angle, .145, {{106,109,side*73},{101,109,side*84},
            {98,104,side*91}})
        for vent = 0, 2 do
            local z = (75 + vent*3.4) * side
            segment(shutter, "emit", angle, .107, {{108,110,z},{108,110,z+side*1.2}})
        end
        segment(shutter, "steel", angle - .304, .017, {{95,97,side*29},{107,109,side*48},
            {108,110,side*76},{89,91,side*103}})
        local nose = radial(angle, 95, side*23)
        shutter:Rod("black_steel", nose, radial(angle,101,side*27), 7, 10)
        shutter:Rod("turned_steel", radial(angle,101,side*27), radial(angle,102.4,side*28), 4.5, 6)
    end
end

local vessel = G.New("reactor_vessel")
vessel.section = "Exposed induction chamber"
lathe(vessel, "arc_shell", {{30,-60},{45,-51},{55,-42},{60,-21},{60,21},{55,42},{45,51},{30,60}}, 24)
lathe(vessel, "emit", {{58,-36},{60,-29},{62,-14},{62,14},{60,29},{58,36}}, 24)
lathe(vessel, "arc_sink", {{59,-26},{63,-23},{63,-18},{62,-16}}, 24, false)
lathe(vessel, "arc_sink", {{62,16},{63,18},{63,23},{59,26}}, 24, false)
for i = 0, 7 do
    local angle = (i + .5) * tau / 8
    segment(vessel, "black_steel", angle, .074, {{58,65,-44},{60,66,-25},{61,67,-13},
        {61,67,13},{60,66,25},{58,65,44}})
    segment(vessel, "turned_steel", angle, .034, {{65,66,-27},{66,68,-15},{66,68,15},{65,66,27}})
end

local field = G.New("reactor_field_collar")
for i = 0, 7 do
    local angle = i * tau / 8
    segment(field, "black_steel", angle, .335, {{64,72,-6},{63,75,-3},{63,75,3},{64,72,6}})
    segment(field, "emit", angle, .220, {{75,76,-2.5},{75,76,2.5}})
    field:Rod("turned_steel", radial(angle + .27,74,-3.2), radial(angle + .27,74,3.2), 2.9, 8)
end

local coolant = G.New("reactor_coolant")
coolant.section = "Sealed coolant manifold"
lathe(coolant, "arc_plate", {{19,-56},{32,-53},{39,-45},{42,-34},{34,-24},
    {34,24},{42,34},{39,46},{33,53},{20,57}}, 16)
lathe(coolant, "arc_sink", {{33,-29},{39,-24},{39,-17},{36,-13}}, 16, false)
lathe(coolant, "arc_sink", {{36,13},{39,17},{39,24},{33,29}}, 16, false)
lathe(coolant, "emit", {{33,-14},{35,-11},{35,11},{33,14}}, 16)
for i = 0, 5 do
    local angle = i * tau / 6
    segment(coolant, "siege_cast", angle, .145, {{32,43,-43},{34,47,-32},{34,46,-25},
        {33,39,-12},{33,39,12},{34,46,25},{34,47,32},{32,43,43}})
    segment(coolant, "hazard", angle, .09, {{45,47,24},{46,48,29}})
    coolant:Rod("turned_steel", radial(angle,47,28), radial(angle,47,33), 2.6, 6)
end
lathe(coolant, "dark", {{14,48},{18,51},{18,57},{15,61}}, 12)
lathe(coolant, "emit", {{13,59},{13,61}}, 12)

if not CLIENT then return end

D6_ReactorVisual = {}
local R = D6_ReactorVisual
local blue, red, gold = Color(88,190,255), Color(255,61,37), Color(255,174,71)
local white = Color(247,241,223)
local glow = Material("sprites/light_glow02_add")
local discharge = Material("sprites/laserbeam")

local function colorBetween(a, b, fraction)
    return Color(Lerp(fraction,a.r,b.r), Lerp(fraction,a.g,b.g), Lerp(fraction,a.b,b.b))
end

local function arc(pos, angles, now, phase, index, ink)
    local a = (index + math.floor(now * 12) * .136) * tau / 4
    local tick = (now * (index + 4)) % 1
    if tick > .26 then return end
    render.SetMaterial(discharge)
    render.StartBeam(6)
    for step = 0, 5 do
        local fraction = step / 5
        local envelope = math.sin(fraction * math.pi)
        local offset = math.sin(now*91+step*1.92) * envelope * 13
        local z = -5 + envelope*math.cos(now*36+index)*42 + fraction*(phase==3 and -40 or 19)
        local point = radial(a, 64 + fraction*55, z, offset)
        local world = LocalToWorld(Vector(unpack(point)), angle_zero, pos, angles)
        render.AddBeam(world, 4.8 - fraction * 2.6, fraction, step % 2==0 and ink or white)
    end
    render.EndBeam()
end

local function glowAt(pos, ink, diameter, power)
    render.SetMaterial(glow)
    render.DrawSprite(pos, diameter, diameter, Color(ink.r,ink.g,ink.b,138*power))
end

local function lightFor(ent, ink, size, strength, now)
    local light = DynamicLight(ent:EntIndex())
    if not light then return end
    light.pos = ent:GetPos()
    light.r, light.g, light.b = ink.r, ink.g, ink.b
    light.brightness, light.size, light.decay = strength, size, size*3
    light.dietime = now + .16
end

function R.Draw(ent)
    local art = D6_Art
    if not art then return end
    local pos, angles, now = ent:GetPos(), ent:GetAngles(), CurTime()
    local charge = math.Clamp(ent:GetCharge(), 0, 1)
    local phase = ent:GetReactorPhase()
    local health = math.Clamp(ent:GetHealthFraction(), 0, 1)
    local tick = now + ent:EntIndex()*.1

    if ent:GetNodeKind() == 1 then
        local enabled = ent:GetNodeEnabled()
        local ink = enabled and colorBetween(blue, gold, 1 - health) or Color(77,94,101)
        local power = enabled and .64 + .22 * math.sin(tick*(4 + (1-health)*15)) or .17
        art.Draw("reactor_coolant", pos, angles, 1, ink, power, true)
        if enabled then
            glowAt(pos + angles:Up()*59, ink, 31, power)
            lightFor(ent, ink, 138, power*.55, now)
        end
        return
    end

    local openingGoal = phase >= 2 and 1 or 0
    local opening = math.Approach(ent.D6_ReactorOpening or 0, openingGoal, FrameTime()*.73)
    ent.D6_ReactorOpening = opening
    local liquidInk = charge < .72 and colorBetween(blue,gold,charge/.72) or
        colorBetween(gold,red,(charge-.72)/.28)
    local ink = phase == 3 and colorBetween(red,gold,.3+.25*math.sin(tick*15)) or liquidInk
    local pulse = .55 + .18*math.sin(tick*(4 + charge*8)) + .19*charge
    local up, slide = angles:Up(), 51*opening
    art.Draw("reactor_frame", pos, angles, 1, phase == 3 and red or blue, pulse, true)
    art.Draw("reactor_shutter_upper", pos + up*slide, angles, 1, ink, pulse, true)
    art.Draw("reactor_shutter_lower", pos - up*slide, angles, 1, ink, pulse, true)
    art.Draw("reactor_vessel", pos, angles, 1, ink, (.26 + opening*.74)*pulse, true)

    local spin = (ent.D6_ReactorSpin or 0) + FrameTime()*(24 + charge*80 + (1-health)*21)
    ent.D6_ReactorSpin = spin % 360
    for _, side in ipairs({-1,1}) do
        local rotor = Angle(angles.p, angles.y, angles.r)
        rotor:RotateAroundAxis(up, spin*side)
        art.Draw("reactor_field_collar", pos + up*side*(13 + 22*opening), rotor, 1, ink, pulse, true)
    end

    glowAt(pos, ink, 84 + 96*opening, pulse * (.2 + .8*opening))
    if opening > .35 then
        for index = 0, 3 do arc(pos, angles, now, phase, index, ink) end
    end
    lightFor(ent, ink, 176 + opening*130, pulse*(.65 + opening*.6), now)
end
