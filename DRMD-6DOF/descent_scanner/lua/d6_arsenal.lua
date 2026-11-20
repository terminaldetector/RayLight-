D6_Arsenal = {}
local A = D6_Arsenal

A.Scanner = {model = "models/combine_scanner.mdl", mesh = "scanner_player", scale = 1.6, yawOffset = 90,
    eye = {15.268, 0, 0.649}}

-- The scanner's eye faces local -Y, while gun meshes face local +X.
function A.ScannerAngles(aim)
    local hull = Angle(aim.p, aim.y, aim.r)
    hull:RotateAroundAxis(aim:Up(), A.Scanner.yawOffset)
    return hull
end

A.Families = {
    pulse = {label = "Кинетика", color = Color(245, 182, 105), mesh = "mount_pulse", muzzle = 16},
    arc = {label = "Энергосистема", color = Color(115, 222, 219), mesh = "mount_arc", muzzle = 16},
    rack = {label = "Ракетный блок", color = Color(242, 138, 89), mesh = "mount_rack", muzzle = 12},
    rail = {label = "Ускоритель", color = Color(157, 172, 255), mesh = "mount_rail", muzzle = 22},
    field = {label = "Полевой модуль", color = Color(198, 155, 240), mesh = "mount_field", muzzle = 13},
    optic = {label = "Оптика", color = Color(149, 227, 242), mesh = "mount_optic", muzzle = 0},
    mine = {label = "Минный отсек", color = Color(182, 222, 124), mesh = "mount_mine", muzzle = 12},
}

local function art(mesh, body, bore, width, shells, skin, ports, depth)
    return {mesh = mesh, body = body, bore = bore, width = width, shells = shells,
        skin = skin, ports = ports, depth = depth or 0}
end

-- Every weapon names its own geometry and its actual emission sockets.
A.Models = {
    mg = art("mount_pulse", nil, 2.28, 5, "twin", "armor", {{15.55,2.75,0},{15.55,-2.75,0}}),
    vulcan = art("gun_vulcan", "rotor", 1.27, 5.4, "six", "steel", {{21.0,2.3,0},{21.0,-2.3,0}}),
    flak = art("gun_flak", "launcher", 3.25, 6.6, "twin", "bone", {{14.8,3.65,-0.8},{14.8,-3.65,-0.8}}, 2),
    plasma = art("mount_arc", nil, 3.28, 5, "lens", "armor", {{15.55,0,0}}),
    laser = art("gun_laser", "optical", 2.9, 4, "lens", "steel", {{19.2,0,0}}, 3),
    quad_laser = art("gun_quad_laser", "optical", 1.63, 7.2, "four", "armor", {{15.6,3.7,2.3},{15.6,3.7,-2.3},{15.6,-3.7,2.3},{15.6,-3.7,-2.3}}, 7),
    overdrive = art("gun_overdrive", "reactor", 3.27, 6.25, "lens", "copper", {{19.6,0,0}}, 6),
    heavy = art("gun_heavy", "launcher", 5.45, 7.0, "large", "steel", {{18.3,0,-0.6}}, 6),
    rockets = art("mount_rack", nil, 2.46, 6.5, "four", "armor", {{12.05,3.4,-2.3},{12.05,3.4,2.4},{12.05,-3.4,-2.3},{12.05,-3.4,2.4}}),
    concussion = art("gun_concussion", "launcher", 3.42, 4.9, "large", "armor", {{17.7,0,-0.6}}, 5),
    homing = art("gun_homing", "launcher", 3.24, 6.1, "lens", "bone", {{21.3,0,0.1}}, 7),
    smart_missile = art("gun_smart_missile", "launcher", 3.3, 7.2, "cell", "frame", {{14.9,0,0}}, 10),
    mega_missile = art("gun_mega_missile", "launcher", 5.5, 7.8, "large", "ceramic", {{22.1,0,-0.6}}, 3),
    frag = art("gun_frag", "launcher", 2.84, 6.8, "cell", "hazard", {{15.2,0,0}}, 8),
    gravy_railgun = art("mount_rail", nil, 1.2, 5, "rails", "steel", {{22,0,0}}),
    railmk2 = art("gun_railmk2", "accelerator", 2.15, 5.4, "rails", "bone", {{25.7,0,0}}, 7),
    darklance = art("gun_darklance", "accelerator", 3.5, 6.4, "prongs", "frame", {{25,0,0}}, 10),
    bfg = art("gun_bfg", "reactor", 5.0, 7.4, "prongs", "bone", {{16.8,0,0}}, 8),
    shockwave = art("gun_shockwave", "reactor", 4.9, 7.1, "annular", "armor", {{11.5,0,0}}, 3),
    energytrap = art("gun_energytrap", "dispenser", 3.1, 6.0, "cell", "steel", {{16.3,0,0}}, 7),
    darkfield = art("gun_darkfield", "reactor", 3.4, 6.25, "annular", "frame", {{13.4,0,0}}, 7),
    telefrag = art("gun_telefrag", "accelerator", 2.9, 5.2, "prongs", "steel", {{21.1,0,0}}, 8),
    whiplash = art("gun_whiplash", "optical", 2.9, 5.4, "prongs", "armor", {{14.3,0,0}}, 5),
    warp = art("gun_warp", "reactor", 3.55, 6.6, "prongs", "frame", {{13.5,0,0}}, 9),
    reactor = art("gun_reactor", "reactor", 4.7, 7.2, "annular", "hazard", {{15.3,0,0}}, 8),
    phasegate = art("gun_phasegate", "accelerator", 3.8, 7.25, "prongs", "bone", {{19.6,0,0}}, 9),
    hyperbeam = art("mount_optic", nil, 0, 5, "cap", "steel", {}),
    plasmamine = art("mount_mine", nil, 3.2, 6, "bay", "armor", {{11.65,0,0}}),
    gravmine = art("gun_gravmine", "dispenser", 3.4, 6.5, "bay", "frame", {{13.6,0,-2.1}}, 5),
}

