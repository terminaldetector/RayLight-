if not CLIENT then return end
D6_Art = {}
local A, G = D6_Art, D6_ArtGeometry
local arsenal = D6_Arsenal
local meshCache = {}
local finishes = {}
for _, finish in pairs(G.finishes) do
    if not finishes[finish] then
        finishes[finish] = CreateMaterial("drmd_model_finish_" .. finish, "UnlitGeneric", {
            ["$basetexture"] = "drmd/drmd_finish_" .. finish, ["$vertexcolor"] = "1", ["$nocull"] = "1",
        })
    end
end
local plain = CreateMaterial("drmd_model_plain", "UnlitGeneric",
    {["$basetexture"] = "vgui/white", ["$vertexcolor"] = "1", ["$nocull"] = "1"})
local signal = CreateMaterial("drmd_model_signal", "UnlitGeneric",
    {["$basetexture"] = "vgui/white", ["$nocull"] = "1"})
local glow = Material("sprites/light_glow02_add")
local trail = Material("sprites/laserbeam")
local neutral = Color(194, 208, 206)
local localSignals = {lamp = 1.0, siege_eye = 0.91}

local skins = D6_Drones.Types
A.Skins = skins

local shotInk = {
    kinetic = Color(249, 203, 133), energy = Color(84, 220, 224),
    explosive = Color(255, 141, 74), exotic = Color(191, 158, 252),
    shot_kinetic = Color(249, 203, 133), shot_energy = Color(84, 220, 224),
    shot_rocket = Color(255, 141, 74), shot_exotic = Color(191, 158, 252),
    mine = Color(166, 235, 164),
}

