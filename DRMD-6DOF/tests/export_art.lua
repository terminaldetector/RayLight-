local root = "../descent_scanner/lua/"
local selected = arg[1]
function Color(r, g, b) return {r, g, b} end
FCVAR_ARCHIVE, FCVAR_REPLICATED = 0, 0
function CreateConVar() return {} end
dofile(root .. "d6_session.lua")
dofile(root .. "d6_arsenal.lua")
dofile(root .. "d6_art_geometry.lua")
dofile(root .. "d6_art_models.lua")
dofile(root .. "d6_art_elites.lua")
dofile(root .. "d6_art_ordnance.lua")
dofile(root .. "d6_support_art.lua")
dofile(root .. "d6_drone_catalog.lua")
dofile(root .. "d6_supports.lua")
assert(not selected or D6_ArtGeometry.models[selected], "Unknown model: " .. tostring(selected))

local function json(value)
    if type(value) == "number" then return string.format("%.5f", value) end
    if type(value) == "string" then return string.format("%q", value) end
    assert(type(value) == "table")
    local fields = {}
    if rawget(value, 1) ~= nil then
        for _, item in ipairs(value) do fields[#fields + 1] = json(item) end
        return "[" .. table.concat(fields, ",") .. "]"
    end
    for key, item in pairs(value) do
        fields[#fields + 1] = json(key) .. ":" .. json(item)
    end
    return "{" .. table.concat(fields, ",") .. "}"
end

local output = assert(io.open(arg[2] or "art-models.json", "w"))
local count, faces = 0, 0
local data = {
    palette = D6_ArtGeometry.palette, finishes = D6_ArtGeometry.finishes,
    scanner = D6_Arsenal.Scanner, enforcer = D6_Session.Enforcer, mounts = {}, models = {}, drones = {}, weapons = {}, payloads = {},
    attachments = {support_reflector = {receptor = D6_Supports.Definitions.reflector.ports[1]}},
}
for index, class in ipairs(D6_Arsenal.Defaults) do
    local item = D6_Arsenal.Entries[class]
    local family = D6_Arsenal.Families[item.family]
    data.mounts[index] = {name = item.name, mesh = item.mesh, ink = family.color,
        offset = D6_Arsenal.Mounts[index].pos, ports = item.ports}
end
for key, craft in pairs(D6_Drones.Types) do
    assert(D6_ArtGeometry.models[craft.mesh], key)
    data.drones[key] = {mesh = craft.mesh, color = craft.color, scale = craft.scale, guns = craft.guns}
end
local usedWeaponMeshes = {}
for _, weapon in ipairs(D6_Arsenal.Order) do
    assert(D6_ArtGeometry.models[weapon.mesh] and not usedWeaponMeshes[weapon.mesh], weapon.class)
    usedWeaponMeshes[weapon.mesh] = true
    data.weapons[weapon.class] = {mesh=weapon.mesh, color=D6_Arsenal.Families[weapon.family].color}
end
for key, payload in pairs(D6_Arsenal.Ordnance) do
    assert(D6_ArtGeometry.models[payload.mesh],key)
    data.payloads[key] = payload.color
end
assert(D6_ArtGeometry.models[D6_Arsenal.ToolVisual.mesh] and D6_ArtGeometry.models[D6_Arsenal.MechVisual.mesh])
for name, model in pairs(D6_ArtGeometry.models) do
    if not selected or selected == name then
        count = count + 1
        for material, part in pairs(model.parts) do
            assert(D6_ArtGeometry.palette[material] and #part > 0 and #part * 3 < 65535)
            faces = faces + #part
            for _, face in ipairs(part) do
                for i = 1, 4 do
                    for _, coordinate in ipairs(face[i]) do assert(coordinate == coordinate and math.abs(coordinate) < 500) end
                end
            end
        end
        data.models[name] = model.parts
    end
end
output:write(json(data))
output:close()
local function entries(t)
    local n=0
    for _ in pairs(t) do n=n+1 end
    return n
end
print(string.format("PASS | %d unique weapon rigs | %d enemy classes | %d ordnance and cargo types",
    #D6_Arsenal.Order,entries(data.drones),entries(data.payloads)))
print(string.format("PASS | %d production meshes | %d triangles | finite vertices and material keys", count, faces))
