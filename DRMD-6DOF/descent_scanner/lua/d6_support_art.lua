-- Functional support-device greyboxes. Local +X is forward and the common
-- docking face is x=-18. Their operating sockets live in the support catalogue;
-- keep the actual mouths/receptors aligned with those coordinates when editing.
-- These register with the same mesh renderer as the weapons, without borrowing
-- the scanner shell or its sensor/light geometry.
local G = D6_ArtGeometry
local sin, cos, pi = math.sin, math.cos, math.pi
local sides = {-1, 1}

local function mirroredPlate(body, material, side, points, low, high)
    local mirrored = {}
    for i, point in ipairs(points) do mirrored[i] = {point[1], point[2]*side} end
    body:Plate(material, mirrored, low, high)
end

local function ring(body, material, x, y, z, outer, inner, depth, count)
    local rings = {{}, {}, {}, {}, {}}
    local profile = {{-depth,inner},{-depth,outer},{depth,outer},{depth,inner},{-depth,inner}}
    for i, section in ipairs(profile) do
        for j = 1, count do
            local a = (j-0.5)*2*pi/count
            rings[i][j] = {x+section[1], y+cos(a)*section[2], z+sin(a)*section[2]}
        end
    end
    body:Rings(material, rings, {x,y,z}, false)
end

local function dock(body)
    body.section = "Dock and exposed drive joint"
    body:Loft("dark",0,0,{{-16,2.7,2.7},{-13,3.5,3.5},{-8,3.3,3.0}})
    body:Collar(-18,-13.5,0,0,3.4,"dark",true)
    for _, s in ipairs(sides) do
        body:Box("black_steel",-15.3,s*4.5,0,4.3,1.8,6.8)
        body:Box("ceramic",-15.4,s*4.58,2.7,2.3,1.6,0.7)
    end
    body:Box("copper",-13.2,0,-3.35,3.1,3.5,0.55)
end

local function status(body, x, y, z, length)
    -- A small face in a dark recess, never a scanner-sized lamp or glow sprite.
    body:Box("dark",x,y,z,length+0.7,1.1,0.32)
    body:Box("emit",x,y,z+0.18,length,0.35,0.12)
end

local function port(body, x, y, z, radius, length)
    -- Collar builds an open lip, inward wall and a black seat behind the mouth.
    body:Collar(x-length,x,y,z,radius,"dark")
end

-- A split, flattened horseshoe. The two offset jaws leave real air around the
-- dark faceted receptor at (16,0,0); no cannon barrel masquerades as a mirror.
local reflector = G.New("support_reflector")
dock(reflector)
reflector.section = "Split refractor yoke"
reflector:Box("black_steel",-7.5,0,0,5,18,4.5)
for _, s in ipairs(sides) do
    local y, z = s*9.7, s*1.3
    local tip = s > 0 and 20 or 17.5
    reflector:Loft("siege_cast",y,z,{{-11,2.4,2.9},{-6,6.3,4.4},{8,6.0,4.1},{tip,2.7,2.8}})
    reflector:Loft("siege_plate",y,z+1.1,{{-8,2.4,2.2},{-3,5.6,3.1},{8.5,5.2,2.7},{tip-1.2,2.5,1.5}})
    reflector:Loft("ceramic",y,z+4.0,{{-4,2.5,0.45},{1,3.4,0.65},{9,2.7,0.6},{tip-3,1.4,0.35}})
    reflector:Box("dark",2,y+s*5.4,z,10,0.5,1.6)
    reflector:Cable({{-10,s*4,0},{-8,s*6,-3.2},{3,s*7,-3.4}},0.38)
    reflector:Fastener(-3,y,z+4.7,0.55)
    status(reflector,8,y,z+4.7,1.9)
end
reflector.section = "Recessed prism receiver"
reflector:Loft("black_steel",0,0,{{-5,2.7,1.6},{3,3.3,2.3},{11.9,4.4,3.9},{15.5,3.7,3.3}})
reflector:Loft("glass",0,0,{{12.1,3.8,3.3},{15.5,3.5,3.05},{16,2.5,2.3}})
reflector:Box("hot",15.7,2.7,0,0.2,0.28,1.9)
reflector:Box("emit",15.7,-2.7,0,0.2,0.28,1.9)

