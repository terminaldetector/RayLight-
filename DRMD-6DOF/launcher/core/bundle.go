package core

import (
	"archive/zip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const bundleProject = "raylight-abaddon"
const bundleName = "abaddon-build.json"
const maxManifestSize = 4 << 20
const maxPayloadSize = 1 << 30

type BuildInfo struct {
	Channel  string  `json:"channel"`
	Revision string  `json:"revision"`
	Status   string  `json:"status"`
	Target   Profile `json:"target"`
}

type bundleFile struct {
	SHA256 string `json:"sha256"`
	Size   uint64 `json:"size"`
}

type bundleTarget struct {
	Status   string          `json:"status"`
	Features map[string]bool `json:"features"`
}

type bundleManifest struct {
	Project  string                   `json:"project"`
	Channel  string                   `json:"channel"`
	Revision string                   `json:"revision"`
	Targets  map[Profile]bundleTarget `json:"targets"`
	Files    map[string]bundleFile    `json:"files"`
}

type installedManifest struct {
	Project string `json:"project"`
	BuildInfo
	Features map[string]bool `json:"features"`
}

type bundle struct {
	*zip.ReadCloser
	manifest bundleManifest
	items    map[string]*zip.File
}

func readJSONFile(reader io.Reader, target any) error {
	data, err := io.ReadAll(io.LimitReader(reader, maxManifestSize+1))
	if err != nil {
		return err
	}
	if len(data) > maxManifestSize {
		return fmt.Errorf("Манифест пакета слишком велик")
	}
	return json.Unmarshal(data, target)
}

func hexSize(value string, size int) bool {
	data, err := hex.DecodeString(value)
	return err == nil && len(data) == size
}

func safeAssetPath(name string) bool {
	if name == "." || !fs.ValidPath(name) || strings.ContainsAny(name, "\\:<>|\"?*") {
		return false
	}
	for _, part := range strings.Split(name, "/") {
		if strings.HasSuffix(part, ".") || strings.HasSuffix(part, " ") {
			return false
		}
		device := strings.ToUpper(strings.SplitN(part, ".", 2)[0])
		switch device {
		case "CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$":
			return false
		}
		if len(device) == 4 && (strings.HasPrefix(device, "COM") || strings.HasPrefix(device, "LPT")) &&
			device[3] >= '0' && device[3] <= '9' {
			return false
		}
		for _, char := range part {
			if char < 32 {
				return false
			}
		}
	}
	return true
}

func openBundle(path string) (*bundle, error) {
	reader, err := zip.OpenReader(path)
	if err != nil {
		return nil, err
	}
	result := &bundle{ReadCloser: reader, items: make(map[string]*zip.File)}
	ok := false
	defer func() {
		if !ok {
			reader.Close()
		}
	}()
	names := make(map[string]bool)
	for _, item := range reader.File {
		name := item.Name
		if item.FileInfo().IsDir() {
			continue
		}
		lower := strings.ToLower(name)
		if !safeAssetPath(name) || !item.Mode().IsRegular() || names[lower] {
			return nil, fmt.Errorf("Недопустимый или повторяющийся путь в пакете: %q", name)
		}
		names[lower] = true
		result.items[name] = item
	}
	manifest := result.items["manifest.json"]
	if manifest == nil {
		return nil, fmt.Errorf("В ZIP отсутствует manifest.json")
	}
	stream, err := manifest.Open()
	if err != nil {
		return nil, err
	}
	err = readJSONFile(stream, &result.manifest)
	stream.Close()
	if err != nil {
		return nil, err
	}
	meta := &result.manifest
	if meta.Project != bundleProject || !hexSize(meta.Revision, 20) ||
		(meta.Channel != "dev" && meta.Channel != "release") ||
		len(meta.Files) == 0 || len(meta.Files)+1 != len(result.items) {
		return nil, fmt.Errorf("Неверный манифест сборки Abaddon")
	}
	var total uint64
	for name, entry := range meta.Files {
		item := result.items["descent_scanner/"+name]
		if !safeAssetPath(name) || strings.EqualFold(name, bundleName) || item == nil ||
			!hexSize(entry.SHA256, sha256.Size) || entry.Size != item.UncompressedSize64 ||
			entry.Size > maxPayloadSize-total {
			return nil, fmt.Errorf("Размер или запись файла %q расходится с манифестом", name)
		}
		total += entry.Size
	}
	ok = true
	return result, nil
}

func (archive *bundle) info(profile Profile) (installedManifest, error) {
	target, valid := archive.manifest.Targets[profile]
	if !valid || target.Status == "" || (profile != GMod && profile != HL2Content) {
		return installedManifest{}, fmt.Errorf("Пакет не содержит файлы для выбранного профиля")
	}
	return installedManifest{
		Project: bundleProject,
		BuildInfo: BuildInfo{Channel: archive.manifest.Channel, Revision: archive.manifest.Revision,
			Status: target.Status, Target: profile},
		Features: target.Features,
	}, nil
}

func BundleInfo(path string, profile Profile) (BuildInfo, error) {
	archive, err := openBundle(path)
	if err != nil {
		return BuildInfo{}, err
	}
	defer archive.Close()
	info, err := archive.info(profile)
	return info.BuildInfo, err
}

func installLocation(cfg Config, profile Profile) (destination, work string, err error) {
	found := Detect(cfg)
	switch profile {
	case GMod:
		if found.GModPath == "" {
			return "", "", fmt.Errorf("Укажите папку установки Garry’s Mod")
		}
		game := filepath.Join(found.GModPath, "garrysmod")
		destination = filepath.Join(game, "addons", "descent_scanner")
		if current := gmodContent(found.GModPath); current != "" && !samePath(current, destination) {
			return "", "", fmt.Errorf("Abaddon уже смонтирован из другой папки: %s", current)
		}
		return destination, filepath.Join(game, "abaddon_launcher"), nil
	case HL2Content:
		if found.ContentPath == "" {
			return "", "", fmt.Errorf("Укажите папку установки Half-Life 2")
		}
		root := filepath.Join(found.ContentPath, "hl2")
		destination = contentInstallPath(found.ContentPath)
		legacy := filepath.Join(root, "custom", "drmd", "maps", "d6_city17_drain.bsp")
		if isFile(legacy) {
			return "", "", fmt.Errorf("Карты Abaddon уже смонтированы из hl2/custom/drmd")
		}
		return destination, filepath.Join(root, "abaddon_launcher"), nil
	default:
		return "", "", fmt.Errorf("Нативная лаборатория устанавливается из отдельной Windows-сборки SDK")
	}
}

func readInstalled(destination string, profile Profile) (installedManifest, error) {
	var data installedManifest
	file, err := os.Open(filepath.Join(destination, bundleName))
	if err != nil {
		return data, err
	}
	defer file.Close()
	err = readJSONFile(file, &data)
	if err == nil && (data.Project != bundleProject || data.Target != profile ||
		!hexSize(data.Revision, 20) || (data.Channel != "dev" && data.Channel != "release")) {
		err = fmt.Errorf("Манифест установленного пакета недействителен")
	}
	return data, err
}

func InstalledBuild(cfg Config, profile Profile) (BuildInfo, error) {
	destination, _, err := installLocation(cfg, profile)
	if err != nil {
		return BuildInfo{}, err
	}
	info, err := readInstalled(destination, profile)
	return info.BuildInfo, err
}

func PackageDestination(cfg Config, profile Profile) (string, error) {
	destination, _, err := installLocation(cfg, profile)
	return destination, err
}

func inTarget(profile Profile, name string) bool {
	if profile == GMod {
		return true
	}
	folder, _, _ := strings.Cut(name, "/")
	extension := strings.ToLower(filepath.Ext(name))
	switch folder {
	case "maps":
		return extension == ".bsp"
	case "models":
		return extension == ".mdl" || extension == ".vtx" || extension == ".vvd" || extension == ".phy"
	case "materials":
		return extension == ".vmt" || extension == ".vtf"
	}
	return false
}

func extractAsset(item *zip.File, entry bundleFile, target string) error {
	source, err := item.Open()
	if err != nil {
		return err
	}
	defer source.Close()
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return err
	}
	destination, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
	if err != nil {
		return err
	}
	hash := sha256.New()
	count, copyErr := io.Copy(io.MultiWriter(destination, hash), io.LimitReader(source, int64(entry.Size)+1))
	closeErr := destination.Close()
	if copyErr != nil {
		return copyErr
	}
	if closeErr != nil {
		return closeErr
	}
	if uint64(count) != entry.Size || !strings.EqualFold(hex.EncodeToString(hash.Sum(nil)), entry.SHA256) {
		return fmt.Errorf("Не совпадает SHA-256 файла %s", item.Name)
	}
	return nil
}

