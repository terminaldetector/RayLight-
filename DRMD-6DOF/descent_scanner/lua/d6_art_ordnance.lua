local G = D6_ArtGeometry
local A = D6_Arsenal
local sin, cos, pi = math.sin, math.cos, math.pi
local sides = {-1, 1}

local function annulus(model, material, x, y, z, outer, inner, depth, count)
    local rings = {{}, {}, {}, {}, {}}
    local profile = {{-depth,inner},{-depth,outer},{depth,outer},{depth,inner},{-depth,inner}}
    for i, section in ipairs(profile) do
        for j = 1, count do
            local a = j*2*pi/count
            rings[i][j] = {x+section[1], y+cos(a)*section[2], z+sin(a)*section[2]}
        end
    end
    model:Rings(material, rings, {x,y,z}, false)
end

local function sight(body, x, y, z, size)
    body:Loft("frame", y, z, {{x-4,size*0.7,size*0.63},{x-2,size,size},{x+2.4,size,size*.84}})
    body:Collar(x+1.6,x+3.3,y,z,size*0.78,"glass")
    body:Rod("emit", {x+2.98,y,z}, {x+3.25,y,z}, size*.2, 10)
end

local function mount(spec)
    local body = G.New(spec.mesh)
    local front, width = spec.ports[1][1], spec.width
    local endX = math.min(front - 4.1, 13)
    local length = spec.body == "accelerator" and 31 or (spec.body == "rotor" and 29 or 25)
    local height = spec.body == "reactor" and 6.3 or (spec.body == "optical" and 3.55 or 4.6)
    local tail = endX-length
    body:Loft("frame", 0, -0.2, {{tail,width*.63,height*.61},{tail+3.3,width,height},
        {endX-4.7,width,height},{endX,width*.82,height*.83}})
    body:Box(spec.skin, (tail+endX)*.5-1.1, 0, height*.68, length*.74, width*1.8, height*.88)
    body:Box("steel", tail+5.2, 0, -height*.7, 8.4, width*1.68, height*.91)
    body:Box("dark", tail+3.9, 0, -height*1.12, 5.4, width*.94, .83)
    for _, s in ipairs(sides) do
        local y = width*s
        body:Box("dark", tail+length*.46, y, 1.35, length*.57, .62, height*.85)
        body:Box("steel", tail+length*.45, y*1.025, 1.35, length*.46, .51, height*.44)
        body:Box("emit", endX-5.35, y*1.047, 1.3, spec.depth*.42+1.5, .31, .41)
        body:Fastener(tail+4.2, y*.62, height*1.12, .59)
        body:Fastener(endX-5.55, y*.62, height*1.12, .61)
        for j = 0, 2+spec.depth%3 do
            local at = endX-4.7-j*1.37
            body:Box("dark", at,y*.31,height*1.12,.43,width*.47,.24)
        end
        body:Cable({{tail+3,y,1.5},{tail+4,y*1.12,-height*.14},
            {endX-5,y*1.08,-height*.51},{endX-2,y*.87,-height*.1}}, 0.40)
    end

    if spec.body == "rotor" then
        body:Rod("frame", {endX-4,0,0}, {front-1.7,0,0}, 3.64, 18)
        for j = 0, 5 do
            local y,z = cos(j*pi/3)*2.30, sin(j*pi/3)*2.30
            body:Rod("steel", {endX-8,y,z}, {front-1.1,y,z}, .95, 10)
            body:Collar(front-2.2,front,y,z,spec.bore,"dark")
        end
        annulus(body,"edge",front-1.4,0,0,3.76,3.1,.28,20)
        return
    end

    local luminous = spec.body == "optical" or spec.body == "reactor" or spec.body == "accelerator"
    for _, port in ipairs(spec.ports) do
        local x,y,z = port[1],port[2],port[3]
        body:Rod("frame", {endX-4,y,z}, {x-1.3,y,z}, spec.bore*.92, 16)
        body:Collar(x-4.4,x,y,z,spec.bore,luminous and "emit" or "dark")
        annulus(body,"edge",x-2.1,y,z,spec.bore*1.13,spec.bore*.86,.44,16)
    end
    if spec.shells == "prongs" or spec.shells == "rails" then
        for _, s in ipairs(sides) do
            local y0,y1 = width*.69*s,(spec.bore+1.3)*s
            body:Loft("steel", y0, 1.4, {{endX-8,1.44,2.04},{endX-2,1.82,2.5},{front-4.7,1.34,1.9},{front-1.3,0.90,1.22}})
            body:Rod("copper", {endX-5,y0,-1.8}, {front-.55,y1,-.66}, .65, 10)
            body:Rod("emit", {front-5.7,y1,1.8}, {front-1.7,y1,1.1}, .3, 8)
        end
    elseif spec.shells == "annular" or spec.shells == "large" then
        local bore = spec.bore
        annulus(body,"steel",front-2,0,0,bore*1.36,bore*.96,.61,24)
        for j=0,5 do
            local y,z=cos(j*pi/3)*bore*1.12,sin(j*pi/3)*bore*1.12
            body:Rod("frame",{front-8,y,z},{front-2.55,y,z},.63,8)
        end
    elseif spec.shells == "cell" or spec.shells == "bay" then
        for _, s in ipairs(sides) do
            body:Box("steel",endX-2,s*width*.76,-3.5,12,2.65,3.02)
            body:Box("copper",tail+5,s*width*.48,2.9,6.8,1.1,1.3)
        end
    end
    if spec.body == "launcher" and spec.depth > 4 then sight(body, endX-6, width*.57, height+1.8, 2.36) end
    if spec.body == "reactor" or spec.body == "dispenser" then
        body:Loft("glass", 0, height+.76, {{tail+3,1.55,1.2},{tail+5,2.2,1.6},{endX-6,2.2,1.6},{endX-4,1.4,1.1}})
        body:Box("emit", (tail+endX)*.5, 0, height+2.03, length*.48, 1.35, .6)
    end
