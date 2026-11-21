package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"reflect"
	"sort"
	"strconv"
	"strings"
	"time"
)

type Target string

const (
	TargetGMod Target = "gmod"
	TargetHL2  Target = "hl2-content"
)

type Installation struct {
	Target     Target
	Root       string
	GameDir    string
	Executable string
	SteamRoot  string
}

type LaunchOptions struct {
	Map, Graphics     string
	Width, Height     int
	Windowed, Console bool
}

type BuildManifest struct {
	Schema      int            `json:"schema"`
	Project     string         `json:"project"`
	Revision    string         `json:"revision"`
	Channel     string         `json:"channel"`
	PayloadRoot string         `json:"payload_root"`
	Files       []ManifestFile `json:"files"`
}

type ManifestFile struct {
	Path   string `json:"path"`
	SHA256 string `json:"sha256"`
	Size   int64  `json:"size"`
}

const (
	stateDirectory = "abaddon-launcher-state"
	receiptName    = ".abaddon-install.json"
	launcherOwner  = "abaddon-launcher/v1"
	configName     = "abaddon_launcher.cfg"
	configMarker   = "// Managed by Abaddon Launcher; this dedicated file may be replaced.\n"
)

// pathSafe rejects POSIX traversal and Windows aliases, ADS, device names, and
// backslashes even when a bundle is inspected on Linux before Windows delivery.
func pathSafe(name string) error {
	if name == "" || name == "." || path.IsAbs(name) || path.Clean(name) != name || strings.ContainsAny(name, "\\:") {
		return fmt.Errorf("unsafe relative path %q", name)
	}
	for _, r := range name {
		if r < 32 || r == 127 {
			return fmt.Errorf("control character in path %q", name)
		}
	}
	for _, part := range strings.Split(name, "/") {
		if part == "" || part == "." || part == ".." || strings.TrimRight(part, ". ") != part || strings.ContainsAny(part, "<>\"|?*") {
			return fmt.Errorf("unsafe path component %q", part)
		}
		stem := strings.ToUpper(strings.SplitN(part, ".", 2)[0])
		if stem == "CON" || stem == "PRN" || stem == "AUX" || stem == "NUL" || stem == "CLOCK$" ||
			(len(stem) == 4 && (strings.HasPrefix(stem, "COM") || strings.HasPrefix(stem, "LPT")) && stem[3] >= '1' && stem[3] <= '9') {
			return fmt.Errorf("Windows device name in path %q", name)
		}
	}
	return nil
}

func isLinkOrReparse(info os.FileInfo) bool {
	if info.Mode()&os.ModeSymlink != 0 {
		return true
	}
	// os.FileInfo.Sys on Windows is Win32FileAttributeData. Reflecting the one
	// documented field keeps this core testable on Linux without platform imports.
	v := reflect.ValueOf(info.Sys())
	if v.IsValid() && v.Kind() == reflect.Ptr && !v.IsNil() {
		v = v.Elem()
	}
	if v.IsValid() && v.Kind() == reflect.Struct {
		attr := v.FieldByName("FileAttributes")
		if attr.IsValid() && attr.CanUint() && attr.Uint()&0x400 != 0 {
			return true // FILE_ATTRIBUTE_REPARSE_POINT, including junctions.
		}
	}
	return false
}

func noLinks(name string, allowMissing bool) error {
	abs, err := filepath.Abs(name)
	if err != nil {
		return err
	}
	for current := filepath.Clean(abs); ; current = filepath.Dir(current) {
		info, err := os.Lstat(current)
		if err != nil {
			if !allowMissing || !os.IsNotExist(err) {
				return err
			}
		} else if isLinkOrReparse(info) {
			return fmt.Errorf("symbolic links and Windows reparse points are not supported: %s", current)
		}
		if filepath.Dir(current) == current {
			break
		}
	}
	return nil
}

func regularFile(name string) error {
	if err := noLinks(name, false); err != nil {
		return err
	}
	info, err := os.Lstat(name)
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("not a regular file: %s", name)
	}
	return nil
}

