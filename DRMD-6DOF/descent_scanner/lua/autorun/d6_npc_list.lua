-- Keep the catalogue in both realms; the NPC tab uses a dedicated content type
-- because Abaddon variants are factories, not engine entity class names.
if SERVER then AddCSLuaFile() end
local menuEntries = {}
do

    local function RegNPC(key, name, class, model, category)
        list.Set("NPC", key, {
            Name      = name,
            Class     = key,
            Category  = category or "Half-Life: Abaddon",
            Model     = model,
            Weapons   = {},
            KeyValues = {},
            NPC       = true,
            AdminOnly = true,
            ScriptedEntityType = "d6_npc",
            IconOverride = "icon16/monkey.png",
        })
        menuEntries[key] = {name=name, id=key:sub(8)}
    end

    RegNPC("d6_npc_mine",   "D6: Воздушная мина",    "npc_cscanner",
        "models/props_combine/combine_mine01.mdl",  "Half-Life: Abaddon / Дроны")

    RegNPC("d6_npc_mg",     "D6: Пулемётный сканер", "npc_cscanner",
        "models/combine_scanner.mdl",               "Half-Life: Abaddon / Дроны")

    RegNPC("d6_npc_rpg",    "D6: РПГ-сканер",        "npc_cscanner",
        "models/combine_scanner.mdl",               "Half-Life: Abaddon / Дроны")

    RegNPC("d6_npc_grav",   "D6: Грави-мастер",      "npc_cscanner",
        "models/combine_scanner.mdl",               "Half-Life: Abaddon / Дроны")

    RegNPC("d6_npc_laser",  "D6: Лазерный сканер",   "npc_cscanner",
        "models/combine_scanner.mdl",               "Half-Life: Abaddon / Дроны")

    RegNPC("d6_npc_heavy",  "D6: Тяжёлый сканер",    "npc_cscanner",
        "models/combine_scanner.mdl",               "Half-Life: Abaddon / Дроны")

    RegNPC("d6_npc_seeker", "D6: Ракетный сикер",    "npc_cscanner",
        "models/combine_scanner.mdl",               "Half-Life: Abaddon / Дроны")

    RegNPC("d6_npc_worm",      "D6: Альянсский червь",    "npc_headcrab",
        "models/headcrab.mdl",                      "Half-Life: Abaddon / Бестиарий")

    RegNPC("d6_npc_manhack",   "D6: Манхок-камикадзе",   "npc_manhack",
        "models/manhack.mdl",                       "Half-Life: Abaddon / Бестиарий")

    RegNPC("d6_npc_squad",     "D6: Боевой отряд (все)", "npc_cscanner",
        "models/combine_scanner.mdl",               "Half-Life: Abaddon / Группы")

    RegNPC("d6_npc_bestiary",  "D6: Весь бестиарий",     "npc_headcrab",
        "models/headcrab.mdl",                      "Half-Life: Abaddon / Группы")

    -- Wave 2
    RegNPC("d6_npc_rocket_elite_homing", "D6: Ракетная элита (самонаведение)", "npc_cscanner",
        "models/combine_scanner.mdl",               "Half-Life: Abaddon / Волна 2")

    RegNPC("d6_npc_rocket_elite_aa", "D6: Ракетная элита (зенитная)", "npc_cscanner",
        "models/combine_scanner.mdl",               "Half-Life: Abaddon / Волна 2")

    RegNPC("d6_npc_rocket_strider", "D6: Ракетный страйдер", "npc_cscanner",
        "models/combine_scanner.mdl",               "Half-Life: Abaddon / Волна 2")

    RegNPC("d6_npc_plasma_strider", "D6: Плазменный страйдер", "npc_cscanner",
        "models/combine_scanner.mdl",               "Half-Life: Abaddon / Волна 2")

    RegNPC("d6_npc_wave2",  "D6: Волна 2 (все элиты)", "npc_cscanner",
        "models/combine_scanner.mdl",               "Half-Life: Abaddon / Волна 2")

    -- Role variants
    RegNPC("d6_npc_assault",     "D6: Штурмовик",         "npc_cscanner",
        "models/combine_scanner.mdl",               "Half-Life: Abaddon / Роли")

    RegNPC("d6_npc_interceptor", "D6: Перехватчик",       "npc_cscanner",
        "models/combine_scanner.mdl",               "Half-Life: Abaddon / Роли")

    RegNPC("d6_npc_artillery",   "D6: Артиллерия",        "npc_cscanner",
        "models/combine_scanner.mdl",               "Half-Life: Abaddon / Роли")

    RegNPC("d6_npc_support",     "D6: Саппорт",           "npc_cscanner",
        "models/combine_scanner.mdl",               "Half-Life: Abaddon / Роли")

    RegNPC("d6_npc_heavy_elite", "D6: Тяжёлая элита",     "npc_cscanner",
        "models/combine_scanner.mdl",               "Half-Life: Abaddon / Роли")

    RegNPC("d6_npc_arc_elite", "Сверхтяжёлый дуговой штурмовик", "npc_cscanner",
        "models/drmd/combine_arc_elite.mdl", "Half-Life: Abaddon / Роли")
    RegNPC("d6_npc_wheatley", "Подрывной дрон", "npc_cscanner",
        "models/drmd/cutting_probe.mdl", "Half-Life: Abaddon / Бестиарий")
    RegNPC("d6_npc_chopper", "Летающая огневая платформа", "npc_cscanner",
        "models/drmd/combine_gunship.mdl", "Half-Life: Abaddon / Бестиарий")

    for role, name in pairs(D6_Session.Resistance) do
        RegNPC("d6_npc_" .. role, name, "npc_cscanner", "models/combine_scanner.mdl", "Half-Life: Abaddon / Сопротивление")
    end

