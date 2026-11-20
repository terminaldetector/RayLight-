"""Export editable Abaddon elite models and render both sides in Blender."""
import argparse
from collections import defaultdict
import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector


ASSETS = {
    'combine_elite': {
        'variant': 'heavy_elite',
        'file': 'citadel-enforcer',
        'name': 'Citadel Enforcer',
        'view': (10.5,-8.1,1.72),
        'reverse': (-10.6,8.3,1.95),
        'lens': 43,
    },
    'combine_arc_elite': {
        'variant': 'arc_elite',
        'file': 'arc-elite',
        'name': 'Arc Elite',
        'view': (13.6,-11.3,1.97),
        'reverse': (-13.8,11.5,2.65),
        'lens': 46,
    },
}


def srgb(values):
    return tuple(v/3294.6 if v <= 10.31 else ((v/255+.055)/1.055)**2.4 for v in values)


def pbr(name, color, roughness, metal, emission=0):
    material=bpy.data.materials.new(name)
    material.diffuse_color=(*srgb(color),1)
    material.use_nodes=True
    shader=material.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value=material.diffuse_color
    shader.inputs['Roughness'].default_value=roughness
    shader.inputs['Metallic'].default_value=metal
    if emission:
        shader.inputs['Emission Color'].default_value=material.diffuse_color
        shader.inputs['Emission Strength'].default_value=emission
    return material, shader


def texture(material, path, noncolor=False):
    image=bpy.data.images.load(str(path),check_existing=True)
    if noncolor:
        image.colorspace_settings.name='Non-Color'
    node=material.node_tree.nodes.new('ShaderNodeTexImage')
    node.image=image
    return node


def material_for(key, palette, finish, ink, path):
    if key in {'emit','hot','lamp','siege_eye'}:
        color, strength = {
            'emit': (ink, 3.7),
            'hot': ((255,153,70), 5.6),
            'lamp': ((206,235,226), 3.3),
            'siege_eye': ((246,66,45), 4.0),
        }[key]
        material, shader=pbr(key, color, .28, .16, strength)
        shader.inputs['Coat Weight'].default_value=.43
        return material
    if key == 'glass':
        material, shader=pbr('Smoked optical glass', (40,61,65), .19, .47)
        shader.inputs['Coat Weight'].default_value=.64
        return material
    metallic, roughness = {
        'siege_plate': (.57,.63), 'arc_shell': (.49,.54), 'turned_steel': (.74,.41),
        'polymer': (.09,.78), 'coating': (.38,.57), 'alloy': (.64,.41),
    }.get(finish,(.48,.61))
    material, shader=pbr(key, palette[key], roughness, metallic)
    if not finish or not (path/f'{finish}-albedo.png').is_file():
        return material
    nodes, links=material.node_tree.nodes, material.node_tree.links
    albedo=texture(material, path/f'{finish}-albedo.png')
    tint=nodes.new('ShaderNodeMixRGB')
    tint.blend_type='MULTIPLY'
    tint.inputs[0].default_value=1
    tint.inputs[2].default_value=(*srgb(palette[key]),1)
    links.new(albedo.outputs['Color'],tint.inputs[1])
    links.new(tint.outputs[0],shader.inputs['Base Color'])
    matte=texture(material,path/f'{finish}-roughness.png',True)
    links.new(matte.outputs['Color'],shader.inputs['Roughness'])
    detail=texture(material,path/f'{finish}-normal.png',True)
    normal=nodes.new('ShaderNodeNormalMap')
    normal.inputs['Strength'].default_value=.53
    links.new(detail.outputs['Color'],normal.inputs['Color'])
    links.new(normal.outputs['Normal'],shader.inputs['Normal'])
    return material


def uv(point, normal):
    x,y,z=map(abs,normal)
    if x>=y and x>=z:
        return point[1]/24,point[2]/24
    if y>=z:
        return point[0]/24,point[2]/24
    return point[0]/24,point[1]/24


def assembly(name, faces, materials, units, parent, collection):
    vertices, polygons, indices, norms, slots = [], [], {}, [], []
    used = {}
    for key, face in faces:
        corners = []
        for raw in face[:3]:
            point = tuple(raw)
            if point not in indices:
                indices[point] = len(vertices)
                vertices.append(tuple(c*units for c in point))
            corners.append(indices[point])
        polygons.append(corners)
        norms.append((face[:3],face[3]))
        if key not in used:
            used[key]=len(used)
        slots.append(used[key])
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(vertices,[],polygons)
    mesh.update()
    obj=bpy.data.objects.new(name,mesh)
    collection.objects.link(obj)
    obj.parent=parent
    for key in used:
        mesh.materials.append(materials[key])
    layer=mesh.uv_layers.new(name='Surface')
    for poly,slot,(points,normal) in zip(mesh.polygons,slots,norms):
        poly.use_smooth=True
        poly.material_index=slot
        for loop,point in zip(poly.loop_indices,points):
            layer.data[loop].uv=uv(point,normal)
    mesh.set_sharp_from_angle(angle=math.radians(42))
    return obj


