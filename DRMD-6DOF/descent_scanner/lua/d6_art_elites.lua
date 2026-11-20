local G = D6_ArtGeometry
local sides = {-1, 1}
local sin, cos, sqrt, pi = math.sin, math.cos, math.sqrt, math.pi

local function dot(a, b)
    return a[1]*b[1]+a[2]*b[2]+a[3]*b[3]
end

local function cross(a, b)
    return {a[2]*b[3]-a[3]*b[2], a[3]*b[1]-a[1]*b[3], a[1]*b[2]-a[2]*b[1]}
end

local function normalized(v)
    local length = sqrt(dot(v,v))
    return {v[1]/length,v[2]/length,v[3]/length}
end

local function between(a, b, t)
    return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t}
end

local function cylinderRing(x, y, z, radius, n)
    local ring = {}
    for i=1,n do
        local theta=(i-.5)*2*pi/n
        ring[i]={x,y+cos(theta)*radius,z+sin(theta)*radius}
    end
    return ring
end

local function tubeLip(m, metal, x0, x1, y, z, outer, inner, n)
    local middle={(x0+x1)*.5,y,z}
    local width=x1-x0
    local step=math.min(width*.25,(outer-inner)*.35)
    local back=cylinderRing(x0,y,z,outer*.91,n)
    local flank=cylinderRing(x1-step,y,z,outer,n)
    local face=cylinderRing(x1,y,z,outer-step,n)
    local mouth=cylinderRing(x1,y,z,inner,n)
    local bore=cylinderRing(x0,y,z,inner*.9,n)
    m:Rings(metal,{back,flank},middle,false)
    m:Rings("turned_steel",{flank,face},middle,false)
    m:Rings(metal,{face,mouth},middle,false)
    m:Rings("dark",{mouth,bore},middle,false,true)
end

local function lens(m, x, y, z, r, material)
    local corner=cylinderRing(x-.56,y,z,r,36)
    local rim=cylinderRing(x-.16,y,z,r*.93,36)
    local facet=cylinderRing(x+.08,y,z,r*.74,36)
    local pupil=cylinderRing(x+.29,y,z,r*.39,36)
    m:Rings("glass",{corner,rim,facet},{x-.09,y,z},false)
    m:Rings(material,{facet,pupil},{x-.09,y,z},false)
    m:Rod(material,{x+.24,y,z},{x+.34,y,z},r*.39,28)
end

local function screw(m, x, y, z, axis, r)
    local a, b = {x,y,z}, {x,y,z}
    b[axis]=b[axis]+(axis==2 and y<0 and -.42 or .42)*r
    m:Rod("turned_steel",a,b,r,6)
end

