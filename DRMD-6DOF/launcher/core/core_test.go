package core

import (
	"bytes"
	"debug/pe"
	"encoding/binary"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func write(t *testing.T, filename string, contents []byte) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(filename), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filename, contents, 0o644); err != nil {
		t.Fatal(err)
	}
}

func makeDLL(t *testing.T, path string, machine uint16, registration string) {
	t.Helper()
	dos := make([]byte, 0x80)
	copy(dos[:], "MZ")
	binary.LittleEndian.PutUint32(dos[0x3c:], 0x80)
	optional := pe.OptionalHeader32{Magic: 0x10b, NumberOfRvaAndSizes: 16}
	literal := []byte(registration + "\x00")
	section := pe.SectionHeader32{SizeOfRawData: uint32(len(literal))}
	copy(section.Name[:], ".rdata")
	section.PointerToRawData = uint32(len(dos) + 4 + binary.Size(pe.FileHeader{}) + binary.Size(optional) + binary.Size(section))
	var dll bytes.Buffer
	dll.Write(dos)
	dll.WriteString("PE\x00\x00")
	for _, item := range []any{
		pe.FileHeader{Machine: machine, NumberOfSections: 1, SizeOfOptionalHeader: uint16(binary.Size(optional)), Characteristics: pe.IMAGE_FILE_DLL},
		optional,
		section,
	} {
		if err := binary.Write(&dll, binary.LittleEndian, item); err != nil {
			t.Fatal(err)
		}
	}
	dll.Write(literal)
	write(t, path, dll.Bytes())
}

func quoted(path string) string {
	return fmt.Sprintf("%q", path)
}

type installation struct {
	steam, library, gmod, addon, sdk, mod, content string
}

func fixture(t *testing.T) installation {
	t.Helper()
	root := t.TempDir()
	install := installation{
		steam:   filepath.Join(root, "Steam Install"),
		library: filepath.Join(root, "Игры Steam"),
	}
	common := filepath.Join(install.library, "steamapps", "common")
	install.gmod = filepath.Join(common, "GarrysMod Renamed")
	install.sdk = filepath.Join(common, "Source SP SDK")
	install.content = filepath.Join(common, "Half-Life 2 Renamed")
	install.addon = filepath.Join(install.gmod, "garrysmod", "addons", "Abaddon from archive")
	install.mod = filepath.Join(install.steam, "steamapps", "sourcemods", "abaddon_native")
	write(t, filepath.Join(install.steam, "steam.exe"), nil)
	write(t, filepath.Join(install.steam, "steamapps", "libraryfolders.vdf"),
		[]byte(fmt.Sprintf(`"libraryfolders" { "1" { "path" %s "apps" { "4000" "1" } } }`, quoted(install.library))))
	write(t, filepath.Join(install.library, "steamapps", "appmanifest_4000.acf"),
		[]byte(`"AppState" { "appid" "4000" "installdir" "GarrysMod Renamed" }`))
	write(t, filepath.Join(install.library, "steamapps", "appmanifest_243730.acf"),
		[]byte(`"AppState" { "appid" "243730" "installdir" "Source SP SDK" }`))
	write(t, filepath.Join(install.library, "steamapps", "appmanifest_220.acf"),
		[]byte(`"AppState" { "appid" "220" "installdir" "Half-Life 2 Renamed" }`))
	write(t, filepath.Join(install.gmod, "bin", "win64", "gmod.exe"), nil)
	write(t, filepath.Join(install.addon, "lua", "autorun", "d6_autoload.lua"), nil)
	write(t, filepath.Join(install.addon, "maps", "d6_city17_drain.bsp"), nil)
	write(t, filepath.Join(install.sdk, "hl2.exe"), nil)
	write(t, filepath.Join(install.sdk, "bin", "engine.dll"), nil)
	write(t, filepath.Join(install.content, "hl2.exe"), nil)
	payload := filepath.Join(install.content, "hl2", "custom", "abaddon_content")
	for _, file := range []string{
		"maps/d6_city17_drain.bsp", "maps/d6_reactor_escape.bsp",
		"models/drmd/combine_elite.mdl", "models/drmd/combine_elite.vvd", "models/drmd/combine_elite.dx90.vtx",
		"models/drmd/combine_arc_elite.mdl", "models/drmd/combine_arc_elite.vvd", "models/drmd/combine_arc_elite.dx90.vtx",
		"materials/models/drmd/arc_shell.vmt", "materials/drmd/drmd_finish_arc_shell.vtf",
	} {
		write(t, filepath.Join(payload, filepath.FromSlash(file)), nil)
	}
	write(t, filepath.Join(install.mod, "gameinfo.txt"),
		[]byte(`"GameInfo" { "game" "Half-Life: Abaddon" "FileSystem" { "SteamAppId" "243730" } }`))
	write(t, filepath.Join(install.mod, "maps", "d6_native_flightlab.bsp"), nil)
	makeDLL(t, filepath.Join(install.mod, "bin", "client.dll"), pe.IMAGE_FILE_MACHINE_I386, "m_bAbaddonFlight")
	makeDLL(t, filepath.Join(install.mod, "bin", "server.dll"), pe.IMAGE_FILE_MACHINE_I386, "abaddon_flight")
	return install
}