func isAbaddonPayload(path string, profile Profile) bool {
	if !isFile(filepath.Join(path, "maps", "d6_city17_drain.bsp")) {
		return false
	}
	if profile == GMod {
		return isFile(filepath.Join(path, "lua", "autorun", "d6_autoload.lua"))
	}
	return hasStoryResources(path)
}

func filesMatch(manifest bundleManifest, root string, profile Profile) bool {
	for name, entry := range manifest.Files {
		if !inTarget(profile, name) {
			continue
		}
		file, err := os.Open(filepath.Join(root, filepath.FromSlash(name)))
		if err != nil {
			return false
		}
		hash := sha256.New()
		size, err := io.Copy(hash, io.LimitReader(file, int64(entry.Size)+1))
		file.Close()
		if err != nil || uint64(size) != entry.Size || !strings.EqualFold(hex.EncodeToString(hash.Sum(nil)), entry.SHA256) {
			return false
		}
	}
	return true
}

func swapPayload(destination, incoming, work string, profile Profile) error {
	if err := os.MkdirAll(filepath.Dir(destination), 0o755); err != nil {
		return err
	}
	var backup string
	if entry, err := os.Lstat(destination); err == nil {
		if !entry.IsDir() || !isAbaddonPayload(destination, profile) {
			return fmt.Errorf("Папка назначения занята другим содержимым: %s", destination)
		}
		folder, err := os.MkdirTemp(work, fmt.Sprintf("previous-%020d-", time.Now().UnixNano()))
		if err != nil {
			return err
		}
		backup = filepath.Join(folder, "payload")
		if err = os.Rename(destination, backup); err != nil {
			_ = os.Remove(folder)
			return err
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if err := os.Rename(incoming, destination); err != nil {
		if backup != "" {
			if restoreErr := os.Rename(backup, destination); restoreErr != nil {
				return fmt.Errorf("Не удалось заменить сборку. Резервная копия находится в %s: %w", backup,
					errors.Join(err, restoreErr))
			}
			_ = os.Remove(filepath.Dir(backup))
		}
		return err
	}
	return nil
}

func InstallBundle(cfg Config, profile Profile, zipPath string) (BuildInfo, error) {
	archive, err := openBundle(zipPath)
	if err != nil {
		return BuildInfo{}, err
	}
	defer archive.Close()
	info, err := archive.info(profile)
	if err != nil {
		return BuildInfo{}, err
	}
	destination, work, err := installLocation(cfg, profile)
	if err != nil {
		return BuildInfo{}, err
	}
	unlock, err := lockInstall(work)
	if err != nil {
		return BuildInfo{}, err
	}
	defer unlock()
	staging, err := os.MkdirTemp(work, ".staging-")
	if err != nil {
		return BuildInfo{}, err
	}
	defer os.RemoveAll(staging)
	for name, entry := range archive.manifest.Files {
		if !inTarget(profile, name) {
			continue
		}
		target := filepath.Join(staging, filepath.FromSlash(name))
		if err = extractAsset(archive.items["descent_scanner/"+name], entry, target); err != nil {
			return BuildInfo{}, err
		}
	}
	if !isAbaddonPayload(staging, profile) {
		return BuildInfo{}, fmt.Errorf("В пакете отсутствуют обязательные карты или файлы аддона")
	}
	meta, err := json.MarshalIndent(info, "", "  ")
	if err != nil {
		return BuildInfo{}, err
	}
	if err := os.WriteFile(filepath.Join(staging, bundleName), append(meta, '\n'), 0o644); err != nil {
		return BuildInfo{}, err
	}
	if current, err := readInstalled(destination, profile); err == nil &&
		current.BuildInfo == info.BuildInfo && filesMatch(archive.manifest, destination, profile) {
		return info.BuildInfo, nil
	}
	if err := swapPayload(destination, staging, work, profile); err != nil {
		return BuildInfo{}, err
	}
	return info.BuildInfo, nil
}

func RollbackBundle(cfg Config, profile Profile) (BuildInfo, error) {
	destination, work, err := installLocation(cfg, profile)
	if err != nil {
		return BuildInfo{}, err
	}
	unlock, err := lockInstall(work)
	if err != nil {
		return BuildInfo{}, err
	}
	defer unlock()
	folders, err := os.ReadDir(work)
	if err != nil {
		return BuildInfo{}, err
	}
	for index := len(folders) - 1; index >= 0; index-- {
		entry := folders[index]
		if !entry.IsDir() || !strings.HasPrefix(entry.Name(), "previous-") {
			continue
		}
		parent := filepath.Join(work, entry.Name())
		backup := filepath.Join(parent, "payload")
		if !isAbaddonPayload(backup, profile) {
			continue
		}
		info, _ := readInstalled(backup, profile)
		if err := swapPayload(destination, backup, work, profile); err != nil {
			return BuildInfo{}, err
		}
		_ = os.Remove(parent)
		return info.BuildInfo, nil
	}
	return BuildInfo{}, fmt.Errorf("Для этой установки ещё нет резервной копии")
}
