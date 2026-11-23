package main

import (
	"bytes"
	"debug/pe"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

const nativeLabMap = "d6_native_flightlab"

type mapChoice struct {
	name  string
	label string
}

func targetMaps(target Target) []mapChoice {
	if target == TargetHL2Native {
		return []mapChoice{{"", "Меню Flight Lab"}, {nativeLabMap, "Полигон — Native Flight Lab"}}
	}
	maps := []mapChoice{
		{"", "Меню игры"},
		{"d6_city17_drain", "Эпизод — City 17"},
		{"d6_reactor_escape", "Реактор — Escape"},
		{"d6_relay_vault", "Арена — Relay Vault"},
	}
	if target == TargetGMod {
		maps = append(maps, mapChoice{"d6_rogue_reactor", "Roguelike — Reactor"})
	}
	return maps
}

func targetAllowsMap(target Target, name string) bool {
	for _, choice := range targetMaps(target) {
		if choice.name == name {
			return true
		}
	}
	return false
}

func discoverNativeRoot(inst Installation) string {
	localSteamApps := filepath.Dir(filepath.Dir(inst.Root))
	roots := []string{localSteamApps}
	if inst.SteamRoot != "" {
		roots = append([]string{filepath.Join(inst.SteamRoot, "steamapps")}, roots...)
	}
	for _, steamApps := range roots {
		candidate := filepath.Join(steamApps, "sourcemods", "abaddon_native")
		if regularFile(filepath.Join(candidate, "gameinfo.txt")) == nil {
			return candidate
		}
	}
	return ""
}

func nativeSourceModule(path, marker string) bool {
	if regularFile(path) != nil {
		return false
	}
	dll, err := pe.Open(path)
	if err != nil {
		return false
	}
	defer dll.Close()
	_, pe32 := dll.OptionalHeader.(*pe.OptionalHeader32)
	if !pe32 || dll.Machine != pe.IMAGE_FILE_MACHINE_I386 || dll.Characteristics&pe.IMAGE_FILE_DLL == 0 {
		return false
	}
	for _, name := range []string{".rdata", ".data", ".text"} {
		if section := dll.Section(name); section != nil && containsModuleMarker(section.Open(), []byte(marker+"\x00")) {
			return true
		}
	}
	return false
}

func containsModuleMarker(reader io.Reader, literal []byte) bool {
	buffer := make([]byte, 32<<10)
	offset := 0
	for {
		n, err := reader.Read(buffer[offset:])
		end := offset + n
		if bytes.Contains(buffer[:end], literal) {
			return true
		}
		if err != nil || n == 0 {
			return false
		}
		offset = min(end, len(literal)-1)
		copy(buffer, buffer[end-offset:end])
	}
}

func validateNativeLaunch(inst Installation) (string, error) {
	sdkRegistered := false
	if inst.SteamRoot != "" && regularFile(filepath.Join(inst.SteamRoot, "steam.exe")) == nil {
		for _, detected := range DiscoverInstallations([]string{inst.SteamRoot}) {
			if detected.Target == TargetHL2Native && strings.EqualFold(detected.Root, inst.Root) {
				sdkRegistered = true
				break
			}
		}
	}
	if !sdkRegistered {
		return "", errors.New("Steam не подтвердил выбранную установку Source SDK Base 2013 Singleplayer (243730).")
	}
	mod := strings.TrimSpace(inst.NativeRoot)
	if mod == "" {
		mod = discoverNativeRoot(inst)
	}
	if mod == "" {
		return "", errors.New("Укажите папку экспериментального мода abaddon_native.")
	}
	mod, err := filepath.Abs(mod)
	if err != nil {
		return "", err
	}
	pairs, err := readVDF(filepath.Join(mod, "gameinfo.txt"))
	if err != nil {
		return "", fmt.Errorf("Не найден gameinfo.txt Flight Lab: %w", err)
	}
	info, _ := vdfFind(pairs, "GameInfo")
	filesystem, _ := vdfFind(info.children, "FileSystem")
	appID, _ := vdfFind(filesystem.children, "SteamAppId")
	if appID.value != "243730" {
		return "", errors.New("gameinfo.txt Flight Lab должен указывать SteamAppId 243730.")
	}
	for _, dll := range []struct{ name, marker string }{
		{"client.dll", "m_bAbaddonFlight"},
		{"server.dll", "abaddon_flight"},
	} {
		if !nativeSourceModule(filepath.Join(mod, "bin", dll.name), dll.marker) {
			return "", fmt.Errorf("Нужна библиотека Win32 Flight Lab: bin/%s.", dll.name)
		}
	}
	mapPath := filepath.Join(mod, "maps", nativeLabMap+".bsp")
	if regularFile(mapPath) != nil {
		return "", fmt.Errorf("В Flight Lab отсутствует maps/%s.bsp.", nativeLabMap)
	}
	f, err := os.Open(mapPath)
	if err != nil {
		return "", err
	}
	defer f.Close()
	var header [4 + 4 + 64*16 + 4]byte
	if _, err := io.ReadFull(f, header[:]); err != nil || string(header[:4]) != "VBSP" || binary.LittleEndian.Uint32(header[4:8]) != 20 {
		return "", fmt.Errorf("Карта %s не распознана как Source BSP версии 20.", nativeLabMap)
	}
	return mod, nil
}
