"""Build the editable DRMD episode maps. Requires srctools, no game assets are copied."""
import argparse
import json
from pathlib import Path

from srctools import Vec
from srctools.vmf import Output, VMF

CONCRETE = 'concrete/concretewall001a'
FLOOR = 'concrete/concretefloor001a'
METAL = 'metal/metalwall048a'
BRICK = 'brick/brickwall001a'
TRIGGER = 'tools/toolstrigger'
SKY = 'tools/toolsskybox'
NODRAW = 'tools/toolsnodraw'


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

    def model(self,name,pos,mesh,angle='0 0 0'):
        self.ent('prop_dynamic_override',pos,name,model=f'models/drmd/{mesh}.mdl',solid='0',angles=angle)

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
    for x,z in [(410,20),(1460,30),(2210,20),(4010,-362),(4430,-359)]:
        m.ent('item_healthkit',(x,-137,z))
        m.ent('item_battery',(x,137,z))
    for x in range(260,2850,150):
        for y in (-210,0,210):
            m.ent('info_node',(x,y,15))
    for x in range(3820,4710,146):
        m.ent('info_node',(x,0,-367))
        m.ent('info_node_air',(x,38,-196))
    for i in range(3):
        m.ent('npc_citizen',(530+i*37,(-1)**i*(120+i*18),11),f'd6_citizen_{i+1}',citizentype='1')
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
    m.text('d6_radio_text','DIRECTIVE 04 // CLEAR THE STATION APPROACH')
    m.text('d6_emp_text','LOCAL OVERRIDE // PRIORITY TABLE LOST',color='240 168 107')
    m.text('d6_sewer_text','MAINTENANCE CHANNEL // REACTOR ACCESS AHEAD')
    auto=m.ent('logic_auto',(128,0,96))
    m.event(auto,'OnMapSpawn','d6_radio_text','Display',delay=1)
    emp=m.relay('d6_emp',(625,32,96))
    m.ent('env_shake',(599,0,132),'d6_emp_shake',amplitude='4',frequency='28',duration='1.3',radius='750',spawnflags='8')
    m.ent('env_fade',(603,24,144),'d6_emp_flash',duration='.28',holdtime='.16',renderamt='186',rendercolor='187 229 244',spawnflags='0')
    m.event(emp,'OnTrigger','d6_emp_shake','StartShake')
    m.event(emp,'OnTrigger','d6_emp_flash','Fade')
    m.event(emp,'OnTrigger','d6_emp_text','Display',delay=.55)
    emp_trigger=m.gate('trigger_once','d6_emp_path',(549,-433,0),(671,432,245))
    m.event(emp_trigger,'OnStartTouch','d6_emp')
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
            'd6_charge_1':(573,108,110),'d6_charge_2':(3407,-212,258),'d6_exit_zone':(6362,0,250)}.items():
        m.endpoint(name,pos)
    m.model('d6_sentry_relic',(682,-238,108),'grav','0 17 0')
    m.model('d6_sentry_gimbal',(682,-238,108),'grav_gimbal','22 90 44')
    m.model('d6_reactor_profile',(3912,0,139),'shot_ion','0 0 0')
    m.text('d6_reactor_intro_text','REACTOR MAINTENANCE // CORE TEMPERATURE CRITICAL')
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
    core=m.ent('func_breakable',name='d6_reactor_core',health='245',material='2',spawnobject='0',spawnflags='512')
    m.box((3830,-75,53),(4000,75,223),METAL,core)
    m.box((3834,-97,0),(3994,97,49),CONCRETE)
    for y in (-114,114):
        m.box((3814,y-13,0),(4014,y+13,402),METAL)
    fail=m.relay('d6_core_failure',(3970,0,400))
    m.event(core,'OnBreak','d6_core_failure')
    m.ent('env_shake',(3980,0,167),'d6_core_shake',amplitude='7',frequency='28',duration='4',radius='3500',spawnflags='8')
    m.ent('env_explosion',(3927,0,134),'d6_core_blast',iMagnitude='88',spawnflags='1')
    m.ent('ambient_generic',(4040,0,283),'d6_alarm',message='ambient/alarms/klaxon1.wav',health='6',spawnflags='17')
    m.event(fail,'OnTrigger','d6_reactor_failure_text','Display')
    m.event(fail,'OnTrigger','d6_core_shake','StartShake')
    m.event(fail,'OnTrigger','d6_core_blast','Explode')
    m.event(fail,'OnTrigger','d6_alarm','PlaySound')
    exit_beam,exit_hurt=m.laser('d6_collapse_laser',(5350,-390,273),(5350,390,273),
        (5340,-390,264),(5360,390,285),26,True)
    m.event(fail,'OnTrigger',exit_beam['targetname'],'TurnOn',delay=.45)
    m.event(fail,'OnTrigger',exit_hurt['targetname'],'Enable',delay=.45)
    door=m.ent('func_door',name='d6_escape_door',movedir='-90 0 0',speed='232',lip='0',wait='-1',spawnflags='32')
    m.box((4870,-197,0),(4912,197,639),METAL,door)
    m.event(fail,'OnTrigger','d6_escape_door','Open',delay=.65)
    done=m.relay('d6_escape_complete',(6260,0,450))
    m.event(done,'OnTrigger','d6_reactor_exit_text','Display')
    exit_zone=m.gate('trigger_once','d6_escape_trigger',(6178,-298,0),(6420,298,1350),True)
    m.event(fail,'OnTrigger','d6_escape_trigger','Enable')
    m.event(exit_zone,'OnStartTouch','d6_escape_complete')
    return m


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('directory',type=Path)
    parser.add_argument('--preview-data',type=Path)
    args=parser.parse_args()
    args.directory.mkdir(parents=True,exist_ok=True)
    maps=[city(),reactor()]
    for level in maps: level.write(args.directory)
    if args.preview_data: args.preview_data.write_text(json.dumps({level.name:level.brushes for level in maps}))


if __name__=='__main__':
    main()
