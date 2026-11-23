package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strconv"
	"strings"
	"testing"
)

func put(t *testing.T, name, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(name), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(name, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
}

func get(t *testing.T, name string) string {
	t.Helper()
	b, err := os.ReadFile(name)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func gameAt(t *testing.T, root string, target Target) Installation {
	t.Helper()
	game, exe := "garrysmod", "bin/win64/gmod.exe"
	if target == TargetHL2 || target == TargetHL2Native {
		game, exe = "hl2", "hl2.exe"
	}
	put(t, filepath.Join(root, game, "gameinfo.txt"), "\"GameInfo\" { \"game\" \"Fixture\" }")
	put(t, filepath.Join(root, filepath.FromSlash(exe)), "MZ-test-executable")
	inst, err := ValidateInstallation(root, target)
	if err != nil {
		t.Fatal(err)
	}
	return inst
}

func bundleAt(t *testing.T, root, revision string, files map[string]string) BuildManifest {
	t.Helper()
	m := BuildManifest{Schema: 1, Project: "Half-Life: Abaddon", Revision: strings.Repeat(revision, 40), Channel: "main", PayloadRoot: "payload/descent_scanner"}
	for name, body := range files {
		put(t, filepath.Join(root, filepath.FromSlash(m.PayloadRoot), filepath.FromSlash(name)), body)
		hash := sha256.Sum256([]byte(body))
		m.Files = append(m.Files, ManifestFile{Path: name, SHA256: hex.EncodeToString(hash[:]), Size: int64(len(body))})
	}
	sort.Slice(m.Files, func(i, j int) bool { return m.Files[i].Path < m.Files[j].Path })
	writeManifest(t, root, m)
	return m
}

func writeManifest(t *testing.T, root string, m BuildManifest) {
	t.Helper()
	b, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	put(t, filepath.Join(root, "abaddon-build.json"), string(b))
}

func TestValidateInstallationNormalizesGameAndWin64Exe(t *testing.T) {
	root := filepath.Join(t.TempDir(), "Игры Space", "GarrysMod")
	want := gameAt(t, root, TargetGMod)
	for _, selected := range []string{root, want.GameDir, want.Executable} {
		got, err := ValidateInstallation(selected, TargetGMod)
		if err != nil || got != want {
			t.Fatalf("selected %s: %#v, %v", selected, got, err)
		}
	}
	if _, err := ValidateInstallation(root, TargetHL2); err == nil {
		t.Fatal("accepted GMod as an HL2 installation without HL2 proof")
	}
	if _, err := ValidateInstallation("", TargetGMod); err == nil {
		t.Fatal("accepted an empty selection")
	}
	if err := os.Remove(filepath.Join(want.GameDir, "gameinfo.txt")); err != nil {
		t.Fatal(err)
	}
	if _, err := ValidateInstallation(root, TargetGMod); err == nil {
		t.Fatal("accepted an executable without gameinfo")
	}
}

func TestDiscoverModernAndLegacySteamLibraries(t *testing.T) {
	base := t.TempDir()
	steam := filepath.Join(base, "Steam Main")
	modern := filepath.Join(base, "Библиотека Игры")
	legacy := filepath.Join(base, "Old Library")
	put(t, filepath.Join(steam, "steam.exe"), "MZ-steam")
	gmod := gameAt(t, filepath.Join(modern, "steamapps", "common", "Garrys Mod Renamed"), TargetGMod)
	hl2 := gameAt(t, filepath.Join(legacy, "steamapps", "common", "Half-Life 2"), TargetHL2)
	put(t, filepath.Join(steam, "steamapps", "libraryfolders.vdf"), "\ufeff\"libraryfolders\" { // modern\n\"0\" { \"path\" "+strconv.Quote(steam)+" } \"1\" { \"path\" "+strconv.Quote(modern)+" \"apps\" { \"4000\" \"1234\" } } }")
	put(t, filepath.Join(steam, "config", "libraryfolders.vdf"), "\"LibraryFolders\" { \"TimeNextStatsReport\" \"99\" \"1\" "+strconv.Quote(legacy)+" }")
	put(t, filepath.Join(modern, "steamapps", "appmanifest_4000.acf"), "\"AppState\" { \"appid\" \"4000\" \"installdir\" \"Garrys Mod Renamed\" }")
	put(t, filepath.Join(legacy, "steamapps", "appmanifest_220.acf"), "\"AppState\" { \"appid\" \"220\" \"installdir\" \"Half-Life 2\" }")
	got := DiscoverInstallations([]string{steam, steam, filepath.Join(base, "Missing")})
	if len(got) != 2 {
		t.Fatalf("expected two installations: %#v", got)
	}
	if got[0].Root != gmod.Root || got[1].Root != hl2.Root || got[0].SteamRoot != steam || got[1].SteamRoot != steam {
		t.Fatalf("wrong installation roots: %#v", got)
	}
	put(t, filepath.Join(modern, "steamapps", "appmanifest_4000.acf"), "\"AppState\" { \"appid\" \"4000\" \"installdir\" \"../../escape\" }")
	if found := DiscoverInstallations([]string{steam}); len(found) != 1 || found[0].Target != TargetHL2 {
		t.Fatalf("unsafe manifest path was accepted: %#v", found)
	}
}

func TestVDFWindowsEscapesAndMalformedBlocks(t *testing.T) {
	nodes, err := parseVDF(`"libraryfolders" { "1" { "path" "D:\\Игры\\Steam Library" "label" "quote \"here\"" } }`)
	if err != nil {
		t.Fatal(err)
	}
	folders, _ := vdfFind(nodes, "libraryfolders")
	value, _ := vdfFind(folders.children[0].children, "path")
	if value.value != `D:\Игры\Steam Library` {
		t.Fatalf("escaped path changed: %q", value.value)
	}
	for _, input := range []string{`"k" {`, `"k" "unfinished`, `}`, `"key" }`} {
		if _, err := parseVDF(input); err == nil {
			t.Fatalf("accepted malformed VDF: %s", input)
		}
	}
}

func TestManifestRejectsTraversalAliasesAndCollisions(t *testing.T) {
	root := t.TempDir()
	base := bundleAt(t, root, "a", map[string]string{"lua/ok.lua": "hello"})
	for _, name := range []string{"../escape", "/absolute", `lua\escape`, "lua/../escape", "lua/x:stream", "lua/CON.txt", "lua/trailing.", "lua/a?b", receiptName} {
		t.Run(name, func(t *testing.T) {
			m := base
			m.Files = append([]ManifestFile(nil), base.Files...)
			m.Files[0].Path = name
			writeManifest(t, root, m)
			if _, err := LoadManifest(root); err == nil {
				t.Fatalf("accepted unsafe manifest path %q", name)
			}
		})
	}
	m := base
	m.Files = append(append([]ManifestFile(nil), base.Files...), base.Files[0])
	m.Files[1].Path = "LUA/OK.LUA"
	writeManifest(t, root, m)
	if _, err := LoadManifest(root); err == nil {
		t.Fatal("accepted case-insensitive duplicate")
	}
	m = base
	m.PayloadRoot = "../outside"
	writeManifest(t, root, m)
	if _, err := LoadManifest(root); err == nil {
		t.Fatal("accepted payload-root traversal")
	}
	m = base
	m.Revision = "abc123"
	writeManifest(t, root, m)
	if _, err := LoadManifest(root); err == nil {
		t.Fatal("accepted a short, ambiguous source revision")
	}
}

func TestCorruptOrMissingPayloadLeavesOldInstallationIntact(t *testing.T) {
	for _, mode := range []string{"corrupt", "missing"} {
		t.Run(mode, func(t *testing.T) {
			root := t.TempDir()
			inst := gameAt(t, filepath.Join(root, "game"), TargetGMod)
			dest := installationDestination(inst)
			put(t, filepath.Join(dest, "legacy.txt"), "keep original")
			bundle := filepath.Join(root, "bundle")
			m := bundleAt(t, bundle, "a", map[string]string{"lua/init.lua": "new payload"})
			source := filepath.Join(bundle, filepath.FromSlash(m.PayloadRoot), "lua", "init.lua")
			if mode == "corrupt" {
				put(t, source, "bad payload") // Same size: digest, not size, must catch it.
			} else if err := os.Remove(source); err != nil {
				t.Fatal(err)
			}
			if _, err := InstallBundle(bundle, inst); err == nil {
				t.Fatal("installed a broken payload")
			}
			if get(t, filepath.Join(dest, "legacy.txt")) != "keep original" {
				t.Fatal("old installation changed")
			}
			if _, err := os.Stat(filepath.Join(inst.GameDir, stateDirectory)); !os.IsNotExist(err) {
				t.Fatal("created transaction state before verifying source")
			}
		})
	}
}

func TestUpgradePreservesUnknownFilesRetiresOnlyOwnedAndRollsBack(t *testing.T) {
	root := t.TempDir()
	inst := gameAt(t, filepath.Join(root, "game"), TargetGMod)
	dest := installationDestination(inst)
	put(t, filepath.Join(dest, "my-data", "notes.txt"), "user notes")
	put(t, filepath.Join(inst.GameDir, "addons", "unrelated", "keep.lua"), "other addon")
	bundle1, bundle2 := filepath.Join(root, "bundle1"), filepath.Join(root, "bundle2")
	bundleAt(t, bundle1, "a", map[string]string{"lua/init.lua": "version one", "lua/retired.lua": "old owned", "maps/test.bsp": "VBSP"})
	bundleAt(t, bundle2, "b", map[string]string{"lua/init.lua": "version two", "maps/test.bsp": "VBSP"})
	if installed, err := InstallBundle(bundle1, inst); err != nil || installed != dest {
		t.Fatalf("initial install: %s, %v", installed, err)
	}
	put(t, filepath.Join(dest, "lua", "user-extra.lua"), "user script")
	if _, err := InstallBundle(bundle2, inst); err != nil {
		t.Fatal(err)
	}
	if get(t, filepath.Join(dest, "lua", "init.lua")) != "version two" || get(t, filepath.Join(dest, "my-data", "notes.txt")) != "user notes" || get(t, filepath.Join(dest, "lua", "user-extra.lua")) != "user script" {
		t.Fatal("upgrade lost user files or did not update managed content")
	}
	if _, err := os.Stat(filepath.Join(dest, "lua", "retired.lua")); !os.IsNotExist(err) {
		t.Fatal("stale owned file was not retired")
	}
	if get(t, filepath.Join(inst.GameDir, "addons", "unrelated", "keep.lua")) != "other addon" {
		t.Fatal("unrelated addon changed")
	}
	entries, _ := os.ReadDir(filepath.Join(inst.GameDir, "addons"))
	if len(entries) != 2 {
		t.Fatalf("staging/backup leaked into Source addon search path: %#v", entries)
	}
	if _, err := RollbackInstallation(inst); err != nil {
		t.Fatal(err)
	}
	if get(t, filepath.Join(dest, "lua", "init.lua")) != "version one" || get(t, filepath.Join(dest, "lua", "retired.lua")) != "old owned" || get(t, filepath.Join(dest, "lua", "user-extra.lua")) != "user script" {
		t.Fatal("rollback did not restore the complete previous installation")
	}
	if _, err := RollbackInstallation(inst); err != nil {
		t.Fatal(err)
	}
	if get(t, filepath.Join(dest, "lua", "init.lua")) != "version two" {
		t.Fatal("rollback discarded the displaced current installation")
	}
}

func TestHL2InstallsOnlyContentAndChecksEntireBundle(t *testing.T) {
	root := t.TempDir()
	inst := gameAt(t, filepath.Join(root, "game"), TargetHL2)
	bundle := filepath.Join(root, "bundle")
	m := bundleAt(t, bundle, "a", map[string]string{
		"maps/test.bsp": "VBSP", "models/drmd/test.mdl": "MDL", "materials/drmd/test.vmt": "VMT", "lua/init.lua": "Lua content", "addon.json": "{}",
	})
	dest, err := InstallBundle(bundle, inst)
	if err != nil {
		t.Fatal(err)
	}
	if dest != filepath.Join(inst.GameDir, "custom", "drmd") || get(t, filepath.Join(dest, "maps", "test.bsp")) != "VBSP" {
		t.Fatal("wrong HL2 content destination")
	}
	for _, excluded := range []string{"lua", "addon.json"} {
		if _, err := os.Stat(filepath.Join(dest, excluded)); !os.IsNotExist(err) {
			t.Fatalf("HL2 content target received %s", excluded)
		}
	}
	put(t, filepath.Join(bundle, filepath.FromSlash(m.PayloadRoot), "lua", "init.lua"), "corrupted!!")
	if _, err := InstallBundle(bundle, inst); err == nil {
		t.Fatal("did not validate source files excluded from the HL2 target")
	}
}

func TestSourceAndExistingSymlinksCannotEscapeInstall(t *testing.T) {
	root := t.TempDir()
	outside := filepath.Join(root, "outside")
	put(t, filepath.Join(outside, "keep.txt"), "outside")
	probe := filepath.Join(root, "probe-link")
	if err := os.Symlink(outside, probe); err != nil {
		t.Skipf("symlinks unavailable: %v", err)
	}
	inst := gameAt(t, filepath.Join(root, "game"), TargetGMod)
	bundle := filepath.Join(root, "bundle")
	m := bundleAt(t, bundle, "a", map[string]string{"lua/init.lua": "new payload"})
	dest := installationDestination(inst)
	if err := os.MkdirAll(dest, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(dest, "user-link")); err != nil {
		t.Fatal(err)
	}
	if _, err := InstallBundle(bundle, inst); err == nil {
		t.Fatal("accepted symlink in old payload")
	}
	if get(t, filepath.Join(outside, "keep.txt")) != "outside" {
		t.Fatal("touched outside directory")
	}
	source := filepath.Join(bundle, filepath.FromSlash(m.PayloadRoot), "lua", "init.lua")
	if err := os.Remove(source); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(outside, "keep.txt"), source); err != nil {
		t.Fatal(err)
	}
	if _, err := VerifyBundle(bundle); err == nil {
		t.Fatal("accepted symlink in source payload")
	}
}

func TestInterruptedTransactionStopsWithoutDiscardingBackup(t *testing.T) {
	root := t.TempDir()
	inst := gameAt(t, filepath.Join(root, "game"), TargetGMod)
	bundleAt(t, filepath.Join(root, "bundle"), "a", map[string]string{"lua/init.lua": "new"})
	state := filepath.Join(inst.GameDir, stateDirectory)
	put(t, filepath.Join(state, "transaction.json"), `{"backup":"retained"}`)
	put(t, filepath.Join(state, "backup-gmod-retained", "old.txt"), "original")
	if _, err := InstallBundle(filepath.Join(root, "bundle"), inst); err == nil || !strings.Contains(err.Error(), "interrupted") {
		t.Fatalf("missing recovery diagnostic: %v", err)
	}
	if get(t, filepath.Join(state, "backup-gmod-retained", "old.txt")) != "original" {
		t.Fatal("discarded recovery backup")
	}
}

func TestFailedCommitRestoresOriginalAndConcurrentOperationIsRejected(t *testing.T) {
	inst := gameAt(t, filepath.Join(t.TempDir(), "game"), TargetGMod)
	dest := installationDestination(inst)
	put(t, filepath.Join(dest, "old.txt"), "original")
	state, release, err := openState(inst)
	if err != nil {
		t.Fatal(err)
	}
	defer release()
	if _, _, err := openState(inst); err == nil {
		t.Fatal("accepted overlapping installation operation")
	}
	// A failed second rename must restore the first directory, not expose an
	// empty addon or remove the original. Exercise real filesystem errors.
	if err := commitDirectory(state, dest, filepath.Join(state, "missing-stage"), TargetGMod, "install"); err == nil {
		t.Fatal("expected the missing replacement to fail")
	}
	if get(t, filepath.Join(dest, "old.txt")) != "original" {
		t.Fatal("failed commit did not restore original content")
	}
	if _, err := os.Stat(filepath.Join(state, "transaction.json")); !os.IsNotExist(err) {
		t.Fatal("completed automatic restoration left a transaction marker")
	}
}

func TestConfigureLaunchExactSteamArgumentsAndOwnedConfig(t *testing.T) {
	root := t.TempDir()
	inst := gameAt(t, filepath.Join(root, "Garrys Mod"), TargetGMod)
	inst.SteamRoot = filepath.Join(root, "Steam Main")
	put(t, filepath.Join(inst.SteamRoot, "steam.exe"), "MZ-Steam")
	put(t, filepath.Join(inst.GameDir, "cfg", "autoexec.cfg"), "user settings")
	put(t, filepath.Join(installationDestination(inst), "maps", "d6_relay_vault.bsp"), "VBSP")
	opts := LaunchOptions{Map: "d6_relay_vault", Graphics: "high", Width: 1920, Height: 1080, Windowed: true, Console: true}
	exe, args, err := ConfigureLaunch(inst, opts)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"-applaunch", "4000", "-novid", "-windowed", "-w", "1920", "-h", "1080", "-console", "+gamemode", "sandbox", "+exec", "abaddon_launcher.cfg", "+map", "d6_relay_vault"}
	if exe != filepath.Join(inst.SteamRoot, "steam.exe") || !reflect.DeepEqual(args, want) {
		t.Fatalf("launch mismatch: %q %#v", exe, args)
	}
	cfgPath := filepath.Join(inst.GameDir, "cfg", configName)
	cfg := get(t, cfgPath)
	if !strings.HasPrefix(cfg, configMarker) || !strings.Contains(cfg, "r_flashlightdepthres 2048\n") || !strings.Contains(cfg, "mat_forceaniso 16\n") {
		t.Fatalf("wrong graphics config: %s", cfg)
	}
	if get(t, filepath.Join(inst.GameDir, "cfg", "autoexec.cfg")) != "user settings" {
		t.Fatal("changed autoexec")
	}
	_, args, err = ConfigureLaunch(inst, LaunchOptions{Graphics: "default"})
	if err != nil || strings.Contains(strings.Join(args, " "), "+exec") || get(t, cfgPath) != cfg {
		t.Fatalf("default changed settings: %#v %v", args, err)
	}
	put(t, cfgPath, "user file using the same name")
	if _, _, err := ConfigureLaunch(inst, opts); err == nil {
		t.Fatal("overwrote an unowned config")
	}
	if get(t, cfgPath) != "user file using the same name" {
		t.Fatal("unowned config changed")
	}
}

