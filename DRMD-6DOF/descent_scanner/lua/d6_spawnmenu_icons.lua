if not CLIENT then return end

D6_SpawnPreview = {}
local P = D6_SpawnPreview
local cache, queue = {}, {}
local width, height, textureWidth = 192, 128, 256
local neutral = Color(175, 207, 207)
local direction = Vector(1, -0.82, 0.52):GetNormalized()

local function resolve(item)
    local key = item.key or item.class or ""
    local definition
    if item.kind == "npc" then
        definition = D6_Drones.Types[key]
    elseif item.kind == "support" then
        definition = D6_Supports.Definitions[key]
    elseif item.kind == "weapon" then
        definition = D6_Arsenal.Visual(key)
    end
    local mesh = item.mesh or (definition and definition.mesh)
    if not mesh or not D6_ArtGeometry.models[mesh] then return end
    local family = definition and D6_Arsenal.Families[definition.family]
    local color = item.color or (definition and definition.color) or (family and family.color) or neutral
    local id = table.concat({item.kind or "", key, mesh, color.r, color.g, color.b}, ":")
    if not cache[id] then
        cache[id] = {id=id, mesh=mesh, key=key, kind=item.kind, color=color}
        queue[#queue + 1] = cache[id]
    end
    return cache[id]
end

local function build(entry)
    local layers = {{mesh=entry.mesh, angle=angle_zero, scale=1}}
    if entry.kind == "npc" and entry.mesh == "cutter" then
        layers[#layers + 1] = {mesh="cutter_rotor", angle=angle_zero, scale=1}
    elseif entry.kind == "npc" and entry.key == "grav" then
        for i, tilt in ipairs({0, 62, -63}) do
            local angle = Angle(0, 0, 0)
            angle:RotateAroundAxis(angle_zero:Forward(), tilt)
            angle:RotateAroundAxis(angle_zero:Up(), i * 37)
            layers[#layers + 1] = {mesh="grav_gimbal", angle=angle, scale=1+(i-1)*0.065}
        end
    end

    -- Measure actual mesh vertices, including the static rotor/gimbal pose.
    local low, high = Vector(math.huge, math.huge, math.huge), Vector(-math.huge, -math.huge, -math.huge)
    for _, layer in ipairs(layers) do
        for _, faces in pairs(D6_ArtGeometry.models[layer.mesh].parts) do
            for _, face in ipairs(faces) do
                for i = 1, 3 do
                    local vertex = face[i]
                    local point = Vector(vertex[1], vertex[2], vertex[3]) * layer.scale
                    point:Rotate(layer.angle)
                    low.x, low.y, low.z = math.min(low.x,point.x), math.min(low.y,point.y), math.min(low.z,point.z)
                    high.x, high.y, high.z = math.max(high.x,point.x), math.max(high.y,point.y), math.max(high.z,point.z)
                end
            end
        end
    end
    local center, radius = (low + high) * 0.5, math.max((high - low):Length() * 0.5, 2)
    local distance = radius * 5.4
    local name = "d6_spawn_preview_v1_" .. util.CRC(entry.id)
    local texture = GetRenderTarget(name, textureWidth, height)
    local red, green, blue = render.GetColorModulation()
    local blend = render.GetBlend()
    render.PushRenderTarget(texture, 0, 0, width, height)
    render.Clear(18, 26, 31, 255, true, true)
    cam.Start3D(center + direction * distance, (-direction):Angle(), 36, 0, 0, width, height, 1, distance + radius * 3)
    render.SetBlend(1)
    local ok, err = pcall(function()
        for _, layer in ipairs(layers) do
            -- Constant preview light: keep silhouettes readable on dark maps.
            D6_Art.Draw(layer.mesh, vector_origin, layer.angle, layer.scale, entry.color, 0.95, false)
        end
    end)
    cam.End3D()
    render.SetColorModulation(red, green, blue)
    render.SetBlend(blend)
    render.PopRenderTarget()
    if not ok then
        ErrorNoHalt("[D6] Spawn preview " .. entry.mesh .. ": " .. tostring(err) .. "\n")
        return
    end
    entry.material = CreateMaterial(name .. "_mat", "UnlitGeneric", {
        ["$basetexture"]=texture:GetName(), ["$ignorez"]="1",
        ["$vertexcolor"]="1", ["$vertexalpha"]="1",
    })
end

-- Only visible Paint/PaintOver calls enqueue work. Build outside VGUI, so its
-- clipping, scissor rectangle and coordinate system are never changed.
local lastFrame = -1
hook.Add("PreRender", "D6_SpawnPreview_Cache", function()
    if #queue == 0 or lastFrame == FrameNumber() or not D6_Art then return end
    lastFrame = FrameNumber()
    build(table.remove(queue, 1))
end)

-- Public API: local VGUI coordinates; returns true once the cached image exists.
function P.Draw(item, x, y, w, h)
    if not item or w <= 0 or h <= 0 then return false end
    surface.SetDrawColor(18, 26, 31, 255)
    surface.DrawRect(x, y, w, h)
    local entry = resolve(item)
    if not entry or not entry.material then return false end
    local scale = math.min(w / width, h / height)
    local dw, dh = width * scale, height * scale
    surface.SetDrawColor(255, 255, 255, 255)
    surface.SetMaterial(entry.material)
    surface.DrawTexturedRectUV(x + (w-dw)*0.5, y + (h-dh)*0.5, dw, dh, 0, 0, width/textureWidth, 1)
    return true
end
