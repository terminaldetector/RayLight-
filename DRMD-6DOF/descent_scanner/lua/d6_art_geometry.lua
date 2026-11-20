D6_ArtGeometry = {models = {}}
local G = D6_ArtGeometry

-- Materials are shared by the in-game mesh builder and the model preview exporter.
G.palette = {
    armor = {103, 116, 112}, bone = {139, 141, 128}, steel = {102, 113, 117},
    edge = {133, 142, 141}, frame = {57, 69, 73}, dark = {27, 33, 37},
    copper = {111, 86, 70}, hazard = {149, 117, 72}, glass = {45, 58, 60},
    ceramic = {175, 180, 170}, stripe = {117, 49, 45},
    scrap = {111, 114, 88}, rust = {135, 84, 54}, tarp = {93, 92, 79},
    primer = {119, 104, 87}, oxide = {145, 68, 49}, canvas = {120, 115, 90},
    rubber = {43, 47, 47}, emit = {255, 255, 255}, hot = {255, 204, 127},
}
G.finishes = {
    armor = "coating", bone = "coating", hazard = "coating",
    ceramic = "coating", stripe = "coating",
    steel = "alloy", edge = "alloy", frame = "alloy", copper = "alloy",
    dark = "polymer", rubber = "polymer", glass = "glass",
    scrap = "salvage", rust = "salvage", tarp = "salvage", primer = "salvage",
    oxide = "salvage", canvas = "polymer",
}

function G.UV(position, normal)
    local x, y, z = math.abs(normal[1]), math.abs(normal[2]), math.abs(normal[3])
    if x >= y and x >= z then return position[2]/24, -position[3]/24 end
    if y >= z then return position[1]/24, -position[3]/24 end
    return position[1]/24, -position[2]/24
end

local cos, sin, sqrt, pi = math.cos, math.sin, math.sqrt, math.pi
local function direction(a, b)
    return {b[1] - a[1], b[2] - a[2], b[3] - a[3]}
end
local function cross(a, b)
    return {a[2]*b[3] - a[3]*b[2], a[3]*b[1] - a[1]*b[3], a[1]*b[2] - a[2]*b[1]}
end
local function dot(a, b) return a[1]*b[1] + a[2]*b[2] + a[3]*b[3] end
local function unit(v)
    local length = sqrt(dot(v, v))
    if length < 0.00001 then return end
    return {v[1]/length, v[2]/length, v[3]/length}
end

local Model = {}
Model.__index = Model

function G.New(name)
    local model = setmetatable({parts = {}}, Model)
    G.models[name] = model
    return model
end

