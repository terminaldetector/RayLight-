package main

import (
	"bytes"
	"debug/pe"
	"encoding/binary"
	"encoding/json"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

func nativeTestDLL(t *testing.T, path string, machine uint16, marker string) {
	t.Helper()
	var file bytes.Buffer
	dos := make([]byte, 0x80)
	copy(dos, "MZ")
	binary.LittleEndian.PutUint32(dos[0x3c:], uint32(len(dos)))
	file.Write(dos)
	file.WriteString("PE\x00\x00")
	optional := pe.OptionalHeader32{Magic: 0x10b, NumberOfRvaAndSizes: 16}
	head := pe.FileHeader{
		Machine: machine, NumberOfSections: 1, SizeOfOptionalHeader: uint16(binary.Size(optional)),
		Characteristics: pe.IMAGE_FILE_DLL,
	}
	section := pe.SectionHeader32{
		SizeOfRawData:    uint32(len(marker) + 1),
		PointerToRawData: uint32(file.Len() + binary.Size(head) + binary.Size(optional) + binary.Size(pe.SectionHeader32{})),
	}
	copy(section.Name[:], ".rdata")
	for _, value := range []any{head, optional, section} {
		if err := binary.Write(&file, binary.LittleEndian, value); err != nil {
			t.Fatal(err)
		}
	}
	file.WriteString(marker + "\x00")
	put(t, path, file.String())
}

func TestNativeFlightLabLaunchUsesOnlyRealWin32ModAndMap(t *testing.T) {
	steam := t.TempDir()
	sdk := gameAt(t, filepath.Join(steam, "steamapps", "common", "Source SDK Base 2013 Singleplayer"), TargetHL2Native)
	mod := filepath.Join(steam, "steamapps", "sourcemods", "abaddon_native")
	put(t, filepath.Join(steam, "steam.exe"), "Steam fixture")
	put(t, filepath.Join(steam, "steamapps", "appmanifest_243730.acf"), `"AppState" { "appid" "243730" "installdir" "Source SDK Base 2013 Singleplayer" }`)
	put(t, filepath.Join(mod, "gameinfo.txt"), `"GameInfo" { "FileSystem" { "SteamAppId" "243730" } }`)
	client := filepath.Join(mod, "bin", "client.dll")
	server := filepath.Join(mod, "bin", "server.dll")
	mapFile := filepath.Join(mod, "maps", nativeLabMap+".bsp")
	nativeTestDLL(t, client, pe.IMAGE_FILE_MACHINE_I386, "m_bAbaddonFlight")
	nativeTestDLL(t, server, pe.IMAGE_FILE_MACHINE_I386, "abaddon_flight")

	found := DiscoverInstallations([]string{steam})
	if len(found) != 1 || found[0].Root != sdk.Root || found[0].NativeRoot != mod || found[0].Target != TargetHL2Native {
		t.Fatalf("wrong SDK or mod discovery: %+v", found)
	}
	inst := found[0]
	opts := LaunchOptions{Map: nativeLabMap, Windowed: true, Graphics: "high"}
	if _, _, err := ConfigureLaunch(inst, LaunchOptions{}); err == nil {
		t.Fatal("native menu accepted a missing lab map")
	}
	put(t, mapFile, "VBSP")
	if _, _, err := ConfigureLaunch(inst, opts); err == nil {
		t.Fatal("native launch accepted truncated BSP")
	}
	bsp := make([]byte, 1036)
	copy(bsp, "VBSP")
	binary.LittleEndian.PutUint32(bsp[4:], 20)
	put(t, mapFile, string(bsp))

	nativeTestDLL(t, server, pe.IMAGE_FILE_MACHINE_AMD64, "abaddon_flight")
	if _, _, err := ConfigureLaunch(inst, opts); err == nil || !strings.Contains(err.Error(), "server.dll") {
		t.Fatalf("non-x86 DLL accepted: %v", err)
	}
	nativeTestDLL(t, server, pe.IMAGE_FILE_MACHINE_I386, "x-abaddon_flight_missing")
	if _, _, err := ConfigureLaunch(inst, opts); err == nil || !strings.Contains(err.Error(), "server.dll") {
		t.Fatalf("unrecognized DLL accepted: %v", err)
	}
	nativeTestDLL(t, server, pe.IMAGE_FILE_MACHINE_I386, "abaddon_flight")

	if _, _, err := ConfigureLaunch(sdk, opts); err == nil {
		t.Fatal("SDK launched without a confirmed Steam registration")
	}
	if _, err := InstallBundle(t.TempDir(), inst); err == nil {
		t.Fatal("packaged runtime installer accepted the native target")
	}
	if _, err := RollbackInstallation(inst); err == nil {
		t.Fatal("packaged rollback accepted the native target")
	}
	if _, _, err := ConfigureLaunch(inst, LaunchOptions{Map: "d6_reactor_escape"}); err == nil {
		t.Fatal("native launch accepted a non-lab start map")
	}

	exe, args, err := ConfigureLaunch(inst, opts)
	wantArgs := []string{"-applaunch", "243730", "-game", mod, "-novid", "-windowed", "+exec", configName, "+map", nativeLabMap}
	if err != nil || exe != filepath.Join(steam, "steam.exe") || !reflect.DeepEqual(args, wantArgs) {
		t.Fatalf("wrong native launch: %q %q (%v)", exe, args, err)
	}
	if cfg := get(t, filepath.Join(mod, "cfg", configName)); !strings.Contains(cfg, "r_flashlightdepthres 2048") {
		t.Fatalf("native graphics config missing: %s", cfg)
	}
}

func TestPreferencesMigrateLegacyAndKeepIndependentTargets(t *testing.T) {
	old := []byte(`{"target":"hl2-content","gmod_path":"C:/GMod","hl2_path":"D:/HL2","map_index":2,"graphics_index":2,"resolution_index":1,"windowed":false,"console":true}`)
	saved := decodePreferences(old)
	if saved.Target != TargetHL2 || saved.Profiles[TargetHL2] != (targetPreferences{MapIndex: 2, GraphicsIndex: 2, ResolutionIndex: 1, Console: true}) {
		t.Fatalf("legacy profile not migrated: %+v", saved)
	}
	if saved.GModPath != "C:/GMod" || saved.HL2Path != "D:/HL2" || saved.Profiles[TargetGMod].MapIndex != 3 || saved.Profiles[TargetHL2Native].MapIndex != 1 {
		t.Fatalf("paths/defaults lost during migration: %+v", saved)
	}
	saved.Profiles[TargetHL2Native] = targetPreferences{MapIndex: 0, ResolutionIndex: 3, Windowed: true}
	encoded, err := json.Marshal(saved)
	if err != nil {
		t.Fatal(err)
	}
	reloaded := decodePreferences(encoded)
	if !reflect.DeepEqual(saved, reloaded) {
		t.Fatalf("independent settings did not persist: %+v, %+v", saved, reloaded)
	}
}
