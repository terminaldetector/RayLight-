"""Build the editable Abaddon maps with srctools."""
import argparse
import json
from pathlib import Path

from srctools import Vec
from srctools.vmf import Output, Side, Solid, UVAxis, VMF

CONCRETE = 'concrete/concretewall001a'
FLOOR = 'concrete/concretefloor001a'
METAL = 'metal/metalwall048a'
BRICK = 'brick/brickwall001a'
TRIGGER = 'tools/toolstrigger'
SKY = 'tools/toolsskybox'
NODRAW = 'tools/toolsnodraw'
REACTOR_PLATE = 'metal/metalcombine002'
REACTOR_BEAM = 'metal/metalcombine001'
REACTOR_CAGE = 'metal/metalwall_combinecore03a'
COOL_STRIP = 'lights/blue001'
ALARM_STRIP = 'lights/hazzardred001a'
SCRIPTED_DOOR = 32 | 512  # Toggle, NPCs cannot open. No player-use or touch flag.


class Map:
    def __init__(self, name, sky='sky_day01_01'):
        self.name = name
        self.vmf = VMF()
        self.vmf.spawn['skyname'] = sky
        self.vmf.spawn['detailmaterial'] = 'detail/detailsprites'
        self.brushes = []

    def box(self, lo, hi, material, owner=None):
        shape = self.vmf.make_prism(Vec(*lo), Vec(*hi), material)
        if owner is None:
            self.vmf.add_brush(shape.solid)
        else:
            owner.solids.append(shape.solid)
        if material not in {TRIGGER, NODRAW, SKY}:
            self.brushes.append((lo, hi, material))
        return shape.solid

    def ent(self, cls, pos=None, name=None, **fields):
        if pos is not None:
            fields['origin'] = ' '.join(map(str,pos))
        if name is not None:
            fields['targetname'] = name
        return self.vmf.create_ent(cls, **{k:str(v) for k,v in fields.items()})

    def event(self, sender, event, to, action='Trigger', value='', delay=0, times=-1):
        sender.outputs.append(Output(event,to,action,str(value),delay=delay,times=times))

    def relay(self, name, pos):
        return self.ent('logic_relay',pos,name)

    def gate(self, cls, name, lo, hi, start_disabled=False, **props):
        ent = self.ent(cls, name=name, spawnflags='1', StartDisabled='1' if start_disabled else '0', **props)
        self.box(lo,hi,TRIGGER,ent)
        return ent

    def endpoint(self, name, pos):
        return self.ent('info_target',pos,name)

    def extrude(self, outline, bottom, top, material):
        """Make a convex brush from a counter-clockwise XY footprint."""
        low = [Vec(x, y, bottom) for x, y in outline]
        high = [Vec(x, y, top) for x, y in outline]
        flat = {'mat': material, 'uaxis': UVAxis(1, 0, 0), 'vaxis': UVAxis(0, -1, 0)}
        faces = [Side(self.vmf, low[:3], **flat), Side(self.vmf, high[:3][::-1], **flat)]
        for i, point in enumerate(low):
            following = low[(i+1) % len(low)]
            axis = (following - point).norm()
            faces.append(Side(self.vmf, [following, point, high[i]], mat=material,
                              uaxis=UVAxis(axis.x, axis.y, 0), vaxis=UVAxis(0, 0, -1)))
        self.vmf.add_brush(Solid(self.vmf, sides=faces))

    def shell(self, lo, hi, open_sky=False):
        x0,y0,z0=lo
        x1,y1,z1=hi
        self.box((x0-48,y0-48,z0-48),(x1+48,y1+48,z0),FLOOR)
        self.box((x0-48,y0-48,z1),(x1+48,y1+48,z1+48),SKY if open_sky else METAL)
        self.box((x0-48,y0-48,z0),(x0,y1+48,z1),CONCRETE)
        self.box((x1,y0-48,z0),(x1+48,y1+48,z1),CONCRETE)
        self.box((x0,y0-48,z0),(x1,y0,z1),BRICK if open_sky else METAL)
        self.box((x0,y1,z0),(x1,y1+48,z1),BRICK if open_sky else METAL)

    def wall_x(self, x, half, bottom, top, gap_low, gap_high, floor, ceiling, texture=METAL):
        self.box((x,-half,bottom),(x+28,gap_low,top),texture)
        self.box((x,gap_high,bottom),(x+28,half,top),texture)
        if floor>bottom:
            self.box((x,gap_low,bottom),(x+28,gap_high,floor),texture)
        if ceiling<top:
            self.box((x,gap_low,ceiling),(x+28,gap_high,top),texture)

    def text(self,name,message,pos=(128,0,96),color='176 218 209',hold='4'):
        return self.ent('game_text',pos,name,message=message,holdtime=hold,fadein='.25',fadeout='.85',channel='1',
                        x='0.05',y='0.16',color=color,color2='226 179 99')

    def light(self,pos,rgba='192 220 217 480'):
        self.ent('light',pos,_light=rgba)

    def model(self,name,pos,mesh,angle='0 0 0',**fields):
        return self.ent('prop_dynamic_override',pos,name,model=f'models/drmd/{mesh}.mdl',solid='0',angles=angle,**fields)

    def flyby(self,name,origin,mesh,scale,yaw,travel,trigger):
        x,y,z=origin
        rail=self.ent('func_movelinear',origin,name+'_rail',movedir=f'0 {travel} 0',
                      movedistance='275',speed='116',blockdamage='0')
        self.box((x-3,y-3,z-3),(x+3,y+3,z+3),NODRAW,rail)
        self.model(name,origin,mesh,f'0 {yaw} 0',parentname=rail['targetname'],modelscale=scale)
        self.relay(name+'_sighting',origin)
        self.event(trigger,'OnStartTouch',name+'_sighting')
        self.event(trigger,'OnStartTouch',rail['targetname'],'Open')

    def laser(self,name,pos,finish,lo,hi,damage=15,start_disabled=False):
        self.endpoint(name+'_a',pos)
        self.endpoint(name+'_b',finish)
        beam=self.ent('env_beam',pos,name+'_beam',LightningStart=name+'_a',LightningEnd=name+'_b',
            texture='sprites/laserbeam.spr',rendercolor='245 91 57',renderamt='196',BoltWidth='4',NoiseAmplitude='.5',
            life='0',StrikeTime='0',spawnflags='0' if start_disabled else '1',damage='0')
        hurt=self.gate('trigger_hurt',name+'_hurt',lo,hi,start_disabled,damage=str(damage),damagecap=str(damage*2),damagetype='256')
        return beam,hurt

    def write(self,directory):
        with (directory/f'{self.name}.vmf').open('w',encoding='utf-8') as file:
            self.vmf.export(file)


