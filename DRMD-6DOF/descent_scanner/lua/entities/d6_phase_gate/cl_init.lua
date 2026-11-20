include("shared.lua")

local glow = Material("sprites/light_glow02_add")
local line = Material("cable/blue_elec")
local inks = {Color(95, 226, 214), Color(255, 166, 94)}
local segments = 48
local ring = {}
for i = 0, segments do
    local a = i*math.pi*2/segments
    ring[i] = {math.cos(a), math.sin(a)}
end

function ENT:Initialize()
    self:SetRenderBounds(Vector(-8, -56, -66), Vector(8, 56, 66))
end

function ENT:DrawTranslucent()
    local origin = self:GetPos()
    local right, up = self:GetRight(), self:GetUp()
    local active = IsValid(self:GetLinkedGate())
    local ink = inks[self:GetPolarity()] or inks[1]
    local creation = self:GetEndsAt() - D6_Gates.lifetime
    local opening = math.Clamp((CurTime() - creation)*4, 0.14, 1)
    local fading = math.Clamp((self:GetEndsAt() - CurTime())*0.6, 0, 1)
    local pulse = math.sin(CurTime()*6)*0.12 + 0.88
    local prev
    render.SetMaterial(line)
    for i = 0, segments do
        local pos = origin + right*(ring[i][1]*D6_Gates.width*opening) + up*(ring[i][2]*D6_Gates.height*opening)
        if prev then
            local alpha = (active and 215 or 107)*fading*pulse
            render.DrawBeam(prev, pos, active and 2.5 or 1.2, 0, 1, Color(ink.r, ink.g, ink.b, alpha))
        end
        prev = pos
    end
    render.SetMaterial(glow)
    render.DrawSprite(origin, 112*opening, 127*opening, Color(ink.r, ink.g, ink.b, (active and 110 or 47)*fading))
    for i = 0, 5 do
        local step = (i*8 + math.floor(CurTime()*14)) % segments
        local pos = origin + right*(ring[step][1]*D6_Gates.width*opening)
            + up*(ring[step][2]*D6_Gates.height*opening)
        render.DrawSprite(pos, 7, 7, Color(ink.r, ink.g, ink.b, 145*fading))
    end
end
