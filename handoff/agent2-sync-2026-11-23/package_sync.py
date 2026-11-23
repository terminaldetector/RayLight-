#!/usr/bin/env python3
"""Pin, pack and hash original Agent2 Markdown + true HL2 native and reactor sources."""
from __future__ import annotations
import argparse,hashlib,io,json,pathlib,subprocess,zipfile

ROOT=pathlib.Path(__file__).resolve().parents[2]
HERE=pathlib.Path(__file__).resolve().parent
MAIN="d9cf3c15e3f9fdeaa1c3e608eaa2a3f21791697d"
REACTOR="28656ac7f2a4c989d208a066b78f6c280cfcd5e1"
NATIVE="5849463a3d3417a16d3cb98e32f8b13e83557bb9"
BASE="6cb7848069c6422632672f626a1346532dfa942e"
OLD_SHA256="01cb37ebab62c8f8dd62e83754e1e5b445f64972d765c3fa2c6ab000f98ef6eb"
OLD=ROOT/"handoff/Abaddon-Agent2-Handoff-2026-11-23.zip"
OUTNAME="Abaddon-Agent2-SYNC-HL2-2026-11-23.zip"

def git(*args,text=False):
    p=subprocess.run(["git",*args],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True)
    return p.stdout.decode("utf-8") if text else p.stdout
def sha(data):return hashlib.sha256(data).hexdigest()
def checked(name):
    parts=pathlib.PurePosixPath(name).parts
    if not parts or ".." in parts or name.startswith(("/","\\")) or "\\" in name:raise ValueError("Unsafe path "+repr(name))
    return name
def info(name):
    obj=zipfile.ZipInfo(checked(name),(2026,11,23,0,0,0))
    obj.compress_type=zipfile.ZIP_DEFLATED
    obj.external_attr=0o644<<16
    return obj
def paths(ref,*dirs):
    return [b.decode("utf-8") for b in git("ls-tree","-r","-z","--name-only",ref,"--",*dirs).split(b"\0") if b]
def changed(base,head,only_added_modified=False):
    opt=["--diff-filter=AM"] if only_added_modified else []
    return [b.decode("utf-8") for b in git("diff","--no-renames","--name-only","-z",*opt,base,head,"--","DRMD-6DOF/").split(b"\0") if b]
def nested(sources,extra):
    buff=io.BytesIO(); records=[]
    with zipfile.ZipFile(buff,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=6) as out:
        for name,ref in sorted(sources):
            data=git("show",ref+":"+name)
            out.writestr(info(name),data)
            records.append({"path":name,"commit":ref,"size":len(data),"sha256":sha(data)})
        out.writestr(info("PINNED_SOURCES.json"),json.dumps(extra,ensure_ascii=False,indent=2).encode())
    return buff.getvalue(),records
