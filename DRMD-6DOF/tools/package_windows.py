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
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    if run("git", "status", "--porcelain", "--untracked-files=normal", cwd=repo):
        raise SystemExit("Commit all source changes before packaging a pinned build.")
    revision = run("git", "rev-parse", "HEAD", cwd=repo)
    tracked = run("git", "ls-files", "-z", cwd=repo).split("\0")
    args.out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="abaddon-package-") as temporary:
        root = Path(temporary) / "Half-Life-Abaddon"
        root.mkdir()
        for item in tracked:
            if not item:
                continue
            source = repo / item
            if source.is_symlink() or not source.is_file():
                raise SystemExit(f"Unsupported tracked entry: {item}")
            dest = root / item
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, dest)
        env = os.environ.copy()
        env.update(GOOS="windows", GOARCH="amd64", CGO_ENABLED="0")
        executable = root / "AbaddonLauncher.exe"
        subprocess.run([args.go, "build", "-trimpath", "-ldflags=-H=windowsgui -s -w",
                        "-o", str(executable), "."], cwd=root / "DRMD-6DOF/launcher", env=env, check=True)
        payload_root = "DRMD-6DOF/descent_scanner"
        payload = root / payload_root
        files = []
        for path in sorted(payload.rglob("*")):
            if path.is_file():
                files.append({"path": path.relative_to(payload).as_posix(),
                              "sha256": sha256(path), "size": path.stat().st_size})
        manifest = {"schema": 1, "project": "raylight-abaddon", "revision": revision,
                    "channel": "main-integration", "payload_root": payload_root, "files": files}
        (root / "abaddon-build.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        shutil.copy2(root / "DRMD-6DOF/launcher/README_RU.md", root / "START_HERE_RU.md")
        provenance = {
            "revision": revision,
            "gameplay_heads": ["6cb7848069c6422632672f626a1346532dfa942e", "900d116eb7e5f2367a0e8b9978a43d2fc883fbe1"],
            "merged_pull_requests": [1, 2],
            "go": run(args.go, "version"), "launcher_platform": "windows/amd64",
            "gmod": "addon", "hl2": "content-only", "pbr": "not-implemented",
            "game_client_validation": "not-run-for-this-integration",
        }
        (root / "BUILD_INFO.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        sums = [f"{sha256(p)}  {p.relative_to(root).as_posix()}" for p in sorted(root.rglob("*")) if p.is_file()]
        (root / "SHA256SUMS").write_text("\n".join(sums) + "\n", encoding="utf-8")
        archive = args.out / "Half-Life-Abaddon-Full-Windows.zip"
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
            for p in sorted(root.rglob("*")):
                if p.is_file():
                    z.write(p, p.relative_to(root.parent).as_posix())
        # Keep the individual launcher/handoff available for review alongside the full archive.
        shutil.copy2(executable, args.out / executable.name)
        shutil.copy2(root / "DRMD-6DOF/WINDOWS_LAUNCHER_HANDOFF_RU.md", args.out / "ABADDON_WINDOWS_LAUNCHER_HANDOFF.md")
        shutil.copy2(root / "abaddon-build.json", args.out / "abaddon-build.json")
        (args.out / "SHA256SUMS.txt").write_text("\n".join(
            f"{sha256(args.out / name)}  {name}" for name in
            [archive.name, executable.name, "ABADDON_WINDOWS_LAUNCHER_HANDOFF.md", "abaddon-build.json"]) + "\n", encoding="utf-8")
        print(json.dumps({"revision": revision, "archive": str(archive.resolve()),
                          "bytes": archive.stat().st_size, "sha256": sha256(archive),
                          "payload_files": len(files)}, indent=2))


if __name__ == "__main__":
    main()
