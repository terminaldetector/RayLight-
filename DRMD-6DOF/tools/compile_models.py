"""Compile the exported DRMD geometry to Source studio models for Hammer and the native map fallback."""
import argparse
import concurrent.futures
import json
import pathlib
import subprocess
import tempfile


def write_materials(game, palette, finishes):
    paths = game / 'materials/models/drmd'
    paths.mkdir(parents=True, exist_ok=True)
    for name, color in palette.items():
        finish = finishes.get(name)
        basetexture = f'drmd/drmd_finish_{finish}' if finish else 'vgui/white'
        shader = 'UnlitGeneric' if name in {'emit', 'hot'} else 'VertexLitGeneric'
        if name == 'emit':
            color = [133, 201, 216]
        tint = ' '.join(f'{component / 255:.4f}' for component in color)
        (paths / f'{name}.vmt').write_text(f'{shader}\n{{\n "$basetexture" "{basetexture}"\n "$color" "[{tint}]"\n}}\n')


SKELETON = 'version 1\nnodes\n0 "root" -1\nend\nskeleton\ntime 0\n0 0 0 0 0 0 0\nend\n'


def uv(p, n):
    x,y,z = map(abs,n)
    if x >= y and x >= z:
        return p[1]/24,-p[2]/24
    if y >= z:
        return p[0]/24,-p[2]/24
    return p[0]/24,-p[1]/24


def compile_one(work, exe, game, name, parts):
    mesh = work / (name+'.smd')
    with mesh.open('w') as stream:
        stream.write(SKELETON + 'triangles\n')
        for finish, faces in parts.items():
            for face in faces:
                stream.write(f'{finish}.vmt\n')
                normal = face[3]
                for vertex in face[:3]:
                    fields = (*vertex,*normal,*uv(vertex,normal))
                    stream.write('0 ' + ' '.join(f'{x:.5f}' for x in fields) + '\n')
        stream.write('end\n')
    qc = work / (name+'.qc')
    qc.write_text(f'$modelname "drmd/{name}.mdl"\n$staticprop\n$cdmaterials "models/drmd"\n'
                  f'$surfaceprop "metal"\n$body "body" "{mesh.name}"\n$sequence "idle" "idle.smd" fps 1\n')
    out=subprocess.run([str(exe),'-game',str(game),str(qc)],cwd=work,capture_output=True,text=True)
    if out.returncode or not (game/'models/drmd'/f'{name}.mdl').exists():
        raise RuntimeError(f'{name}: {out.stdout}\n{out.stderr}')
    return name


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('geometry',type=pathlib.Path)
    parser.add_argument('compiler',type=pathlib.Path)
    parser.add_argument('game',type=pathlib.Path)
    args=parser.parse_args()
    manifest=json.loads(args.geometry.read_text())
    game=args.game.resolve()
    (game/'models/drmd').mkdir(parents=True,exist_ok=True)
    write_materials(game,manifest['palette'],manifest['finishes'])
    with tempfile.TemporaryDirectory(prefix='drmd-smd-') as tmp, concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
        work=pathlib.Path(tmp)
        (work/'idle.smd').write_text(SKELETON)
        jobs=[pool.submit(compile_one, work, args.compiler.resolve(), game, name, parts) for name, parts in manifest['models'].items()]
        for job in concurrent.futures.as_completed(jobs): print('PASS | MDL | '+job.result(),flush=True)
    print(f'Compiled {len(jobs)} original Source models')


if __name__=='__main__':
    main()