def run():
    arg=argparse.ArgumentParser()
    arg.add_argument("--out",required=True,type=pathlib.Path)
    out=arg.parse_args().out
    out.mkdir(parents=True,exist_ok=True)
    for rev in [MAIN,REACTOR,NATIVE,BASE]:git("cat-file","-e",rev+"^{commit}")
    if git("merge-base",MAIN,NATIVE,text=True).strip()!=BASE:raise SystemExit("ERROR: unexpected merge base")
    git("merge-base","--is-ancestor",REACTOR,NATIVE)
    original=OLD.read_bytes()
    if sha(original)!=OLD_SHA256:raise SystemExit("ERROR: original 21-MD ZIP SHA mismatch")
    nfiles=[(p,NATIVE) for p in paths(NATIVE,"DRMD-6DOF/native/hl2")]
    if not any(p.endswith("/source-2013-sp.patch") for p,_ in nfiles):raise SystemExit("ERROR: native SDK patch not found")
    nfiles += [("DRMD-6DOF/tools/build_native_flightlab.py",NATIVE),("DRMD-6DOF/tools/build_episode.py",REACTOR)]
    native,manifest_native=nested(nfiles,{"branch":"feat/abaddon-native-flight","commit":NATIVE,"reactor_dependency":REACTOR,"external_valve_sdk_commit":"77567eb4bce8d7b6b7f73e929fcde3a331c0216e","native_windows_dll_included":False})
    changed_reactor=changed(BASE,REACTOR,True)
    if not any("d6_rogue_reactor.vmf" in p for p in changed_reactor):raise SystemExit("ERROR: missing reactor map")
    reactor,manifest_reactor=nested([(p,REACTOR) for p in changed_reactor],{"branch":"feat/abaddon-reactor","commit":REACTOR,"common_base":BASE,"do_not_overwrite_main":True})
    (out/"HL2_NATIVE_PORT_SOURCE.zip").write_bytes(native)
    (out/"REACTOR_BRANCH_CHANGED_FILES.zip").write_bytes(reactor)
    main_paths=set(changed(BASE,MAIN))
    native_paths=set(changed(BASE,NATIVE))
    common=sorted(main_paths & native_paths)
    overlaps={"main":MAIN,"reactor":REACTOR,"native":NATIVE,"merge_base":BASE,"main_changed_count":len(main_paths),"native_changed_count":len(native_paths),"overlap_count":len(common),"overlap_paths":common,"note":"These are overlapping file paths, not necessarily text merge conflicts or unknown agent-local changes."}
    overlap_text="# Потенциальные пересечения main и native\n\nОбщий предок: "+BASE+"\n\nОбщие изменённые пути: "+str(len(common))+". Никакого принудительного overwrite.\n\n"+"\n".join("- "+p for p in common)+"\n\nТочные конфликты проверяйте в GIT_MERGE_PREVIEW.txt. Непубликованная работа второго агента здесь не представлена.\n"
    pr=subprocess.run(["git","merge-tree","--write-tree",MAIN,NATIVE],cwd=ROOT,capture_output=True,text=True)
    mergepreview="Non-mutating git merge-tree "+MAIN+" "+NATIVE+"\nExit code: "+str(pr.returncode)+" (0=clean, 1=conflicts).\nLocal agent work not included.\n\n"+pr.stdout+"\n"+pr.stderr
    provenance={"source_sha":{"main":MAIN,"reactor":REACTOR,"native":NATIVE,"merge_base":BASE},"previous_zip_sha256":OLD_SHA256,"native_files":manifest_native,"reactor_files":manifest_reactor,"local_agent_work_included":False,"status":"SYNC_PENDING_AGENT_WORKTREE"}
    name=out/OUTNAME; md_count=0; filebytes={}
    with zipfile.ZipFile(name,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=6,allowZip64=True) as outer:
        def add(path,data):
            raw=data if isinstance(data,bytes) else data.encode("utf-8")
            if path in filebytes:raise ValueError("Duplicate archive path: "+path)
            outer.writestr(info(path),raw);filebytes[path]=raw
        for p in ["README_RU.md","00_SYNC_FIRST_RU.md","07_HL2_PORT_AND_REACTOR_RU.md","SYNC_WORKTREE_CHECKLIST_RU.md"]:
            add(p,(HERE/p).read_bytes())
        with zipfile.ZipFile(io.BytesIO(original)) as prior:
            for z in prior.infolist():
                if z.is_dir():continue
                p=checked(z.filename)
                add("CONTEXT_21_MD/"+p,prior.read(z))
                if p.lower().endswith(".md"):md_count+=1
        if md_count<21:raise SystemExit("ERROR: original Markdown file count "+str(md_count))
        add("HL2_NATIVE_PORT_SOURCE.zip",native)
        add("REACTOR_BRANCH_CHANGED_FILES.zip",reactor)
        add("BRANCH_OVERLAPS.json",json.dumps(overlaps,ensure_ascii=False,indent=2))
        add("MERGE_OVERLAPS_RU.md",overlap_text)
        add("GIT_MERGE_PREVIEW.txt",mergepreview)
        add("SOURCE_PROVENANCE.json",json.dumps(provenance,ensure_ascii=False,indent=2))
        add("SHA256SUMS.txt","".join(sha(data)+"  "+p+"\n" for p,data in sorted(filebytes.items())))
    with zipfile.ZipFile(name) as z:
        if z.testzip() is not None:raise SystemExit("ERROR: invalid ZIP CRC")
        if len(z.namelist())!=len(set(z.namelist())):raise SystemExit("ERROR: duplicate archive paths")
    (out/"README_RU.md").write_bytes((HERE/"README_RU.md").read_bytes())
    assets=[OUTNAME,"HL2_NATIVE_PORT_SOURCE.zip","REACTOR_BRANCH_CHANGED_FILES.zip","README_RU.md"]
    (out/"SHA256SUMS.txt").write_text("".join(sha((out/n).read_bytes())+"  "+n+"\n" for n in assets),encoding="utf-8")
    summary={"archive":OUTNAME,"archive_sha256":sha(name.read_bytes()),"archive_size":name.stat().st_size,
             "previous_md_count":md_count,"native_source_files":len(manifest_native),"reactor_changed_files":len(manifest_reactor),
             "common_changed_paths":len(common),"merge_preview_exit_code":pr.returncode,"source_sha":provenance["source_sha"],
             "agent_local_work":"UNAVAILABLE"}
    (out/"BUILD_SUMMARY.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(summary,ensure_ascii=False,indent=2))
if __name__=="__main__":run()
