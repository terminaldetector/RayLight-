-- =========================================================
-- DESCENT 6DOF — d6_client.lua  (чистая версия)
-- Пушки-вертолёты убраны полностью.
-- Модель игрока — combine_scanner.mdl (ставится в d6_core).
-- =========================================================
if not CLIENT then return end

local ROLL_SPEED  = 175
local ROLL_LIMIT  = 180
local ANG_HZ      = 20
local ANG_THRESH  = 1.5

local Ang        = nil
local LastAng    = Angle()
local LastSendT  = 0
local CamReady   = false
local Dashing    = false
local DashDir    = Vector(0,0,0)
local ThirdPerson   = false
local CamLag        = Vector(0, 0, 0)
local RollVel       = 0
local CameraFOVKick = 0

local Remote = {}

-- X-клавиша: рывок; Q-клавиша: быстрый выбор грависрельсы
local XKeyDown = false

-- =========================================================
-- NET RECEIVES
-- =========================================================
net.Receive("D6_Toggle", function()
    local ply = net.ReadEntity(); local on = net.ReadBool()
    if not IsValid(ply) then return end
    if on then
        Remote[ply] = Remote[ply] or {}; Remote[ply].d6On = true
    else
        Remote[ply] = nil
        if ply == LocalPlayer() then
            Ang = nil; CamReady = false
            Dashing = false
            CameraFOVKick = 0
            RollVel = 0
            CamLag = Vector()
        end
    end
end)

net.Receive("D6_AngSync", function()
    local ply = net.ReadEntity(); local ang = net.ReadAngle()
    if not IsValid(ply) or ply == LocalPlayer() then return end
    Remote[ply] = Remote[ply] or {}
    Remote[ply].ang = ang
    Remote[ply].angLerp = Remote[ply].angLerp or ang
    -- Сохраняем на энтити для D6-оружий
    ply._D6AngLerp = Remote[ply].angLerp
end)

net.Receive("D6_DashSync", function()
    local ply = net.ReadEntity(); local on = net.ReadBool(); local dir = net.ReadVector()
    if not IsValid(ply) then return end
    if ply == LocalPlayer() then
        Dashing = on
        if on then DashDir = dir end
    end
    local state = Remote[ply] or {}
    Remote[ply] = state
    if on then state.dashTime, state.dashDir = CurTime(), dir end
end)

hook.Add("EntityRemoved", "D6_CLI_EntRemoved", function(ent)
    if ent:IsPlayer() then Remote[ent] = nil end
end)