end

for _, spec in pairs(A.Models) do if spec.body then mount(spec) end end
mount({mesh="mech_receiver", body="rotor", width=6.5, bore=1.42, skin="steel", ports={{20,0,0}}, depth=6})
local tool = G.New("tool_deployer")
tool:Loft("frame",0,0,{{-13,4,2.6},{-10,5.1,3.1},{8,5.1,3.2},{13,3.65,2.35}})
tool:Box("armor",-.8,0,2.23,19.5,8.1,3.03)
tool:Box("glass",-1,0,3.72,9.9,5.25,.79)
tool:Box("emit",-.87,0,4.09,5.6,.52,.24)
tool:Box("emit",-.19,1.12,4.09,4.4,.46,.24)
tool:Collar(9.3,13,0,.15,2.7,"emit")
for _, s in ipairs(sides) do
    tool:Fastener(-7.15,s*3.35,3.65,.54)
    tool:Box("hazard",5.85,s*3.65,3.5,2.25,1.86,.51)
    tool:Rod("steel",{-8,s*4.8,-2},{-4,s*5.9,-2},1.04,8)
end

local function payload(name, nose, radius, endX, finish, shape)
    local body = G.New(name)
    body:Tube(finish, {nose,0,0}, {endX,0,0}, {{0,radius*.37},{.12,radius*.81},{.36,radius},{.72,radius},{.85,radius*.74},{1,.15}}, 18)
    body:Collar(nose-.52,nose+2.0,0,0,radius*.66,"emit",true)
    annulus(body,"frame",nose+(endX-nose)*.36,0,0,radius*1.01,radius*.9,.36,18)
    annulus(body,"edge",nose+(endX-nose)*.64,0,0,radius*1.025,radius*.92,.31,18)
    for j=0,3 do
        local a = j*pi*.5 + pi*.25
        local v,w = cos(a),sin(a)
        if shape == "fin" or shape == "long" then
            local z = shape == "long" and 1.86 or 1.56
            body:Rod("steel",{nose+1,v*radius*.52,w*radius*.52},{nose+2.8,v*radius*z,w*radius*z},radius*.12,8)
            body:Rod("frame",{nose+2.8,v*radius*z,w*radius*z},{nose+5.2,v*radius*.83,w*radius*.83},radius*.14,8)
        elseif shape == "cluster" then
            body:Rod("steel",{nose+3,v*radius,w*radius},{endX-3,v*radius,w*radius},radius*.31,10)
            body:Rod("emit",{endX-4,v*radius,w*radius},{endX-2.6,v*radius,w*radius},radius*.17,8)
        else
            body:Rod("copper",{nose+1,v*radius*.81,w*radius*.81},{nose+3.5,v*radius,w*radius},radius*.18,8)
        end
    end
    return body
end
payload("shot_shell", -8.5, 4.1, 7.6, "armor", "shell")
payload("shot_cluster", -10.8, 3.75, 11.3, "hazard", "cluster")
payload("shot_homing", -11.15, 2.75, 13.26, "bone", "fin")
payload("shot_mega", -13.85, 4.25, 15.3, "ceramic", "long")
payload("shot_shard", -4.4, 1.35, 4.2, "steel", "shell")

