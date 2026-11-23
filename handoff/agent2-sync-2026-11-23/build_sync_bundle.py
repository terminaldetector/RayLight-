#!/usr/bin/env python3
"""Make a file-complete Agent2/HL2 handoff from pinned Git objects; no game files changed."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile

MAIN = "d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d"
NATIVE = "5849463a3d3417a16d3cb98e32f8b13e83557bb9"
REACTOR = "28656ac7f2a4c989d208a066b78f6c280cfcd5e1"
BASE = "6cb7848069c6422632672f626a1346532dfa942e"
DOCS = "c07fc0d965f1f4a14ca5e2c6e194b2e508b52f69"
ROOT = Path(__file__).resolve().parents[2]
NAME = "Abaddon-Agent2-HL2-SYNC-2026-11-23.zip"


def command(*args, cwd=ROOT, check=True):
    p = subprocess.run(["git", *args], cwd=cwd, capture_output=True)
    if check and p.returncode:
        raise RuntimeError("git " + " ".join(args) + " failed: " +
                           p.stderr.decode("utf-8", "replace"))
    return p


def text_command(*args):
    return command(*args).stdout.decode("utf-8", "replace").strip()


def data(ref, filename):
    return command("show", ref + ":" + filename).stdout


def paths_diff(ref):
    b = command("diff", "--no-renames", "--name-only", "-z", BASE, ref,
                "--", "DRMD-6DOF/").stdout
    return sorted(x.decode("utf-8") for x in b.split(b"\0") if x)


def files_at(ref, folder):
    b = command("ls-tree", "-r", "--name-only", "-z", ref, "--", folder).stdout
    return sorted(x.decode("utf-8") for x in b.split(b"\0") if x)


def sha(data_):
    return hashlib.sha256(data_).hexdigest()


def merge_preview():
    with tempfile.TemporaryDirectory(prefix="abaddon-merge-preview-") as td:
        work = Path(td) / "work"
        command("worktree", "add", "--detach", str(work), MAIN)
        try:
            p = command("-C", str(work), "-c", "user.name=Abaddon CI Preview",
                        "-c", "user.email=preview@localhost", "merge", "--no-commit",
                        "--no-ff", NATIVE, check=False)
            conflicts = command("-C", str(work), "diff", "--name-only", "-z",
                                "--diff-filter=U").stdout
            names = sorted(x.decode("utf-8") for x in conflicts.split(b"\0") if x)
            clean = p.returncode == 0 and not names
            return {"clean_textual_merge": clean, "exit_code": p.returncode,
                    "conflicts": names,
                    "output": (p.stdout + p.stderr).decode("utf-8", "replace")[-12000:],
                    "note": "This is an isolated dry-run. It does NOT include the second agent's unknown local work."}
        finally:
            command("-C", str(work), "merge", "--abort", check=False)
            command("worktree", "remove", "--force", str(work), check=False)


def verify_refs():
    for ref in [MAIN, NATIVE, BASE, REACTOR, DOCS]:
        command("cat-file", "-e", ref + "^{commit}")
    if command("merge-base", "--is-ancestor", BASE, MAIN, check=False).returncode:
        raise RuntimeError("BASE is not an ancestor of main")
    if command("merge-base", "--is-ancestor", BASE, NATIVE, check=False).returncode:
        raise RuntimeError("BASE is not an ancestor of native")
    if command("merge-base", "--is-ancestor", REACTOR, NATIVE, check=False).returncode:
        raise RuntimeError("Reactor is not in native history. Cannot claim included.")
    head = text_command("rev-parse", "HEAD")
    # Branch used for packaging must contain the original handoff folder.
    if not (ROOT / "handoff" / "agent2-2026-11-23" / "00_START_HERE_RU.md").is_file():
        raise RuntimeError("Previous 21-MD handoff files are absent")
    return head


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, type=Path)
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    pack_sha = verify_refs()
    main_changed, native_changed = paths_diff(MAIN), paths_diff(NATIVE)
    overlap = sorted(set(main_changed) & set(native_changed))
    port_paths = files_at(NATIVE, "DRMD-6DOF/native/hl2")
    required = {
        "DRMD-6DOF/native/hl2/source-2013-sp.patch",
        "DRMD-6DOF/native/hl2/abaddon_flight_math.h",
        "DRMD-6DOF/native/hl2/abaddon_flight_input.h",
        "DRMD-6DOF/native/hl2/setup_hl2.py",
        "DRMD-6DOF/native/hl2/maps/d6_native_flightlab.bsp",
        "DRMD-6DOF/native/hl2/maps/d6_native_flightlab.vmf",
        "DRMD-6DOF/native/hl2/BUILD_RESULTS_RU.txt",
    }
    if not required.issubset(port_paths):
        raise RuntimeError("Native port has missing expected files: " + repr(sorted(required-set(port_paths))))
    preview = merge_preview()
    report = {
        "schema": 1, "package_commit": pack_sha,
        "base_sha": BASE, "main_sha": MAIN, "native_sha": NATIVE,
        "reactor_sha": REACTOR, "original_docs_sha": DOCS,
        "native_includes_reactor": True, "second_agent_local_head": None,
        "second_agent_local_changes_synchronized": False,
        "main_changed_since_base": main_changed,
        "native_changed_since_base": native_changed,
        "common_changed_paths": overlap,
        "native_port_files": port_paths,
        "warning": "These are real source snapshots. Never overlay one branch's files blindly onto the other.",
    }
    content = {}
    def add(name, b):
        if name.startswith("/") or "\\" in name or any(x in ("", ".", "..") for x in name.split("/")):
            raise ValueError("Unsafe archive member: " + name)
        if name in content:
            raise ValueError("Duplicate archive member: " + name)
        content[name] = b

    # Complete original documentation and research, without replacing it.
    old = ROOT / "handoff" / "agent2-2026-11-23"
    for f in sorted(old.rglob("*")):
        if f.is_file():
            add("ORIGINAL_HANDOFF/" + f.relative_to(old).as_posix(), f.read_bytes())
    for filename in ["00_SYNC_FIRST_RU.md", "01_NATIVE_HL2_STATUS_RU.md",
                     "02_SYNC_CONTRACT_RU.md"]:
        add(filename, (Path(__file__).parent / filename).read_bytes())
    add("scripts/sync_agent_worktree.py",
        (Path(__file__).parent / "scripts/sync_agent_worktree.py").read_bytes())

    # The complete actual native Source SDK 2013 SP overlay INCLUDING binary BSP.
    for filename in port_paths:
        add("HL2_NATIVE_PORT/" + filename, data(NATIVE, filename))
    # Both sides' changed files, including reactor gameplay and compiled VMF/BSP assets.
    for title, ref, names in [("MAIN", MAIN, main_changed),
                              ("NATIVE", NATIVE, native_changed)]:
        missing = []
        for filename in names:
            p = command("show", ref + ":" + filename, check=False)
            if p.returncode:
                missing.append(filename)  # Deleted in this branch; recorded explicitly.
            else:
                add("BRANCH_DELTAS/" + title + "/" + filename, p.stdout)
        report[title.lower() + "_deleted_paths"] = missing

    # A real three-way reference for every path that both branches changed.
    for filename in overlap:
        for title, ref in [("BASE", BASE), ("MAIN", MAIN), ("NATIVE", NATIVE)]:
            p = command("show", ref + ":" + filename, check=False)
            if p.returncode:
                add("THREE_WAY/" + title + "/DELETED_PATHS.txt",
                    (filename + "\n").encode()) if False else None
            else:
                add("THREE_WAY/" + title + "/" + filename, p.stdout)

    add("SYNC_REPORT.json", (json.dumps(report, indent=2, ensure_ascii=False) + "\n").encode())
    add("MERGE_PREVIEW.json", (json.dumps(preview, indent=2, ensure_ascii=False) + "\n").encode())
    sums = "".join(sha(b) + "  " + name + "\n" for name, b in sorted(content.items()))
    add("CONTENTS_SHA256.txt", sums.encode("utf-8"))

    dest = args.out / NAME
    with zipfile.ZipFile(dest, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6,
                         allowZip64=True) as z:
        for name, b in sorted(content.items()):
            z.writestr(name, b)
    with zipfile.ZipFile(dest) as z:
        if z.testzip() is not None:
            raise RuntimeError("Invalid ZIP CRC")
        if set(z.namelist()) != set(content):
            raise RuntimeError("ZIP content mismatch")
        for name, b in content.items():
            if z.read(name) != b:
                raise RuntimeError("ZIP payload mismatch " + name)
    digest = sha(dest.read_bytes())
    (args.out / (NAME + ".sha256")).write_text(digest + "  " + NAME + "\n")
    (args.out / "MERGE_PREVIEW.json").write_bytes(content["MERGE_PREVIEW.json"])
    print(json.dumps({"zip": str(dest), "size": dest.stat().st_size,
                      "sha256": digest, "members": len(content),
                      "original_md": len(list(old.rglob("*.md"))),
                      "native_port_source_files": len(port_paths),
                      "native_changed_files": len(native_changed),
                      "main_changed_files": len(main_changed),
                      "paths_edited_both": len(overlap),
                      "preview": preview}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
