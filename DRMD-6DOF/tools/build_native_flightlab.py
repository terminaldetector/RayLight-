"""Generate the editable HL2 flight test map with the same srctools as the campaign."""
import argparse
from pathlib import Path

from build_episode import ALARM_STRIP, CONCRETE, COOL_STRIP, METAL, Map


NAME = 'd6_native_flightlab'


def frame(map_, face_x, left, right, bottom, top, material):
    for y in (left - 8, right):
        map_.box((face_x, y, bottom), (face_x + 5, y + 8, top), material)
    map_.box((face_x, left - 8, top), (face_x + 5, right + 8, top + 8), material)
    if bottom > 0:
        map_.box((face_x, left - 8, bottom - 8), (face_x + 5, right + 8, bottom), material)


def marker_volume(map_, name, bounds, message):
    low, high = bounds
    label = map_.text(name + '_caption', message)
    volume = map_.gate('trigger_multiple', name, low, high, wait=1)
    map_.event(volume, 'OnStartTouch', label['targetname'], 'Display')


def ballistic_range(map_):
    firing_x, bore_z = 896, 128
    lanes = (
        ('near', -444, 512, 24, COOL_STRIP, 'NEAR // 512 SU'),
        ('far', -328, 1024, 36, COOL_STRIP, 'FAR // 1024 SU'),
        ('shielded', -216, 768, 24, ALARM_STRIP, 'SHIELDED // LINE PASSES, BOLT STOPS'),
    )
    for name, y, distance, health, strip, caption in lanes:
        firing_name = f'd6_lab_shot_{name}'
        target_x = firing_x + distance
        map_.endpoint(firing_name, (firing_x, y, bore_z))
        map_.endpoint(f'd6_lab_aim_{name}', (target_x, y, bore_z))
        map_.box((firing_x - 48, y - 30, 0), (firing_x + 48, y + 30, 4), METAL)
        map_.box((firing_x - 48, y - 30, 4), (firing_x - 42, y + 30, 6), strip)
        map_.box((firing_x + 42, y - 30, 4), (firing_x + 48, y + 30, 6), strip)
        marker_volume(map_, firing_name + '_zone',
                      ((firing_x - 42, y - 26, 7), (firing_x + 42, y + 26, 170)), caption)

        target = map_.ent('func_breakable', name=f'd6_lab_target_{name}',
                          health=health, material=2, spawnflags='0')
        map_.box((target_x, y - 26, bore_z - 32), (target_x + 16, y + 26, bore_z + 32), strip, target)
        map_.box((target_x + 8, y - 12, 0), (target_x + 28, y + 12, bore_z - 32), METAL)
        confirmation = map_.text(f'd6_lab_down_{name}', 'TARGET DOWN // ' + name.upper(), hold=2)
        confirmation['spawnflags'] = '1'
        map_.event(target, 'OnBreak', confirmation['targetname'], 'Display')
        map_.light((target_x - 50, y, bore_z + 54), '133 193 220 260')

    # The center ray clears this four-unit slit. The 3-SU radius bolt hits its
    # leading face even though the shutter is only four units thick.
    shield_x, shield_y = 1320, -216
    map_.box((shield_x, shield_y - 44, 64), (shield_x + 4, shield_y + 44, bore_z - 2), CONCRETE)
    map_.box((shield_x, shield_y - 44, bore_z + 2), (shield_x + 4, shield_y + 44, 192), CONCRETE)
    map_.box((shield_x - 1, shield_y - 44, 184), (shield_x, shield_y + 44, 192), ALARM_STRIP)
    map_.light((firing_x, -330, 230), '183 221 246 520')