func TestSteamLibraryDetectionAndSeparateArguments(t *testing.T) {
	game := fixture(t)
	cfg := DefaultConfig()
	cfg.SteamPath = game.steam
	cfg.GMod.Display = "borderless"
	cfg.GMod.GameProfile = "campaign"
	cfg.HL2.Display, cfg.HL2.Width, cfg.HL2.Height = "fullscreen", 1280, 720
	cfg.HL2.Console, cfg.HL2.DebugLog = false, true
	cfg.HL2Content.Width, cfg.HL2Content.Height = 1024, 768
	cfg.HL2Content.SkipIntro = false
	found := Detect(cfg)
	if !found.GMod.Ready || !found.HL2.Ready || found.GModPath != game.gmod || found.SDKPath != game.sdk ||
		found.NativePath != game.mod || !found.HL2Content.Ready || found.ContentPath != game.content {
		t.Fatalf("unexpected discovery: %+v", found)
	}
	want := map[Profile][]string{
		GMod: {"-applaunch", "4000", "-windowed", "-noborder", "-w", "1600", "-h", "900", "-console", "-novid",
			"+gamemode", "sandbox", "+lservercfgfile", "abaddon_launcher_campaign.cfg", "+map", "d6_city17_drain"},
		HL2: {"-applaunch", "243730", "-game", game.mod, "-fullscreen", "-w", "1280", "-h", "720", "-novid",
			"-condebug", "+map", "d6_native_flightlab"},
		HL2Content: {"-applaunch", "220", "-windowed", "-w", "1024", "-h", "768", "-console", "+map", "d6_city17_drain"},
	}
	for profile, args := range want {
		plan, err := BuildLaunch(cfg, profile)
		if err != nil || plan.Executable != filepath.Join(game.steam, "steam.exe") || !reflect.DeepEqual(plan.Args, args) {
			t.Fatalf("%s: %+v, %v", profile, plan, err)
		}
	}
}

func TestRetailContentDetectsPartialInstallAndLegacyLayout(t *testing.T) {
	game := fixture(t)
	cfg := DefaultConfig()
	cfg.SteamPath = game.steam
	cfg.ContentPath = filepath.Join(game.content, "hl2")
	payload := contentInstallPath(game.content)
	legacy := filepath.Join(game.content, "hl2", "custom", "drmd")
	if err := os.Rename(payload, legacy); err != nil {
		t.Fatal(err)
	}
	if got := Detect(cfg); !got.HL2Content.Ready || got.ContentPath != game.content || !strings.Contains(got.HL2Content.Message, "content-only") {
		t.Fatalf("legacy content: %+v", got)
	}
	if err := os.Remove(filepath.Join(legacy, "models", "drmd", "combine_elite.vvd")); err != nil {
		t.Fatal(err)
	}
	if got := Detect(cfg); got.HL2Content.Ready || !got.HL2.Ready || !strings.Contains(got.HL2Content.Message, "ресурсы") {
		t.Fatalf("partial retail content confused with the native lab: %+v", got)
	}
	if plan, err := BuildLaunch(cfg, HL2Content); err == nil || len(plan.Args) != 0 {
		t.Fatalf("incomplete retail payload launched: %+v, %v", plan, err)
	}
}