// ValidateInstallation accepts the install root, game directory, or an actual
// executable, including Garry's Mod's bin/win64/gmod.exe.
func ValidateInstallation(selected string, target Target) (Installation, error) {
	if target != TargetGMod && target != TargetHL2 {
		return Installation{}, fmt.Errorf("unknown target %q", target)
	}
	if strings.TrimSpace(selected) == "" {
		return Installation{}, errors.New("select an existing game installation")
	}
	abs, err := filepath.Abs(selected)
	if err != nil {
		return Installation{}, err
	}
	abs = filepath.Clean(abs)
	if err := noLinks(abs, false); err != nil {
		return Installation{}, err
	}
	info, err := os.Stat(abs)
	if err != nil {
		return Installation{}, err
	}
	if !info.IsDir() {
		abs = filepath.Dir(abs)
	}
	game := "garrysmod"
	exes := []string{"bin/win64/gmod.exe", "gmod.exe", "hl2.exe"}
	if target == TargetHL2 {
		game, exes = "hl2", []string{"hl2.exe"}
	}
	for depth, candidate := 0, abs; depth < 5; depth, candidate = depth+1, filepath.Dir(candidate) {
		gameDir := filepath.Join(candidate, game)
		if regularFile(filepath.Join(gameDir, "gameinfo.txt")) == nil {
			for _, exe := range exes {
				executable := filepath.Join(candidate, filepath.FromSlash(exe))
				if regularFile(executable) == nil {
					if exeInfo, e := os.Stat(executable); e == nil && exeInfo.Size() > 0 {
						return Installation{Target: target, Root: candidate, GameDir: gameDir, Executable: executable}, nil
					}
				}
			}
		}
		if filepath.Dir(candidate) == candidate {
			break
		}
	}
	return Installation{}, fmt.Errorf("no %s gameinfo.txt and Windows game executable found at %s", target, selected)
}

type vdfPair struct {
	key, value string
	children   []vdfPair
}

func vdfTokens(input string) ([]string, error) {
	var tokens []string
	for i := 0; i < len(input); {
		if strings.ContainsRune(" \t\r\n\ufeff", rune(input[i])) {
			i++
			continue
		}
		if i+1 < len(input) && input[i:i+2] == "//" {
			for i < len(input) && input[i] != '\n' {
				i++
			}
			continue
		}
		if input[i] == '{' || input[i] == '}' {
			tokens = append(tokens, input[i:i+1])
			i++
			continue
		}
		if input[i] == '"' {
			i++
			var b strings.Builder
			closed := false
			for i < len(input) {
				if input[i] == '"' {
					i++
					closed = true
					break
				}
				if input[i] == '\\' && i+1 < len(input) && (input[i+1] == '\\' || input[i+1] == '"') {
					i++
				}
				b.WriteByte(input[i])
				i++
			}
			if !closed {
				return nil, errors.New("unterminated VDF string")
			}
			tokens = append(tokens, b.String())
			continue
		}
		start := i
		for i < len(input) && !strings.ContainsRune(" \t\r\n{}", rune(input[i])) {
			i++
		}
		tokens = append(tokens, input[start:i])
	}
	return tokens, nil
}

func parseVDF(input string) ([]vdfPair, error) {
	tokens, err := vdfTokens(strings.TrimPrefix(input, "\ufeff"))
	if err != nil {
		return nil, err
	}
	pos := 0
	var parse func(bool, int) ([]vdfPair, error)
	parse = func(nested bool, depth int) ([]vdfPair, error) {
		if depth > 32 {
			return nil, errors.New("VDF nesting exceeds 32 levels")
		}
		var pairs []vdfPair
		for pos < len(tokens) {
			if tokens[pos] == "}" {
				if !nested {
					return nil, errors.New("unexpected VDF closing brace")
				}
				pos++
				return pairs, nil
			}
			key := tokens[pos]
			pos++
			if key == "{" || pos >= len(tokens) {
				return nil, errors.New("invalid VDF key/value")
			}
			pair := vdfPair{key: key}
			if tokens[pos] == "{" {
				pos++
				pair.children, err = parse(true, depth+1)
				if err != nil {
					return nil, err
				}
			} else if tokens[pos] == "}" {
				return nil, errors.New("VDF value is missing")
			} else {
				pair.value = tokens[pos]
				pos++
			}
			pairs = append(pairs, pair)
		}
		if nested {
			return nil, errors.New("unclosed VDF block")
		}
		return pairs, nil
	}
	return parse(false, 0)
}

func vdfFind(pairs []vdfPair, key string) (vdfPair, bool) {
	for _, p := range pairs {
		if strings.EqualFold(p.key, key) {
			return p, true
		}
	}
	return vdfPair{}, false
}

