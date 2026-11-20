if not CLIENT then return end
local D, A = D6_Drones, D6_Arsenal
local entries = {}
local colors = {combine = Color(148,219,224), resistance = Color(217,167,115)}
local names = {
    assault="Средний штурмовик", mg="Дрон с парными пушками", laser="Лазерный дрон", interceptor="Лёгкий перехватчик",
    rpg="Ракетоносец", artillery="Дальняя артиллерия", rocket_elite_homing="Элитный ракетчик", rocket_elite_aa="Элитный зенитный дрон",
    grav="Грависканер", support="Ремонтный дрон", heavy="Тяжёлый плазмодрон", heavy_elite="Элитный бронедрон", seeker="Ловец",
    arc_elite="Элитный дуговой штурмовик",
    rocket_strider="Rocket Strider", plasma_strider="Плазменный страйдер", manhack_fast="Манхак", wheatley="Подрывной дрон",
    chopper="Летающая огневая платформа", worm="Наземный червь", mine="Минный дрон",
}
local payloads = {
    mine_plasma="Плазменная мина", mine_gravity="Гравитационная мина", mine_air="Воздушная мина",
    node_snare="Узел энергокапкана", node_dark="Полевой узел", shot_shell="Ударный снаряд",
    shot_cluster="Кассетная бомба", shot_homing="Управляемая ракета", shot_mega="Тяжёлая ракета",
    shot_shard="Осколок", shot_arcpulse="Плазменный болт", shot_ion="Ионное ядро",
    supply="Контейнер снабжения", salvage_ballast="Лом для гравиполя",
}
local tactics = {gravity="Собирает подвижный груз и распределяет его по сфере.", support="Держится за строем и чинит соседей.",
    rear="Держит дистанцию и стреляет через просветы строя.", flank="Смещается по высоте и заходит сбоку.", screen="Прикрывает ведущего и стреляет очередями."}
for key, name in pairs(D6_Session.Resistance) do names[key] = name end
for key, drone in pairs(D.Types) do
    local note=key=="arc_elite" and "Сводит два дуговых луча и сбрасывает раскалённые заряды." or tactics[drone.role]
    entries[#entries+1] = {key=key,kind="npc",name=names[key],mesh=drone.mesh,
        group=drone.faction=="resistance" and "Сопротивление" or "Альянс", color=colors[drone.faction], note=note or ""}
end
for _, item in ipairs(A.Order) do
    local family=A.Families[item.family]
    entries[#entries+1]={kind="weapon",name=item.name,group="Оружие",mesh=item.mesh,color=family.color,note=family.label}
end
for key, payload in pairs(A.Ordnance) do
    entries[#entries+1]={kind="payload",name=payloads[key],group="Заряды и снаряды",mesh=payload.mesh,color=payload.color}
end
table.sort(entries,function(a,b) if a.group==b.group then return a.name<b.name end return a.group<b.group end)

local frame
local function open()
    if IsValid(frame) then frame:MakePopup(); return end
    local width, height = math.min(983,ScrW()-36), math.min(640,ScrH()-38)
    frame=vgui.Create("DFrame")
    frame:SetSize(width,height)
    frame:SetTitle("DRMD 6DOF · Бестиарий")
    frame:Center()
    frame:MakePopup()
    local left=math.floor(width*.41)
    local tableView=frame:Add("DListView")
    tableView:SetPos(10,34)
    tableView:SetSize(left,height-45)
    tableView:SetMultiSelect(false)
    tableView:AddColumn("Модель")
    tableView:AddColumn("Раздел"):SetFixedWidth(math.min(116, left*.40))
    local selected=entries[1]
    local pane=frame:Add("DPanel")
    pane:SetPos(left+18,34)
    pane:SetSize(width-left-29,height-45)
    pane.Paint=function(self,w,h)
        local item=selected
        local ui=D6_Interface
        if not ui or not item then return end
        ui.Panel(0,0,w,h,Color(18,27,31,255))
        local x,y=self:LocalToScreen(2,2)
        local distance=item.kind=="npc" and 133 or (item.kind=="weapon" and 77 or 56)
        local camera=Vector(distance,-distance*.66,distance*.43)
        render.SetScissorRect(x,y,x+w-4,y+h-82,true)
        cam.Start3D(camera,(-camera):Angle(),43,x,y,w-4,h-82,1,512)
        cam.IgnoreZ(true)
        local turn=Angle(0,(RealTime()*34)%360,0)
        if item.kind=="npc" then D6_Art.DrawDrone(item.key,vector_origin,turn,.97,true,1)
        else D6_Art.Draw(item.mesh,vector_origin,turn,1,item.color,1,false) end
        cam.IgnoreZ(false)
        cam.End3D()
        render.SetScissorRect(0,0,0,0,false)
        ui.Text(item.name,"label",14,h-75,item.color)
        ui.Text(item.note or item.group,"tiny",14,h-42,Color(174,196,192))
    end
    tableView.OnRowSelected=function(_,_,row) selected=row.D6_Entry end
    for _,entry in ipairs(entries) do tableView:AddLine(entry.name,entry.group).D6_Entry=entry end
end
concommand.Add("d6_bestiary",open)
