#!/usr/bin/env python3
"""Build a pinned Windows launcher and a complete offline Abaddon source/payload ZIP."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile


def run(*args, cwd=None, env=None):
    return subprocess.check_output(args, cwd=cwd, env=env, text=True).strip()


def sha256(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--go", default="go")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--runtime-only", action="store_true",
                        help="Package the launcher, installable content and native lab source without authoring assets")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    if run("git", "status", "--porcelain", "--untracked-files=normal", cwd=repo):
        raise SystemExit("Commit all source changes before packaging a pinned build.")
    revision = run("git", "rev-parse", "HEAD", cwd=repo)
    tree = subprocess.check_output(("git", "ls-tree", "-rz", "--full-tree", revision), cwd=repo)
    tracked = []
    for entry in tree.split(b"\0"):
        if not entry:
            continue
        record, path = entry.split(b"\t", 1)
        mode, _, object_id = record.decode("ascii").split()
        tracked.append((path.decode(), mode, object_id))
    args.out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="abaddon-package-") as temporary:
        env = os.environ.copy()
        env.update(GOOS="windows", GOARCH="amd64", CGO_ENABLED="0")
        executable = Path(temporary) / "AbaddonLauncher.exe"
        subprocess.run([args.go, "build", "-trimpath", "-buildvcs=false", "-ldflags=-H=windowsgui -s -w",
                        "-o", str(executable), "."], cwd=repo / "DRMD-6DOF/launcher", env=env, check=True)
        payload_root = "DRMD-6DOF/descent_scanner"
        planned = {"DRMD-6DOF/INSTALL_RU.md", "DRMD-6DOF/MAPS_RU.md", "DRMD-6DOF/SYNC_RESULT_RU.md",
                   "DRMD-6DOF/WINDOWS_LAUNCHER_HANDOFF_RU.md", "DRMD-6DOF/launcher/README_RU.md",
                   "DRMD-6DOF/tools/build_native_flightlab.py", "DRMD-6DOF/tools/build_episode.py"}
        channel = "agent2-integration" if run("git", "branch", "--show-current", cwd=repo).startswith("integration/") else "main-integration"
        manifest = {"schema": 1, "project": "raylight-abaddon", "revision": revision,
                    "channel": channel, "payload_root": payload_root, "files": []}
        provenance = {
            "revision": revision,
            "export": "runtime-only" if args.runtime_only else "full-tree",
            "go": run(args.go, "version"), "launcher_platform": "windows/amd64",
            "gmod": "addon", "hl2": "content-only", "hl2-native": "experimental-source-lab",
            "native_windows_game_dlls": "external-sdk-build",
        }
        archive = args.out / ("Half-Life-Abaddon-Windows.zip" if args.runtime_only else "Half-Life-Abaddon-Full-Windows.zip")
        staged = archive.with_suffix(".tmp")
        sums = []
        handoff = b""
        with zipfile.ZipFile(staged, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
            def add(name, content):
                digest = hashlib.sha256(content).hexdigest()
                z.writestr("Half-Life-Abaddon/" + name, content)
                sums.append(f"{digest}  {name}")
                return digest

            for path, mode, object_id in tracked:
                if args.runtime_only and path not in planned and not path.startswith((payload_root + "/", "DRMD-6DOF/native/hl2/", "DRMD-6DOF/swep_construction_kit/")):
                    continue
                if not mode.startswith("100"):
                    raise SystemExit(f"Unsupported tracked entry: {path}")
                content = subprocess.check_output(("git", "cat-file", "blob", object_id), cwd=repo)
                digest = add(path, content)
                if path.startswith(payload_root + "/"):
                    manifest["files"].append({"path": path[len(payload_root)+1:], "sha256": digest, "size": len(content)})
                elif path == "DRMD-6DOF/launcher/README_RU.md":
                    add("START_HERE_RU.md", content)
                elif path == "DRMD-6DOF/WINDOWS_LAUNCHER_HANDOFF_RU.md":
                    handoff = content
            manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode()
            add("abaddon-build.json", manifest_bytes)
            add("BUILD_INFO.json", (json.dumps(provenance, ensure_ascii=False, indent=2) + "\n").encode())
            add(executable.name, executable.read_bytes())
            go_license = Path(run(args.go, "env", "GOROOT", env=env)) / "LICENSE"
            add("GO_LICENSE.txt", go_license.read_bytes())
            z.writestr("Half-Life-Abaddon/SHA256SUMS", "\n".join(sorted(sums)) + "\n")
        staged.replace(archive)
        shutil.copy2(executable, args.out / executable.name)
        (args.out / "ABADDON_WINDOWS_LAUNCHER_HANDOFF.md").write_bytes(handoff)
        (args.out / "abaddon-build.json").write_bytes(manifest_bytes)
        (args.out / "SHA256SUMS.txt").write_text("\n".join(
            f"{sha256(args.out / name)}  {name}" for name in
            [archive.name, executable.name, "ABADDON_WINDOWS_LAUNCHER_HANDOFF.md", "abaddon-build.json"]) + "\n", encoding="utf-8")
        print(json.dumps({"revision": revision, "archive": str(archive.resolve()),
                          "bytes": archive.stat().st_size, "sha256": sha256(archive),
                          "payload_files": len(manifest["files"])}, indent=2))


if __name__ == "__main__":
    main()