func readVDF(name string) ([]vdfPair, error) {
	if err := regularFile(name); err != nil {
		return nil, err
	}
	b, err := os.ReadFile(name)
	if err != nil {
		return nil, err
	}
	if len(b) > 8<<20 {
		return nil, errors.New("VDF exceeds size limit")
	}
	return parseVDF(string(b))
}

// DiscoverInstallations uses caller-provided Steam roots (registry/environment/
// manual candidates), not one assumed Program Files location. Broken entries
// are ignored; ValidateInstallation remains the manual path with diagnostics.
func DiscoverInstallations(steamRoots []string) []Installation {
	type library struct{ root, steam string }
	var libraries []library
	seenLibraries, seenGames := map[string]bool{}, map[string]bool{}
	addLibrary := func(root, steam string) {
		abs, err := filepath.Abs(root)
		if err != nil || root == "" || noLinks(abs, false) != nil {
			return
		}
		key := strings.ToLower(filepath.Clean(abs))
		if !seenLibraries[key] {
			seenLibraries[key] = true
			libraries = append(libraries, library{filepath.Clean(abs), steam})
		}
	}
	for _, root := range steamRoots {
		abs, err := filepath.Abs(root)
		if err != nil || strings.TrimSpace(root) == "" {
			continue
		}
		steam := ""
		if regularFile(filepath.Join(abs, "steam.exe")) == nil {
			steam = abs
		}
		addLibrary(abs, steam)
		for _, name := range []string{"steamapps/libraryfolders.vdf", "config/libraryfolders.vdf"} {
			pairs, err := readVDF(filepath.Join(abs, filepath.FromSlash(name)))
			if err != nil {
				continue
			}
			folder, ok := vdfFind(pairs, "libraryfolders")
			if !ok {
				continue
			}
			for _, p := range folder.children {
				if _, err := strconv.Atoi(p.key); err != nil {
					continue
				}
				libraryPath := p.value
				if item, ok := vdfFind(p.children, "path"); ok {
					libraryPath = item.value
				}
				if filepath.IsAbs(libraryPath) {
					addLibrary(libraryPath, steam)
				}
			}
		}
	}
	var found []Installation
	for _, lib := range libraries {
		for _, spec := range []struct {
			app    string
			target Target
		}{{"4000", TargetGMod}, {"220", TargetHL2}} {
			pairs, err := readVDF(filepath.Join(lib.root, "steamapps", "appmanifest_"+spec.app+".acf"))
			if err != nil {
				continue
			}
			state, ok := vdfFind(pairs, "AppState")
			if !ok {
				continue
			}
			app, appOK := vdfFind(state.children, "appid")
			dir, dirOK := vdfFind(state.children, "installdir")
			if !appOK || app.value != spec.app || !dirOK || strings.ContainsAny(dir.value, "/\\") || pathSafe(dir.value) != nil {
				continue
			}
			inst, err := ValidateInstallation(filepath.Join(lib.root, "steamapps", "common", dir.value), spec.target)
			if err != nil {
				continue
			}
			key := string(inst.Target) + ":" + strings.ToLower(inst.Root)
			if !seenGames[key] {
				inst.SteamRoot = lib.steam
				found = append(found, inst)
				seenGames[key] = true
			}
		}
	}
	sort.Slice(found, func(i, j int) bool {
		return string(found[i].Target)+found[i].Root < string(found[j].Target)+found[j].Root
	})
	return found
}

func validHex(s string, size int) bool {
	if len(s) != size*2 {
		return false
	}
	_, err := hex.DecodeString(s)
	return err == nil
}

func validateFiles(files []ManifestFile) error {
	if len(files) == 0 || len(files) > 100000 {
		return errors.New("manifest must contain 1..100000 files")
	}
	seen := map[string]bool{}
	for _, f := range files {
		if err := pathSafe(f.Path); err != nil {
			return err
		}
		key := strings.ToLower(f.Path)
		if key == receiptName || strings.HasPrefix(key, stateDirectory+"/") || seen[key] {
			return fmt.Errorf("reserved or duplicate manifest path %q", f.Path)
		}
		if f.Size < 0 || !validHex(f.SHA256, sha256.Size) {
			return fmt.Errorf("invalid size or SHA-256 for %s", f.Path)
		}
		seen[key] = true
	}
	for name := range seen {
		for parent := path.Dir(name); parent != "."; parent = path.Dir(parent) {
			if seen[parent] {
				return fmt.Errorf("manifest file is also a directory: %s", parent)
			}
		}
	}
	return nil
}

