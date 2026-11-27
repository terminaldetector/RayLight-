-- Exercise the actual BSP collision world around the native service station.
if not SERVER then return end

hook.Add("InitPostEntity", "AbaddonRecoveryRangeQA", function()
    if game.GetMap() ~= "d6_native_flightlab" then return end
    timer.Simple(.9, function()
        local total, failures = 0, 0
        local function check(label, ok)
            total = total + 1
            if not ok then failures = failures + 1 end
            print(("RECOVERY %s | %s"):format(ok and "PASS" or "FAIL", label))
        end
        local center = Vector(1496,-450,480)
        local marker = ents.FindByName("d6_lab_service_center")[1]
        local volume = ents.FindByName("d6_lab_service_zone")[1]
        check("service marker matches station", IsValid(marker) and marker:GetPos():DistToSqr(center) < .1)
        check("service approach announces the station", IsValid(volume) and volume:GetClass() == "trigger_multiple")
        local function trace(dest)
            return util.TraceLine({start=center, endpos=dest, mask=MASK_SOLID_BRUSHONLY})
        end
        local front, rear, high = center+Vector(0,64,0), center-Vector(0,90,0), center+Vector(0,0,97)
        check("front approach inside service sphere", center:Distance(front) < 112 and not trace(front).Hit)
        check("rear shield blocks service within reach", center:Distance(rear) < 112 and trace(rear).HitWorld)
        check("vertical approach inside service sphere", center:Distance(high) < 112 and not trace(high).Hit)
        local far = center+Vector(0,145,0)
        check("open approach also extends outside service sphere", center:Distance(far) > 112 and not trace(far).Hit)
        local hull = util.TraceHull({start=far, endpos=front, mins=Vector(-16,-16,-16),
            maxs=Vector(16,16,16), mask=MASK_SOLID_BRUSHONLY})
        check("flight hull clears front approach", not hull.Hit)
        print(("RECOVERY COMPLETE | %d checks | %d failures"):format(total,failures))
    end)
end)
