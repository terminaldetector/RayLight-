D6_Session = {}
D6_Session.Enforcer = {scale = 4.2, radius = 132, below = 147, above = 122}
D6_Session.ArcElite = {scale = 2.35, radius = 94, below = 68, above = 61,
    parts = {
        {{-24,-18,-12},{27,18,17}},
        {{-13,-34,-6},{36,-16,9}},
        {{-13,16,-6},{36,34,9}},
        {{-21,-8,15},{8,8,26}},
        {{-12,-11,-28},{16,11,-11}},
    },
}
D6_Session.Resistance = {
    resistance_scout = "Самодельный планер",
    resistance_raider = "Бочкарь",
    resistance_hauler = "Сборщик",
}

local profile = CreateConVar("d6_profile", "auto", FCVAR_ARCHIVE + FCVAR_REPLICATED,
    "Abaddon profile: auto, campaign, arena")

function D6_Session.Resolve(map, gamemode, configured)
    configured = string.lower(configured or "auto")
    if configured == "arena" or configured == "campaign" then return configured end
    map = string.lower(map or "")
    if map:match("^d[123]_") or map:match("^ep[12]_") or gamemode ~= "sandbox" then
        return "campaign"
    end
    return "arena"
end

function D6_Session.Profile()
    return D6_Session.Resolve(game.GetMap(), engine.ActiveGamemode(), profile:GetString())
end

function D6_Session.IsArena()
    return D6_Session.Profile() == "arena"
end

function D6_Session.CanEditWorld(ply)
    return IsValid(ply) and (ply:IsAdmin() or ply:IsListenServerHost())
end

if SERVER then
    local roleByAI = {pressure = "assault", flank = "interceptor", standoff = "artillery",
        support = "support", anchor = "heavy_elite"}

    function D6_Session.SetVariant(ent, variant, target)
        ent.D6_Variant = variant
        local loadout = ent.D6_Loadout
        local visual = loadout and (loadout.appearance or roleByAI[loadout.ai]) or variant
        local customModel = loadout and loadout.model and loadout.model ~= "" and util.IsValidModel(loadout.model)
        ent:SetNW2String("D6_ArtVariant", customModel and "" or visual)
        local art = D6_Drones.Types[visual]
        if art and art.role and D6_Swarm and not ent.D6_SwarmExclude then
            D6_Swarm.Register(ent, art, target)
        end
        if variant == "grav" and D6_Gravity then D6_Gravity.Register(ent, target) end
        if ent:GetClass() == "npc_cscanner" then ent:Fire("DisableFlashlight") end
    end
end