-- Two broad shield leaves, with thick shoulders and a narrow central optic.
-- The four firing outlets are forward at x18, y=+/-10, z=+/-6. The leaves stay
-- legible while docked; runtime moves the complete device for its launch cycle.
local bulwark = G.New("support_bulwark")
dock(bulwark)
bulwark.section = "Shield drive and rear hinges"
bulwark:Loft("black_steel",0,0,{{-11,3.5,4},{-4,5.2,6},{7,5.2,7}})
bulwark:Box("dark",3.5,0,0,6,27,7)
for _, s in ipairs(sides) do
    bulwark:Rod("turned_steel",{3,s*12,-10},{3,s*12,10},1.6,10)
    bulwark:Cable({{-6,s*4,-2},{0,s*8,-5},{6,s*12,-5}},0.5)
    bulwark.section = "Split shield leaves"
    bulwark:Loft("siege_cast",s*10.6,0,{{4,5.2,9},{8,8.3,13.5},{13.5,8.3,13.5},{15.2,6.8,11.4}})
    bulwark:Box("siege_plate",9.5,s*17.5,1.5,12,5,23)
    bulwark:Box("ceramic",15.25,s*10.6,0,0.65,10.0,20.5)
    bulwark:Box("black_steel",12,s*10.6,-13.7,6.2,13.6,2.6)
    bulwark:Box("hazard",15.7,s*15.1,1.5,0.4,1.3,6.5)
    status(bulwark,10.2,s*10.6,13.7,2)
    for _, z in ipairs({-6,6}) do port(bulwark,18,s*10,z,2.15,3.4) end
end
bulwark.section = "Narrow recessed shield optic"
bulwark:Box("dark",12.3,0,1.4,3.8,3,13)
bulwark:Box("glass",14.25,0,2.1,0.2,1.0,5.5)
bulwark:Box("emit",14.38,0,2.1,0.1,0.38,2.7)

-- A short mechanical fang: swept rear cheeks, a narrow armoured nose and two
-- open forward rails. There are no insect legs, rotors or scanner features.
local interceptor = G.New("support_interceptor")
dock(interceptor)
interceptor.section = "Dart spine"
interceptor:Loft("dark",0,-0.2,{{-12,3.3,2.8},{-7,6.6,4.5},{7,4.3,3.7},{21,1.05,1.6}})
interceptor:Loft("siege_plate",0,1.8,{{-10,3.5,2.8},{-4,5.7,4.3},{9,3.3,3.5},{22,0.65,0.8}})
interceptor:Loft("ceramic",0,5.1,{{-5,2.6,0.35},{0,3.5,0.8},{10,2.2,0.7},{17,0.5,0.25}})
for _, s in ipairs(sides) do
    interceptor.section = "Swept claw and forward rail"
    mirroredPlate(interceptor,"black_steel",s,{{-12,5.1},{-9,13},{-1,12.4},{18,7.1},{22,4.4},{8,4.9}},-3.0,0.8)
    mirroredPlate(interceptor,"siege_cast",s,{{-10,6},{-7,12.2},{-1,11.5},{13,7.5},{11,6.2}},0.7,3.1)
    interceptor:Rod("turned_steel",{8,s*5,0},{22,s*5,0},1.48,10)
    interceptor:Box("dark",14,s*5,1.9,12,2.3,0.6)
    port(interceptor,24,s*5,0,1.65,3.8)
    interceptor:Box("ceramic",-4,s*10,3.45,5,2.5,0.6)
    interceptor.section = "Rear directional thrusters"
    interceptor:Collar(-17,-11.5,s*7.5,-0.7,2.35,"emit",true)
    interceptor:Cable({{-13,s*5.2,-1},{-9,s*7,-3.8},{-2,s*8,-3.3}},0.36)
    status(interceptor,-1,s*4.5,4.9,1.5)
end