func decodeJSONFile(name string, value any) error {
	if err := regularFile(name); err != nil {
		return err
	}
	f, err := os.Open(name)
	if err != nil {
		return err
	}
	defer f.Close()
	decoder := json.NewDecoder(io.LimitReader(f, 32<<20))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(value); err != nil {
		return fmt.Errorf("%s: %w", name, err)
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		return fmt.Errorf("trailing JSON in %s", name)
	}
	return nil
}

func LoadManifest(bundleRoot string) (BuildManifest, error) {
	var m BuildManifest
	if err := decodeJSONFile(filepath.Join(bundleRoot, "abaddon-build.json"), &m); err != nil {
		return m, err
	}
	if m.Schema != 1 || strings.TrimSpace(m.Project) == "" || strings.TrimSpace(m.Channel) == "" || !validHex(m.Revision, 20) {
		return m, errors.New("unsupported or incomplete build manifest metadata; schema 1 and full commit SHA required")
	}
	if err := pathSafe(m.PayloadRoot); err != nil {
		return m, err
	}
	if err := validateFiles(m.Files); err != nil {
		return m, err
	}
	payload := filepath.Join(bundleRoot, filepath.FromSlash(m.PayloadRoot))
	if err := noLinks(payload, false); err != nil {
		return m, err
	}
	info, err := os.Stat(payload)
	if err != nil || !info.IsDir() {
		return m, fmt.Errorf("payload directory is missing: %s", payload)
	}
	return m, nil
}

func checkFile(name string, expected ManifestFile, destination io.Writer) error {
	if err := regularFile(name); err != nil {
		return err
	}
	f, err := os.Open(name)
	if err != nil {
		return err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return err
	}
	if info.Size() != expected.Size {
		return fmt.Errorf("payload size mismatch: %s", expected.Path)
	}
	hash := sha256.New()
	writer := io.Writer(hash)
	if destination != nil {
		writer = io.MultiWriter(destination, hash)
	}
	count, err := io.Copy(writer, f)
	if err != nil {
		return err
	}
	if count != expected.Size || !strings.EqualFold(hex.EncodeToString(hash.Sum(nil)), expected.SHA256) {
		return fmt.Errorf("payload SHA-256 mismatch: %s", expected.Path)
	}
	return nil
}

// VerifyBundle checks the entire immutable payload, including files excluded by
// the selected target. Installation repeats the hash while staging each file.
func VerifyBundle(bundleRoot string) (BuildManifest, error) {
	m, err := LoadManifest(bundleRoot)
	if err != nil {
		return m, err
	}
	root := filepath.Join(bundleRoot, filepath.FromSlash(m.PayloadRoot))
	for _, f := range m.Files {
		if err := checkFile(filepath.Join(root, filepath.FromSlash(f.Path)), f, nil); err != nil {
			return m, err
		}
	}
	return m, nil
}

func targetFiles(files []ManifestFile, target Target) []ManifestFile {
	if target == TargetGMod {
		return files
	}
	var selected []ManifestFile
	for _, f := range files {
		for _, prefix := range []string{"maps/", "models/", "materials/"} {
			if strings.HasPrefix(f.Path, prefix) {
				selected = append(selected, f)
				break
			}
		}
	}
	return selected
}

func installationDestination(inst Installation) string {
	if inst.Target == TargetHL2 {
		return filepath.Join(inst.GameDir, "custom", "drmd")
	}
	return filepath.Join(inst.GameDir, "addons", "descent_scanner")
}

type installReceipt struct {
	Schema      int            `json:"schema"`
	Owner       string         `json:"owner"`
	Project     string         `json:"project"`
	Revision    string         `json:"revision"`
	Target      Target         `json:"target"`
	InstalledAt string         `json:"installed_at"`
	Files       []ManifestFile `json:"files"`
}