func TestListenServerConfigUsesIsolatedProfile(t *testing.T) {
	game := fixture(t)
	cfg := DefaultConfig()
	cfg.SteamPath = game.steam
	cfg.GMod.GameProfile = "campaign"
	plan, err := BuildLaunch(cfg, GMod)
	if err != nil {
		t.Fatal(err)
	}
	dir := filepath.Join(game.gmod, "garrysmod", "cfg")
	name := filepath.Join(dir, "abaddon_launcher_campaign.cfg")
	defaultConfig := filepath.Join(dir, "listenserver.cfg")
	write(t, defaultConfig, []byte("hostname Test\n"))
	if isFile(name) {
		t.Fatal("building a launch plan must not write to the game")
	}
	for attempt := 0; attempt < 2; attempt++ {
		if err = plan.prepareListenConfig(); err != nil {
			t.Fatal(err)
		}
	}
	contents, err := os.ReadFile(name)
	if err != nil || !strings.HasSuffix(string(contents), "exec listenserver.cfg\nd6_profile campaign\n") {
		t.Fatalf("listen config = %q, %v", contents, err)
	}
	if contents, err := os.ReadFile(defaultConfig); err != nil || string(contents) != "hostname Test\n" {
		t.Fatalf("original config changed: %q, %v", contents, err)
	}
	write(t, name, []byte("user command\n"))
	if err := plan.prepareListenConfig(); err == nil {
		t.Fatal("launch granted over a user config collision")
	}
	if contents, err := os.ReadFile(name); err != nil || string(contents) != "user command\n" {
		t.Fatalf("user config changed: %q, %v", contents, err)
	}
}

func TestLegacyLibrariesAndSafeVDF(t *testing.T) {
	game := fixture(t)
	if err := os.Remove(filepath.Join(game.steam, "steamapps", "libraryfolders.vdf")); err != nil {
		t.Fatal(err)
	}
	write(t, filepath.Join(game.steam, "config", "libraryfolders.vdf"),
		[]byte("\ufeff// old layout\n"+fmt.Sprintf(`"LibraryFolders" { "TimeNextStatsReport" "123" "1" %s }`, quoted(game.library))))
	cfg := DefaultConfig()
	cfg.SteamPath = filepath.Join(game.steam, "steam.exe")
	got := Detect(cfg)
	if got.GModPath != game.gmod || !got.HL2.Ready {
		t.Fatalf("legacy discovery: %+v", got)
	}
	config := parseVDF(`"head" { "a" "C:\\Program Files\\Steam" "b" "E:\Steam" "c" "Steam \"QA\"" }`).child("head")
	if config.child("a").value != `C:\Program Files\Steam` || config.child("b").value != `E:\Steam` ||
		config.child("c").value != `Steam "QA"` {
		t.Fatalf("bad escapes: %+v", config)
	}
	write(t, filepath.Join(game.library, "steamapps", "appmanifest_4000.acf"),
		[]byte(`"AppState" { "appid" "4000" "installdir" "../../escaped" }`))
	if Detect(cfg).GModPath != "" {
		t.Fatal("manifest directory traversal was accepted")
	}
}

func TestManualPaths(t *testing.T) {
	game := fixture(t)
	t.Setenv("ABADDON_TEST_STEAM", game.steam)
	cfg := DefaultConfig()
	cfg.SteamPath = `"%ABADDON_TEST_STEAM%"`
	cfg.GModPath = filepath.Join(game.gmod, "bin", "win64", "gmod.exe")
	cfg.SDKPath = filepath.Join(game.sdk, "hl2.exe")
	cfg.NativePath = game.mod + string(filepath.Separator)
	found := Detect(cfg)
	if !found.GMod.Ready || !found.HL2.Ready || found.GModPath != game.gmod {
		t.Fatalf("manual paths: %+v", found)
	}
	cfg.GModPath = filepath.Join(game.steam, "missing")
	if got := Detect(cfg); got.GMod.Ready || got.GModPath != "" {
		t.Fatalf("manual invalid path was ignored: %+v", got)
	}
	cfg.GModPath = filepath.Join(game.steam, "unregistered")
	write(t, filepath.Join(cfg.GModPath, "gmod.exe"), nil)
	write(t, filepath.Join(cfg.GModPath, "garrysmod", "lua", "autorun", "d6_autoload.lua"), nil)
	if got := Detect(cfg); got.GMod.Ready || !strings.Contains(got.GMod.Message, "отличается") {
		t.Fatalf("conflicting manual path: %+v", got)
	}
	cfg.SteamPath = filepath.Join(game.steam, "missing")
	if got := Detect(cfg); got.SteamPath != "" || got.HL2.Ready || got.GMod.Ready {
		t.Fatalf("invalid Steam path: %+v", got)
	}
}