function Model:Tri(material, a, b, c, center, inward)
    local normal = unit(cross(direction(a, b), direction(a, c)))
    if not normal then return end
    if (dot(normal, direction(center, a)) < 0) ~= (inward == true) then
        b, c = c, b
        normal = {-normal[1], -normal[2], -normal[3]}
    end
    local part = self.parts[material] or {}
    self.parts[material] = part
    part[#part + 1] = {a, b, c, normal}
end

function Model:Quad(material, a, b, c, d, center, inward)
    self:Tri(material, a, b, c, center, inward)
    self:Tri(material, a, c, d, center, inward)
end

function Model:Rings(material, rings, center, cap, inward)
    for i = 1, #rings - 1 do
        local a, b = rings[i], rings[i + 1]
        for j = 1, #a do
            local k = j % #a + 1
            self:Quad(material, a[j], a[k], b[k], b[j], center, inward)
        end
    end
    if cap == false then return end
    for _, index in ipairs({1, #rings}) do
        local ring = rings[index]
        for j = 2, #ring - 1 do self:Tri(material, ring[1], ring[j], ring[j + 1], center) end
    end
end

-- Each slice is x, half-width, half-height, centerline height.
function Model:Loft(material, y, z, slices)
    local rings = {}
    for i, slice in ipairs(slices) do
        local x, w, h, dz = slice[1], slice[2], slice[3], slice[4] or 0
        rings[i] = {}
        local outline = {{-0.72,-1},{0.72,-1},{1,-0.62},{1,0.62},
            {0.72,1},{-0.72,1},{-1,0.62},{-1,-0.62}}
        for j, p in ipairs(outline) do rings[i][j] = {x, y + w*p[1], z + dz + h*p[2]} end
    end
    self:Rings(material, rings, {(slices[1][1] + slices[#slices][1])/2, y, z})
end

function Model:Box(material, x, y, z, length, width, height)
    local w, h = width/2, height/2
    local a, b = x - length/2, x + length/2
    local bevel = math.min(length/4, width/5, height/3)
    self:Loft(material, y, z, {{a,w*0.86,h*0.83},{a+bevel,w,h},{b-bevel,w,h},{b,w*0.86,h*0.83}})
end

function Model:Plate(material, points, low, high)
    local a, b, center = {}, {}, {0, 0, (low + high)/2}
    for i, p in ipairs(points) do
        a[i], b[i] = {p[1], p[2], low}, {p[1], p[2], high}
        center[1], center[2] = center[1] + p[1]/#points, center[2] + p[2]/#points
    end
    self:Rings(material, {a, b}, center)
end

function Model:Tube(material, start, finish, radii, sides)
    local axis = unit(direction(start, finish))
    local u = unit(cross(axis, math.abs(axis[3]) > 0.9 and {0, 1, 0} or {0, 0, 1}))
    local v = cross(axis, u)
    local rings = {}
    for i, slice in ipairs(radii) do
        local t, radius = slice[1], slice[2]
        local x = start[1] + (finish[1] - start[1])*t
        local y = start[2] + (finish[2] - start[2])*t
        local z = start[3] + (finish[3] - start[3])*t
        rings[i] = {}
        for j = 1, sides do
            local a = (j - 0.5)*2*pi/sides
            local c, s = radius*cos(a), radius*sin(a)
            rings[i][j] = {x + u[1]*c + v[1]*s, y + u[2]*c + v[2]*s, z + u[3]*c + v[3]*s}
        end
    end
    self:Rings(material, rings, {(start[1] + finish[1])/2, (start[2] + finish[2])/2, (start[3] + finish[3])/2})
end

function Model:Rod(material, a, b, radius, sides)
    self:Tube(material, a, b, {{0, radius*0.81}, {0.1, radius}, {0.9, radius}, {1, radius*0.81}}, sides or 8)
end

function Model:Collar(x0, x1, y, z, radius, optic, atRear)
    local tip, root = x1, x0
    local axis = 1
    if atRear then tip, root, axis = x0, x1, -1 end
    local function ring(x, scale)
        local vertices = {}
        for i = 1, 16 do
            local angle = (i - 0.5)*pi/8
            vertices[i] = {x, y + cos(angle)*radius*scale, z + sin(angle)*radius*scale}
        end
        return vertices
    end
    local center = {(root + tip)*0.5, y, z}
    local step = math.min(math.abs(tip - root)*0.34, radius*0.36)
    local shoulder = ring(tip-axis*step, 1)
    local edge = ring(tip, 0.89)
    local mouth = ring(tip, 0.69)
    local seat = ring(tip-axis*radius*0.40, 0.61)
    self:Rings("steel", {ring(root, 0.84), shoulder}, center, false)
    self:Rings("edge", {shoulder, edge, mouth}, center, false)
    self:Rings("dark", {mouth, seat}, center, false, true)

    local depth = tip-axis*radius*0.40
    if optic == "emit" then
        self:Rod("glass", {depth-axis*0.16,y,z}, {depth,y,z}, radius*0.63, 16)
        if atRear then
            self:Rod("emit", {depth,y,z}, {depth+axis*0.20,y,z}, radius*0.27, 10)
        else
            self:Box("emit", depth+0.12, y, z, 0.22, radius*0.77, radius*0.14)
        end
    else
        self:Rod(optic or "dark", {depth-axis*0.16,y,z}, {depth,y,z}, radius*0.63, 16)
    end
end

function Model:Fastener(x, y, z, radius)
    self:Rod("dark", {x,y,z-0.10}, {x,y,z+0.08}, radius*1.17, 8)
    self:Rod("edge", {x,y,z}, {x,y,z+radius*0.40}, radius, 6)
end

function Model:Cable(points, radius)
    for i = 2, #points do
        self:Rod("rubber", points[i-1], points[i], radius, 8)
    end
end