-- =========================================================
-- КАМЕРА
-- =========================================================
hook.Add("CreateMove", "D6_Cam_CM", function(cmd)
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:GetNWBool("D6On", false) then
        CamReady = false; return
    end
    if not CamReady or not Ang then
        Ang = cmd:GetViewAngles(); CamReady = true
    end
    local ft = FrameTime()
    if ft <= 0 then return end

    -- ── [Descent] угловая инерция камеры ────────────────────────────
    -- TurnVel: первый слой фильтра — сглаживает мышиный ввод (75ms до 50%).
    --          было ft*12 (60ms) — слишком быстро, нет ощущения массы.
    --          стало ft*8  (75ms) — отклик 75ms, угасание 240ms.
    -- _D6AngVel: второй слой — угловая инерция тела (FA=ON 135ms, FA=OFF 330ms).
    ply.D6TurnVel = ply.D6TurnVel or { pitch = 0, yaw = 0 }
    ply._D6AngVel = ply._D6AngVel or { pitch = 0, yaw = 0 }
    local targetPitch =  cmd:GetMouseY() * 0.015
    local targetYaw   = -cmd:GetMouseX() * 0.015
    ply.D6TurnVel.pitch = Lerp(ft * 8, ply.D6TurnVel.pitch, targetPitch)
    ply.D6TurnVel.yaw   = Lerp(ft * 8, ply.D6TurnVel.yaw,   targetYaw)
    local angDamp = ply:GetNWBool("D6_FlightAssist", true) and 5 or 2.0
    ply._D6AngVel.pitch = Lerp(ft * angDamp, ply._D6AngVel.pitch, ply.D6TurnVel.pitch)
    ply._D6AngVel.yaw   = Lerp(ft * angDamp, ply._D6AngVel.yaw,   ply.D6TurnVel.yaw)
    Ang:RotateAroundAxis(Ang:Right(), ply._D6AngVel.pitch)
    Ang:RotateAroundAxis(Ang:Up(),    ply._D6AngVel.yaw)

    -- ─── [Descent] инерция крена: плавная раскрутка/останов ───
    local rollIn = 0
    if input.IsKeyDown(KEY_LSHIFT) then rollIn = rollIn - 1 end
    if input.IsKeyDown(KEY_F)      then rollIn = rollIn + 1 end
    RollVel = Lerp(ft * 5, RollVel, rollIn * ROLL_SPEED) -- было ft*8: крен инерционнее
    Ang:RotateAroundAxis(Ang:Forward(), RollVel * ft)

    Ang.r = math.Clamp(((Ang.r + 180) % 360) - 180, -ROLL_LIMIT, ROLL_LIMIT)

    cmd:SetViewAngles(Ang)
    ply.D6Ang = Ang

    -- ─── X-клавиша: рывок ───────────────────────────────────
    -- Читаем направление из текущего cmd (точные данные клиента).
    -- Отправляем только на переднем фронте нажатия.
    local xDown = input.IsKeyDown(KEY_X)
    if xDown and not XKeyDown then
        local input = D6_Mobility.Steering(cmd)
        net.Start("D6_DashDir")
            net.WriteInt(input.x, 4)
            net.WriteInt(input.y, 4)
            net.WriteInt(input.z, 4)
        net.SendToServer()
    end
    XKeyDown = xDown

    local now = RealTime()
    if now - LastSendT >= 1 / ANG_HZ then
        if math.abs(math.AngleDifference(Ang.p, LastAng.p)) > ANG_THRESH
        or math.abs(math.AngleDifference(Ang.y, LastAng.y)) > ANG_THRESH
        or math.abs(math.AngleDifference(Ang.r, LastAng.r)) > ANG_THRESH then
            net.Start("D6_AngSync"); net.WriteAngle(Ang); net.SendToServer()
            LastAng = Angle(Ang.p, Ang.y, Ang.r); LastSendT = now
        end
    end
end)