func TestLaunchRejectsCommandInjectionAndUsesValidatedFallback(t *testing.T) {
	root := t.TempDir()
	inst := gameAt(t, filepath.Join(root, "HL2"), TargetHL2)
	if _, _, err := ConfigureLaunch(inst, LaunchOptions{Map: "d6_city17_drain", Graphics: "high"}); err == nil || !strings.Contains(err.Error(), "сначала установите пакет") {
		t.Fatalf("missing map did not produce install instruction: %v", err)
	}
	if _, err := os.Stat(filepath.Join(inst.GameDir, "cfg", configName)); !os.IsNotExist(err) {
		t.Fatal("wrote graphics settings before checking the installed map")
	}
	if _, _, err := ConfigureLaunch(inst, LaunchOptions{}); err != nil {
		t.Fatalf("game menu launch should not require installed addon content: %v", err)
	}
	put(t, filepath.Join(installationDestination(inst), "maps", "d6_city17_drain.bsp"), "VBSP")
	exe, args, err := ConfigureLaunch(inst, LaunchOptions{Map: "d6_city17_drain"})
	if err != nil || exe != inst.Executable || !reflect.DeepEqual(args, []string{"-game", "hl2", "-novid", "-fullscreen", "+map", "d6_city17_drain"}) {
		t.Fatalf("HL2 fallback mismatch: %s %#v %v", exe, args, err)
	}
	for _, opts := range []LaunchOptions{
		{Map: "d6_relay_vault; quit"}, {Map: "../outside"}, {Graphics: "high; quit"}, {Width: 1920}, {Width: -1, Height: 1080}, {Width: 99999, Height: 1080},
	} {
		if _, _, err := ConfigureLaunch(inst, opts); err == nil {
			t.Fatalf("accepted unsafe launch input: %#v", opts)
		}
	}
}
