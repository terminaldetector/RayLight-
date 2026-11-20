-- =========================================================
-- d6_autoload.lua — Автозагрузка мода Descent 6DOF
-- =========================================================

local sharedFiles = {"d6_actors.lua", "d6_session.lua", "d6_arsenal.lua", "d6_combat_balance.lua", "d6_drone_catalog.lua", "d6_reactor_hazards.lua", "d6_reactor.lua", "d6_supplies.lua", "d6_campaign.lua", "d6_mission.lua", "d6_gates.lua"}
local clientFiles = {"d6_art_geometry.lua", "d6_art_models.lua", "d6_art_elites.lua", "d6_art_ordnance.lua", "d6_view_mounts.lua", "d6_art_render.lua", "d6_reactor_visual.lua", "d6_interface.lua", "d6_hangar.lua", "d6_bestiary.lua"}

for _, path in ipairs(sharedFiles) do
    if SERVER then AddCSLuaFile(path) end
    include(path)
end
if SERVER then
    for _, path in ipairs(clientFiles) do AddCSLuaFile(path) end
    for _, material in ipairs(file.Find("materials/models/drmd/*.vmt", "GAME")) do
        resource.AddFile("materials/models/drmd/" .. material)
    end
    for _, model in ipairs(file.Find("models/drmd/*.mdl", "GAME")) do
        resource.AddFile("models/drmd/" .. model)
    end
    for _, texture in ipairs(file.Find("materials/drmd/drmd_finish_*.vtf", "GAME")) do
        resource.AddFile("materials/drmd/" .. texture)
    end
end

if SERVER then
    for _, weapon in ipairs(D6_Arsenal.Order) do AddCSLuaFile("weapons/" .. weapon.class .. ".lua") end
    AddCSLuaFile("d6_core.lua")
    AddCSLuaFile("d6_weapon_core.lua")  -- единый фреймворк оружия (Phase B)
    AddCSLuaFile("d6_client.lua")
    AddCSLuaFile("d6_wepview.lua")   -- DOOM-стиль рендер оружий
    AddCSLuaFile("d6_menu.lua")
    AddCSLuaFile("d6_ang_patch.lua")
    AddCSLuaFile("d6_weapon_registry.lua")
    AddCSLuaFile("d6_nav.lua")       -- nav graph debug overlay
    AddCSLuaFile("d6_energy.lua")    -- энергорезерв (Stage 6)
    AddCSLuaFile("d6_weapon_feed.lua")
    AddCSLuaFile("d6_aux_mines.lua")
    AddCSLuaFile("d6_shield.lua")    -- щиты/урон (Stage 7)
    AddCSLuaFile("d6_rearview.lua")  -- вид сзади (Descent-стиль)
end

local function TryInclude(path)
    if file.Exists("lua/" .. path, "GAME") then
        include(path)
    else
        MsgC(Color(255,100,0), "[D6] Не найден: " .. path .. "\n")
    end
end

if SERVER then
    TryInclude("d6_core.lua")
    TryInclude("d6_energy.lua")      -- Stage 6: до оружий/щитов/модулей
    TryInclude("d6_weapon_feed.lua")
    TryInclude("d6_weapon_core.lua")
    TryInclude("d6_aux_mines.lua")
    TryInclude("d6_loadout.lua")
    TryInclude("d6_swarm.lua")
    TryInclude("d6_gravity.lua")
    TryInclude("d6_ai.lua")
    TryInclude("d6_frags.lua")        -- экспортирует глобальный D6_Explode
    TryInclude("d6_patterns.lua")
    TryInclude("d6_frags2.lua")      -- волна 2: ракетные элиты + страйдеры
    TryInclude("d6_shield.lua")      -- Stage 7: после frags (нужен D6_Explode) и energy
    TryInclude("d6_ang_patch.lua")
    TryInclude("d6_weapon_registry.lua")
    TryInclude("d6_nav.lua")
    TryInclude("d6_modules.lua")     -- Stage 8: регистрирует модули + диспетчер
    TryInclude("d6_ai_roles.lua")    -- тонкий: LOADOUTS + SpawnD6Role-обёртка
    TryInclude("d6_encounter.lua")
    TryInclude("d6_trial.lua")
    TryInclude("d6_reactor_boss.lua")
    AddCSLuaFile("d6_rogue.lua")
    TryInclude("d6_rogue.lua")
    -- Меню — только клиент, но включаем чтобы сработал SERVER-раздел в других файлах
end

if CLIENT then
    include("d6_core.lua")
    include("d6_energy.lua")
    include("d6_weapon_feed.lua")
    include("d6_weapon_core.lua")    -- Phase B: фреймворк оружия (HUD-хелперы, таксономия)
    include("d6_aux_mines.lua")
    include("d6_client.lua")
    include("d6_wepview.lua")        -- рендер оружий от 1-го лица
    include("d6_menu.lua")
    include("d6_ang_patch.lua")
    include("d6_weapon_registry.lua")
    include("d6_nav.lua")            -- nav graph client debug
    include("d6_shield.lua")         -- щиты (геттеры для cockpit)
    include("d6_rearview.lua")
    for _, path in ipairs(clientFiles) do include(path) end
    include("d6_rogue.lua")
end

-- Only the curated catalogue participates in normal equipment selection.
if D6_RegisterWeapon then
    for _, item in ipairs(D6_Arsenal.Order) do
        D6_RegisterWeapon(item.class, {category = D6_Arsenal.Families[item.family].label, autoGive = false})
    end
end

-- Source requires identical ammo registration in Initialize on both realms.
hook.Add("Initialize", "D6_RegisterAmmo", function()
    for _, legacy in ipairs({{"d6_concussion",6},{"d6_homing",8},{"d6_smart",4},{"d6_mega",2}}) do
        game.AddAmmoType({name=legacy[1], dmgtype=DMG_BLAST, maxcarry=legacy[2]})
    end
    local registered = {}
    for _, item in ipairs(D6_Arsenal.Order) do
        local policy = D6_Arsenal.Operating[item.class]
        if policy.ammo and not registered[policy.ammo] then
            game.AddAmmoType({name=policy.ammo, dmgtype=DMG_GENERIC, maxcarry=policy.maxAmmo})
            registered[policy.ammo] = true
        end
    end
end)

if SERVER then
    concommand.Add("d6_give_weapons", function(ply)
        if not D6_Session.IsArena() or not D6_Session.CanEditWorld(ply) then return end
        local count = D6_Session.GiveLoadout(ply,true)
        ply:PrintMessage(HUD_PRINTTALK, "[Abaddon] Выдано систем: " .. count)
    end)

    concommand.Add("d6_weapon_next", function(ply)
        if not IsValid(ply) or not ply.D6On then return end
        local active = ply:GetActiveWeapon()
        local slot = IsValid(active) and D6_Arsenal.Slot(ply, active:GetClass()) or 0
        for step = 1, 4 do
            local class = D6_Arsenal.Get(ply, (slot + step - 1) % 4 + 1)
            if IsValid(ply:GetWeapon(class)) then ply:SelectWeapon(class); return end
        end
    end)
end