A.Ordnance = {
    mine_plasma = {mesh = "mine_plasma", radius = 12, color = Color(100,192,220), state = "armed"},
    mine_gravity = {mesh = "mine_gravity", radius = 12, color = Color(175,133,224), state = "active"},
    mine_air = {mesh = "mine_air", radius = 13, color = Color(239,145,90), state = "trigger"},
    node_snare = {mesh = "node_snare", radius = 11, color = Color(113,216,186), state = "active"},
    node_dark = {mesh = "node_dark", radius = 11, color = Color(178,139,228), state = "active"},
    shot_shell = {mesh = "shot_shell", color = Color(242,148,78)},
    shot_cluster = {mesh = "shot_cluster", color = Color(237,170,102)},
    shot_homing = {mesh = "shot_homing", color = Color(233,165,97)},
    shot_mega = {mesh = "shot_mega", color = Color(249,126,82)},
    shot_shard = {mesh = "shot_shard", color = Color(242,173,89)},
    shot_arcpulse = {mesh = "shot_arcpulse", color = Color(120,222,229)},
    shot_ion = {mesh = "shot_ion", color = Color(121,211,210)},
    supply = {mesh = "supply", radius = 15, color = Color(207,176,108)},
    salvage_ballast = {mesh = "salvage_ballast", radius = 12, color = Color(162,113,73)},
}

A.ToolVisual = {mesh = "tool_deployer", family = "field", ports = {{13,0,0}}}
A.MechVisual = {mesh = "mech_receiver", family = "pulse", ports = {{20,0,0}}}

function A.NativeModel(mesh)
    return "models/drmd/" .. mesh .. ".mdl"
end

function A.Visual(class)
    local item = A.Entries[class]
    if item then return item end
    if class == "weapon_d6_deployer" or class:find("^weapon_d6_spawn_") then return A.ToolVisual end
    if class == "weapon_combine_mech_drone" then return A.MechVisual end
end

