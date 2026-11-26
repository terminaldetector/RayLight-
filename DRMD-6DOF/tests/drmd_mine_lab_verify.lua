-- Dedicated Source geometry and asset checks. Load before the Flight Lab BSP.
if not SERVER then return end

hook.Add("InitPostEntity", "AbaddonMineLabQA", function()
    if game.GetMap() ~= "d6_native_flightlab" then return end
    timer.Simple(1, function()
        local total, failures = 0, 0
        local function check(label, ok)
            total = total + 1
            if not ok then failures = failures + 1 end
            print(("MINE LAB %s | %s"):format(ok and "PASS" or "FAIL", label))
        end
        for _, key in ipairs({"mine_plasma", "mine_gravity", "supply"}) do
            local model = "models/drmd/" .. key .. ".mdl"
            util.PrecacheModel(model)
            check(key .. " loaded", util.IsValidModel(model) and util.IsModelLoaded(model))
            local body = ents.Create("prop_dynamic_override")
            body:SetModel(model)
            body:SetPos(Vector(465, -220, 190))
            body:Spawn()
            local low, high = body:GetModelBounds()
            check(key .. " has studio geometry", body:GetModel() == model and high.x > low.x and high.z > low.z)
            body:Remove()
        end
        local function clearance(start, angles)
            local dest = start + angles:Forward() * 100 - angles:Up() * 18
            local extent = Vector(14,14,14)
            return util.TraceHull({start=start, endpos=dest, mins=-extent, maxs=extent, mask=MASK_SHOT_HULL})
        end
        check("level port clears open room", not clearance(Vector(180,-80,128), Angle()).Hit)
        check("floor blocks the lowered port", clearance(Vector(200,-80,21), Angle()).Hit)
        check("inversion clears the port above the floor", not clearance(Vector(200,-80,21), Angle(0,0,180)).Hit)
        check("wall blocks deployment", clearance(Vector(-48,0,160), Angle(0,180,0)).Hit)
        check("vertical launch clears room", not clearance(Vector(240,-80,128), Angle(-90,0,0)).Hit)
        local maker = ents.FindByName("d6_lab_mine_target")[1]
        local button = ents.FindByName("d6_lab_mine_switch")[1]
        check("maker and manual control exist", IsValid(maker) and IsValid(button))
        check("no target before activation", #ents.FindByClass("npc_manhack") == 0)
        if IsValid(button) then button:Fire("Press") end
        timer.Simple(.55, function()
            check("Hammer button spawns one manhack", #ents.FindByClass("npc_manhack") == 1)
            if IsValid(maker) then maker:Fire("Spawn") end
            timer.Simple(.25, function()
                check("second spawn respects the live target limit", #ents.FindByClass("npc_manhack") == 1)
                print(("MINE LAB COMPLETE | %d checks | %d failures"):format(total,failures))
            end)
        end)
    end)
end)
