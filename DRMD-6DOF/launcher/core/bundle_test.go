package core

import (
	"archive/zip"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func packageFixture(t *testing.T, revision, script string, broken bool) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "Abaddon-Game.zip")
	f, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	z := zip.NewWriter(f)
	meta := bundleManifest{Project: bundleProject, Channel: "dev", Revision: revision,
		Targets: map[Profile]bundleTarget{GMod: {Status: "experimental"}, HL2Content: {Status: "content-only"}},
		Files:   make(map[string]bundleFile)}
	files := map[string]string{
		"maps/d6_city17_drain.bsp":                 "VBSP",
		"maps/d6_reactor_escape.bsp":               "VBSP",
		"lua/autorun/d6_autoload.lua":              script,
		"models/drmd/combine_elite.mdl":            "model",
		"models/drmd/combine_elite.vvd":            "model",
		"models/drmd/combine_elite.dx90.vtx":       "model",
		"models/drmd/combine_arc_elite.mdl":        "model",
		"models/drmd/combine_arc_elite.vvd":        "model",
		"models/drmd/combine_arc_elite.dx90.vtx":   "model",
		"materials/models/drmd/arc_shell.vmt":      "pattern",
		"materials/drmd/drmd_finish_arc_shell.vtf": "tex",
	}
	for name, content := range files {
		entry, err := z.Create("descent_scanner/" + name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := entry.Write([]byte(content)); err != nil {
			t.Fatal(err)
		}
		digest := fmt.Sprintf("%x", sha256.Sum256([]byte(content)))
		if broken && name == "lua/autorun/d6_autoload.lua" {
			digest = strings.Repeat("0", 64)
		}
		meta.Files[name] = bundleFile{SHA256: digest, Size: uint64(len(content))}
	}
	m, err := z.Create("manifest.json")
	if err != nil {
		t.Fatal(err)
	}
	if err := json.NewEncoder(m).Encode(meta); err != nil {
		t.Fatal(err)
	}
	if err := z.Close(); err != nil {
		t.Fatal(err)
	}
	if err := f.Close(); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestBundleInstallUpdateAndRollback(t *testing.T) {
	game := fixture(t)
	cfg := DefaultConfig()
	cfg.SteamPath = game.steam
	if err := os.RemoveAll(game.addon); err != nil {
		t.Fatal(err)
	}
	dest := filepath.Join(game.gmod, "garrysmod", "addons", "descent_scanner")
	data := filepath.Join(game.gmod, "garrysmod", "data", "test-save.txt")
	write(t, data, []byte("saved game"))
	a, b := strings.Repeat("a", 40), strings.Repeat("b", 40)
	first, second := packageFixture(t, a, "first", false), packageFixture(t, b, "second", false)
	for attempt := 0; attempt < 2; attempt++ {
		if got, err := InstallBundle(cfg, GMod, first); err != nil || got.Revision != a || !Detect(cfg).GMod.Ready {
			t.Fatalf("install: %+v, %v", got, err)
		}
	}
	if _, err := RollbackBundle(cfg, GMod); err == nil {
		t.Fatal("installing the same verified build made an unnecessary backup")
	}
	if got, err := InstallBundle(cfg, GMod, second); err != nil || got.Revision != b {
		t.Fatalf("update: %+v, %v", got, err)
	}
	if got, err := InstalledBuild(cfg, GMod); err != nil || got.Revision != b {
		t.Fatalf("installed build: %+v, %v", got, err)
	}
	if got, err := RollbackBundle(cfg, GMod); err != nil || got.Revision != a {
		t.Fatalf("rollback: %+v, %v", got, err)
	}
	if asset, _ := os.ReadFile(filepath.Join(dest, "lua", "autorun", "d6_autoload.lua")); string(asset) != "first" {
		t.Fatalf("wrong rolled-back asset: %q", asset)
	}
	if saved, _ := os.ReadFile(data); string(saved) != "saved game" {
		t.Fatal("user data changed")
	}
}

func TestBundleRejectsCorruptionAndPreservesCurrent(t *testing.T) {
	game := fixture(t)
	cfg := DefaultConfig()
	cfg.SteamPath = game.steam
	if err := os.RemoveAll(game.addon); err != nil {
		t.Fatal(err)
	}
	a := strings.Repeat("a", 40)
	if _, err := InstallBundle(cfg, GMod, packageFixture(t, a, "working", false)); err != nil {
		t.Fatal(err)
	}
	if _, err := InstallBundle(cfg, GMod, packageFixture(t, strings.Repeat("b", 40), "invalid", true)); err == nil {
		t.Fatal("corrupt archive was accepted")
	}
	dest, work, err := installLocation(cfg, GMod)
	if err != nil {
		t.Fatal(err)
	}
	if err := swapPayload(dest, filepath.Join(work, "missing"), work, GMod); err == nil {
		t.Fatal("test expected a failed rename")
	}
	if got, err := InstalledBuild(cfg, GMod); err != nil || got.Revision != a {
		t.Fatalf("working build was lost: %+v, %v", got, err)
	}
}

func TestBundleContentInstallsOnlyStockEngineAssets(t *testing.T) {
	game := fixture(t)
	cfg := DefaultConfig()
	cfg.SteamPath = game.steam
	payload := contentInstallPath(game.content)
	if err := os.RemoveAll(payload); err != nil {
		t.Fatal(err)
	}
	zipPath := packageFixture(t, strings.Repeat("a", 40), "gmod", false)
	if got, err := InstallBundle(cfg, HL2Content, zipPath); err != nil || got.Status != "content-only" ||
		!Detect(cfg).HL2Content.Ready || isDirectory(filepath.Join(payload, "lua")) {
		t.Fatalf("retail HL2 payload: %+v, %v", got, err)
	}
	if _, err := InstallBundle(cfg, HL2, zipPath); err == nil {
		t.Fatal("assets-only archive was accepted as native SDK build")
	}
	if _, err := InstallBundle(cfg, GMod, zipPath); err == nil {
		t.Fatal("installation duplicated the add-on in a second folder")
	}
}

func TestBundleRejectsUnsafePaths(t *testing.T) {
	for _, name := range []string{"../maps/test.bsp", "maps\\test.bsp", "C:/test.bsp",
		"maps/con.bsp", "models/fake. ", "strange\"name", "path//asset"} {
		if safeAssetPath(name) {
			t.Fatalf("unsafe path accepted: %q", name)
		}
	}
}