def flightlab():
    map_ = Map(NAME)
    map_.shell((-128, -576, 0), (2048, 576, 784))
    map_.ent('info_player_start', (112, 0, 8), angles='0 0 0')
    map_.endpoint('d6_lab_axes', (320, 0, 160))
    map_.endpoint('d6_lab_high', (700, 0, 648))
    map_.endpoint('d6_lab_side', (700, -392, 366))
    map_.endpoint('d6_lab_impact', (1000, 0, 288))
    map_.endpoint('d6_lab_sleeve', (1300, 276, 208))
    map_.endpoint('d6_lab_slit', (1300, 468, 208))
    map_.endpoint('d6_lab_finish', (1776, 0, 48))

    # Flush floor markings give a heading reference during a rolled pass.
    map_.box((72, -5, 0), (608, 5, 2), COOL_STRIP)
    map_.box((312, -180, 0), (328, -5, 2), METAL)
    map_.box((312, 5, 0), (328, 180, 2), METAL)
    map_.box((310, -192, 0), (330, -180, 2), COOL_STRIP)
    map_.box((310, 180, 0), (330, 192, 2), ALARM_STRIP)
    for x in (32, 368, 528, 928, 1200, 1568, 1872):
        for y in (-456, 456):
            map_.box((x - 100, y - 36, 760), (x + 100, y + 36, 784), METAL)
            map_.box((x - 78, y - 12, 756), (x + 78, y + 12, 760), COOL_STRIP)
            map_.light((x, y, 742), '116 165 210 272')

    # A continuous wall with three separated openings. The path along the
    # floor remains available to a normal walking HL2 player.
    for left, right in ((-576, -528), (-256, -160), (160, 576)):
        map_.box((672, left, 0), (728, right, 784), METAL)
    for bottom, top in ((0, 260), (476, 784)):
        map_.box((672, -528, bottom), (728, -256, top), CONCRETE)
    for left, right in ((-160, -112), (112, 160)):
        map_.box((672, left, 0), (728, right, 576), METAL)
    map_.box((672, -112, 136), (728, 112, 576), CONCRETE)
    map_.box((672, -160, 768), (728, 160, 784), METAL)
    frame(map_, 667, -112, 112, 0, 136, ALARM_STRIP)
    frame(map_, 667, -160, 160, 576, 768, COOL_STRIP)
    frame(map_, 667, -528, -256, 260, 476, COOL_STRIP)
    for y, z, ink in ((0, 80, '255 180 123 390'), (0, 640, '117 198 255 475'),
                      (-392, 366, '112 221 219 450')):
        map_.light((628, y, z), ink)
        map_.light((776, y, z), ink)

    # Suspended collision baffle, upper landing ledge, and two sleeves at
    # the same altitude. The red slit admits a ray and rejects a 32-SU hull.
    map_.box((1040, -124, 96), (1088, 124, 448), METAL)
    frame(map_, 1035, -116, 116, 106, 438, ALARM_STRIP)
    map_.box((836, -160, 524), (1016, 160, 552), METAL)
    map_.box((1056, 244, 136), (1432, 308, 152), METAL)
    map_.box((1056, 244, 264), (1432, 308, 280), METAL)
    map_.box((1056, 228, 136), (1432, 244, 280), CONCRETE)
    map_.box((1056, 308, 136), (1432, 324, 280), CONCRETE)
    map_.box((1056, 432, 136), (1432, 504, 152), METAL)
    map_.box((1056, 432, 264), (1432, 504, 280), METAL)
    map_.box((1056, 432, 136), (1432, 456, 280), CONCRETE)
    map_.box((1056, 480, 136), (1432, 504, 280), CONCRETE)
    frame(map_, 1051, 244, 308, 152, 264, COOL_STRIP)
    frame(map_, 1051, 456, 480, 152, 264, ALARM_STRIP)
    map_.light((990, 0, 344), '255 177 132 530')
    map_.light((994, 354, 240), '150 207 247 486')
    map_.light((1496, 384, 232), '138 219 216 475')

    map_.box((1664, -88, 0), (1888, 88, 8), METAL)
    map_.box((1888, -88, 0), (1904, 88, 8), COOL_STRIP)
    map_.light((1752, 0, 180), '132 229 174 713')
    map_.light((144, 0, 180), '224 216 177 450')

    caption = map_.text('d6_lab_caption', 'ABADDON // NATIVE FLIGHT LAB', hold=5)
    caption['spawnflags'] = '1'
    auto = map_.ent('logic_auto', (112, 0, 96))
    map_.event(auto, 'OnMapSpawn', caption['targetname'], 'Display', delay=.4)
    marker_volume(map_, 'd6_lab_floor_route', ((680, -100, 8), (720, 100, 126)),
                  'GROUND ROUTE // WALKING BASELINE')
    marker_volume(map_, 'd6_lab_high_route', ((680, -148, 584), (720, 148, 758)),
                  'HIGH APERTURE // LOCAL UP')
    marker_volume(map_, 'd6_lab_side_route', ((680, -518, 268), (720, -266, 466)),
                  'SIDE APERTURE // ROLL AND STRAFE')
    marker_volume(map_, 'd6_lab_sleeve_route', ((1296, 244, 152), (1344, 308, 264)),
                  'HULL SLEEVE // 64 UNITS WIDE')
    marker_volume(map_, 'd6_lab_finish_route', ((1664, -88, 9), (1888, 88, 104)),
                  'LANDING PAD // RETURN TO NORMAL MOVEMENT')
    ballistic_range(map_)
    return map_


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path, help='Destination for the generated VMF')
    args = parser.parse_args()
    args.directory.mkdir(parents=True, exist_ok=True)
    flightlab().write(args.directory)


if __name__ == '__main__':
    main()