func copyRegular(source, destination string) error {
	if err := regularFile(source); err != nil {
		return err
	}
	in, err := os.Open(source)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(destination, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(out, in)
	closeErr := out.Close()
	if copyErr != nil {
		return copyErr
	}
	return closeErr
}

func copyTree(source, destination string) error {
	if err := noLinks(source, false); err != nil {
		return err
	}
	return filepath.WalkDir(source, func(name string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		if isLinkOrReparse(info) {
			return fmt.Errorf("existing installation contains a link/reparse point: %s", name)
		}
		rel, err := filepath.Rel(source, name)
		if err != nil {
			return err
		}
		target := filepath.Join(destination, rel)
		if entry.IsDir() {
			return os.MkdirAll(target, 0755)
		}
		if !info.Mode().IsRegular() {
			return fmt.Errorf("unsupported existing file type: %s", name)
		}
		return copyRegular(name, target)
	})
}

func writeAtomic(name string, data []byte, marker string) error {
	if err := noLinks(name, true); err != nil {
		return err
	}
	if old, err := os.ReadFile(name); err == nil {
		if marker != "" && !strings.HasPrefix(string(old), marker) {
			return fmt.Errorf("refusing to overwrite a file not owned by Abaddon Launcher: %s", name)
		}
	} else if !os.IsNotExist(err) {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(name), 0755); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(name), ".abaddon-write-")
	if err != nil {
		return err
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if _, err = f.Write(data); err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(tmp, name)
}

func writeJSON(name string, value any) error {
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	return writeAtomic(name, append(data, '\n'), "")
}

func openState(inst Installation) (string, func(), error) {
	state := filepath.Join(inst.GameDir, stateDirectory)
	if err := noLinks(state, true); err != nil {
		return "", nil, err
	}
	if err := os.MkdirAll(state, 0755); err != nil {
		return "", nil, err
	}
	journal := filepath.Join(state, "transaction.json")
	if _, err := os.Lstat(journal); err == nil {
		return "", nil, fmt.Errorf("interrupted installation: inspect %s; if the target is missing, restore the backup path recorded there. Keep backup/staging folders; after recovery and closing all launchers remove transaction.json and operation.lock", journal)
	} else if !os.IsNotExist(err) {
		return "", nil, err
	}
	lock := filepath.Join(state, "operation.lock")
	f, err := os.OpenFile(lock, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		if os.IsExist(err) {
			return "", nil, fmt.Errorf("another launcher operation is running or was interrupted; close other launcher instances. If none remain and transaction.json is absent, remove the stale lock %s and retry", lock)
		}
		return "", nil, err
	}
	_, err = fmt.Fprintf(f, "pid=%d\nstarted=%s\n", os.Getpid(), time.Now().UTC().Format(time.RFC3339Nano))
	closeErr := f.Close()
	if err != nil || closeErr != nil {
		os.Remove(lock)
		if err != nil {
			return "", nil, err
		}
		return "", nil, closeErr
	}
	return state, func() { _ = os.Remove(lock) }, nil
}

type transaction struct {
	Operation   string `json:"operation"`
	Target      Target `json:"target"`
	Destination string `json:"destination"`
	Replacement string `json:"replacement"`
	Backup      string `json:"backup"`
}

func commitDirectory(state, destination, replacement string, target Target, operation string) error {
	if err := noLinks(destination, true); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(destination), 0755); err != nil {
		return err
	}
	backup := ""
	if info, err := os.Lstat(destination); err == nil {
		if !info.IsDir() {
			return fmt.Errorf("installation destination is not a directory: %s", destination)
		}
		prefix := "backup-" + string(target) + "-" + time.Now().UTC().Format("20060102T150405.000000000") + "-"
		backup, err = os.MkdirTemp(state, prefix)
		if err != nil {
			return err
		}
		if err := os.Remove(backup); err != nil {
			return err
		}
	} else if !os.IsNotExist(err) {
		return err
	}
	journal := filepath.Join(state, "transaction.json")
	if err := writeJSON(journal, transaction{operation, target, destination, replacement, backup}); err != nil {
		return err
	}
	if backup != "" {
		if err := os.Rename(destination, backup); err != nil {
			_ = os.Remove(journal)
			return fmt.Errorf("cannot move existing installation to backup; installed files unchanged: %w", err)
		}
	}
	if err := os.Rename(replacement, destination); err != nil {
		if backup != "" {
			if restoreErr := os.Rename(backup, destination); restoreErr != nil {
				return fmt.Errorf("installation commit failed (%v) and automatic restoration failed (%v); original files remain at %s; recovery instructions are in %s", err, restoreErr, backup, journal)
			}
		}
		_ = os.Remove(journal)
		return fmt.Errorf("installation commit failed; previous installation restored: %w", err)
	}
	if err := os.Remove(journal); err != nil {
		return fmt.Errorf("files installed at %s, but transaction cleanup failed; remove %s after checking installation: %w", destination, journal, err)
	}
	return nil
}