end

local groups = {
    squad = {radius=120, up=40, members={"heavy","mg","mg","rpg","laser","mine"}},
    bestiary = {radius=200, up=50, members={"worm","wheatley","chopper","manhack","seeker"}},
    wave2 = {radius=300, up=60, members={"rocket_elite_homing","rocket_elite_aa","rocket_strider","plasma_strider"}},
}

if CLIENT then
    spawnmenu.AddContentType("d6_npc", function(container, object)
        local entry = object and menuEntries[object.spawnname]
        if not entry then return end
        -- Reuse GMod's icon, tooltip, dragging, search and category behaviour.
        local icon = spawnmenu.CreateContentIcon("npc", container, object)
        if not IsValid(icon) then return end
        icon:SetContentType("d6_npc")
        icon.DoClick = function()
            RunConsoleCommand("d6_spawn_unit", entry.id)
            surface.PlaySound("ui/buttonclickrelease.wav")
        end
        -- The native creator tool expects an actual engine class, not a factory alias.
        icon.OpenMenuExtra = function(_, menu)
            menu:AddOption("Вызвать юнита", icon.DoClick):SetIcon("icon16/add.png")
        end
        local variant = groups[entry.id] and groups[entry.id].members[1] or entry.id
        if variant == "manhack" then variant = "manhack_fast" end
        local art = D6_Drones and D6_Drones.Types[variant]
        local preview = art and {kind="npc", key=variant, mesh=art.mesh, color=art.color}
        local previousPaint = icon.PaintOver
        icon.PaintOver = function(self, width, height)
            if preview and D6_SpawnPreview and D6_SpawnPreview.Draw then
                D6_SpawnPreview.Draw(preview, 4, 4, width-8, height-30)
            end
            if previousPaint then previousPaint(self, width, height) end
        end
        return icon
    end)
    return
end

-- The old hook spawned as a side effect and returned false. Sandbox consequently
-- displayed a failure even on success. Only the explicit command now creates units.
hook.Remove("PlayerSpawnNPC", "D6_NPCTab_Spawner")