-- Two unequal armoured missile boxes on an exposed latch spine. Four tubes in
-- total, all opening at x20, y=+/-7, z=+/-5; their seats remain visibly recessed.
local missile = G.New("support_missile")
dock(missile)
missile.section = "Open docking spine and latch"
missile:Box("black_steel",0,0,-3,23,3.2,9)
missile:Box("dark",-3,0,5.4,17,3.7,4.5)
missile:Box("turned_steel",-4,0,8.2,12,2.1,1.0)
missile:Box("copper",-7,0,8.8,2.4,4.1,1.4)
missile:Box("turned_steel",1,0,8.8,2.7,4.1,1.4)
for _, s in ipairs(sides) do
    local rear = s > 0 and -12 or -8.5
    local halfWidth = s > 0 and 6.3 or 5.3
    missile.section = "Asymmetric missile cells"
    missile:Loft("siege_cast",s*7,0,{{rear,halfWidth*.7,6.4},{rear+3,halfWidth,9.3},
        {12.5,halfWidth,9.3},{15.8,halfWidth*.83,8.3}})
    missile:Box("siege_plate",1,s*(7+halfWidth-.2),0,19,1.3,14)
    missile:Box("ceramic",3,s*7,9.5,18,halfWidth*1.5,1.1)
    missile:Box("black_steel",2,s*7,-9.5,17,halfWidth*1.5,1.2)
    missile:Box("hazard",12,s*7,10.25,2,halfWidth*1.2,0.45)
    for _, z in ipairs({-5,5}) do port(missile,20,s*7,z,3.05,5.3) end
    for i = 0, 2 do
        missile:Box("dark",rear+4+i*2.1,s*(7+halfWidth+.5),0,1.2,0.5,7.5)
    end
    status(missile,-3,s*7,10.2,2.1)
end
missile.section = "Offset service cassette"
missile:Box("black_steel",-2,14.2,-1.7,13,3.5,8)
missile:Box("ceramic",-1.2,16,-1.7,8,0.45,4.5)
missile:Cable({{-11,4,-2},{-10,9,-6},{-2,13,-6}},0.48)

-- An armoured charge canister inside three open structural ribs. The forward
-- strike plate is a solid inset hexagon at (14,0,0), not a fifth gun muzzle.
local resonator = G.New("support_resonator")
dock(resonator)
resonator.section = "Armoured resonant canister"
resonator:Tube("siege_cast",{-12,0,0},{12,0,0},{{0,3.7},{0.15,7.3},{0.38,9.1},{0.62,8.7},{0.83,6.3},{1,4.0}},12)
resonator:Tube("ceramic",{-7.3,0,0},{8.5,0,0},{{0,7.5},{0.18,9.18},{0.55,8.93},{0.78,7.7},{1,6.05}},12)
ring(resonator,"black_steel",-6.7,0,0,8.2,7.4,0.7,12)
ring(resonator,"black_steel",5.6,0,0,8.1,7.3,0.7,12)
for j = 0, 2 do
    local a = j*2*pi/3
    local y,z = cos(a),sin(a)
    resonator.section = "Three open charge ribs"
    resonator:Rod("black_steel",{-11,y*4.5,z*4.5},{-7,y*13.6,z*13.6},1.8,6)
    resonator:Rod("siege_plate",{-7,y*13.6,z*13.6},{7,y*13.8,z*13.8},2.0,6)
    resonator:Rod("siege_cast",{7,y*13.8,z*13.8},{18.7,y*8.0,z*8.0},1.75,6)
    resonator:Rod("turned_steel",{-4,y*13.5,z*13.5},{3,y*13.6,z*13.6},0.65,6)
    -- Short charge slits in the exposed gaps, away from the impact face.
    local b = a+pi/3
    local yy,zz = cos(b),sin(b)
    resonator:Rod("dark",{-3,yy*9.02,zz*9.02},{3,yy*8.8,zz*8.8},0.64,6)
    resonator:Rod("hot",{-2.6,yy*9.69,zz*9.69},{2.6,yy*9.47,zz*9.47},0.23,6)
end
resonator.section = "Recessed hexagonal strike plate"
ring(resonator,"black_steel",13.4,0,0,5.6,3.6,1.4,6)
resonator:Rod("dark",{13,0,0},{13.7,0,0},3.8,6)
resonator:Rod("ceramic",{13.7,0,0},{14,0,0},3.3,6)
resonator:Box("hazard",14.05,0,1.3,0.08,2.7,0.55)
resonator:Box("hazard",14.05,0,-1.3,0.08,2.7,0.55)
