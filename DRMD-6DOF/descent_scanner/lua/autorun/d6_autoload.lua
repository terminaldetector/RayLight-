-- =========================================================
-- d6_autoload.lua — Автозагрузка мода Descent 6DOF
-- =========================================================

local sharedFiles = {"d6_session.lua", "d6_arsenal.lua", "d6_drone_catalog.lua", "d6_campaign.lua", "d6_mission.lua", "d6_gates.lua"}
local clientFiles = {"d6_art_geometry.lua", "d6_art_models.lua", "d6_art_ordnance.lua", "d6_art_render.lua", "d6_interface.lua", "d6_hangar.lua", "d6_bestiary.lua"}

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
    TryInclude("d6_weapon_core.lua") -- Phase B: фреймворк оружия (после core, до оружий)
    TryInclude("d6_energy.lua")      -- Stage 6: до оружий/щитов/модулей
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
    AddCSLuaFile("d6_rogue.lua")
    TryInclude("d6_rogue.lua")
    -- Меню — только клиент, но включаем чтобы сработал SERVER-раздел в других файлах
end

if CLIENT then
    include("d6_core.lua")
    include("d6_weapon_core.lua")    -- Phase B: фреймворк оружия (HUD-хелперы, таксономия)
    include("d6_client.lua")
    include("d6_wepview.lua")        -- рендер оружий от 1-го лица
    include("d6_menu.lua")
    include("d6_ang_patch.lua")
    include("d6_weapon_registry.lua")
    include("d6_nav.lua")            -- nav graph client debug
    include("d6_energy.lua")         -- энергорезерв (геттеры для HUD/меню)
    include("d6_shield.lua")         -- щиты (геттеры для cockpit)
    include("d6_rearview.lua")
    for _, path in ipairs(clientFiles) do include(path) end
    include("d6_rogue.lua")
end

-- ── Реестр: категории оружий Descent (Waves D–G) ─────────
-- Регистрируем явные категории ДО авто-детекта (InitPostEntity),
-- чтобы реестр/TAB-меню показывали правильные группы, а не
-- «Auto-detected». autoGive=false — выдача идёт через D6_COMBAT.
if D6_RegisterWeapon then
    local function reg(class, cat) D6_RegisterWeapon(class, { category = cat, autoGive = false }) end
    -- Cat D — Anti-Swarm
    reg("weapon_d6_bfg",        "Anti-Swarm")
    reg("weapon_d6_flak",       "Anti-Swarm")
    reg("weapon_d6_frag",       "Anti-Swarm")
    reg("weapon_d6_shockwave",  "Anti-Swarm")
    -- Cat E — Area Control
    reg("weapon_d6_plasmamine", "Area Control")
    reg("weapon_d6_gravmine",   "Area Control")
    reg("weapon_d6_energytrap", "Area Control")
    reg("weapon_d6_darkfield",  "Area Control")
    -- Cat F — Mobility
    reg("weapon_d6_telefrag",   "Mobility")
    reg("weapon_d6_whiplash",   "Mobility")
    reg("weapon_d6_warp",       "Mobility")
    -- Cat G — Ultimate
    reg("weapon_d6_overdrive",  "Ultimate")
    reg("weapon_d6_reactor",    "Ultimate")
    reg("weapon_d6_darklance",  "Ultimate")
    reg("weapon_d6_hyperbeam",  "Ultimate")
end

-- =========================================================
-- СЕРВЕР: авто-выдача оружий
-- =========================================================
if SERVER then

    -- Cat B: limited-ammo secondary weapons
    game.AddAmmoType({ name = "d6_concussion", dmgtype = DMG_BLAST, maxcarry = 6  })
    game.AddAmmoType({ name = "d6_homing",     dmgtype = DMG_BLAST, maxcarry = 8  })
    game.AddAmmoType({ name = "d6_smart",      dmgtype = DMG_BLAST, maxcarry = 4  })
    game.AddAmmoType({ name = "d6_mega",       dmgtype = DMG_BLAST, maxcarry = 2  })

    local function giveLoadout(ply)
        local count = 0
        for _, item in ipairs(D6_Arsenal.Order) do
            if not IsValid(ply:GetWeapon(item.class)) and IsValid(ply:Give(item.class, true)) then
                count = count + 1
            end
        end
        for class, data in pairs(D6_Weapons or {}) do
            if data.autoGive and not IsValid(ply:GetWeapon(class)) then
                if IsValid(ply:Give(class, true)) then
                    for ammoType, amount in pairs(data.ammoOnGive) do ply:GiveAmmo(amount, ammoType, true) end
                    count = count + 1
                end
            end
        end
        ply:GiveAmmo(4, "d6_concussion", true)
        ply:GiveAmmo(6, "d6_homing", true)
        ply:GiveAmmo(2, "d6_smart", true)
        ply:GiveAmmo(1, "d6_mega", true)
        return count
    end
    D6_Session.GiveLoadout = giveLoadout

    concommand.Add("d6_give_weapons", function(ply)
        if not D6_Session.IsArena() or not D6_Session.CanEditWorld(ply) then return end
        local count = giveLoadout(ply)
        ply:PrintMessage(HUD_PRINTTALK, "[Abaddon] Выдано систем: " .. count)
    end)

    concommand.Add("d6_weapon_next", function(ply)
        if not IsValid(ply) or not ply.D6On then return end
        local active = ply:GetActiveWeapon()
        local slot = IsValid(active) and D6_Arsenal.Slot(ply, active:GetClass()) or 0
        for step = 1, #D6_Arsenal.Mounts do
            local class = D6_Arsenal.Get(ply, (slot + step - 1) % #D6_Arsenal.Mounts + 1)
            if IsValid(ply:GetWeapon(class)) then ply:SelectWeapon(class); return end
        end
    end)
end