hook.Add("CalcView", "D6_Cam_CV", function(ply, pos, _, fov)
    if not IsValid(ply) or not ply:GetNWBool("D6On", false) or not Ang then return end
    local lagTarget = Vector(0, 0, 0)
    if ply:GetNWBool("D6AlwaysRun", false) then
        local fwdSpd = ply:GetVelocity():Dot(Ang:Forward())
        lagTarget = -Ang:Forward() * math.Clamp(fwdSpd / 800, 0, 5)
    end
    if Dashing then lagTarget = lagTarget - DashDir * 8 end
    CamLag = LerpVector(FrameTime() * 10, CamLag, lagTarget)
    local eye, clearance = D6_Arsenal.EyeClearance(ply, Ang, MASK_SOLID)
    local pivot = clearance.Hit and (clearance.HitPos + clearance.HitNormal*3) or eye - Ang:Forward()*2
    local origin = pivot + CamLag

    -- ── Micro-motion: реакторное покачивание корпуса ─────────────────
    -- Двухчастотное смещение ПОЗИЦИИ (не угла, не camera shake).
    -- Амплитуда пропорциональна скорости: ноль при стоянии, макс ~1.4ед на топ-скорости.
    -- Две частоты (8.3Hz + 11.7Hz) создают биение — ощущение работающего реактора.
    -- Направление смещения привязано к осям КОРПУСА, не мировым координатам.
    local spd_mm = ply:GetVelocity():Length()
    local mm_amp = math.Clamp(spd_mm / 1800, 0, 1) * 1.4
    if mm_amp > 0.05 then
        local t_mm  = CurTime() + ply:EntIndex() * 0.37   -- фаза уникальна для каждого игрока
        local drift = Ang:Right()   * math.sin(t_mm * 8.3)  * mm_amp
                    + Ang:Up()      * math.sin(t_mm * 11.7) * mm_amp * 0.55
        origin = origin + drift
    end

    -- ── Engine vibration (уже было, оставлено без изменений) ─────────
    local arOn   = ply:GetNWBool("D6AlwaysRun", false)
    local spd    = ply:GetVelocity():Length()
    local vibAmp = (arOn and 0.6 or 0.25) * math.Clamp(spd / 900, 0, 1)
    if vibAmp > 0.01 then
        local t   = CurTime()
        local vib = Ang:Right()   * math.sin(t * 61)
                  + Ang:Up()      * math.sin(t * 67)
                  + Ang:Forward() * math.sin(t * 53)
        origin = origin + vib * vibAmp
    end
    local brake = ply:GetNWBool("D6_AirBrake", false)
    local target = math.Clamp((spd - 1500)/1400, 0, 1)*3.3 + (Dashing and 5 or 0) - (brake and 2.7 or 0)
    CameraFOVKick = Lerp(math.min(FrameTime()*9, 1), CameraFOVKick, target)
    fov = fov + CameraFOVKick
    if ThirdPerson then
        local back = Ang:Forward() * -100 + Ang:Up() * 22
        local tr = util.TraceLine({start=pivot, endpos=origin+back, filter=ply, mask=MASK_SOLID})
        return { origin=tr.HitPos + tr.HitNormal*3, angles=Ang, fov=fov, drawviewer=true }
    end
    return { origin=origin, angles=Ang, fov=fov, drawviewer=false }
end)

hook.Add("PlayerButtonDown", "D6_CamSwitch", function(ply, key)
    if key ~= KEY_F5 or ply ~= LocalPlayer() then return end
    if not IsValid(ply) or not ply:GetNWBool("D6On", false) then return end
    ThirdPerson = not ThirdPerson
    chat.AddText(Color(160,40,255), "[6DOF] ", color_white,
        ThirdPerson and "Третье лицо" or "Первое лицо")
end)

-- =========================================================
-- ИНТЕРПОЛЯЦИЯ УГЛОВ ДРУГИХ ИГРОКОВ (для корректного вида)
-- =========================================================
hook.Add("Think", "D6_LerpRemoteAngs", function()
    local ft = FrameTime()
    for ply, data in pairs(Remote) do
        if not IsValid(ply) then Remote[ply] = nil; continue end
        if data.ang then
            data.angLerp = LerpAngle(ft * 14, data.angLerp or data.ang, data.ang)
            ply._D6AngLerp = data.angLerp
        end
    end
end)

-- =========================================================
-- Camera state stays local, the cockpit reads this small snapshot.
function D6_FlightHUDState()
    local ply = LocalPlayer()
    return {adhering = ply:GetNW2Int("D6_AdhesionEntity", -1) >= 0,
        braking = ply:GetNWBool("D6_AirBrake", false), dashing = Dashing, roll = Ang and Ang.r or 0}
end

function D6_DashVisual(ply)
    local state = Remote[ply]
    if not state or not state.dashTime then return end
    local elapsed = CurTime() - state.dashTime
    if elapsed < 0.33 then return elapsed, state.dashDir end
end

concommand.Add("d6_level", function()
    if Ang then
        Ang.r = 0
        RollVel = 0
    end
end)

net.Receive("D6_GateView", function()
    Ang = net.ReadAngle()
    LocalPlayer().D6Ang = Ang
    LastAng = Angle(Ang.p, Ang.y, Ang.r)
    CamLag = Vector()
    RollVel = 0
end)
