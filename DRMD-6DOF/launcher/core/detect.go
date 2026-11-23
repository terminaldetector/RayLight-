package core

import (
	"bytes"
	"debug/pe"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

type Status struct {
	Ready   bool
	Message string
}

type Detection struct {
	SteamPath   string
	GModPath    string
	SDKPath     string
	NativePath  string
	ContentPath string
	GMod        Status
	HL2         Status
	HL2Content  Status
}

var windowsVariable = regexp.MustCompile(`%([^%]+)%`)

func cleanPath(value string) string {
	value = strings.TrimSpace(value)
	if len(value) >= 2 && value[0] == '"' && value[len(value)-1] == '"' {
		value = value[1 : len(value)-1]
	}
	value = windowsVariable.ReplaceAllStringFunc(value, func(token string) string {
		if expanded, set := os.LookupEnv(token[1 : len(token)-1]); set {
			return expanded
		}
		return token
	})
	if value == "" {
		return ""
	}
	path, err := filepath.Abs(filepath.FromSlash(value))
	if err != nil {
		return ""
	}
	return path
}

func isDirectory(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

func isFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

func samePath(first, second string) bool {
	if strings.EqualFold(first, second) {
		return true
	}
	fi, err1 := os.Stat(first)
	si, err2 := os.Stat(second)
	return err1 == nil && err2 == nil && os.SameFile(fi, si)
}

func addPath(paths []string, raw string) []string {
	path := cleanPath(raw)
	if path == "" || !isDirectory(path) {
		return paths
	}
	for _, previous := range paths {
		if samePath(path, previous) {
			return paths
		}
	}
	return append(paths, path)
}

func steamExecutable(raw string) string {
	path := cleanPath(raw)
	if path == "" {
		return ""
	}
	if !strings.EqualFold(filepath.Base(path), "steam.exe") || isDirectory(path) {
		path = filepath.Join(path, "steam.exe")
	}
	if isFile(path) {
		return path
	}
	return ""
}

func findSteam(manual string) string {
	if strings.TrimSpace(manual) != "" {
		return steamExecutable(manual)
	}
	paths := append(steamRegistryPaths(), os.Getenv("STEAM_PATH"))
	for _, name := range []string{"ProgramFiles(x86)", "ProgramFiles", "ProgramW6432"} {
		if root := os.Getenv(name); root != "" {
			paths = append(paths, filepath.Join(root, "Steam"))
		}
	}
	for _, path := range paths {
		if steam := steamExecutable(path); steam != "" {
			return steam
		}
	}
	return ""
}

func steamLibraries(steam string) []string {
	if steam == "" {
		return nil
	}
	root := filepath.Dir(steam)
	libraries := []string{root}
	for _, path := range []string{
		filepath.Join(root, "steamapps", "libraryfolders.vdf"),
		filepath.Join(root, "config", "libraryfolders.vdf"),
	} {
		config := readVDF(path).child("libraryfolders")
		for _, entry := range config.children {
			if _, err := strconv.ParseUint(entry.name, 10, 32); err != nil {
				continue
			}
			folder := entry.value
			if entry.children != nil {
				folder = entry.child("path").value
			}
			libraries = addPath(libraries, folder)
		}
	}
	return libraries
}

func readManifest(library, appID string) string {
	path := filepath.Join(library, "steamapps", "appmanifest_"+appID+".acf")
	app := readVDF(path).child("AppState")
	if id := app.child("appid").value; id != "" && id != appID {
		return ""
	}
	name := app.child("installdir").value
	if name == "" || name == "." || name == ".." || strings.ContainsAny(name, "/\\:\x00") {
		return ""
	}
	return filepath.Join(library, "steamapps", "common", name)
}

func gameRoot(raw string, good func(string) bool) string {
	path := cleanPath(raw)
	if path == "" {
		return ""
	}
	if strings.EqualFold(filepath.Ext(path), ".exe") {
		path = filepath.Dir(path)
	}
	for check := 0; check < 3; check++ {
		if good(path) {
			return path
		}
		// Accept the game directory, its content subfolder, or a bin/<arch> executable.
		base := strings.ToLower(filepath.Base(path))
		switch base {
		case "garrysmod", "hl2", "bin", "win64", "win32":
			path = filepath.Dir(path)
		default:
			return ""
		}
	}
	return ""
}

func gmodRuntime(path string) bool {
	if !isDirectory(filepath.Join(path, "garrysmod")) {
		return false
	}
	for _, exe := range []string{"gmod.exe", "hl2.exe", "bin/win64/gmod.exe", "bin/win64/hl2.exe"} {
		if isFile(filepath.Join(path, filepath.FromSlash(exe))) {
			return true
		}
	}
	return false
}

func sdkRuntime(path string) bool {
	return isFile(filepath.Join(path, "hl2.exe")) &&
		(isDirectory(filepath.Join(path, "hl2")) || isFile(filepath.Join(path, "bin", "engine.dll")))
}

func retailHL2Runtime(path string) bool {
	return isFile(filepath.Join(path, "hl2.exe")) && isDirectory(filepath.Join(path, "hl2"))
}

func contentInstallPath(game string) string {
	return filepath.Join(game, "hl2", "custom", "abaddon_content")
}

func contentPayload(game string) string {
	canonical := contentInstallPath(game)
	if isDirectory(canonical) {
		return canonical
	}
	legacy := filepath.Join(game, "hl2", "custom", "drmd")
	if isDirectory(legacy) {
		return legacy
	}
	return ""
}

func hasStoryResources(payload string) bool {
	for _, file := range []string{
		"maps/d6_city17_drain.bsp", "maps/d6_reactor_escape.bsp",
		"models/drmd/combine_elite.mdl", "models/drmd/combine_elite.vvd", "models/drmd/combine_elite.dx90.vtx",
		"models/drmd/combine_arc_elite.mdl", "models/drmd/combine_arc_elite.vvd", "models/drmd/combine_arc_elite.dx90.vtx",
		"materials/models/drmd/arc_shell.vmt", "materials/drmd/drmd_finish_arc_shell.vtf",
	} {
		if !isFile(filepath.Join(payload, filepath.FromSlash(file))) {
			return false
		}
	}
	return true
}

type appInstall struct {
	path     string
	conflict bool
}

func locateGame(libraries []string, manual, appID, defaultName string, good func(string) bool) appInstall {
	if strings.TrimSpace(manual) != "" {
		path := gameRoot(manual, good)
		if path == "" {
			return appInstall{}
		}
		foundManifest, matched := false, false
		for _, library := range libraries {
			if registered := readManifest(library, appID); registered != "" && good(registered) {
				foundManifest = true
				matched = matched || samePath(path, registered)
			}
		}
		return appInstall{path: path, conflict: foundManifest && !matched}
	}
	for _, library := range libraries {
		if path := readManifest(library, appID); path != "" && good(path) {
			return appInstall{path: path}
		}
	}
	for _, library := range libraries {
		if path := filepath.Join(library, "steamapps", "common", defaultName); good(path) {
			return appInstall{path: path}
		}
	}
	return appInstall{}
}

// gmodContent supports the standard add-on install and manual merged content.
func gmodContent(game string) string {
	base := filepath.Join(game, "garrysmod")
	hasMarker := func(root string) bool {
		return isFile(filepath.Join(root, "lua", "autorun", "d6_autoload.lua"))
	}
	if hasMarker(base) {
		return base
	}
	addons := filepath.Join(base, "addons")
	canonical := filepath.Join(addons, "descent_scanner")
	if hasMarker(canonical) {
		return canonical
	}
	entries, _ := os.ReadDir(addons)
	for _, entry := range entries {
		candidate := filepath.Join(addons, entry.Name())
		if hasMarker(candidate) {
			return candidate
		}
	}
	return ""
}

func windowsSourceModule(path, marker string) bool {
	f, err := pe.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()
	_, isPE32 := f.OptionalHeader.(*pe.OptionalHeader32)
	if !isPE32 || f.Machine != pe.IMAGE_FILE_MACHINE_I386 || f.Characteristics&pe.IMAGE_FILE_DLL == 0 {
		return false
	}
	// These registered text literals distinguish the flight overlay from the stock SDK DLLs.
	for _, name := range []string{".rdata", ".data", ".text"} {
		if section := f.Section(name); section != nil && containsLiteral(section.Open(), []byte(marker+"\x00")) {
			return true
		}
	}
	return false
}

func containsLiteral(section io.Reader, literal []byte) bool {
	buffer := make([]byte, 32<<10)
	overlap := 0
	for {
		n, err := section.Read(buffer[overlap:])
		end := overlap + n
		if bytes.Contains(buffer[:end], literal) {
			return true
		}
		if err != nil || n == 0 {
			return false
		}
		overlap = min(end, len(literal)-1)
		copy(buffer, buffer[end-overlap:end])
	}
}

func nativeModules(path string) bool {
	bin := filepath.Join(path, "bin")
	return windowsSourceModule(filepath.Join(bin, "client.dll"), "m_bAbaddonFlight") &&
		windowsSourceModule(filepath.Join(bin, "server.dll"), "abaddon_flight")
}

func nativeLabMap(path string) bool {
	return isFile(filepath.Join(path, "maps", "d6_native_flightlab.bsp"))
}

func nativeInfo(path string) keyValue {
	return readVDF(filepath.Join(path, "gameinfo.txt")).child("GameInfo")
}

func nativeAppMatches(info keyValue) bool {
	return info.child("FileSystem").child("SteamAppId").value == "243730"
}

func locateNative(libraries []string, manual string) string {
	if strings.TrimSpace(manual) != "" {
		return cleanPath(manual)
	}

	var partial string
	for _, library := range libraries {
		mods := filepath.Join(library, "steamapps", "sourcemods")
		canonical := filepath.Join(mods, "abaddon_native")
		folders := []string{canonical}
		entries, _ := os.ReadDir(mods)
		for _, entry := range entries {
			if !strings.EqualFold(entry.Name(), "abaddon_native") {
				folders = append(folders, filepath.Join(mods, entry.Name()))
			}
		}
		for _, candidate := range folders {
			if !isDirectory(candidate) {
				continue
			}
			info := nativeInfo(candidate)
			if candidate != canonical && !strings.Contains(strings.ToLower(info.child("game").value), "abaddon") {
				continue
			}
			if nativeAppMatches(info) && nativeLabMap(candidate) && nativeModules(candidate) {
				return candidate
			}
			if partial == "" {
				partial = candidate
			}
		}
	}
	return partial
}

func Detect(cfg Config) Detection {
	d := Detection{SteamPath: findSteam(cfg.SteamPath)}
	libraries := steamLibraries(d.SteamPath)
	gmod := locateGame(libraries, cfg.GModPath, "4000", "GarrysMod", gmodRuntime)
	sdk := locateGame(libraries, cfg.SDKPath, "243730", "Source SDK Base 2013 Singleplayer", sdkRuntime)
	content := locateGame(libraries, cfg.ContentPath, "220", "Half-Life 2", retailHL2Runtime)
	d.GModPath, d.SDKPath = gmod.path, sdk.path
	d.ContentPath = content.path
	d.NativePath = locateNative(libraries, cfg.NativePath)
	d.GMod = gmodStatus(d, cfg, gmod)
	d.HL2 = hl2Status(d, cfg, sdk)
	d.HL2Content = contentStatus(d, cfg, content)
	return d
}

func requiredPath(value, automatic, manual string) Status {
	if strings.TrimSpace(value) == "" {
		return Status{Message: automatic}
	}
	return Status{Message: manual}
}

func steamStatus(cfg Config) Status {
	return requiredPath(cfg.SteamPath, "Steam не найден. Укажите папку Steam вручную.",
		"По заданному пути Steam.exe не найден.")
}

func gmodStatus(d Detection, cfg Config, game appInstall) Status {
	switch {
	case d.SteamPath == "":
		return steamStatus(cfg)
	case d.GModPath == "":
		return requiredPath(cfg.GModPath, "Garry’s Mod не найден в библиотеках Steam.",
			"По заданному пути клиент Garry’s Mod не найден.")
	case game.conflict:
		return Status{Message: "Заданный каталог Garry’s Mod отличается от установки, зарегистрированной в Steam."}
	case gmodContent(d.GModPath) == "":
		return Status{Message: "Garry’s Mod найден. Установите аддон Abaddon в garrysmod/addons."}
	default:
		return Status{Ready: true, Message: "Garry’s Mod и аддон найдены. Доступ проверит Steam."}
	}
}

func hl2Status(d Detection, cfg Config, game appInstall) Status {
	switch {
	case d.SteamPath == "":
		return steamStatus(cfg)
	case d.SDKPath == "":
		return requiredPath(cfg.SDKPath, "Установите Source SDK Base 2013 Singleplayer в Steam.",
			"По заданному пути клиент Source SDK Base 2013 Singleplayer не найден.")
	case game.conflict:
		return Status{Message: "Заданный каталог SDK Base отличается от установки, зарегистрированной в Steam."}
	case d.NativePath == "" || !isFile(filepath.Join(d.NativePath, "gameinfo.txt")):
		return Status{Message: "Укажите папку нативного Abaddon с gameinfo.txt."}
	case !nativeAppMatches(nativeInfo(d.NativePath)):
		return Status{Message: "В gameinfo.txt нативного мода должен быть SteamAppId 243730."}
	case !nativeModules(d.NativePath):
		return Status{Message: fmt.Sprintf("В %s нужны 32-битные Windows client.dll и server.dll с полётом Abaddon.", filepath.Join(d.NativePath, "bin"))}
	case !nativeLabMap(d.NativePath):
		return Status{Message: "Положите d6_native_flightlab.bsp в maps нативного мода."}
	default:
		return Status{Ready: true, Message: "SDK Base и Windows-модули найдены. Полигон полёта / эксперимент."}
	}
}

func contentStatus(d Detection, cfg Config, game appInstall) Status {
	switch {
	case d.SteamPath == "":
		return steamStatus(cfg)
	case d.ContentPath == "":
		return requiredPath(cfg.ContentPath, "Half-Life 2 (App 220) не найден в библиотеках Steam.",
			"По заданному пути клиент Half-Life 2 не найден.")
	case game.conflict:
		return Status{Message: "Заданный каталог Half-Life 2 отличается от установки, зарегистрированной в Steam."}
	default:
		payload := contentPayload(d.ContentPath)
		if payload == "" {
			return Status{Message: "Half-Life 2 найден. Установите набор карт и ресурсов в hl2/custom/abaddon_content."}
		}
		if !hasStoryResources(payload) {
			return Status{Message: "В наборе Half-Life 2 отсутствуют карты или ресурсы. Проверьте установку content-only."}
		}
		return Status{Ready: true, Message: "Карты и основные ресурсы Half-Life 2 найдены. Режим content-only."}
	}
}
