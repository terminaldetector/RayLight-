local G = D6_ArtGeometry
local sides = {-1, 1}

local function plate(model, material, side, points, bottom, top)
    local mirrored = {}
    for i, point in ipairs(points) do mirrored[i] = {point[1], point[2]*side} end
    model:Plate(material, mirrored, bottom, top)
end

local function vents(model, x, y, z, side, count, gap)
    for i = 1, count do
        local offset = (i - 1)*gap
        model:Box("dark", x - offset, y*side, z, gap*0.55, 4.2, 0.58)
        model:Box("steel", x - offset - 0.28, y*side, z + 0.17, gap*0.18, 3.45, 0.55)
    end
end

local function optic(model, x, y, z, radius)
    model:Collar(x - 3, x, y, z, radius, "emit")
    model:Box("frame", x - 1.55, y, z + radius + 0.1, 3.7, radius*1.72, radius*0.42)
end

local function fins(model, x, y, z, side)
    for i = 0, 2 do
        plate(model, "hazard", side, {{x-i*1.8,y},{x-1.1-i*1.8,y+2.2},{x-1.7-i*1.8,y+2.2},{x-0.6-i*1.8,y}},
            z, z + 0.23)
    end
end

-- Shallow spun shells, a central lens and exposed module rails from the scanner drawings.
local scanner = G.New("scanner_player")
local function shell(material, profile)
    local rings = {}
    for i, section in ipairs(profile) do
        rings[i] = {}
        for j = 1, 48 do
            local a = j*math.pi/24
            rings[i][j] = {-1.25 + math.cos(a)*section[2], math.sin(a)*section[3], section[1]}
        end
    end
    scanner:Rings(material, rings, {-1.25, 0, (profile[1][1] + profile[#profile][1])*0.5})
end
shell("steel", {{2.15,22.8,24.1},{4.8,22.25,23.55},{7.8,19.1,20.2},{10.5,13.8,15.2},{12.1,5.6,7.2}})
shell("frame", {{-9.6,8.8,12.2},{-8.2,14.8,17.3},{-5.3,20.05,21.85},{-1.4,22.8,24.1}})
shell("dark", {{-2.15,22.85,24.3},{-0.4,23.32,24.7},{0.75,23.32,24.7},{2.3,22.85,24.25}})
shell("edge", {{2.22,22.89,24.21},{2.75,22.83,24.18},{3.05,22.72,24.06}})
shell("hazard", {{-2.8,22.36,23.83},{-2.12,22.9,24.28},{-1.8,22.9,24.3}})
shell("dark", {{11.9,5.6,7.1},{12.48,5.45,6.8},{12.75,4.98,6.4}})
scanner:Loft("frame", 0, 1.04, {{14,8.9,7.1},{19,8.8,7.8},{23.7,6.8,6.6}})
scanner:Collar(19.2, 26.66, 0, 1.04, 5.58, "glass")
scanner:Rod("emit", {24.202,0,1.04}, {24.43,0,1.04}, 2.38, 32)
for j = 0, 11 do
    local a = j*math.pi/6
    local y, z = math.cos(a), math.sin(a)
    scanner:Rod("steel", {24.81,y*3.76,1.04+z*3.76}, {25.2,y*4.32,1.04+z*4.32}, 0.19, 6)
end
scanner:Box("frame", -6.7, 12.2, 10.5, 17, 5.5, 2.0)
scanner:Box("edge", -4.7, 12.2, 11.7, 16, 3.3, 0.75)
scanner:Rod("frame", {-7,13,9.3}, {-7,13,23.9}, 3.2, 10)
scanner:Rod("steel", {-12,13,10.75}, {-8.1,13,20.75}, 1.25, 10)
scanner:Box("edge", -7.2, 13, 19.8, 7.8, 6.6, 2.2)
scanner:Box("armor", -2.9, 6.4, -10.2, 20.1, 9.8, 4.3)
scanner:Box("dark", -12, 0, -18, 11.3, 12.9, 8.8)
scanner:Box("steel", -13.1, 0, -21.4, 11.7, 14.4, 2.0)
for _, s in ipairs(sides) do
    scanner:Box("frame", 1.6, s*23.25, -0.4, 18.4, 4.1, 4.7)
    scanner:Box("edge", 4.0, s*24.25, -0.4, 8.7, 2.1, 5.34)
    scanner:Rod("frame", {-3,s*10.3,-7.2}, {-11.8,s*16.8,-16.9}, 2.8, 10)
    scanner:Rod("steel", {-3,s*9.9,-7.1}, {-10.8,s*17.1,-15.8}, 1.16, 10)
    scanner:Rod("frame", {-11.8,s*17.5,-16.8}, {-11.8,s*14.3,-16.8}, 3.02, 14)
    scanner:Rod("edge", {-11.8,s*17.55,-16.8}, {-11.8,s*18.1,-16.8}, 1.6, 12)
    scanner:Rod("steel", {-11.8,s*16.4,-16.8}, {-0.5,s*15.9,-20.6}, 2.39, 10)
    scanner:Rod("dark", {-0.88,s*15.9,-20.65}, {2.5,s*15.5,-20.8}, 2.03, 10)
    scanner:Rod("steel", {1.1,s*14.1,-20.4}, {4.1,s*11.8,-20.6}, 0.74, 8)
    scanner:Rod("steel", {1.1,s*17.5,-20.4}, {4.1,s*18.3,-20.6}, 0.74, 8)
    scanner:Cable({{-9,s*17.9,-4.6},{-11,s*21,-8.3},{-5,s*23,-9.8},{4.6,s*23,-4.4}}, 0.62)
    scanner:Plate("armor", {{7,s*11},{7,s*19},{11,s*17},{13,s*10}}, 5.27, 6.10)
    scanner:Fastener(9, s*15.4, 6.15, 0.62)
    scanner:Collar(-23.5, -13.1, s*7.2, -2.3, 4.7, "emit", true)
    scanner:Box("dark", -10.0, s*17.2, 5.6, 12.1, 4.2, 0.8)
    vents(scanner, -6, 17.2, 6.04, s, 5, 1.57)
    scanner:Box("emit", 18.6, s*8.55, 1.2, 1.42, 2.05, 0.40)
end

local capacitor = G.New("mount_optic")
capacitor:Loft("frame", 0, 0, {{-10,4.4,4.9},{-6,6,5.55},{7,6,5.55},{10,5.4,4.7}})
capacitor:Box("steel", 0.0, 0, 5.22, 15.6, 10.02, 2.05)
for i = -3, 3 do capacitor:Box("dark", i*2, 0, 6.33, 0.58, 8.1, 0.42) end
for _, s in ipairs(sides) do
    capacitor:Rod("copper", {-8.7,s*5.71,-1.1}, {7.9,s*5.71,-1.1}, 1.1, 10)
    capacitor:Rod("steel", {-3,s*5.71,-1.1}, {-1.75,s*5.71,-1.1}, 1.5, 12)
    capacitor:Box("emit", 1.8, s*3.56, 6.42, 2.9, 0.5, 0.21)
    capacitor:Fastener(-6.8, s*3.6, 6.19, 0.59)
end

local assault = G.New("assault")
assault:Loft("frame", 0, -1, {{-21,7,5},{-16,12,8},{7,12,8},{19,6,5}})
assault:Loft("armor", 0, 4, {{-16,8,3},{-11,11,5,2},{8,11,4,2},{18,6,2}})
assault:Loft("dark", 0, -5, {{-16,4,3},{5,9,4},{15,7,3}})
for _, s in ipairs(sides) do
    plate(assault, "steel", s, {{-14,7},{9,7},{15,14},{7,23},{-9,21},{-17,13}}, -3, 3)
    plate(assault, "bone", s, {{-13,10},{6,9},{12,14},{5,20},{-7,20},{-14,15}}, 2.9, 5.1)
    plate(assault, "frame", s, {{-16,16},{-9,19},{-2,21},{-10,24},{-19,20}}, -3.65, -0.4)
    assault:Box("frame", 2, s*15.8, -4.8, 19, 8, 6)
    assault:Collar(10, 18, s*16, -4.6, 3.3, "dark")
    assault:Collar(-22, -17, s*8.1, -0.6, 4.4, "emit", true)
    assault:Box("copper", -6, s*14.8, 5.7, 11, 3, 1.3)
    assault:Box("emit", 9.5, s*12.8, 5.3, 3.25, 0.85, 0.6)
    vents(assault, 4, 15.9, 5.45, s, 5, 1.5)
    assault:Fastener(-7.2, s*16.7, 5.14, 0.69)
    assault:Fastener(7.8, s*15.1, 5.15, 0.62)
    assault:Tube("dark", {4,s*16,-4.6}, {12,s*16,-4.6}, {{0,2.1},{0.24,2.13},{1,1.9}}, 14)
    assault:Cable({{-10,s*12,-2.7},{-6,s*17,-3.5},{4,s*17,-4.8}}, 0.40)
    fins(assault, -7.2, 11.5, 5.2, s)
    optic(assault, 19.4, 3.05*s, 1.1, 2.45)
end

local interceptor = G.New("interceptor")
interceptor:Loft("frame", 0, 0, {{-23,5,4},{-13,8,6},{0,8,5},{17,4,3},{23,1.8,1.8}})
interceptor:Loft("steel", 0, 3.1, {{-16,4,1.65},{-7,6.8,3.5},{7,5,2.2},{21,2,1}})
interceptor:Loft("glass", 0, 5.8, {{-6,2,0.64},{0,3,1.3},{12,1.7,0.6}})
optic(interceptor, 23, 0, 0, 1.65)
for _, s in ipairs(sides) do
    plate(interceptor, "armor", s, {{9,4},{-4,23},{-22,32},{-19,23},{-12,7}}, -1.9, 1.35)
    plate(interceptor, "frame", s, {{5,7},{-8,20},{-22,29},{-17,20},{-10,10}}, 1.25, 2.85)
    interceptor:Fastener(-11, s*16.8, 2.88, 0.55)
    interceptor:Fastener(-16.9, s*23.8, 2.86, 0.59)
    plate(interceptor, "copper", s, {{-7,20},{-16,26},{-19,26},{-11,20}}, 2.78, 3.15)
    plate(interceptor, "emit", s, {{-9,20},{-22,29.5},{-22.3,28.6},{-9.3,19.3}}, 2.8, 3.15)
    interceptor:Loft("dark", s*9.1, -0.4, {{-23,3.6,3.9},{-17,5,4.4},{-3,3.2,3.3},{7,1.7,2}})
    interceptor:Collar(-24.3, -17, s*9.1, -0.4, 3.8, "emit", true)
    interceptor:Rod("steel", {-3,17*s,-2.2}, {13,13*s,-3.1}, 1.6, 8)
    interceptor:Rod("dark", {11,13.5*s,-3.1}, {16,12.2*s,-3.5}, 1.15, 8)
    vents(interceptor, -10, 9.3, 3.8, s, 4, 1.6)
end

local artillery = G.New("artillery")
artillery:Loft("frame", 0, -2, {{-28,14,9},{-20,18,10},{14,19,10},{24,13,6}})
artillery:Loft("armor", 0, 5, {{-24,10,3},{-15,14,5,3},{2,13,5,1},{17,10,3},{23,7,2}})
artillery:Box("bone", 5, 0, 12.2, 20, 12, 3.3)
optic(artillery, 25.2, 0, 2.1, 4.25)
for _, s in ipairs(sides) do
    artillery:Loft("frame", s*19.2, 3.7, {{-17,6,7},{-13,9.4,10},{10,9.4,10},{15,8,8}})
    artillery:Box("bone", -0.2, s*19.2, 10, 24, 17, 8)
    artillery:Box("armor", 1, s*28.2, 3.8, 21, 2.3, 14.6)
    artillery:Box("frame", 2.2, s*28.2, 4.8, 19, 2.6, 4.5)
    for j = -1, 1 do
        for k = 0, 1 do artillery:Collar(12.2, 16.2, s*(19 + j*4.8), 4.6+k*5.4, 2.5, "copper") end
    end
    artillery:Collar(-29, -19, s*9.1, -2.3, 5.2, "emit", true)
    artillery:Rod("steel", {-17,s*20,13.1}, {-12,s*20,21}, 1.05)
    artillery:Box("emit", -11.3, s*20, 21.3, 2.5, 1.6, 1.3)
    vents(artillery, 6, 19, 14.1, s, 6, 2)
    artillery:Fastener(-9.2, s*24.3, 14.02, 0.67)
    artillery:Fastener(8.4, s*23.5, 14.02, 0.64)
    fins(artillery, 9, 21, 14.18, s)
end

local support = G.New("support")
support:Loft("frame", 0, 0, {{-19,7,6},{-11,10,8},{7,10,6},{15,5,4}})
support:Loft("bone", 0, 4.3, {{-17,5,3},{-11,7,4},{6,8,3},{14,4,1.9}})
support:Collar(10, 17.45, 0, -2, 5.4, "emit")
for _, s in ipairs(sides) do
    plate(support, "steel", s, {{-12,6},{-5,21},{4,26},{18,24},{22,16},{18,13},{11,18},{0,19},{-6,11}}, -3.4, 1.7)
    plate(support, "bone", s, {{-10,8},{-4,20},{4,24},{17,22},{20,16},{17,15},{10,20},{0,20},{-3,13}}, 1.65, 3.15)
    support:Rod("copper", {-4,s*16,-2}, {16,s*20,-2}, 1.18)
    support:Collar(-19.6, -13.2, s*5.6, -0.2, 4, "emit", true)
    support:Rod("emit", {17.25,s*16.9,0.5}, {21.4,s*15.5,0.3}, 1.27)
    support:Box("dark", 4.3, s*21, 3.4, 9.5, 3.4, 0.9)
    support:Box("emit", 4.3, s*21, 3.8, 6, 1.25, 0.75)
end

local heavy = G.New("heavy")
heavy:Loft("dark", 0, -1.5, {{-30,12,8},{-24,19,10},{12,18,13},{25,13,8},{32,8,6}})
heavy:Loft("steel", 0, 6, {{-24,12,3},{-12,15,9,4},{10,17,6,4},{27,10,4}})
heavy:Collar(20, 34.8, 0, -5.2, 6.4, "emit")
for _, s in ipairs(sides) do
    plate(heavy, "frame", s, {{-25,14},{-15,31},{4,34},{20,24},{23,12},{6,12}}, -6.2, 8)
    plate(heavy, "armor", s, {{-24,16},{-15,29},{2,31},{17,24},{20,15},{3,17}}, 7.9, 11.2)
    plate(heavy, "steel", s, {{-24,17},{-15,29},{-4,30},{-7,24},{-17,22}}, 11, 13)
    plate(heavy, "bone", s, {{9,18},{18,15},{21,15},{16,24},{9,25}}, 10.5, 12.5)
    heavy:Loft("armor", s*23.5, -2.2, {{-24,5,5},{-16,7,7},{12,7.5,7},{24,4,4}})
    heavy:Collar(-31, -22, s*12.2, 0, 5.7, "emit", true)
    heavy:Collar(22.3, 27.8, s*22, -2.5, 3.4, "dark")
    optic(heavy, 29.5, s*5.2, 3.8, 2.65)
    heavy:Box("copper", -5, s*18.5, 13.7, 15, 2.3, 2.1)
    heavy:Box("emit", -7, s*19.8, 14.5, 10, 0.9, 0.58)
    heavy:Fastener(13, s*21.6, 12.52, 0.8)
    heavy:Cable({{-17,s*23.4,5.8},{-13,s*28.2,5.2},{-3,s*30.2,5.5}}, 0.62)
    vents(heavy, 5.6, 22.1, 11.35, s, 6, 2.05)
    fins(heavy, 14, 18, 12.55, s)
end

local cutter = G.New("cutter")
cutter:Tube("frame", {0,0,-5}, {0,0,5}, {{0,4},{0.22,10},{0.73,11},{1,7}}, 12)
cutter:Tube("armor", {0,0,3}, {0,0,8}, {{0,8},{0.4,8},{1,3}}, 10)
cutter:Rod("emit", {0,0,7}, {0,0,8.55}, 3.8, 12)
optic(cutter, 11, 0, -0.7, 2.6)
local rotor = G.New("cutter_rotor")
for i = 0, 4 do
    local a = i*math.pi*0.4
    local function blade(mat, points, low, high)
        local rotated = {}
        for j, p in ipairs(points) do
            rotated[j] = {p[1]*math.cos(a)-p[2]*math.sin(a), p[1]*math.sin(a)+p[2]*math.cos(a)}
        end
        rotor:Plate(mat, rotated, low, high)
    end
    blade("steel", {{9,-2},{15,-4},{23,-2},{25,4},{17,2},{11,4}}, -1.2, 1.2)
    blade("bone", {{14,-2},{21,-1},{24,3.5},{17,1},{14,1}}, 1.2, 1.7)
    blade("emit", {{20,-1.2},{23,-0.8},{24.4,2.5},{23.5,2}}, 1.2, 1.8)
end

local worm = G.New("worm")
for i = 0, 3 do
    local x = 11 - 8*i
    local wide = 9.75 - i*1.25
    worm:Loft("frame", 0, wide*0.44, {{x-6,wide*0.73,wide*0.35},{x-3,wide,wide*0.55},{x+4,wide*0.78,wide*0.41}})
    worm:Loft("bone", 0, wide*0.66, {{x-3.4,wide*0.85,wide*0.36},{x-1,wide*0.87,wide*0.49},{x+3.8,wide*0.70,wide*0.41}})
    for _, s in ipairs(sides) do
        worm:Rod("steel", {x,s*(wide-1),3}, {x-3,s*(wide+4),0}, 1.45)
        worm:Rod("dark", {x-3,s*(wide+4),0}, {x+1,s*(wide+6),-3}, 1.2)
        worm:Box("emit", x-1, s*(wide*0.78), wide*0.92, 2.8, 0.9, 0.6)
    end
end
optic(worm, 17, -3.4, 5.6, 2)
optic(worm, 17, 3.4, 5.6, 2)
worm:Tube("steel", {14,0,0}, {22,0,0}, {{0,4.2},{0.36,4.5},{0.74,2.4},{1,0.65}}, 7)

local mine = G.New("mine")
mine:Tube("frame", {0,0,-7}, {0,0,8}, {{0,4},{0.28,11.8},{0.74,11.8},{1,5}}, 12)
mine:Tube("armor", {0,0,1}, {0,0,9}, {{0,11.6},{0.22,11.6},{0.48,9.5},{1,5}}, 12)
mine:Rod("emit", {0,0,7.7}, {0,0,9.8}, 5.4, 12)
for i = 0, 5 do
    local a = i*math.pi/3
    local x, y = math.cos(a), math.sin(a)
    mine:Rod("steel", {x*9,y*9,-1.2}, {x*16,y*16,-1.5}, 2.1)
    mine:Rod("emit", {x*14,y*14,-1.5}, {x*17,y*17,-1.5}, 1.15)
end

-- Player mounts and viewmodels use the same barrels, breeches and optic geometry.
local pulse = G.New("mount_pulse")
pulse:Loft("frame", 0, 0, {{-11,3.2,4},{-8,5,4.6},{3,5,4.6},{8,3.2,3.8}})
pulse:Box("armor", -3, 0, 2, 14, 10, 5.5)
pulse:Box("bone", -3, 0, 4.55, 12, 6.6, 1.2)
for _, s in ipairs(sides) do
    pulse:Rod("steel", {2,s*2.75,0}, {12.7,s*2.75,0}, 1.47, 14)
    for i = 0, 2 do pulse:Rod("frame", {5.2 + i*1.7,s*2.75,0}, {5.83 + i*1.7,s*2.75,0}, 2.04, 14) end
    pulse:Collar(12, 15.55, s*2.75, 0, 2.28, "dark")
    pulse:Box("copper", -3, s*4.7, 0.8, 9, 0.9, 2.45)
    pulse:Box("emit", 1.75, s*3.7, 4.25, 2.36, 0.46, 0.39)
    pulse:Fastener(-6.4, s*3.5, 4.5, 0.62)
    pulse:Fastener(2.9, s*3.7, 4.68, 0.56)
end
vents(pulse, 0.7, 0, 5.22, 1, 5, 1.35)

local arc = G.New("mount_arc")
arc:Loft("frame", 0, 0, {{-11,3.3,4},{-7,4.4,4.6},{9,4.55,4.2},{13.9,2.7,2.7}})
arc:Box("glass", 2.8, 0, 3.3, 16, 3, 3.3)
arc:Box("emit", 4.1, 0, 5, 11.5, 1.23, 1.19)
arc:Collar(10.9, 15.55, 0, 0, 3.28, "emit")
for _, s in ipairs(sides) do
    arc:Loft("armor", s*4.3, 0.5, {{-8,1.7,3.6},{-5,2.3,3.85},{7,2.65,3.8},{14,1.41,2.2}})
    arc:Rod("copper", {-6.7,s*5.3,-3}, {12.3,s*5,-2}, 0.76)
    arc:Box("emit", 7.1, s*6.43, 1.65, 4.8, 0.36, 0.52)
    arc:Cable({{-7,s*5.8,2.0},{-5.6,s*6.6,1.1},{-1,s*6.8,0.89},{1.2,s*6.45,1.61}}, 0.38)
    arc:Fastener(-2.5, s*4.95, 4.48, 0.49)
    arc:Fastener(4.6, s*5.0, 4.38, 0.49)
end

local rack = G.New("mount_rack")
rack:Loft("frame", 0, 0, {{-13,4.6,4},{-9,6.5,5.6},{8,6.5,5.6},{10.1,5.8,4.9}})
rack:Box("armor", -1.5, 0, 3.5, 21, 14, 4.8)
rack:Box("bone", -2.5, 0, 5.7, 16, 9.65, 1.2)
for _, s in ipairs(sides) do
    for _, z in ipairs({-2.3, 2.4}) do rack:Collar(8.1, 12.05, s*3.4, z, 2.46, "dark") end
    rack:Box("emit", 1.4, s*6.7, 1.55, 7.5, 0.75, 0.65)
    rack:Box("steel", 0.5, s*6.95, -0.25, 16, 1.32, 3.1)
    rack:Fastener(-7.2, s*4.7, 6.28, 0.61)
    rack:Fastener(4.8, s*4.7, 6.24, 0.65)
    fins(rack, 0.8, 3, 6.36, s)
end

local rail = G.New("mount_rail")
rail:Loft("frame", 0, 0, {{-13,3.4,4.5},{-8,5.4,5.1},{2,5.2,4.8},{9,3.3,3.3},{20,1.8,1.6}})
rail:Box("emit", 8.5, 0, 1.75, 20, 1.15, 0.85)
for _, s in ipairs(sides) do
    rail:Loft("steel", s*3.4, 1.2, {{-8,1.5,3.3},{-2,2.15,3.7},{13,1.45,2.0},{22,0.85,1.45}})
    rail:Box("copper", 3, s*4.3, 4.2, 13.8, 1, 0.94)
    rail:Box("emit", 14, s*3.5, 3.2, 10.5, 0.68, 0.5)
    for i = 0, 2 do
        local x = -6+i*3.2
        rail:Box("steel", x, s*4.97, 1.6, 1.75, 1.7, 6.4)
        rail:Fastener(x, s*4.97, 4.84, 0.57)
    end
    rail:Cable({{-10,s*3.3,2.2},{-7,s*5.6,1},{1.2,s*5.6,0.8},{7.8,s*3.85,0.6}}, 0.46)
end

local field = G.New("mount_field")
field:Loft("frame", 0, 0, {{-12,4,3.3},{-8,5.8,4.65},{3,5.45,4.4},{9,3.7,3.9},{11.4,2,2}})
field:Box("bone", -3.4, 0, 3.8, 16.3, 7, 3.25)
field:Collar(7.5, 13.2, 0, 0, 3.23, "emit")
for _, s in ipairs(sides) do
    field:Rod("steel", {-8,s*4,0}, {10,s*7,0}, 1.7)
    field:Rod("copper", {-3.5,s*5.1,0}, {11,s*7.35,0}, 0.96)
    field:Box("emit", 4.5, s*6.3, 0.9, 5.5, 0.42, 0.4)
    field:Fastener(-4, s*2.8, 5.41, 0.61)
end

local bay = G.New("mount_mine")
bay:Loft("frame", 0, 0, {{-10,4.3,3},{-6,5.4,4},{7,5.4,4},{10.1,4.2,3.1}})
bay:Box("armor", 0, 0, 2.5, 22.5, 12, 3.1)
for _, s in ipairs(sides) do
    bay:Box("bone", 0, s*4.5, -2.9, 18.1, 3.1, 2.65)
    bay:Box("emit", 6.5, s*6, 0.3, 3.1, 0.48, 0.48)
    bay:Fastener(-7.0, s*4.65, 4.07, 0.6)
    bay:Fastener(5.0, s*4.65, 4.07, 0.6)
    fins(bay, 2, 2, 4.15, s)
end
bay:Collar(8, 11.65, 0, 0, 3.2, "emit")
local hatch = G.New("mine_hatch")
hatch:Box("steel", -0.5, 0, 0, 15, 6.1, 1.4)
hatch:Box("hazard", 4.05, 0, -0.76, 2.7, 3.2, 0.4)

local mount = G.New("mount_joint")
mount:Rod("frame", {-4,0,0}, {4,0,0}, 5.0)
mount:Rod("steel", {-3,0,0}, {3,0,0}, 4.45)
mount:Rod("copper", {-3,0,-0.1}, {0,0,0}, 3.0)

local bolt = G.New("shot_kinetic")
bolt:Tube("copper", {-8,0,0}, {3.7,0,0}, {{0,0.65},{0.6,0.82},{0.8,0.82},{1,0.15}}, 8)
bolt:Rod("emit", {-7.5,0,0}, {-2.5,0,0}, 0.85, 8)

local cell = G.New("shot_energy")
cell:Tube("hot", {-5.7,0,0}, {4.6,0,0}, {{0,0.4},{0.22,2},{0.72,2.05},{1,0.25}}, 10)
for i = 0, 3 do
    local a = i*math.pi/2
    local y, z = math.cos(a)*1.45, math.sin(a)*1.45
    cell:Rod("emit", {-3.8,y,z}, {2.8,y,z}, 0.85, 8)
end

local rocket = G.New("shot_rocket")
rocket:Tube("bone", {-9.4,0,0}, {11.6,0,0}, {{0,2.65},{0.21,2.65},{0.72,2.35},{0.84,2},{1,0.25}}, 9)
rocket:Collar(-11.2, -8.6, 0, 0, 2.48, "emit", true)
for _, s in ipairs(sides) do
    plate(rocket, "steel", s, {{-8,1.5},{-4.5,4.4},{-0.1,1.5}}, -0.47, 0.47)
    rocket:Rod("hazard", {-8,1.88*s,1.65}, {-2.4,1.72*s,1.52}, 0.49, 6)
end

local orb = G.New("shot_exotic")
orb:Tube("emit", {-5.8,0,0}, {5.8,0,0}, {{0,0.2},{0.12,3.7},{0.5,5},{0.88,3.7},{1,0.2}}, 14)
orb:Tube("steel", {-3,0,0}, {-2,0,0}, {{0,4.5},{1,4.9}}, 12)
orb:Tube("steel", {2,0,0}, {3,0,0}, {{0,4.9},{1,4.5}}, 12)

local function chassis(name, donor)
    local copy = G.New(name)
    for mat, part in pairs(donor.parts) do
        copy.parts[mat] = {}
        for i, face in ipairs(part) do copy.parts[mat][i] = face end
    end
    return copy
end

local gravity = G.New("grav")
gravity:Tube("frame", {-17.1,0,0}, {21.8,0,0},
    {{0,5.9},{.11,9.2},{.31,12.3},{.49,13.1},{.66,12.3},{.87,9.2},{1,5.9}}, 28)
gravity:Tube("armor", {-12.4,0,0}, {13,0,0}, {{0,9.6},{.32,12.4},{.70,12.55},{1,8.7}}, 24)
gravity:Collar(15.3, 24.1, 0, 0, 6.9, "glass")
gravity:Rod("emit", {20.91,0,0}, {21.68,0,0}, 3.65, 24)
for _, s in ipairs(sides) do
    gravity:Loft("dark", s*10.75, 0, {{-16,3,4},{-13,5.9,6.2},{3,7,6.6},{11,5.3,4.97}})
    gravity:Box("steel", -4.8, s*15.1, 4.9, 18, 8.75, 3.45)
    gravity:Rod("copper", {-13,s*15.7,2.15}, {9,s*17.22,2.15}, 1.6, 12)
    gravity:Rod("frame", {-.5,s*17.8,-2}, {-.5,s*22.1,-2}, 4.1, 16)
    gravity:Rod("steel", {-.5,s*21,-2}, {-.5,s*22.4,-2}, 3.15, 16)
    gravity:Rod("emit", {-.5,s*22.32,-2}, {-.5,s*22.62,-2}, 1.31, 12)
    gravity:Collar(-20,-12.5,s*9.35,-3.7,4.31,"emit",true)
    gravity:Cable({{-13,s*11.5,-3.25},{-7,s*16.5,-7.6},{2,s*17.4,-7},{9,s*10.3,-4.1}}, .72)
    vents(gravity, 3.8, 15.8, 6.63, s, 5, 1.57)
end
gravity:Box("frame", -4.1, 0, -12.1, 12.7, 7.5, 4.21)
gravity:Box("steel", -4.2, 0, -14.42, 10.2, 4.2, 1.26)

local gimbal = G.New("grav_gimbal")
local function winding(mat, radius, thickness, low, high)
    local rings = {{},{},{},{},{}}
    local profile = {{low,radius-thickness},{low,radius},{high,radius},{high,radius-thickness},{low,radius-thickness}}
    for i, section in ipairs(profile) do
        for j=1,48 do
            local a=j*math.pi/24
            rings[i][j] = {math.cos(a)*section[2],math.sin(a)*section[2],section[1]}
        end
    end
    gimbal:Rings(mat,rings,{0,0,(low+high)*.5},false)
end
winding("steel", 21.25, 1.65, -.69, .69)
winding("copper", 21.51, .60, -.28, .27)
for j=0, 7 do
    local a=j*math.pi/4
    local x,y=math.cos(a),math.sin(a)
    gimbal:Rod("frame", {x*18.8,y*18.8,.33}, {x*21.9,y*21.9,.33}, 1.2, 10)
    gimbal:Rod("emit", {x*19.95,y*19.95,1}, {x*21.4,y*21.4,1}, .36, 8)
end

local strider = chassis("rocket_strider", heavy)
for _, s in ipairs(sides) do
    strider:Loft("frame", s*33, 7.8, {{-23,5.3,7},{-18,7.6,8.3},{10,8.9,8.3},{17.15,7.8,6.7}})
    strider:Loft("armor", s*33, 14.3, {{-23,5.3,3.1},{-17,7.6,4.9},{8,7.7,4.8},{17,7.15,3.1}})
    strider:Box("bone", -3, s*34, 18.7, 25, 10.1, 2.1)
    for k = -1, 1 do
        strider:Collar(12.8, 18.8, s*(33 + k*4.65), 10, 2.5, "dark")
    end
    strider:Collar(-29, -21.6, s*33, 6.2, 5.85, "emit", true)
    strider:Rod("copper", {-20,s*38.5,9},{12,s*40.4,9.2}, 0.8)
    for i = 0, 2 do strider:Box("emit", 9-i*4.6, s*41, 5.85, 2.85, 0.58, 1.18) end
    fins(strider, 6.9, 30.8, 19.87, s)
end

-- Individual loadout hulls keep sensor and launcher silhouettes readable at range.
local gunner = G.New("combine_gunner")
gunner:Loft("frame",0,-.74,{{-21,8.9,6.12},{-13,11.4,8.5},{8,11.6,7.6},{19,7.5,5.04}})
gunner:Loft("steel",0,4.1,{{-17,7,3.1},{-10,10.5,4.8},{5,10.5,3.55},{15.5,6.1,2.1}})
optic(gunner,19.9,0,2,3.36)
for _, s in ipairs(sides) do
    gunner:Box("armor",-2,s*13.5,.1,19,8.6,8.8)
    gunner:Rod("steel",{3,s*14,-1.8},{22.4,s*14,-1.8},2.03,16)
    gunner:Collar(19,25,s*14,-1.8,2.97,"dark")
    gunner:Rod("copper",{-9,s*16.68,4.3},{8,s*16.07,4.3},.84)
    gunner:Collar(-22.1,-15,s*7,-1.29,4.82,"emit",true)
    vents(gunner,4.1,14.25,4.76,s,5,1.5)
end

local laserShip = G.New("combine_laser")
laserShip:Loft("frame",0,0,{{-25,5.4,4.4},{-14,9.6,6.5},{1,10.7,5.65},{21,5.73,3.94},{26,3.9,2.36}})
laserShip:Collar(21,27,0,0,3.82,"glass")
laserShip:Rod("emit",{24.75,0,0},{25.51,0,0},1.15,18)
for _, s in ipairs(sides) do
    plate(laserShip,"armor",s,{{9,7},{-12,24},{-20,26},{-16,15},{-8,8}},-1.18,2.78)
    plate(laserShip,"edge",s,{{5,8},{-11,20},{-17,21},{-12,14},{-5,8}},2.59,3.54)
    laserShip:Rod("copper",{-6,s*4.4,4.61},{18.4,s*2.75,2.83},.78,10)
    laserShip:Collar(-25,-17,s*5.9,-.93,3.6,"emit",true)
    laserShip:Box("emit",-10,s*16.85,3.15,4.53,.7,.43)
end

local rocketeer = G.New("combine_rocketeer")
rocketeer:Loft("frame",0,-1,{{-21,9.1,5.9},{-15,13.4,9.2},{13,13.5,7.2},{20,9.4,5.1}})
rocketeer:Loft("armor",0,4.5,{{-18,8,3.4},{-10,11,5.1},{7,11,4.86},{17,7.9,3.2}})
optic(rocketeer,21,0,-2,3.62)
for _, s in ipairs(sides) do
    rocketeer:Loft("bone",s*11.8,8,{{-15,3.7,3.6},{-12,5.5,5.1},{10,5.2,4.87},{13.9,4.76,4.16}})
    rocketeer:Collar(10.5,15,s*11.8,8,3.6,"dark")
    rocketeer:Box("hazard",-1,s*12,13.03,4.44,6.8,.53)
    rocketeer:Rod("frame",{-10,s*7.5,2.9},{-10,s*12,6.6},2.14)
    rocketeer:Collar(-22.7,-16,s*7.6,-3.2,4.51,"emit",true)
    rocketeer:Cable({{-16,s*9.5,-3},{-11,s*15.5,-5.7},{2,s*16.3,-2.3}},.68)
end

local seeker = G.New("combine_seeker")
seeker:Loft("frame",0,1.1,{{-23,4.75,4.4},{-12,9.0,7.3},{7,10,6.2},{19,6,4.15},{22.3,3.4,2.8}})
optic(seeker,22.5,0,2.1,3.26)
for _, s in ipairs(sides) do
    plate(seeker,"ceramic",s,{{-16,7},{-16,15},{-6,28},{7,28},{17,12},{13,8}},-2.8,2.87)
    plate(seeker,"frame",s,{{-10,12},{-5,25},{6,25},{12,14}},2.67,4.3)
    seeker:Loft("armor",s*17,2.13,{{-15,3.2,2.9},{-7,4.6,3.8},{9,4.55,3.68},{13,3.4,3.3}})
    seeker:Collar(10.2,14,s*17,2.13,2.91,"dark")
    seeker:Collar(-23.3,-17,s*6.7,1.13,4.02,"emit",true)
    seeker:Rod("emit",{-9,s*22.5,3.8},{3.6,s*22.5,3.8},.47)
end

local homing = chassis("elite_homing",seeker)
homing:Loft("ceramic", 16.8,5.48,{{-14,3.9,3.4},{-10,6.5,5},{13,6.5,5},{18.8,5.3,4.0}})
homing:Collar(16,21.7,16.8,5.48,4.11,"dark")
homing:Box("stripe", 5.85,16.8,10.31,3.79,8.0,.64)
homing:Collar(9,12,-8.3,8.1,3.22,"emit")
local aa = G.New("elite_aa")
aa:Loft("frame",0,-2.2,{{-24,8,5.86},{-18,17.4,8.645},{10,17.4,8.3},{19,11.2,6.25}})
optic(aa,21,0,.5,4.1)
for _, s in ipairs(sides) do
    aa:Loft("ceramic",s*17.1,10.4,{{-18,5.05,4.44},{-14,7.6,6.1},{11,7.3,6.15},{15.3,6.3,5.8}})
    for _, dz in ipairs({-3,2.85}) do aa:Collar(13.2,16.3,s*17,11.4+dz,2.95,"dark") end
    aa:Box("stripe",5,s*18.5,16.76,4.9,7.86,.51)
    aa:Collar(-25.7,-20,s*9,-3,5.2,"emit",true)
    aa:Rod("steel",{-7,s*7.1,4.9},{-7,s*13.45,7.2},2.5,14)
end

local ionStrider = chassis("plasma_strider", heavy)
ionStrider:Loft("ceramic",0,7.4,{{-16,10.1,5.54},{-11,14.2,8.25},{12,14.82,7.09},{27,10.31,3.11}})
ionStrider:Collar(26.1,36.5,0,-1,6.8,"emit")
for _, s in ipairs(sides) do
    ionStrider:Tube("steel",{-19,s*25.2,9.4},{12,s*25.2,9.4},{{0,3.6},{.2,5.78},{.68,5.35},{1,3.55}},16)
    ionStrider:Rod("emit",{-11,s*26.6,14.4},{6,s*26.9,14.45},.45)
    ionStrider:Cable({{12,s*26,8.6},{19,s*24,5.4},{20,s*17.1,2.7},{27,s*6.9,-1}},.86)
end

local gunship = G.New("combine_gunship")
gunship:Loft("frame",0,0,{{-37,4.5,3.8},{-24,8.8,6.5},{-7,15.64,9.2},{13,13.3,8.3},{27,8.6,6.77}})
gunship:Loft("steel",0,5.4,{{-25,6.5,3.1},{-16,12.3,6.5},{9,13.64,6.9},{24,8.6,3.9}})
gunship:Collar(21,34,0,-5.6,4.62,"dark")
optic(gunship,28,0,2.1,4.1)
for _, s in ipairs(sides) do
    plate(gunship,"armor",s,{{-18,10},{-23,19},{-14,34},{3,31},{16,17},{10,12}},-3.6,4.1)
    gunship:Loft("frame",s*23.2,-3.6,{{-22,3.9,4.9},{-15,6.0,6.1},{9,5.24,4.8}})
    gunship:Collar(-23.5,-15.6,s*23.2,-3.6,4.92,"emit",true)
    gunship:Box("hazard",-12,s*22.7,4.0,3.6,7.7,.5)
end

local probe = G.New("cutting_probe")
probe:Tube("frame",{-13.8,0,0},{13.7,0,0},{{0,5.2},{.17,8.72},{.43,11.1},{.68,10.2},{1,6.21}},20)
probe:Collar(9.1,15.3,0,0,5.1,"glass")
probe:Rod("emit",{12.22,0,0},{13.5,0,0},2.65,18)
for _, s in ipairs(sides) do
    probe:Box("ceramic",-2,s*8.8,2.8,14.1,5.1,3.15)
    probe:Rod("steel",{-10,s*8.2,-2.2},{-7,s*14.6,-4.9},1.77)
    probe:Rod("edge",{-7,s*14.6,-4.9},{1.4,s*6.7,-7.8},.71)
end

local function eliteArmor(model)
    model:Loft("ceramic", 0, 11.6, {{-18,10,2.4},{-9,15,5,1},{12,13,4},{26,9,2.1}})
    model:Loft("frame", 0, 15.3, {{-9,2.8,1.3},{2,3.7,1.8},{14,2.8,1.15},{22,1.3,0.72}})
    for _, s in ipairs(sides) do
        plate(model, "ceramic", s, {{-14,19},{-8,29},{5,29.5},{15,23},{18,17},{6,18}}, 10.8, 13.35)
        plate(model, "stripe", s, {{-0.8,18.4},{5.4,19},{1.4,28.7},{-3.8,28.5}}, 13.35, 13.55)
        model:Fastener(-6.3, s*24.2, 13.37, 0.68)
        model:Fastener(11.3, s*22.5, 13.37, 0.65)
    end
end

local elite = G.New("combine_elite")
elite:Loft("frame", 0, 0, {{-24,10,8},{-17,17,12},{2,18,13},{20,13,10},{24,9,7}})
elite:Loft("steel", 0, 8, {{-20,12,3.7},{-12,15.7,7.8,1.4},{8,16.3,7.1,-0.5},{20,12,5,-2}})
elite:Loft("dark", 0, -6, {{-19,9,5},{6,12,7},{19,9.8,6.5}})
elite:Loft("frame", 0, 1.0, {{17,8,7},{22.3,7.4,6.2},{24.6,6.6,5.9}})
elite:Collar(21, 26.6, 0, 1.03, 5.4, "glass")
elite:Rod("emit", {24.27,0,1.03}, {24.62,0,1.03}, 1.72, 24)
elite:Box("frame", -2.3, 0, -13.7, 18, 10.2, 6.5)
elite:Rod("steel", {-7,0,-13.6}, {-7,0,-20.4}, 2.7, 12)
elite:Box("dark", -4.6, 0, -19.75, 12.8, 7.9, 4.4)
elite:Rod("frame", {-6.4,-5.02,-20.2}, {-6.4,5.02,-20.2}, 3.15, 16)
elite:Rod("steel", {-6.4,-5.12,-20.2}, {-6.4,5.12,-20.2}, 1.64, 12)
elite:Cable({{-6.4,0,-20.2},{-6.5,0,-24.4},{-7.0,0,-28.4},{-7.1,0,-31.0}}, 0.48)
elite:Rod("steel", {-7.1,0,-30.45}, {-7.1,0,-34.25}, 0.86, 10)
elite:Collar(16.2, 19.2, -9.6, 6.5, 2.65, "glass")
elite:Rod("edge", {18.08,-9.6,6.5}, {18.25,-9.6,6.5}, 1.28, 12)
for _, s in ipairs(sides) do
    plate(elite, "ceramic", s, {{-10,11},{-8,17.5},{7,17.5},{17,12},{10,8},{0,8}}, 9.8, 12.5)
    plate(elite, "stripe", s, {{6,10},{11,9.6},{13,14},{8,16}}, 12.5, 12.71)
    elite:Fastener(-7.1, s*15.9, 12.5, 0.74)
    elite:Fastener(6.2, s*14.6, 12.51, 0.74)
    elite:Box("armor", -1, s*13.5, 15.5, 7, 8, 5.8)
    elite:Rod("edge", {-9,s*14.3,16.8}, {9,s*14.3,16.8}, 1.6, 12)
    elite:Loft("armor", s*14.45, 22.15, {{-12,6,5.15},{-9,7.9,6.35},{11,7.9,6.35},{13,7.3,5.8}})
    elite:Box("dark", 11.36, s*14.45, 22.15, 1.9, 14.7, 10.6)
    for col = -1, 1 do
        for row = -1, 1 do
            elite:Collar(11, 14.3, s*14.45+col*4.15, 22.15+row*3.35, 1.56, row == 1 and "stripe" or "dark")
        end
    end
    elite:Box("steel", -1.5, s*16.5, 28.35, 17, 5.3, 0.79)
    elite:Box("hazard", 7, s*19.6, 28.67, 3.1, 2.8, 0.3)
    elite:Loft("frame", s*24.2, -0.2, {{-19,4,3.65},{-12,6.85,5.35},{4,7,5.6},{11,5.15,4.7}})
    elite:Box("steel", -2.9, s*27.65, 3.65, 18.2, 6.2, 2.1)
    for col = -1, 1, 2 do
        local y = s*24.2 + col*2.51
        elite:Rod("steel", {6,y,0.4}, {27.8,y,0.4}, 1.51, 12)
        elite:Rod("frame", {9.5,y,0.4}, {17,y,0.4}, 2.06, 12)
        elite:Collar(24.4, 28.7, y, 0.4, 1.86, "dark")
    end
    elite:Collar(-24.2, -16, s*10, -0.8, 5.1, "emit", true)
    elite:Box("dark", -4.7, s*17.55, 5.9, 14.1, 3.15, 0.7)
    vents(elite, -0.9, 17.5, 6.34, s, 6, 1.58)
    elite:Cable({{-17,s*18.4,-6},{-12,s*22.8,-11.1},{0,s*23.8,-11.8},{7,s*20.8,-7.4}}, 1.15)
    elite:Rod("steel", {-7.2,0,-33.8}, {-6.85,s*2.3,-34.8}, 0.78, 10)
    elite:Rod("edge", {-6.85,s*2.3,-34.8}, {-6.48,s*3.9,-34.04}, 0.67, 10)
    elite:Rod("edge", {-6.48,s*3.9,-34.04}, {-6.15,s*4.7,-32.43}, 0.43, 8)
end

local arc = G.New("combine_arc_elite")
arc:Loft("frame",0,1.8,{{-25,8.5,8},{-18,17,13},{4,18.1,14.3},{21,12.6,10.6},{25,8.2,8.8}})
arc:Loft("ceramic",0,12,{{-15,11.4,2},{-8,16.5,6.3},{8,15,5.9},{22,9.3,3}})
arc:Loft("dark",0,-8,{{-21,7,5},{-11,13,4.7},{17,10,4.6},{22,5.4,2}})
arc:Collar(16.7,27.3,0,3.5,7.25,"glass")
arc:Rod("emit",{24.5,0,3.5},{25.15,0,3.5},3.28,24)
arc:Box("armor",-7.8,0,17.4,15.6,7.5,5.12)
arc:Loft("steel",0,22.1,{{-27,4.1,3.1},{-15,6.9,4},{3,7.1,3.75},{9,5.08,2.9}})
arc:Collar(4.4,10.1,0,22,3.5,"dark")
arc:Box("hazard",-7.85,0,26.03,8.9,7.1,.48)
arc:Loft("armor",0,-18.2,{{-14,5.4,4},{-8,11.5,8.5},{7,10.5,8.7},{14,6.9,5.6}})
arc:Collar(8.1,16.1,0,-18.2,6.11,"hot")
arc:Rod("hot",{13,0,-18.2},{14.5,0,-18.2},3.45,24)
for _, s in ipairs(sides) do
    plate(arc,"armor",s,{{-14,11.5},{-12,21.8},{1,24.6},{13,17},{15,11}},5.1,9.5)
    plate(arc,"stripe",s,{{0,17},{4,16},{5,21.9},{1.6,23}},9.52,9.76)
    arc:Rod("steel",{-12,s*13.5,1.5},{-6,s*24,1.5},3.5,14)
    arc:Loft("frame",s*26.4,1.3,{{-14,4.8,4.6},{-8,7.7,6.7},{10,7.8,6.2},{19,5.78,4.5}})
    arc:Loft("bone",s*26.4,7.4,{{-9,5.2,2.1},{-5,6.6,2.9},{11,6.1,2.9},{18,5.2,2}})
    arc:Box("stripe",6,s*28.4,10,4.7,4.3,.62)
    arc:Collar(25,36,s*26.4,1.35,3.75,"emit")
    for _, offset in ipairs({-2.45,2.45}) do
        local y=s*26.4+offset
        arc:Rod("steel",{11,y,1.35},{29,y,1.35},1.16,12)
        arc:Rod("copper",{14.1,y,1.35},{21.45,y,1.35},1.55,12)
    end
    for j=0,5 do
        arc:Box("dark",11.5-j*2.55,s*29.4,9.5,1.04,2.6,.51)
        arc:Box("edge",11.2-j*2.55,s*29.4,9.76,.5,2.1,.23)
    end
    arc:Fastener(-5,s*25.9,10.23,.57)
    arc:Fastener(-6,s*14.88,15.8,.63)
    arc:Cable({{-17,s*11.2,-5},{-16,s*17.3,-9},{-8,s*24,-10},{5,s*25.9,-6}},1.06)
    arc:Cable({{-9,s*9,-17},{-4,s*11.2,-21},{4,s*9.4,-22.3},{10,s*5.9,-19.6}},.88)
    arc:Rod("hot",{-7.4,s*10.7,-15.6},{6.1,s*10.34,-15.6},.52,10)
    arc:Collar(-26,-19.2,s*10.7,-2.2,4.3,"emit",true)
end

eliteArmor(strider)
for _, s in ipairs(sides) do
    strider:Box("ceramic", -0.8, s*33.2, 19.25, 21, 9.4, 1.65)
    strider:Box("stripe", 5.6, s*33.2, 20.1, 3.7, 8.1, 0.22)
    strider:Fastener(-8, s*36.5, 20.07, 0.69)
    strider:Fastener(8.3, s*36.45, 20.05, 0.67)
    strider:Cable({{-21,s*36.8,7.6},{-18,s*41,5.5},{-4,s*41.5,5.0},{2,s*40.2,7.9}}, 0.58)
    strider:Rod("edge", {-9,s*35.5,2},{-1,s*33,5.1}, 1.05, 10)
end

-- Improvised frames have reclaimed parts, exposed joints and mismatched panels.
local function drum(model, x0, x1, y, z, radius, material)
    model:Tube(material, {x0,y,z}, {x1,y,z}, {
        {0,radius*0.82},{0.12,radius*0.94},{0.35,radius},
        {0.71,radius*0.98},{0.90,radius*0.93},{1,radius*0.81},
    }, 20)
    for _, t in ipairs({0.16, 0.74}) do
        local x = x0 + (x1-x0)*t
        model:Rod("rust", {x-0.48,y,z}, {x+0.48,y,z}, radius*1.03, 20)
    end
end

local function strap(model, x, y, z, radius)
    local rings = {{}, {}}
    for j = 1, 24 do
        local a = j*math.pi/12
        local yy, zz = y + math.cos(a)*radius, z + math.sin(a)*radius
        rings[1][j], rings[2][j] = {x-0.79,yy,zz}, {x+0.79,yy,zz}
    end
    model:Rings("canvas", rings, {x,y,z}, false)
    model:Box("dark", x, y+radius*0.68, z+radius*0.72, 2.8, 2.15, 1.72)
end

local function wreckWing(model, side, x, y, z, length)
    local wing = {{x+2.4,y},{x-5.8,y+length},{x-10.8,y+length-0.8},{x-9.2,y+3.5},{x-6.5,y}}
    for i = 1, #wing do
        local a, b = wing[i], wing[i%#wing+1]
        model:Rod("rust", {a[1],a[2]*side,z}, {b[1],b[2]*side,z-0.25}, 0.42)
    end
    for i = 0, 5 do
        local t = i/5
        local xx, yy = x + 1.2 - t*6, y+1.6+t*(length-3.9)
        model:Rod("steel", {xx,yy*side,z}, {xx-4.35,(yy+1.55)*side,z-0.15}, 0.24)
    end
    plate(model, "scrap", side, {{x+1.9,y+0.8},{x-2.8,y+length*0.64},{x-8.05,y+length*0.57},
        {x-7.2,y+3.7},{x-6.2,y+0.7}}, z+0.09, z+0.42)
    plate(model, "primer", side, {{x-3.3,y+length*0.67},{x-5.4,y+length*0.94},{x-9.4,y+length*0.93},
        {x-8.5,y+length*0.67}}, z+0.25, z+0.58)
    local tip = y + length*0.86
    model:Fastener(x-6.2, side*tip, z+0.59, 0.54)
    model:Fastener(x-8.1, side*tip, z+0.59, 0.59)
    model:Cable({{x-1,side*(y-0.8),z+0.8},{x-3.1,side*(y+length*.36),z+0.45},
        {x-3.9,side*(y+length*.69),z+0.62}}, 0.24)
end

local scout = G.New("resistance_scout")
drum(scout, -19, 15.2, 0, 0.8, 7.8, "oxide")
strap(scout, -9.75, 0, 0.8, 7.95)
strap(scout, 6.8, 0, 0.8, 7.87)
scout:Loft("scrap", -0.48, 0.06, {{12,4.2,4},{15,5.4,5.34},{19,4.6,4.4},{23,3.65,3.75}})
scout:Collar(18.4, 24.6, -0.48, 0.06, 3.84, "glass")
scout:Rod("emit", {22.98,-0.48,0.06}, {23.18,-0.48,0.06}, 1.02, 15)
scout:Box("tarp", -2.2, -2.75, 8.76, 10.4, 5.45, 2.9)
scout:Box("primer", -4.7, -2.73, 10.3, 5.9, 4.35, 0.48)
scout:Loft("frame", 0.9, 2.6, {{-31,3.1,3.65},{-27,5.05,4.92},{-18,5.05,4.78},{-14,3.95,3.78}})
scout:Collar(-32.5, -26.5, 0.9, 2.55, 4.12, "emit", true)
scout:Rod("rust", {-22,0.85,5.8}, {-26,0.85,15.2}, 0.55, 8)
scout:Loft("primer", 0.85, 10.2, {{-27,0.64,4.2},{-24,0.61,4.2},{-19,0.44,2.13},{-17,0.42,0.7}})
scout:Cable({{-24,-0.3,6.3},{-18,-4.3,7.4},{-10,-5.6,9.65},{-5,-5.55,9.75}}, 0.49)
scout:Cable({{-17,3.2,4.8},{-11,5.75,6.3},{2,5.6,5.8},{14,3.2,3.0},{20,2.6,2.5}}, 0.39)
scout:Rod("stripe", {2,-4.1,9.6}, {10,-4.92,5.9}, 0.32, 8)
wreckWing(scout, 1, -0.1, 5.45, -1.1, 27)
wreckWing(scout, -1, -2.1, 5.85, -0.85, 22)

local raider = G.New("resistance_raider")
drum(raider, -23, 16, -6.3, 1.9, 6.5, "rust")
drum(raider, -19, 11, 6.25, 0.7, 6.28, "scrap")
strap(raider, -4.8, -6.3, 1.9, 6.65)
strap(raider, -8.4, 6.25, 0.7, 6.44)
raider:Box("primer", -5, 0, -3.8, 29, 20, 3.7)
raider:Box("tarp", -5.5, -1.8, 8.05, 18.4, 8.2, 2.05)
raider:Loft("armor", 1.1, 2.75, {{7,8.6,3.5},{11,9.1,4.85},{18,7.5,3.45},{20,5.4,2.76}})
raider:Collar(17, 21.4, 1.7, 1.85, 2.25, "emit")
raider:Rod("frame", {7,-13.25,-2.1}, {19,-13.25,-2.1}, 1.6, 12)
raider:Collar(16, 21.9, -13.25, -2.1, 2.66, "dark")
raider:Collar(-25, -20, -6.3, 1.9, 3.4, "emit", true)
raider:Collar(-22, -17, 6.25, 0.7, 3.1, "emit", true)
plate(raider, "primer", -1, {{4,10},{-1,21},{-12,29},{-20,23},{-16,10}}, -2.4, 0.22)
plate(raider, "scrap", 1, {{1,10},{-4,17},{-11,23},{-18,18},{-12,9}}, -2.1, 0.39)
plate(raider, "rust", -1, {{-9,22},{-12.5,28},{-16.9,25},{-13.4,20.8}}, 0.23, 0.75)
raider:Cable({{-15,-11.9,4.0},{-12,-13,1.1},{1.2,-14.05,1.8},{7.5,-13.3,-0.6}}, 0.77)
raider:Cable({{-17,8.7,3},{-10,13,0.5},{1,12.5,1.5},{10,8.6,1.2}}, 0.61)
raider:Fastener(9.3, 5.55, 7.27, 0.67)
raider:Fastener(-13.4, -22.6, 0.77, 0.86)
raider:Fastener(-11, 14.8, 0.44, 0.70)

local hauler = G.New("resistance_hauler")
drum(hauler, -28, 21, 0, -2.2, 10.2, "scrap")
strap(hauler, -11.0, 0, -2.2, 10.43)
strap(hauler, 9.4, 0, -2.2, 10.34)
hauler:Loft("primer", -1.15, 4.7, {{-24,7.4,3.0},{-16,12.2,4.5},{10,11.4,5.2},{20,8.9,3.2}})
hauler:Loft("rust", 18.5, 1.7, {{-22,4.2,5.4},{-16,7.3,6.7},{12,6.9,6.2},{19,5.3,4.85}})
hauler:Loft("scrap", -17.3, 1.2, {{-18,4.5,4.6},{-11,6.4,6.4},{12,6.4,5.9},{18,5.1,4.45}})
hauler:Box("tarp", -10.4, -1.2, 9.5, 17, 12.5, 1.9)
hauler:Box("armor", 1.55, 18.7, 8.0, 21.4, 10.6, 2.25)
hauler:Box("primer", 1.2, -17.8, 7.55, 18.7, 10.5, 2.2)
hauler:Collar(16, 23, 2.1, 3.3, 3.55, "emit")
hauler:Collar(-31, -23, 0, -2.2, 6.4, "emit", true)
hauler:Collar(15.4, 22.7, 17.4, -0.5, 4.06, "dark")
hauler:Collar(14.0, 23.0, -17.4, 0.6, 3.65, "dark")
for _, s in ipairs(sides) do
    plate(hauler, "rust", s, {{-17,6.7},{7,7.2},{9,14},{-15,17}}, -4.8, -0.7)
    plate(hauler, s == 1 and "primer" or "scrap", s, {{-13,19},{5,19},{-5,32},{-16,30}}, -3.1, -0.3)
    hauler:Cable({{-21,s*9.6,4.7},{-18,s*15.8,5.3},{-12,s*23.2,2},{3,s*24.9,1.3},{10,s*22,0.7}}, 0.92)
    hauler:Rod("rust", {-20,s*5.5,-8.1}, {-10,s*22.6,-4.8}, 1.05, 8)
    hauler:Fastener(-12, s*24.9, -0.24, 0.79)
    hauler:Fastener(7.3, s*19.3, 9.1, 0.75)
end