def model(asset, key, manifest, texture_path):
    craft = manifest['drones'][asset['variant']]
    units = craft['scale']*.0254
    collection=bpy.data.collections.new(asset['name'])
    bpy.context.scene.collection.children.link(collection)
    root=bpy.data.objects.new(asset['name'],None)
    collection.objects.link(root)
    root['Forward'] = '+X'
    root['Source model'] = key+'.mdl'
    root['Game scale'] = craft['scale']
    root.empty_display_size=.35
    by_assembly=defaultdict(list)
    mats={}
    for material,faces in manifest['models'][key].items():
        mats[material]=material_for(material,manifest['palette'],manifest['finishes'].get(material),
                                    craft['color'] if key != 'combine_elite' else (126,182,217),texture_path)
        for face in faces:
            by_assembly[face[4]].append((material,face))
    objects=[assembly(name,faces,mats,units,root,collection) for name,faces in by_assembly.items()]
    sockets = {}
    if key == 'combine_elite':
        sockets['Range finder']=(26.70,0,1.03)
        for s,side in [(-1,'right'),(1,'left')]:
            for j in range(2):
                sockets[f'Cannon {side} {j+1}']=(29.2,s*(24.2+(-1)**j*2.51),.4)
            for j in range(3):
                sockets[f'Rocket cassette {side} {j+1}']=(14.8,s*(14.45+(j-1)*4.15),22.15)
    else:
        for label,point in zip(('Port arc emitter','Starboard arc emitter','Ventral rail','Optical laser',
                                'Port plasma rocket','Starboard plasma rocket','Port rotary','Starboard rotary'),craft['guns']):
            sockets[label]=point
    for label,pos in sockets.items():
        empty=bpy.data.objects.new(f'Socket · {label}',None)
        collection.objects.link(empty)
        empty.parent=root
        empty.location=tuple(x*units for x in pos)
        empty.empty_display_type='ARROWS'
        empty.empty_display_size=.13
    assert sum(len(o.data.polygons) for o in objects) == sum(map(len,manifest['models'][key].values()))
    return collection


def look_at(obj, target):
    obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()


def relink(obj, collection):
    for source in list(obj.users_collection):
        source.objects.unlink(obj)
    collection.objects.link(obj)


def box(collection, name, pos, size, material, bevel=0):
    bpy.ops.mesh.primitive_cube_add(size=1,location=pos)
    obj=bpy.context.object
    obj.name=name
    relink(obj,collection)
    bpy.context.view_layer.objects.active=obj
    obj.select_set(True)
    obj.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    obj.data.materials.append(material)
    if bevel:
        modifier=obj.modifiers.new('Cast edges','BEVEL')
        modifier.width=bevel
        modifier.segments=3
        obj.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return obj


def light(collection, name, pos, at, energy, size, color):
    data=bpy.data.lights.new(name,'AREA')
    data.energy, data.size, data.color=energy,size,srgb(color)
    obj=bpy.data.objects.new(name,data)
    collection.objects.link(obj)
    obj.location=pos
    look_at(obj,at)


def camera(collection, name, pos, lens):
    data=bpy.data.cameras.new(name)
    data.lens=lens
    obj=bpy.data.objects.new(name,data)
    collection.objects.link(obj)
    obj.location=pos
    look_at(obj,(.25,0,-.16))
    return obj


def concrete():
    material, shader=pbr('Pitted workshop concrete',(48,57,59),.71,.03)
    nodes, links=material.node_tree.nodes, material.node_tree.links
    noise=nodes.new('ShaderNodeTexNoise')
    noise.inputs['Scale'].default_value=51
    noise.inputs['Detail'].default_value=5
    ramp=nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color=(*srgb((33,41,42)),1)
    ramp.color_ramp.elements[1].color=(*srgb((76,83,85)),1)
    bump=nodes.new('ShaderNodeBump')
    bump.inputs['Distance'].default_value=.1
    bump.inputs['Strength'].default_value=.31
    links.new(noise.outputs['Fac'],ramp.inputs[0])
    links.new(noise.outputs['Fac'],bump.inputs['Height'])
    links.new(ramp.outputs[0],shader.inputs['Base Color'])
    links.new(bump.outputs[0],shader.inputs['Normal'])
    return material