local function compile(name)
    local model = G.models[name]
    if not model then return end
    local cache = {}
    local rig = D6_Drones.Rigs[name]
    for material, part in pairs(model.parts) do
        local groups = {}
        local rgb = G.palette[material]
        for _, face in ipairs(part) do
            local bank = rig and rig.sections[face[5]] or "body"
            local triangles = groups[bank] or {}
            groups[bank] = triangles
            local n = face[4]
            local shade = math.Clamp(0.81 + n[3]*0.17 + n[1]*0.08 - n[2]*0.07, 0.53, 1)
            local col = Color(rgb[1]*shade, rgb[2]*shade, rgb[3]*shade)
            local normal = Vector(n[1], n[2], n[3])
            for j = 1, 3 do
                local p = face[j]
                local u, v = G.UV(p, n)
                triangles[#triangles + 1] = {pos = Vector(p[1],p[2],p[3]), normal = normal, u = u, v = v, color = col}
            end
        end
        for bank, triangles in pairs(groups) do
            local object = Mesh()
            object:BuildFromTriangles(triangles)
            cache[bank] = cache[bank] or {}
            cache[bank][material] = object
        end
    end
    meshCache[name] = cache
    return cache
end

local transform = Matrix()
local function drawBatch(model, position, angles, scale, brightness, ink, power)
    transform:Identity()
    transform:SetTranslation(position)
    transform:SetAngles(angles)
    transform:Scale(Vector(scale, scale, scale))
    cam.PushModelMatrix(transform)
    render.SetColorModulation(brightness, brightness, brightness)
    for material, part in pairs(model) do
        if material ~= "emit" and material ~= "hot" and not localSignals[material] then
            render.SetMaterial(finishes[G.finishes[material]] or plain)
            part:Draw()
        end
    end
    if model.hot then
        local heat=0.50+power*.34
        render.SetMaterial(plain)
        render.SetColorModulation(heat,heat,heat)
        model.hot:Draw()
    end
    if model.emit then
        render.SetMaterial(signal)
        render.SetColorModulation(ink.r/255*power, ink.g/255*power, ink.b/255*power)
        model.emit:Draw()
    end
    for material, strength in pairs(localSignals) do
        if model[material] then
            local color = G.palette[material]
            local amount = strength*(material == "siege_eye" and power or 1)/255
            render.SetMaterial(signal)
            render.SetColorModulation(color[1]*amount, color[2]*amount, color[3]*amount)
            model[material]:Draw()
        end
    end
    render.SetColorModulation(1, 1, 1)
    cam.PopModelMatrix()
end

function A.Draw(name, position, angles, scale, ink, power, lit, ent)
    local model = meshCache[name] or compile(name)
    if not model then return false end
    ink, power = ink or neutral, power or 1
    local light = lit and render.GetLightColor(position) or nil
    local brightness = light and math.Clamp(0.55 + light:Length()*0.45, 0.56, 1.25) or 1.06
    local now = CurTime()
    for bank,batch in pairs(model) do
        local lighting,source,rotation=ink,position,angles
        if bank~="body" and IsValid(ent) then
            source,rotation=D6_Drones.BankPose(ent,bank,now)
            if bank=="eye" then
                local started=ent:GetNW2Float("D6_EyeCharge",-10)
                local charge=math.Clamp((now-started)/.95,0,1)
                if now-started<1.38 then lighting=Color(Lerp(charge,113,255),Lerp(charge,203,79),Lerp(charge,248,51)) end
            end
        end
        drawBatch(batch,source,rotation,scale,brightness,lighting,power)
    end
    return true
end

local function flash(pos, ink, size, alpha)
    render.SetMaterial(glow)
    render.DrawSprite(pos, size, size, Color(ink.r, ink.g, ink.b, alpha))
end

local function projectileColor(tag)
    local spec = arsenal.Ordnance[tag]
    return spec and spec.color or shotInk[tag] or neutral
end

function A.DrawProjectile(ent)
    local tag = ent:GetNWString("D6_ProjectileArt", "")
    local spec = arsenal.Ordnance[tag]
    local mesh = spec and spec.mesh or tag
    if not G.models[mesh] then return end
    local pos, ang = ent:GetPos(), ent:GetAngles()
    local col = projectileColor(tag)
    if not spec or ent:GetNW2Bool("D6_ProjectileTint") then
        local rgb = ent:GetColor()
        if rgb.r + rgb.g + rgb.b < 760 then col = rgb end
    end
    local scale = ent:GetNWFloat("D6_ProjectileArtScale", 1)
    local phase = spec and spec.state
    local power = 0.86
    if phase == "armed" and not ent:GetNWBool("D6_MineArmed") then
        power = 0.23
    elseif phase then
        power = 0.78 + 0.26*math.sin(CurTime()*5 + ent:EntIndex()*0.73)
    elseif not spec or not spec.radius then
        local roll = Angle(ang.p,ang.y,ang.r)
        roll:RotateAroundAxis(ang:Forward(),(CurTime()*310)%360)
        ang = roll
    end
    A.Draw(mesh,pos,ang,scale,col,power,spec and spec.radius ~= nil)
    if (spec and not spec.radius) or tag == "shot_energy" or tag == "shot_exotic" or phase then
        flash(pos,col,(phase and 13 or 15)*scale,(phase and 119 or 105)*power)
    end
    return true
end

function A.DrawDrone(variant, pos, ang, power, animated, factor, ent)
    local skin = skins[variant]
    if not skin then return end
    local scale = factor or skin.scale
    A.Draw(skin.mesh,pos,ang,scale,skin.color,power,true,ent)
    if skin.mesh == "cutter" then
        local spin = Angle(ang.p,ang.y,ang.r)
        if animated then spin:RotateAroundAxis(ang:Up(), (CurTime()*610)%360) end
        A.Draw("cutter_rotor",pos,spin,scale,skin.color,power,true)
    elseif variant == "grav" then
        local now = animated and CurTime() or 0
        for i, tilt in ipairs({0,62,-63}) do
            local ring = Angle(ang.p,ang.y,ang.r)
            ring:RotateAroundAxis(ang:Forward(),tilt+now*(i%2==0 and 22 or -16))
            ring:RotateAroundAxis(ang:Up(),i*37+now*24)
            A.Draw("grav_gimbal",pos,ring,scale*(1+(i-1)*0.065),skin.color,power,true)
        end
    end
end

local proxies, gravityProps = {}, {}
local function drawAssigned(ent, flags)
    local variant = ent:GetNW2String("D6_ArtVariant", "")
    local projectile = ent:GetNWString("D6_ProjectileArt", "")
    local skin = skins[variant]
    local pos, ang = ent:GetPos(), ent:GetAngles()
    if skin then
        local charge = math.max(0, ent:GetNWFloat("D6_ThreatAt", 0) - CurTime())
        local power = charge > 0 and (0.72 + math.abs(math.sin(CurTime()*23))*0.38) or 0.70
        if variant == "grav" then power = power + ent:GetNW2Int("D6_GravityLoad",0)*0.04 end
        A.DrawDrone(variant,pos,ang,power,true,nil,ent)
        return
    elseif projectile ~= "" and G.models[projectile] then
        A.DrawProjectile(ent)
        return
    end
    local previous = proxies[ent]
    if previous then previous(ent, flags) else ent:DrawModel(flags) end
end

local function discover(ent)
    if proxies[ent] ~= nil or not IsValid(ent) then return end
    local class = ent:GetClass()
    if class == "d6_projectile" or class == "d6_ordnance" or class == "d6_exhibit" then return end
    local variant = ent:GetNW2String("D6_ArtVariant", "")
    local projectile = ent:GetNWString("D6_ProjectileArt", "")
    local skin = skins[variant]
    if not skin and not G.models[projectile] then return end
    proxies[ent] = ent.RenderOverride or false
    ent.RenderOverride = drawAssigned
    local extent = skin and 42*skin.scale or 28
    ent:SetRenderBounds(Vector(-extent, -extent, -extent), Vector(extent, extent, extent))
end

hook.Add("EntityNetworkedVarChanged", "D6_ArtNetwork", function(ent, key)
    if key == "D6_ArtVariant" or key == "D6_ProjectileArt" then discover(ent) end
end)
timer.Create("D6_ArtDiscover", 0.25, 0, function()
    for _, ent in ipairs(ents.GetAll()) do
        discover(ent)
        if ent:GetClass() == "prop_physics" or ent:GetClass() == "prop_physics_multiplayer" or ent:GetClass() == "d6_ordnance" then
            gravityProps[ent] = IsValid(ent:GetNWEntity("D6_GravityCarrier")) and true or nil
        end
    end
end)
hook.Add("EntityRemoved", "D6_ArtForget", function(ent)
    proxies[ent], gravityProps[ent] = nil, nil
end)
hook.Add("ShutDown", "D6_DestroyMeshes", function()
    for _, model in pairs(meshCache) do
        for _, bank in pairs(model) do
            for _, part in pairs(bank) do part:Destroy() end
        end
    end
    meshCache = {}
end)

function A.DrawWorldWeapon(weapon)
    local owner = weapon:GetOwner()
    if IsValid(owner) and owner:GetNWBool("D6On") then return end
    local item = arsenal.Visual(weapon:GetClass())
    if not item then weapon:DrawModel(); return end
    local data = arsenal.Families[item.family]
    local ang, pos = weapon:GetAngles(), weapon:GetPos()
    if IsValid(owner) and owner:IsPlayer() then
        local id = owner:LookupAttachment("anim_attachment_RH")
        local hand = id > 0 and owner:GetAttachment(id)
        if hand then ang, pos = hand.Ang, hand.Pos end
    end
    A.Draw(item.mesh, pos + ang:Forward()*4 + ang:Up()*2, ang, 0.72, data.color, 0.78, true)
end

local function recoil(weapon)
    if not IsValid(weapon) then return 0, 0 end
    local time = weapon:GetNWFloat("D6_ShotAt", -1)
    if time < 0 then return 0, 0 end
    local age = CurTime() - time
    if age < 0 or age > 0.38 then return 0, 0 end
    local kick = weapon:GetNWFloat("D6_ShotKick", 1)
    local reset = math.max(0, 1 - age/0.34)
    return 4.4*kick*reset*reset, math.Clamp(1-age/0.09, 0, 1)
end

local function drawMount(item, weapon, position, angles, scale, lit, active)
    local data = arsenal.Families[item.family]
    local kick, ignition = recoil(weapon)
    local charge = item.charge and IsValid(weapon) and weapon:GetNWFloat(item.charge, 0) or 0
    local power = (active and 0.96 or 0.34) + 0.38*ignition + 0.52*charge
    local bodyPosition = position - angles:Forward()*kick
    A.Draw(item.mesh, bodyPosition, angles, scale, data.color, power, lit)
    if item.family == "mine" then
        local hinge = Angle(angles.p, angles.y, angles.r)
        hinge:RotateAroundAxis(hinge:Forward(), math.Clamp(kick*17, 0, 64))
        A.Draw("mine_hatch", position - angles:Up()*(4 + kick*0.45)*scale, hinge, scale, data.color, power, lit)
    end
    if item.family ~= "optic" and (ignition > 0 or charge > 0.2) then
        local port = arsenal.Port(bodyPosition,angles,item,1)
        local muzzle = bodyPosition + (port-bodyPosition)*scale
        flash(muzzle, data.color, (10 + ignition*14 + charge*8)*scale, 128*ignition + 51*charge)
    end
end

local function pose(ply)
    return (ply == LocalPlayer() and ply.D6Ang) or ply._D6AngLerp or ply:GetRenderAngles()
end

local function drawScannerMounts(ply, origin, angles)
    local active = ply:GetActiveWeapon()
    local class = IsValid(active) and active:GetClass() or ""
    local index = arsenal.Slot(ply, class)
    for i = 1, #arsenal.Mounts do
        local assigned = i == index and class or arsenal.Get(ply, i)
        local item = arsenal.Entries[assigned]
        if item then
            local anchor = arsenal.MountOrigin(origin, angles, i)
            local joint = origin + (anchor - origin)*0.74
            A.Draw("mount_joint", joint, angles, 1.0, neutral, 0.5, true)
            drawMount(item, ply:GetWeapon(assigned), anchor, angles, 1, true, i == index)
        end
    end
end

local opticInk = Color(127, 214, 238)
hook.Add("PrePlayerDraw", "D6_ArtScannerBody", function(ply)
    if not ply:GetNWBool("D6On") or ply:GetModel() ~= arsenal.Scanner.model then return end
    local angles, origin = pose(ply), arsenal.Anchor(ply)
    local weapon = ply:GetActiveWeapon()
    local charge, firing = 0, false
    if IsValid(weapon) and weapon:GetClass() == "weapon_d6_hyperbeam" then
        charge = weapon:GetNWFloat("D6_HyperCharge", 0)
        firing = weapon:GetNWBool("D6_HyperFiring", false)
    end
    A.Draw(arsenal.Scanner.mesh, origin, angles, 1, opticInk, 0.77 + charge*0.9 + (firing and 0.7 or 0), true)
    drawScannerMounts(ply, origin, angles)
    if charge > 0.12 or firing then
        local eye = arsenal.ScannerEye(ply, angles, origin)
        flash(eye, opticInk, 13 + charge*9, firing and 192 or charge*142)
    end
    return true
end)

hook.Add("PostPlayerDraw", "D6_ArtCustomMounts", function(ply)
    if ply:GetNWBool("D6On") and ply:GetModel() ~= arsenal.Scanner.model then
        drawScannerMounts(ply, arsenal.Anchor(ply), pose(ply))
    end
end)

local function hasWorkshop(class)
    return D6_SCKBridge and D6_SCKBridge.Has and D6_SCKBridge.Has(class)
end

hook.Add("PreDrawViewModel", "D6_ArtHideBaseViewmodel", function(_, _, weapon)
    if not IsValid(weapon) then return end
    local class = weapon:GetClass()
    if arsenal.Visual(class) or hasWorkshop(class) then return true end
end)

local selected, drawnAt
hook.Add("PostDrawTranslucentRenderables", "D6_ArtViewMount", function(depth, sky)
    if depth or sky or D6_RearViewPass then return end
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() or ply:ShouldDrawLocalPlayer() or ply:InVehicle()
    or GetViewEntity() ~= ply then return end
    if ply:GetNWBool("D6On") then
        local mounts = D6_ViewMounts.Collect(ply, arsenal, hasWorkshop)
        local angles, origin = EyeAngles(), EyePos()
        local drift = ply._D6AngVel or {}
        local bob = math.cos(RealTime()*4)*math.min(ply:GetVelocity():Length()/1500, 1)*0.2
        render.DepthRange(0, 0.08)
        for _, mount in ipairs(mounts) do
            if not mount.customActive then
                local position, scale = D6_ViewMounts.Pose(origin, angles, mount.slot,
                    ScrW()/math.max(ScrH(), 1), (drift.yaw or 0)*0.12, bob)
                drawMount(mount.item, mount.weapon, position, angles, scale, false, mount.active)
            end
        end
        render.DepthRange(0, 1)
        return
    end
    local weapon = ply:GetActiveWeapon()
    if not IsValid(weapon) then return end
    local class = weapon:GetClass()
    local item = arsenal.Visual(class)
    if not item or item.family == "optic" or item == arsenal.MechVisual or hasWorkshop(class) then return end
    if selected ~= weapon then selected, drawnAt = weapon, RealTime() end
    local rise = 1 - math.Clamp((RealTime() - drawnAt)/0.27, 0, 1)
    local ang = EyeAngles()
    local drift = ply._D6AngVel or {}
    local velocity = ply:GetVelocity():Length()
    local offset = arsenal.Slot(ply, class) == 1 and -14 or 14
    if item.family == "mine" then offset = 0 end
    local pos = EyePos() + ang:Forward()*30 + ang:Right()*(offset + math.Clamp(drift.yaw or 0, -5, 5)*0.2)
        - ang:Up()*(12.8 + rise*rise*11 + math.cos(RealTime()*4)*math.min(velocity/1500, 1)*0.38)
    render.DepthRange(0, 0.08)
    drawMount(item, weapon, pos, ang, 0.88, false, true)
    render.DepthRange(0, 1)
end)

net.Receive("D6_ImpactFX", function()
    local pos, normal, kind = net.ReadVector(), net.ReadNormal(), net.ReadString()
    if EyePos():DistToSqr(pos) > 2400^2 then return end
    local color = projectileColor(kind)
    local emitter = ParticleEmitter(pos)
    if not emitter then return end
    for i = 1, kind == "kinetic" and 3 or 6 do
        local particle = emitter:Add("sprites/light_glow02_add", pos + normal*2)
        if particle then
            particle:SetVelocity(normal*math.Rand(55, 120) + VectorRand()*95)
            particle:SetDieTime(math.Rand(0.10, 0.28))
            particle:SetStartSize(math.Rand(2, 4))
            particle:SetEndSize(0)
            particle:SetStartAlpha(210)
            particle:SetEndAlpha(0)
            particle:SetColor(color.r, color.g, color.b)
            particle:SetGravity(Vector(0, 0, -110))
        end
    end
    emitter:Finish()
end)

local motion = {}
local motionInk = {Color(122, 230, 226), Color(195, 159, 255), Color(255, 171, 102)}
net.Receive("D6_MoveFX", function()
    local start, finish, kind = net.ReadVector(), net.ReadVector(), net.ReadUInt(2)
    if #motion > 20 then table.remove(motion, 1) end
    motion[#motion + 1] = {from = start, to = finish, kind = kind, at = CurTime()}
end)

hook.Add("PostDrawTranslucentRenderables", "D6_ArtMovement", function(depth, sky)
    if depth or sky then return end
    for i = #motion, 1, -1 do
        local fx = motion[i]
        local frac = (CurTime() - fx.at)/0.42
        if frac >= 1 then table.remove(motion, i) else
            local dir = (fx.to-fx.from):GetNormalized()
            local ink = motionInk[fx.kind] or neutral
            if fx.kind == 1 then
                local front = LerpVector(frac, fx.from, fx.to)
                render.SetMaterial(trail)
                render.DrawBeam(fx.from + dir*13, front, 9*(1-frac), 0, 1, Color(ink.r, ink.g, ink.b, 188*(1-frac)))
                flash(front, ink, 36*(1-frac), 145*(1-frac))
            else
                local ang = dir:Angle()
                local right, up = ang:Right(), ang:Up()
                local radius = 15 + 54*frac
                render.SetMaterial(trail)
                local alpha = Color(ink.r, ink.g, ink.b, 182*(1-frac))
                for _, point in ipairs({fx.from, fx.to}) do
                    local last
                    for n = 0, 20 do
                        local theta = n*math.pi/10
                        local nextPoint = point + (right*math.cos(theta) + up*math.sin(theta))*radius
                        if last then render.DrawBeam(last, nextPoint, 2.5, 0, 1, alpha) end
                        last = nextPoint
                    end
                    flash(point, ink, radius*1.9, 100*(1-frac))
                end
            end
        end
    end
end)

local arcShots={}
net.Receive("D6_ArcDischarge",function()
    local start,finish,hit,optic=net.ReadVector(),net.ReadVector(),net.ReadBool(),net.ReadBool()
    local duration=optic and .51 or .31
    arcShots[#arcShots+1]={start=start,finish=finish,hit=hit,optic=optic,duration=duration,untilTime=CurTime()+duration}
end)
net.Receive("D6_RepairLink",function()
    arcShots[#arcShots+1]={start=net.ReadVector(),finish=net.ReadVector(),repair=true,untilTime=CurTime()+.31}
end)

hook.Add("PostDrawTranslucentRenderables", "D6_ArtThreats", function(depth, sky)
    if depth or sky then return end
    local now = CurTime()
    for ent in pairs(proxies) do
        if not IsValid(ent) then continue end
        local threatAt = ent:GetNWFloat("D6_ThreatAt", 0)
        local remaining = threatAt - now
        if remaining <= 0 then continue end
        local art = skins[ent:GetNW2String("D6_ArtVariant", "")]
        if not art then continue end
        local ink, scale = art.color, art.scale
        if art.mesh == "combine_arc_elite" then
            local thermal=ent:GetNWBool("D6_ArcThermal")
            local mode=ent:GetNW2Int("D6_ArcMode",2)
            local mix=math.Clamp((now-ent:GetNW2Float("D6_EyeCharge",now))/.95,0,1)
            local color=mode==4 and Color(Lerp(mix,113,255),Lerp(mix,204,71),Lerp(mix,246,49))
                or thermal and Color(255,170,93) or ink
            local endPos=ent:GetNWVector("D6_ThreatAim",ent:GetPos())
            local first,last=1,2
            if mode==4 then first,last=4,4
            elseif mode==3 then first,last=5,6
            elseif thermal then first,last=3,3 end
            for i=first,last do
                local source=D6_Drones.Muzzle(ent,i)
                flash(source,color,(18+8*math.abs(math.sin(remaining*26)))*scale,154)
                if not thermal and mode~=3 then
                    render.SetMaterial(trail)
                    render.DrawBeam(source,endPos,1.55,0,1,Color(color.r,color.g,color.b,118))
                end
            end
            continue
        end
        local cursor = ent:GetPos() + ent:GetForward()*27*scale
        if art.mesh == "combine_elite" then cursor = ent:GetPos() + (ent:GetForward()*26.7 + ent:GetUp()*1.03)*scale end
        if art.guns and art.mesh~="combine_elite" then cursor=D6_Drones.Muzzle(ent,1,cursor) end
        flash(cursor, ink, 29*scale + math.abs(math.sin(remaining*25))*19, 130 + 60*math.abs(math.sin(remaining*17)))
        local aim = ent:GetNWVector("D6_ThreatAim", cursor)
        render.SetMaterial(trail)
        render.DrawBeam(cursor, aim, 2.3, 0, 1, Color(ink.r, ink.g, ink.b, 72 + 54*math.abs(math.sin(remaining*19))))
    end
    for i=#arcShots,1,-1 do
        local shot=arcShots[i]
        local life=(shot.untilTime-now)/(shot.duration or .31)
        if life<=0 then table.remove(arcShots,i);continue end
        local color=shot.optic and Color(252,74,64) or shot.repair and skins.support.color or skins.arc_elite.color
        render.SetMaterial(trail)
        render.DrawBeam(shot.start,shot.finish,(shot.optic and 35 or shot.repair and 5 or 14)*life,0,2,Color(color.r,color.g,color.b,156*life))
        render.DrawBeam(shot.start,shot.finish,3.2*life,0,1,Color(219,246,255,246*life))
        flash(shot.start,color,41*life,192*life)
        if shot.hit then flash(shot.finish,color,44*life,196*life) end
    end
end)

hook.Add("PostDrawTranslucentRenderables", "D6_ArtGravField", function(depth, sky)
    if depth or sky then return end
    local ink = skins.grav.color
    for ent in pairs(gravityProps) do
        if not IsValid(ent) then continue end
        local carrier = ent:GetNWEntity("D6_GravityCarrier")
        if not IsValid(carrier) then continue end
        local origin = carrier:WorldSpaceCenter()
        local held = ent:WorldSpaceCenter()
        local wing = carrier:GetUp() * (18 + math.sin(CurTime()*10)*9)
        render.SetMaterial(trail)
        local last = origin
        for i = 1, 5 do
            local f = i/5
            local point = LerpVector(f, origin, held) + wing*math.sin(f*math.pi)
            render.DrawBeam(last, point, 1.55, 0, 1, Color(ink.r, ink.g, ink.b, 101))
            last = point
        end
        flash(held, ink, 16, 133)
    end
end)

local amber = Color(228, 162, 96)
local cream = Color(255, 228, 180)
local blue = Color(90, 206, 235)
local white = Color(216, 253, 255)
local hyper = {}

local function tone(color, alpha)
    return Color(color.r, color.g, color.b, alpha)
end

local function contactRing(point, normal, radius, color)
    if normal:LengthSqr() < 0.5 then return end
    local angle = normal:Angle()
    local right, up = angle:Right(), angle:Up()
    local last = point + right*radius
    for i = 1, 24 do
        local fraction = i*math.pi/12
        local nextPoint = point + (right*math.cos(fraction) + up*math.sin(fraction))*radius
        render.DrawLine(last, nextPoint, color, true)
        last = nextPoint
    end
end

local shockFields={}
net.Receive("D6_BossField",function()
    shockFields[#shockFields+1]={origin=net.ReadVector(),radius=net.ReadFloat(),time=CurTime()+net.ReadFloat()}
end)
hook.Add("PostDrawTranslucentRenderables","D6_BossShocks",function(depth,sky)
    if depth or sky then return end
    local now=CurTime()
    for i=#shockFields,1,-1 do
        local field=shockFields[i]
        local age=now-field.time
        if age>.67 then table.remove(shockFields,i);continue end
        local radius=age<0 and field.radius or math.max(18,field.radius*math.min(1,age/.43))
        local alpha=age<0 and 103+60*math.abs(math.sin(now*24)) or 227*(1-age/.67)
        for _,normal in ipairs({vector_up,Vector(1,0,0),Vector(0,1,0)}) do
            contactRing(field.origin,normal,radius,tone(amber,alpha))
        end
    end
end)

local function drawAdhesion(ply, now)
    local index = ply:GetNW2Int("D6_AdhesionEntity", -1)
    if index < 0 then return end
    local point = ply:GetNW2Vector("D6_AdhesionPoint")
    local normal = ply:GetNW2Vector("D6_AdhesionNormal")
    if index > 0 then
        local entity = Entity(index)
        if not IsValid(entity) then return end
        local localPoint = point
        point = entity:LocalToWorld(localPoint)
        normal = (entity:LocalToWorld(localPoint + normal) - point):GetNormalized()
    end
    local eye, obstruction = arsenal.EyeClearance(ply, pose(ply), MASK_SOLID)
    if obstruction.Hit then eye = obstruction.HitPos + obstruction.HitNormal end
    if eye:DistToSqr(point) < 4 then return end
    local roll = now*2.3
    render.SetMaterial(trail)
    render.DrawBeam(eye, point, 5.2, roll, roll+3, tone(amber, 103))
    render.DrawBeam(eye, point, 1.6, -roll, -roll+1, tone(cream, 226))
    flash(point + normal*2, amber, 16+math.sin(now*20)*3, 130)
    contactRing(point + normal*1.25, normal, 7+(now*2.2%1)*13, tone(amber, 125))
    contactRing(point + normal*1.35, normal, 5, tone(cream, 174))
end

local function drawDash(ply)
    local elapsed, direction = D6_DashVisual(ply)
    if not elapsed or not direction then return end
    if ply == LocalPlayer() and not ply:ShouldDrawLocalPlayer() then return end
    local amount = 1-elapsed/0.33
    local center = arsenal.Anchor(ply)
    local angle = pose(ply)
    for _, side in ipairs({-1, 1}) do
        local start = center - angle:Forward()*15 + angle:Right()*side*11
        local finish = start - direction*(39+118*amount)
        render.SetMaterial(trail)
        render.DrawBeam(start, finish, 2.9*amount, 0, 1, tone(blue, 143*amount))
        flash(start, blue, 24*amount, 191*amount)
    end
end

net.Receive("D6_HyperPulse", function()
    local ply = net.ReadEntity()
    local source, impact, normal = net.ReadVector(), net.ReadVector(), net.ReadVector()
    local first = net.ReadBool()
    if not IsValid(ply) then return end
    local now = CurTime()
    local before = hyper[ply]
    hyper[ply] = {origin = source, impact = impact, normal = normal, updated = now,
        born = not first and before and before.born or now}
    if normal:LengthSqr() < 0.5 or EyePos():DistToSqr(impact) > 2600^2 then return end
    local emitter = ParticleEmitter(impact)
    if not emitter then return end
    for _ = 1, first and 7 or 3 do
        local spark = emitter:Add("sprites/light_glow02_add", impact + normal*2)
        if spark then
            spark:SetVelocity(normal*math.Rand(84, 175) + VectorRand()*88)
            spark:SetDieTime(math.Rand(0.09, 0.23))
            spark:SetStartSize(math.Rand(1.5, 3.3))
            spark:SetEndSize(0)
            spark:SetStartAlpha(238)
            spark:SetEndAlpha(0)
            spark:SetColor(148, 219, 237)
            spark:SetGravity(Vector(0,0,-180))
        end
    end
    emitter:Finish()
end)

local function drawHyper(ply, shot, now)
    local age = now - shot.updated
    if not IsValid(ply) or not ply:GetNWBool("D6On") or age > 0.25 then hyper[ply] = nil; return end
    local source = arsenal.ScannerEye(ply, pose(ply))
    if shot.origin:DistToSqr(shot.impact) < 12^2 then source = shot.origin end
    local impact = shot.impact
    local intensity = math.min((now-shot.born)*25 + 0.45, 1) * math.Clamp((0.25-age)/0.14, 0, 1)
    local width = intensity*(1 + 0.08*math.sin(now*66))
    render.SetMaterial(trail)
    render.DrawBeam(source, impact, 16*width, now*9, now*9+2.8, tone(blue, 106*intensity))
    render.DrawBeam(source, impact, 7.1*width, 0, 1, tone(opticInk, 213*intensity))
    render.DrawBeam(source, impact, 2.8*width, 0, 1, tone(white, 245*intensity))
    if ply ~= LocalPlayer() or ply:ShouldDrawLocalPlayer() then flash(source, opticInk, 30*width, 187*intensity) end
    if shot.normal:LengthSqr() > 0.5 then
        local contact = impact + shot.normal*2
        flash(contact, blue, 44*width, 224*intensity)
        contactRing(contact, shot.normal, 10 + (now*2.6%1)*25, tone(opticInk, 160*intensity))
        contactRing(contact, shot.normal, 7, tone(white, 160*intensity))
        local light = DynamicLight(ply:EntIndex()+2400)
        if light then
            light.pos, light.r, light.g, light.b = contact, 102, 209, 235
            light.brightness, light.Size, light.DieTime = 1.6*intensity, 134, now+0.10
        end
    end
end

hook.Add("PostDrawTranslucentRenderables", "D6_FlightFields", function(depth, sky)
    if depth or sky then return end
    local now = CurTime()
    for _, ply in ipairs(player.GetAll()) do
        if ply:GetNWBool("D6On") then
            drawAdhesion(ply, now)
            drawDash(ply)
        end
    end
    for ent in pairs(proxies) do
        if not IsValid(ent) or ent:GetNW2String("D6_ArtVariant") ~= "grav" then continue end
        local load = ent:GetNW2Int("D6_GravityLoad", 0)
        if load == 0 or EyePos():DistToSqr(ent:GetPos()) > 1950^2 then continue end
        local center = ent:WorldSpaceCenter()
        local phase = now*0.8 + ent:EntIndex()*0.13
        local radius = now < ent:GetNWFloat("D6_ThreatAt",0) and 119 or 153
        for i=1,3 do
            local axis=Angle(19*math.sin(phase+i), phase*37+i*57, i*49+phase*26):Up()
            contactRing(center,axis,radius,tone(skins.grav.color,21+load*3))
        end
        local captured = now-ent:GetNW2Float("D6_GravityCapturedAt", -8)
        if captured < 0.36 then flash(center, skins.grav.color, 29+captured*66, 155*(1-captured/0.36)) end
    end
    for ply, shot in pairs(hyper) do drawHyper(ply, shot, now) end
end)

local shots = {}
net.Receive("D6_MuzzleFX", function()
    local from, aim, tag = net.ReadVector(), net.ReadNormal(), net.ReadString()
    if EyePos():DistToSqr(from) > 2400^2 then return end
    if #shots >= 96 then table.remove(shots,1) end
    shots[#shots+1] = {pos=from,axis=aim,ink=projectileColor(tag),born=CurTime(),
        heavy=tag=="shot_homing" or tag=="shot_mega" or tag=="shot_ion"}
end)

hook.Add("PostDrawTranslucentRenderables", "D6_MuzzleGeometry", function(depth, sky)
    if depth or sky then return end
    local now = CurTime()
    for i=#shots,1,-1 do
        local item=shots[i]
        local fraction=(now-item.born)/0.14
        if fraction >= 1 then table.remove(shots,i); continue end
        local live=1-fraction
        local length=item.heavy and 43 or 29
        local size=item.heavy and 7.5 or 3.55
        render.SetMaterial(trail)
        render.DrawBeam(item.pos,item.pos+item.axis*length*live,size*live,0,1,tone(item.ink,212*live))
        flash(item.pos,item.ink,size*3.2*live,183*live)
        if item.heavy then contactRing(item.pos+item.axis*(6+fraction*15),item.axis,6+fraction*8,tone(item.ink,134*live)) end
    end
end)