func InstallBundle(bundleRoot string, inst Installation) (string, error) {
	validated, err := ValidateInstallation(inst.Root, inst.Target)
	if err != nil {
		return "", err
	}
	inst = validated
	m, err := VerifyBundle(bundleRoot)
	if err != nil {
		return "", err
	}
	selected := targetFiles(m.Files, inst.Target)
	if len(selected) == 0 {
		return "", fmt.Errorf("bundle has no payload for %s", inst.Target)
	}
	destination := installationDestination(inst)
	if err := noLinks(destination, true); err != nil {
		return "", err
	}
	state, unlock, err := openState(inst)
	if err != nil {
		return "", err
	}
	defer unlock()
	stage, err := os.MkdirTemp(state, "stage-"+string(inst.Target)+"-")
	if err != nil {
		return "", err
	}
	defer func() {
		// Never discard evidence/recovery content from an incomplete commit.
		if _, err := os.Lstat(filepath.Join(state, "transaction.json")); os.IsNotExist(err) {
			_ = os.RemoveAll(stage)
		}
	}()
	var previous installReceipt
	if info, err := os.Lstat(destination); err == nil {
		if !info.IsDir() {
			return "", fmt.Errorf("installation destination is not a directory: %s", destination)
		}
		if err := copyTree(destination, stage); err != nil {
			return "", err
		}
		name := filepath.Join(destination, receiptName)
		if _, err := os.Lstat(name); err == nil {
			if err := decodeJSONFile(name, &previous); err != nil {
				return "", fmt.Errorf("existing installation receipt is invalid; no files changed: %w", err)
			}
			if previous.Schema != 1 || previous.Owner != launcherOwner || previous.Project != m.Project || previous.Target != inst.Target || validateFiles(previous.Files) != nil {
				return "", errors.New("existing installation receipt is not owned by this project/target; no files changed")
			}
		} else if !os.IsNotExist(err) {
			return "", err
		}
	} else if !os.IsNotExist(err) {
		return "", err
	}
	current := map[string]string{}
	for _, f := range selected {
		current[strings.ToLower(f.Path)] = f.Path
	}
	for _, old := range previous.Files {
		if current[strings.ToLower(old.Path)] == old.Path {
			continue
		}
		name := filepath.Join(stage, filepath.FromSlash(old.Path))
		if err := os.Remove(name); err != nil && !os.IsNotExist(err) {
			return "", fmt.Errorf("cannot retire previously managed file without affecting unrelated files: %w", err)
		}
	}
	payload := filepath.Join(bundleRoot, filepath.FromSlash(m.PayloadRoot))
	for _, item := range selected {
		name := filepath.Join(stage, filepath.FromSlash(item.Path))
		if err := os.MkdirAll(filepath.Dir(name), 0755); err != nil {
			return "", err
		}
		if info, err := os.Lstat(name); err == nil && !info.Mode().IsRegular() {
			return "", fmt.Errorf("managed file conflicts with existing directory or special file: %s", item.Path)
		} else if err != nil && !os.IsNotExist(err) {
			return "", err
		}
		out, err := os.OpenFile(name, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0644)
		if err != nil {
			return "", err
		}
		copyErr := checkFile(filepath.Join(payload, filepath.FromSlash(item.Path)), item, out)
		closeErr := out.Close()
		if copyErr != nil {
			return "", copyErr
		}
		if closeErr != nil {
			return "", closeErr
		}
	}
	receipt := installReceipt{1, launcherOwner, m.Project, m.Revision, inst.Target, time.Now().UTC().Format(time.RFC3339), selected}
	if err := writeJSON(filepath.Join(stage, receiptName), receipt); err != nil {
		return "", err
	}
	if err := commitDirectory(state, destination, stage, inst.Target, "install"); err != nil {
		return "", err
	}
	return destination, nil
}