def stage(asset, giant):
    scene=bpy.context.scene
    stage_collection=bpy.data.collections.new('Studio')
    scene.collection.children.link(stage_collection)
    scene.render.engine='BLENDER_EEVEE_NEXT'
    scene.eevee.taa_render_samples=42
    scene.render.resolution_x=1600
    scene.render.resolution_y=1100
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    scene.view_settings.view_transform='AgX'
    scene.world=bpy.data.worlds.new('Workshop air')
    scene.world.use_nodes=True
    world=scene.world.node_tree.nodes.get('Background')
    world.inputs['Color'].default_value=(*srgb((145,164,182)),1)
    world.inputs['Strength'].default_value=.36
    height= -3.93 if giant else -4.34
    floor=concrete()
    rail,_=pbr('Dark steel framing',(41,48,50),.55,.31)
    box(stage_collection,'Floor',(0,0,height-.18),(42,48,.33),floor,.035)
    box(stage_collection,'Baffle',(0,13,3.7),(38,.6,16),floor,.09)
    box(stage_collection,'Baffle opposite',(0,-13,3.7),(38,.6,16),floor,.09)
    for side in [-1,1]:
        for x in [-15,-10,-5,0,5,10,15]:
            box(stage_collection,'Wall pier',(x,side*12.57,2.9),(.62,.88,15),rail,.04)
    k=1 if giant else 1.26
    light(stage_collection,'Soft overcast key',(5.7,-6.9,6.4),(0,0,.5),2720*k,6.4*k,(204,228,240))
    light(stage_collection,'Opposite cold strip',(1.9,7.9,4.6),(0,0,0),2110*k,5.3*k,(162,204,231))
    light(stage_collection,'Metal glint',(-5.6,.9,4.95),(-1.1,0,.7),2460*k,4.1*k,(233,214,190))
    light(stage_collection,'Low bounce',(4.2,-2.7,-2.9),(1,0,-.9),620*k,4.5*k,(237,178,124))
    light(stage_collection,'Back fill',(-7.7,7.1,1.0),(-.4,0,0),1920*k,5.3*k,(185,210,223))
    light(stage_collection,'Floor pool',(-2.8,-1.75,1.2),(-2.8,-4,height),430*k,4.4*k,(163,199,218))
    scene.use_nodes=True
    nodes,links=scene.node_tree.nodes,scene.node_tree.links
    nodes.clear()
    raw=nodes.new('CompositorNodeRLayers')
    bloom=nodes.new('CompositorNodeGlare')
    bloom.glare_type='FOG_GLOW'
    bloom.quality='HIGH'
    bloom.threshold=1.75
    bloom.size=8
    result=nodes.new('CompositorNodeComposite')
    links.new(raw.outputs['Image'],bloom.inputs['Image'])
    links.new(bloom.outputs['Image'],result.inputs['Image'])
    return (camera(stage_collection,'Front three-quarter',asset['view'],asset['lens']),
            camera(stage_collection,'Rear three-quarter',asset['reverse'],asset['lens']))


def build(key, asset, manifest, textures, out, render):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    collection=model(asset,key,manifest,textures)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in collection.objects:
        obj.select_set(True)
    basename=asset['file']
    bpy.ops.export_scene.gltf(filepath=str(out/(basename+'.glb')),export_format='GLB',
                              use_selection=True,export_extras=True)
    front,rear=stage(asset,key=='combine_elite')
    scene=bpy.context.scene
    scene.camera=front
    for screen in bpy.data.screens:
        for space in (area.spaces.active for area in screen.areas if area.type == 'VIEW_3D'):
            space.region_3d.view_perspective='CAMERA'
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(out/(basename+'.blend')),compress=True)
    if render:
        for suffix,cam in [('front',front),('rear',rear)]:
            scene.camera=cam
            scene.render.filepath=str(out/(basename+'-'+suffix+'.png'))
            bpy.ops.render.render(write_still=True)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('manifest',type=Path)
    parser.add_argument('textures',type=Path)
    parser.add_argument('out',type=Path)
    parser.add_argument('--render',action='store_true')
    parser.add_argument('--model',choices=[asset['file'] for asset in ASSETS.values()])
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    args.out.mkdir(exist_ok=True,parents=True)
    source=json.loads(args.manifest.read_text())
    for key,asset in ASSETS.items():
        if args.model is None or asset['file']==args.model:
            build(key,asset,source,args.textures,args.out,args.render)


if __name__=='__main__':
    main()
