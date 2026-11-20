local root = "../descent_scanner/lua/"
CLIENT = true
TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT = 0,1,2
TEXT_ALIGN_TOP = 3
TOP = 1
local canvasW, canvasH = tonumber(arg[1]) or 1600, tonumber(arg[2]) or 900
local page = arg[3] or "cockpit"
function ScrW() return canvasW end
function ScrH() return canvasH end
function IsValid(item) return type(item) == "table" and not item.closed end
function Color(r,g,b,a) return {r or 255,g or 255,b or 255,a or 255} end
function math.Clamp(x,a,b) return math.max(a, math.min(x,b)) end
function CurTime() return 14.8 end
function RealTime() return 8.5 end
local Vec = {}; Vec.__index = Vec
function Vector(x,y,z) return setmetatable({x=x,y=y,z=z}, Vec) end
function Vec.__unm(v) return Vector(-v.x,-v.y,-v.z) end
function Vec:Angle() return {} end
function Angle() return {} end
vector_origin = Vector(0,0,0)
local hooks = {}
hook = {Add = function(h,n,f) hooks[n] = f end}
concommand = {Add = function() end}

local commands, fonts = {}, {}
local ox, oy, clip = 0,0,nil
local function add(kind, fields)
    fields.kind = kind
    fields.clip = clip
    commands[#commands + 1] = fields
end

surface = {color = Color(255,255,255)}
function surface.CreateFont(name, options) fonts[name] = {size=options.size, weight=options.weight} end
function surface.SetDrawColor(col) surface.color = col end
function surface.DrawRect(x,y,w,h) add("rect",{x=x+ox,y=y+oy,w=w,h=h,color=surface.color}) end
function surface.DrawLine(a,b,c,d) add("line",{x=a+ox,y=b+oy,x2=c+ox,y2=d+oy,color=surface.color}) end
function surface.DrawPoly(points)
    local coords = {}
    for i, p in ipairs(points) do coords[i] = {p.x+ox,p.y+oy} end
    add("poly",{points=coords,color=surface.color})
end
draw = {NoTexture = function() end}
function draw.SimpleText(text,font,x,y,color,align,vertical)
    add("text",{text=text,font=font,x=x+ox,y=y+oy,color=color,align=align,vertical=vertical})
end

dofile(root .. "d6_arsenal.lua")
dofile(root .. "d6_interface.lua")
dofile(root .. "d6_hangar.lua")

local A, U = D6_Arsenal, D6_Interface
local mounts = A.Normalize()
local arsenal = {}
for _, item in ipairs(A.Order) do arsenal[item.class] = {GetClass=function() return item.class end} end
local ply = {
    GetWeapon=function(_, class) return arsenal[class] end, GetNWBool=function() return true end,
    IsAdmin=function() return true end, GetNW2Int=function() return 0 end,
    GetNW2String=function(_, key, fallback) return mounts[tonumber(key:match("(%d)$"))] or fallback end,
    GetActiveWeapon=function() return arsenal[D6_Arsenal.Defaults[4]] end,
}
function LocalPlayer() return ply end
D6_Session = {IsArena=function() return page ~= "campaign" end, CanEditWorld=function() return true end}
D6_Art = {Draw=function() end}
function RunConsoleCommand(cmd, slot, class)
    if cmd == "d6_mount_set" then assert(A.Assign(mounts, tonumber(slot), class)) end
end
local selection = 0
input = {SelectWeapon = function(wep) selection = wep:GetClass() end}
render = {SetScissorRect = function() end}
cam = {IgnoreZ=function() end, End3D=function() end}
function cam.Start3D(_,_,_,x,y,w,h)
    add("image",{x=x,y=y,w=w,h=h})
end

local Panel = {}; Panel.__index = Panel
local frame
local function panel(kind,parent)
    return setmetatable({kind=kind,parent=parent,children={},x=0,y=0,w=0,h=0},Panel)
end
function Panel:Add(kind) local p=panel(kind,self); self.children[#self.children+1]=p; return p end
function Panel:SetSize(w,h) self.w,self.h=w,h end
function Panel:SetPos(x,y) self.x,self.y=x,y end
function Panel:Center() self.x,self.y=(canvasW-self.w)/2,(canvasH-self.h)/2 end
function Panel:LocalToScreen(x,y)
    if self.parent then local px, py = self.parent:LocalToScreen(0,0); return self.x+x+px,self.y+y+py end
    return self.x+x,self.y+y
end
function Panel:SetText(t) self.text=t end
function Panel:SetFont(f) self.font=f end
function Panel:SetTextColor(c) self.textColor=c end
function Panel:SetTall(h) self.h=h end
function Panel:SetEnabled(isEnabled) self.enabled=isEnabled end
function Panel:IsEnabled() return self.enabled ~= false end
function Panel:IsHovered() return false end
function Panel:SetTitle() end
function Panel:ShowCloseButton() end
function Panel:MakePopup() end
function Panel:SetCursor() end
function Panel:GetVBar() return {btnGrip={}} end
function Panel:Dock() self.docked=true end
function Panel:DockMargin(_,_,right,bottom) self.marginR,self.marginB=right,bottom end
function Panel:Clear() self.children={} end
function Panel:Close() self.closed=true end
vgui = {Create=function(kind) frame=panel(kind); return frame end}

local function paint(p, parentClip)
    ox,oy=p:LocalToScreen(0,0)
    clip=parentClip
    if p.Paint then p:Paint(p.w,p.h) end
    if p.font and p.text and p.text ~= "" then
        draw.SimpleText(p.text,p.font,0,2,p.textColor,TEXT_ALIGN_LEFT,TEXT_ALIGN_TOP)
    end
    local y=0
    if p.kind=="DScrollPanel" then parentClip={ox,oy,p.w,p.h} end
    for _, child in ipairs(p.children) do
        if child.docked then
            child.x,child.y,child.w=0,y,p.w-child.marginR
            y=y+child.h+child.marginB
        end
        if not child.docked or child.y < p.h then paint(child,parentClip) end
    end
end

if page == "cockpit" or page == "beam" or page == "flight" or page=="episode" or page=="rogue" then
    local mountPalette = {}
    for i, class in ipairs(mounts) do mountPalette[i] = A.Families[A.Entries[class].family] end
    local state = {
        map="Полигон · арена",roll=-16,yaw=14,speed=846,warning="",assist=true,boost=false,
        hp=92,hpMax=100,shield=63,shieldMax=100,energy=78,energyMax=100,mounts=mountPalette,active=4,
        weapon="Гравирельс",weaponGroup="Ускоритель",accent=A.Families.rail.color,weaponStatus="Объект захвачен",
        charge=0.74,dash=0.63,kick=0.22,trial="Волна 4 / 4   ·   Тяжёлая группа Альянса",drift={-0.53,-0.4},damage=0,
    }
    if page == "beam" then
        state.weapon, state.weaponGroup, state.weaponStatus = "Гиперлуч", "Оптика", "Гиперлуч активен"
        state.energy, state.mounts[4], state.accent, state.trial = 53, A.Families.optic, A.Families.optic.color, ""
        state.charge, state.kick, state.speed, state.warning = 0, 0.66, 424, ""
    elseif page == "flight" then
        state.energy, state.speed, state.warning, state.trial = 66, 2590, "Сцепление активно", ""
        state.roll, state.charge, state.kick, state.weaponStatus = -31, 0, 0, "К стрельбе готово"
    elseif page == "episode" then
        state.map, state.order, state.deadline = "Реакторный отсек", "РАСПАД · Эвакуационный шлюз", 38.1
        state.trial, state.warning, state.charge = "", "", 0
    elseif page == "rogue" then
        state.trial, state.warning, state.charge = "Забег 38271 · Волна 3 / 5", "", 0
        state.hp,state.shield,state.energy = 89,47,65
    end
    U.PaintHUD(canvasW, canvasH, state)
    if page=="rogue" then
        local scale=U.Scale(canvasW,canvasH)
        local w,h=math.min(canvasW-38,491*scale),290*scale
        local x,y=(canvasW-w)*.5,(canvasH-h)*.5
        ox,oy=x,y
        U.PaintDraft(w,h,scale,38271,3)
        U.Text("×","label",w-36*scale,32.5*scale,U.colors.muted,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
        local cards={
            {name="Конденсатор",note="+20 к пределу энергии и +20 к запасу"},
            {name="Ремонтные пластины",note="+24 к пределу корпуса и ремонт 24 единиц"},
            {name="Векторные сопла",note="+15% к набору скорости"},
        }
        for i,card in ipairs(cards) do
            ox,oy=x+19*scale,y+(90+(i-1)*61)*scale
            U.PaintUpgrade(w-38*scale,54*scale,scale,card,i==1)
        end
    end
else
    D6_Hangar.Open()
    assert(frame and frame.w <= canvasW-20 and frame.h <= canvasH-20, "frame fits viewport")
    paint(frame)
    if page ~= "campaign" then
        local original = mounts[4]
        local list
        for _, p in ipairs(frame.children) do if p.kind == "DScrollPanel" then list=p end end
        assert(list and #list.children == #A.Order - 2)
        list.children[1].DoClick()
        assert(mounts[4] == A.Order[1].class and mounts[1] == original, "mounts swap")
        local mineCard = frame.children[6]
        mineCard.DoClick()
        assert(#list.children == 2, "mine bay exposes only mine systems")
        list.children[2].DoClick()
        assert(selection == "weapon_d6_gravmine" and mounts[5] == "weapon_d6_plasmamine", "fixed section supports alternative mines")
    end
end

for _, cmd in ipairs(commands) do
    if cmd.kind == "rect" or cmd.kind == "image" then
        assert(cmd.x > -1 and cmd.x + cmd.w <= canvasW+1 and cmd.y > -1 and cmd.y+cmd.h <= canvasH+16, "layout bounds")
    end
end

local function json(value)
    if type(value)=="string" then return string.format("%q",value) end
    if type(value)=="number" then return string.format("%.4f",value) end
    local items={}
    if value[1] ~= nil then
        for _, v in ipairs(value) do items[#items+1]=json(v) end
        return "[" .. table.concat(items,",") .. "]"
    end
    for key,v in pairs(value) do items[#items+1]=json(key)..":"..json(v) end
    return "{" .. table.concat(items,",") .. "}"
end
local out = io.open(page.."-"..canvasW..".json", "w")
out:write(json({cmds=commands,fonts=fonts,w=canvasW,h=canvasH}))
out:close()
print("PASS | "..page.." | "..canvasW.."×"..canvasH.." | "..#commands.." paint operations")