func RollbackInstallation(inst Installation) (string, error) {
	validated, err := ValidateInstallation(inst.Root, inst.Target)
	if err != nil {
		return "", err
	}
	inst = validated
	state, unlock, err := openState(inst)
	if err != nil {
		return "", err
	}
	defer unlock()
	entries, err := os.ReadDir(state)
	if err != nil {
		return "", err
	}
	var backups []string
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), "backup-"+string(inst.Target)+"-") {
			info, err := entry.Info()
			if err != nil {
				return "", err
			}
			if isLinkOrReparse(info) || !info.IsDir() {
				return "", fmt.Errorf("unsafe backup entry: %s", entry.Name())
			}
			backups = append(backups, filepath.Join(state, entry.Name()))
		}
	}
	if len(backups) == 0 {
		return "", errors.New("no previous installation backup is available")
	}
	sort.Strings(backups)
	backup := backups[len(backups)-1]
	if err := filepath.WalkDir(backup, func(name string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		if isLinkOrReparse(info) || (!info.IsDir() && !info.Mode().IsRegular()) {
			return fmt.Errorf("backup contains unsupported link or file: %s", name)
		}
		return nil
	}); err != nil {
		return "", err
	}
	destination := installationDestination(inst)
	if err := commitDirectory(state, destination, backup, inst.Target, "rollback"); err != nil {
		return "", err
	}
	return destination, nil
}

func ConfigureLaunch(inst Installation, opts LaunchOptions) (string, []string, error) {
	validated, err := ValidateInstallation(inst.Root, inst.Target)
	if err != nil {
		return "", nil, err
	}
	validated.SteamRoot = inst.SteamRoot
	inst = validated
	switch opts.Map {
	case "", "d6_city17_drain", "d6_reactor_escape", "d6_relay_vault":
	default:
		return "", nil, fmt.Errorf("unsupported map %q", opts.Map)
	}
	if opts.Map != "" {
		mapFile := filepath.Join(installationDestination(inst), "maps", opts.Map+".bsp")
		if err := regularFile(mapFile); err != nil {
			return "", nil, fmt.Errorf("карта %s не установлена; сначала установите пакет Abaddon: %w", opts.Map, err)
		}
	}
	if (opts.Width == 0) != (opts.Height == 0) || opts.Width < 0 || opts.Height < 0 ||
		(opts.Width != 0 && (opts.Width < 640 || opts.Width > 16384 || opts.Height < 480 || opts.Height > 16384)) {
		return "", nil, errors.New("resolution must be omitted or between 640x480 and 16384x16384")
	}
	profiles := map[string]string{
		"balanced": "r_shadows 1\nr_shadowrendertotexture 1\nr_flashlightdepthtexture 1\nr_flashlightdepthres 1024\nmat_bumpmap 1\nmat_specular 1\nmat_forceaniso 8\n",
		"high":     "r_shadows 1\nr_shadowrendertotexture 1\nr_flashlightdepthtexture 1\nr_flashlightdepthres 2048\nmat_bumpmap 1\nmat_specular 1\nmat_forceaniso 16\n",
		"low":      "r_shadows 1\nr_shadowrendertotexture 0\nr_flashlightdepthtexture 0\nr_flashlightdepthres 512\nmat_bumpmap 1\nmat_specular 0\nmat_forceaniso 2\n",
	}
	profile := opts.Graphics
	if profile == "" {
		profile = "default"
	}
	if profile != "default" {
		commands, ok := profiles[profile]
		if !ok {
			return "", nil, fmt.Errorf("unknown graphics profile %q", profile)
		}
		cfg := configMarker + "// Source lighting/shadow settings; not a PBR shader or a reset of previous engine settings.\n" + commands
		if err := writeAtomic(filepath.Join(inst.GameDir, "cfg", configName), []byte(cfg), configMarker); err != nil {
			return "", nil, err
		}
	}
	executable := inst.Executable
	var args []string
	steam := filepath.Join(inst.SteamRoot, "steam.exe")
	if inst.SteamRoot != "" && regularFile(steam) == nil {
		executable = steam
		app := "4000"
		if inst.Target == TargetHL2 {
			app = "220"
		}
		args = append(args, "-applaunch", app)
	} else {
		game := "garrysmod"
		if inst.Target == TargetHL2 {
			game = "hl2"
		}
		args = append(args, "-game", game)
	}
	args = append(args, "-novid")
	if opts.Windowed {
		args = append(args, "-windowed")
	} else {
		args = append(args, "-fullscreen")
	}
	if opts.Width != 0 {
		args = append(args, "-w", strconv.Itoa(opts.Width), "-h", strconv.Itoa(opts.Height))
	}
	if opts.Console {
		args = append(args, "-console")
	}
	if inst.Target == TargetGMod {
		args = append(args, "+gamemode", "sandbox")
	}
	if profile != "default" {
		args = append(args, "+exec", configName)
	}
	if opts.Map != "" {
		args = append(args, "+map", opts.Map)
	}
	return executable, args, nil
}
