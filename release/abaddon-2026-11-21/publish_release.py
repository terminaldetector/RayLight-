"""Publish the already-delivered Abaddon bytes, with a draft-first hash gate."""
import hashlib
import json
import os
from pathlib import Path
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile

REPO = "terminaldetector/RayLight-"
TAG = "abaddon-2026-11-21-windows"
SOURCE = "d231bbac538f289b069c6e6d14861b0a429bb3cd"
TITLE = "Half-Life: Abaddon — Windows Full (2026-11-21)"
EXPECTED = {
    "Half-Life-Abaddon-Full-Windows.zip": (71462863, "769bf07517f1da507ec1b2c201fa3a2c50d1bc9feffff6d0d50664fa59716583"),
    "AbaddonLauncher.exe": (3346432, "e5c6e893214ce0dcef410542a32cfb14a0de4988e5d033572c33596e6c5f00c4"),
    "ABADDON_WINDOWS_LAUNCHER_HANDOFF.md": (21512, "118d28cdf503607e8bc1ba84c4149a240320d8478232df2336cf920978b95d86"),
    "abaddon-build.json": (84425, "71ba6162bab26aadc4493182559cd441bf24aa6f2d98c359a4a5de62b9cfbb59"),
    "SHA256SUMS.txt": (374, "662fe34d10947aa407baa885332ceb497b3182b690d01551bd16138fb1792fd6"),
}
BASE = "https://api.github.com/repos/" + REPO


def sha(data):
    return hashlib.sha256(data).hexdigest()


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        redirected = super().redirect_request(request, fp, code, msg, headers, newurl)
        if redirected and urllib.parse.urlsplit(request.full_url).netloc != urllib.parse.urlsplit(newurl).netloc:
            redirected.remove_header("Authorization")
        return redirected


OPENER = urllib.request.build_opener(SafeRedirect())


def request(url, method="GET", payload=None, binary=False, allow_missing=False, raw=False):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname not in {"api.github.com", "uploads.github.com"}:
        raise RuntimeError("Unexpected GitHub API host")
    headers = {
        "Authorization": "Bearer " + os.environ["GH_TOKEN"],
        "Accept": "application/octet-stream" if raw else "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "Abaddon-release-publisher",
    }
    if payload is not None:
        headers["Content-Type"] = "application/octet-stream" if binary else "application/json"
        body = payload if binary else json.dumps(payload, ensure_ascii=False).encode("utf-8")
    else:
        body = None
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with OPENER.open(req, timeout=180) as response:
            data = response.read()
    except urllib.error.HTTPError as error:
        if error.code == 404 and allow_missing:
            return None
        detail = error.read(1500).decode("utf-8", "replace")
        raise RuntimeError(f"GitHub {method} failed: HTTP {error.code}: {detail}") from None
    return data if raw else json.loads(data)


def verify_asset(asset, name):
    size, expected_hash = EXPECTED[name]
    if asset.get("name") != name or asset.get("state") != "uploaded" or asset.get("size") != size:
        raise RuntimeError("Uploaded asset metadata mismatch: " + name)
    digest = asset.get("digest")
    if digest:
        if digest != "sha256:" + expected_hash:
            raise RuntimeError("Uploaded asset SHA-256 mismatch: " + name)
    else:
        data = request(asset["url"], raw=True)
        if len(data) != size or sha(data) != expected_hash:
            raise RuntimeError("Downloaded asset SHA-256 mismatch: " + name)
    print("Verified release asset:", name, expected_hash, flush=True)


def prepare(folder):
    source = folder / "Half-Life-Abaddon-Full-Windows.zip"
    size, digest = EXPECTED[source.name]
    data = source.read_bytes()
    if len(data) != size or sha(data) != digest:
        raise RuntimeError("Full ZIP does not match the delivered build")
    with zipfile.ZipFile(source) as archive:
        prefix = "Half-Life-Abaddon/"
        paths = {
            "AbaddonLauncher.exe": prefix + "AbaddonLauncher.exe",
            "ABADDON_WINDOWS_LAUNCHER_HANDOFF.md": prefix + "DRMD-6DOF/WINDOWS_LAUNCHER_HANDOFF_RU.md",
            "abaddon-build.json": prefix + "abaddon-build.json",
        }
        for name, member in paths.items():
            (folder / name).write_bytes(archive.read(member))
    (folder / "SHA256SUMS.txt").write_bytes(Path(__file__).with_name("SHA256SUMS.txt").read_bytes())
    for name, (size, digest) in EXPECTED.items():
        data = (folder / name).read_bytes()
        if len(data) != size or sha(data) != digest:
            raise RuntimeError("Local asset SHA-256 mismatch: " + name)
    print("All five local assets match the previously delivered files", flush=True)


