"""Make the three elite surface finishes for Source and Blender."""
import argparse
from pathlib import Path
from struct import pack_into

import numpy as np
from PIL import Image, ImageDraw


SIZE = 1024
FINISHES = {
    'siege_plate': (18417, (215, 223, 225), (153, 116, 93), 0.65, 1.0),
    'arc_shell': (51247, (223, 230, 226), (165, 134, 106), 0.53, 0.68),
    'turned_steel': (91001, (225, 228, 220), (161, 145, 119), 0.38, 0.51),
}


def lattice(rng, columns, rows):
    """Sample a periodic field with a smooth cubic interpolation."""
    x, y = np.arange(SIZE) * columns / SIZE, np.arange(SIZE) * rows / SIZE
    i, j = x.astype(int), y.astype(int)
    u, v = x-i, y-j
    u, v = u*u*(3-2*u), v*v*(3-2*v)
    points = rng.standard_normal((rows, columns))
    lower = points[j[:, None], i]*(1-u) + points[j[:, None], (i+1) % columns]*u
    upper = points[((j+1) % rows)[:, None], i]*(1-u) + points[((j+1) % rows)[:, None], (i+1) % columns]*u
    return lower*(1-v[:, None]) + upper*v[:, None]


def scratches(rng):
    mask = Image.new('L', (SIZE, SIZE))
    draw = ImageDraw.Draw(mask)
    for _ in range(390):
        x, y = rng.integers(0, SIZE, 2)
        length = int(rng.integers(8, 78))
        drift = int(rng.integers(-28, 25))
        ink = int(rng.integers(60, 224))
        for dx, dy in ((0,0),(0,-SIZE),(0,SIZE),(-SIZE,0),(-SIZE,-SIZE),(-SIZE,SIZE)):
            draw.line((x+dx, y+dy, x+length+dx, y+drift+dy), fill=ink, width=2 if length > 43 else 1)
    return np.asarray(mask, dtype=float)/255


def maps(settings):
    seed, base, undercoat, rough, weathering = settings
    rng = np.random.default_rng(seed)
    broad = lattice(rng, 8, 8)
    tarnish = lattice(rng, 23, 19)
    grit = lattice(rng, 78, 94)
    flakes = (broad*.50 + tarnish*.76 + grit*.29)
    rust = np.clip((flakes-.59)*1.26, 0, 1)*weathering
    rim = (np.clip((flakes-.33)*1.31,0,1) - np.clip((flakes-.61)*1.37,0,1))*.38
    pit = np.clip(lattice(rng, 198, 178)-1.05,0,1)
    grind = lattice(rng, 12, 412)
    scores = scratches(rng)
    shadow = np.roll(scores, 2, axis=0)*.7
    dark = (broad*8+tarnish*6+grit*3+grind*2.4-pit*32-shadow*46)
    color = np.array(base) + dark[:, :, None]
    color = color*(1-rust[:, :, None]) + np.array(undercoat)*rust[:, :, None]
    color += (scores*86+rim*40)[:, :, None]
    albedo = Image.fromarray(np.uint8(np.clip(color,30,254)), 'RGB')
    matte = np.clip(rough+rust*.24+tarnish*.06+grit*.027+pit*.22-scores*.30, .18, .98)
    roughness = Image.fromarray(np.uint8(matte*255), 'L')
    elevation = broad*.38 + tarnish*.28 + grit*.13 + grind*.08-pit*.38-scores*.29
    dx = (np.roll(elevation, 1, axis=1)-np.roll(elevation,-1,axis=1))*2.1
    dy = (np.roll(elevation,-1,axis=0)-np.roll(elevation,1,axis=0))*2.1
    lengths = np.sqrt(dx*dx+dy*dy+1)
    normal = np.stack((dx/lengths,dy/lengths,1/lengths), axis=2)
    normal = Image.fromarray(np.uint8((normal*.5+.5)*255),'RGB')
    return albedo, roughness, normal


def source_texture(image):
    """Write RGBA8888 VTF 7.2 with the full mip chain for Source."""
    size = 512
    levels = size.bit_length()
    header = bytearray(80)
    pack_into('<4sIIIHHIHH',header,0,b'VTF\0',7,2,len(header),size,size,0,1,0)
    pack_into('<3f',header,32,.5,.5,.5)
    pack_into('<fIBIBBH',header,48,1.,0,levels,0xffffffff,0,0,1)
    mipmaps = [image.resize((2**i,2**i),Image.Resampling.LANCZOS).convert('RGBA').tobytes() for i in range(levels)]
    return bytes(header)+b''.join(mipmaps)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source_materials',type=Path)
    parser.add_argument('blender_textures',type=Path)
    args = parser.parse_args()
    args.source_materials.mkdir(parents=True,exist_ok=True)
    args.blender_textures.mkdir(parents=True,exist_ok=True)
    for name,settings in FINISHES.items():
        albedo, roughness, normal = maps(settings)
        (args.source_materials/f'drmd_finish_{name}.vtf').write_bytes(source_texture(albedo))
        for kind,image in [('albedo',albedo),('roughness',roughness),('normal',normal)]:
            image.save(args.blender_textures/f'{name}-{kind}.png')
        print(f'{name} · 512 px VTF · 1024 px PBR')


if __name__ == '__main__':
    main()