func TestMissingPayloadAndNativeModuleIdentity(t *testing.T) {
	game := fixture(t)
	cfg := DefaultConfig()
	cfg.SteamPath = game.steam
	mapPath := filepath.Join(game.addon, "maps", "d6_city17_drain.bsp")
	if err := os.Remove(mapPath); err != nil {
		t.Fatal(err)
	}
	if _, err := BuildLaunch(cfg, GMod); err == nil || !strings.Contains(err.Error(), "d6_city17_drain.bsp") {
		t.Fatalf("missing BSP: %v", err)
	}
	cfg.GMod.Map = "gm_flatgrass"
	if _, err := BuildLaunch(cfg, GMod); err != nil {
		t.Fatalf("stock map should use the engine resource lookup: %v", err)
	}
	loader := filepath.Join(game.addon, "lua", "autorun", "d6_autoload.lua")
	if err := os.Remove(loader); err != nil {
		t.Fatal(err)
	}
	if _, err := BuildLaunch(cfg, GMod); err == nil || !strings.Contains(err.Error(), "garrysmod/addons") {
		t.Fatalf("missing addon: %v", err)
	}
	native := filepath.Join(game.mod, "bin", "server.dll")
	write(t, native, []byte("\x7fELF"))
	write(t, filepath.Join(game.mod, "bin", "server.so"), []byte("\x7fELF"))
	if _, err := BuildLaunch(cfg, HL2); err == nil || !strings.Contains(err.Error(), "32-битные Windows") {
		t.Fatalf("Linux file in Windows bin: %v", err)
	}
	makeDLL(t, native, pe.IMAGE_FILE_MACHINE_AMD64, "abaddon_flight")
	if _, err := BuildLaunch(cfg, HL2); err == nil {
		t.Fatal("wrong DLL machine was accepted")
	}
	makeDLL(t, native, pe.IMAGE_FILE_MACHINE_I386, "sdk_stock_command")
	if _, err := BuildLaunch(cfg, HL2); err == nil {
		t.Fatal("stock Windows Source SDK DLL was accepted as the flight overlay")
	}
	makeDLL(t, native, pe.IMAGE_FILE_MACHINE_I386, "abaddon_flight")
	if err := os.Remove(filepath.Join(game.mod, "maps", "d6_native_flightlab.bsp")); err != nil {
		t.Fatal(err)
	}
	cfg.HL2.Map = ""
	if _, err := BuildLaunch(cfg, HL2); err == nil || !strings.Contains(err.Error(), "d6_native_flightlab.bsp") {
		t.Fatalf("incomplete lab even when launching from the menu: %v", err)
	}
}

func TestValidatesSettingsBeforeLaunch(t *testing.T) {
	game := fixture(t)
	cfg := DefaultConfig()
	cfg.SteamPath = game.steam
	cfg.HL2.Map = "d6_native_flightlab +exec unexpected"
	if got, err := BuildLaunch(cfg, HL2); err == nil || len(got.Args) != 0 {
		t.Fatal("untrusted map string reached Source arguments")
	}
	cfg.HL2.Map = ""
	cfg.HL2.Width, cfg.HL2.Height = 0, 0
	got, err := BuildLaunch(cfg, HL2)
	if err != nil || strings.Contains(strings.Join(got.Args, " "), "-w ") || strings.Contains(strings.Join(got.Args, " "), "+map") {
		t.Fatalf("startup menu without forced resolution: %+v, %v", got, err)
	}
	cfg.HL2.Height = 180
	if _, err := BuildLaunch(cfg, HL2); err == nil {
		t.Fatal("incomplete resolution was accepted")
	}
	cfg.GMod.GameProfile = "unsupported"
	if _, err := BuildLaunch(cfg, GMod); err == nil {
		t.Fatal("unknown Garry’s Mod game mode was accepted")
	}
}

func TestConfigurationWritesSeparateProfiles(t *testing.T) {
	t.Setenv("LOCALAPPDATA", t.TempDir())
	cfg, err := LoadConfig()
	if err != nil || cfg != DefaultConfig() {
		t.Fatalf("config defaults: %+v, %v", cfg, err)
	}
	cfg.Selected = HL2Content
	cfg.HL2.Height = 1200
	cfg.HL2Content.Height = 800
	cfg.GMod.GameProfile = "arena"
	if err := SaveConfig(cfg); err != nil {
		t.Fatal(err)
	}
	cfg.HL2.Width = 1920
	if err := SaveConfig(cfg); err != nil {
		t.Fatal(err)
	}
	if got, err := LoadConfig(); err != nil || got != cfg {
		t.Fatalf("load after atomic replacement: %+v, %v", got, err)
	}
	path, _ := configPath()
	write(t, path, []byte(`{"gmod":{"height":720}}`))
	if got, err := LoadConfig(); err != nil || got.GMod.Height != 720 || got.HL2 != DefaultConfig().HL2 || got.HL2Content != DefaultConfig().HL2Content {
		t.Fatalf("partial config: %+v, %v", got, err)
	}
	write(t, path, []byte("{"))
	if got, err := LoadConfig(); err == nil || got != DefaultConfig() {
		t.Fatalf("malformed config: %+v, %v", got, err)
	}
}
