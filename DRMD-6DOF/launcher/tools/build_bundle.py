"""Package one reviewed Abaddon commit for the Windows launcher."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import subprocess
from zipfile import ZIP_DEFLATED, ZipFile

PIN = "5849463a3d3417a16d3cb98e32f8b13e83557bb9"
PAYLOAD = "DRMD-6DOF/descent_scanner"
ROOT = Path(__file__).resolve().parents[3]


def git(*args):
    return subprocess.check_output(("git", "-C", str(ROOT), *args))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="Path to Abaddon-Game.zip")
    args = parser.parse_args()
    manifest = {
        "project": "raylight-abaddon",
        "channel": "dev",
        "revision": PIN,
        "targets": {
            "gmod": {
                "status": "experimental",
                "features": {
                    "combat_drone_entity": True,
                    "four_visible_mounts": True,
                    "independent_mouse_mounts": False,
                    "mines_independent": True,
                    "granada_supports": False,
                    "grav_rail_xray": False,
                    "dedicated_server_verified": True,
                    "graphical_client_verified": False,
                },
            },
            "hl2-content": {
                "status": "content-only",
                "features": {"maps_and_models": True, "native_hl2_combat": False},
            },
        },
        "files": {},
    }
    names = git("ls-tree", "-r", "--name-only", "-z", f"{PIN}:{PAYLOAD}").decode().split("\0")
    output = args.output.resolve()
    staged = output.with_suffix(".tmp")
    with ZipFile(staged, "w", ZIP_DEFLATED) as bundle:
        for name in filter(None, names):
            data = git("show", f"{PIN}:{PAYLOAD}/{name}")
            manifest["files"][name] = {"sha256": sha256(data).hexdigest(), "size": len(data)}
            bundle.writestr(f"descent_scanner/{name}", data)
        bundle.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
    staged.replace(output)
    print(f"{output.name}: {len(manifest['files'])} files, dev {PIN[:10]}")


if __name__ == "__main__":
    main()