local arc = G.New("shot_arcpulse")
arc:Tube("glass",{-6.4,0,0},{6.4,0,0},{{0,.94},{.2,2.5},{.38,2.8},{.65,2.8},{.8,2.5},{1,.04}},16)
arc:Tube("hot",{-5.7,0,0},{5.85,0,0},{{0,.3},{.4,1.61},{.67,1.65},{1,.11}},14)
for j=0,3 do
    local y,z=cos(j*pi*.5)*2.28,sin(j*pi*.5)*2.28
    arc:Rod("emit",{-3.6,y,z},{4.3,y,z},.41,8)
end
annulus(arc,"steel",-2.1,0,0,2.98,2.12,.36,18)
local ion = G.New("shot_ion")
ion:Tube("glass",{-7,0,0},{7,0,0},{{0,.1},{.2,5},{.43,6},{.57,6},{.8,5},{1,.1}},20)
ion:Rod("hot",{-4.8,0,0},{5.55,0,0},4.17,16)
for _, x in ipairs({-3.9,3.7}) do annulus(ion,"edge",x,0,0,5.35,4.19,.5,23) end
for j=0,5 do
    local y,z=cos(j*pi/3)*5.02,sin(j*pi/3)*5.02
    ion:Rod("frame",{-4.1,y,z},{4,y,z},.61,8)
    ion:Rod("emit",{-.9,y,z},{2.3,y,z},.42,8)
end

local function device(name, skin, wide, height, count, cage)
    local body = G.New(name)
    body:Tube("frame",{0,0,-height*.82},{0,0,height*.72},{{0,wide*.44},{.22,wide*.78},{.47,wide},{.74,wide},{1,wide*.57}},20)
    body:Tube(skin,{0,0,-height*.39},{0,0,height*.72},{{0,wide*.92},{.38,wide*.93},{.63,wide*.84},{1,wide*.56}},20)
    body:Tube("dark",{0,0,height*.54},{0,0,height*.90},{{0,wide*.49},{.54,wide*.49},{1,wide*.39}},16)
    body:Rod("glass",{0,0,height*.86},{0,0,height},wide*.41,16)
    body:Rod("emit",{0,0,height*.96},{0,0,height*1.12},wide*.24,18)
    for j=0,count-1 do
        local a=j*2*pi/count
        local x,y = cos(a),sin(a)
        body:Rod("steel",{x*wide*.5,y*wide*.5,-height*.57},{x*wide*1.08,y*wide*1.08,-height*.25},wide*.17,10)
        body:Fastener(x*wide*.68,y*wide*.68,height*.40,.55)
        body:Rod("emit",{x*wide*.87,y*wide*.87,.22},{x*wide*1.06,y*wide*1.06,.27},wide*.074,8)
        if cage then body:Rod("copper",{x*wide*.86,y*wide*.86,0},{x*wide*.48,y*wide*.48,height*1.31},wide*.089,8) end
    end
    return body
end

device("mine_plasma","armor",11.6,5.95,6,false)
local sink = device("mine_gravity","frame",10.9,7.4,4,true)
annulus(sink,"steel",0,0,.35,9.75,7.56,.69,18)
device("mine_air","hazard",11.4,6.21,4,true)
device("node_snare","steel",9.6,4.4,3,true)
local dark = device("node_dark","stripe",10.3,8.6,5,true)
annulus(dark,"copper",0,0.02,1.9,8.66,6.19,.62,18)

local supply = G.New("supply")
supply:Box("frame",0,0,0,21.2,16.7,13.8)
supply:Box("armor",.15,0,6.65,18.75,15.85,2.01)
for _, s in ipairs(sides) do
    supply:Box("steel",0,s*7.78,-.2,17.23,.95,8.6)
    supply:Box("canvas",s*6.33,0,0,1.72,17.22,14.33)
    supply:Box("hazard",0,s*8.37,1.6,7.92,.65,2.55)
end
supply:Box("emit",9.51,0,3.4,1.36,5.46,1.13)
local ballast = G.New("salvage_ballast")
ballast:Tube("scrap",{0,0,-11},{0,0,11},{{0,6},{.11,8.65},{.23,9.6},{.80,9.6},{.91,8.65},{1,6.2}},16)
for _, z in ipairs({-6.1,5.2}) do ballast:Rod("rust",{0,0,z},{0,0,z+.8},9.92,16) end
ballast:Box("frame",0,0,9.86,7.5,4.73,1.98)
ballast:Box("hazard",0,0,11.02,3.47,2.89,.37)