def verify_tag(allow_missing=True):
    ref = request(BASE + "/git/ref/tags/" + TAG, allow_missing=allow_missing)
    if ref is None:
        return
    obj = ref["object"]
    for _ in range(8):
        if obj["type"] == "commit":
            if obj["sha"] != SOURCE:
                raise RuntimeError("Release tag points to a different source commit")
            return
        if obj["type"] != "tag":
            break
        obj = request(BASE + "/git/tags/" + obj["sha"])["object"]
    raise RuntimeError("Release tag cannot be resolved to the expected commit")


def find_release():
    matches = []
    page = 1
    while True:
        batch = request(BASE + "/releases?per_page=100&page=" + str(page))
        matches.extend(release for release in batch if release["tag_name"] == TAG)
        if len(batch) < 100:
            break
        page += 1
    if len(matches) > 1:
        raise RuntimeError("Multiple releases use the requested tag; leaving them unchanged")
    return matches[0] if matches else None


def publish(folder):
    prepare(folder)
    verify_tag()
    release = find_release()
    if release is None:
        release = request(BASE + "/releases", "POST", {
            "tag_name": TAG,
            "target_commitish": SOURCE,
            "name": TITLE,
            "body": Path(__file__).with_name("RELEASE_NOTES_RU.md").read_text(encoding="utf-8"),
            "draft": True,
            "prerelease": False,
        })
        print("Created release draft", release["id"], flush=True)
    if release.get("tag_name") != TAG or release.get("target_commitish") != SOURCE:
        raise RuntimeError("Existing release has an unexpected tag or source; leaving it unchanged")
    assets = release.get("assets", [])
    if len({asset["name"] for asset in assets}) != len(assets):
        raise RuntimeError("Release contains duplicate asset names")
    existing = {asset["name"]: asset for asset in assets}
    if set(existing) - set(EXPECTED):
        raise RuntimeError("Release contains unexpected assets; leaving it unchanged")
    for name in EXPECTED:
        if name in existing:
            verify_asset(existing[name], name)
            continue
        if not release["draft"]:
            raise RuntimeError("Published release is incomplete; refusing to modify it")
        upload_url = release["upload_url"].split("{", 1)[0] + "?" + urllib.parse.urlencode({"name": name})
        asset = request(upload_url, "POST", (folder / name).read_bytes(), binary=True)
        verify_asset(asset, name)
    checked = request(BASE + "/releases/" + str(release["id"]))
    if len(checked["assets"]) != len(EXPECTED) or {asset["name"] for asset in checked["assets"]} != set(EXPECTED):
        raise RuntimeError("Release asset list changed before publication")
    for asset in checked["assets"]:
        verify_asset(asset, asset["name"])
    verify_tag()
    if checked.get("tag_name") != TAG or checked.get("target_commitish") != SOURCE:
        raise RuntimeError("Release source changed before publication")
    if checked["draft"]:
        checked = request(BASE + "/releases/" + str(release["id"]), "PATCH", {"draft": False, "make_latest": "true"})
    if checked["draft"]:
        raise RuntimeError("Release is still a draft")
    verify_tag(allow_missing=False)
    print("Published:", checked["html_url"], flush=True)
    for asset in checked["assets"]:
        print(asset["name"], asset["browser_download_url"], flush=True)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as output:
            output.write("## Abaddon Windows full build\n\n[Published release](" + checked["html_url"] + ")\n\n")
            output.write("All five attached files match the SHA-256 of the previously delivered build.\n")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--verify-only":
        prepare(Path(sys.argv[2]))
    elif len(sys.argv) == 2:
        publish(Path(sys.argv[1]))
    else:
        raise SystemExit("Usage: publish_release.py [--verify-only] ASSET_FOLDER")