function A.Port(origin, ang, item, index, offset)
    local sockets = item.ports
    if not sockets or #sockets == 0 then return origin end
    if not index and offset then
        local right, up = offset.rgt or 0, offset.up or 0
        local best = math.huge
        for i, point in ipairs(sockets) do
            local dist = (right+point[2])^2 + (up-point[3])^2
            if dist < best then index, best = i, dist end
        end
    end
    local tip = sockets[((index or 1)-1)%#sockets+1]
    return origin + ang:Forward()*tip[1] - ang:Right()*tip[2] + ang:Up()*tip[3]
end

A.Order = {}
A.Entries = {}
local function weapon(suffix, name, family, ammo, charge)
    local class = "weapon_d6_" .. suffix
    local model = A.Models[suffix]
    local item = {class = class, name = name, family = family, ammo = ammo, charge = charge,
        mesh = model.mesh, ports = model.ports}
    A.Entries[class] = item
    A.Order[#A.Order + 1] = item
end

weapon("mg", "Пульсар", "pulse")
weapon("vulcan", "Вулкан", "pulse")
weapon("flak", "Флак", "pulse")
weapon("plasma", "Плазменный излучатель", "arc")
weapon("laser", "Импульсный лазер", "arc", nil, "D6_LaserCharge")
weapon("quad_laser", "Квадролазер", "arc")
weapon("overdrive", "Овердрайв", "arc")
weapon("heavy", "Штурмовая мортира", "rack")
weapon("rockets", "Ракетный блок", "rack")
weapon("concussion", "Ударная ракета", "rack", "d6_concussion")
weapon("homing", "Ракета с ГСН", "rack", "d6_homing")
weapon("smart_missile", "Кассетная ракета", "rack", "d6_smart")
weapon("mega_missile", "Мега-ракета", "rack", "d6_mega")
weapon("frag", "Осколочный заряд", "rack")
weapon("gravy_railgun", "Гравирельс", "rail")
weapon("railmk2", "Рельсотрон Mk II", "rail", nil, "D6_RailCharge")
weapon("darklance", "Тёмное копьё", "rail", nil, "D6_LanceCharge")
weapon("bfg", "Ионный реактор", "field")
weapon("shockwave", "Ударная волна", "field")
weapon("energytrap", "Энергокапкан", "field")
weapon("darkfield", "Тёмное поле", "field")
weapon("telefrag", "Телефраг", "field")
weapon("whiplash", "Луч сцепления", "field")
weapon("warp", "Боевой варп", "field")
weapon("reactor", "Сброс реактора", "field")
weapon("phasegate", "Фазовая пушка", "field")
weapon("hyperbeam", "Гиперлуч", "optic", nil, "D6_HyperCharge")
weapon("plasmamine", "Плазменная мина", "mine")
weapon("gravmine", "Гравитационная мина", "mine")

-- The playable catalogue is deliberately smaller than the compatibility registry.
-- Retired definitions remain addressable while existing saves/map rewards migrate;
-- they are not additional choices in the hangar or the automatic loadout.
A.LegacyOrder = A.Order
A.Order = {}
A.Playable = {}
A.Replacements = {
    vulcan="mg", laser="plasma", quad_laser="plasma", overdrive="plasma",
    concussion="rockets", homing="rockets", smart_missile="rockets", mega_missile="rockets",
    frag="heavy", darklance="railmk2", hyperbeam="plasma",
    energytrap="gravmine", darkfield="gravmine", shockwave="bfg", reactor="bfg",
    telefrag="phasegate", warp="whiplash",
}
local selected = {"mg", "flak", "plasma", "heavy", "rockets", "gravy_railgun", "railmk2",
    "bfg", "whiplash", "phasegate", "plasmamine", "gravmine"}
for _, suffix in ipairs(selected) do
    local class = "weapon_d6_" .. suffix
    A.Playable[class] = true
    A.Order[#A.Order + 1] = A.Entries[class]
end

function A.ResolveClass(class)
    if type(class) ~= "string" then return nil end
    if A.Playable[class] then return class end
    local suffix = class:match("^weapon_d6_(.+)$")
    return suffix and A.Replacements[suffix] and ("weapon_d6_" .. A.Replacements[suffix]) or nil
end

-- Starting values for the first playable pass, not measured final balance.
-- Capacity describes trigger cycles, not individual pellets in a volley.
A.Operating = {
    weapon_d6_mg = {tier=1, kind="continuous", energy=0},
    weapon_d6_flak = {tier=2, kind="magazine", capacity=2, reload=1.8},
    weapon_d6_plasma = {tier=2, kind="capacitor", capacity=6, reload=1.7},
    weapon_d6_heavy = {tier=2, kind="ordnance", capacity=2, reload=2.4,
        ammo="d6_shell", maxAmmo=12, initialAmmo=4, pickup=4},
    weapon_d6_rockets = {tier=2, kind="ordnance", capacity=3, reload=2.0,
        ammo="d6_rocket", maxAmmo=12, initialAmmo=4, pickup=4},
    weapon_d6_gravy_railgun = {tier=2, kind="physical"},
    weapon_d6_railmk2 = {tier=3, kind="charge", capacity=1, reload=1.5,
        ammo="d6_rail_cell", maxAmmo=8, initialAmmo=3, pickup=2},
    weapon_d6_bfg = {tier=3, kind="rare", capacity=1, reload=10,
        ammo="d6_bfg_cell", maxAmmo=2, initialAmmo=1, pickup=0},
    weapon_d6_whiplash = {tier=2, kind="utility"},
    weapon_d6_phasegate = {tier=2, kind="utility"},
    weapon_d6_plasmamine = {tier=2, kind="mine", ammo="d6_mine", maxAmmo=6, initialAmmo=2, pickup=2},
    weapon_d6_gravmine = {tier=2, kind="mine", ammo="d6_mine", maxAmmo=6, initialAmmo=2, pickup=2},
}
for class, policy in pairs(A.Operating) do
    A.Entries[class].ammo = policy.ammo
end
A.Starting = {weapon_d6_mg=true, weapon_d6_plasma=true, weapon_d6_heavy=true,
    weapon_d6_gravy_railgun=true, weapon_d6_plasmamine=true}
-- Old episode caches used Hyperbeam as a late powerful reward. A saved mount
-- resolves to plasma, but that pickup must not become a duplicate starter gun.
A.RewardAliases = {weapon_d6_hyperbeam="weapon_d6_bfg"}
A.RewardWave = {
    weapon_d6_flak=1, weapon_d6_rockets=1, weapon_d6_whiplash=1,
    weapon_d6_phasegate=2, weapon_d6_gravmine=2,
    weapon_d6_railmk2=3, weapon_d6_bfg=3,
}

function A.ResolveRewardClass(class)
    return A.RewardAliases[class] or A.ResolveClass(class)
end

function A.AvailableRewards(ply, wave)
    local choices = {}
    for _, item in ipairs(A.Order) do
        local required = A.RewardWave[item.class]
        if required and wave >= required and not ply:HasWeapon(item.class) then
            choices[#choices+1] = item.class
        end
    end
    return choices
end

-- x forward, y right, z up. Both the renderer and shot origins use these positions.
A.Mounts = {
    {label = "Левое крыло", pos = { 5, -24, -3}},
    {label = "Правое крыло", pos = { 5, 24, -3}},
    {label = "Верхний узел", pos = {-7, -13, 26}},
    {label = "Нижний узел", pos = { 4, 15, -20}},
    {label = "Минный отсек", pos = {-11, 0, -29}},
}

A.Defaults = {
    "weapon_d6_mg", "weapon_d6_plasma", "weapon_d6_heavy",
    "weapon_d6_gravy_railgun", "weapon_d6_plasmamine",
}

function A.CanMount(class)
    local item = A.Entries[class]
    return A.Playable[class] == true and item ~= nil and item.family ~= "mine"
end

function A.CanMine(class)
    return A.Playable[class] == true and A.Entries[class].family == "mine"
end

function A.Normalize(saved)
    local slots, used = {}, {}
    if type(saved) ~= "table" then saved = {} end
    for i = 1, 4 do
        local chosen = A.ResolveClass(saved[i])
        if type(chosen) == "string" and A.CanMount(chosen) and not used[chosen] then
            slots[i], used[chosen] = chosen, true
        end
    end
    for i = 1, 4 do
        if not slots[i] then
            for j = 0, 3 do
                local fallback = A.Defaults[(i + j - 1) % 4 + 1]
                if not used[fallback] then
                    slots[i], used[fallback] = fallback, true
                    break
                end
            end
        end
    end
    local mine = A.ResolveClass(saved[5])
    slots[5] = A.CanMine(mine) and mine or A.Defaults[5]
    return slots
end

function A.Assign(slots, index, class)
    if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > 4 or not A.CanMount(class) then
        return false
    end
    for i = 1, 4 do
        if slots[i] == class then
            slots[i] = slots[index]
            break
        end
    end
    slots[index] = class
    return true
end

function A.AssignMine(slots, class)
    if not A.CanMine(class) then return false end
    slots[5] = class
    return true
end

function A.Get(ply, index)
    return ply:GetNW2String("D6_Mount" .. index, A.Defaults[index])
end

function A.Slot(ply, class)
    if A.CanMine(class) then return A.Get(ply, 5) == class and 5 or nil end
    for i = 1, 4 do
        if A.Get(ply, i) == class then return i end
    end
end

function A.MountOrigin(origin, ang, index)
    local offset = A.Mounts[index].pos
    return origin + ang:Forward() * offset[1] + ang:Right() * offset[2] + ang:Up() * offset[3]
end

function A.Anchor(ply)
    return ply:WorldSpaceCenter()
end

-- The neutral eyes attachment transformed into the scanner's corrected flight basis.
function A.ScannerEye(ply, aim, center)
    local eye = A.Scanner.eye
    return (center or A.Anchor(ply)) + A.Scanner.scale * (aim:Forward()*eye[1]
        + aim:Right()*eye[2] + aim:Up()*eye[3])
end

function A.EyeClearance(ply, aim, mask)
    local center = A.Anchor(ply)
    local eye = A.ScannerEye(ply, aim, center)
    return eye, util.TraceLine({start = center, endpos = eye, filter = ply, mask = mask})
end

if SERVER then
    local storageKey = "drmd_arsenal_mounts_v1"
    local function publish(ply, slots)
        for i = 1, #A.Mounts do ply:SetNW2String("D6_Mount" .. i, slots[i]) end
    end
    A.Publish = publish

    function A.EnsureOwned(ply)
        local slots = A.Normalize(ply.D6_Mounts)
        local used = {}
        for i = 1, 4 do
            if not IsValid(ply:GetWeapon(slots[i])) then slots[i] = false
            else used[slots[i]] = true end
        end
        for i = 1, 4 do
            if not slots[i] then
                for j = 0, 3 do
                    local class = A.Defaults[(i+j-1)%4+1]
                    if not used[class] and IsValid(ply:GetWeapon(class)) then
                        slots[i], used[class] = class, true
                        break
                    end
                end
                slots[i] = slots[i] or A.Defaults[i]
            end
        end
        if not IsValid(ply:GetWeapon(slots[5])) then slots[5] = A.Defaults[5] end
        ply.D6_Mounts = slots
        publish(ply, slots)
    end

    hook.Add("PlayerInitialSpawn", "D6_ArsenalLoad", function(ply)
        local stored = not ply:IsBot() and ply:GetPData(storageKey)
        ply.D6_Mounts = A.Normalize(stored and util.JSONToTable(stored))
        publish(ply, ply.D6_Mounts)
    end)

    concommand.Add("d6_mount_set", function(ply, _, args)
        if not IsValid(ply) or not D6_Session.IsArena() then return end
        local slot, class = tonumber(args[1]), args[2]
        if not class or not A.CanMount(class) or not IsValid(ply:GetWeapon(class)) then return end
        local slots = ply.D6_Mounts or A.Normalize()
        if not A.Assign(slots, slot, class) then return end
        ply.D6_Mounts = slots
        if not ply:IsBot() then ply:SetPData(storageKey, util.TableToJSON(slots)) end
        publish(ply, slots)
    end)

    concommand.Add("d6_mine_set", function(ply, _, args)
        if not IsValid(ply) or not D6_Session.IsArena() then return end
        local class = args[1]
        if not class or not A.CanMine(class) or not IsValid(ply:GetWeapon(class)) then return end
        local slots = ply.D6_Mounts or A.Normalize()
        if not A.AssignMine(slots, class) then return end
        ply.D6_Mounts = slots
        if not ply:IsBot() then ply:SetPData(storageKey, util.TableToJSON(slots)) end
        publish(ply, slots)
    end)

    concommand.Add("d6_mount_select", function(ply, _, args)
        if not IsValid(ply) or not ply:Alive() or not ply.D6On then return end
        local index = tonumber(args[1])
        if not index or index % 1 ~= 0 or index < 1 or index > 4 then return end
        local class = A.Get(ply, index)
        if IsValid(ply:GetWeapon(class)) then ply:SelectWeapon(class) end
    end)
end

if CLIENT then
    hook.Add("PlayerBindPress", "D6_SelectMount", function(ply, bind, pressed)
        if not pressed or not ply:Alive() or not ply:GetNWBool("D6On") then return end
        if bind == "slot5" then return true end
        local index = tonumber(bind:match("^slot([1-4])$"))
        if index then
            local wep = ply:GetWeapon(A.Get(ply, index))
            if IsValid(wep) then input.SelectWeapon(wep) end
            return true
        end
        if bind ~= "invnext" and bind ~= "invprev" then return end
        local active = ply:GetActiveWeapon()
        local direction = bind == "invnext" and 1 or -1
        local start = IsValid(active) and A.Slot(ply, active:GetClass()) or (direction == 1 and 0 or 1)
        for step = 1, 4 do
            local slot = (start - 1 + step * direction) % 4 + 1
            local wep = ply:GetWeapon(A.Get(ply, slot))
            if IsValid(wep) then
                input.SelectWeapon(wep)
                return true
            end
        end
    end)
end
