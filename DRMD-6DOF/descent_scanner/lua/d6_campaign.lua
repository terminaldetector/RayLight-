D6_Campaign = {}
local C = D6_Campaign
C.Maps = {
    d1_trainstation_01 = {name = "Вокзал · прибытие", units = {"interceptor","laser","grav"}, distance = 212},
    d1_trainstation_02 = {name = "Вокзал · городская площадь", units = {"assault","support","rocket_elite_aa"}, distance = 275},
    d1_trainstation_03 = {name = "Вокзал · жилой квартал", units = {"resistance_scout","resistance_raider","resistance_hauler"}, distance = 228},
}

function C.ActiveMap()
    return C.Maps[game.GetMap():lower()]
end

if CLIENT then return end
local enabled = CreateConVar("d6_campaign_preview", "0", FCVAR_ARCHIVE, "Allow explicit Abaddon exhibits on the first three Half-Life 2 maps",0,1)
local active = {}

local function clear(ply)
    for _,ent in ipairs(active[ply] or {}) do if IsValid(ent) then ent:Remove() end end
    active[ply] = nil
end

-- Resolve placements in the loaded map, checking the view path, the volume at
-- each slot and transition entities. No BSP coordinates or landmark edits are needed.
function C.Layout(ply, section)
    local angles = Angle(0,ply:EyeAngles().y,0)
    local origin = ply:WorldSpaceCenter()
    local slots = {}
    local function canPlace(pos, half)
        if not util.IsInWorld(pos) then return false end
        local hull = Vector(half,half,half)
        local path = util.TraceLine({start=origin,endpos=pos,filter=ply,mask=MASK_SOLID_BRUSHONLY})
        if path.Hit then return false end
        local blocked = util.TraceHull({start=pos,endpos=pos,mins=-hull,maxs=hull,filter=ply,mask=MASK_SOLID})
        if blocked.Hit or blocked.StartSolid then return false end
        for _,marker in ipairs(ents.FindInSphere(pos, 115)) do
            local class = marker:GetClass()
            if class == "info_landmark" or class == "trigger_changelevel" or class == "trigger_transition"
                or class == "info_player_start" then return false end
        end
        return true
    end
    for scaleIndex, distance in ipairs({section.distance,section.distance*.84,section.distance*1.24}) do
        local candidates = {}
        for i, variant in ipairs(section.units) do
            local art = D6_Drones.Types[variant]
            local side = (i-(#section.units+1)*.5)*(scaleIndex == 2 and 49 or 67)
            local pos = origin + angles:Forward()*(distance+i*5) + angles:Right()*side + Vector(0,0,21+(i%2)*14)
            if canPlace(pos,22) and art then
                candidates[#candidates+1] = {variant=variant,pos=pos,yaw=(origin-pos):Angle().y,scale=math.min(art.scale,0.75)}
            end
        end
        if #candidates == #section.units then slots=candidates; break end
    end
    return slots
end

local function show(ply)
    if not D6_Session.CanEditWorld(ply) or not ply:Alive() then return end
    local section = C.ActiveMap()
    if not (enabled:GetBool() and D6_Session.Profile() == "campaign" and section) then
        ply:ChatPrint("[Abaddon] Для стенда доступны d1_trainstation_01–03 и d6_campaign_preview 1.")
        return
    end
    if CurTime() < (ply.D6_NextCampaignExhibit or 0) then return end
    ply.D6_NextCampaignExhibit = CurTime()+1
    local slots = C.Layout(ply,section)
    if #slots == 0 then ply:ChatPrint("[Abaddon] Для стенда нужен свободный участок перед игроком."); return end
    local exhibits = {}
    for _, slot in ipairs(slots) do
        local model = ents.Create("d6_exhibit")
        if not IsValid(model) then
            for _,ent in ipairs(exhibits) do ent:Remove() end
            return
        end
        model:SetPos(slot.pos)
        model:SetAngles(Angle(0,slot.yaw,0))
        model:Spawn()
        model:SetNW2String("D6_ExhibitModel",slot.variant)
        model:SetNW2Float("D6_ExhibitScale",slot.scale)
        model:SetNW2Float("D6_ExhibitEnd",CurTime()+45)
        exhibits[#exhibits+1] = model
    end
    clear(ply)
    active[ply] = exhibits
    timer.Simple(45,function() if active[ply] == exhibits then clear(ply) end end)
    ply:ChatPrint("[Abaddon] Бестиарий · "..section.name.." · 45 с")
end

concommand.Add("d6_campaign_exhibit",show)
concommand.Add("d6_campaign_exhibit_clear",function(ply) if IsValid(ply) then clear(ply) end end)
hook.Add("PlayerDisconnected","D6_CampaignPreviewDisconnect",clear)
hook.Add("PostCleanupMap","D6_CampaignPreviewCleanup",function() for ply in pairs(active) do clear(ply) end end)
cvars.AddChangeCallback("d6_campaign_preview",function(_,_,value)
    if tonumber(value) == 0 then for ply in pairs(active) do clear(ply) end end
end,"D6_CampaignPreviewEnable")
