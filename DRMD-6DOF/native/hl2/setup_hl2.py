"""Apply the Abaddon flight overlay or deploy built SDK modules and the test map."""

import argparse
import filecmp
from pathlib import Path
import shutil
import subprocess
import tempfile


HERE = Path(__file__).resolve().parent
HEADERS = {
    "abaddon_flight_input.h": "src/game/client/hl2/abaddon_flight_input.h",
    "abaddon_flight_math.h": "src/game/shared/hl2/abaddon_flight_math.h",
    "abaddon_mounts.h": "src/game/shared/hl2/abaddon_mounts.h",
    "abaddon_projectile_server.h": "src/game/server/hl2/abaddon_projectile_server.h",
    "abaddon_mine_bay.h": "src/game/shared/hl2/abaddon_mine_bay.h",
    "abaddon_mine_server.h": "src/game/server/hl2/abaddon_mine_server.h",
    "abaddon_arsenal_hud.h": "src/game/client/hl2/abaddon_arsenal_hud.h",
}


def overlay_patch():
    patch = (HERE / "source-2013-sp.patch").read_bytes()
    for name, target in HEADERS.items():
        lines = (HERE / name).read_bytes().splitlines(keepends=True)
        header = (
            f"diff --git a/{target} b/{target}\n"
            "new file mode 100644\n"
            "--- /dev/null\n"
            f"+++ b/{target}\n"
            f"@@ -0,0 +1,{len(lines)} @@\n"
        ).encode("ascii")
        patch += header + b"".join(b"+" + line for line in lines)
    return patch


def patch_sdk(sdk, check_only):
    sdk = sdk.resolve()
    if not (sdk / "src/game/shared/hl2/hl_gamemovement.cpp").is_file():
        raise SystemExit("Choose the root of the Valve Source SDK 2013 singleplayer checkout.")
    patch = overlay_patch()

    def git_apply(*options):
        return subprocess.run(
            ["git", "apply", *options, "-"], cwd=sdk, input=patch,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )

    if git_apply("--check", "--reverse").returncode == 0:
        print("Abaddon overlay is already applied.")
        return
    result = git_apply("--check")
    if result.returncode:
        raise SystemExit(result.stderr.decode(errors="replace"))
    if not check_only:
        result = git_apply()
        if result.returncode:
            raise SystemExit(result.stderr.decode(errors="replace"))
    print("Abaddon overlay applies cleanly." if check_only else "Abaddon overlay applied.")


def deploy(bins, destination):
    payload = {
        Path("gameinfo.txt"): HERE / "gameinfo.txt",
        Path("maps/d6_native_flightlab.bsp"): HERE / "maps/d6_native_flightlab.bsp",
        Path("LICENSE"): HERE / "LICENSE",
        Path("thirdpartylegalnotices.txt"): HERE / "thirdpartylegalnotices.txt",
    }
    # Both engines load the same compiled models and surface finishes.
    art = HERE.parents[1] / "descent_scanner"
    for model in ("shot_kinetic", "shot_arcpulse", "mine_plasma", "mine_gravity", "supply"):
        for suffix in (".mdl", ".vvd", ".dx80.vtx", ".dx90.vtx"):
            path = Path("models/drmd") / (model + suffix)
            payload[path] = art / path
    for material in ("armor", "canvas", "copper", "dark", "edge", "emit", "frame", "glass", "hazard", "hot", "steel"):
        path = Path("materials/models/drmd") / (material + ".vmt")
        payload[path] = art / path
    for texture in ("alloy", "coating", "glass", "polymer"):
        path = Path("materials/drmd") / ("drmd_finish_" + texture + ".vtf")
        payload[path] = art / path
    available = {}
    for extension in ("so", "dll"):
        modules = tuple(f"{name}.{extension}" for name in ("client", "server"))
        if all((bins / name).is_file() for name in modules):
            available.update({Path("bin") / name: bins / name for name in modules})
    if not available:
        raise SystemExit("Choose the directory containing built SP client/server binaries (.so or .dll).")
    payload.update(available)

    destination = destination.absolute()
    if destination.exists():
        if all((destination / name).is_file()
               and filecmp.cmp(source, destination / name, shallow=False)
               for name, source in payload.items()):
            print(f"Abaddon is already deployed to {destination}.")
            return
        raise SystemExit(f"The destination contains a different installation: {destination}")

    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".abaddon-", dir=destination.parent) as staging:
        mod = Path(staging) / "mod"
        for name, source in payload.items():
            target = mod / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        mod.rename(destination)
    print(f"Abaddon deployed to {destination}.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    patch = commands.add_parser("patch", help="Apply the overlay to a Source SDK checkout")
    patch.add_argument("sdk", type=Path)
    patch.add_argument("--check", action="store_true")
    package = commands.add_parser("deploy", help="Install the built native test mod")
    package.add_argument("bins", type=Path, help="Directory with the built client and server binaries")
    package.add_argument("destination", type=Path, help="New directory under steamapps/sourcemods")
    args = parser.parse_args()
    if args.command == "patch":
        patch_sdk(args.sdk, args.check)
    else:
        deploy(args.bins, args.destination)


if __name__ == "__main__":
    main()