def city():
    m=Map('d6_city17_drain')
    m.shell((0,-896,-544),(4864,896,832),True)
    m.box((0,-896,-64),(2928,896,0),FLOOR)
    m.box((2928,-896,-448),(3728,-230,0),BRICK)
    m.box((2928,230,-448),(3728,896,0),BRICK)
    for step in range(12):
        x=2928+step*64
        m.box((x,-230,-448),(x+64,230,-32*(step+1)),CONCRETE)
    m.box((3696,-896,-448),(4864,896,-384),FLOOR)
    m.box((3696,-896,-384),(4864,-274,832),BRICK)
    m.box((3696,274,-384),(4864,896,832),BRICK)
    m.box((3700,-274,-75),(4864,274,832),METAL)
    m.wall_x(672,896,0,832,-172,172,0,244,CONCRETE)
    m.wall_x(2534,896,0,832,-215,215,0,310,BRICK)
    for i in range(5):
        x=894+i*280
        for s in (-1,1):
            y=354*s
            m.box((x-78,y-68,0),(x+79,y+68,216+(i%3)*95),BRICK if i%2 else CONCRETE)
            m.box((x-86,y-76,210),(x+87,y+76,228),METAL)
    for x,y,wide in [(385,-183,52),(486,181,72),(1218,-94,74),(1696,132,81),(2010,-154,84),(2370,94,72)]:
        m.box((x-wide,y-48,0),(x+wide,y+48,70),METAL)
    for x in [3860,4140,4390,4660]:
        for s in (-1,1):
            y=s*224
            m.box((x-20,y-26,-384),(x+20,y+26,-75),CONCRETE)
        m.light((x,0,-100),'190 192 178 480')
    for x in [254,520,1020,1540,2040,2450,2770,3150,3520]:
        m.light((x,42,240 if x<2928 else -60),'195 214 222 615')
    m.ent('light_environment',(1080,0,625), angles='35 22 0', pitch='-50', _light='197 214 228 380',_ambient='153 172 189 150')
    m.ent('info_player_start',(172,0,12),angles='0 0 0')
    m.ent('info_landmark',(4668,0,-340),'d6_drain_link')
    m.ent('weapon_smg1',(316,-104,30),'d6_ground_primary')
    m.ent('weapon_rpg',(1018,-206,21),'d6_ground_rpg')
    for x in [1070,1360,1720,2270]:
        m.ent('item_rpg_round',(x,184,23))
    for x,y,z in [(308,110,22),(1124,-189,22),(1716,238,21),(3920,-145,-350),(4400,152,-350)]:
        m.ent('item_ammo_smg1',(x,y,z))
    for x,z in [(410,20),(1460,30),(2210,20),(4010,-362),(4430,-359)]:
        m.ent('item_healthkit',(x,-137,z))
        m.ent('item_battery',(x,137,z))
    for x in range(260,2850,150):
        for y in (-210,0,210):
            m.ent('info_node',(x,y,15))
    for x in range(3820,4710,146):
        m.ent('info_node',(x,0,-367))
        m.ent('info_node_air',(x,38,-196))
    for i in range(8):
        m.ent('npc_citizen',(405+(i%4)*58,(-1)**i*(148+(i//4)*74),11),f'd6_citizen_{i+1}',citizentype='1')
    m.endpoint('d6_crowd_shelter',(338,-363,13))
    for x in (396,452,510):
        m.ent('prop_physics',(x,53,30),model='models/props_c17/furniturechair001a.mdl')
    for i,(x,y) in enumerate([(858,-251),(977,196),(1440,213),(1954,-173),(2326,78)]):
        cls='npc_metropolice' if i<2 else 'npc_combine_s'
        m.ent(cls,(x,y,13),additionalequipment='weapon_smg1',angles='0 180 0')
    m.ent('npc_strider',(1440,-312,25),'d6_strider_street',angles='0 180 0')
    m.ent('npc_strider',(2278,293,25),'d6_strider_square',angles='0 180 0')
    m.ent('npc_helicopter',(2243,460,510),'d6_helicopter_outer',angles='0 180 0',spawnflags='4')
    for i in range(3):
        m.ent('npc_manhack',(3870+i*152,(-1)**i*93,-200),f'd6_drain_manhack_{i+1}')
    for x,y,z in [(1887,-74,24),(4130,169,-358),(4274,-176,-356)]:
        m.ent('prop_physics',(x,y,z),model='models/props_c17/oildrum001_explosive.mdl')
    m.text('d6_radio_text','DIRECTIVE 04 // DISPERSE THE STATION PROTEST')
    m.text('d6_city_title','HALF-LIFE: ABADDON // CITY 17',color='176 217 227',hold='3')
    m.text('d6_emp_text','LOCAL OVERRIDE // PRIORITY TABLE LOST',color='240 168 107')
    m.text('d6_sewer_text','MAINTENANCE CHANNEL // REACTOR ACCESS AHEAD')
    auto=m.ent('logic_auto',(128,0,96))
    m.event(auto,'OnMapSpawn','d6_city_title','Display',delay=.40)
    m.event(auto,'OnMapSpawn','d6_radio_text','Display',delay=3.5)
    m.ent('ambient_generic',(578,0,89),'d6_dispersal_siren',message='ambient/alarms/klaxon1.wav',health='6',spawnflags='49')
    orders=m.relay('d6_protest_order',(392,0,73))
    m.event(orders,'OnTrigger','d6_dispersal_siren','PlaySound')
    m.event(orders,'OnTrigger','d6_dispersal_siren','StopSound',delay=2.8)
    m.event(m.gate('trigger_once','d6_protest_path',(349,-431,0),(429,429,186)),'OnStartTouch','d6_protest_order')
    emp=m.relay('d6_emp',(625,32,96))
    m.ent('env_shake',(599,0,132),'d6_emp_shake',amplitude='4',frequency='28',duration='1.3',radius='750',spawnflags='8')
    m.ent('env_fade',(603,24,144),'d6_emp_flash',duration='.28',holdtime='.16',renderamt='186',rendercolor='187 229 244',spawnflags='0')
    m.event(emp,'OnTrigger','d6_emp_shake','StartShake')
    m.event(emp,'OnTrigger','d6_emp_flash','Fade')
    m.event(emp,'OnTrigger','d6_emp_text','Display',delay=.55)
    emp_trigger=m.gate('trigger_once','d6_emp_path',(549,-433,0),(671,432,245))
    m.event(emp_trigger,'OnStartTouch','d6_emp')
    m.flyby('d6_city_enforcer',(1135,-378,365),'combine_elite','4.2',157,90,
            m.gate('trigger_once','d6_city_enforcer_path',(719,-428,0),(810,434,225)))
    m.flyby('d6_city_arc',(2139,379,316),'combine_arc_elite','5.3',209,-90,
            m.gate('trigger_once','d6_city_arc_path',(1685,-470,0),(1750,468,267)))
    beam,hurt=m.laser('d6_drain_laser',(4120,-224,-257),(4120,225,-257),
        (4109,-226,-268),(4135,226,-246),18)
    m.event(m.gate('trigger_once','d6_drain_entry',(3750,-226,-385),(3830,226,-82)),
            'OnStartTouch','d6_sewer_text','Display')
    m.relay('d6_city_transfer',(4544,0,-132))
    m.event(m.gate('trigger_once','d6_city_transfer_path',(4500,-224,-384),(4552,224,-90)),
            'OnStartTouch','d6_city_transfer')
    transition=m.ent('trigger_changelevel',name='d6_city_exit',map='d6_reactor_escape',landmark='d6_drain_link',spawnflags='0')
    m.box((4580,-220,-384),(4820,220,-90),TRIGGER,transition)
    return m


def shaft_ring(m, x, y, radius, rim, z, height):
    # Sector joints create a walkable inspection deck and hold the clamp housings.
    def perimeter(size):
        corner = round(size * .43)
        return [(x + a, y + b) for a, b in (
            (size, corner), (corner, size), (-corner, size), (-size, corner),
            (-size, -corner), (-corner, -size), (corner, -size), (size, -corner))]
    outer, inner = perimeter(radius), perimeter(radius-rim)
    for i in range(8):
        j = (i+1) % 8
        sector = [outer[i], outer[j], inner[j], inner[i]]
        m.extrude(sector, z, z+height, REACTOR_BEAM if i % 2 else REACTOR_PLATE)


def shaft_fixtures(m, center, radius, top, bottom, decks):
    x, y, z = center
    for deck in decks:
        shaft_ring(m, x, y, radius, 108, deck, 54)
        shaft_ring(m, x, y, radius+16, 18, deck+21, 8)
        for side in (-1, 1):
            m.box((x-164,y+side*(radius-98)-6,deck-6),
                  (x+164,y+side*(radius-98)+6,deck+14), COOL_STRIP)
    for side in (-1, 1):
        sx = x+side*(radius-61)
        for far in (-1, 1):
            sy = y+far*(radius-122)
            m.box((sx-38,sy-49,bottom),(sx+38,sy+49,top), REACTOR_CAGE)
            m.box((sx-50,sy-63,bottom+32),(sx+50,sy+63,bottom+79), REACTOR_PLATE)
            m.box((sx-57,sy-74,top-93),(sx+57,sy+74,top-36), REACTOR_PLATE)
        sx = x+side*67
        m.box((sx-8,y-29,z+174),(sx+8,y+29,top), REACTOR_BEAM)
    m.box((x-68,y-70,z+175),(x+68,y+70,top), REACTOR_CAGE)
    m.box((x-111,y-109,top-86),(x+111,y+109,top-44), REACTOR_PLATE)
    m.box((x-74,y-76,bottom),(x+74,y+76,z-175), REACTOR_CAGE)
    m.box((x-98,y-96,z-201),(x+98,y+96,z-175), REACTOR_PLATE)
    m.box((x-103,y-99,z-183),(x+103,y-92,z-177), ALARM_STRIP)
    m.box((x-103,y+92,z-183),(x+103,y+99,z-177), ALARM_STRIP)
    for level,palette in [(z-118,'232 111 75 420'),(z+226,'100 168 238 680')]:
        m.light((x-194,y,level),palette)
        m.light((x+210,y,level),palette)


def reactor_landmarks(m, center, coolants, hazards, goal):
    m.endpoint('d6_reactor_center', center)
    m.endpoint('d6_reactor_escape_goal', goal)
    for i, (x,y,z) in enumerate(coolants, start=1):
        m.endpoint(f'd6_reactor_coolant_{i}', (x,y,z))
        # Connect each suspended exchanger to a separate service shelf.
        m.box((x-93,y-92,z-104),(x+93,y+92,z-79), REACTOR_PLATE)
        m.box((x-29,y-27,z-79),(x+29,y+27,z-63), REACTOR_BEAM)
        m.box((x-71,y-97,z-94),(x+71,y-91,z-83), COOL_STRIP)
        m.box((x-71,y+91,z-94),(x+71,y+97,z-83), COOL_STRIP)
        m.light((x,y,z+126),'88 153 221 400')
    for name, pos, angles in hazards:
        m.ent('info_target',pos,f'd6_reactor_hazard_{name}',angles=angles)


def reactor():
    m=Map('d6_reactor_escape')
    m.shell((0,-1088,-128),(6592,1088,1536))
    m.box((0,-1088,-60),(6592,1088,0),FLOOR)
    m.wall_x(912,1088,0,1536,-184,184,0,448)
    m.wall_x(2960,1088,0,1536,-332,332,0,1090)
    m.wall_x(4864,1088,0,1536,-199,199,0,646)
    for i in range(10):
        x=1210+i*351
        side=-1 if i%2==0 else 1
        y=side*(590+(i%3)*110)
        top=340+(i%4)*178
        m.box((x-86,y-90,0),(x+86,y+90,top),METAL)
        m.box((x-117,y-116,top),(x+117,y+116,top+25),CONCRETE)
    for x,y,z in [(1720,-360,350),(2050,390,685),(2470,-318,917),(3230,440,470),(3610,-480,818),(5280,300,514),(5740,-317,783)]:
        m.box((x-130,y-88,z),(x+142,y+93,z+39),METAL)
    for x in [325,700,1160,1690,2120,2520,3190,3590,4020,4460,4780,5300,5960,6370]:
        m.light((x,0,294),'148 200 212 651')
        m.light((x,497,997),'200 210 200 401')
    for x in [3460,4250,4920,5760]:
        m.light((x,-322,390),'245 101 59 480')
    m.ent('info_player_start',(176,0,12),angles='0 0 0')
    m.ent('info_landmark',(176,0,48),'d6_drain_link')
    for x in range(290,6470,210):
        m.ent('info_node',(x,96,15))
        for z in (158,459,805):
            m.ent('info_node_air',(x,(-1)**(x//210)*190,z))
    m.ent('weapon_357',(372,-113,21))
    m.ent('weapon_shotgun',(561,118,28))
    m.ent('weapon_ar2',(1360,-198,31))
    for x in [539,1370,2520,3450,5170,5980]:
        m.ent('item_battery',(x,-125,25))
        m.ent('item_healthkit',(x,125,24))
    for i,(x,y,z) in enumerate([(1220,-271,168),(1517,295,360),(2450,-445,699),(3340,450,498),(5100,-240,471)]):
        m.ent('npc_cscanner',(x,y,z),f'd6_native_air_{i+1}')
    for i in range(3):
        m.ent('npc_manhack',(1680+i*135,134,119),f'd6_native_cutter_{i+1}')
    for x,y in [(1470,-333),(3060,180),(3440,-125),(5400,192)]:
        m.ent('npc_combine_s',(x,y,11),additionalequipment='weapon_ar2',angles='0 180 0')
    for i in range(3):
        m.ent('prop_physics',(2650+i*112,-138,24),model='models/props_c17/oildrum001_explosive.mdl')
    for name,pos in {'d6_swarm_1':(1490,-287,428),'d6_swarm_2':(1690,81,665),
            'd6_swarm_3':(1930,364,490),'d6_swarm_4':(2170,-310,318),'d6_swarm_5':(2410,143,826),
            'd6_guard_1':(3760,-545,592),'d6_guard_2':(4220,536,735),'d6_guard_3':(4510,-485,623),
            'd6_enforcer_boss':(2418,62,535),'d6_enforcer_support':(2532,-156,565),
            'd6_arc_boss':(4272,120,642),'d6_arc_support':(4445,260,650),
            'd6_charge_1':(573,108,110),'d6_charge_2':(3407,-212,258),'d6_exit_zone':(6362,0,250)}.items():
        m.endpoint(name,pos)
    for name,pos in {
        'battery_1':(732,136,114),'battery_2':(2110,390,748),'battery_3':(5380,270,583),
        'ammo_1':(1295,-288,226),'ammo_2':(3430,435,544),'ammo_3':(5701,-316,866),
        'repair_1':(2530,-322,979),'repair_2':(4617,-240,306),
        'module_hyperbeam':(2538,-421,804),'module_homing':(1675,-362,429),
        'module_gravmine':(3310,525,542),'module_railmk2':(3660,-467,894),
    }.items():
        m.endpoint('d6_supply_'+name,pos)
    m.wall_x(1456,1088,0,1536,-620,198,112,894,CONCRETE)
    m.wall_x(2688,1088,0,1536,-332,492,450,1160,METAL)
    m.model('d6_sentry_relic',(682,-238,108),'grav','0 17 0')
    m.model('d6_sentry_gimbal',(682,-238,108),'grav_gimbal','22 90 44')
    for i,(x,y,z) in enumerate([(3635,-430,441),(4440,437,730)],start=1):
        name=f'd6_regulator_{i}'
        node=m.ent('func_breakable',name=name,health='74',material='2',spawnflags='512')
        m.box((x-22,y-22,z-29),(x+22,y+22,z+29),METAL,node)
        hardware=m.model(name+'_cage',(x-16,y,z),'grav_gimbal','0 180 20',modelscale='1.7')
        spark=m.ent('env_spark',(x,y,z),name+'_spark',Magnitude='2',TrailLength='1')
        relay=m.relay(name+'_broken',(x,y,z))
        m.event(node,'OnBreak',relay['targetname'])
        m.event(relay,'OnTrigger',hardware['targetname'],'Kill')
        m.event(relay,'OnTrigger',spark['targetname'],'SparkOnce')
        m.light((x-30,y,z),'101 205 225 369')
    m.text('d6_reactor_intro_text','REACTOR MAINTENANCE // THERMAL INTERLOCK ACTIVE')
    m.text('d6_reactor_failure_text','CONTAINMENT LOST // FIND THE EVACUATION SHAFT',color='246 128 80',hold='5')
    m.text('d6_reactor_exit_text','EXIT FOUND // NEURAL PRIORITIES SAVED',hold='6')
    m.event(m.ent('logic_auto',(176,0,80)),'OnMapSpawn','d6_reactor_intro_text','Display',delay=1)
    swarm=m.relay('d6_swarm_enter',(1164,0,175))
    m.event(m.gate('trigger_once','d6_swarm_trigger',(1100,-915,0),(1180,915,1380)),'OnStartTouch','d6_swarm_enter')
    m.event(m.gate('trigger_once','d6_guard_trigger',(3200,-900,0),(3290,900,1380)),'OnStartTouch','d6_guard_enter')
    m.relay('d6_guard_enter',(3240,0,190))
    m.laser('d6_service_laser',(1980,-385,219),(1980,385,219),(1969,-385,208),(1991,385,231),21)
    m.laser('d6_service_laser_b',(2550,0,91),(2550,0,880),(2539,-11,91),(2562,11,880),23)
    for x,y in [(2304,-264),(2750,216),(4268,-400)]:
        m.model('d6_mine_display',(x,y,136),'mine_air')
    center=(3944,0,420)
    shaft_fixtures(m,center,512,1536,0,(173,1204))
    reactor_landmarks(m,center,[(3456,-704,260),(4512,712,1102),(4320,-625,718)],[
        (1,(3624,-936,625),'0 90 0'),
        (2,(4534,939,493),'0 270 0'),
        (3,(3298,221,1136),'0 0 0'),
        ('escape_1',(5568,-543,402),'0 90 0'),
        ('escape_2',(5940,582,669),'0 270 0'),
    ],(6310,0,430))
    for x in (3352,4230,4756):
        for y in (-1030,1030):
            m.box((x-86,y-44,232),(x+86,y+44,1380),REACTOR_CAGE)
            m.box((x-113,y-51,534),(x+113,y+51,553),COOL_STRIP)
            m.box((x-113,y-51,1004),(x+113,y+51,1023),COOL_STRIP)
    # Offset shield fins leave both the low maintenance circuit and the upper flyway open.
    for x0,y0,z0,x1,y1,z1 in [
        (3320,-1088,302,3360,-671,832), (4650,653,576,4692,1088,1048),
        (5488,-1088,121,5532,-588,664), (5820,576,476,5864,1088,1204),
    ]:
        m.box((x0,y0,z0),(x1,y1,z1),REACTOR_PLATE)
        m.box((x0-4,y0,z1),(x1+4,y1,z1+13),REACTOR_BEAM)
    core=m.ent('func_breakable',name='d6_reactor_core',health='245',material='2',spawnobject='0',spawnflags='512')
    m.box((3881,-63,366),(4007,63,474),REACTOR_CAGE,core)
    fail=m.relay('d6_core_failure',(3970,0,400))
    m.event(core,'OnBreak','d6_core_failure')
    m.ent('env_shake',(3980,0,167),'d6_core_shake',amplitude='7',frequency='28',duration='4',radius='3500',spawnflags='8')
    m.ent('env_explosion',center,'d6_core_blast',iMagnitude='88',spawnflags='1')
    m.ent('ambient_generic',(4040,0,283),'d6_alarm',message='ambient/alarms/klaxon1.wav',health='6',spawnflags='17')
    m.event(fail,'OnTrigger','d6_reactor_failure_text','Display')
    m.event(fail,'OnTrigger','d6_core_shake','StartShake')
    m.event(fail,'OnTrigger','d6_core_blast','Explode')
    m.event(fail,'OnTrigger','d6_alarm','PlaySound')
    exit_beam,exit_hurt=m.laser('d6_collapse_laser',(5350,-390,273),(5350,390,273),
        (5340,-390,264),(5360,390,285),26,True)
    m.event(fail,'OnTrigger',exit_beam['targetname'],'TurnOn',delay=.45)
    m.event(fail,'OnTrigger',exit_hurt['targetname'],'Enable',delay=.45)
    door=m.ent('func_door',name='d6_escape_door',movedir='-90 0 0',speed='232',lip='0',wait='-1',spawnflags=SCRIPTED_DOOR)
    m.box((4870,-197,0),(4912,197,639),METAL,door)
    m.event(fail,'OnTrigger','d6_escape_door','Open',delay=.65)
    done=m.relay('d6_escape_complete',(6260,0,450))
    m.event(done,'OnTrigger','d6_reactor_exit_text','Display')
    exit_zone=m.gate('trigger_once','d6_escape_trigger',(6178,-298,0),(6420,298,1350),True)
    m.event(fail,'OnTrigger','d6_escape_trigger','Enable')
    m.event(exit_zone,'OnStartTouch','d6_escape_complete')
    return m


def rogue_reactor():
    m=Map('d6_rogue_reactor')
    m.shell((0,-1024,0),(3736,1024,2176))
    # Service hangar has a straight lower access and a slower, covered ramp in the upper wall.
    m.box((181,-286,0),(614,286,397), REACTOR_BEAM)
    m.box((170,-300,397),(624,300,407), REACTOR_PLATE)
    m.box((550,-295,407),(624,-282,416), COOL_STRIP)
    m.box((550,282,407),(624,295,416), COOL_STRIP)
    m.ent('info_player_start',(416,0,416),angles='0 0 0')
    for y in (-164, 164):
        m.ent('info_player_start',(416,y,416),angles='0 0 0')
    m.endpoint('d6_rogue_reactor_entry',(416,0,416))
    # Partition at x=832, with an offset upper bypass and a wider lower throat.
    for y0,y1,z0,z1 in (
        (-1024,-675,0,2176), (700,1024,0,2176),
        (-675,700,0,280), (-675,-545,280,708), (570,700,280,708),
        (-675,700,708,1120), (-675,206,1120,1508),
        (-675,700,1508,2176),
    ):
        m.box((818,y0,z0),(866,y1,z1), REACTOR_PLATE)
    for y,z in [(-542,472),(566,472),(208,1232),(694,1232)]:
        m.box((806,y-6,z),(872,y+6,z+144), COOL_STRIP)
    m.box((328,482,890),(791,769,925), REACTOR_CAGE)
    m.box((116,-820,0),(354,-646,861), REACTOR_CAGE)
    m.light((641,0,580),'127 177 213 640')
    m.light((578,503,1220),'123 156 218 620')
    center=(1888,0,1024)
    shaft_fixtures(m,center,410,2176,0,(330,1696))
    reactor_landmarks(m,center,[(1344,-435,550),(2210,514,939),(1616,-490,1482)],[
        (1,(1290,-916,683),'0 90 0'),
        (2,(2434,910,863),'0 270 0'),
        (3,(978,144,1310),'0 0 0'),
        ('escape_1',(2548,-740,1737),'0 90 0'),
        ('escape_2',(3330,873,1905),'0 270 0'),
    ],(3456,520,1888))
    # The fins provide real brush cover while leaving passages over, under and beside them.
    for x0,y0,z0,x1,y1,z1 in [
        (1108,-1024,258,1149,-612,935),
        (1452,544,647,1500,1024,1307),
        (2320,-1024,429,2364,-544,1040),
        (2452,393,978,2500,1024,1475),
        (2674,-1024,1162,2723,-244,1516),
        (2652,674,341,2696,1024,838),
        (3169,-1024,1122,3215,217,1962),
        (3176,794,1591,3228,1024,2176),
    ]:
        m.box((x0,y0,z0),(x1,y1,z1), REACTOR_PLATE)
        m.box((x0-8,y0,z1-19),(x1+8,y1,z1-8), REACTOR_BEAM)
    for x,y,z in [(980,-705,247),(1354,693,690),(1816,-735,1077),(2267,690,1427),
                  (2650,-545,1534),(2811,520,1445),(3257,484,1629),(3548,599,1732)]:
        m.box((x-108,y-149,z),(x+108,y+149,z+26),REACTOR_CAGE)
        m.box((x-103,y-151,z+11),(x+103,y-144,z+21),COOL_STRIP)
    # Every route out of the chamber passes through this door. The gate is
    # actuated by the encounter Lua only once the containment vessel is breached.
    for y0,y1,z0,z1 in [(-1024,312,0,2176),(716,1024,0,2176),
                         (312,716,0,1648),(312,716,2112,2176)]:
        m.box((2952,y0,z0),(3008,y1,z1),REACTOR_BEAM)
    gate=m.ent('func_door',name='d6_reactor_escape_gate',movedir='-90 0 0',
               speed='440',lip='0',wait='-1',spawnflags=SCRIPTED_DOOR)
    m.box((2958,312,1648),(2998,716,2112),REACTOR_CAGE,gate)
    m.box((2941,284,1648),(2951,312,2112),ALARM_STRIP)
    m.box((2941,716,1648),(2951,744,2112),ALARM_STRIP)
    m.box((2941,284,2112),(2951,744,2127),ALARM_STRIP)
    m.box((3300,246,1809),(3634,788,1834),REACTOR_PLATE)
    for x in (3316,3524):
        m.box((x,260,1833),(x+20,775,1838),COOL_STRIP)
    m.light((2897,522,1892),'255 122 76 450')
    m.light((3214,520,1930),'141 203 237 590')
    m.light((3510,578,1988),'104 232 170 820')
    for x,y,z in [(1112,0,585),(1180,-620,1099),(1494,625,380),(1844,-738,1458),
                  (2268,654,523),(2450,0,1188),(2608,-558,1550),(2205,604,1868)]:
        m.light((x,y,z),'91 163 219 570')
    for i,pos in enumerate([(1220,-341,522),(1204,382,719),(1560,-497,996),(1800,656,1348),
                            (2312,394,570),(2388,-408,1235),(2080,574,1627),(2604,-385,1760)],1):
        m.endpoint(f'd6_rogue_reactor_wave_{i}',pos)
        m.ent('info_node_air',pos)
    for name,pos in {
        'battery_1':(560,-115,472),'ammo_1':(560,139,475),
        'battery_2':(1361,687,762),'repair_1':(1796,-729,1147),
        'ammo_2':(2282,697,1503),'repair_2':(2641,-559,1603),
        'reload_1':(1021,-705,315),'reload_2':(1810,-724,1147),
        'reload_3':(2287,686,1516),
    }.items():
        m.endpoint('d6_supply_'+name,pos)
    m.text('d6_rogue_reactor_text','EXPERIMENTAL SHAFT // START A RUN AT THE SERVICE DECK')
    m.event(m.ent('logic_auto',(416,0,520)),'OnMapSpawn','d6_rogue_reactor_text','Display',delay=1.3)
    return m


def vault():
    m=Map('d6_relay_vault')
    m.shell((0,-1152,-100),(4136,1152,1536))
    m.box((0,-1152,-78),(4136,1152,0),FLOOR)
    m.box((145,-282,6),(563,282,112),METAL)
    m.ent('info_player_start',(350,0,126),angles='0 0 0')
    for x,side,height in [(895,-1,338),(1246,1,579),(1840,-1,926),(2210,1,299),(2780,-1,627),(3420,1,1041)]:
        y=side*657
        m.box((x-105,y-76,0),(x+105,y+76,height),CONCRETE)
        m.box((x-191,y-161,height),(x+194,y+183,height+27),METAL)
    m.wall_x(1500,1152,0,1536,-512,632,197,994)
    m.wall_x(2896,1152,0,1536,-676,543,463,1292)
    for x,y,z,wide in [(1054,90,416,126),(2010,-151,703,182),(2491,159,994,137),(3618,-108,651,182)]:
        m.box((x-wide,y-69,z),(x+wide,y+69,z+29),METAL)
        for offset in (-wide,wide-15):
            m.box((x+offset,y-69,z+29),(x+offset+15,y+69,z+90),CONCRETE)
    for x in (280,630,920,1250,1750,2150,2560,3120,3600,3940):
        m.light((x,238,364),'152 209 233 652')
        m.light((x,-469,1042),'229 167 115 713')
    for name,pos in {
        'battery_1':(1098,92,502),'repair_1':(1840,-642,1012),'ammo_1':(1262,645,663),
        'battery_2':(3430,659,1120),'ammo_2':(2780,-666,705),'repair_2':(3722,-50,752),
        'reload_1':(889,-644,425),'reload_2':(2200,665,388),'reload_3':(2500,134,1077),
    }.items():
        m.endpoint('d6_supply_'+name,pos)
    m.laser('d6_vault_lower',(3180,-340,587),(3180,340,587),(3169,-345,576),(3191,345,597),16)
    m.text('d6_vault_entry','RELAY VAULT // FLIGHT LEVELS OPEN')
    m.event(m.ent('logic_auto',(280,0,156)),'OnMapSpawn','d6_vault_entry','Display',delay=1.3)
    return m


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('directory',type=Path)
    parser.add_argument('--preview-data',type=Path)
    parser.add_argument('--maps',nargs='+',choices=[
        'd6_city17_drain','d6_reactor_escape','d6_relay_vault','d6_rogue_reactor'])
    args=parser.parse_args()
    args.directory.mkdir(parents=True,exist_ok=True)
    maps=[level for level in (city(),reactor(),vault(),rogue_reactor())
          if args.maps is None or level.name in args.maps]
    for level in maps: level.write(args.directory)
    if args.preview_data: args.preview_data.write_text(json.dumps({level.name:level.brushes for level in maps}))


if __name__=='__main__':
    main()
