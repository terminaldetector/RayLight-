include("shared.lua")

local glow = Material("sprites/light_glow02_add")
local chargeInk = Color(255,178,89)

function ENT:Initialize()
    self:SetRenderBounds(Vector(-32,-32,-32),Vector(32,32,32))
end

function ENT:Draw()
    if not D6_Supports or not D6_Art then return end
    local def=D6_Supports.Definitions[self:GetNWString("D6_SupportKind","")]
    if not def then return end
    local power=self:GetNWFloat("D6_SupportPower",0)
    if def.model and self:GetModel() == def.model then
        self:DrawModel()
    else
        D6_Art.Draw(def.mesh,self:GetPos(),self:GetAngles(),1,def.color,0.22+0.48*power,true)
    end
    if def.id ~= "reflector" then return end
    local combat = self:GetNWString("D6_SupportCombat", "idle")
    local charged = combat == "charged_fire"
    local age = CurTime()-self:GetNWFloat("D6_SupportShotAt", -1)
    local flash = age >= 0 and math.max(0, 1-age/0.14) or 0
    if combat ~= "redirect" and not charged and flash == 0 then return end
    local port = self:GetNWInt("D6_SupportShotPort", 1)
    local position = D6_Supports.Socket(self, port)+self:GetForward()*0.4
    local ink = charged and chargeInk or def.color
    local size = (charged and 8 or 5) + 7*flash
    render.SetMaterial(glow)
    render.DrawSprite(position, size, size, Color(ink.r,ink.g,ink.b,58+120*flash))
end
