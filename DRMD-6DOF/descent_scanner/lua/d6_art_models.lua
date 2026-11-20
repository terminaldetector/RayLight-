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

-- The compact Combine units use ribbed pressure shells and articulated emitter banks.
local function bioHull(name, length, width, height, metal, eye)
    local model=G.New(name)
    model.section="Pressure shell and sensor spine"
    local profile={{-.96,.29,.39},{-.81,.65,.71},{-.51,.91,.92},{-.06,1,1},{.51,.83,.91},{.79,.61,.76},{.96,.43,.50}}
    local rings={}
    for i, p in ipairs(profile) do
        local ring={}
        for j=1,28 do
            local t=(j-.5)*math.pi/14
            ring[j]={p[1]*length,math.cos(t)*width*p[2],math.sin(t)*height*p[3]+1.1}
        end
        rings[i]=ring
    end
    model:Rings(metal,rings,{0,0,1.1})
    model:Loft("black_steel",0,-height*.56,{{-length*.87,width*.28,height*.24},{-length*.61,width*.6,height*.31},
        {length*.35,width*.48,height*.3},{length*.73,width*.29,height*.19}})
    optic(model,length*.98,0,height*.22,eye)
    for _, s in ipairs(sides) do
        local root=width*s
        model:Collar(-length*.99,-length*.74,root*.52,-height*.18,width*.34,"emit",true)
        model:Cable({{-length*.83,root*.56,-height*.2},{-length*.53,root*.91,-height*.62},
            {-length*.12,root*.96,-height*.73},{length*.55,root*.66,-height*.2}},.47)
        for i=0,4 do
            local x=length*(-.64+i*.23)
            local y=root*(.89+math.sin(i*.8)*.085)
            model:Rod(i%2==0 and "turned_steel" or "arc_plate",{x,y,height*.64},{x-.85,y*1.05,height*.12},.52,10)
            model:Rod("black_steel",{x-.85,y*1.05,height*.12},{x-1.57,y*.89,-height*.35},.51,10)
        end
        model:Rod("emit",{length*.54,root*.65,height*.68},{length*.68,root*.58,height*.64},.34,10)
    end
    return model
end

local function bioEmitter(model,x,y,z,mode)
    for _,s in ipairs(sides) do
        model.section=s>0 and "Port armature" or "Starboard armature"
        local yy=s*y
        local width=mode=="rocket" and 4.72 or 3.14
        model:Rod("black_steel",{x-12,yy*.61,z-2.5},{x-10,yy*.98,z},2.4,16)
        model:Tube("arc_plate",{x-16.3,yy,z},{x-3,yy,z},{{0,width*.61},{.21,width},{.57,width*.94},{1,width*.66}},24)
        model:Rod("turned_steel",{x-7.4,yy,z},{x-2.1,yy,z},width*.49,16)
        model:Collar(x-3.6,x,yy,z,width*.67,mode=="rocket" and "dark" or "emit")
        for j=0,3 do
            model:Rod(j%2==0 and "turned_steel" or "black_steel",{x-12+j*2.15,yy,z},{x-11.44+j*2.15,yy,z},width*(.96-j*.073),20)
        end
        model:Cable({{x-16.5,yy*.65,z-1.1},{x-18,yy*.92,z-3.22},{x-9,yy*1.09,z-3.7},{x-3.7,yy,z-2}},.51)
        model:Box(mode=="rocket" and "hazard" or "stencil",x-9.8,yy,z+width-.1,3.28,width, .38)
    end
end

local assault = bioHull("assault",21.1,13.1,9.6,"siege_cast",3.61)
bioEmitter(assault,19,16,-4.6,"cannon")
local interceptor = bioHull("interceptor",22.6,9.45,9.06,"arc_plate",3.05)
bioEmitter(interceptor,16.4,12.3,-3.1,"pulse")
interceptor.section="Mandibles"
for _,s in ipairs(sides) do
    interceptor:Rod("arc_shell",{6,s*5.2,-4.7},{15.1,s*6.7,-6.1},1.55,16)
    interceptor:Rod("black_steel",{15.1,s*6.7,-6.1},{21.3,s*3.92,-4.87},.84,16)
end
local artillery = bioHull("artillery",27.2,16.8,12.6,"siege_cast",4.46)
bioEmitter(artillery,16.7,19,10,"rocket")
artillery.section="Chamber armour"
artillery:Loft("siege_plate",0,11.8,{{-23,6.2,2.1},{-15,9.1,4.0},{2,8.1,4.3},{12,6.4,2.6}})
local support = bioHull("support",18.7,11.4,10.6,"arc_shell",3.42)
bioEmitter(support,21.4,15.5,.3,"repair")
support.section="Repair fluid reservoir"
support:Rod("copper",{-11,0,-7.6},{11,0,-5.55},3.69,28)
support:Collar(10,14.1,0,-5.5,3.9,"emit")

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
local gunner = bioHull("combine_gunner",19.85,10.84,8.62,"siege_plate",3.35)
bioEmitter(gunner,25,14,-1.8,"cannon")

local laserShip = bioHull("combine_laser",24.2,10.71,9.79,"arc_plate",3.0)
laserShip.section="Focusing cage"
laserShip:Collar(21,27,0,0,4.25,"emit")
for _,s in ipairs(sides) do
    laserShip:Rod("copper",{6,s*6.3,4.5},{19.5,s*4.95,2.84},1.05,14)
    laserShip:Rod("black_steel",{19.5,s*4.95,2.84},{25.6,s*3.94,.59},.66,14)
end

local rocketeer = bioHull("combine_rocketeer",24.3,13.5,10.03,"siege_cast",3.62)
bioEmitter(rocketeer,15,11.8,8,"rocket")

local seeker = bioHull("combine_seeker",22.6,11.8,10.05,"arc_shell",3.93)
bioEmitter(seeker,14,17,2.1,"rocket")

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