local basic = {mine=true, mg=true, rpg=true, grav=true, laser=true, heavy=true}
local roles = {assault=true, interceptor=true, artillery=true, support=true, heavy_elite=true, arc_elite=true}
for role in pairs(D6_Session.Resistance) do roles[role] = true end
local factories = {
    seeker="SpawnHeavySeeker", worm="SpawnWorm", manhack="SpawnManhackKamikaze",
    wheatley="SpawnWheatley", chopper="SpawnChopper",
    rocket_elite_homing="SpawnRocketEliteHoming", rocket_elite_aa="SpawnRocketEliteAA",
    rocket_strider="SpawnRocketStrider", plasma_strider="SpawnPlasmaStrider",
}

local function spawnPosition(variant, trace)
    local distance = 50
    local loadout = roles[variant] and D6_GetRoleLoadout and D6_GetRoleLoadout(variant)
    local hull = loadout and loadout.hull
    if hull then
        local normal = trace.HitNormal
        distance = (math.abs(normal.x)+math.abs(normal.y))*hull.radius
            + math.max(normal.z,0)*hull.below + math.max(-normal.z,0)*hull.above + 15
    end
    return trace.HitPos + trace.HitNormal*distance
end

local function spawnUnit(ply, variant, position)
    if basic[variant] and SpawnEnemyDrone then
        return SpawnEnemyDrone(ply, "npc_cscanner", variant, position)
    end
    if roles[variant] and SpawnD6Role then return SpawnD6Role(variant, position, ply) end
    local factory = factories[variant] and _G[factories[variant]]
    if factory then return factory(ply, position) end
end

concommand.Add("d6_spawn_unit", function(ply, _, args)
    if not IsValid(ply) or not ply:Alive() then return end
    if not D6_Session.IsArena() or not D6_Session.CanEditWorld(ply) then
        ply:PrintMessage(HUD_PRINTTALK, "[Abaddon] Прямой вызов доступен владельцу или администратору в режиме арены.")
        return
    end
    local variant = tostring(args[1] or ""):gsub("^d6_npc_", "")
    if variant == "manhack_fast" then variant = "manhack" end
    local entry = menuEntries["d6_npc_"..variant]
    if not entry then return end
    if CurTime() < (ply.D6_NPCMenuReady or 0) then return end
    local trace = ply:GetEyeTrace()
    if not trace.Hit or trace.HitSky then
        ply:PrintMessage(HUD_PRINTTALK, "[Abaddon] Укажите поверхность для появления юнита.")
        return
    end
    ply.D6_NPCMenuReady = CurTime()+0.35
    local group = groups[variant]
    local members = group and group.members or {variant}
    local spawned = {}
    for index, kind in ipairs(members) do
        if not ply:CheckLimit("npcs") then break end
        -- Ask normal Sandbox/third-party policy before creating each actual body.
        if gamemode.Call("PlayerSpawnNPC", ply, "d6_npc_"..kind, "") == false then break end
        local position = spawnPosition(kind, trace)
        if group then
            local angle = ((index-1)/#members)*math.pi*2
            position = trace.HitPos+trace.HitNormal*80
                + Vector(math.sin(angle)*group.radius, math.cos(angle)*group.radius, group.up)
        end
        local ok, entity = pcall(spawnUnit, ply, kind, position)
        if not ok then
            ErrorNoHalt("[Abaddon] Unit spawn failed: "..kind..": "..tostring(entity).."\n")
        elseif IsValid(entity) then
            entity:SetCreator(ply)
            gamemode.Call("PlayerSpawnedNPC", ply, entity)
            ply:AddCleanup("npcs", entity)
            spawned[#spawned+1] = entity
        end
    end
    if #spawned == 0 then
        ply:PrintMessage(HUD_PRINTTALK, "[Abaddon] Юнит не появился: проверьте свободное место и лимит NPC.")
        return
    end
    undo.Create("Abaddon NPC")
    for _, entity in ipairs(spawned) do undo.AddEntity(entity) end
    undo.SetPlayer(ply)
    undo.Finish("Abaddon: "..entry.name)
end)
