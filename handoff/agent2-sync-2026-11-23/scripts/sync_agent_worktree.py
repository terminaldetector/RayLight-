#!/usr/bin/env python3
"""Non-destructive integration of an existing agent branch with pinned Abaddon main + native.
Never alters the original working tree or pushes; conflict resolution remains manual.
"""
import argparse
from pathlib import Path
import subprocess
import sys

MAIN = "d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d"
NATIVE = "5849463a3d3417a16d3cb98e32f8b13e83557bb9"


def git(repo, *args, check=True):
    p = subprocess.run(["git", "-C", str(repo), *args], text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and p.returncode:
        raise RuntimeError("git " + " ".join(args) + ":\n" + p.stderr.strip())
    return p


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo", required=True, type=Path, help="Existing second-agent Git worktree")
    ap.add_argument("--out", required=True, type=Path, help="NEW separate worktree path")
    ap.add_argument("--agent-ref", default="HEAD", help="Committed agent branch/ref (default HEAD)")
    args = ap.parse_args()
    root = args.repo.resolve()
    out = args.out.absolute()
    if not (root / ".git").exists():
        # Worktree .git is a file; both formats are fine.
        if not (root / ".git").is_file():
            raise RuntimeError("This is not an accessible Git worktree")
    if out.exists():
        raise RuntimeError("Output path exists; refusing to overwrite: " + str(out))
    if git(root, "status", "--porcelain", "--untracked-files=all").stdout.strip():
        raise RuntimeError("Original worktree has uncommitted/untracked work. Preserve it on an agent branch first. NO reset/clean performed.")
    agent = git(root, "rev-parse", "--verify", args.agent_ref + "^{commit}").stdout.strip()
    for name, ref in (("main", MAIN), ("native-flight", NATIVE)):
        if git(root, "cat-file", "-e", ref + "^{commit}", check=False).returncode:
            raise RuntimeError("Missing pinned " + name + " commit " + ref +
                               ". Fetch repository branches before rerunning.")
    branch = "sync/agent2-" + agent[:8] + "-" + MAIN[:7] + "-" + NATIVE[:7]
    if git(root, "show-ref", "--verify", "--quiet", "refs/heads/" + branch, check=False).returncode == 0:
        raise RuntimeError("Integration branch already exists: " + branch +
                           ". Continue that worktree manually; nothing was modified.")
    out.parent.mkdir(parents=True, exist_ok=True)
    git(root, "worktree", "add", "--detach", str(out), agent)
    git(out, "switch", "-c", branch)
    print("SOURCE AGENT SHA:", agent)
    print("MERGE WORKTREE:", out)
    print("ORIGINAL WORKTREE: untouched", root)
    print("Integrating pinned main...")
    main_merge = git(out, "-c", "merge.autostash=false",
                     "-c", "user.name=Abaddon Integration Preview",
                     "-c", "user.email=abaddon-preview@localhost",
                     "merge", "--no-ff", "--no-edit", MAIN, check=False)
    print(main_merge.stdout, main_merge.stderr, sep="\n")
    if main_merge.returncode:
        print("STOP: resolve main conflicts in new worktree only:", out)
        print("Then git add + git commit, followed by git merge --no-ff --no-commit " + NATIVE)
        return 2
    print("Integrating pinned native-flight without committing resolution...")
    native_merge = git(out, "-c", "merge.autostash=false",
                       "merge", "--no-ff", "--no-commit", NATIVE, check=False)
    print(native_merge.stdout, native_merge.stderr, sep="\n")
    print("WORKTREE STATUS:\n" + git(out, "status", "--short").stdout)
    if native_merge.returncode:
        print("STOP: native conflicts. Resolve manually. Never whole-file ours/theirs.")
        return 3
    print("Review merged code, C++ overlay, GMod menus, reactor maps and tests;")
    print("if MERGE_HEAD exists, finish with git commit. No push or main mutation was made.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError) as e:
        print("SYNC REFUSED: " + str(e), file=sys.stderr)
        sys.exit(1)
