-- Run from tests/: texlua support_art_unit.lua
-- Exercises the actual procedural meshes without GMod. Engine lighting, moving
-- attachments and first-person occlusion still require the in-game art range.
local root = arg[1] or "../descent_scanner/lua/"
local passed = 0
local function check(name, condition)
    assert(condition, name)
    passed = passed+1
    print("PASS | " .. name)
end
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

dofile(root .. "d6_art_geometry.lua")
dofile(root .. "d6_support_art.lua")
local G = D6_ArtGeometry
local names = {"support_reflector","support_bulwark","support_interceptor","support_missile","support_resonator"}
local summaries = {}

local function frontAt(model, y, z)
    -- Cast a ray from +X through a given mouth/receptor. A closed or wrongly
    -- positioned barrel cap would be detected in front of its recessed seat.
    local best, material
    for ink, part in pairs(model.parts) do
        for _, face in ipairs(part) do
            local a,b,c = face[1],face[2],face[3]
            local by,bz,cy,cz = b[2]-a[2],b[3]-a[3],c[2]-a[2],c[3]-a[3]
            local determinant = by*cz-bz*cy
            if math.abs(determinant) > 0.000001 then
                local yy,zz = y-a[2],z-a[3]
                local u,v = (yy*cz-zz*cy)/determinant,(by*zz-bz*yy)/determinant
                if u >= -0.000001 and v >= -0.000001 and u+v <= 1.000001 then
                    local x = a[1]+u*(b[1]-a[1])+v*(c[1]-a[1])
                    if not best or x > best then best,material = x,ink end
                end
            end
        end
    end
    return best,material
end

for _, name in ipairs(names) do
    local model = G.models[name]
    check(name .. " is registered independently", type(model) == "table" and type(model.parts) == "table")
    local count, materials, luminous, area, lightArea = 0,0,0,0,0
    local low,high = {math.huge,math.huge,math.huge},{-math.huge,-math.huge,-math.huge}
    local radius, valid = 0,true
    for material, part in pairs(model.parts) do
        materials = materials+1
        valid = valid and G.palette[material] ~= nil
        for _, face in ipairs(part) do
            count = count+1
            local normal = face[4]
            local norm = 0
            for axis=1,3 do
                valid = valid and finite(normal[axis])
                norm = norm+normal[axis]*normal[axis]
            end
            valid = valid and math.abs(norm-1) < 0.00001
            for vertex=1,3 do
                local p,r = face[vertex],0
                for axis=1,3 do
                    valid = valid and finite(p[axis])
                    low[axis],high[axis] = math.min(low[axis],p[axis]),math.max(high[axis],p[axis])
                    r = r+p[axis]*p[axis]
                end
                radius = math.max(radius,math.sqrt(r))
            end
            local a,b,c = face[1],face[2],face[3]
            local ux,uy,uz = b[1]-a[1],b[2]-a[2],b[3]-a[3]
            local vx,vy,vz = c[1]-a[1],c[2]-a[2],c[3]-a[3]
            local nx,ny,nz = uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx
            local faceArea = math.sqrt(nx*nx+ny*ny+nz*nz)*0.5
            valid = valid and finite(faceArea) and faceArea > 0.000001
            area = area+faceArea
            if material == "emit" or material == "hot" then
                luminous = luminous+1
                lightArea = lightArea+faceArea
            end
        end
    end
    check(name .. " has finite nondegenerate vertices and unit normals", valid)
    check(name .. " has bounded mesh cost", count >= 400 and count <= 4500 and materials >= 5)
    check(name .. " has restrained indicator area", luminous > 0 and lightArea/area < 0.035)
    check(name .. " keeps the common docking face at x=-18", math.abs(low[1]+18) < 0.00001)
    check(name .. " fits the shared support render envelope", low[1] >= -18.01 and high[1] <= 24.01
        and low[2] >= -20.1 and high[2] <= 20.1 and low[3] >= -18 and high[3] <= 18 and radius < 33)
    summaries[name] = {low=low,high=high,count=count,radius=radius,
        length=high[1]-low[1],width=high[2]-low[2],height=high[3]-low[3]}
end

local ports = {
    support_bulwark = {{18,-10,-6},{18,-10,6},{18,10,-6},{18,10,6}},
    support_interceptor = {{24,-5,0},{24,5,0}},
    support_missile = {{20,-7,-5},{20,-7,5},{20,7,-5},{20,7,5}},
}
for name, sockets in pairs(ports) do
    for index, socket in ipairs(sockets) do
        local x,material = frontAt(G.models[name],socket[2],socket[3])
        check(name .. " socket " .. index .. " opens onto a recessed dark seat",
            x and material == "dark" and x < socket[1]-0.3 and x > socket[1]-2)
        local lip = false
        for _, part in pairs(G.models[name].parts) do
            for _, face in ipairs(part) do
                for vertex=1,3 do
                    local p = face[vertex]
                    local distance = (p[2]-socket[2])^2+(p[3]-socket[3])^2
                    if math.abs(p[1]-socket[1]) < 0.00001 and distance > 0.5 and distance < 11 then lip=true end
                end
            end
        end
        check(name .. " socket " .. index .. " has its visible lip at the gameplay origin",lip)
    end
end

local receptor, material = frontAt(G.models.support_reflector,0,0)
check("reflector receptor meets x16 without a cannon muzzle", material == "glass" and math.abs(receptor-16) < 0.00001)
for _, side in ipairs({-1,1}) do
    local gap = frontAt(G.models.support_reflector,side*5.5,0)
    check("reflector has an open optical gap on side " .. side, not gap or gap < 14)
end
local plate, plateMaterial = frontAt(G.models.support_resonator,0,0)
check("resonator has a solid strike plate at x14", plateMaterial == "ceramic" and math.abs(plate-14) < 0.00001)

for _, name in ipairs(names) do
    local s = summaries[name]
    print(string.format("MESH | %s | %d triangles | bounds (%.3f, %.3f, %.3f)..(%.3f, %.3f, %.3f) | radius %.3f",
        name,s.count,s.low[1],s.low[2],s.low[3],s.high[1],s.high[2],s.high[3],s.radius))
end

local reflector,bulwark,interceptor,missile,resonator = summaries[names[1]],summaries[names[2]],summaries[names[3]],summaries[names[4]],summaries[names[5]]
check("reflector reads as a flat wide yoke", reflector.width > reflector.height*2.6 and reflector.length > 35)
check("bulwark has the widest and tallest broad shield silhouette", bulwark.width > 39
    and bulwark.width > reflector.width+6 and bulwark.height > 28)
check("interceptor is a longer narrow dart", interceptor.length > 41 and interceptor.width < 27
    and interceptor.height < 12 and interceptor.length > missile.length+3)
check("missile cassette is visibly asymmetric", missile.high[2] > -missile.low[2]+2 and missile.height > 20)
check("resonator cage has a deep canister silhouette", resonator.height > 24 and resonator.height > reflector.height*2)
for i=1,#names do
    for j=i+1,#names do
        local a,b = summaries[names[i]],summaries[names[j]]
        local distance = math.abs(a.length-b.length)+math.abs(a.width-b.width)+math.abs(a.height-b.height)
        check(names[i] .. " and " .. names[j] .. " retain distinct silhouette dimensions",distance > 6)
    end
end

print(string.format("PASS | %d support geometry checks",passed))