local function shell(m, material, outline, slices, y, close)
    local rings = {}
    for i,slice in ipairs(slices) do
        local x,w,h,z=slice[1],slice[2],slice[3],slice[4] or 0
        rings[i]={}
        for j,p in ipairs(outline) do rings[i][j]={x,y+w*p[1],z+h*p[2]} end
    end
    m:Rings(material,rings,{(slices[1][1]+slices[#slices][1])*.5,y,slices[2][4] or 0},close)
end

local slab = {
    {-.57,-1},{.57,-1},{.91,-.68},{1,-.30},{1,.28},{.89,.58},{.56,.92},{.23,1},
    {-.23,1},{-.56,.92},{-.89,.58},{-1,.28},{-1,-.30},{-.91,-.68},
}
local cassette = {{-.84,-1},{.84,-1},{1,-.78},{1,.79},{.84,1},{-.84,1},{-1,.79},{-1,-.78}}
local oval = {}
for i=1,40 do
    local t=(i-.5)*2*pi/40
    oval[i]={cos(t),sin(t)}
end

local function armour(m, material, corners, lift)
    local center={0,0,0}
    for _,p in ipairs(corners) do
        for i=1,3 do center[i]=center[i]+p[i]/#corners end
    end
    local bevel, face = {}, {}
    for i,p in ipairs(corners) do
        local edge=between(p,center,.029)
        bevel[i]={p[1]+lift[1]*.22,p[2]+lift[2]*.22,p[3]+lift[3]*.22}
        face[i]={edge[1]+lift[1],edge[2]+lift[2],edge[3]+lift[3]}
    end
    local middle={center[1]+lift[1]*.44,center[2]+lift[2]*.44,center[3]+lift[3]*.44}
    m:Rings("black_steel",{corners,bevel},middle,false)
    m:Rings(material,{bevel,face},middle,false)
    for i=2,#face-1 do m:Tri(material,face[1],face[i],face[i+1],middle) end
end

-- Swept hoses follow the chassis ribs. The outer braid is represented by raised ridges.
local function hose(m, material, knots, radius, ribs)
    local samples={}
    for i=1,#knots-1 do
        local a,b,c,d=knots[math.max(1,i-1)],knots[i],knots[i+1],knots[math.min(#knots,i+2)]
        local distance=sqrt((c[1]-b[1])^2+(c[2]-b[2])^2+(c[3]-b[3])^2)
        local steps=math.max(5,math.ceil(distance*(ribs and 4.2 or 1.3)))
        for n=0,steps-1 do
            local t=n/steps
            local p={}
            for j=1,3 do
                p[j]=.5*(2*b[j]+(c[j]-a[j])*t+(2*a[j]-5*b[j]+4*c[j]-d[j])*t*t
                    +(3*b[j]-a[j]-3*c[j]+d[j])*t*t*t)
            end
            samples[#samples+1]=p
        end
    end
    samples[#samples+1]=knots[#knots]
    local prevRing, right
    for i,p in ipairs(samples) do
        local a,b=samples[math.max(1,i-1)],samples[math.min(i+1,#samples)]
        local tangent=normalized({b[1]-a[1],b[2]-a[2],b[3]-a[3]})
        if right then
            local projection=dot(right,tangent)
            right=normalized({right[1]-tangent[1]*projection,right[2]-tangent[2]*projection,right[3]-tangent[3]*projection})
        else
            right=normalized(cross(tangent,math.abs(tangent[3])>.88 and {0,1,0} or {0,0,1}))
        end
        local up=cross(tangent,right)
        local r=radius*(ribs and (i%3==0 and 1.09 or .96) or 1)
        local ring={}
        for j=1,10 do
            local t=j*pi/5
            local ac,bs=cos(t)*r,sin(t)*r
            ring[j]={p[1]+right[1]*ac+up[1]*bs,p[2]+right[2]*ac+up[2]*bs,p[3]+right[3]*ac+up[3]*bs}
        end
        if prevRing then
            m:Rings(material,{prevRing,ring},between(p,samples[i-1],.5),false)
        end
        prevRing=ring
    end
end

local cityMark = {
    {{.83,1},{.18,1},{.04,.8},{.04,.2},{.18,0},{.86,0}},
    {{.23,.75},{.47,1},{.47,0}},
    {{.05,1},{.92,1},{.36,0}},
}

local function stencil(m, x,y,z,s)
    local pitch,scale=-s*2.3,2.16
    local middle={x,y-s*1,z}
    for index,glyph in ipairs(cityMark) do
        for i=2,#glyph do
            local a,b=glyph[i-1],glyph[i]
            local ax,bx=(index-1)*pitch-s*a[1]*1.78,(index-1)*pitch-s*b[1]*1.78
            local az,bz=a[2]*scale,b[2]*scale
            local n=normalized({bz-az,0,ax-bx})
            local w=.11
            m:Quad("stencil",{x+ax+n[1]*w,y,z+az+n[3]*w},{x+bx+n[1]*w,y,z+bz+n[3]*w},
                {x+bx-n[1]*w,y,z+bz-n[3]*w},{x+ax-n[1]*w,y,z+az-n[3]*w},middle)
        end
    end
end

local function siegeLauncher(m, s)
    local y,z=s*14.45,22.15
    m:Box("siege_cast",-2.3,s*13.9,14.5,13.0,9.4,5.3)
    m:Rod("black_steel",{-9,s*14.3,16.1},{10.5,s*14.3,16.1},1.66,14)
    shell(m,"siege_plate",cassette,{{-15.25,6.42,4.92,z},{-13.4,7.37,5.52,z},{11.6,7.43,5.61,z},{13.65,6.8,5.25,z}},y,false)
    m:Box("siege_oxide",-4.15,y,27.56,16.6,9.66,1.70)
    m:Box("black_steel",12.77,y,z,1.75,13.10,9.74)
    m:Box("black_steel",-13.9,y,z,1.2,9.3,8.0)
    for col=-1,1 do
        for row=-1,1 do
            local yy,zz=y+col*4.15,z+row*3.35
            tubeLip(m,"black_steel",12.39,14.38,yy,zz,1.48,1.19,22)
            m:Rod(row==1 and "siege_oxide" or "dark",{13.63,yy,zz},{13.76,yy,zz},1.12,20)
        end
    end
    for i=0,5 do
        local x=-10.4+i*3.37
        m:Box("black_steel",x,y+s*6.55,24.06,1.56,1.34,2.18)
        m:Box("siege_plate",x-.18,y+s*7.05,24.00,1.10,.57,1.70)
    end
    for _,x in ipairs({-10.3,7.8}) do screw(m,x,y+s*4.9,27.28,3,.61) end
end

local function siegeCannon(m,s)
    local y=s*24.2
    shell(m,"siege_cast",slab,{{-22,4.3,3.7,0},{-14,6.7,5.9,.45},{2,7.10,5.8,.45},{11,5.3,4.2,.42}},y,true)
    m:Box("siege_plate",-4.7,y+s*2.15,5.06,20.3,7.2,2.24)
    armour(m,"siege_oxide",{{-12,y+s*6.1,-3},{3,y+s*6.75,-2.3},{9,y+s*5.1,2.7},{-9,y+s*6.45,4.68}},{0,s*.75,0})
    m:Box("black_steel",8.4,y,.4,7.2,10.7,5.2)
    for i=-1,1,2 do
        local port=y+i*2.51
        m:Tube("black_steel",{7.8,port,.4},{25.0,port,.4},{{0,1.83},{.23,1.83},{.33,1.18},{.86,1.18},{1,1.41}},20)
        tubeLip(m,"turned_steel",24,28.95,port,.4,1.62,1.03,24)
        m:Rod("dark",{25.2,port,.4},{26.4,port,.4},1.10,20)
        m:Rod("black_steel",{14.2,port,.4},{17.75,port,.4},1.62,18)
        m:Rod("turned_steel",{20.0,port,.4},{20.88,port,.4},1.4,18)
    end
    m:Rod("turned_steel",{7.8,y,-2.25},{19.85,y,-2.25},.68,12)
    for i=0,6 do
        local x=-12.17+i*2.03
        m:Box("dark",x,y+s*2,6.23,1.11,4.6,.52)
        m:Box("turned_steel",x+.25,y+s*2,6.31,.39,3.9,.52)
    end
    screw(m,-13,y+s*2.3,6.02,3,.88)
end

local siege=G.New("combine_elite")
siege.section="Armoured citadel hull"
shell(siege,"siege_cast",slab,{{-26.4,7.27,5.43,-.7},{-22.2,12.4,8.1,0},{-15.7,16.9,12.12,.45},
    {-5.5,18,13.18,.58},{6.2,17.8,12.9,.10},{16.4,14.1,9.93,-.25},{21.6,10.74,8.5,-.24},
    {24.75,8.2,6.41,.4}},0,true)
shell(siege,"black_steel",slab,{{-22,9.64,3.35,-7.8},{-17,12.97,4.7,-8.97},{10,11.37,6.1,-8.15},{20.5,8.68,4.29,-6.35}},0,true)
armour(siege,"siege_plate",{{-19,-6.2,9.4},{-18.1,-11,9.2},{-7.6,-10.84,12.7},{-.8,-9.1,13.12},
    {3.7,0,13.7},{-.8,9.1,13.12},{-7.6,10.84,12.7},{-18.1,11,9.2}}, {0,0,1.15})
armour(siege,"siege_plate",{{-.13,-10.4,13.23},{5.94,-9.33,12.25},{15.9,-7.29,9.16},{19.54,0,8.15},
    {15.9,7.29,9.16},{5.94,9.33,12.25},{-.13,10.4,13.23}}, {0,0,1.03})
for _,s in ipairs(sides) do
    armour(siege,"black_steel",{{1.4,s*3.6,13.28},{5.3,s*8.8,12.76},{15.26,s*7.1,9.96},
        {19.36,s*4.89,8.76},{14.6,s*3.42,9.77}},{.32,s*.25,.77})
    siege:Rod("turned_steel",{3.7,s*9.95,12.64},{16.25,s*7.33,9.86},.32,10)
end
siege.section="Combat optic and searchlight"
shell(siege,"siege_oxide",slab,{{17.0,9.6,7.8,1.03},{20.7,9.35,7.74,1.03},{24.25,7.2,6.49,1.03}},0,true)
tubeLip(siege,"black_steel",21,26.63,0,1.03,5.6,4.27,36)
tubeLip(siege,"siege_oxide",23.84,26.21,0,1.03,4.23,3.67,32)
lens(siege,25.03,0,1.03,3.80,"siege_eye")
tubeLip(siege,"black_steel",12.3,20.47,-9.6,6.95,2.81,2.26,32)
lens(siege,19.93,-9.6,6.95,1.98,"lamp")
for _,s in ipairs(sides) do
    siege.section=s>0 and "Port armour and radiators" or "Starboard armour and radiators"
    local y=s*16.75
    armour(siege,"siege_plate",{{-13,y,-5.1},{5.68,y,-5.4},{15.15,s*13.7,-4.85},{20.34,s*10.86,1.58},
        {13.75,s*14.27,5.69},{3.25,y,8.25},{-13,s*16,6.8}},{.09,s*1.19,0})
    armour(siege,"siege_oxide",{{-8,y,-5.82},{7.72,y,-5.95},{14.4,s*13.2,-4.88},{16.6,s*12.09,-2.72},
        {9.95,s*15.39,-4.68},{-8.2,s*16.9,-4.45}},{0,s*.66,-.47})
    siege:Box("black_steel",-11.18,s*17.21,2.28,4.52,2.1,7.39)
    for i=0,6 do
        local z=-.46+i*.88
        siege:Box("turned_steel",-11.23,s*18.15,z,3.64,.54,.24)
    end
    stencil(siege,s<0 and -3.4 or 3.74,s*18.08,-2.52,s)
    for _,p in ipairs({{-8.6,5.58},{3.49,4.54},{-9.17,-3.27},{4.39,-3.48}}) do
        screw(siege,p[1],s*17.9,p[2],2,.41)
    end
    siege:Rod("black_steel",{-24.8,s*8.47,-1.0},{-16,s*10.13,-1.0},4.48,26)
    siege:Collar(-26.2,-18.8,s*8.47,-1.0,4.43,"emit",true)
    siege.section=s>0 and "Port rocket cassette" or "Starboard rocket cassette"
    siegeLauncher(siege,s)
    siege.section=s>0 and "Port cannon" or "Starboard cannon"
    siegeCannon(siege,s)
    siege.section="Winch, towing claw and service lines"
    hose(siege,"black_steel",{{-18,s*16.8,-5.2},{-14,s*20.9,-9.8},{-6,s*22.18,-13.3},{4,s*19.25,-13.1},
        {12,s*14.1,-8.73},{13.96,s*12.1,-6.8}},1.03,true)
    hose(siege,"rubber",{{-12,s*10.6,19.0},{-16.8,s*10.7,18.9},{-17.1,s*9.1,14.8},{-12.2,s*6.6,12.24}},.39)
end
siege.section="Winch, towing claw and service lines"
siege:Box("siege_cast",-4.16,0,-14.65,15.6,13.35,6.92)
siege:Rod("black_steel",{-7.3,-5.84,-18.98},{-7.3,5.84,-18.98},3.29,24)
for i=-4,4 do
    siege:Rod("turned_steel",{-7.3,i*1.08-.14,-18.98},{-7.3,i*1.08+.14,-18.98},3.46,22)
end
for _,s in ipairs(sides) do
    hose(siege,"rubber",{{-15,s*4.38,-14.42},{-10,s*7.21,-19.8},{-3.6,s*6.25,-23.0},{.57,s*4,-21.08},
        {5.1,s*3.29,-14.13}},.43)
end
hose(siege,"turned_steel",{{-7.34,0,-19.9},{-7.27,.14,-23.8},{-7.07,.13,-27.8},{-7.01,0,-31.11}},.34)
siege:Rod("black_steel",{-7.0,0,-29.37},{-7.0,0,-34.65},1.07,20)
for i=0,2 do
    local t=(i+.16)*2*pi/3
    hose(siege,"black_steel",{{-7.0,0,-33.06},{-7.0+cos(t)*2,sin(t)*2,-34.7},{-7.0+cos(t)*4.08,sin(t)*4.08,-34.34},
        {-7.0+cos(t)*4.73,sin(t)*4.73,-32.4}},.54)
end

local function arcCannon(m,s)
    local y=s*26.4
    local near,far=s*14.6,s*20.4
    local carriage=m.section
    m.section="Fixed gimbal bearings"
    m:Rod("black_steel",{-4.7,near,1.0},{-4.7,far,1.0},8.92,40)
    m:Rod("turned_steel",{-4.7,s*18.6,1.0},{-4.7,s*19.55,1.0},9.21,40)
    m:Rod("arc_plate",{-4.7,s*19.5,1.0},{-4.7,s*22.06,1.0},7.62,40)
    m.section=carriage
    shell(m,"arc_plate",slab,{{-17.2,3.59,4.39,1.35},{-12.2,6.14,6.32,1.35},{3.7,6.75,6.29,1.35},
        {15.6,5.36,4.1,1.35},{20.2,4.16,3.10,1.35}},y,true)
    armour(m,"arc_shell",{{-13.9,y-s*3.7,6.14},{8.15,y-s*4.74,6.11},{14.74,y+s*1.9,5.53},
        {10.4,y+s*5.55,5.56},{-10.9,y+s*5.54,6.17}}, {0,0,1.16})
    tubeLip(m,"black_steel",19.7,36.11,y,1.35,2.52,1.78,30)
    tubeLip(m,"turned_steel",29.87,35.15,y,1.35,2.0,1.56,30)
    lens(m,35.27,y,1.35,1.403,"emit")
    m:Box("arc_sink",12.18,y,1.32,7.60,9.46,5.73)
    for i=0,6 do
        local x=-7.6+i*3.01
        m:Box("black_steel",x,y+s*5.45,2.04,1.76,.94,4.73)
        m:Box("turned_steel",x+.19,y+s*5.86,2.09,1.02,.50,3.60)
    end
    m.section=s>0 and "Port rotary barrels" or "Starboard rotary barrels"
    for i=0,2 do
        local angle=i*2*pi/3
        local yy,zz=y+s*cos(angle)*1.74,4.58+sin(angle)*1.74
        m:Rod("black_steel",{10.63,yy,zz},{32.48,yy,zz},.72,20)
        m:Rod("turned_steel",{21.85,yy,zz},{29.54,yy,zz},.83,20)
        tubeLip(m,"black_steel",29.04,34.25,yy,zz,.94,.53,18)
    end
    tubeLip(m,"arc_plate",20.1,23.3,y,4.58,2.72,1.98,22)
end

local arc=G.New("combine_arc_elite")
arc.section="Curved flight shell"
shell(arc,"arc_plate",oval,{{-27.6,7.89,6.82,1.62},{-24.6,11.93,9.08,1.7},{-17.4,15.11,11.83,1.88},
    {-10.0,17.17,13.67,1.91},{-1.0,17.89,14.27,1.92},{7.0,16.66,13.81,1.95},{14.4,13.78,12.7,1.94},
    {20.91,10.35,10.17,1.98},{24.62,7.50,7.85,3.1}},0,true)
shell(arc,"arc_shell",oval,{{5.9,15.6,10.91,3.22},{10.5,15.15,11.96,3.60},{15.2,12.71,11.46,3.90},
    {20.44,10.66,10.30,3.93},{24.32,8.36,8.78,3.93},{25.8,6.94,7.43,3.92}},0,false)
arc.section="Optical head"
tubeLip(arc,"black_steel",20.8,27.1,0,3.99,6.37,5.28,40)
tubeLip(arc,"arc_shell",24.3,27.3,0,3.99,5.3,4.67,40)
lens(arc,26.36,0,3.99,4.23,"emit")
for i=0,9 do
    local t=i*2*pi/10
    screw(arc,26.34,cos(t)*5.55,3.99+sin(t)*5.55,1,.31)
end
tubeLip(arc,"arc_sink",19.7,24.4,0,-5.95,3.56,2.26,28)
lens(arc,23.67,0,-5.95,2.08,"glass")
arc.section="Dorsal plasma rack"
arc:Box("black_steel",-10.3,0,16.24,12.96,8.11,5.2)
arc:Rod("turned_steel",{-9.4,0,14.53},{-9.4,0,21.36},3.12,26)
shell(arc,"arc_shell",slab,{{-26.6,4.59,2.47,19.6},{-21.32,5.94,3.5,20.02},{-12.2,7.01,3.88,20.98},
    {4.55,6.85,3.92,21.73},{8.64,4.87,3.10,22.15}},0,true)
for _,y in ipairs({-2.56,2.56}) do
    tubeLip(arc,"black_steel",5.85,9.42,y,22.10,2.11,1.37,26)
    arc:Rod("arc_sink",{7.16,y,22.10},{7.68,y,22.10},1.58,20)
end
arc:Box("arc_sink",-9.24,0,24.77,17.9,5.31,.72)
for i=0,4 do arc:Box("black_steel",-17.1+i*3.28,0,25.11,1.47,4.72,.38) end
for _,s in ipairs(sides) do
    arc.section=s>0 and "Port curved armour" or "Starboard curved armour"
    armour(arc,"arc_shell",{{-21.19,s*5.47,9.51},{-18.4,s*11.16,8.95},{-8.34,s*14.32,10.02},
        {5.43,s*14.93,9.22},{9.4,s*11.97,12.1},{-3.06,s*7.52,15.0}}, {-.22,s*.66,.56})
    arc:Box("black_steel",-19.21,s*10.08,1.20,8.69,8.34,5.18)
    for i=0,5 do
        local x=-22.54+i*1.49
        arc:Box("turned_steel",x,s*13.42,1.16,.52,.81,3.55)
    end
    arc:Collar(-29.1,-21,s*7.7,0,4.29,"emit",true)
    arc:Box("arc_plate",-20.3,s*5.67,-5.72,9.5,7.04,3.42)
    stencil(arc,-15.4,s*14.19,-3.85,s)
    for i=0,4 do
        local x=-15.15+i*3.78
        screw(arc,x,s*13.78,9.76+math.sin(i*.69)*.32,3,.46)
    end
    arc.section=s>0 and "Port arc emitter and carriage" or "Starboard arc emitter and carriage"
    arcCannon(arc,s)
    arc.section="Thermal cage and coolant feed"
    hose(arc,"black_steel",{{-18,s*12.7,-5.5},{-17.1,s*18.8,-8.4},{-8.6,s*22.54,-8.9},{.6,s*22.97,-6.21}},.70,true)
    hose(arc,"arc_sink",{{-11,s*8.3,-7.63},{-5,s*10.34,-13.44},{.1,s*10.98,-18.3},{9.4,s*6.3,-19.1},
        {13.28,s*4.31,-18.45}},.81)
end
arc.section="Thermal cage and coolant feed"
shell(arc,"arc_sink",slab,{{-14.8,5.05,4.2,-15.08},{-10.9,8.7,5.21,-15.45},{2.71,9.12,5.49,-16},
    {12.1,7.36,5.70,-17.2}},0,true)
tubeLip(arc,"black_steel",8.1,16.1,0,-18.2,6.64,5.3,40)
tubeLip(arc,"arc_sink",11.73,16.15,0,-18.2,5.76,5.11,40)
local core={}
for i=-6,6 do
    local t=i*math.pi/14
    core[#core+1]=cylinderRing(11.85+sin(t)*3.92,0,-18.2,cos(t)*4.69,40)
end
arc:Rings("hot",core,{11.85,0,-18.2},true)
for i=0,5 do
    local theta=i*pi/3+.15
    local y,z=cos(theta),sin(theta)
    hose(arc,"turned_steel",{{8.25,y*7.4,-18.2+z*7.23},{12.05,y*6.77,-18.2+z*6.38},
        {15.5,y*5.48,-18.2+z*5.49},{16.40,y*4.78,-18.2+z*4.72}},.46)
    screw(arc,13.43,y*5.87,-18.2+z*5.87,1,.37)
end
arc.section="Ventral accelerator"
arc:Box("black_steel",17.43,0,-18.2,9.6,8.85,5.16)
for _,s in ipairs(sides) do
    local y=s*3.28
    arc:Rod("turned_steel",{16.14,y,-18.2},{25.2,y,-18.2},.98,18)
    arc:Rod("arc_plate",{16.21,y,-18.2},{19.3,y,-18.2},1.51,18)
    arc:Rod("hot",{19.2,y,-17.96},{24.76,y,-17.96},.24,12)
end
