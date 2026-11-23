package core

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

type Profile string

const (
	GMod       Profile = "gmod"
	HL2        Profile = "hl2"
	HL2Content Profile = "hl2-content"
)

type Options struct {
	Map         string `json:"map"`
	Display     string `json:"display"`
	Width       int    `json:"width"`
	Height      int    `json:"height"`
	Console     bool   `json:"console"`
	SkipIntro   bool   `json:"skip_intro"`
	DebugLog    bool   `json:"debug_log"`
	GameProfile string `json:"game_profile,omitempty"`
}

type Config struct {
	Selected    Profile `json:"selected"`
	SteamPath   string  `json:"steam_path,omitempty"`
	GModPath    string  `json:"gmod_path,omitempty"`
	SDKPath     string  `json:"sdk_path,omitempty"`
	NativePath  string  `json:"native_path,omitempty"`
	ContentPath string  `json:"content_path,omitempty"`
	GMod        Options `json:"gmod"`
	HL2         Options `json:"hl2"`
	HL2Content  Options `json:"hl2_content"`
}

func DefaultConfig() Config {
	video := Options{Display: "windowed", Width: 1600, Height: 900, Console: true, SkipIntro: true}
	gmod, hl2, content := video, video, video
	gmod.Map, gmod.GameProfile = "d6_city17_drain", "auto"
	hl2.Map = "d6_native_flightlab"
	content.Map = "d6_city17_drain"
	return Config{Selected: GMod, GMod: gmod, HL2: hl2, HL2Content: content}
}

func configPath() (string, error) {
	base := os.Getenv("LOCALAPPDATA")
	if base == "" {
		var err error
		base, err = os.UserConfigDir()
		if err != nil {
			return "", fmt.Errorf("Каталог настроек недоступен: %w", err)
		}
	}
	return filepath.Join(base, "HalfLifeAbaddon", "launcher.json"), nil
}

func LoadConfig() (Config, error) {
	cfg := DefaultConfig()
	path, err := configPath()
	if err != nil {
		return cfg, err
	}
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return cfg, nil
	}
	if err != nil {
		return cfg, fmt.Errorf("Не удалось прочитать настройки: %w", err)
	}
	if err = json.Unmarshal(data, &cfg); err != nil {
		return DefaultConfig(), fmt.Errorf("Повреждён файл настроек %s: %w", path, err)
	}
	if cfg.Selected != GMod && cfg.Selected != HL2 && cfg.Selected != HL2Content {
		cfg.Selected = GMod
	}
	return cfg, nil
}

func SaveConfig(cfg Config) error {
	path, err := configPath()
	if err != nil {
		return err
	}
	if err = saveConfigFile(path, cfg); err != nil {
		return fmt.Errorf("Не удалось сохранить настройки: %w", err)
	}
	return nil
}

func saveConfigFile(path string, cfg Config) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	staged, err := os.CreateTemp(dir, "launcher-*.tmp")
	if err != nil {
		return err
	}
	defer os.Remove(staged.Name())

	encoder := json.NewEncoder(staged)
	encoder.SetIndent("", "  ")
	if err = encoder.Encode(cfg); err == nil {
		err = staged.Sync()
	}
	closeErr := staged.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(staged.Name(), path)
}
